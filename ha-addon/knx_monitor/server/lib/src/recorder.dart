import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'free_space.dart';

/// Writes group telegrams to the daily history
/// (`history/YYYY-MM-DD.ndjson`, one JSON line per telegram) – the same
/// format the app reads.
///
/// - collected every [flushInterval] and without `fsync`; committed to disk
///   only every [syncInterval] and on shutdown (spares SD cards, so a power
///   failure loses at most that many seconds),
/// - too little free space ([minFreeBytes]): first delete the oldest days (today
///   stays); if that is not enough, stop writing and say so ([lowSpace]),
/// - completed days are packed into `.ndjson.gz`,
/// - retention by days and by total size,
/// - if the buffer overflows, telegrams are counted instead of silently dropped,
/// - without a confirmed time ([timeKnown], box only) the lines go with a
///   monotonic counter into `history/unsynced-<start>.ndjson` and are moved
///   into the right days when the clock is set ([retime]) – or, with
///   [holdUntilTime], not recorded at all. If such a file is left over from an
///   earlier start, it can no longer be placed: the monotonic counter restarts
///   with every start. It stays readable as a section "without time"
///   (`/api/files/history/`) and falls under retention, counted from the first
///   cleanup with a confirmed clock (`unsynced-<start>-<detected>.ndjson`); the
///   name itself only carries the wrong clock of that time.
class Recorder {
  Recorder(
    this.data, {
    this.retentionDays = 7,
    this.maxMegabytes = 1000,
    this.flushInterval = const Duration(seconds: 5),
    this.syncInterval = const Duration(seconds: 30),
    this.minFreeBytes = 256 * 1024 * 1024,
    Future<int?> Function(String path)? freeSpace,
    Future<void> Function(File file)? syncFile,
    DateTime Function()? clock,
  }) : _freeSpace = freeSpace ?? freeBytes,
       _syncFile = syncFile ?? _fsync,
       _now = clock ?? DateTime.now;

  final Directory data;
  int retentionDays;
  int maxMegabytes;
  Duration flushInterval;

  /// Interval between two `fsync` calls.
  final Duration syncInterval;

  /// Below this, old data is cleaned up and, if needed, writing stops. Writing
  /// resumes at one and a half times this value so it does not flap.
  final int minFreeBytes;

  final Future<int?> Function(String path) _freeSpace;
  final Future<void> Function(File file) _syncFile;
  final DateTime Function() _now;

  /// Writing paused because the disk is full.
  bool lowSpace = false;

  /// Telegrams dropped for that reason since start.
  int droppedLowSpace = 0;

  /// Last measured free space.
  int? lastFree;

  DateTime? _freeChecked;
  DateTime? _lastSync;
  final _unsynced = <String>{};

  static const _freeCheckInterval = Duration(minutes: 1);

  /// Upper limit of the buffer; beyond it telegrams are dropped and counted.
  static const maxBuffered = 200000;

  final _buffer = <Map<String, Object?>>[];
  Timer? _timer;
  Future<void> _writing = Future.value();

  /// Telegrams dropped since start (buffer full).
  int dropped = 0;

  /// Telegrams written since start.
  int written = 0;

  /// Whether the clock is right; `null` means always (Home Assistant sets the time).
  bool Function()? timeKnown;

  /// Monotonic counter in microseconds (from the box's clock).
  int Function()? monoMicros;

  /// Whether to record only once the time is right (instead of correcting later).
  bool holdUntilTime = false;

  /// Dropped because the time was still missing ([holdUntilTime]).
  int waiting = 0;

  /// File for lines without a confirmed time, one per server start.
  late final String _unsyncedName = 'unsynced-${DateTime.now().millisecondsSinceEpoch}.ndjson';

  Directory get _dir => Directory('${data.path}/history');

  static final _unsyncedFile = RegExp(r'^unsynced-(\d+)(?:-(\d+))?\.ndjson$');

