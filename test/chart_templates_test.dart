import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/model/chart_templates.dart';

void main() {
  List<ChartTemplate> of(Map<int, GroupInfo> groups, [Map<int, DeviceInfo> devices = const {}]) =>
      chartTemplates(groups, devices, dptOf: (a) => groups[a]?.dpt);

  GroupInfo g(int a, String name, Dpt? dpt, {String? path, List<GroupLink> links = const []}) =>
      GroupInfo(address: a, name: name, dpt: dpt, path: path, links: links);

  test('Demo-Haus: Raumklima je Raum, Licht, Beschattung je Geschoss, Wetter, Energie', () {
    final c = demoCatalog();
    final list = of(c.groups, c.devices);
    String name(int a) => c.groups[a]!.name;
    final climate = list.where((t) => t.recipe == ChartRecipe.climate).toList();
    expect(climate.map((t) => t.place), containsAll(['EG KÜ', 'EG WZ', 'OG BZ']));
    final kitchen = climate.firstWhere((t) => t.place == 'EG KÜ');
    expect(kitchen.addresses.map(name), [
      'EG KÜ Ist-Temperatur',
      'EG KÜ Soll-Temperatur',
      'EG KÜ Stellwert Heizen (%)',
    ]);
    final light = list.firstWhere((t) => t.recipe == ChartRecipe.light && t.place == 'EG WZ');
    expect(light.addresses.map(name), contains('EG WZ L01 Rückmeldung Schalten'));
    expect(list.where((t) => t.recipe == ChartRecipe.shading).map((t) => t.place), ['EG', 'OG']);
    expect(list.where((t) => t.recipe == ChartRecipe.weather), hasLength(1));
    expect(list.where((t) => t.recipe == ChartRecipe.energy), hasLength(1));
    for (final t in list) {
      expect(t.addresses.length, inInclusiveRange(1, 8));
      expect(t.addresses.toSet(), hasLength(t.addresses.length));
    }
    // Nach Rezept sortiert.
    expect([for (final t in list) t.recipe.index], orderedEquals([...list.map((t) => t.recipe.index)]..sort()));
  });

  test('Rollenwort vorne, englische Namen', () {
    final list = of({
      1: g(1, 'Ist-Temperatur Wohnen', const Dpt(9, 1)),
      2: g(2, 'Sollwert Wohnen', const Dpt(9, 1)),
      3: g(3, 'Kitchen actual temperature', const Dpt(9, 1)),
      4: g(4, 'Kitchen setpoint', const Dpt(9, 1)),
      5: g(5, 'Kitchen valve', const Dpt(5, 1)),
    });
    expect([for (final t in list) t.place], ['Kitchen', 'Wohnen']);
    expect(list[0].addresses, [3, 4, 5]);
    expect(list[1].addresses, [1, 2]);
  });

  test('Ort aus der ETS-Gebäudestruktur, wenn der Name keinen hergibt', () {
    final list = of(
      {
        1: g(1, 'Ist-Temperatur', const Dpt(9, 1), links: const [GroupLink(device: 0x1101, sends: true)]),
        2: g(2, 'Sollwert', const Dpt(9, 1), links: const [GroupLink(device: 0x1101, sends: true)]),
      },
      {0x1101: const DeviceInfo(address: 0x1101, name: 'RTR', location: 'EG › Bad')},
    );
    expect(list.single.place, 'Bad');
    expect(list.single.addresses, [1, 2]);
  });

  test('Kanalkürzel sind kein Ort: Rückfall auf den ETS-Ort', () {
    const sender = [GroupLink(device: 0x1101, sends: true)];
    final list = of(
      {
        1: g(1, 'L01 Rückmeldung Schalten', const Dpt(1, 1), path: 'Beleuchtung › Rückmeldung', links: sender),
        2: g(2, 'L02 Rückmeldung Schalten', const Dpt(1, 1), path: 'Beleuchtung › Rückmeldung', links: sender),
        3: g(3, 'EG WZ L01 Rückmeldung Schalten', const Dpt(1, 1), path: 'Beleuchtung › Rückmeldung'),
        4: g(4, 'EG WZ L02 Rückmeldung Schalten', const Dpt(1, 1), path: 'Beleuchtung › Rückmeldung'),
      },
      {0x1101: const DeviceInfo(address: 0x1101, name: 'Aktor', location: 'OG › Bad')},
    );
    // Nur Rückmeldungen reichen für Licht; L01/L02 bilden keinen Raum.
    expect([for (final t in list) t.place], ['Bad', 'EG WZ']);
    expect(
      [for (final t in list) t.addresses],
      [
        [1, 2],
        [3, 4],
      ],
    );
  });

  test('ohne Datentyp oder mit nur einer Reihe: keine Vorlage', () {
    expect(of({1: g(1, 'EG Ist-Temperatur', null), 2: g(2, 'EG Sollwert', null)}), isEmpty);
    expect(of({1: g(1, 'EG Ist-Temperatur', const Dpt(9, 1))}), isEmpty);
  });
}
