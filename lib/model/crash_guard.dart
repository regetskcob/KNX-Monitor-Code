import 'dart:async';
import 'dart:convert';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/process_info.dart' as process;
import '../platform/storage.dart';
import 'app_log.dart';

/// Tells whether process `pid` still runs this app: `true`, `false`, or `null`
/// when it cannot be told ([process.processAlive]).
typedef ProcessProbe = Future<bool?> Function(int pid);

/// Detects an unexpected termination of the app (public issue #4): while it runs
/// in the foreground, a marker file of this process lies in the app folder; the
/// next start only finds it if the app did not exit cleanly. The latest log
/// lines are written to disk regularly, because otherwise they would vanish
/// with the process.
///
/// Several instances on one computer (macOS, Windows, Linux) share the folder:
/// each has its own marker (`crash/running-<pid>.json`) and log
/// (`crash/log-<pid>.txt`), and a start only evaluates markers of processes that
/// no longer run. Files rather than the settings: on Windows and Linux every
/// instance rewrites the whole settings file from its own copy and would drop
/// the other's marker.
///
/// Limits: a process counts as running if a process with its id runs the same
/// executable (`ps`, `tasklist`), which rules out a reused id of another
/// program. Where that cannot be checked (sandbox, missing tool) the marker
/// counts as dead, as before; two instances may then give a wrong notice. On
/// iOS and Android there is only one process, so any foreign marker is dead.
///
/// Nothing is sent. The notice leads to the existing diagnostic package, which
/// the user reviews and shares themselves; the lines of the last run then appear
/// scrubbed in its log. The system terminates apps in the background all the
/// time, so only the foreground counts. In the browser there is no clean end of
/// a tab; there the server reports its own restarts.
class CrashGuard extends ChangeNotifier {
  CrashGuard({
    AppLog? log,
    AppStorage? storage,
    this.flushInterval = const Duration(seconds: 15),
    int? pid,
    ProcessProbe? alive,
    bool? singleProcess,
    DateTime Function()? now,
  }) : _log = log ?? AppLog.instance,
       _storageOverride = storage,
       pid = pid ?? process.currentPid ?? 0,
       _alive = alive ?? ((id) => process.processAlive(id, process.executableName)),
       _singleProcess =
           singleProcess ?? const {TargetPlatform.iOS, TargetPlatform.android}.contains(defaultTargetPlatform),
       _now = now ?? DateTime.now;

  static final instance = CrashGuard();

  static const dir = 'crash';

  /// Before 1.9.10: one marker in the settings and one log for all instances.
  static const legacyKey = 'crash_running';
  static const legacyLogFile = 'crash_log.txt';

  /// Unexpected ends in a row, across starts.
  static const streakFile = '$dir/streak.json';

  /// This many lines of the last run go into the new log.
  static const keepLines = 100;

  /// From this many unexpected ends in a row, the notice suggests starting
  /// without connecting automatically ([holdAutoConnect]).
  static const streakNotice = 3;

  /// A run that stays in the foreground this long ends the streak.
  static const stableAfter = Duration(minutes: 5);

  /// An end this soon after the connection counts as "shortly after connecting".
  static const afterConnect = Duration(minutes: 3);

  final AppLog _log;
  final AppStorage? _storageOverride;
  final Duration flushInterval;

  /// Id of this process; names its marker and log.
  final int pid;
  final ProcessProbe _alive;
  final bool _singleProcess;
  final DateTime Function() _now;

  AppStorage get _storage => _storageOverride ?? AppStorage.instance;

  String get markerFile => '$dir/running-$pid.json';
  String get logFile => '$dir/log-$pid.txt';

  static final _markerName = RegExp(r'^running-(\d+)\.json$');
  static final _logName = RegExp(r'^log-(\d+)\.txt$');

  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  int _written = -1;
  bool _active = false;
  bool _started = false;
  DateTime? _touched;
  DateTime? _activeSince;
  DateTime? _connected;
  bool _streakOpen = false;

