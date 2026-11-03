import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Largest file that opens directly from outside (mail, AirDrop, file manager).
/// It is held entirely in memory and passes through the platform channel; users
/// who really have more use the file picker in the app.
const incomingMaxBytes = 128 * 1024 * 1024;

/// Why an opened file does not even reach the check.
enum IncomingProblem { tooLarge, unreadable }

/// A file opened from outside: only the content, never the name or path.
sealed class IncomingFile {
  const IncomingFile();
}

final class IncomingBytes extends IncomingFile {
  const IncomingBytes(this.bytes);
  final Uint8List bytes;
}

final class IncomingRefused extends IncomingFile {
  const IncomingRefused(this.problem);
  final IncomingProblem problem;
}

/// Path from the launch arguments (Windows, Linux): the first argument with our
/// extension, as a path or `file:` URI. Everything else (switches, foreign files,
/// other schemes) does not count. Never throws.
String? packagePathFromArgs(List<String> args) {
  for (final arg in args) {
    final lower = arg.toLowerCase();
    if (!lower.endsWith('.knxhandover') && !lower.endsWith('.knxreport')) continue;
    if (lower.startsWith('file:')) {
      try {
        return Uri.parse(arg).toFilePath();
      } on Object catch (e) {
        debugPrint('Startargument: $e');
        continue;
      }
    }
    // Other schemes; a drive letter (C:\…) is not one.
    if (RegExp(r'^[a-z][a-z0-9+.-]+:').hasMatch(lower)) continue;
    return arg;
  }
  return null;
}

/// Response of the native side to `incomingFiles`. Anything that does not fit
/// counts as unreadable. Never throws.
List<IncomingFile> incomingFromNative(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      switch (item) {
        {'bytes': final Uint8List bytes} when bytes.length <= incomingMaxBytes => IncomingBytes(bytes),
        {'bytes': Uint8List _} || {'problem': 'tooLarge'} => const IncomingRefused(IncomingProblem.tooLarge),
        _ => const IncomingRefused(IncomingProblem.unreadable),
      },
  ];
}

/// Switch between platform and UI. Files wait until [attach] says the UI is
/// ready, then open one after another: each brings dialogs. An error while
/// opening stops neither the next file nor the app.
class IncomingFileGate {
  /// No more than this wait at once: each file is held entirely in memory.
  static const maxWaiting = 4;

  final _waiting = Queue<IncomingFile>();
  Future<void> Function(IncomingFile)? _open;
  bool _busy = false;

  int get waiting => _waiting.length;

  void add(IncomingFile file) {
    if (_waiting.length >= maxWaiting) {
      debugPrint('Geöffnete Datei verworfen: schon $maxWaiting in der Warteschlange');
      return;
    }
    _waiting.add(file);
    _drain();
  }

  void attach(Future<void> Function(IncomingFile) open) {
    _open = open;
    _drain();
  }

  Future<void> _drain() async {
    final open = _open;
    if (open == null || _busy) return;
    _busy = true;
    try {
      while (_waiting.isNotEmpty) {
        try {
          await open(_waiting.removeFirst());
        } on Object catch (e, st) {
          debugPrint('Geöffnete Datei: $e\n$st');
        }
      }
    } finally {
      _busy = false;
    }
  }
}
