import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/device_channels.dart';
import 'package:knx_monitor/model/device_shapes.dart';

void main() {
  test('Bauform aus Produktnamen wie im Projekt', () {
    final products = {
      'BE-04001.02 Tasterinterface 4-fach, UP, Ausführung potentialfrei': DeviceShape.flushInput,
      'SCN-P360D1.01 Präsenzmelder 1S Mini': DeviceShape.ceilingPresence,
      'thePrema S360 KNX': DeviceShape.ceilingPresence,
      'theLuxa P300 KNX': DeviceShape.wallMotion,
      'Meteodata 140 S 24V': DeviceShape.weatherStation,
      'Gira KNX RWM': DeviceShape.smokeDetector,
      'Gira Dual-Q Rauchmelder': DeviceShape.smokeDetector,
      'AKS-2016.03 Schaltaktor 20-fach, 12TE, 16A': DeviceShape.din,
      'Binäreingang 8-fach REG': DeviceShape.din,
      'Binäreingang 8-fach, 4TE': DeviceShape.din,
      '4-fach UP-Fensterkontakt TE/WC Tasterinterface': DeviceShape.flushInput,
    };
    final devices = {
      for (final (i, p) in products.keys.indexed) 0x1100 + i: DeviceInfo(address: 0x1100 + i, name: p, product: p),
    };
    final catalog = GroupCatalog(const {}, devices: devices);
    CatalogStore.instance.catalog = catalog;
    for (final (i, shape) in products.values.indexed) {
      expect(shapeOf(0x1100 + i, catalog), shape, reason: products.keys.elementAt(i));
    }
  });

  test('Rollen der Sensor-Objekte und Himmelsrichtungen', () {
    final station = parseIndividual('1.2.20')!;
    GroupInfo ga(String a, String name, Dpt dpt) => GroupInfo(
      address: parseGroup(a)!,
      name: name,
      dpt: dpt,
      links: [GroupLink(device: station, sends: true)],
    );
    final catalog = GroupCatalog({
      for (final g in [
        ga('8/1/4', 'Außenhelligkeit NW (vorne)', const Dpt(9, 4)),
        ga('8/1/2', 'Außentemperatur', const Dpt(9, 1)),
        ga('8/1/12', 'Außentemperatur Sensor defekt', const Dpt(1, 1)),
        ga('8/1/1', 'Windgeschwindigkeit (m/s)', const Dpt(9, 5)),
        ga('8/1/0', 'Regen', const Dpt(1, 1)),
        ga('8/1/9', 'Azimut', const Dpt(14, 7)),
        ga('8/3/0', 'EG FL Präsenz', const Dpt(1, 18)),
        ga('8/0/3', 'Tag / Nacht', const Dpt(1, 2)),
      ])
        g.address: g,
    });
    final roles = {for (final o in objectsOf(station, catalog)) catalog[o.address]!.name: roleOf(o, catalog)};
    expect(roles, {
      'Außenhelligkeit NW (vorne)': SensorRole.brightness,
      'Außentemperatur': SensorRole.temperature,
      'Außentemperatur Sensor defekt': null,
      'Windgeschwindigkeit (m/s)': SensorRole.wind,
      'Regen': SensorRole.rain,
      'Azimut': SensorRole.azimuth,
      'EG FL Präsenz': SensorRole.presence,
      'Tag / Nacht': SensorRole.dayNight,
    });
    expect(bearingOf('Außenhelligkeit NW (vorne)'), 315);
    expect(bearingOf('Helligkeit Ost'), 90);
    expect(bearingOf('Außenhelligkeit'), isNull);
    expect(const DeviceObject(address: 1).sends, isFalse);
  });
}
