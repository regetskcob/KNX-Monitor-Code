import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'alarms.dart';
import 'http.dart';

import 'package:knx/knx.dart';

import 'outbound.dart';
import 'recorder.dart';

/// Installation report on the box and the add-on (#108).
///
/// Off by default. When enabled, the server condenses every completed day into
/// a small daily summary (`reports/days/<day>.json`) once per hour, because
/// the history often holds only a few days, while a report reaches back a
/// quarter. After a month or quarter ends, the daily summaries become
/// `reports/<period>.json`; the app produces the texts and the PDF.
///
/// None of this may disturb continuous operation: condensing runs in its own
/// isolate, [ReportService.tick] never throws, and an error only shows up in
/// the status.
class ReportSettings {
  ReportSettings({
    this.enabled = false,
    this.period = monthly,
    this.since,
    this.notifyKind = 'off',
    this.notifyUrl = '',
    this.notifyTopic = '',
    this.notifyToken = '',
    this.notifyReady = true,
    this.notifyUrgent = true,
    this.maintenanceDue,
  });

  static const monthly = 'monthly';
  static const quarterly = 'quarterly';
  static const notifyKinds = {'off', 'ntfy', 'webhook', 'homeassistant'};

  bool enabled;
  String period;

  /// When it was enabled: earlier periods get no automatic report because
  /// the data for them is missing.
  DateTime? since;

  /// Target of the notifications; `off` until the user picks one.
  String notifyKind;
  String notifyUrl;
  String notifyTopic;

  /// Credentials of the target. They never leave the server (see [toJson]).
  String notifyToken;
  bool notifyReady;
  bool notifyUrgent;

  /// Next maintenance date from the app's customer record; only the date, the
  /// customer data stays on the device.
  DateTime? maintenanceDue;

  factory ReportSettings.fromJson(Map<String, Object?> j) => ReportSettings(
    enabled: j['enabled'] == true,
    period: j['period'] == quarterly ? quarterly : monthly,
    since: _time(j['since']),
    notifyKind: notifyKinds.contains(j['notifyKind']) ? j['notifyKind']! as String : 'off',
    notifyUrl: j['notifyUrl'] as String? ?? '',
    notifyTopic: j['notifyTopic'] as String? ?? '',
    notifyToken: j['notifyToken'] as String? ?? '',
    notifyReady: j['notifyReady'] != false,
    notifyUrgent: j['notifyUrgent'] != false,
    maintenanceDue: _time(j['maintenanceDue']),
  );

  static DateTime? _time(Object? v) => v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;

  Map<String, Object?> toJson({bool secrets = true}) => {
    'enabled': enabled,
    'period': period,
    'since': since?.millisecondsSinceEpoch,
    'notifyKind': notifyKind,
    'notifyUrl': notifyUrl,
    'notifyTopic': notifyTopic,
    if (secrets) 'notifyToken': notifyToken else 'hasNotifyToken': notifyToken.isNotEmpty,
    'notifyReady': notifyReady,
    'notifyUrgent': notifyUrgent,
    'maintenanceDue': maintenanceDue?.millisecondsSinceEpoch,
  };
}

/// Period of a report: `[from, to)`.
class ReportPeriod {
  const ReportPeriod(this.id, this.from, this.to);
  final String id;
  final DateTime from;
  final DateTime to;

  static ReportPeriod containing(DateTime t, String kind) {
    if (kind == ReportSettings.quarterly) {
      final q = (t.month - 1) ~/ 3;
      return ReportPeriod('${t.year}-Q${q + 1}', DateTime(t.year, q * 3 + 1), DateTime(t.year, q * 3 + 4));
    }
    return ReportPeriod(
      '${t.year}-${t.month.toString().padLeft(2, '0')}',
      DateTime(t.year, t.month),
      DateTime(t.year, t.month + 1),
    );
  }

  /// The most recently completed period.
  static ReportPeriod lastComplete(DateTime t, String kind) {
    final current = containing(t, kind);
    return containing(current.from.subtract(const Duration(days: 1)), kind);
  }
}

// --- Daily summary ---------------------------------------------------------------

/// Bus occupancy of a telegram in seconds: the formula of `BusLoad` in the
/// app (`lib/knx/busmon.dart`, 9600 bit/s), plus the acknowledgement. [x] is
/// the payload as hex; [small] a value in the APCI.
double busySeconds(String x, {required bool small}) {
  // Control field, source, destination, length, TPCI/APCI, payload, checksum.
  final bytes = small ? 9 : 9 + x.length ~/ 2;
  return (50 + 13 * bytes + 15 + 13) / 9600;
}

