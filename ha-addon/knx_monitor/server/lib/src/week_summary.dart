import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:knx/knx.dart';

import 'project_lint.dart';
import 'recorder.dart';
import 'report.dart' show busySeconds;

/// Overview of the last days of the continuous recording, for the app's start card and
/// `/api/summary`: how much went over the bus, how busy it was, whether the recording ran, and
/// the few findings worth a look (each with plain parameters; the app words them).
///
/// One pass over the history per day; [WeekSummaryCache] keeps the result for an hour, so
/// opening the app never waits for it twice.
class WeekSummary {
  WeekSummary._();

  /// How long a response may come after a read to count as its answer.
  static const readWindow = Duration(seconds: 3);

  /// A group address counts as chatty above this many telegrams a day on average.
  static const chattyPerDay = 1000;

  /// Reads of one sender within a minute that count as a read storm.
  static const stormPerMinute = 100;

  /// Computes the overview of the [days] days up to [now], against [catalog] (may be empty).
  static Future<Map<String, Object?>> compute(
    Recorder recorder,
    Availability availability,
    LintCatalog catalog, {
    required DateTime now,
    int days = 7,
  }) async {
    await recorder.flush();
    final style = catalog.style;
    String ga(int a) => formatGroupAddress(a, style);
    final start = DateTime(now.year, now.month, now.day - (days - 1));
    final end = now.microsecondsSinceEpoch;
    final perDay = <Map<String, Object?>>[];
    final senders = <int, int>{};
    final groups = <int, int>{};
    final groupSenders = <int, Set<int>>{};
    final minuteBusy = <int, double>{};
    final readsPerMinute = <(int, int), int>{};
    final responders = <int, Map<int, int>>{}; // group → responder → times
    final multiReads = <int, int>{}; // group → reads answered by several devices
    var total = 0, repeats = 0, reads = 0;
    for (var d = start; !d.isAfter(now); d = DateTime(d.year, d.month, d.day + 1)) {
      final lines = await recorder.dayLines(Recorder.dayName(d));
      var n = 0;
      if (lines != null) {
        final day = <({int t, int s, int d, int y, bool rp, double busy})>[];
        await for (final line in lines) {
          final t = int.tryParse(Recorder.field(line, 't') ?? '');
          final s = int.tryParse(Recorder.field(line, 's') ?? '');
          final dest = int.tryParse(Recorder.field(line, 'd') ?? '');
          final y = int.tryParse(Recorder.field(line, 'y') ?? '');
          if (t == null || s == null || dest == null || y == null || t > end) continue;
          if (line.contains('"o":true')) continue; // our own telegrams
          day.add((
            t: t,
            s: s,
            d: dest,
            y: y,
            rp: line.contains('"rp":true'),
            busy: busySeconds(_payload(line), small: line.contains('"m":true')),
          ));
        }
        day.sort((a, b) => a.t.compareTo(b.t));
        final openReads = <int, int>{}; // group → time of the last read
        final answeredBy = <int, Set<int>>{};
        void closeRead(int group) {
          final who = answeredBy.remove(group);
          if (who != null && who.length > 1) multiReads[group] = (multiReads[group] ?? 0) + 1;
        }

        for (final m in day) {
          n++;
          senders[m.s] = (senders[m.s] ?? 0) + 1;
          groups[m.d] = (groups[m.d] ?? 0) + 1;
          if (m.y == 2) (groupSenders[m.d] ??= {}).add(m.s);
          if (m.rp) repeats++;
          final minute = m.t ~/ 60000000;
          minuteBusy[minute] = (minuteBusy[minute] ?? 0) + m.busy;
          if (m.y == 0) {
            reads++;
            readsPerMinute[(m.s, minute)] = (readsPerMinute[(m.s, minute)] ?? 0) + 1;
            closeRead(m.d);
            openReads[m.d] = m.t;
            answeredBy[m.d] = {};
          } else if (m.y == 1) {
            final asked = openReads[m.d];
            if (asked != null && m.t - asked <= readWindow.inMicroseconds) {
              answeredBy[m.d]?.add(m.s);
              final r = responders[m.d] ??= {};
              r[m.s] = (r[m.s] ?? 0) + 1;
            }
          }
        }
        for (final g in [...answeredBy.keys]) {
          closeRead(g);
        }
      }
      total += n;
      perDay.add({'day': Recorder.dayName(d), 'telegrams': n});
    }

    // Load: share of each recorded minute the line was busy (TP, 9600 bit/s).
    final loads = [for (final b in minuteBusy.values) b / 60 * 100]..sort();
    final loadMean = loads.isEmpty ? 0.0 : loads.reduce((a, b) => a + b) / loads.length;
    final loadMax = loads.isEmpty ? 0.0 : loads.last;
    final loadMaxAt = minuteBusy.isEmpty
        ? null
        : minuteBusy.entries.reduce((a, b) => b.value > a.value ? b : a).key * 60000;

    // Availability of the recording over the period.
    final from = start;
    final ratio = await availability.ratio(from, now);
    final outages = await availability.outages(from, now, taps: true);
    int minutesOf(Iterable<Map<String, Object?>> list) =>
        list.fold(0, (n, o) => n + (((o['to']! as int) - (o['from']! as int)) / 60000).round());
    final offline = outages.where((o) => o['kind'] == 'offline');
    final disconnected = outages.where((o) => o['kind'] == 'disconnected');
    final tapGaps = outages.where((o) => o['kind'] == 'tap');

    String deviceName(int a) => catalog.devices[a]?.name ?? '';
    String groupName(int a) => catalog.groups[a]?.name ?? '';
    final top = (senders.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(5);

    // --- Findings, most useful first -----------------------------------------------------------
    final findings = <Map<String, Object?>>[];
    if (total > 0 && repeats / total > 0.01) {
      findings.add({'kind': 'repeats', 'severity': 'warn', 'count': repeats, 'share': _round(100 * repeats / total)});
    }
    if (loadMax > 30) {
      findings.add({'kind': 'load', 'severity': 'warn', 'max': _round(loadMax), 'at': loadMaxAt});
    }
    // Several clocks: date/time types written every few minutes by more than one sender or on
    // more than one address.
    final clockGroups = [
      for (final MapEntry(key: g, value: n) in groups.entries)
        if (_isClock(catalog.groups[g]?.dpt) && n / days > 24 * 6) g,
    ];
    final clockSenders = {for (final g in clockGroups) ...?groupSenders[g]};
    if (clockGroups.length > 1 && clockSenders.length > 1) {
      final clockTelegrams = clockGroups.fold(0, (n, g) => n + groups[g]!);
      findings.add({
        'kind': 'clocks',
        'severity': 'info',
        'groups': [for (final g in clockGroups) ga(g)],
        'senders': [for (final s in clockSenders) formatIndividual(s)],
        'share': total == 0 ? 0 : _round(100 * clockTelegrams / total),
      });
    }
    final multi = (multiReads.entries.where((e) => e.value >= 3).toList()..sort((a, b) => b.value.compareTo(a.value)));
    if (multi.isNotEmpty) {
      findings.add({
        'kind': 'multi_responders',
        'severity': 'info',
        'groups': [
          for (final e in multi.take(5))
            {
              'group': ga(e.key),
              'name': groupName(e.key),
              'devices': [for (final s in responders[e.key]!.keys) formatIndividual(s)],
            },
        ],
        'count': multi.length,
      });
    }
    final storms = <int, int>{};
    readsPerMinute.forEach((k, n) {
      if (n >= stormPerMinute) storms[k.$1] = math.max(storms[k.$1] ?? 0, n);
    });
    if (storms.isNotEmpty) {
      final sender = storms.entries.reduce((a, b) => b.value > a.value ? b : a);
      final share = reads == 0 ? 0 : (100 * (senders[sender.key] ?? 0) / total);
      findings.add({
        'kind': 'read_storms',
        'severity': 'info',
        'sender': formatIndividual(sender.key),
        'name': deviceName(sender.key),
        'max_per_minute': sender.value,
        'share': _round(share.toDouble()),
      });
    }
    final chatty = (groups.entries.where((e) => e.value / days > chattyPerDay && !clockGroups.contains(e.key)).toList()
      ..sort((a, b) => b.value.compareTo(a.value)));
    if (chatty.isNotEmpty) {
      findings.add({
        'kind': 'chatty',
        'severity': 'info',
        'groups': [
          for (final e in chatty.take(3))
            {
              'group': ga(e.key),
              'name': groupName(e.key),
              'per_day': (e.value / days).round(),
              'interval_s': _round(days * 86400 / e.value),
            },
        ],
      });
    }
    if (!catalog.isEmpty && total > 0) {
      final silent = [
        for (final dev in catalog.devices.values)
          if (!dev.tunnel && dev.address & 0xFF != 0 && !senders.containsKey(dev.address)) dev,
      ]..sort((a, b) => a.address.compareTo(b.address));
      if (silent.isNotEmpty) {
        findings.add({
          'kind': 'silent',
          'severity': 'info',
          'devices': [
            for (final dev in silent.take(8)) {'address': formatIndividual(dev.address), 'name': dev.name},
          ],
          'count': silent.length,
        });
      }
      final unknown = [
        for (final s in senders.keys)
          if (!catalog.devices.containsKey(s) && s != 0xFFFF) formatIndividual(s),
      ]..sort();
      if (unknown.isNotEmpty) findings.add({'kind': 'unknown_senders', 'severity': 'info', 'senders': unknown});
    }
    if (disconnected.isNotEmpty) {
      findings.add({
        'kind': 'disconnected',
        'severity': 'warn',
        'count': disconnected.length,
        'minutes': minutesOf(disconnected),
      });
    }
    if (tapGaps.isNotEmpty) {
      findings.add({
        'kind': 'tap_gaps',
        'severity': 'info',
        'taps': {for (final o in tapGaps) o['tap']}.toList(),
        'minutes': minutesOf(tapGaps),
      });
    }

    final fullDays = perDay.where((d) => d['day'] != Recorder.dayName(now) && (d['telegrams']! as int) > 0);
    return {
      'v': 1,
      'from': start.millisecondsSinceEpoch,
      'to': now.millisecondsSinceEpoch,
      'days': days,
      'telegrams': total,
      'per_day_mean': fullDays.isEmpty
          ? total
          : (fullDays.fold(0, (n, d) => n + (d['telegrams']! as int)) / fullDays.length).round(),
      'per_day': perDay,
      'repeats': repeats,
      'reads': reads,
      'load_mean_pct': _round(loadMean, 2),
      'load_max_pct': _round(loadMax),
      'load_max_at': loadMaxAt,
      'availability_pct': ratio == null ? null : _round(ratio * 100),
      'offline_minutes': minutesOf(offline),
      'senders_active': senders.length,
      'groups_active': groups.length,
      if (!catalog.isEmpty)
        'devices_project': catalog.devices.values.where((d) => !d.tunnel && d.address & 0xFF != 0).length,
      if (!catalog.isEmpty) 'groups_project': catalog.groups.length,
      'top_senders': [
        for (final e in top) {'address': formatIndividual(e.key), 'name': deviceName(e.key), 'telegrams': e.value},
      ],
      'state': findings.any((f) => f['severity'] == 'warn') ? 'warn' : 'ok',
      'findings': findings,
    };
  }

  static bool _isClock((int, int?)? dpt) => dpt != null && (dpt.$1 == 10 || dpt.$1 == 11 || dpt.$1 == 19);

  static double _round(double v, [int digits = 1]) {
    final f = math.pow(10, digits);
    return (v * f).round() / f;
  }

  /// Payload hex (`"x":"…"`) of a history line; [Recorder.field] only reads numbers.
  static String _payload(String line) {
    final i = line.indexOf('"x":"');
    if (i < 0) return '';
    final end = line.indexOf('"', i + 5);
    return end < 0 ? '' : line.substring(i + 5, end);
  }
}

/// [WeekSummary.compute] in a separate isolate, from the history in [dataPath] and the
/// availability log in [availabilityPath]. Seven days of history on the main isolate would hold
/// up the bus for a moment, long enough for tap point sightings to miss the merge window. Flush
/// the recorder before, the isolate only reads what is on disk.
Future<Map<String, Object?>> weekSummaryInIsolate(String dataPath, String availabilityPath, DateTime now) =>
    Isolate.run(
      () async => WeekSummary.compute(
        Recorder(Directory(dataPath)),
        Availability(Directory(availabilityPath)),
        await LintCatalog.load(Directory(dataPath)),
        now: now,
      ),
    );

/// Keeps the last [WeekSummary] per installation for [maxAge]; one computation at a time.
class WeekSummaryCache {
  WeekSummaryCache({this.maxAge = const Duration(hours: 1)});

  final Duration maxAge;
  final _entries = <String, ({DateTime at, Future<Map<String, Object?>> value})>{};

  Future<Map<String, Object?>> get(String key, Future<Map<String, Object?>> Function() compute, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final hit = _entries[key];
    if (hit != null && t.difference(hit.at) < maxAge) return hit.value;
    final value = compute();
    _entries[key] = (at: t, value: value);
    // A failed computation is not kept.
    value.catchError((Object _) {
      if (identical(_entries[key]?.value, value)) _entries.remove(key);
      return const <String, Object?>{};
    });
    return value;
  }
}
