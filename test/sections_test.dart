import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/sections.dart';

void main() {
  final cases = <String, (String name, String? path, Dpt? dpt, String section)>{
    '8/2/2': ('EG TE Helligkeit', 'Sonstiges › Helligkeit', const Dpt(9, 4), 'type:brightness'),
    '8/1/1': ('Windgeschwindigkeit', 'Sonstiges › Wetter', const Dpt(9, 5), 'type:weather'),
    '8/1/0': ('Regen', 'Sonstiges › Wetter', const Dpt(1, 1), 'type:weather'),
    '8/1/2': ('Außentemperatur', 'Sonstiges', const Dpt(9, 1), 'type:weather'),
    '1/4/73': ('Außenleuchte Deich Rückmeldung', 'Beleuchtung › Rückmeldung', const Dpt(1, 1), 'main:1'),
    '2/0/0': ('EG FL Ist-Temperatur', 'Heizung › Ist', const Dpt(9, 1), 'main:2'),
    '2/2/0': ('EG FL Ventil-Zustand', 'Heizung › Ventil-Zustand', const Dpt(1, 11), 'type:valves'),
    '2/3/0': ('EG FL Stellgröße', 'Heizung › Stellgröße', const Dpt(5, 1), 'type:valves'),
    '8/4/8': ('Leistung Waschmaschine', 'Sonstiges › Verbrauch', const Dpt(14, 56), 'type:energy'),
    '8/4/0': ('Verbrauch Pumpe', 'Sonstiges › Verbrauch', const Dpt(13, 10), 'type:energy'),
    '8/0/1': ('Uhrzeit', 'Sonstiges › Datum / Uhrzeit', const Dpt(10, 1), 'type:datetime'),
    // Englische Projekte
    '9/0/0': ('Wind Speed', 'Weather Station', const Dpt(9, 5), 'type:weather'),
    '9/0/1': ('Outdoor Temperature', 'Weather Station', const Dpt(9, 1), 'type:weather'),
    '9/0/2': ('Sun Elevation', 'Weather Station', const Dpt(9, 1), 'type:weather'),
    '9/1/0': ('Power Heat Pump', 'Energy › Meters', const Dpt(14, 56), 'type:energy'),
    '9/1/1': ('PV Feed-in', 'Energy › Meters', const Dpt(13, 10), 'type:energy'),
    '9/2/0': ('GF Kitchen Current Temperature', 'Heating › GF', const Dpt(9, 1), 'main:9'),
    '9/2/1': ('GF Kitchen Valve Position', 'Heating › GF', const Dpt(5, 1), 'type:valves'),
    '9/3/0': ('Smoke Detector Hallway', 'Safety', const Dpt(1, 1), 'type:alarms'),
    '9/3/1': ('Actuator Fault', 'Diagnostics', const Dpt(1, 1), 'type:alarms'),
  };

  setUp(() {
    CatalogStore.instance.catalog = GroupCatalog({
      for (final MapEntry(key: ga, value: c) in cases.entries)
        parseGroup(ga)!: GroupInfo(address: parseGroup(ga)!, name: c.$1, path: c.$2, dpt: c.$3),
    });
  });

  for (final MapEntry(key: ga, value: c) in cases.entries) {
    test('${c.$1} → ${c.$4}', () => expect(sectionFor(parseGroup(ga)!).id, c.$4));
  }

  test('ohne Projekt: Hauptgruppe', () {
    CatalogStore.instance.catalog = GroupCatalog.empty;
    expect(sectionFor(parseGroup('3/1/2')!).id, 'main:3');
  });
}