/// Condenses the day [day] (`YYYY-MM-DD`); `null` if there is neither
/// history nor heartbeats for it. Runs in its own isolate.
Future<Map<String, Object?>?> computeDayRollup(String dataPath, String day) async {
  final data = Directory(dataPath);
  final lines = await Recorder(data).dayLines(day);
  final beats = await _dayBeats(data, day);
  if (lines == null && beats == null) return null;
  final hours = List.filled(24, 0);
  final hourBusy = <int, List<double>>{};
  final senders = <int, List<int>>{}; // n, repetitions, last (ms)
  final groups = <int, List<Object>>{}; // n, last (ms), last value, changes
  var total = 0;
  var busy = 0.0;
  if (lines != null) {
    await for (final raw in lines) {
      final Map<String, Object?> t;
      try {
        t = jsonDecode(raw) as Map<String, Object?>;
      } on Object {
        continue; // truncated line
      }
      final micros = t['t'];
      final d = t['d'];
      final s = t['s'];
      if (micros is! int || d is! int || s is! int) continue;
      final time = DateTime.fromMicrosecondsSinceEpoch(micros);
      final ms = micros ~/ 1000;
      total++;
      hours[time.hour]++;
      final x = t['x'] as String? ?? '';
      final frame = busySeconds(x, small: t['m'] == true);
      busy += frame;
      (hourBusy[s >> 8] ??= List.filled(24, 0.0))[time.hour] += frame;
      if (t['o'] != true) {
        final sender = senders[s] ??= [0, 0, 0];
        sender[0]++;
        if (t['rp'] == true) sender[1]++;
        if (ms > sender[2]) sender[2] = ms;
      }
      if (t['y'] != 0) {
        final group = groups[d];
        if (group == null) {
          groups[d] = [1, ms, x, 0];
        } else {
          group[0] = (group[0] as int) + 1;
          if (ms >= (group[1] as int)) {
            group[1] = ms;
            if (group[2] != x) {
              group[2] = x;
              group[3] = (group[3] as int) + 1;
            }
          }
        }
      }
    }
  }
  Map<String, Object?>? busmon;
  try {
    final file = File('$dataPath/status/busmon-$day.json');
    if (await file.exists()) busmon = (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>();
  } on Object {
    // The day is still usable without these counters.
  }
  var peak = 0.0;
  final perHour = List.filled(24, 0.0);
  final perLine = <String, List<double>>{};
  hourBusy.forEach((line, values) {
    var lineBusy = 0.0;
    var linePeak = 0.0;
    for (var h = 0; h < 24; h++) {
      lineBusy += values[h];
      perHour[h] += values[h];
      if (values[h] > linePeak) linePeak = values[h];
    }
    perLine['$line'] = [lineBusy, linePeak];
  });
  for (final v in perHour) {
    if (v > peak) peak = v;
  }
  return {
    'v': 1,
    'day': day,
    'n': total,
    'h': hours,
    'busy': busy,
    'peak': peak,
    'lines': perLine,
    's': {for (final e in senders.entries) '${e.key}': e.value},
    'g': {for (final e in groups.entries) '${e.key}': e.value},
    'busmon': ?busmon,
    ...?beats,
  };
}

/// A separate function so the isolate only captures the two texts.
Future<Map<String, Object?>?> _rollupInIsolate(String path, String day) =>
    Isolate.run(() => computeDayRollup(path, day));

/// Heartbeats of a day: count, how many connected, first and last, outages
/// including the gap before the first and after the last.
Future<Map<String, Object?>?> _dayBeats(Directory data, String day) async {
  final start = DateTime.parse(day);
  final end = DateTime(start.year, start.month, start.day + 1);
  final month = day.substring(0, 7);
  final file = File('${data.path}/status/availability-$month.ndjson');
  if (!await file.exists()) return null;
  final beats = <(int, bool)>[];
  for (final line in await file.readAsLines()) {
    try {
      final j = jsonDecode(line) as Map<String, Object?>;
      final t = j['t']! as int;
      if (t >= start.millisecondsSinceEpoch && t < end.millisecondsSinceEpoch) beats.add((t, j['c'] == true));
    } on Object {
      // truncated line
    }
  }
  if (beats.isEmpty) return null;
  beats.sort((a, b) => a.$1.compareTo(b.$1));
  const gap = 3 * 60 * 1000;
  final outages = <Map<String, Object?>>[];
  void add(int from, int to, String kind) {
    if (outages.isNotEmpty && outages.last['kind'] == kind && outages.last['to'] == from) {
      outages.last['to'] = to;
    } else {
      outages.add({'from': from, 'to': to, 'kind': kind});
    }
  }

  if (beats.first.$1 - start.millisecondsSinceEpoch > gap) {
    add(start.millisecondsSinceEpoch, beats.first.$1, 'offline');
  }
  for (var i = 1; i < beats.length; i++) {
    final (prev, prevConnected) = beats[i - 1];
    final (t, connected) = beats[i];
    if (t - prev > gap) {
      add(prev, t, 'offline');
    } else if (!connected || !prevConnected) {
      add(prev, t, 'disconnected');
    }
  }
  if (end.millisecondsSinceEpoch - beats.last.$1 > gap) add(beats.last.$1, end.millisecondsSinceEpoch, 'offline');
  return {
    'beats': beats.length,
    'conn': beats.where((b) => b.$2).length,
    'first': beats.first.$1,
    'last': beats.last.$1,
    'out': outages,
  };
}

// --- Report ----------------------------------------------------------------------

/// What the report needs to know about the project (default: [AlarmWatch]).
abstract class ReportCatalog {
  String formatGroup(int group);
  String? nameOf(int group);
  (int, int?)? dptOf(int group);
  String? kindOf(int group);
  String searchTextOf(int group);
  Iterable<int> get groups;
}

class _AlarmCatalog implements ReportCatalog {
  _AlarmCatalog(this.alarms);
  final AlarmWatch alarms;
  @override
  String formatGroup(int group) => alarms.formatGroup(group);
  @override
  String? nameOf(int group) => alarms.nameOf(group);
  @override
  (int, int?)? dptOf(int group) => alarms.dptOf(group);
  @override
  String? kindOf(int group) => alarms.kindOf(group);
  @override
  String searchTextOf(int group) => alarms.searchTextOf(group);
  @override
  Iterable<int> get groups => alarms.groups;
}

final _batteryWords = RegExp(r'batterie|battery|akku');
final _inverseWords = RegExp(r'\b(ok|okay|gut|normal|good)\b');

/// How far reports look back to detect "usually sends regularly".
const reportLookback = Duration(days: 92);

/// Builds the report from daily summaries; pure and thus testable without a bus.
///
/// [rollups]: daily summaries from [period].from minus [reportLookback].
/// [restarts]: unexpected restarts in the period. [previous]: the previous
/// report, for "new, resolved, unchanged".
Map<String, Object?> buildInstallationReport({
  required ReportPeriod period,
  required String kind,
  required List<Map<String, Object?>> rollups,
  required ReportCatalog catalog,
  required DateTime now,
  Map<String, Object?>? previous,
  List<Map<String, Object?>> restarts = const [],
  DateTime? maintenanceDue,
  bool partial = false,
}) {
  final sorted = [...rollups]..sort((a, b) => (a['day']! as String).compareTo(b['day']! as String));
  final fromDay = Recorder.dayName(period.from);
  final end = partial && now.isBefore(period.to) ? now : period.to;
  final endDay = Recorder.dayName(end.subtract(const Duration(milliseconds: 1)));
  final inPeriod = [
    for (final r in sorted)
      if ((r['day']! as String).compareTo(fromDay) >= 0 && (r['day']! as String).compareTo(endDay) <= 0) r,
  ];
  final totalDays = _daysBetween(period.from, end);

  // Availability: combine outages per day; days without any heartbeat between
  // two days with heartbeats count as "not running".
  final outages = <Map<String, Object?>>[];
  void addOutage(int from, int to, String kind) {
    final clippedFrom = from < period.from.millisecondsSinceEpoch ? period.from.millisecondsSinceEpoch : from;
    final clippedTo = to > end.millisecondsSinceEpoch ? end.millisecondsSinceEpoch : to;
    if (clippedTo <= clippedFrom) return;
    if (outages.isNotEmpty && outages.last['kind'] == kind && outages.last['to'] == clippedFrom) {
      outages.last['to'] = clippedTo;
    } else {
      outages.add({'from': clippedFrom, 'to': clippedTo, 'kind': kind});
    }
  }

  final withBeats = [
    for (final r in inPeriod)
      if (r['beats'] != null) r,
  ];
  // Only days with heartbeats before this one count: before that the report did not apply yet.
  final knownBefore = sorted.any((r) => r['beats'] != null && (r['day']! as String).compareTo(fromDay) < 0);
  DateTime? previousDay;
  for (final (i, r) in withBeats.indexed) {
    final day = DateTime.parse(r['day']! as String);
    if (previousDay != null) {
      for (
        var d = DateTime(previousDay.year, previousDay.month, previousDay.day + 1);
        d.isBefore(day);
        d = DateTime(d.year, d.month, d.day + 1)
      ) {
        addOutage(d.millisecondsSinceEpoch, DateTime(d.year, d.month, d.day + 1).millisecondsSinceEpoch, 'offline');
      }
    }
    previousDay = day;
    for (final o in (r['out'] as List? ?? const []).cast<Map<String, Object?>>()) {
      final leading = i == 0 && !knownBefore && o['from'] == day.millisecondsSinceEpoch;
      if (!leading) addOutage(o['from']! as int, o['to']! as int, o['kind']! as String);
    }
  }
  final firstKnown = withBeats.isEmpty ? null : withBeats.first['first']! as int;
  final startKnown = knownBefore ? period.from.millisecondsSinceEpoch : firstKnown;
  final covered = startKnown == null ? 0 : end.millisecondsSinceEpoch - startKnown;
  final outageMs = outages.fold<int>(0, (a, o) => a + (o['to']! as int) - (o['from']! as int));
  final availability = covered <= 0 ? null : (1 - outageMs / covered).clamp(0.0, 1.0);

  // Traffic and bus load
  var total = 0;
  var busy = 0.0;
  var peakLoad = 0.0;
  String? peakDay;
  var peakDayCount = 0;
  ({String day, int hour, int n})? peakHour;
  final perDay = <String, int>{};
  final senderTotals = <int, List<int>>{};
  final lineTotals = <int, List<double>>{};
  for (final r in inPeriod) {
    final n = r['n'] as int? ?? 0;
    final day = r['day']! as String;
    total += n;
    perDay[day] = n;
    busy += (r['busy'] as num? ?? 0).toDouble();
    final peak = (r['peak'] as num? ?? 0).toDouble();
    if (peak > peakLoad) peakLoad = peak;
    if (n > peakDayCount) {
      peakDayCount = n;
      peakDay = day;
    }
    final hours = (r['h'] as List? ?? const []).cast<int>();
    for (final (h, value) in hours.indexed) {
      if (peakHour == null || value > peakHour.n) peakHour = (day: day, hour: h, n: value);
    }
    (r['s'] as Map? ?? const {}).forEach((key, value) {
      final v = (value as List).cast<int>();
      final sum = senderTotals[int.parse(key as String)] ??= [0, 0];
      sum[0] += v[0];
      sum[1] += v[1];
    });
    (r['lines'] as Map? ?? const {}).forEach((key, value) {
      final v = (value as List).cast<num>();
      final sum = lineTotals[int.parse(key as String)] ??= [0, 0];
      sum[0] += v[0].toDouble();
      if (v[1].toDouble() > sum[1]) sum[1] = v[1].toDouble();
    });
  }
  final seconds = covered > 0 ? covered / 1000 : inPeriod.length * 86400.0;
  double load(double busy) => seconds <= 0 ? 0 : (busy / seconds).clamp(0.0, 1.0);

  final findings = <Map<String, Object?>>[];
  void finding(
    String kind,
    String level,
    int? address, {
    String? name,
    String? label,
    int? since,
    num? rate,
    int? count,
    String? value,
  }) => findings.add({
    'key': '$kind${address == null ? '' : ':$address'}',
    'kind': kind,
    'level': level,
    'address': ?address,
    'label': ?label,
    'name': ?name,
    'since': ?since,
    'rate': ?rate,
    'count': ?count,
    'value': ?value,
  });

  // Devices and cyclic senders: activity over the whole lookback.
  final activeBySender = <int, List<(String, int)>>{};
  final activeByGroup = <int, List<(String, List<Object?>)>>{};
  for (final r in sorted) {
    final day = r['day']! as String;
    if (day.compareTo(endDay) > 0) continue;
    (r['s'] as Map? ?? const {}).forEach((key, value) {
      final v = (value as List).cast<int>();
      if (v[0] > 0) (activeBySender[int.parse(key as String)] ??= []).add((day, v[2]));
    });
    (r['g'] as Map? ?? const {}).forEach((key, value) {
      (activeByGroup[int.parse(key as String)] ??= []).add((day, (value as List).cast<Object?>()));
    });
  }
  // Days on which the server was really listening: a switched-off box is not
  // a silent device.
  final listenedDays = <String>{
    for (final r in sorted)
      if (((r['conn'] as int?) ?? (r['n'] as int?) ?? 0) > 0) r['day']! as String,
  };
  int listenedAfter(String day) => listenedDays.where((d) => d.compareTo(day) > 0 && d.compareTo(endDay) <= 0).length;

  activeBySender.forEach((address, days) {
    if (days.length < 3) return;
    final gaps = [
      for (var i = 1; i < days.length; i++) _daysBetween(DateTime.parse(days[i - 1].$1), DateTime.parse(days[i].$1)),
    ]..sort();
    final median = gaps[gaps.length ~/ 2];
    final limit = median * 3 > 3 ? median * 3 : 3;
    if (listenedAfter(days.last.$1) >= limit) {
      finding('deviceSilent', 'warning', address, label: formatIndividual(address), since: days.last.$2);
    }
  });
  activeByGroup.forEach((address, days) {
    if (days.length < 3) return;
    final counts = [for (final d in days) d.$2[0]! as int]..sort();
    // Sends at least every 6 hours on average, like the app's `cycleFindings`.
    if (counts[counts.length ~/ 2] >= 4 && listenedAfter(days.last.$1) >= 2) {
      finding(
        'cyclicSilent',
        'warning',
        address,
        label: catalog.formatGroup(address),
        name: catalog.nameOf(address),
        since: days.last.$2[1]! as int,
      );
    }
    // Sends a measurement (temperature, humidity) but has not changed for days.
    final dpt = catalog.dptOf(address);
    if (dpt != null && dpt.$1 == 9 && (dpt.$2 == 1 || dpt.$2 == 7) && days.length >= 3) {
      final recent = days.sublist(days.length - 3);
      final fresh = listenedAfter(recent.last.$1) == 0;
      if (fresh && recent.every((d) => (d.$2[0]! as int) >= 12 && d.$2[3] == 0) && recent[0].$2[2] == recent[2].$2[2]) {
        finding(
          'stuck',
          'warning',
          address,
          label: catalog.formatGroup(address),
          name: catalog.nameOf(address),
          since: DateTime.parse(recent.first.$1).millisecondsSinceEpoch,
          value: recent.last.$2[2] as String?,
        );
      }
    }
  });

  final repeats = <Map<String, Object?>>[];
  senderTotals.forEach((address, sum) {
    if (sum[1] == 0) return;
    final rate = sum[1] / sum[0];
    repeats.add({
      'address': address,
      'label': formatIndividual(address),
      'count': sum[0],
      'repeats': sum[1],
      'rate': rate,
    });
    if (sum[0] >= 20 && rate >= 0.05) {
      finding('repeats', 'warning', address, label: formatIndividual(address), rate: rate, count: sum[0]);
    }
  });
  repeats.sort((a, b) => (b['rate']! as double).compareTo(a['rate']! as double));

  if (peakLoad / 3600 >= 0.3) finding('busLoad', 'warning', null, rate: peakLoad / 3600);
  if (availability != null && availability < 0.99) {
    finding('outages', 'warning', null, rate: availability, count: outages.length);
  }
  // Only with the KNX HAT in bus monitor mode: what really went wrong on the bus.
  final busmon = <String, int>{};
  for (final r in inPeriod) {
    (r['busmon'] as Map? ?? const {}).forEach((key, value) {
      if (value is int) busmon[key as String] = (busmon[key] ?? 0) + value;
    });
  }
  final frames = (busmon['data'] ?? 0) + (busmon['damaged'] ?? 0);
  final faults = (busmon['naks'] ?? 0) + (busmon['damaged'] ?? 0);
  if (frames >= 100 && faults / frames >= 0.01) {
    finding('busErrors', 'warning', null, rate: faults / frames, count: faults);
  }
  if (restarts.isNotEmpty) finding('restarts', 'warning', null, count: restarts.length);

  // Smoke detectors, faults, batteries: last known state from the project.
  final safety = <Map<String, Object?>>[];
  for (final group in catalog.groups) {
    final alarmKind = catalog.kindOf(group);
    final text = catalog.searchTextOf(group);
    final battery = _batteryWords.hasMatch(text);
    if (alarmKind == null && !battery) continue;
    final seen = activeByGroup[group];
    final last = seen?.last.$2;
    final hex = last?[2] as String?;
    final state = hex == null || hex.isEmpty ? 'unknown' : _safetyState(catalog, group, hex, text, battery: battery);
    final kind = battery ? 'battery' : alarmKind!;
    safety.add({
      'address': group,
      'label': catalog.formatGroup(group),
      'name': ?catalog.nameOf(group),
      'kind': kind,
      'state': state,
      'last': ?last?[1],
    });
    if (state == 'active') {
      finding(
        switch (kind) {
          'alarm' => 'alarmActive',
          'fault' => 'faultActive',
          _ => 'batteryLow',
        },
        kind == 'battery' ? 'warning' : 'critical',
        group,
        label: catalog.formatGroup(group),
        name: catalog.nameOf(group),
        since: last?[1] as int?,
      );
    }
  }

  // Comparison with the previous report.
  final before = <String, Map<String, Object?>>{
    for (final f in (previous?['findings'] as List? ?? const []).cast<Map<String, Object?>>()) f['key']! as String: f,
  };
  for (final f in findings) {
    f['status'] = previous == null
        ? 'first'
        : before.containsKey(f['key'])
        ? 'unchanged'
        : 'new';
  }
  final keys = {for (final f in findings) f['key']};
  final resolved = [
    for (final e in before.entries)
      if (!keys.contains(e.key)) {...e.value, 'status': 'resolved'},
  ];
  findings.sort((a, b) => _levelRank(b['level']).compareTo(_levelRank(a['level'])));

  final topSenders = senderTotals.entries.toList()..sort((a, b) => b.value[0].compareTo(a.value[0]));
  final lines = lineTotals.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  return {
    'version': 1,
    'id': period.id,
    'period': kind,
    'from': period.from.millisecondsSinceEpoch,
    'to': end.millisecondsSinceEpoch,
    'generated': now.millisecondsSinceEpoch,
    if (partial) 'partial': true,
    'coverage': {'days': inPeriod.length, 'total': totalDays},
    'availability': {'ratio': ?availability, 'outages': outages, 'restarts': restarts},
    'traffic': {
      'total': total,
      'perDay': perDay,
      'avgPerDay': inPeriod.isEmpty ? 0 : total ~/ inPeriod.length,
      'peakDay': ?peakDay,
      'peakDayCount': peakDayCount,
      if (peakHour != null && peakHour.n > 0) 'peakHour': {'day': peakHour.day, 'hour': peakHour.hour, 'n': peakHour.n},
      'topSenders': [
        for (final e in topSenders.take(10)) {'address': e.key, 'label': formatIndividual(e.key), 'count': e.value[0]},
      ],
    },
    'load': {
      'average': load(busy),
      'peak': (peakLoad / 3600).clamp(0.0, 1.0),
      'lines': [
        for (final e in lines)
          {
            'line': '${e.key >> 4}.${e.key & 0xF}',
            'average': load(e.value[0]),
            'peak': (e.value[1] / 3600).clamp(0.0, 1.0),
          },
      ],
    },
    'repeats': repeats.take(20).toList(),
    if (busmon.isNotEmpty) 'busmon': busmon,
    'safety': safety,
    'findings': findings,
    'resolved': resolved,
    'maintenanceDue': ?maintenanceDue?.millisecondsSinceEpoch,
  };
}

int _levelRank(Object? level) => switch (level) {
  'critical' => 2,
  'warning' => 1,
  _ => 0,
};

int _daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// State of a safety object from its last value: `active`, `ok` or
/// `unknown`. For batteries the meaning can only be read from the name
/// ("Battery OK" is inverted) and estimated as a percentage.
String _safetyState(ReportCatalog catalog, int group, String hex, String text, {required bool battery}) {
  final value = hex.length < 2 ? null : int.tryParse(hex.substring(0, 2), radix: 16);
  if (value == null) return 'unknown';
  final dpt = catalog.dptOf(group);
  if (dpt?.$1 == 21 && !battery) return value & 0x1A != 0 ? 'active' : 'ok';
  if (battery && dpt?.$1 == 5) return value * 100 / 255 < 20 ? 'active' : 'ok';
  if (dpt != null && dpt.$1 != 1) return 'unknown';
  final on = value & 0x01 == 1;
  if (battery && _inverseWords.hasMatch(text)) return on ? 'ok' : 'active';
  return on ? 'active' : 'ok';
}

// --- Service ---------------------------------------------------------------------

/// Schedules daily summaries, reports and notifications for an installation.
class ReportService {
  ReportService(
    this.data, {
    required this.recorder,
    required AlarmWatch alarms,
    required this.language,
    DateTime Function()? now,
    bool Function()? timeKnown,
    this.homeAssistant,
    this.restarts,
    ReportCatalog? catalog,
    void Function(String message)? log,
  }) : _alarms = alarms,
       catalog = catalog ?? _AlarmCatalog(alarms),
       _now = now ?? DateTime.now,
       _timeKnown = timeKnown ?? (() => true),
       _log = log ?? stderr.writeln;

  final Directory data;
  final Recorder recorder;
  final AlarmWatch _alarms;
  final ReportCatalog catalog;
  final String Function() language;
  final DateTime Function() _now;
  final bool Function() _timeKnown;
  final void Function(String message) _log;

  /// Notification via Home Assistant; `null` outside the add-on.
  final Future<bool> Function({required String id, required String title, required String message})? homeAssistant;

  /// Unexpected restarts in the period (see `CrashWatch`).
  final Future<List<Map<String, Object?>>> Function(DateTime from, DateTime to)? restarts;

  ReportSettings settings = ReportSettings();

  /// Last run and last error, without addresses and credentials.
  DateTime? lastRun;
  String? lastError;
  DateTime? lastNotified;
  String? lastNotifyError;

  /// Daily summaries reach back at most this far (enough for an annual report).
  static const keepDays = 400;

  /// Condensing catches up this far on what is still in the history.
  static const backfillDays = 40;

  static const keepReports = 60;

  File get _settingsFile => File('${data.path}/report_settings.json');
  Directory get _dir => Directory('${data.path}/reports');
  Directory get _days => Directory('${data.path}/reports/days');
  File get _stateFile => File('${data.path}/reports/state.json');

  bool _running = false;

  /// Loads the settings. Corrupt file: everything off instead of guessing.
  Future<void> load() async {
    try {
      if (await _settingsFile.exists()) {
        settings = ReportSettings.fromJson(jsonDecode(await _settingsFile.readAsString()) as Map<String, Object?>);
      }
    } on Object catch (_) {
      _log('report_settings.json nicht lesbar – Bericht bleibt aus');
      settings = ReportSettings();
    }
  }

  Future<void> _save() async {
    final tmp = File('${_settingsFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await tmp.rename(_settingsFile.path);
  }

  /// Applies changes from the app; throws [FormatException] for an invalid
  /// target (then everything stays as it was). An empty token means
  /// "unchanged", `clearToken` deletes it.
  Future<void> update(Map<String, Object?> changes) async {
    final merged = settings.toJson()..addAll(changes);
    if (changes['notifyToken'] == '' || !changes.containsKey('notifyToken')) {
      merged['notifyToken'] = settings.notifyToken;
    }
    if (changes['clearToken'] == true) merged['notifyToken'] = '';
    final next = ReportSettings.fromJson(merged);
    if (next.notifyKind == 'ntfy' || next.notifyKind == 'webhook') {
      if (parseOutboundTarget(next.notifyUrl) == null) throw const FormatException('notifyUrl');
      if (next.notifyKind == 'ntfy' && !validNtfyTopic(next.notifyTopic)) throw const FormatException('notifyTopic');
    }
    if (next.notifyKind == 'homeassistant' && homeAssistant == null) throw const FormatException('notifyKind');
    if (next.enabled && !settings.enabled) next.since = _now();
    if (!next.enabled) next.since = null;
    settings = next;
    await _save();
  }

  /// The hourly run. Never throws: a report must not disturb recording.
  Future<void> tick() async {
    if (!settings.enabled || _running || !_timeKnown()) return;
    _running = true;
    try {
      final now = _now();
      // Also waits for packing in progress, and yesterday's last lines must be
      // in the file before the day is condensed.
      await recorder.flush();
      await _alarms.loadCatalog();
      await _rollupMissing(now);
      await _reportIfDue(now);
      await _dailyChecks(now);
      await _prune(now);
      lastRun = now;
      lastError = null;
    } on Object catch (e) {
      // Only the kind: paths and addresses do not belong in the status.
      lastError = e.runtimeType.toString();
      _log('Anlagenbericht: $e');
    } finally {
      _running = false;
    }
  }

  Future<void> _rollupMissing(DateTime now) async {
    await _days.create(recursive: true);
    final path = data.path;
    for (var back = 1; back <= backfillDays; back++) {
      final day = Recorder.dayName(DateTime(now.year, now.month, now.day - back));
      final file = File('${_days.path}/$day.json');
      if (await file.exists()) continue;
      final rollup = await _rollupInIsolate(path, day);
      if (rollup == null) continue;
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(rollup), flush: true);
      await tmp.rename(file.path);
    }
  }

  Future<List<Map<String, Object?>>> _loadRollups(DateTime from, DateTime to) async {
    final result = <Map<String, Object?>>[];
    if (!await _days.exists()) return result;
    final first = Recorder.dayName(from.subtract(reportLookback));
    final last = Recorder.dayName(to);
    await for (final e in _days.list()) {
      final name = e.uri.pathSegments.last;
      if (e is! File || !name.endsWith('.json') || name.length != 15) continue;
      final day = name.substring(0, 10);
      if (day.compareTo(first) < 0 || day.compareTo(last) > 0) continue;
      try {
        result.add(jsonDecode(await e.readAsString()) as Map<String, Object?>);
      } on Object {
        _log('Tagessumme $day nicht lesbar');
      }
    }
    return result;
  }

  Future<Map<String, Object?>?> _read(File f) async {
    try {
      return await f.exists() ? jsonDecode(await f.readAsString()) as Map<String, Object?> : null;
    } on Object {
      return null;
    }
  }

  File _reportFile(String id) => File('${_dir.path}/$id.json');

  Future<void> _reportIfDue(DateTime now) async {
    final period = ReportPeriod.lastComplete(now, settings.period);
    final since = settings.since;
    // First the period that ends after enabling.
    if (since != null && period.to.isBefore(since)) return;
    final existing = await _read(_reportFile(period.id));
    if (existing != null && existing['partial'] != true) return;
    final report = await generate(period);
    if (settings.notifyReady) {
      final count = (report['findings'] as List).length;
      await _notify('ready', _text('ready', {'period': period.id, 'n': '$count'}), period: period.id);
    }
  }

  /// Builds the report for [period]; `null` = the current period up to now
  /// ("Create now", stays marked as interim).
  Future<Map<String, Object?>> generate(ReportPeriod? period) async {
    final now = _now();
    final partial = period == null;
    final p = period ?? ReportPeriod.containing(now, settings.period);
    await _alarms.loadCatalog();
    final rollups = await _loadRollups(p.from, p.to);
    if (partial) {
      // Today has not been condensed yet.
      await recorder.flush();
      final path = data.path;
      final day = Recorder.dayName(now);
      final today = await _rollupInIsolate(path, day);
      if (today != null) rollups.add(today);
    }
    final previous = await _previousReport(p);
    final report = buildInstallationReport(
      period: p,
      kind: settings.period,
      rollups: rollups,
      catalog: catalog,
      now: now,
      previous: previous,
      restarts: await restarts?.call(p.from, partial ? now : p.to) ?? const [],
      maintenanceDue: settings.maintenanceDue,
      partial: partial,
    );
    await _dir.create(recursive: true);
    final file = _reportFile(p.id);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(report), flush: true);
    await tmp.rename(file.path);
    return report;
  }

  Future<Map<String, Object?>?> _previousReport(ReportPeriod p) async {
    Map<String, Object?>? best;
    for (final report in await list()) {
      if (report['partial'] == true || (report['to']! as int) > p.from.millisecondsSinceEpoch) continue;
      if (best == null || (report['to']! as int) > (best['to']! as int)) best = report;
    }
    return best == null ? null : _read(_reportFile(best['id']! as String));
  }

  /// Reports, newest first, without details.
  Future<List<Map<String, Object?>>> list() async {
    final result = <Map<String, Object?>>[];
    if (!await _dir.exists()) return result;
    await for (final e in _dir.list()) {
      final name = e.uri.pathSegments.last;
      if (e is! File || !_reportName.hasMatch(name)) continue;
      final r = await _read(e);
      if (r == null) continue;
      final findings = (r['findings'] as List? ?? const []).cast<Map<String, Object?>>();
      result.add({
        'id': r['id'],
        'period': r['period'],
        'from': r['from'],
        'to': r['to'],
        'generated': r['generated'],
        if (r['partial'] == true) 'partial': true,
        'findings': findings.length,
        'critical': findings.where((f) => f['level'] == 'critical').length,
        'new': findings.where((f) => f['status'] == 'new').length,
        'resolved': (r['resolved'] as List? ?? const []).length,
      });
    }
    result.sort((a, b) => (b['to']! as int).compareTo(a['to']! as int));
    return result;
  }

  static final _reportName = RegExp(r'^\d{4}-(\d{2}|Q[1-4])\.json$');

  /// Full report; `null` if it does not exist or [id] is invalid.
  Future<Map<String, Object?>?> read(String id) async =>
      _reportName.hasMatch('$id.json') ? _read(_reportFile(id)) : null;

  /// Reports urgent items once and again only after they were gone; maintenance
  /// once per date. Once a day is enough: this is not an alarm device.
  Future<void> _dailyChecks(DateTime now) async {
    final state = await _read(_stateFile) ?? {};
    final today = Recorder.dayName(now);
    if (state['day'] == today) return;
    state['day'] = today;
    final known = (state['urgent'] as List? ?? const []).cast<String>().toSet();
    final end = DateTime(now.year, now.month, now.day);
    final period = ReportPeriod(today, end.subtract(const Duration(days: 1)), end);
    final report = buildInstallationReport(
      period: period,
      kind: settings.period,
      rollups: await _loadRollups(period.from, period.to),
      catalog: catalog,
      now: now,
    );
    final urgent = {
      for (final f in (report['findings']! as List).cast<Map<String, Object?>>())
        if (f['level'] == 'critical') f['key']! as String,
    };
    final fresh = urgent.difference(known);
    if (fresh.isNotEmpty && settings.notifyUrgent) {
      await _notify('urgent', _text('urgent', {'n': '${fresh.length}'}));
    }
    state['urgent'] = urgent.toList();
    final due = settings.maintenanceDue;
    if (due != null && !due.isAfter(now) && state['maintenance'] != due.millisecondsSinceEpoch) {
      state['maintenance'] = due.millisecondsSinceEpoch;
      if (settings.notifyUrgent) await _notify('maintenance', _text('maintenance', const {}));
    }
    await _dir.create(recursive: true);
    final tmp = File('${_stateFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(state), flush: true);
    await tmp.rename(_stateFile.path);
  }

  Future<void> _prune(DateTime now) async {
    final oldest = Recorder.dayName(now.subtract(const Duration(days: keepDays)));
    await for (final e in _days.list()) {
      final name = e.uri.pathSegments.last;
      if (e is File && name.length == 15 && name.substring(0, 10).compareTo(oldest) < 0) await e.delete();
    }
    final reports = await list();
    for (final r in reports.skip(keepReports)) {
      await _reportFile(r['id']! as String).delete();
    }
  }

  String _text(String key, Map<String, String> args) {
    final de = language().startsWith('de');
    return switch (key) {
      'ready' =>
        de
            ? 'Anlagenbericht ${args['period']} bereit: ${args['n']} Befunde.'
            : 'Installation report ${args['period']} ready: ${args['n']} findings.',
      'urgent' =>
        de
            ? 'Dringend: ${args['n']} neue Befunde in der Anlage. Einzelheiten in der App.'
            : 'Urgent: ${args['n']} new findings in the installation. Details in the app.',
      'maintenance' =>
        de
            ? 'Die Wartung der Anlage ist fällig. Einzelheiten in der App.'
            : 'Maintenance of the installation is due. Details in the app.',
      _ => de ? 'Testmitteilung von KNX Monitor.' : 'Test message from KNX Monitor.',
    };
  }

  /// Sends "Test" to the chosen target and returns the result for the app.
  Future<OutboundResult> sendTest() => _notify('test', _text('test', const {}));

  /// A failure only shows up in the status; it does not throw or block anything.
  Future<OutboundResult> _notify(String kind, String text, {String? period}) async {
    const title = 'KNX Monitor';
    final OutboundResult result;
    try {
      result = switch (settings.notifyKind) {
        'off' => const OutboundResult.failed('off'),
        'homeassistant' =>
          homeAssistant == null
              ? const OutboundResult.failed('off')
              : await homeAssistant!(id: 'knx_report_$kind', title: title, message: text)
                    .timeout(const Duration(seconds: 20))
                    .then((ok) => ok ? const OutboundResult.ok() : const OutboundResult.failed('network')),
        final target => await sendOutbound(
          kind: target,
          url: settings.notifyUrl,
          topic: settings.notifyTopic,
          token: settings.notifyToken,
          message: OutboundMessage(kind: kind, title: title, message: text, period: period),
        ),
      };
    } on Object {
      lastNotifyError = 'network';
      _log('Mitteilung: nicht zugestellt (network)');
      return const OutboundResult.failed('network');
    }
    if (result.ok) {
      lastNotified = _now();
      lastNotifyError = null;
    } else if (settings.notifyKind != 'off') {
      lastNotifyError = result.code;
      _log('Mitteilung: nicht zugestellt (${result.code})');
    }
    return result;
  }

  Map<String, Object?> status() => {
    'settings': settings.toJson(secrets: false),
    'canHomeAssistant': homeAssistant != null,
    'lastRun': lastRun?.millisecondsSinceEpoch,
    'lastError': lastError,
    'lastNotified': lastNotified?.millisecondsSinceEpoch,
    'lastNotifyError': lastNotifyError,
  };
}

/// `/api/report…`; `true` if [request] has been answered.
///
/// - `GET /api/report` → status, settings (without token) and list
/// - `PUT /api/report` → change settings ([admin] only)
/// - `GET /api/report/<id>` → one report
/// - `POST /api/report/generate` → interim report of the current period ([admin] only)
/// - `POST /api/report/test` → test notification ([admin] only)
/// - `POST /api/report/maintenance` `{due}` → maintenance date from the customer record
Future<bool> serveReports(HttpRequest request, ReportService service, {required bool admin}) async {
  final path = request.uri.path;
  if (path != '/api/report' && !path.startsWith('/api/report/')) return false;
  final response = request.response;
  final rest = path == '/api/report' ? '' : path.substring('/api/report/'.length);
  final method = request.method;

  Future<void> status(int code) async {
    response.statusCode = code;
    await response.close();
  }

  Future<Map<String, Object?>?> body() async {
    final raw = await readBody(request, 16 * 1024);
    if (raw == null) return null;
    try {
      return raw.isEmpty ? const {} : (jsonDecode(utf8.decode(raw)) as Map).cast<String, Object?>();
    } on Object {
      return null;
    }
  }

  Future<void> overview() async => sendJson(response, {...service.status(), 'reports': await service.list()});

  if (rest.isEmpty && method == 'GET') {
    await overview();
    return true;
  }
  if (rest.isEmpty && (method == 'PUT' || method == 'POST')) {
    if (!admin) {
      await status(HttpStatus.forbidden);
      return true;
    }
    final changes = await body();
    if (changes == null) {
      await status(HttpStatus.badRequest);
      return true;
    }
    try {
      await service.update(changes);
      // Catch up on what is still in the history; the response does not wait for it.
      if (service.settings.enabled) unawaited(service.tick());
    } on FormatException catch (e) {
      response.statusCode = HttpStatus.unprocessableEntity;
      await sendJson(response, {'error': e.message});
      return true;
    }
    await overview();
    return true;
  }
  if (method == 'POST' && rest == 'maintenance') {
    final changes = await body();
    if (changes == null) {
      await status(HttpStatus.badRequest);
      return true;
    }
    final due = changes['due'] is int ? changes['due']! as int : null;
    // Unchanged: write nothing; the app reports the date on every load.
    if (due != service.settings.maintenanceDue?.millisecondsSinceEpoch) {
      await service.update({'maintenanceDue': due});
    }
    await status(HttpStatus.noContent);
    return true;
  }
  if (method == 'POST' && (rest == 'generate' || rest == 'test')) {
    if (!admin) {
      await status(HttpStatus.forbidden);
      return true;
    }
    if (rest == 'generate') {
      await sendJson(response, await service.generate(null));
    } else {
      final result = await service.sendTest();
      await sendJson(response, {'ok': result.ok, 'error': ?result.code});
    }
    return true;
  }
  if (method == 'GET' && !rest.contains('/')) {
    final report = await service.read(rest);
    if (report == null) {
      await status(HttpStatus.notFound);
    } else {
      await sendJson(response, report);
    }
    return true;
  }
  await status(HttpStatus.methodNotAllowed);
  return true;
}
