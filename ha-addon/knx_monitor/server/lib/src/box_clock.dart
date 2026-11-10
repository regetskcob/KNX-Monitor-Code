import 'dart:convert';
import 'dart:io';

/// Where the box gets its time from, in ascending order of trust.
enum ClockSource {
  /// No reliable time since start (no internet, no RTC).
  none,

  /// Battery-backed real-time clock (Pi 5) or DS3231 (Pi 4).
  rtc,

  /// Time master on the KNX line (DPT 19.001 or 10.001 + 11.001).
  knx,

  /// Clock of the connecting iPhone/iPad.
  client,

  /// Internet (chrony with an NTP source).
  ntp,
}

/// Clock of the Busclear Box (`BOX=1`), see docs/knx-box.md, section "Time without an RTC".
///
/// The server must not set the system time. It puts the request into
/// [requestFile]; on the host, `knx-box-time.service` then sets chrony and the
/// RTC. Until that takes effect, [now] applies the correction itself, so no
/// telegram is stamped with the old time.
///
/// Rules for an offered time ([offer]):
/// - Clock unreliable: set immediately.
/// - Deviation below [tolerance]: do nothing.
/// - Otherwise only if the source is more trustworthy than the previous one
///   and deviates by at most [maxAutoStep], or if the app explicitly asks for
///   it (`force`). Otherwise the deviation is reported.
class BoxClock {
  BoxClock({
    this.requestFile,
    Future<ClockSource> Function()? probe,
    DateTime Function()? system,
    Stopwatch? monotonic,
    this.tolerance = const Duration(seconds: 2),
    this.maxAutoStep = const Duration(minutes: 15),
  }) : _probe = probe ?? probeSystemClock,
       _system = system ?? DateTime.now,
       _mono = monotonic ?? (Stopwatch()..start());

  /// Time request to the host; `null` where the clock cannot be set.
  final File? requestFile;
  final Future<ClockSource> Function() _probe;
  final DateTime Function() _system;
  final Stopwatch _mono;
  final Duration tolerance;
  final Duration maxAutoStep;

  ClockSource source = ClockSource.none;
  DateTime? setAt;

  /// Last reported, unapplied deviation per source (ms, + = box is behind).
  final offsets = <ClockSource, int>{};

  /// Called when the clock was set: new time and monotonic counter at the
  /// same instant (for converting recordings made without a reliable time).
  void Function(DateTime time, int monoMicros)? onSet;

  /// Time that was set, as long as the host has not yet updated the system clock.
  ({DateTime time, int mono})? _anchor;

  bool get synced => source != ClockSource.none;

  /// Microseconds since start, independent of time jumps.
  int get monoMicros => _mono.elapsedMicroseconds;

  Future<void> init() async {
    try {
      source = await _probe();
    } on Object catch (e) {
      stderr.writeln('Uhr prüfen: $e');
    }
  }

  /// Current time of the box, with the correction until the system clock is right.
  DateTime now() {
    final real = _system();
    final anchor = _anchor;
    if (anchor == null) return real;
    final expected = anchor.time.add(Duration(microseconds: monoMicros - anchor.mono));
    if (real.difference(expected).abs() < tolerance) {
      _anchor = null; // The host has set it.
      return real;
    }
    return expected;
  }

  /// Offers a time from [from]. Result: `set`, `ok`, `differs` or
  /// `unsupported` (no host that can set the clock).
  Future<String> offer(DateTime time, ClockSource from, {bool force = false}) async {
    final diff = time.difference(now());
    if (synced && diff.abs() < tolerance) {
      offsets.remove(from);
      if (from.index > source.index) source = from;
      return 'ok';
    }
    final allowed = !synced || force || (from.index > source.index && diff.abs() <= maxAutoStep);
    if (!allowed) {
      offsets[from] = diff.inMilliseconds;
      return 'differs';
    }
    if (requestFile == null) return 'unsupported';
    final mono = monoMicros;
    await requestFile!.writeAsString(jsonEncode({'epochMs': time.millisecondsSinceEpoch}), flush: true);
    _anchor = (time: time, mono: mono);
    source = from;
    setAt = time;
    offsets.remove(from);
    onSet?.call(time, mono);
    return 'set';
  }

  Map<String, Object?> status() => {
    'source': source.name,
    'synced': synced,
    'time': now().millisecondsSinceEpoch,
    if (setAt != null) 'setAt': setAt!.millisecondsSinceEpoch,
    'settable': requestFile != null,
    if (offsets.isNotEmpty) 'offsets': {for (final e in offsets.entries) e.key.name: e.value},
  };
}

/// Asks chrony and the RTC: internet time, battery clock or nothing.
Future<ClockSource> probeSystemClock() async {
  try {
    // CSV: ref ID, name, stratum, …, leap status (last field).
    final r = await Process.run('chronyc', ['-c', 'tracking']);
    if (r.exitCode == 0) {
      final f = (r.stdout as String).trim().split(',');
      final stratum = f.length > 2 ? int.tryParse(f[2]) ?? 0 : 0;
      if (f.length > 3 &&
          f[0] != '00000000' &&
          f[0] != '7F7F0101' &&
          stratum >= 1 &&
          stratum < 16 &&
          f.last == 'Normal') {
        return ClockSource.ntp;
      }
    }
  } on Object {
    // chrony is missing (development): continue with the RTC.
  }
  try {
    final rtc = Directory('/sys/class/rtc/rtc0');
    if (await rtc.exists()) {
      final seconds = int.tryParse((await File('${rtc.path}/since_epoch').readAsString()).trim()) ?? 0;
      // An empty RTC counts from 1970 or 2000.
      if (seconds > 1735689600) return ClockSource.rtc;
    }
  } on Object {
    // no RTC
  }
  return ClockSource.none;
}

