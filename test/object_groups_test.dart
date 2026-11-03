import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/object_groups.dart';

void main() {
  final names = {
    '3/1/0': 'EG FL F01 Auf/Ab fahren',
    '3/4/0': 'EG FL F01 Aktuelle Position',
    '4/1/0': 'EG FL F01 Geöffnet',
    '1/1/1': 'EG FL L02 Schalten',
    '1/4/1': 'EG FL L02 Rückmeldung Schalten',
    '2/0/1': 'EG FL Ist-Temperatur',
    '2/2/1': 'EG FL Sollwertverschiebung',
    '2/0/2': 'EG KÜ Ist-Temperatur',
    '2/0/12': 'DG Ist-Temperatur',
    '2/2/12': 'DG Sollwertverschiebung',
    '3/1/30': 'DG F02 Auf/Ab fahren',
    '3/5/30': 'DG F02 Verfahrstatus',
    '1/1/71': 'Außenleuchte Haustür Schalten',
    '1/4/71': 'Außenleuchte Haustür Rückmeldung Schalten',
    '1/0/0': 'Alles Aus',
    '1/1/90': 'OG K1 L01 Schalten',
    '1/4/90': 'OG K1 L01 Rückmeldung Schalten',
    '3/1/90': 'OG K1 F01 Auf/Ab fahren',
    '3/4/90': 'OG K1 F01 Aktuelle Position',
    '2/0/90': 'OG K1 Ist-Temperatur',
    '2/2/90': 'OG K1 Sollwertverschiebung',
    '1/1/91': 'OG K2 L01 Schalten',
    '1/4/91': 'OG K2 L01 Rückmeldung Schalten',
    '2/0/91': 'OG K2 Ist-Temperatur',
  };
  final catalog = GroupCatalog({
    for (final MapEntry(key: ga, value: name) in names.entries)
      parseGroup(ga)!: GroupInfo(address: parseGroup(ga)!, name: name),
  });
  final index = ObjectIndex.of(catalog);
  ObjectGroup? of(String ga) => index.objectOf(parseGroup(ga)!);

  test('Element-Kürzel bilden Objekte mit Befehlen und Rückmeldungen', () {
    final f01 = of('3/1/0')!;
    expect(f01.key, 'EG FL F01');
    expect(f01.room, 'EG FL');
    expect(f01.title, 'F01');
    expect(f01.commands.map((m) => m.function), ['Auf/Ab fahren']);
    expect(f01.feedbacks.map((m) => m.function), ['Aktuelle Position', 'Geöffnet']);
    expect(of('1/4/1')!.key, 'EG FL L02');
  });

  test('Raumnummer vor dem Element-Kürzel gehört zum Raum', () {
    final l01 = of('1/1/90')!;
    expect(l01.key, 'OG K1 L01');
    expect(l01.room, 'OG K1');
    expect(l01.title, 'L01');
    expect(of('3/4/90')!.key, 'OG K1 F01');
    expect(of('2/0/90')!.room, 'OG K1');
    expect(of('1/4/91')!.room, 'OG K2');
  });

  test('Raum ohne Element, Geschoss als Raum, Namensanfang ohne Schema', () {
    expect(of('2/0/1')!.key, 'EG FL');
    expect(of('2/0/12')!.key, 'DG');
    expect(of('3/5/30')!.key, 'DG F02');
    expect(of('3/5/30')!.room, 'DG');
    expect(of('1/1/71')!.key, 'Außenleuchte Haustür');
    expect(of('1/1/71')!.room, isNull);
    expect(of('2/0/2'), isNull); // einzelne Adresse ist kein Objekt
    expect(of('1/0/0'), isNull);
  });
}
