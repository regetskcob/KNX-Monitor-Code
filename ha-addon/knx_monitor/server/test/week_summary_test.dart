import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

void main() {
  late Directory data;
  final now = DateTime(2026, 11, 10, 12);

  setUp(() async => data = await Directory.systemTemp.createTemp('knx_summary'));
  tearDown(() => data.delete(recursive: true));

  Map<String, Object?> t(
    DateTime at,
    int src,
    int ga, {
    int y = 2,
    String x = '01',
    bool small = false,
    bool rp = false,
  }) => {'t': at.microsecondsSinceEpoch, 's': src, 'd': ga, 'y': y, 'x': x, if (small) 'm': true, if (rp) 'rp': true};

  Future<void> day(DateTime d, List<Map<String, Object?>> lines) async {
    final dir = Directory('${data.path}/history');
    await dir.create(recursive: true);
    await File('${dir.path}/${Recorder.dayName(d)}.ndjson').writeAsString('${lines.map(jsonEncode).join('\n')}\n');
  }

  // Project: 1/0/0 Alarm (1.1.10 and 1.1.11 answer reads), 8/0/1 time, 8/0/2 date/time, devices
  // 1.1.10, 1.1.11 and the silent 1.1.12.
  LintCatalog catalog() => LintCatalog.fromJson({
    'groups': [
      {
        'a': 0x0800,
        'n': 'Alarm',
        'd': [1, 2],
      },
      {
        'a': 0x4001,
        'n': 'Uhrzeit',
        'd': [10, 1],
      },
      {
        'a': 0x4002,
        'n': 'Datum / Uhrzeit',
        'd': [19, 1],
      },
    ],
    'devices': [
      {'a': 0x110A, 'n': 'Melder EG'},
      {'a': 0x110B, 'n': 'Melder OG'},
      {'a': 0x110C, 'n': 'Taster Keller'},
      // Radio device (KNX RF): silent all week, and no finding for that.
      {'a': 0x120D, 'n': 'Funktaster Garten', 'rf': true},
      {'a': 0x1123, 'n': 'X1'},
      {'a': 0x1124, 'n': 'HA', 'tu': 1123},
    ],
  });

  test('a week: counts, availability, and the findings worth a look', () async {
    for (var i = 0; i < 3; i++) {
      final d = DateTime(2026, 11, 8 + i);
      await day(d, [
        // Two clocks, every minute, on two addresses.
        for (var m = 0; m < (i == 2 ? 12 * 60 : 24 * 60); m++) ...[
          t(d.add(Duration(minutes: m)), 0x1123, 0x4001, x: '0C0000'),
          t(d.add(Duration(minutes: m, seconds: 1)), 0x1124, 0x4002, x: '7E0B0A0C00002000'),
        ],
        // Read of the alarm, answered by two detectors, four times a day.
        for (var h = 0; h < 4; h++) ...[
          t(d.add(Duration(hours: h * 3)), 0x1124, 0x0800, y: 0, x: '00', small: true),
          t(d.add(Duration(hours: h * 3, milliseconds: 20)), 0x110A, 0x0800, y: 1, x: '00', small: true),
          t(d.add(Duration(hours: h * 3, milliseconds: 40)), 0x110B, 0x0800, y: 1, x: '00', small: true),
        ],
        // One sender nobody knows.
        t(d.add(const Duration(hours: 1)), 0x1250, 0x0800, x: '00', small: true),
      ]);
    }
    final s = await WeekSummary.compute(Recorder(data), Availability(data), catalog(), now: now, days: 3);
    expect(s['telegrams'], 2 * 24 * 60 * 2 + 2 * 12 * 60 + 3 * 13);
    expect(s['repeats'], 0);
    expect(s['reads'], 12);
    expect(s['per_day_mean'], 2 * 24 * 60 + 13);
    final kinds = [for (final f in s['findings']! as List) (f as Map)['kind']];
    expect(kinds, containsAll(['clocks', 'multi_responders', 'silent', 'unknown_senders']));
    final multi = (s['findings']! as List).cast<Map<String, Object?>>().firstWhere(
      (f) => f['kind'] == 'multi_responders',
    );
    expect((multi['groups']! as List).first, {
      'group': '1/0/0',
      'name': 'Alarm',
      'devices': ['1.1.10', '1.1.11'],
    });
    final silent = (s['findings']! as List).cast<Map<String, Object?>>().firstWhere((f) => f['kind'] == 'silent');
    expect(silent['devices'], [
      {'address': '1.1.12', 'name': 'Taster Keller'},
    ]);
    expect(silent['count'], 1, reason: 'the radio device is not reported as silent');
    expect(s['state'], 'ok');
  });

  test('in its own isolate: the same result as on the main isolate', () async {
    final d = DateTime(2026, 11, 9);
    await day(d, [
      for (var m = 0; m < 600; m++) t(d.add(Duration(minutes: m)), 0x1123, 0x4001, x: '0C0000'),
      t(d.add(const Duration(hours: 1)), 0x1250, 0x0800, x: '00', small: true),
    ]);
    final here = await WeekSummary.compute(Recorder(data), Availability(data), await LintCatalog.load(data), now: now);
    final there = await weekSummaryInIsolate(data.path, data.path, now);
    expect(jsonEncode(there), jsonEncode(here));
  });

  test('without history and project: empty but valid', () async {
    final s = await WeekSummary.compute(Recorder(data), Availability(data), LintCatalog(const {}, const {}), now: now);
    expect(s['telegrams'], 0);
    expect(s['findings'], isEmpty);
    expect((s['per_day']! as List).length, 7);
  });

  test('repeats above one percent are a warning', () async {
    final d = DateTime(2026, 11, 10);
    await day(d, [for (var i = 0; i < 50; i++) t(d.add(Duration(seconds: i)), 0x110A, 0x0800, rp: i % 10 == 0)]);
    final s = await WeekSummary.compute(Recorder(data), Availability(data), catalog(), now: now, days: 1);
    expect(s['state'], 'warn');
    expect((s['findings']! as List).first, containsPair('kind', 'repeats'));
  });

  test('the cache computes once within its age', () async {
    final cache = WeekSummaryCache();
    var runs = 0;
    Future<Map<String, Object?>> run() async => {'run': ++runs};
    expect(await cache.get('a', run, now: now), {'run': 1});
    expect(await cache.get('a', run, now: now.add(const Duration(minutes: 30))), {'run': 1});
    expect(await cache.get('a', run, now: now.add(const Duration(hours: 2))), {'run': 2});
  });
}
