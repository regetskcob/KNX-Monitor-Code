import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

void main() {
  late Directory data;
  final sent = <(String, String, String)>[];
  late WatchRuleSet set;
  final t0 = DateTime(2026, 10, 21, 20, 15, 3);

  setUp(() async {
    data = await Directory.systemTemp.createTemp('knx_watch');
    sent.clear();
    set = WatchRuleSet(
      data,
      notify: ({required id, required title, required message}) async => sent.add((id, title, message)),
    );
  });
  tearDown(() => data.delete(recursive: true));

  Future<void> rules(List<Map<String, Object?>> list) async {
    await File('${data.path}/watch_rules.json').writeAsString(jsonEncode({'rules': list}));
  }

  Map<String, Object?> line(int ga, String hex, {bool small = false, int type = 2, DateTime? at}) => {
    't': (at ?? t0).microsecondsSinceEpoch,
    's': 0x1105,
    'd': ga,
    'y': type,
    'x': hex,
    if (small) 'm': true,
  };

  test('ohne Wert: jedes Schreiben, Mitteilung mit Name, Lesen zählt nicht', () async {
    await rules([
      {
        'id': 'a',
        'address': 0x0A03,
        'name': 'Außenleuchten',
        'label': '1/2/3 Außenleuchten',
        'check': {'any': true},
      },
    ]);
    expect(await set.check(line(0x0A03, '00', small: true, type: 0)), isEmpty);
    expect(await set.check(line(0x0A03, '01', small: true)), ['a']);
    expect(sent.single.$1, 'knx_watch_a');
    expect(sent.single.$2, 'Wächter: Außenleuchten');
    expect(sent.single.$3, '1/2/3 Außenleuchten · 20:15:03');
    expect(await set.check(line(0x0A04, '01', small: true)), isEmpty);
  });

  test('Rohwerte: nur die passenden, kleine Werte getrennt von Bytes', () async {
    await rules([
      {
        'id': 'on',
        'address': 0x0A03,
        'label': '1/2/3 = Ein',
        'check': {
          'small': true,
          'bytes': 0,
          'values': [1],
        },
      },
    ]);
    expect(await set.check(line(0x0A03, '00', small: true)), isEmpty);
    expect(await set.check(line(0x0A03, '01', small: true)), ['on']);
    expect(await set.check(line(0x0A03, '01', at: t0.add(const Duration(seconds: 10)))), isEmpty);
  });

  test('Zahlenvergleich DPT 9, Drosselung von Treffern und Mitteilungen', () async {
    await rules([
      {
        'id': 'wind',
        'address': 0x4101,
        'name': 'Wind',
        'label': '8/1/1 Wind > 10',
        'check': {
          'num': [9, 5],
          'op': 'greater',
          'n': 10,
        },
      },
      {
        'id': 'off',
        'address': 0x4101,
        'enabled': false,
        'label': '',
        'check': {'any': true},
      },
      {'id': 'app', 'address': 0x4101, 'label': 'nur App'},
    ]);
    // 0x0C1A: Exponent 1, Mantisse 1050 → 21 m/s.
    expect(await set.check(line(0x4101, '0C1A', at: t0)), ['wind']);
    expect(sent.single.$3, '8/1/1 Wind > 10 · 21 · 20:15:03');
    // Innerhalb der Sperrzeit kein zweiter Treffer.
    expect(await set.check(line(0x4101, '0C1A', at: t0.add(const Duration(seconds: 1)))), isEmpty);
    // Treffer ja, Mitteilung erst nach einer Minute wieder.
    expect(await set.check(line(0x4101, '0C1A', at: t0.add(const Duration(seconds: 5)))), ['wind']);
    expect(sent, hasLength(1));
    expect(await set.check(line(0x4101, '0C1A', at: t0.add(const Duration(minutes: 2)))), ['wind']);
    expect(sent, hasLength(2));
    // 0,5 m/s liegt darunter.
    expect(await set.check(line(0x4101, '0032', at: t0.add(const Duration(minutes: 5)))), isEmpty);
  });

  test('ohne Datei oder bei kaputter Datei: keine Treffer', () async {
    expect(await set.check(line(0x0A03, '01', small: true)), isEmpty);
    await File('${data.path}/watch_rules.json').writeAsString('{kaputt');
    expect(await set.check(line(0x0A03, '01', small: true)), isEmpty);
  });
}
