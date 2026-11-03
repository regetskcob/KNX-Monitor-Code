import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

void main() {
  late Directory data;
  late FaultHunt hunt;
  final blind = 0x0A03; // 1/2/3
  final other = 0x0A04;
  // 23:00 Uhr Ortszeit: im Fenster 22–6 Uhr.
  final night = DateTime(2026, 10, 27, 23);

  setUp(() async {
    data = await Directory.systemTemp.createTemp('knx_hunt');
    hunt = FaultHunt(data);
  });
  tearDown(() => data.delete(recursive: true));

  Future<void> define({List<int>? window, int until = 0, String id = 'h1', int pre = 120, int post = 60}) =>
      File('${data.path}/fault_hunt.json').writeAsString(
        jsonEncode({
          'id': id,
          'until': until == 0 ? night.add(const Duration(days: 7)).millisecondsSinceEpoch : until,
          'pre': pre,
          'post': post,
          'window': ?window,
          'rules': [
            {
              'id': 'r1',
              'address': blind,
              'label': '1/2/3 Rollladen Auf = 1',
              'check': {
                'values': [1],
                'small': true,
              },
            },
          ],
        }),
      );

  Map<String, Object?> line(DateTime at, int ga, {int value = 1, int type = 2, int source = 0x1105}) => {
    't': at.microsecondsSinceEpoch,
    's': source,
    'd': ga,
    'y': type,
    'x': value.toRadixString(16).padLeft(2, '0'),
    'm': true,
  };

  Future<List<Map<String, Object?>>> index(String id) async {
    final f = File('${data.path}/hunts/$id/hits.ndjson');
    if (!await f.exists()) return const [];
    return [
      for (final l in await f.readAsLines())
        if (l.isNotEmpty) jsonDecode(l) as Map<String, Object?>,
    ];
  }

  test('Treffer hält Vorlauf und Nachlauf fest, außerhalb davon nichts', () async {
    await define();
    // Älter als der Vorlauf: fällt heraus.
    await hunt.add(line(night.subtract(const Duration(minutes: 5)), other), night.subtract(const Duration(minutes: 5)));
    await hunt.add(
      line(night.subtract(const Duration(seconds: 30)), other),
      night.subtract(const Duration(seconds: 30)),
    );
    await hunt.add(line(night, blind, value: 0), night); // passt nicht (Wert)
    await hunt.add(
      line(night.add(const Duration(seconds: 1)), blind, source: 0x1107),
      night.add(const Duration(seconds: 1)),
    );
    await hunt.add(line(night.add(const Duration(seconds: 30)), other), night.add(const Duration(seconds: 30)));
    expect(await index('h1'), isEmpty, reason: 'Fenster ist noch offen');
    // Nach dem Nachlauf: Fenster geschlossen.
    final later = night.add(const Duration(minutes: 2));
    await hunt.add(line(later, other), later);

    final hits = await index('h1');
    expect(hits, hasLength(1));
    final entry = hits.single;
    expect((entry['hits']! as List).single, containsPair('s', 0x1107));
    expect((entry['hits']! as List).single, containsPair('label', '1/2/3 Rollladen Auf = 1'));
    final lines = await File('${data.path}/hunts/h1/${entry['file']}').readAsLines();
    // Vorlauf (−30 s, Wert 0), Treffer, +30 s, und die Zeile, die das Fenster schloss.
    expect(lines, hasLength(5));
    expect(entry['from'], night.subtract(const Duration(seconds: 30)).microsecondsSinceEpoch);
  });

  test('Mehrere Treffer kurz hintereinander landen in einem Fenster', () async {
    await define();
    await hunt.add(line(night, blind), night);
    await hunt.add(line(night.add(const Duration(seconds: 20)), blind), night.add(const Duration(seconds: 20)));
    await hunt.close();
    final hits = await index('h1');
    expect(hits, hasLength(1));
    expect(hits.single['hits'], hasLength(2));
  });

  test('Zeitfenster über Mitternacht und Laufzeit', () async {
    await define(window: [22 * 60, 6 * 60]);
    final noon = DateTime(2026, 10, 28, 12);
    await hunt.add(line(noon, blind), noon);
    await hunt.close();
    expect(await index('h1'), isEmpty, reason: 'mittags außerhalb des Fensters');

    final early = DateTime(2026, 10, 28, 3);
    await hunt.add(line(early, blind), early.add(const Duration(seconds: 10)));
    await hunt.close();
    expect(await index('h1'), hasLength(1));
  });

  test('Abgelaufene Jagd fängt nichts, Lesen und Eigenes zählen nicht', () async {
    await define(until: night.subtract(const Duration(hours: 1)).millisecondsSinceEpoch);
    await hunt.add(line(night, blind), night);
    await hunt.close();
    expect(await index('h1'), isEmpty);

    final hunt2 = FaultHunt(data);
    await define(id: 'h2');
    await hunt2.add(line(night, blind, type: 0), night);
    await hunt2.add({...line(night, blind), 'o': true}, night);
    await hunt2.close();
    expect(await index('h2'), isEmpty);
  });

  test('Ein Schwall ohne Warten kommt vollständig und in Reihenfolge an', () async {
    await define();
    final pending = <Future<void>>[];
    for (var i = 0; i < 50; i++) {
      final at = night.add(Duration(milliseconds: i * 100));
      pending.add(hunt.add(line(at, i == 25 ? blind : other), at));
    }
    await hunt.close();
    await Future.wait(pending);
    final entry = (await index('h1')).single;
    final lines = await File('${data.path}/hunts/h1/${entry['file']}').readAsLines();
    expect(lines, hasLength(50));
    final times = [for (final l in lines) (jsonDecode(l) as Map)['t'] as int];
    expect(times, [...times]..sort());
  });

  test('Höchstzahl der Treffer je Jagd', () async {
    hunt = FaultHunt(data, maxHits: 2);
    await define();
    for (var i = 0; i < 5; i++) {
      final at = night.add(Duration(minutes: i * 5));
      await hunt.add(line(at, blind), at);
    }
    await hunt.close();
    final total = [for (final e in await index('h1')) ...(e['hits']! as List)];
    expect(total, hasLength(2));
  });
}