  /// When the last run was last in the foreground, if it ended unexpectedly;
  /// otherwise `null`, or after [dismiss].
  DateTime? get unclean => _unclean;
  DateTime? _unclean;

  /// Unexpected ends in a row, including the one of [unclean]; 0 without one.
  int get consecutive => _consecutive;
  int _consecutive = 0;

  /// Whether every end of the streak came shortly after connecting (the
  /// connection was set up at most [afterConnect] before the last sign of life).
  bool get afterConnecting => _afterConnecting;
  bool _afterConnecting = false;

  /// The notice stands after several ends in a row: the connect screen does not
  /// open the monitor by itself until the user chose.
  bool get holdAutoConnect => _unclean != null && _consecutive >= streakNotice;

  /// Starts monitoring. Must never prevent the app from starting: everything is
  /// caught, without a notice if in doubt.
  ///
  /// Not in debug mode, except with [force]: there every run ends abruptly.
  Future<void> start({bool force = false}) async {
    if (kIsWeb || (kDebugMode && !force) || _started) return;
    _started = true;
    try {
      await _evaluate();
    } on Object catch (e) {
      debugPrint('Absturzerkennung: $e');
    }
    try {
      await _setRunning(true);
      _timer = Timer.periodic(flushInterval, (_) => unawaited(flush()));
      _lifecycle = AppLifecycleListener(onStateChange: handleState, onExitRequested: _exitRequested);
    } on Object catch (e) {
      debugPrint('Absturzerkennung: $e');
    }
    if (_unclean != null) notifyListeners();
  }

