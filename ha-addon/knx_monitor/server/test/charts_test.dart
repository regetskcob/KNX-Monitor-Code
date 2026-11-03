import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

void main() {
  late Directory data;
  late Recorder recorder;
  final now = DateTime(2026, 10, 27, 12);
  const temp = 0x0A01; // 1/2/1
  const light = 0x0A02; // 1/2/2

  setUp(() async {
    data = await Directory.systemTemp.createTemp('knx_charts');
    recorder = Recorder(data);
  });
  tearDown(() => data.delete(recursive: true));

  Map<String, Object?> line(int ga, String hex, DateTime at, {bool small = false, int type = 2}) => {
    't': at.microsecondsSinceEpoch,
    's': 0x1105,
    'd': ga,
    'y': type,
    'x': hex,
    if (small) 'm': true,
  };

  Future<void> day(DateTime d, List<Map<String, Object?>> lines, {bool packed = false}) async {
    final dir = Directory('${data.path}/history');
    await dir.create(recursive: true);
    final text = '${lines.map(jsonEncode).join('\n')}\n';
    final name = '${dir.path}/${Recorder.dayName(d)}.ndjson';
    if (packed) {
      await File('$name.gz').writeAsBytes(gzip.encode(utf8.encode(text)));
    } else {
      await File(name).writeAsString(text);
    }
  }

  Future<void> charts({bool allowed = true}) => File('${data.path}/${ChartService.fileName}').writeAsString(
    jsonEncode({
      'scope': 'Haus',
      'allowed': allowed,
      'charts': [
        {
          'name': 'Wohnen',
          'series': [
            {
              'address': temp,
              'label': '1/2/1',
              'name': 'Temperatur',
              'dpt': [9, 1],
              'unit': '°C',
              'off': 'Aus',
              'on': 'Ein',
            },
            {
              'address': light,
              'label': '1/2/2',
              'name': 'Licht',
              'dpt': [1, 1],
              'off': 'Aus',
              'on': 'Ein',
            },
          ],
        },
      ],
    }),
  );

  test('Liste ohne Werte, ohne Datei leer', () async {
    final service = ChartService();
    expect(await service.list(data), {'allowed': true, 'charts': <Object?>[]});
    await charts();
    final list = await service.list(data);
    expect((list['charts']! as List).single, {
      'name': 'Wohnen',
      'series': [
        {'address': temp, 'label': '1/2/1', 'name': 'Temperatur', 'unit': '°C', 'off': 'Aus', 'on': 'Ein'},
        {'address': light, 'label': '1/2/2', 'name': 'Licht', 'off': 'Aus', 'on': 'Ein'},
      ],
    });
  });

  test('Verlauf über zwei Tage, umgerechnet, mit Wert am Rand', () async {
    await charts();
    final yesterday = now.subtract(const Duration(days: 1));
    await day(yesterday, [
      line(temp, '0C1A', yesterday.subtract(const Duration(hours: 2))), // vor dem Zeitraum: 21 °C
      line(light, '01', yesterday.subtract(const Duration(hours: 1)), small: true),
      line(temp, '0C1A', yesterday.add(const Duration(hours: 1)), type: 0), // Lesen: kein Wert
      line(temp, '0C4C', yesterday.add(const Duration(hours: 2))), // 22 °C
    ], packed: true);
    await day(now, [
      line(temp, '0C7E', now.subtract(const Duration(hours: 1))), // 23 °C
      line(light, '00', now.subtract(const Duration(minutes: 30)), small: true),
      line(0x0A03, '0C7E', now.subtract(const Duration(minutes: 20))), // andere Adresse
    ]);
    final result = (await ChartService().series(data, recorder, 'Wohnen', now: now))!;
    final from = now.subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
    expect(result['from'], from);
    expect(result['to'], now.millisecondsSinceEpoch);
    final [t, l] = (result['series']! as List).cast<Map<String, Object?>>();
    expect(t['kind'], 'line');
    expect(t['unit'], '°C');
    expect(t['points'], [
      [from, 21.0],
      [yesterday.add(const Duration(hours: 2)).millisecondsSinceEpoch, 22.0],
      [now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch, 23.0],
    ]);
    expect(t['last'], [now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch, 23.0]);
    expect(l['kind'], 'step');
    expect(l['points'], [
      [from, 1.0],
      [now.subtract(const Duration(minutes: 30)).millisecondsSinceEpoch, 0.0],
    ]);
  });

  test('nur ein Wert vor dem Zeitraum: Zahl bleibt Zahl', () async {
    await charts();
    final before = now.subtract(const Duration(hours: 2));
    await day(now, [line(temp, '0C1A', before)]);
    final result = (await ChartService().series(data, recorder, 'Wohnen', hours: 1, now: now))!;
    final t = (result['series']! as List).first as Map<String, Object?>;
    expect(t['kind'], 'line');
    expect(t['points'], [
      [now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch, 21.0],
    ]);
  });

  test('unbekanntes Diagramm: null; ohne Freischaltung keine Werte', () async {
    await charts(allowed: false);
    await day(now, [line(temp, '0C7E', now.subtract(const Duration(hours: 1)))]);
    final service = ChartService();
    expect(await service.series(data, recorder, 'Gibt es nicht', now: now), isNull);
    final locked = (await service.series(data, recorder, 'Wohnen', now: now))!;
    expect(locked['allowed'], isFalse);
    expect((locked['series']! as List).first, isNot(contains('points')));
  });

  test('Wert am Rand auch aus dem Vortag', () async {
    await charts();
    final early = DateTime(2026, 10, 27, 0, 30);
    final evening = DateTime(2026, 10, 26, 22);
    await day(evening, [line(temp, '0C1A', evening)]);
    final result = (await ChartService().series(data, recorder, 'Wohnen', hours: 1, now: early))!;
    expect((result['series']! as List).first['points'], [
      [DateTime(2026, 10, 26, 23, 30).millisecondsSinceEpoch, 21.0],
    ]);
  });

  test('kurz nach Mitternacht wird der Vortag noch neu gelesen', () async {
    await charts();
    final service = ChartService();
    final early = DateTime(2026, 10, 27, 0, 30);
    final yesterday = DateTime(2026, 10, 26, 23);
    expect(((await service.series(data, recorder, 'Wohnen', now: early))!['series']! as List).first['points'], isEmpty);
    await day(yesterday, [line(temp, '0C4C', yesterday)]);
    expect(
      ((await service.series(data, recorder, 'Wohnen', now: early))!['series']! as List).first['points'],
      hasLength(1),
    );
  });

  test('abgeschlossene Tage bleiben im Speicher', () async {
    await charts();
    final yesterday = now.subtract(const Duration(hours: 20));
    await day(yesterday, [line(temp, '0C4C', yesterday)]);
    final service = ChartService();
    expect(((await service.series(data, recorder, 'Wohnen', now: now))!['series']! as List).first['last'], isNotNull);
    // Datei weg: Der gelesene Tag bleibt im Speicher.
    await File('${data.path}/history/${Recorder.dayName(yesterday)}.ndjson').delete();
    final again = (await service.series(data, recorder, 'Wohnen', now: now))!;
    expect((again['series']! as List).first['points'], hasLength(1));
  });

  test('Kennzahlen: Telegramme, Wiederholungen und Linie je Minute', () async {
    await File('${data.path}/${ChartService.fileName}').writeAsString(
      jsonEncode({
        'charts': [
          {
            'name': 'Bus',
            'series': [
              {'address': -1, 'label': 'telegrams', 'metric': 'telegrams', 'unit': '/min'},
              {'address': -2, 'label': 'repeats', 'metric': 'repeats', 'unit': '/min'},
              {'address': -(256 + 0x11), 'label': '1.1', 'metric': 'line', 'line': 0x11, 'unit': '/min'},
            ],
          },
        ],
      }),
    );
    final minute = DateTime(2026, 10, 27, 11, 30);
    Map<String, Object?> at(int second, {int src = 0x1105, bool rp = false}) => {
      ...line(temp, '0C1A', minute.add(Duration(seconds: second))),
      's': src,
      if (rp) 'rp': true,
    };
    await day(now, [at(1), at(2, rp: true), at(3, src: 0x1201), at(70)]);
    final result = (await ChartService().series(data, recorder, 'Bus', hours: 1, now: now))!;
    final [telegrams, repeats, lineLoad] = (result['series']! as List).cast<Map<String, Object?>>();
    List<num> valueAt(Map<String, Object?> s, DateTime t) =>
        (s['points']! as List).cast<List<num>>().firstWhere((p) => p[0] == t.millisecondsSinceEpoch);
    expect(telegrams['metric'], 'telegrams');
    expect(valueAt(telegrams, minute)[1], 3);
    expect(valueAt(telegrams, minute.add(const Duration(minutes: 1)))[1], 1);
    expect(valueAt(repeats, minute)[1], 1);
    expect(valueAt(lineLoad, minute)[1], 2);
    expect((telegrams['points']! as List).length, 61);
  });

  group('thin', () {
    test('wenige Punkte bleiben', () {
      final points = [(0, 1.0), (10, 2.0)];
      expect(thin(points, 0, 100, 10), points);
    });

    test('je Spalte kleinster und größter Wert, in zeitlicher Folge', () {
      final points = [for (var i = 0; i < 1000; i++) (i, i == 503 ? 99.0 : (i % 7).toDouble())];
      final out = thin(points, 0, 1000, 10);
      expect(out.length, lessThanOrEqualTo(21)); // dazu der letzte Punkt
      expect(out, contains((503, 99.0)));
      for (var i = 1; i < out.length; i++) {
        expect(out[i].$1, greaterThan(out[i - 1].$1));
      }
    });

    test('der letzte Punkt bleibt', () {
      final points = [for (var i = 0; i < 1000; i++) (i, i == 999 ? 50.0 : (i % 7).toDouble())];
      expect(thin(points, 0, 1000, 10).last, (999, 50.0));
      final flat = [for (var i = 0; i < 1000; i++) (i, i % 2 == 0 ? 0.0 : 9.0)];
      expect(thin(flat, 0, 1000, 10).last, (999, 9.0));
    });

    test('Schaltzustände: Wiederholungen fallen weg', () {
      expect(thin([(0, 1.0), (5, 1.0), (9, 0.0), (12, 0.0), (20, 1.0)], 0, 100, 10, step: true), [
        (0, 1.0),
        (9, 0.0),
        (20, 1.0),
      ]);
    });
  });
}
