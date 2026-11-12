/// Health check on the server (add-on, Docker, box), without an open app: the rules of the app's
/// health check (`lib/model/health.dart`) that work from recorded traffic and the project alone.
///
/// Off unless switched on: add-on option `health_check`, `HEALTH_CHECK=true` for Docker and the
/// box. With it on, `POST /api/ha/health/run` runs the check and returns the result,
/// `GET /api/ha/health` returns the last one (ha_integration.dart), and [ServerHealthCheck.tick]
/// runs it once a day at a quiet hour.
///
/// **Nothing goes on the bus.** The check only reads the history and the project; it has no way
/// to the bus connection at all. The rules of the app that need read requests (who answers a
/// read, who fell silent) are not part of it.
///
/// What it reads, as the app does: the recorded days of today and yesterday ([HealthScan]). The
/// addresses that stopped sending come from the server's own check for them ([CycleWatch], seven
/// days of history, the same rule of package:knx as the app's, with the server's longer minimum
/// silence and without the time the recording did not cover), so the health check and the
/// integration's "stopped sending" repairs never disagree. The
/// days are read in a separate isolate, line by line, with only the fields a rule needs; what is
/// kept per sender and address is bounded ([HealthScan.maxKeys]), and so is the number of lines
/// ([ServerHealthCheck.maxLines]) and of findings in the result ([ServerHealthCheck.maxFindings]).
///
/// The result carries no sentences: each finding has a kind, a severity, the address or device
/// with its name from the project, numbers, and `text`, the key of the app's sentence for it
/// (`lib/l10n/app_*.arb`) that clients translate. See docs/health-check.md.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:knx/knx.dart';

import 'atomic_file.dart';
import 'bus.dart';
import 'cycle_watch.dart';
import 'dali.dart';
import 'dpt_value.dart';
import 'project_lint.dart';
import 'recorder.dart';

/// Kinds of findings, named as the app's `FindingKind` (there in camel case).
enum HealthKind {
  /// Measured value outside the plausible range.
  outOfRange('out_of_range', 'readings', 'error', 'healthOutOfRange'),

  /// Payload length does not match the datapoint type of the group address.
  dptSize('dpt_size', 'dpt', 'error', 'healthDptSize'),

  /// DALI: luminaires behind a gateway report a lamp failure.
  lampFault('lamp_fault', 'lighting', 'error', 'daliHealthLampFault', device: true),

  /// DALI: control gear or converters behind a gateway report a failure.
  gearFault('gear_fault', 'lighting', 'error', 'daliHealthGearFault', device: true),

  /// Usually sends regularly, but has been silent much longer than usual.
  overdue('overdue', 'cycle', 'warning', 'healthOverdue'),

  /// Cyclic measured value has not changed for many hours.
  stuck('stuck', 'readings', 'warning', 'healthStuck'),

  /// Value is invalid for the datapoint type (0x7FFF for DPT 9, say).
  dptValue('dpt_value', 'dpt', 'warning', 'healthDptValue'),

  /// Address without a datapoint type; senders send values of different lengths.
  mixedSizes('mixed_sizes', 'dpt', 'warning', 'healthMixedSizes'),

  /// Sender repeats conspicuously often (missing acknowledgements).
  repeats('repeats', 'bus', 'warning', 'healthRepeats', device: true),

  /// Read requests from other devices go unanswered.
  unansweredReads('unanswered_reads', 'bus', 'info', 'healthUnansweredReads');

  const HealthKind(this.id, this.area, this.severity, this.text, {this.device = false});

  /// Name in the result (`kind`).
  final String id;

  /// `readings`, `dpt`, `cycle`, `bus` or `lighting`, as the app's `HealthArea`.
  final String area;

  /// `error`, `warning` or `info`.
  final String severity;

  /// Key of the app's sentence for this kind (`lib/l10n/app_de.arb`).
  final String text;

  /// Whether the finding names a device (individual address) instead of a group address.
  final bool device;

  int get rank => switch (severity) {
    'error' => 2,
    'warning' => 1,
    _ => 0,
  };
}

