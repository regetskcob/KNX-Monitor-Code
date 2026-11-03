import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Detects unexpected server exits (crash, power failure, SIGKILL) and records
/// them locally (public issue #4). On start, `running.json` is placed in the
/// data folder and removed on a clean shutdown; if the next start still finds
/// it, something went wrong. Nothing is sent: it only leaves the device if the
/// user creates and shares a diagnostics package.
///
/// Every method catches everything. A full or read-only storage medium must
/// never prevent the start.
class CrashWatch {
  CrashWatch(
    this.data, {
    this.version,
    this.keep = 200,
    DateTime Function()? now,
    File? bootIdFile,
    void Function(String message)? log,
  }) : _now = now ?? DateTime.now,
       _bootId = bootIdFile ?? File('/proc/sys/kernel/random/boot_id'),
       _log = log ?? stderr.writeln;

  final Directory data;
  final String? version;
  final int keep;
  final DateTime Function() _now;
  final File _bootId;
  final void Function(String message) _log;

  File get _marker => File('${data.path}/running.json');
  File get _file => File('${data.path}/restarts.ndjson');
  File get _errorFile => File('${data.path}/last-error.txt');

  final _entries = <Map<String, Object?>>[];
  Timer? _touch;

  /// How often the marker gets "still alive"; time of the last sign of life.
  static const touchInterval = Duration(minutes: 1);

  /// Known restarts, oldest first.
  List<Map<String, Object?>> get entries => List.unmodifiable(_entries);

  /// Evaluates the marker of the last run and sets its own.
  Future<void> start() async {
    try {
      await _load();
      await _detect();
    } on Object catch (e) {
      _log('Neustarts: $e');
    }
    try {
      await _marker.writeAsString(
        jsonEncode({'start': _now().millisecondsSinceEpoch, 'version': version, 'boot': await _readBootId()}),
        flush: true,
      );
      _touch = Timer.periodic(touchInterval, (_) => unawaited(_keepAlive()));
    } on Object catch (e) {
      _log('Neustarts: Marke nicht geschrieben: $e');
    }
  }

  /// Metadata only: spares the SD card; the availability is written as a
  /// status line anyway.
  Future<void> _keepAlive() async {
    try {
      await _marker.setLastModified(_now());
    } on Object {
      // Try again next time.
    }
  }

  Future<String?> _readBootId() async {
    try {
      return (await _bootId.readAsString()).trim();
    } on Object {
      return null;
    }
  }

  Future<void> _load() async {
    if (!await _file.exists()) return;
    for (final line in await _file.readAsLines()) {
      try {
        _entries.add((jsonDecode(line) as Map).cast<String, Object?>());
      } on Object {
        // truncated line
      }
    }
    if (_entries.length > keep) _entries.removeRange(0, _entries.length - keep);
  }

  Future<void> _detect() async {
    final marker = _marker;
    if (!await marker.exists()) return;
    final seen = await marker.lastModified();
    Map<String, Object?> previous;
    try {
      previous = (jsonDecode(await marker.readAsString()) as Map).cast<String, Object?>();
    } on Object {
      // Interrupted while writing: the run still did not end cleanly.
      previous = const {};
    }
    String? error;
    try {
      if (await _errorFile.exists()) {
        error = await _errorFile.readAsString();
        await _errorFile.delete();
      }
    } on Object {
      // Continue without an error text.
    }
    final boot = await _readBootId();
    final reason = error != null
        ? 'error'
        : (boot != null && previous['boot'] is String && previous['boot'] != boot)
        ? 'host'
        : 'unknown';
    final entry = {
      't': _now().millisecondsSinceEpoch,
      'lastSeen': seen.millisecondsSinceEpoch,
      'reason': reason,
      'version': ?previous['version'],
      'error': ?error,
    };
    _entries.add(entry);
    if (_entries.length > keep) _entries.removeRange(0, _entries.length - keep);
    // Rewrite the whole file if it got too long; otherwise append.
    await _file.writeAsString('${jsonEncode(entry)}\n', mode: FileMode.append, flush: true);
    if (await _file.length() > 256 * 1024) {
      await _file.writeAsString(_entries.map((e) => '${jsonEncode(e)}\n').join(), flush: true);
    }
    _log('Server wurde unerwartet beendet (Grund: $reason, zuletzt am Leben: $seen)');
  }

  /// Unhandled error: write to disk immediately, the process ends afterwards.
  void recordError(Object error, StackTrace? stack) {
    try {
      final text = '$error\n${stack ?? ''}';
      _errorFile.writeAsStringSync(text.length > 8000 ? text.substring(0, 8000) : text, flush: true);
    } on Object catch (e) {
      _log('Neustarts: Fehler nicht gesichert: $e');
    }
  }

  /// Clean exit (SIGTERM from the Supervisor or from systemd).
  Future<void> cleanExit() async {
    _touch?.cancel();
    try {
      if (await _marker.exists()) await _marker.delete();
    } on Object catch (e) {
      _log('Neustarts: Marke nicht entfernt: $e');
    }
  }

  /// Restarts within the time span, without error text (for the customer report).
  List<Map<String, Object?>> between(DateTime from, DateTime to) => [
    for (final e in _entries)
      if ((e['t']! as int) >= from.millisecondsSinceEpoch && (e['t']! as int) < to.millisecondsSinceEpoch)
        {'t': e['t'], 'lastSeen': e['lastSeen'], 'reason': e['reason']},
  ];

  /// For the status: number in the last 30 days and the most recent one;
  /// `null` if there was none.
  Map<String, Object?>? summary() {
    final since = _now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    final recent = [
      for (final e in _entries)
        if ((e['t']! as int) >= since) e,
    ];
    if (recent.isEmpty) return null;
    final last = recent.last;
    return {
      'count': recent.length,
      'last': {'t': last['t'], 'lastSeen': last['lastSeen'], 'reason': last['reason']},
    };
  }

  /// Complete, for the diagnostics package; the app sanitizes the texts.
  List<Map<String, Object?>> recent({int days = 30}) {
    final since = _now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    return [
      for (final e in _entries)
        if ((e['t']! as int) >= since) e,
    ];
  }
}