  static String dayName(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool get enabled => retentionDays > 0;

  Future<void> start() async {
    await _dir.create(recursive: true);
    await _maintain();
  }

  void add(Map<String, Object?> line) {
    if (!enabled) return;
    if (timeKnown?.call() == false) {
      if (holdUntilTime) {
        waiting++;
        return;
      }
      line['mono'] = monoMicros?.call() ?? 0;
    }
    if (_buffer.length >= maxBuffered) {
      dropped++;
      return;
    }
    _buffer.add(line);
    _timer ??= Timer(
      flushInterval < const Duration(milliseconds: 250) ? const Duration(milliseconds: 250) : flushInterval,
      flush,
    );
  }

  /// Writes the buffer immediately. With [durable] also commits it to disk (shutdown).
  Future<void> flush({bool durable = false}) {
    _timer?.cancel();
    _timer = null;
    final pending = List.of(_buffer);
    _buffer.clear();
    return _writing = _writing
        .then((_) async {
          try {
            await _write(pending);
          } on FileSystemException catch (e) {
            // Disk full or broken: counted and reported, not silently lost.
            droppedLowSpace += pending.length;
            lowSpace = true;
            stderr.writeln('Verlauf schreiben: $e');
          }
          await _syncIfDue(force: durable);
        })
        .catchError((Object e) {
          stderr.writeln('Verlauf schreiben: $e');
        });
  }

  /// Commits the files written since the last time to disk.
  Future<void> _syncIfDue({bool force = false}) async {
    if (_unsynced.isEmpty) return;
    final now = _now();
    final last = _lastSync ??= now;
    if (!force && now.difference(last) < syncInterval) return;
    _lastSync = now;
    final files = List.of(_unsynced);
    _unsynced.clear();
    for (final path in files) {
      final file = File(path);
      if (await file.exists()) await _syncFile(file);
    }
  }

  static Future<void> _fsync(File file) async {
    final handle = await file.open(mode: FileMode.append);
    try {
      await handle.flush();
    } finally {
      await handle.close();
    }
  }

  /// Whether there is enough space to write. Measures at most once per minute.
  /// When space gets tight, the oldest days go; today stays.
  Future<bool> _roomToWrite() async {
    final now = _now();
    final checked = _freeChecked;
    if (checked != null && now.difference(checked) < _freeCheckInterval) return !lowSpace;
    _freeChecked = now;
    var free = lastFree = await _freeSpace(data.path);
    // Not measurable: write as before, [flush] catches errors.
    if (free == null) return !lowSpace;
    if (free < minFreeBytes) {
      await _freeUp();
      free = lastFree = await _freeSpace(data.path);
    }
    if (free == null) return !lowSpace;
    final was = lowSpace;
    lowSpace = free < (lowSpace ? minFreeBytes * 3 ~/ 2 : minFreeBytes);
    if (lowSpace != was) {
      stderr.writeln(
        lowSpace
            ? 'Verlauf: nur noch ${free >> 20} MB frei, Aufzeichnung angehalten'
            : 'Verlauf: wieder ${free >> 20} MB frei, Aufzeichnung läuft weiter',
      );
    }
    return !lowSpace;
  }

  /// Deletes from oldest to newest until enough is free; today and this
  /// start's file stay. Works independently of [maxMegabytes]: on a small card
  /// space runs out long before the configured limit.
  Future<void> _freeUp() async {
    if (!await _dir.exists()) return;
    final today = dayName(DateTime.now());
    final candidates = <(String, File)>[];
    for (final f in await _unsyncedFiles()) {
      if (f.uri.pathSegments.last != _unsyncedName) candidates.add(('', f));
    }
    for (final f in await _dayFiles()) {
      final day = f.uri.pathSegments.last.substring(0, 10);
      if (day != today) candidates.add((day, f));
    }
    candidates.sort((a, b) => a.$1.compareTo(b.$1));
    for (final (day, f) in candidates) {
      final free = await _freeSpace(data.path);
      if (free != null && free >= minFreeBytes * 3 ~/ 2) return;
      stderr.writeln('Verlauf: wenig Platz, lösche ${day.isEmpty ? 'Abschnitt ohne Uhrzeit' : day}');
      await f.delete();
    }
  }

  Future<void> _write(List<Map<String, Object?>> pending) async {
    if (pending.isEmpty) return;
    if (!await _roomToWrite()) {
      droppedLowSpace += pending.length;
      return;
    }
    final byDay = <String, StringBuffer>{};
    for (final line in pending) {
      // Without a confirmed time into its own file, not into a wrong day.
      final day = line.containsKey('mono')
          ? _unsyncedName.replaceFirst('.ndjson', '')
          : dayName(DateTime.fromMicrosecondsSinceEpoch(line['t']! as int));
      (byDay[day] ??= StringBuffer()).writeln(jsonEncode(line));
    }
    await _dir.create(recursive: true);
    for (final MapEntry(key: day, value: lines) in byDay.entries) {
      final file = File('${_dir.path}/$day.ndjson');
      await file.writeAsString(lines.toString(), mode: FileMode.append);
      _unsynced.add(file.path);
    }
    written += pending.length;
  }

  /// The clock was set: [time] applied at monotonic counter [monoMicros].
  /// Moves this start's lines without time into the daily files before new
  /// lines are written.
  Future<void> retime(DateTime time, int monoMicros) {
    unawaited(flush());
    return _writing = _writing.then((_) => _retime(time, monoMicros)).catchError((Object e) {
      stderr.writeln('Verlauf umrechnen: $e');
    });
  }

  Future<void> _retime(DateTime time, int mono) async {
    final file = File('${_dir.path}/$_unsyncedName');
    if (!await file.exists()) return;
    final byDay = <String, StringBuffer>{};
    var count = 0;
    await for (final raw in file.openRead().transform(utf8.decoder).transform(const LineSplitter())) {
      try {
        final line = jsonDecode(raw) as Map<String, Object?>;
        final m = line.remove('mono') as int? ?? mono;
        final t = time.subtract(Duration(microseconds: mono - m));
        line['t'] = t.microsecondsSinceEpoch;
        (byDay[dayName(t)] ??= StringBuffer()).writeln(jsonEncode(line));
        count++;
      } on Object {
        // truncated line
      }
    }
    for (final MapEntry(key: day, value: lines) in byDay.entries) {
      await File('${_dir.path}/$day.ndjson').writeAsString(lines.toString(), mode: FileMode.append, flush: true);
    }
    await file.delete();
    stdout.writeln('Verlauf: $count Telegramme ohne Zeit nachträglich eingeordnet');
  }

  /// Packs completed days and cleans up according to retention. Runs at
  /// start (catches up on what a crash left behind) and once per hour.
  Future<void> maintain() => _writing = _writing.then((_) => _maintain()).catchError((Object e) {
    stderr.writeln('Verlauf aufräumen: $e');
  });

  Future<void> _maintain() async {
    if (!await _dir.exists()) return;
    final today = dayName(DateTime.now());
    await _recover();
    for (final f in await _dayFiles()) {
      final name = f.uri.pathSegments.last;
      if (name.endsWith('.ndjson') && name != '$today.ndjson') await _gzip(f);
    }
    await _markOrphans();
    await _prune(today);
    // Measure even without telegrams: the status should show a full disk.
    _freeChecked = null;
    await _roomToWrite();
  }

  /// Packs a finished day in steps that a power cut cannot leave ambiguous:
  ///
  /// 1. pack the plain file (and an existing `.gz`) into `.gz.tmp`, flushed to
  ///    disk;
  /// 2. rename the plain file to `.done`: from now on `.gz.tmp` is the day;
  /// 3. rename `.gz.tmp` to `.gz`;
  /// 4. delete `.done`.
  ///
  /// [_recover] finishes or discards an interrupted run from the files that are
  /// left, without comparing content.
  Future<void> _gzip(File f) async {
    final target = File('${f.path}.gz');
    final tmp = File('${target.path}.tmp');
    final done = File('${f.path}.done');
    // Already packed (clock briefly showed another day): append, do not replace.
    final Stream<List<int>> lines = await target.exists()
        ? () async* {
            yield* target.openRead().transform(gzip.decoder);
            yield* f.openRead();
          }()
        : f.openRead();
    await lines.transform(gzip.encoder).pipe(tmp.openWrite());
    final raf = await tmp.open(mode: FileMode.append);
    try {
      await raf.flush();
    } finally {
      await raf.close();
    }
    await f.rename(done.path);
    await tmp.rename(target.path);
    await done.delete();
  }

  /// Leftovers of an interrupted [_gzip]: with `.done` the `.gz.tmp` is complete
  /// and becomes the day (or already did); without `.done` it is discarded and
  /// the plain file is packed again.
  Future<void> _recover() async {
    await for (final e in _dir.list()) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      if (name.endsWith('.ndjson.done')) {
        final day = name.substring(0, name.length - '.done'.length);
        final tmp = File('${_dir.path}/$day.gz.tmp');
        if (await tmp.exists()) await tmp.rename('${_dir.path}/$day.gz');
        await e.delete();
      }
    }
    await for (final e in _dir.list()) {
      if (e is File && e.uri.pathSegments.last.endsWith('.ndjson.gz.tmp')) await e.delete();
    }
  }