/// Expected payload length per DPT main group; 0 = value in the APCI (at most 6 bits). The same
/// table as `expectedSize` in the app (lib/model/analysis.dart).
int? healthExpectedSize(int main) => switch (main) {
  1 || 2 || 3 => 0,
  4 || 5 || 6 || 17 || 18 || 20 || 21 || 23 || 26 || 238 => 1,
  7 || 8 || 9 || 22 || 237 || 244 => 2,
  10 || 11 || 232 => 3,
  12 || 13 || 14 || 15 => 4,
  245 || 251 => 6,
  19 || 29 => 8,
  16 => 14,
  _ => null,
};

/// Plausible range per measured quantity; `null` = no check. The same table as `plausibleRange`
/// in the app (lib/model/health.dart).
(double, double)? healthPlausibleRange((int, int?) dpt) => switch (dpt) {
  (9, 1) => (-30, 60), // temperature °C
  (9, 4) => (0, 200000), // brightness lx
  (9, 5) => (0, 60), // wind m/s
  (9, 7) => (0, 100), // humidity %
  (9, 8) => (0, 10000), // CO₂ ppm
  (9, 28) => (0, 220), // wind km/h
  _ => null,
};

/// Values that are invalid for their datapoint type, as `_invalidValue` in the app: the
/// "invalid" marker of DPT 9, an HVAC mode above 4, a scene number above 63.
bool _invalidValue((int, int?) dpt, List<int> d, {required bool small}) => switch ((dpt.$1, small ? 0 : d.length)) {
  (9, 2) => d[0] == 0x7F && d[1] == 0xFF,
  (20, 1) when dpt.$2 == 102 => d[0] > 4,
  (17, 1) => d[0] > 63,
  _ => false,
};

/// The rules over recorded telegrams, fed line by line ([add]) and closed with [finish].
///
/// Thresholds as in the app:
/// - `out_of_range`: the newest value of a temperature, brightness, wind, humidity or CO₂
///   address lies outside [healthPlausibleRange].
/// - `stuck`: temperature or humidity with at least [stuckMinTelegrams] telegrams in the last
///   [stuckWindow] that span at least [stuckMinSpan] and all carry the same value.
/// - `dpt_size`, `dpt_value`: per group address and sender.
/// - `mixed_sizes`: an address of the project without a datapoint type gets several lengths.
/// - `repeats`: a sender with at least [repeatsMinTelegrams] telegrams of which at least
///   [repeatsMinRate] are repeated.
/// - `unanswered_reads`: at least [unansweredMin] read requests to an address from other
///   devices without a response within [readTimeout].
///
/// Anyone on the bus can send anything from any sender address, so nothing here grows without
/// bound: at most [maxKeys] pairs of address and sender per rule; [truncated] tells that more
/// came.
class HealthScan {
  HealthScan(this.catalog, {required this.now, this.maxKeys = 8192});

  final LintCatalog catalog;
  final DateTime now;
  final int maxKeys;

  static const stuckWindow = Duration(hours: 24);
  static const stuckMinSpan = Duration(hours: 12);
  static const stuckMinTelegrams = 12;
  static const repeatsMinTelegrams = 20;
  static const repeatsMinRate = 0.05;
  static const unansweredMin = 2;
  static const readTimeout = Duration(seconds: 3);

  /// Telegrams taken in.
  int telegrams = 0;

  /// Whether a bound was hit, so some findings may be missing.
  bool truncated = false;

  late final _nowMicros = now.microsecondsSinceEpoch;

  // (GA << 16 | sender) → [length, count, last time µs]
  final _wrongSize = <int, List<int>>{};
  // (GA << 16 | sender) → (payload hex, count, time µs of the kept payload)
  final _badValue = <int, (String, int, int)>{};
  // GA without DPT → length → a sender
  final _sizesNoDpt = <int, Map<int, int>>{};
  // sender → [telegrams, repeated]
  final _senders = <int, List<int>>{};
  // GA → open read requests (time µs, negative for our own)
  final _openReads = <int, List<int>>{};
  final _unanswered = <int, int>{};
  // GA → newest value
  final _latest = <int, ({int time, double value, int source})>{};
  // GA (temperature, humidity) → the last [stuckWindow]
  final _series = <int, _Series>{};

