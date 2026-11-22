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

  /// Lines handed to the write queue but not on disk yet: they count towards
  /// [maxBuffered] too, otherwise a stalled disk lets the queue grow without limit.
  int _queued = 0;

  /// Since when lines wait in the write queue without a break.
  DateTime? _queuedSince;

  /// Lines wait longer than this: the write queue hangs.
  static const stallAfter = Duration(minutes: 10);

  /// The write queue has not come to an end for [stallAfter] (packing a large
  /// day takes minutes, not this long): nothing is recorded any more although
  /// the server still answers. A restart helps, unlike with a full disk.
  bool get stalled {
    final since = _queuedSince;
    return since != null && _now().difference(since) > stallAfter;
  }

  /// Last write that reached the file (or found nothing to write); `null`
  /// until the first one. With [lastWriteFailed] the health check tells a
  /// recorder that only answers from one that still records.
  DateTime? lastFlush;

  /// The last write failed with an error other than "disk full".
  bool lastWriteFailed = false;

  /// While this returns `true`, nothing is deleted by age (and "retention off"
  /// deletes nothing either): the settings or the clock that decide what is
  /// "old" are not confirmed (lost `server.json`, a clock set far ahead by a
  /// source that is not trusted). The size limit and "disk full" still apply.
  bool Function()? keepExpired;

  /// Daily files this start has already appended to: only the first append
  /// checks whether the file ends with a line break.
  final _tailChecked = <String>{};

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

  /// Never throws: a history folder that cannot be cleaned up (full disk,
  /// broken file) must not keep the server from starting.
  Future<void> start() async {
    try {
      await _dir.create(recursive: true);
      await _maintain();
    } on Object catch (e) {
      stderr.writeln('Verlauf aufräumen beim Start: $e');
    }
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
    if (_buffer.length + _queued >= maxBuffered) {
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
    _queued += pending.length;
    if (pending.isNotEmpty) _queuedSince ??= _now();
    return _writing = _writing
        .then((_) async {
          try {
            await _write(pending);
            lastFlush = _now();
            lastWriteFailed = false;
          } on FileSystemException catch (e) {
            // Disk full or broken: counted and reported, not silently lost.
            droppedLowSpace += pending.length;
            lowSpace = true;
            lastWriteFailed = true;
            stderr.writeln('Verlauf schreiben: $e');
          } finally {
            _queued -= pending.length;
            if (_queued == 0) _queuedSince = null;
          }
          await _syncIfDue(force: durable);
        })
        .catchError((Object e) {
          lastWriteFailed = true;
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
    final today = dayName(_now());
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
      final lead = await _needsLineBreak(file) ? '\n' : '';
      await file.writeAsString('$lead$lines', mode: FileMode.append);
      _unsynced.add(file.path);
    }
    written += pending.length;
  }

  /// A power cut can leave the last line of a file without its line break. The
  /// next append would continue in that line, and readers would skip the first
  /// new telegram together with the truncated one. Checked once per file and start.
  Future<bool> _needsLineBreak(File file) async {
    if (!_tailChecked.add(file.path)) return false;
    try {
      if (!await file.exists()) return false;
      final raf = await file.open();
      try {
        final length = await raf.length();
        if (length == 0) return false;
        await raf.setPosition(length - 1);
        return await raf.readByte() != 0x0A;
      } finally {
        await raf.close();
      }
    } on FileSystemException {
      return false;
    }
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

  /// Streams the file line by line (a box that ran for days without a clock
  /// has hundreds of megabytes there) and in steps a power cut cannot turn
  /// into duplicates:
  ///
  /// 1. the converted lines go into one `<day>.ndjson.retime-tmp` per day,
  ///    flushed to disk;
  /// 2. the source is renamed to `.retimed`: from now on the parts are the data;
  /// 3. each part is renamed to `<day>.ndjson.retime-<length of the daily
  ///    file>`, appended to the daily file and deleted;
  /// 4. `.retimed` is deleted.
  ///
  /// [_recoverRetime] finishes an interrupted run at the next start.
  Future<void> _retime(DateTime time, int mono) async {
    final file = File('${_dir.path}/$_unsyncedName');
    if (!await file.exists()) return;
    final parts = <String, IOSink>{};
    var count = 0;
    try {
      await for (final raw in file.openRead().transform(utf8.decoder).transform(const LineSplitter())) {
        try {
          final line = jsonDecode(raw) as Map<String, Object?>;
          final m = line.remove('mono') as int? ?? mono;
          final t = time.subtract(Duration(microseconds: mono - m));
          line['t'] = t.microsecondsSinceEpoch;
          final day = dayName(t);
          (parts[day] ??= File('${_dir.path}/$day.ndjson$_retimePart').openWrite()).writeln(jsonEncode(line));
          count++;
        } on FormatException {
          // truncated line
        } on TypeError {
          // not a telegram line
        }
      }
    } finally {
      for (final sink in parts.values) {
        await sink.flush();
        await sink.close();
      }
    }
    for (final day in parts.keys) {
      await _fsync(File('${_dir.path}/$day.ndjson$_retimePart'));
    }
    await file.rename('${file.path}$_retimedMark');
    await _applyRetimeParts();
    await File('${file.path}$_retimedMark').delete();
    stdout.writeln('Verlauf: $count Telegramme ohne Zeit nachträglich eingeordnet');
  }

  static const _retimePart = '.retime-tmp';
  static const _retimedMark = '.retimed';
  static final _retimeApply = RegExp(r'^(\d{4}-\d{2}-\d{2}\.ndjson)\.retime-(\d+)$');

  /// Step 3 of [_retime], repeatable: a part that was being appended when the
  /// power failed carries the length the daily file had before; the file is cut
  /// back to it and the part appended again.
  Future<void> _applyRetimeParts() async {
    final entries = [
      await for (final e in _dir.list())
        if (e is File) e,
    ]..sort((a, b) => a.path.compareTo(b.path));
    for (final e in entries) {
      final name = e.uri.pathSegments.last;
      var part = e;
      File target;
      int offset;
      final applying = _retimeApply.firstMatch(name);
      if (applying != null) {
        target = File('${_dir.path}/${applying[1]}');
        offset = int.parse(applying[2]!);
        if (await target.exists() && await target.length() > offset) {
          final raf = await target.open(mode: FileMode.append);
          try {
            await raf.truncate(offset);
          } finally {
            await raf.close();
          }
        }
      } else if (name.endsWith('.ndjson$_retimePart')) {
        target = File('${_dir.path}/${name.substring(0, name.length - _retimePart.length)}');
        offset = await target.exists() ? await target.length() : 0;
        // A truncated last line would swallow the first appended one.
        if (await _needsLineBreak(target)) {
          await target.writeAsString('\n', mode: FileMode.append, flush: true);
          offset++;
        }
        part = await e.rename('${target.path}.retime-$offset');
      } else {
        continue;
      }
      final out = target.openWrite(mode: FileMode.append);
      try {
        await out.addStream(part.openRead());
        await out.flush();
      } finally {
        await out.close();
      }
      await _fsync(target);
      await part.delete();
    }
  }

  /// Leftovers of an interrupted [_retime]. With a `.retimed` mark the parts
  /// are complete and are appended now. Without it they are incomplete and
  /// discarded; the source then stays as a section "without time", as after any
  /// restart without a clock.
  Future<void> _recoverRetime() async {
    final marks = [
      await for (final e in _dir.list())
        if (e is File && e.uri.pathSegments.last.endsWith('.ndjson$_retimedMark')) e,
    ];
    if (marks.isEmpty) {
      await for (final e in _dir.list()) {
        final name = e.uri.pathSegments.last;
        if (e is File && (name.endsWith('.ndjson$_retimePart') || _retimeApply.hasMatch(name))) await e.delete();
      }
      return;
    }
    await _applyRetimeParts();
    for (final mark in marks) {
      await mark.delete();
    }
  }

  /// Packs completed days and cleans up according to retention. Runs at
  /// start (catches up on what a crash left behind) and once per hour.
  /// Without a confirmed clock ([timeKnown]) no packing and no retention by
  /// days, only the size limit: with the wrong date, "today" would be packed
  /// early and retention would count from the wrong day.
  Future<void> maintain() => _writing = _writing.then((_) => _maintain()).catchError((Object e) {
    stderr.writeln('Verlauf aufräumen: $e');
  });

  /// Every step on its own: a day that cannot be packed (disk full, broken
  /// `.gz`) must not keep the rest from running, least of all the cleanup that
  /// would make room again.
  Future<void> _maintain() async {
    if (!await _dir.exists()) return;
    final today = dayName(_now());
    Future<void> step(String what, Future<void> Function() run) async {
      try {
        await run();
      } on Object catch (e) {
        stderr.writeln('Verlauf aufräumen ($what): $e');
      }
    }

    await step('Umrechnen abschließen', _recoverRetime);
    await step('Packen abschließen', _recover);
    final known = timeKnown?.call() != false;
    if (known) {
      var files = const <File>[];
      await step('Tage lesen', () async => files = await _dayFiles());
      for (final f in files) {
        final name = f.uri.pathSegments.last;
        if (name.endsWith('.ndjson') && name != '$today.ndjson') await step('$name packen', () => _gzip(f));
      }
    }
    await step('Abschnitte ohne Zeit', _markOrphans);
    await step('Aufbewahrung', () => _prune(today, byAge: known && keepExpired?.call() != true));
    // Measure even without telegrams: the status should show a full disk.
    _freeChecked = null;
    await step('freier Platz', () async => _roomToWrite());
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
    try {
      await lines.transform(gzip.encoder).pipe(tmp.openWrite());
      final raf = await tmp.open(mode: FileMode.append);
      try {
        await raf.flush();
      } finally {
        await raf.close();
      }
    } on Object {
      // Half a `.gz.tmp` only takes the space the next attempt needs.
      try {
        if (await tmp.exists()) await tmp.delete();
      } on FileSystemException {
        // [_recover] removes it at the next run.
      }
      rethrow;
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
    final now = _now().millisecondsSinceEpoch;
    for (final f in await _unsyncedFiles()) {
      final name = f.uri.pathSegments.last;
      if (name == _unsyncedName) continue;
      final m = _unsyncedFile.firstMatch(name)!;
      if (m[2] == null) await f.rename('${_dir.path}/unsynced-${m[1]}-$now.ndjson');
    }
  }

  Future<void> _prune(String today, {required bool byAge}) async {
    final files = await _dayFiles();
    final unsynced = await _unsyncedFiles();
    if (!enabled) {
      // "Off" from settings nobody confirmed deletes nothing.
      if (keepExpired?.call() == true) return;
      for (final f in [...files, ...unsynced]) {
        await f.delete();
      }
      return;
    }
    final now = _now();
    // Without a confirmed clock nothing counts as expired.
    final cutoff = byAge ? dayName(DateTime(now.year, now.month, now.day - (retentionDays - 1))) : '';
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
    final now = _now();
    for (var back = days - 1; back >= 0; back--) {
      final day = dayName(DateTime(now.year, now.month, now.day - back));
      final d = await _dayStats(day);
      if (d == null) continue;
      for (var w = 0; w < 7; w++) {
        for (var h = 0; h < 24; h++) {
          heatmap[w][h] += d.heatmap[w][h];
        }
      }
      d.groups.forEach((k, v) => groups[k] = (groups[k] ?? 0) + v);
      d.senders.forEach((k, v) => senders[k] = (senders[k] ?? 0) + v);
      perDay[day] = d.count;
      total += d.count;
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

  /// Counts of completed days: they no longer change, and a 30-day view would
  /// otherwise unpack every day again (4 s on a Mac with 100,000 telegrams a
  /// day, during which the server answers nothing else). Checked against the
  /// stamp of the `.gz`; concurrent requests for a day share one count.
  final _statsCache = <String, ({String stamp, _DayStats stats})>{};
  final _statsCounting = <String, Future<_DayStats?>>{};

  Future<_DayStats?> _dayStats(String day) async {
    final stamp = await packedDayStamp(day);
    if (stamp == null) return _countDay(day);
    final cached = _statsCache[day];
    if (cached != null && cached.stamp == stamp) return cached.stats;
    final running = _statsCounting[day];
    if (running != null) return running;
    final counting = _countDay(day);
    _statsCounting[day] = counting;
    try {
      final stats = await counting;
      if (stats != null) {
        _statsCache[day] = (stamp: stamp, stats: stats);
        // A year and a bit; older entries belong to deleted days.
        while (_statsCache.length > 400) {
          _statsCache.remove(_statsCache.keys.first);
        }
      }
      return stats;
    } finally {
      // Drops the shared read; whoever awaits it handles its result.
      // ignore: unawaited_futures
      _statsCounting.remove(day);
    }
  }

  Future<_DayStats?> _countDay(String day) async {
    final lines = await dayLines(day);
    if (lines == null) return null;
    final stats = _DayStats();
    await for (final line in lines) {
      // Only the needed fields, without fully decoding each line.
      final t = int.tryParse(field(line, 't') ?? '');
      final d = int.tryParse(field(line, 'd') ?? '');
      if (t == null || d == null) continue;
      final time = DateTime.fromMicrosecondsSinceEpoch(t);
      stats.heatmap[time.weekday - 1][time.hour]++;
      stats.groups[d] = (stats.groups[d] ?? 0) + 1;
      if (!line.contains('"o":true')) {
        final src = int.tryParse(field(line, 's') ?? '');
        if (src != null) stats.senders[src] = (stats.senders[src] ?? 0) + 1;
      }
      stats.count++;
    }
    return stats;
  }

  /// Version of a completed day (only packed, size and time of the `.gz`), for
  /// caches; `null` if the day is still open (plain file) or does not exist.
  Future<String?> packedDayStamp(String day) async {
    final plain = File('${_dir.path}/$day.ndjson');
    final packed = File('${plain.path}.gz');
    if (await plain.exists()) return null;
    final stat = await packed.stat();
    if (stat.type == FileSystemEntityType.notFound) return null;
    return '${stat.size}:${stat.modified.microsecondsSinceEpoch}';
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

/// Longest period `/api/bus/availability` evaluates: availability is kept for
/// a few months, and every month in the period is read line by line.
const availabilityMaxRange = Duration(days: 400);

/// Period of `/api/bus/availability` from the query (`from`, `to` in
/// milliseconds; without them the last day before [now]), or an [error] text
/// for the 400 response: negative, reversed or longer than
/// [availabilityMaxRange] used to cost minutes of CPU.
({String? error, DateTime? from, DateTime? to}) availabilityRange(Map<String, String> q, DateTime now) {
  final from = q.containsKey('from')
      ? int.tryParse(q['from']!)
      : now.subtract(const Duration(days: 1)).millisecondsSinceEpoch;
  final to = q.containsKey('to') ? int.tryParse(q['to']!) : now.millisecondsSinceEpoch;
  if (from == null || to == null || from < 0 || to <= from || to > 8640000000000000) {
    return (error: 'from und to (Millisekunden) fehlen oder sind verdreht.', from: null, to: null);
  }
  if (to - from > availabilityMaxRange.inMilliseconds) {
    return (error: 'Höchstens ${availabilityMaxRange.inDays} Tage.', from: null, to: null);
  }
  return (error: null, from: DateTime.fromMillisecondsSinceEpoch(from), to: DateTime.fromMillisecondsSinceEpoch(to));
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

  /// The bus connection dropped ([reason]) or came back ([reason] `null`), at
  /// once rather than with the next heartbeat: a drop that reconnects within
  /// the minute is otherwise invisible, and only these lines keep the reason
  /// (the journal of a box may be volatile).
  ///
  /// With [tap] the event is about that further tap point (issue #8), not the
  /// bus connection: such a gap is no bus fault and only shows with `taps`.
  Future<void> connectionEvent({String? reason, String? tap, DateTime? now}) async {
    final t = now ?? DateTime.now();
    await _dir.create(recursive: true);
    await File('${_dir.path}/availability-${_month(t)}.ndjson').writeAsString(
      '${jsonEncode({'t': t.millisecondsSinceEpoch, 'e': reason == null ? 'back' : 'lost', 'r': ?reason, 'p': ?tap})}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  /// Outages in the period: stretches without a connection or without
  /// heartbeats (longer than [gap]). Time before the first line counts as unknown.
  /// A drop recorded by [connectionEvent] adds its `reason` to the outage it
  /// falls in, or becomes a short `disconnected` outage of its own. With
  /// [taps] the gaps of further tap points come along as kind `tap` (with
  /// `tap` and `reason`); without it older apps get the list they know.
  Future<List<Map<String, Object?>>> outages(
    DateTime from,
    DateTime to, {
    Duration gap = const Duration(minutes: 3),
    bool taps = false,
  }) async {
    final events = <(DateTime, String?)>[];
    final tapEvents = <(DateTime, String?, String)>[];
    final result = _outages(await _beats(from, to, gap, events: events, tapEvents: tapEvents), to, gap);
    if (taps) result.addAll(_tapGaps(tapEvents, from, to));
    for (var i = 0; i < events.length; i++) {
      final (at, reason) = events[i];
      if (reason == null || at.isBefore(from) || at.isAfter(to)) continue;
      final back = i + 1 < events.length && events[i + 1].$2 == null ? events[i + 1].$1 : at;
      final t0 = at.millisecondsSinceEpoch, t1 = back.millisecondsSinceEpoch;
      final within = result.where(
        (o) => o['kind'] == 'disconnected' && (o['from']! as int) <= t1 && (o['to']! as int) >= t0,
      );
      if (within.isNotEmpty) {
        within.first['reason'] ??= reason;
      } else {
        result.add({'from': t0, 'to': t1, 'kind': 'disconnected', 'reason': reason});
      }
    }
    result.sort((a, b) => (a['from']! as int).compareTo(b['from']! as int));
    return result;
  }

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

  /// Gaps of further tap points from their events: from `lost` to the next
  /// `back` of the same tap point, open ones up to [to] (or now).
  static List<Map<String, Object?>> _tapGaps(List<(DateTime, String?, String)> events, DateTime from, DateTime to) {
    final open = <String, (DateTime, String)>{};
    final out = <Map<String, Object?>>[];
    void close(String tap, DateTime end) {
      final (start, reason) = open.remove(tap)!;
      if (end.isBefore(from) || start.isAfter(to)) return;
      out.add({
        'from': (start.isBefore(from) ? from : start).millisecondsSinceEpoch,
        'to': (end.isAfter(to) ? to : end).millisecondsSinceEpoch,
        'kind': 'tap',
        'tap': tap,
        if (reason.isNotEmpty) 'reason': reason,
      });
    }

    for (final (at, reason, tap) in events) {
      if (reason != null) {
        open.putIfAbsent(tap, () => (at, reason));
      } else if (open.containsKey(tap)) {
        close(tap, at);
      }
    }
    final now = DateTime.now();
    for (final tap in [...open.keys]) {
      close(tap, now.isBefore(to) ? now : to);
    }
    return out;
  }

  Future<List<(DateTime, bool)>> _beats(
    DateTime from,
    DateTime to,
    Duration gap, {
    List<(DateTime, String?)>? events,
    List<(DateTime, String?, String)>? tapEvents,
  }) async {
    final beats = <(DateTime, bool)>[];
    for (var m = DateTime(from.year, from.month); !m.isAfter(to); m = DateTime(m.year, m.month + 1)) {
      final f = File('${_dir.path}/availability-${_month(m)}.ndjson');
      if (!await f.exists()) continue;
      for (final line in await f.readAsLines()) {
        try {
          final j = jsonDecode(line) as Map<String, Object?>;
          final t = DateTime.fromMillisecondsSinceEpoch(j['t']! as int);
          if (t.isBefore(from.subtract(gap)) || t.isAfter(to.add(gap))) continue;
          // Event lines (connectionEvent) are no heartbeats.
          if (j['e'] case final String e) {
            final reason = e == 'lost' ? (j['r'] as String? ?? '') : null;
            if (j['p'] case final String tap) {
              tapEvents?.add((t, reason, tap));
            } else {
              events?.add((t, reason));
            }
            continue;
          }
          beats.add((t, j['c'] == true));
        } on Object {
          // truncated line
        }
      }
    }
    beats.sort((a, b) => a.$1.compareTo(b.$1));
    events?.sort((a, b) => a.$1.compareTo(b.$1));
    tapEvents?.sort((a, b) => a.$1.compareTo(b.$1));
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

/// Counts of one day for [Recorder.stats].
class _DayStats {
  final heatmap = List.generate(7, (_) => List.filled(24, 0));
  final groups = <int, int>{};
  final senders = <int, int>{};
  var count = 0;
}

/// Number of telegrams recorded on [day] below [dataPath] before [beforeMicros]
/// (0 if the day does not exist). Top level so that [Isolate.run] only captures
/// the texts and the number; the server counts the running day with it after a
/// restart.
Future<int> countDayBefore(String dataPath, String day, int beforeMicros) async {
  final lines = await Recorder(Directory(dataPath)).dayLines(day);
  if (lines == null) return 0;
  var count = 0;
  await for (final line in lines) {
    final t = int.tryParse(Recorder.field(line, 't') ?? '');
    if (t != null && t < beforeMicros) count++;
  }
  return count;
}