  /// Markers of processes that no longer run: the latest one is the notice.
  /// Afterwards their files are gone, as are logs of processes that ended
  /// cleanly.
  Future<void> _evaluate() async {
    final files = await _storage.list(dir);
    final alive = <int, bool>{};
    Future<bool> running(int id) async {
      if (id == pid || _singleProcess) return false;
      return alive[id] ??= (await _alive(id)) ?? false;
    }

    final dead = <({DateTime seen, DateTime? connected, String marker, String log})>[];
    var othersAlive = false;
    for (final f in files) {
      final id = int.tryParse(_markerName.firstMatch(f.name)?.group(1) ?? '');
      if (id == null) continue;
      if (await running(id)) {
        othersAlive = true;
        continue;
      }
      final marker = '$dir/${f.name}';
      Map<String, Object?> data;
      try {
        data = (jsonDecode(await _storage.read(marker) ?? '') as Map).cast<String, Object?>();
      } on Object {
        // Cut off while writing: still an unclean end, but without a time.
        data = const {};
      }
      final t = data['t'];
      final c = data['connected'];
      dead.add((
        seen: t is int ? DateTime.fromMillisecondsSinceEpoch(t) : _now(),
        connected: c is int ? DateTime.fromMillisecondsSinceEpoch(c) : null,
        marker: marker,
        log: '$dir/log-$id.txt',
      ));
    }
    // Older version: one marker in the settings for all instances.
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getInt(legacyKey) case final t?) {
        dead.add((seen: DateTime.fromMillisecondsSinceEpoch(t), connected: null, marker: '', log: legacyLogFile));
        await prefs.remove(legacyKey);
      }
    } on Object catch (e) {
      debugPrint('Absturzerkennung: alte Marke nicht lesbar: $e');
    }

    if (dead.isNotEmpty) {
      dead.sort((a, b) => a.seen.compareTo(b.seen));
      final last = dead.last;
      _unclean = last.seen;
      try {
        await _adoptPreviousLog(last.log);
      } on Object catch (e) {
        debugPrint('Absturzerkennung: Log nicht lesbar: $e');
      }
      final sinceConnect = last.connected == null ? null : last.seen.difference(last.connected!);
      await _countStreak(sinceConnect != null && !sinceConnect.isNegative && sinceConnect <= afterConnect);
      for (final d in dead) {
        await _delete(d.marker);
        await _delete(d.log);
      }
    } else if (!othersAlive) {
      // The last run ended without a crash. While another instance still
      // runs, its streak stays: it may yet end unexpectedly.
      await _delete(streakFile);
    }

    // Logs of processes that ended cleanly or in the background.
    final markers = {
      for (final f in files)
        if (_markerName.firstMatch(f.name)?.group(1) case final id?) int.parse(id),
    };
    for (final f in files) {
      final id = int.tryParse(_logName.firstMatch(f.name)?.group(1) ?? '');
      if (id == null || markers.contains(id) || await running(id)) continue;
      await _delete('$dir/${f.name}');
    }
    await _delete(legacyLogFile);
  }

  Future<void> _countStreak(bool soon) async {
    var count = 0;
    var allSoon = true;
    try {
      final data = (jsonDecode(await _storage.read(streakFile) ?? '{}') as Map).cast<String, Object?>();
      count = (data['count'] as num?)?.toInt() ?? 0;
      allSoon = count == 0 || data['afterConnect'] == true;
    } on Object {
      // Start a new streak.
    }
    _consecutive = count + 1;
    _afterConnecting = allSoon && soon;
    _streakOpen = true;
    try {
      await _storage.write(streakFile, jsonEncode({'count': _consecutive, 'afterConnect': _afterConnecting}));
    } on Object catch (e) {
      debugPrint('Absturzerkennung: $e');
    }
  }

  /// The streak ends with a clean exit or a run that held [stableAfter].
  Future<void> _endStreak() async {
    if (!_streakOpen) return;
    _streakOpen = false;
    await _delete(streakFile);
  }

  Future<void> _delete(String path) async {
    if (path.isEmpty) return;
    try {
      await _storage.delete(path);
    } on Object catch (e) {
      debugPrint('Absturzerkennung: $path nicht gelöscht: $e');
    }
  }

  Future<AppExitResponse> _exitRequested() async {
    await _setRunning(false);
    await _endStreak();
    return AppExitResponse.exit;
  }

  Future<void> _adoptPreviousLog(String path) async {
    final text = await _storage.read(path);
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
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        unawaited(flush());
        unawaited(_setRunning(false));
      case AppLifecycleState.detached:
        unawaited(flush());
        unawaited(_setRunning(false));
        unawaited(_endStreak());
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// A connection to the bus is up (gateway, box or add-on): an end shortly
  /// after counts as "shortly after connecting".
  void connected() {
    if (!_started) return;
    _connected = _now();
    if (_active) unawaited(_writeMarker());
  }

  /// Marker writes and deletes run one after another: lifecycle callbacks do
  /// not wait for each other, and a write still in flight after the delete
  /// would leave a foreground marker behind for a run in the background.
  Future<void> _markerOps = Future.value();

  Future<void> _serial(Future<void> Function() op) => _markerOps = _markerOps.then((_) => op()).catchError((Object e) {
    debugPrint('Absturzerkennung: $e');
  });

  Future<void> _setRunning(bool running) {
    if (running == _active && running) return _markerOps;
    _active = running;
    if (running) {
      _activeSince = _now();
      return _writeMarker();
    }
    _activeSince = null;
    return _serial(() async {
      // Back in the foreground meanwhile: the marker stays.
      if (!_active) await _delete(markerFile);
    });
  }

  Future<void> _writeMarker() => _serial(() async {
    // Left the foreground meanwhile: no marker.
    if (!_active) return;
    final now = _now();
    _touched = now;
    try {
      await _storage.write(
        markerFile,
        jsonEncode({'t': now.millisecondsSinceEpoch, 'connected': ?_connected?.millisecondsSinceEpoch}),
      );
    } on Object catch (e) {
      debugPrint('Absturzerkennung: $e');
    }
  });

  /// Writes the latest lines to disk when new ones have arrived.
  Future<void> flush() async {
    // At most once per minute: the notice says when the app last ran.
    final now = _now();
    if (_active && (_touched == null || now.difference(_touched!) >= const Duration(minutes: 1))) {
      await _writeMarker();
    }
    if (_active && _activeSince != null && now.difference(_activeSince!) >= stableAfter) await _endStreak();
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