  /// One history line (`Telegram.toJson()` of package:knx), read without decoding all of it.
  void add(String line) {
    final t = int.tryParse(Recorder.field(line, 't') ?? '');
    final s = int.tryParse(Recorder.field(line, 's') ?? '');
    final d = int.tryParse(Recorder.field(line, 'd') ?? '');
    final y = int.tryParse(Recorder.field(line, 'y') ?? '');
    if (t == null || s == null || d == null || y == null) return;
    const mark = '"x":"';
    final i = line.indexOf(mark);
    final end = i < 0 ? -1 : line.indexOf('"', i + mark.length);
    addTelegram(
      time: t,
      source: s,
      destination: d,
      type: y,
      payload: end < 0 ? '' : line.substring(i + mark.length, end),
      small: line.contains('"m":true'),
      outgoing: line.contains('"o":true'),
      repeated: line.contains('"rp":true'),
    );
  }

  /// One telegram: [time] in µs, [type] 0 read, 1 response, 2 write, [payload] as hex.
  void addTelegram({
    required int time,
    required int source,
    required int destination,
    required int type,
    String payload = '',
    bool small = false,
    bool outgoing = false,
    bool repeated = false,
  }) {
    telegrams++;
    if (!outgoing) {
      final sender = _senders[source] ??= [0, 0];
      sender[0]++;
      if (repeated) sender[1]++;
    }
    if (type == 0) {
      final open = _openReads[destination] ??= [];
      // Whatever is older than the timeout can no longer be answered.
      _settle(destination, open, time);
      open.add(outgoing ? -time : time);
      return;
    }
    if (type == 1) {
      final open = _openReads.remove(destination);
      if (open != null) {
        for (final r in open) {
          if (r > 0 && time - r > readTimeout.inMicroseconds) _countUnanswered(destination);
        }
      }
    }
    final group = catalog.groups[destination];
    if (group == null) return;
    final data = hexBytes(payload);
    final actual = small ? 0 : data.length;
    final dpt = group.dpt;
    if (dpt == null) {
      (_sizesNoDpt[destination] ??= {})[actual] = source;
      return;
    }
    final expected = healthExpectedSize(dpt.$1);
    final key = destination << 16 | source;
    if (expected != null && expected != actual) {
      final old = _wrongSize[key];
      if (old != null) {
        old[0] = actual;
        old[1]++;
        if (time > old[2]) old[2] = time;
      } else if (_wrongSize.length < maxKeys) {
        _wrongSize[key] = [actual, 1, time];
      } else {
        truncated = true;
      }
    } else if (_invalidValue(dpt, data, small: small)) {
      final old = _badValue[key];
      if (old != null) {
        _badValue[key] = time >= old.$3 ? (payload, old.$2 + 1, time) : (old.$1, old.$2 + 1, old.$3);
      } else if (_badValue.length < maxKeys) {
        _badValue[key] = (payload, 1, time);
      } else {
        truncated = true;
      }
    }
    if (healthPlausibleRange(dpt) == null) return;
    final value = numericValue(dpt, data, small: small);
    if (value == null) return;
    final previous = _latest[destination];
    if (previous == null || time >= previous.time) {
      _latest[destination] = (time: time, value: value, source: source);
    }
    if ((dpt.$2 == 1 || dpt.$2 == 7) && _nowMicros - time <= stuckWindow.inMicroseconds) {
      (_series[destination] ??= _Series(time, value)).add(time, value);
    }
  }

  void _settle(int destination, List<int> open, int time) {
    open.removeWhere((r) {
      if (time - r.abs() <= readTimeout.inMicroseconds) return false;
      if (r > 0) _countUnanswered(destination);
      return true;
    });
  }

  void _countUnanswered(int destination) => _unanswered[destination] = (_unanswered[destination] ?? 0) + 1;