  Future<List<File>> _dayFiles() async => [
    await for (final e in _dir.list())
      if (e is File && RegExp(r'^\d{4}-\d{2}-\d{2}\.ndjson(\.gz)?$').hasMatch(e.uri.pathSegments.last)) e,
  ]..sort((a, b) => a.path.compareTo(b.path));

  Future<List<File>> _unsyncedFiles() async => [
    await for (final e in _dir.list())
      if (e is File && _unsyncedFile.hasMatch(e.uri.pathSegments.last)) e,
  ]..sort((a, b) => a.path.compareTo(b.path));

  /// With a confirmed clock: leftover files get the time from which their
  /// retention runs. Their start stamp is useless for this (the clock was
  /// wrong); with it they would disappear at the first cleanup.
  Future<void> _markOrphans() async {
    if (timeKnown?.call() == false) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final f in await _unsyncedFiles()) {
      final name = f.uri.pathSegments.last;
      if (name == _unsyncedName) continue;
      final m = _unsyncedFile.firstMatch(name)!;
      if (m[2] == null) await f.rename('${_dir.path}/unsynced-${m[1]}-$now.ndjson');
    }
  }

  Future<void> _prune(String today) async {
    final files = await _dayFiles();
    final unsynced = await _unsyncedFiles();
    if (!enabled) {
      for (final f in [...files, ...unsynced]) {
        await f.delete();
      }
      return;
    }
    final now = DateTime.now();
    final cutoff = dayName(DateTime(now.year, now.month, now.day - (retentionDays - 1)));
    final kept = <(String, File)>[];
    for (final f in files) {
      final day = f.uri.pathSegments.last.substring(0, 10);
      if (day.compareTo(cutoff) < 0) {
        await f.delete();
      } else {
        kept.add((day, f));
      }
    }
    var total = 0;
    for (final f in unsynced) {
      final name = f.uri.pathSegments.last;
      // This start's file is still being written and moved.
      if (name == _unsyncedName) {
        total += await f.length();
        continue;
      }
      final marked = int.tryParse(_unsyncedFile.firstMatch(name)![2] ?? '');
      // No confirmed clock yet: no date, first in line for the size limit.
      final day = marked == null ? '' : dayName(DateTime.fromMillisecondsSinceEpoch(marked));
      if (marked != null && day.compareTo(cutoff) < 0) {
        await f.delete();
      } else {
        kept.add((day, f));
      }
    }
    kept.sort((a, b) => a.$1.compareTo(b.$1));
    // Size limit: oldest days first, today stays.
    for (final (_, f) in kept) {
      total += await f.length();
    }
    final limit = maxMegabytes * 1024 * 1024;
    for (final (day, f) in kept) {
      if (total <= limit || day == today) break;
      total -= await f.length();
      await f.delete();
    }
  }

  /// Statistics for the last [days] days: telegrams per weekday × hour
  /// (Monday = 0), per day, and the most active group addresses and senders.
  Future<Map<String, Object?>> stats(int days, {int top = 50}) async {
    await flush();
    final heatmap = List.generate(7, (_) => List.filled(24, 0));
    final perDay = <String, int>{};
    final groups = <int, int>{};
    final senders = <int, int>{};
    var total = 0;
    final now = DateTime.now();
    for (var back = days - 1; back >= 0; back--) {
      final day = dayName(DateTime(now.year, now.month, now.day - back));
      final lines = await dayLines(day);
      if (lines == null) continue;
      var count = 0;
      await for (final line in lines) {
        // Only the needed fields, without fully decoding each line.
        final t = int.tryParse(field(line, 't') ?? '');
        final d = int.tryParse(field(line, 'd') ?? '');
        if (t == null || d == null) continue;
        final time = DateTime.fromMicrosecondsSinceEpoch(t);
        heatmap[time.weekday - 1][time.hour]++;
        groups[d] = (groups[d] ?? 0) + 1;
        if (!line.contains('"o":true')) {
          final src = int.tryParse(field(line, 's') ?? '');
          if (src != null) senders[src] = (senders[src] ?? 0) + 1;
        }
        count++;
      }
      perDay[day] = count;
      total += count;
    }
    List<List<int>> topOf(Map<int, int> m) => ([
      for (final e in m.entries) [e.key, e.value],
    ]..sort((a, b) => b[1].compareTo(a[1]))).take(top).toList();
    return {
      'days': days,
      'total': total,
      'heatmap': heatmap,
      'perDay': perDay,
      'groups': topOf(groups),
      'senders': topOf(senders),
    };
  }

  /// Lines of the day [day] (`YYYY-MM-DD`, open or packed); `null` if the day
  /// does not exist.
  Future<Stream<String>?> dayLines(String day) async {
    final plain = File('${_dir.path}/$day.ndjson');
    final packed = File('${plain.path}.gz');
    final Stream<List<int>> bytes;
    if (await plain.exists() && await packed.exists()) {
      bytes = () async* {
        yield* packed.openRead().transform(gzip.decoder);
        yield* plain.openRead();
      }();
    } else if (await plain.exists()) {
      bytes = plain.openRead();
    } else if (await packed.exists()) {
      bytes = packed.openRead().transform(gzip.decoder);
    } else {
      return null;
    }
    return bytes.transform(utf8.decoder).transform(const LineSplitter());
  }

  /// Time of the newest recorded telegram, only before [before] if given;
  /// `null` without history. Lines in the buffer only count after a [flush].
  Future<DateTime?> lastTime({DateTime? before}) async {
    if (!await _dir.exists()) return null;
    final limit = before?.microsecondsSinceEpoch;
    final days = {for (final f in await _dayFiles()) f.uri.pathSegments.last.substring(0, 10)}.toList()..sort();
    for (final day in days.reversed) {
      if (before != null && day.compareTo(dayName(before)) > 0) continue;
      int? newest;
      // A day can be out of order (clock corrected later), so read all of it.
      await for (final line in (await dayLines(day))!) {
        final t = int.tryParse(field(line, 't') ?? '');
        if (t != null && (limit == null || t < limit) && (newest == null || t > newest)) newest = t;
      }
      if (newest != null) return DateTime.fromMicrosecondsSinceEpoch(newest);
    }
    return null;
  }

  /// Recorded lines between [from] and [to] (both included), in file order.
  Future<List<Map<String, Object?>>> linesBetween(DateTime from, DateTime to) async {
    final result = <Map<String, Object?>>[];
    final start = from.microsecondsSinceEpoch;
    final end = to.microsecondsSinceEpoch;
    for (var d = DateTime(from.year, from.month, from.day); !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
      final lines = await dayLines(dayName(d));
      if (lines == null) continue;
      await for (final line in lines) {
        final t = int.tryParse(field(line, 't') ?? '');
        if (t == null || t < start || t > end) continue;
        try {
          result.add(jsonDecode(line) as Map<String, Object?>);
        } on FormatException {
          // truncated line
        }
      }
    }
    return result;
  }

  /// Number after `"[key]":` in a history line, without fully decoding it.
  static String? field(String line, String key) {
    final i = line.indexOf('"$key":');
    if (i < 0) return null;
    final start = i + key.length + 3;
    var end = start;
    while (end < line.length && line.codeUnitAt(end) >= 0x30 && line.codeUnitAt(end) <= 0x39) {
      end++;
    }
    return line.substring(start, end);
  }

  /// Total size, number of days and oldest day of the history.
  Future<Map<String, Object?>> usage() async {
    if (!await _dir.exists()) return {'bytes': 0, 'days': 0};
    final files = await _dayFiles();
    final unsynced = await _unsyncedFiles();
    var bytes = 0;
    for (final f in [...files, ...unsynced]) {
      bytes += await f.length();
    }
    return {
      'bytes': bytes,
      'days': files.length,
      'free': ?lastFree,
      if (lowSpace) 'lowSpace': true,
      if (droppedLowSpace > 0) 'droppedLowSpace': droppedLowSpace,
      if (unsynced.isNotEmpty) 'unsynced': unsynced.length,
      if (files.isNotEmpty) 'first': files.first.uri.pathSegments.last.substring(0, 10),
    };
  }
}

