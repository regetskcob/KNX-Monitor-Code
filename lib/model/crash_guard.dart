import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/storage.dart';
import 'app_log.dart';

/// Detects an unexpected termination of the app (public issue #4): while it runs
/// in the foreground, a marker sits in the settings; the next start only finds it
/// if the app did not exit cleanly. The latest log lines are written to disk
/// regularly, because otherwise they would vanish with the process.
///
/// Nothing is sent. The notice leads to the existing diagnostic package, which
/// the user reviews and shares themselves; the lines of the last run then appear
/// scrubbed in its log. The system terminates apps in the background all the
/// time, so only the foreground counts. In the browser there is no clean end of
/// a tab; there the server reports its own restarts.
class CrashGuard extends ChangeNotifier {
  CrashGuard({AppLog? log, AppStorage? storage, this.flushInterval = const Duration(seconds: 15)})
    : _log = log ?? AppLog.instance,
      _storageOverride = storage;

  static final instance = CrashGuard();

  static const _runningKey = 'crash_running';
  static const logFile = 'crash_log.txt';

  /// This many lines of the last run go into the new log.
  static const keepLines = 100;

  final AppLog _log;
  final AppStorage? _storageOverride;
  final Duration flushInterval;

  AppStorage get _storage => _storageOverride ?? AppStorage.instance;

  SharedPreferences? _prefs;
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  int _written = -1;
  bool _active = false;
  DateTime? _touched;

  /// When the last run was last in the foreground, if it ended unexpectedly;
  /// otherwise `null`, or after [dismiss].
  DateTime? get unclean => _unclean;
  DateTime? _unclean;

  /// Starts monitoring. Must never prevent the app from starting: everything is
  /// caught, without a notice if in doubt.
  ///
  /// Not in debug mode, except with [force]: there every run ends abruptly.
  Future<void> start({bool force = false}) async {
    if (kIsWeb || (kDebugMode && !force)) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      final running = _prefs!.getInt(_runningKey);
      if (running != null) {
        _unclean = DateTime.fromMillisecondsSinceEpoch(running);
        try {
          await _adoptPreviousLog();
        } on Object catch (e) {
          debugPrint('Absturzerkennung: Log nicht lesbar: $e');
        }
        notifyListeners();
      }
      await _setRunning(true);
      _timer = Timer.periodic(flushInterval, (_) => unawaited(flush()));
      _lifecycle = AppLifecycleListener(onStateChange: handleState, onExitRequested: _exitRequested);
    } on Object catch (e) {
      debugPrint('Absturzerkennung: $e');
    }
  }

  Future<AppExitResponse> _exitRequested() async {
    await _setRunning(false);
    return AppExitResponse.exit;
  }

  Future<void> _adoptPreviousLog() async {
    final text = await _storage.read(logFile);
    if (text == null || text.isEmpty) return;
    final lines = text.trimRight().split('\n');
    final start = lines.length > keepLines ? lines.length - keepLines : 0;
    _log.add('--- letzter Lauf vor dem unerwarteten Ende ---');
    for (final line in lines.sublist(start)) {
      _log.add(line);
    }
    _log.add('--- dieser Lauf ---');
  }

  /// The marker only runs in the foreground; ending in the background is normal.
  @visibleForTesting
  void handleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_setRunning(true));
      case AppLifecycleState.hidden || AppLifecycleState.paused || AppLifecycleState.detached:
        unawaited(flush());
        unawaited(_setRunning(false));
      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<void> _setRunning(bool running) async {
    if (running == _active && running) return;
    _active = running;
    try {
      if (running) {
        await _prefs?.setInt(_runningKey, DateTime.now().millisecondsSinceEpoch);
      } else {
        await _prefs?.remove(_runningKey);
      }
    } on Object catch (e) {
      debugPrint('Absturzerkennung: $e');
    }
  }

  /// Writes the latest lines to disk when new ones have arrived.
  Future<void> flush() async {
    // At most once per minute: the notice says when the app last ran.
    final now = DateTime.now();
    if (_active && (_touched == null || now.difference(_touched!) >= const Duration(minutes: 1))) {
      _touched = now;
      try {
        await _prefs?.setInt(_runningKey, now.millisecondsSinceEpoch);
      } on Object catch (e) {
        debugPrint('Absturzerkennung: $e');
      }
    }
    final lines = _log.lines;
    final stamp = lines.isEmpty ? 0 : lines.last.hashCode ^ lines.length;
    if (stamp == _written) return;
    _written = stamp;
    try {
      await _storage.write(logFile, lines.join('\n'));
    } on Object catch (e) {
      debugPrint('Absturzerkennung: Log nicht geschrieben: $e');
    }
  }

  /// Notice handled.
  void dismiss() {
    _unclean = null;
    notifyListeners();
  }

  /// On shutdown in tests.
  @visibleForTesting
  Future<void> stop() async {
    _timer?.cancel();
    _lifecycle?.dispose();
    _lifecycle = null;
  }
}