  /// The findings, most severe first. [overdue] are the addresses that stopped sending
  /// (`[address, last µs, interval s]`, from [CycleWatch]), [dali] the luminaires in a fault per
  /// gateway (`[gateway, lamp faults, gear faults]`, from [DaliWatch]).
  List<Map<String, Object?>> finish({List<List<int>> overdue = const [], List<List<int>> dali = const []}) {
    for (final MapEntry(key: ga, value: open) in _openReads.entries) {
      _settle(ga, open, _nowMicros);
    }
    _openReads.clear();

    String iso(int micros) => DateTime.fromMicrosecondsSinceEpoch(micros).toUtc().toIso8601String();
    Map<String, Object?> base(HealthKind kind, int address) => {
      'kind': kind.id,
      'severity': kind.severity,
      'area': kind.area,
      'text': kind.text,
      if (kind.device) ...{
        'device': formatIndividual(address),
        'name': _deviceName(address),
      } else ...{
        'address': formatGroupAddress(address, catalog.style),
        'name': _groupName(address),
      },
    };
    Map<String, Object?> sender(int source) => {'source': formatIndividual(source), 'source_name': _deviceName(source)};
    String? dptText(int ga) => switch (catalog.groups[ga]?.dpt) {
      final d? => Dpt(d.$1, d.$2).toString(),
      null => null,
    };
    String? unit(int ga) => switch (catalog.groups[ga]?.dpt) {
      final d? => switch (dptUnit(Dpt(d.$1, d.$2))) {
        '' => null,
        final u => u,
      },
      null => null,
    };

    final found = <(HealthKind, int, int, Map<String, Object?>)>[];
    void put(HealthKind kind, int address, int source, Map<String, Object?> details) =>
        found.add((kind, address, source, {...base(kind, address), ...details}));

    for (final [address, last, interval] in overdue) {
      put(HealthKind.overdue, address, 0, {'since': iso(last), 'interval_s': interval});
    }
    for (final MapEntry(key: ga, value: latest) in _latest.entries) {
      final dpt = catalog.groups[ga]!.dpt!;
      final (lo, hi) = healthPlausibleRange(dpt)!;
      if (latest.value < lo || latest.value > hi) {
        put(HealthKind.outOfRange, ga, latest.source, {
          'value': _round(latest.value),
          'unit': unit(ga),
          'since': iso(latest.time),
          ...sender(latest.source),
        });
        continue;
      }
      final series = _series[ga];
      if (series == null || series.count < stuckMinTelegrams) continue;
      if (series.last - series.first >= stuckMinSpan.inMicroseconds && series.same) {
        put(HealthKind.stuck, ga, 0, {'value': _round(latest.value), 'unit': unit(ga), 'since': iso(series.first)});
      }
    }
    for (final MapEntry(:key, value: [actual, count, time]) in _wrongSize.entries) {
      final ga = key >> 16, source = key & 0xFFFF;
      put(HealthKind.dptSize, ga, source, {
        ...sender(source),
        'actual': actual,
        'expected': healthExpectedSize(catalog.groups[ga]!.dpt!.$1),
        'dpt': dptText(ga),
        'count': count,
        'since': iso(time),
      });
    }
    for (final MapEntry(:key, value: (payload, count, time)) in _badValue.entries) {
      final ga = key >> 16, source = key & 0xFFFF;
      put(HealthKind.dptValue, ga, source, {
        ...sender(source),
        'raw': payload,
        'dpt': dptText(ga),
        'count': count,
        'since': iso(time),
      });
    }
    for (final MapEntry(key: ga, value: sizes) in _sizesNoDpt.entries) {
      if (sizes.length > 1) put(HealthKind.mixedSizes, ga, 0, {'count': sizes.length});
    }
    for (final MapEntry(key: source, value: [count, repeated]) in _senders.entries) {
      if (count >= repeatsMinTelegrams && repeated / count >= repeatsMinRate) {
        put(HealthKind.repeats, source, 0, {
          'rate': double.parse((repeated / count).toStringAsFixed(4)),
          'count': count,
        });
      }
    }
    for (final MapEntry(key: ga, value: n) in _unanswered.entries) {
      if (n >= unansweredMin) put(HealthKind.unansweredReads, ga, 0, {'count': n});
    }
    for (final [gateway, lamp, gear] in dali) {
      if (lamp > 0) put(HealthKind.lampFault, gateway, 0, {'count': lamp});
      if (gear > 0) put(HealthKind.gearFault, gateway, 0, {'count': gear});
    }
    // Most severe first; then by kind, address and sender, so two runs over the same history
    // give the same list.
    found.sort((a, b) {
      var c = b.$1.rank.compareTo(a.$1.rank);
      if (c == 0) c = a.$1.index.compareTo(b.$1.index);
      if (c == 0) c = a.$2.compareTo(b.$2);
      return c == 0 ? a.$3.compareTo(b.$3) : c;
    });
    return [for (final f in found) f.$4];
  }