/// Availability: once per minute a line with the connection state and the
/// number of telegrams since the previous line. This explains every gap in
/// the history – bus quiet (connected, 0 telegrams), connection lost
/// (not connected) or the add-on was not running (no line).
class Availability {
  Availability(this.data, {this.keepMonths = 3});

  final Directory data;
  final int keepMonths;

  Directory get _dir => Directory('${data.path}/status');

  static String _month(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  Future<void> beat({required bool connected, required int telegrams, DateTime? now}) async {
    final t = now ?? DateTime.now();
    await _dir.create(recursive: true);
    await File('${_dir.path}/availability-${_month(t)}.ndjson').writeAsString(
      '${jsonEncode({'t': t.millisecondsSinceEpoch, 'c': connected, 'n': telegrams})}\n',
      mode: FileMode.append,
      flush: true,
    );
    // Remove old months.
    final oldest = _month(DateTime(t.year, t.month - keepMonths + 1));
    await for (final e in _dir.list()) {
      final name = e.uri.pathSegments.last;
      final m = RegExp(r'^availability-(\d{4}-\d{2})\.ndjson$').firstMatch(name);
      if (e is File && m != null && m[1]!.compareTo(oldest) < 0) await e.delete();
    }
  }

  /// Outages in the period: stretches without a connection or without
  /// heartbeats (longer than [gap]). Time before the first line counts as unknown.
  Future<List<Map<String, Object?>>> outages(
    DateTime from,
    DateTime to, {
    Duration gap = const Duration(minutes: 3),
  }) async => _outages(await _beats(from, to, gap), to, gap);

  /// Share (0–1) of the period in which the bus was connected: 1 minus the
  /// [outages] (clipped to the period) divided by the known time, which starts
  /// at the first heartbeat in the period. `null` without heartbeats.
  Future<double?> ratio(DateTime from, DateTime to, {Duration gap = const Duration(minutes: 3)}) async {
    final beats = await _beats(from, to, gap);
    if (beats.isEmpty) return null;
    final start = beats.first.$1.isAfter(from) ? beats.first.$1 : from;
    final known = to.difference(start).inMilliseconds;
    if (known <= 0) return null;
    var out = 0;
    for (final o in _outages(beats, to, gap)) {
      final a = (o['from']! as int).clamp(start.millisecondsSinceEpoch, to.millisecondsSinceEpoch);
      final b = (o['to']! as int).clamp(start.millisecondsSinceEpoch, to.millisecondsSinceEpoch);
      out += b - a;
    }
    return (1 - out / known).clamp(0.0, 1.0);
  }

  Future<List<(DateTime, bool)>> _beats(DateTime from, DateTime to, Duration gap) async {
    final beats = <(DateTime, bool)>[];
    for (var m = DateTime(from.year, from.month); !m.isAfter(to); m = DateTime(m.year, m.month + 1)) {
      final f = File('${_dir.path}/availability-${_month(m)}.ndjson');
      if (!await f.exists()) continue;
      for (final line in await f.readAsLines()) {
        try {
          final j = jsonDecode(line) as Map<String, Object?>;
          final t = DateTime.fromMillisecondsSinceEpoch(j['t']! as int);
          if (t.isBefore(from.subtract(gap)) || t.isAfter(to.add(gap))) continue;
          beats.add((t, j['c'] == true));
        } on Object {
          // truncated line
        }
      }
    }
    beats.sort((a, b) => a.$1.compareTo(b.$1));
    return beats;
  }

  static List<Map<String, Object?>> _outages(List<(DateTime, bool)> beats, DateTime to, Duration gap) {
    final result = <Map<String, Object?>>[];
    void add(DateTime start, DateTime end, String kind) {
      if (result.isNotEmpty && result.last['kind'] == kind && result.last['to'] == start.millisecondsSinceEpoch) {
        result.last['to'] = end.millisecondsSinceEpoch;
      } else {
        result.add({'from': start.millisecondsSinceEpoch, 'to': end.millisecondsSinceEpoch, 'kind': kind});
      }
    }

    for (var i = 1; i < beats.length; i++) {
      final (prev, prevConnected) = beats[i - 1];
      final (t, connected) = beats[i];
      if (t.difference(prev) > gap) {
        add(prev, t, 'offline'); // add-on was not running
      } else if (!connected || !prevConnected) {
        add(prev, t, 'disconnected');
      }
    }
    if (beats.isNotEmpty && to.difference(beats.last.$1) > gap && DateTime.now().difference(beats.last.$1) > gap) {
      add(beats.last.$1, to, 'offline');
    }
    return result;
  }
}