/// Detects time masters on the line and offers their time to the [clock].
///
/// - DPT 19.001 (date and time, 8 bytes): with a project immediately; without
///   a project only once two telegrams of the same address are consistent
///   with each other (8 bytes can also be something else).
/// - DPT 10.001 + 11.001 (time, date, 3 bytes each): only with a project,
///   otherwise too easily confused with RGB or counters.
///
/// KNX time is local time without a zone; calculations use the server's zone
/// (`TZ`, Europe/Berlin on the box).
class KnxTimeWatch {
  KnxTimeWatch(this.clock, {required this.dptOf, this.enabled = true});

  final BoxClock clock;

  /// Main datapoint type of a group address from the project, otherwise `null`.
  final int? Function(int group) dptOf;
  bool enabled;

  /// Last candidate without a project: address, time, monotonic counter.
  ({int group, DateTime time, int mono})? _pending;

  /// Last date (DPT 11) with monotonic counter.
  ({DateTime date, int mono})? _date;

  /// Group address with time, or date and time, from the project, to request
  /// on connect.
  int? timeGroup(Iterable<int> groups) {
    int? time;
    for (final g in groups) {
      final dpt = dptOf(g);
      if (dpt == 19) return g;
      if (dpt == 10) time ??= g;
    }
    return time;
  }

  /// Checks a telegram line (same format as in the history).
  Future<void> observe(Map<String, Object?> line) async {
    if (!enabled) return;
    final type = line['y'];
    if (type != 1 && type != 2) return; // only response and write
    final group = line['d'] as int?;
    final hex = line['x'] as String?;
    if (group == null || hex == null || line['m'] == true) return;
    final bytes = _bytes(hex);
    final dpt = dptOf(group);
    final mono = clock.monoMicros;
    if (bytes.length == 8 && (dpt == 19 || dpt == null)) {
      final time = parseDateTime19(bytes);
      if (time == null) return;
      if (dpt == 19) return _offer(time);
      final pending = _pending;
      _pending = (group: group, time: time, mono: mono);
      if (pending == null || pending.group != group) return;
      // Does the gap between the times match the gap on the box (±3 s)?
      final expected = pending.time.add(Duration(microseconds: mono - pending.mono));
      if (time.difference(expected).abs() <= const Duration(seconds: 3)) await _offer(time);
    } else if (bytes.length == 3 && dpt == 11) {
      final date = parseDate11(bytes);
      if (date != null) _date = (date: date, mono: mono);
    } else if (bytes.length == 3 && dpt == 10) {
      final date = _date;
      final t = parseTime10(bytes);
      if (date == null || t == null || mono - date.mono > const Duration(hours: 24).inMicroseconds) return;
      await _offer(DateTime(date.date.year, date.date.month, date.date.day, t.$1, t.$2, t.$3));
    }
  }

  Future<void> _offer(DateTime time) async {
    final result = await clock.offer(time, ClockSource.knx);
    if (result == 'set') stdout.writeln('Busclear Box: Uhr vom KNX-Zeitgeber gestellt ($time)');
  }

  static List<int> _bytes(String hex) => [
    for (var i = 0; i + 1 < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}

/// DPT 19.001 as local time, `null` for invalid fields or fields marked as
/// missing (fault, no year, no date, no time).
DateTime? parseDateTime19(List<int> b) {
  if (b.length != 8) return null;
  final flags = b[6];
  // F (fault), NY (no year), ND (no date), NT (no time)
  if (flags & 0x80 != 0 || flags & 0x10 != 0 || flags & 0x08 != 0 || flags & 0x02 != 0) return null;
  final year = 1900 + b[0];
  final month = b[1] & 0x0F;
  final day = b[2] & 0x1F;
  final hour = b[3] & 0x1F;
  final minute = b[4] & 0x3F;
  final second = b[5] & 0x3F;
  if (year < 2025 || year > 2100 || month < 1 || month > 12 || day < 1 || day > 31) return null;
  if (hour > 23 || minute > 59 || second > 59) return null;
  final t = DateTime(year, month, day, hour, minute, second);
  return t.day == day ? t : null; // Feb 31 or similar
}

/// DPT 10.001: hour, minute, second.
(int, int, int)? parseTime10(List<int> b) {
  if (b.length != 3) return null;
  final h = b[0] & 0x1F, m = b[1] & 0x3F, s = b[2] & 0x3F;
  return h > 23 || m > 59 || s > 59 ? null : (h, m, s);
}

/// DPT 11.001: date (year < 90 → 20xx).
DateTime? parseDate11(List<int> b) {
  if (b.length != 3) return null;
  final day = b[0] & 0x1F, month = b[1] & 0x0F, y = b[2] & 0x7F;
  final year = y < 90 ? 2000 + y : 1900 + y;
  if (year < 2025 || month < 1 || month > 12 || day < 1 || day > 31) return null;
  final d = DateTime(year, month, day);
  return d.day == day ? d : null;
}