  String? _groupName(int ga) => switch (catalog.groups[ga]?.name.trim()) {
    final String n when n.isNotEmpty => n,
    _ => null,
  };

  String? _deviceName(int pa) => switch (catalog.devices[pa]?.name.trim()) {
    final String n when n.isNotEmpty => n,
    _ => null,
  };

  static double _round(double v) => double.parse(v.toStringAsFixed(2));
}

/// What "stuck" needs of the last 24 hours of an address, whatever the order of the lines.
class _Series {
  _Series(this.first, this.value) : last = first;

  int first;
  int last;
  final double value;
  int count = 0;
  bool same = true;

  void add(int time, double v) {
    count++;
    if (time < first) first = time;
    if (time > last) last = time;
    if (v != value) same = false;
  }
}

/// What [scanHealth] needs; only plain values, so [Isolate.run] can take it along.
class HealthScanInput {
  const HealthScanInput({
    required this.dataPath,
    required this.days,
    required this.nowMicros,
    this.overdue = const [],
    this.dali = const [],
    this.maxLines = ServerHealthCheck.maxLines,
    this.maxKeys = 8192,
    this.maxFindings = ServerHealthCheck.maxFindings,
  });

  /// Data folder of the installation (history and `catalog.json`).
  final String dataPath;

  /// Days to read (`YYYY-MM-DD`), newest first.
  final List<String> days;
  final int nowMicros;
  final List<List<int>> overdue;
  final List<List<int>> dali;
  final int maxLines;
  final int maxKeys;
  final int maxFindings;
}

/// Reads the project and the [HealthScanInput.days] of the history and applies the rules. Top
/// level so that [Isolate.run] captures nothing but the input. The newest day comes first: if
/// the bound on lines is hit, what is left out is the oldest. The counts cover every finding, the
/// list only the first [HealthScanInput.maxFindings]: the caller's isolate gets a small answer.
Future<Map<String, Object?>> scanHealth(HealthScanInput input) async {
  final data = Directory(input.dataPath);
  final catalog = await LintCatalog.load(data);
  final scan = HealthScan(catalog, now: DateTime.fromMicrosecondsSinceEpoch(input.nowMicros), maxKeys: input.maxKeys);
  final recorder = Recorder(data);
  var lines = 0;
  var daysRead = 0;
  days:
  for (final day in input.days) {
    final stream = await recorder.dayLines(day);
    if (stream == null) continue;
    daysRead++;
    await for (final line in stream) {
      if (++lines > input.maxLines) {
        scan.truncated = true;
        break days;
      }
      scan.add(line);
    }
  }
  final findings = scan.finish(overdue: input.overdue, dali: input.dali);
  final byKind = <String, int>{};
  final bySeverity = {'error': 0, 'warning': 0, 'info': 0};
  for (final f in findings) {
    byKind[f['kind']! as String] = (byKind[f['kind']] ?? 0) + 1;
    bySeverity[f['severity']! as String] = (bySeverity[f['severity']] ?? 0) + 1;
  }
  return {
    'findings': findings.take(input.maxFindings).toList(),
    'counts': {
      'total': findings.length,
      'errors': bySeverity['error'],
      'warnings': bySeverity['warning'],
      'infos': bySeverity['info'],
      'by_kind': byKind,
    },
    'telegrams': scan.telegrams,
    'days': daysRead,
    'project': !catalog.isEmpty,
    'truncated': scan.truncated || findings.length > input.maxFindings,
  };
}

