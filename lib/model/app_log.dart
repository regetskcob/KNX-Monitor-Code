import 'dart:collection';

import 'package:flutter/foundation.dart';

/// The app's latest messages (debugPrint, Flutter and runtime errors) in memory –
/// for the diagnostic package. Nothing is sent on its own.
///
/// They are stored, though: in release builds [CrashGuard] regularly writes the
/// lines unfiltered to `crash_log.txt` on the device so they survive a crash.
/// The file is encrypted where the storage has a key. Only the diagnostic package
/// filters out addresses and identifiers.
class AppLog {
  AppLog._();

  static final instance = AppLog._();

  /// A bug report does not need more.
  static const capacity = 300;

  final _lines = ListQueue<String>();

  List<String> get lines => List.unmodifiable(_lines);

  void add(String message) {
    final time = DateTime.now().toIso8601String();
    for (final line in message.trimRight().split('\n')) {
      _lines.addLast('$time $line');
      if (_lines.length > capacity) _lines.removeFirst();
    }
  }

  /// Also captures debugPrint and unhandled errors; the existing output stays as
  /// it is.
  void install() {
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) add(message);
      print(message, wrapWidth: wrapWidth);
    };
    final flutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      add('FlutterError: ${details.exceptionAsString()}\n${details.stack ?? ''}');
      flutterError?.call(details);
    };
    final platformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      add('Error: $error\n$stack');
      return platformError?.call(error, stack) ?? false;
    };
  }

  @visibleForTesting
  void clear() => _lines.clear();
}