/// The health check of the active installation: one run at a time, the last result kept in
/// `health_check.json` of the installation, a run a day at [quietHour].
class ServerHealthCheck {
  ServerHealthCheck(
    this.currentBus, {
    required this.enabled,
    required this.cycles,
    this.quietHour = 3,
    DateTime Function() clock = DateTime.now,
    Future<Map<String, Object?>> Function(HealthScanInput input)? scan,
  }) : _clock = clock,
       _scan = scan ?? _scanInIsolate;

  /// Bus of the active installation (changes with the installation).
  final BusService Function() currentBus;

  /// Whether the feature is switched on (add-on option `health_check`, `HEALTH_CHECK=true`).
  final bool enabled;

  /// Source of the `overdue` findings: the server's own "stopped sending" check.
  final CycleWatch cycles;

  /// Local hour of the daily run: the bus is quiet, and so is the box.
  final int quietHour;

  final DateTime Function() _clock;
  final Future<Map<String, Object?>> Function(HealthScanInput input) _scan;

  /// Name of the add-on option and of the environment variable, for the "not enabled" answer.
  static const option = 'health_check';
  static const variable = 'HEALTH_CHECK';

  /// Format version of the result.
  static const formatVersion = 1;

  /// Most history lines one run reads: ten times a very full bus (100,000 telegrams a day)
  /// over the two days it looks at. Beyond that the oldest lines are left out.
  static const maxLines = 2000000;

  /// Most findings in a result; the counts still cover all of them.
  static const maxFindings = 200;

  /// Runs started so far (for tests).
  int runs = 0;

  BusService? _bus;
  Map<String, Object?>? _last;
  Future<Map<String, Object?>>? _running;

  static Future<Map<String, Object?>> _scanInIsolate(HealthScanInput input) => Isolate.run(() => scanHealth(input));

  File _file(BusService bus) => File('${bus.data.path}/health_check.json');

  /// Whether [value] from the add-on options or the environment switches the feature on.
  static bool parseEnabled(Object? value) => switch (value) {
    final bool on => on,
    final String text => const {'true', '1', 'yes', 'on'}.contains(text.trim().toLowerCase()),
    _ => false,
  };

  /// Loads the last result of the active installation (start, other installation).
  Future<void> load() async {
    final bus = currentBus();
    if (identical(bus, _bus)) return;
    Map<String, Object?>? last;
    try {
      final json = jsonDecode(await _file(bus).readAsString());
      if (json is Map<String, Object?> && json['format'] == formatVersion && json['time'] is String) last = json;
    } on Object {
      // Missing or damaged: no result yet, the next run writes a new one.
    }
    if (!identical(bus, currentBus())) return;
    _bus = bus;
    _last = last;
  }

  /// The last result of the active installation; without one only `enabled` and empty fields.
  Map<String, Object?> last() {
    final last = identical(_bus, currentBus()) ? _last : null;
    return {
      'enabled': enabled,
      'running': _running != null,
      ...last ?? const {'status': null, 'time': null, 'counts': null, 'findings': <Object?>[]},
    };
  }

  /// For `GET /api/ha/state` and the app's data export page: on or off, state and time of the
  /// last run and its counts, without the findings.
  Map<String, Object?> summary() {
    final last = identical(_bus, currentBus()) ? _last : null;
    return {
      'enabled': enabled,
      if (enabled) ...{'status': last?['status'], 'time': last?['time'], 'counts': last?['counts']},
    };
  }

  /// Runs the check now; a call during a run waits for that run and gets its result.
  Future<Map<String, Object?>> run({String trigger = 'manual'}) {
    if (!enabled) throw StateError('health check is not enabled');
    return _running ??= _run(trigger).whenComplete(() => _running = null);
  }

  Future<Map<String, Object?>> _run(String trigger) async {
    runs++;
    final bus = currentBus();
    final started = _clock();
    final watch = Stopwatch()..start();
    // Lines in the buffer count too.
    await bus.recorder.flush();
    var overdue = const <CycleSilence>[];
    try {
      // The hourly result of the "stopped sending" check, kept current by every telegram
      // (CycleWatch.observe). Reading seven days again for each run would only cost time; a
      // check of its own is needed only before the first hourly one.
      if (!cycles.checked) await cycles.check();
      overdue = cycles.reported();
    } on Object catch (e) {
      stderr.writeln('Gesundheitsprüfung: Schweige-Prüfung: $e');
    }
    final yesterday = DateTime(started.year, started.month, started.day - 1);
    final scanned = await _scan(
      HealthScanInput(
        dataPath: bus.data.path,
        days: [Recorder.dayName(started), Recorder.dayName(yesterday)],
        nowMicros: started.microsecondsSinceEpoch,
        overdue: [
          for (final s in overdue) [s.address, s.last.microsecondsSinceEpoch, s.interval.inSeconds],
        ],
        dali: bus.dali.faultCounts(),
      ),
    );
    final counts = (scanned['counts']! as Map).cast<String, Object?>();
    final result = <String, Object?>{
      'format': formatVersion,
      'status': (counts['errors']! as int) > 0
          ? 'faults'
          : counts['total'] == 0
          ? 'ok'
          : 'hints',
      'time': started.toUtc().toIso8601String(),
      'duration_ms': watch.elapsedMilliseconds,
      'trigger': trigger,
      // No rule that sends read requests is part of this check.
      'read_test': false,
      'recording': bus.config.enabled,
      'project': scanned['project'],
      'days': scanned['days'],
      'telegrams': scanned['telegrams'],
      'truncated': scanned['truncated'] == true,
      'counts': counts,
      'findings': scanned['findings'],
    };
    try {
      await writeAtomic(_file(bus), text: jsonEncode(result));
    } on Object catch (e) {
      stderr.writeln('Gesundheitsprüfung: Ergebnis nicht gespeichert: $e');
    }
    if (identical(bus, currentBus())) {
      _bus = bus;
      _last = result;
    }
    return {'enabled': true, 'running': false, ...result};
  }

  /// Whether a scheduled run is due at [now]: never run, the last run older than a day, or
  /// [quietHour] has passed since it.
  static bool due(DateTime now, DateTime? last, {int quietHour = 3}) {
    if (last == null) return true;
    if (now.difference(last) >= const Duration(hours: 24)) return true;
    var mark = DateTime(now.year, now.month, now.day, quietHour);
    if (mark.isAfter(now)) mark = DateTime(now.year, now.month, now.day - 1, quietHour);
    return last.isBefore(mark);
  }

  /// Called every minute (ha_integration.dart): starts the daily run when it is [due]. Returns
  /// whether a run was started; it finishes in the background.
  Future<bool> tick() async {
    if (!enabled || _running != null) return false;
    await load();
    final time = DateTime.tryParse(_last?['time'] as String? ?? '')?.toLocal();
    if (!due(_clock(), time, quietHour: quietHour)) return false;
    unawaited(
      run(trigger: 'schedule').then<void>((_) {}, onError: (Object e) => stderr.writeln('Gesundheitsprüfung: $e')),
    );
    return true;
  }

  /// Waits for a run in progress (tests, shutdown).
  Future<void> get idle async {
    try {
      await _running;
    } on Object {
      // The caller of the run gets the error.
    }
  }
}

/// Luminaires in a fault per gateway from the keys of [DaliWatch] (`<gateway>:<address>`, groups
/// `<gateway>:g<group>` do not count): `[gateway, lamp faults, gear or converter faults]`.
List<List<int>> daliFaultCounts(Map<String, int> faults) {
  final counts = <int, List<int>>{};
  for (final MapEntry(:key, value: bits) in faults.entries) {
    final parts = key.split(':');
    if (parts.length != 2 || parts[1].startsWith('g')) continue;
    final gateway = int.tryParse(parts[0]);
    if (gateway == null || bits == 0) continue;
    final c = counts[gateway] ??= [gateway, 0, 0];
    if (bits & DaliFault.lamp != 0) c[1]++;
    if (bits & (DaliFault.gear | DaliFault.converter) != 0) c[2]++;
  }
  return counts.values.toList();
}
