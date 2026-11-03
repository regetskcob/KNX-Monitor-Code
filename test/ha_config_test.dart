import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/export/ha_config.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:yaml/yaml.dart';

/// Schlüssel je Plattform laut Schema der KNX-Integration (Home Assistant
/// core, components/knx/schema.py, Stand 10/2026) – nur die, die der
/// Generator schreiben darf.
const _allowed = {
  'light': {'name', 'address', 'state_address', 'brightness_address', 'brightness_state_address'},
  'cover': {
    'name',
    'move_long_address',
    'move_short_address',
    'stop_address',
    'position_address',
    'position_state_address',
    'angle_address',
    'angle_state_address',
  },
  'climate': {
    'name',
    'temperature_address',
    'target_temperature_address',
    'target_temperature_state_address',
    'setpoint_shift_address',
    'setpoint_shift_state_address',
    'setpoint_shift_mode',
    'operation_mode_address',
    'operation_mode_state_address',
    'controller_mode_address',
    'controller_mode_state_address',
    'heat_cool_address',
    'heat_cool_state_address',
    'command_value_state_address',
  },
  'switch': {'name', 'address', 'state_address'},
  'binary_sensor': {'name', 'state_address', 'device_class'},
  'sensor': {'name', 'state_address', 'type'},
};

const _required = {
  'light': {'address'},
  'climate': {'temperature_address', 'target_temperature_state_address'},
  'switch': {'address'},
  'binary_sensor': {'state_address'},
  'sensor': {'state_address', 'type'},
};

final _ga = RegExp(r'^\d{1,2}/\d/\d{1,3}$');

/// Prüft eine erzeugte Datei gegen das Schema: bekannte Plattformen und
/// Schlüssel, Pflichtschlüssel, Adressformat, `type`, Inclusive-Gruppen.
List<String> schemaErrors(String text) {
  final errors = <String>[];
  final doc = loadYaml(text) as YamlMap?;
  if (doc == null) return ['leer'];
  for (final MapEntry(:key, :value) in doc.entries) {
    final platform = key as String;
    final allowed = _allowed[platform];
    if (allowed == null) {
      errors.add('Plattform $platform');
      continue;
    }
    for (final entity in value as YamlList) {
      final e = entity as YamlMap;
      for (final k in e.keys) {
        if (k == 'device') {
          final d = e[k];
          if (d is! YamlMap || d['id'] is! String || d.keys.any((x) => x != 'id' && x != 'name')) {
            errors.add('$platform.device=$d');
          }
          continue;
        }
        if (!allowed.contains(k)) errors.add('$platform.$k');
        if ('$k'.endsWith('_address') && !_ga.hasMatch('${e[k]}')) errors.add('$platform.$k=${e[k]}');
      }
      for (final k in _required[platform] ?? const <String>{}) {
        if (!e.containsKey(k)) errors.add('$platform fehlt $k (${e['name']})');
      }
      if (platform == 'cover' && !e.containsKey('move_long_address') && !e.containsKey('position_address')) {
        errors.add('cover ohne Fahrbefehl');
      }
      if (e.containsKey('setpoint_shift_address') != e.containsKey('setpoint_shift_state_address')) {
        errors.add('setpoint_shift nur halb');
      }
      if (platform == 'sensor' &&
          !RegExp(r'^([a-z0-9_]+|percentU8|percentV8|\d+(\.\d{3})?)$').hasMatch('${e['type']}')) {
        errors.add('type ${e['type']}');
      }
      if (e['name'] is! String) errors.add('name ${e['name']}');
    }
  }
  return errors;
}

int _a(String ga) => parseGroup(ga)!;

GroupInfo _g(String ga, String name, Dpt? dpt, {String? path, List<GroupLink> links = const []}) =>
    GroupInfo(address: _a(ga), name: name, dpt: dpt, path: path, links: links);

void main() {
  test('Demo-Haus: gültiges YAML nach dem HA-Schema', () {
    final catalog = demoCatalog();
    final entities = HaConfig.fromCatalog(catalog);
    final text = HaConfig.toYaml(entities, catalog: catalog, appVersion: '1.9.0', created: DateTime(2026, 10, 29));
    expect(schemaErrors(text), isEmpty, reason: text);

    final byPlatform = {for (final p in HaPlatform.values) p: entities.where((e) => e.platform == p).toList()};
    expect(byPlatform[HaPlatform.light], hasLength(16)); // L01 je Raum + L02 (nur Dimmwert, auskommentiert)
    expect(byPlatform[HaPlatform.cover], hasLength(8));
    expect(byPlatform[HaPlatform.climate], hasLength(8));
    final kitchen = byPlatform[HaPlatform.light]!.firstWhere((e) => e.name == 'EG KÜ L01');
    expect(kitchen.addresses, {'address': _a('1/0/1'), 'state_address': _a('1/1/1')});
    expect(kitchen.uncertain, isFalse);
    final dimOnly = byPlatform[HaPlatform.light]!.firstWhere((e) => e.name == 'EG KÜ L02');
    expect(dimOnly.incomplete, isTrue);
    expect(text, contains('  # - name: "EG KÜ L02"'));

    final cover = byPlatform[HaPlatform.cover]!.firstWhere((e) => e.name == 'EG WZ F01');
    expect(cover.addresses.keys, ['move_long_address', 'move_short_address', 'position_state_address']);

    // Soll-Temperatur ohne Rückmeldung: markiert, nicht geraten.
    final climate = byPlatform[HaPlatform.climate]!.first;
    expect(climate.doubts, contains(HaDoubt.targetFromCommand));
    expect(climate.addresses['command_value_state_address'], isNotNull);

    final outdoor = byPlatform[HaPlatform.sensor]!.firstWhere((e) => e.addresses['state_address'] == _a('4/0/0'));
    expect(outdoor.options['type'], 'temperature');
    expect(outdoor.room, 'Wetter');
    final smoke = byPlatform[HaPlatform.binarySensor]!.firstWhere((e) => e.addresses['state_address'] == _a('6/0/0'));
    expect(smoke.options['device_class'], 'smoke');
    // Befehle werden keine Sensoren.
    final sensorAddresses = {for (final e in byPlatform[HaPlatform.sensor]!) e.addresses['state_address']};
    expect(sensorAddresses, isNot(contains(_a('1/2/1'))));
  });

  test('Vollständiger Raumregler, Dimmer, Jalousie mit Lamelle', () {
    final catalog = GroupCatalog({
      for (final g in [
        _g('1/1/1', 'EG WZ L01 Schalten', const Dpt(1, 1)),
        _g('1/1/2', 'EG WZ L01 Rückmeldung Schalten', const Dpt(1, 1)),
        _g('1/1/3', 'EG WZ L01 Helligkeitswert', const Dpt(5, 1)),
        _g('1/1/4', 'EG WZ L01 Rückmeldung Helligkeitswert', const Dpt(5, 1)),
        _g('1/1/5', 'EG WZ L01 Dimmen relativ', const Dpt(3, 7)),
        _g('3/1/1', 'EG WZ F01 Auf/Ab', const Dpt(1, 8)),
        _g('3/1/2', 'EG WZ F01 Stopp/Lamelle', const Dpt(1, 7)),
        _g('3/1/3', 'EG WZ F01 Position', const Dpt(5, 1)),
        _g('3/1/4', 'EG WZ F01 Aktuelle Position', const Dpt(5, 1)),
        _g('3/1/5', 'EG WZ F01 Lamelle Position', const Dpt(5, 1)),
        _g('3/1/6', 'EG WZ F01 Aktuelle Lamelle Position', const Dpt(5, 1)),
        _g('2/1/1', 'EG WZ HZ01 Ist-Temperatur', const Dpt(9, 1)),
        _g('2/1/2', 'EG WZ HZ01 Sollwert', const Dpt(9, 1)),
        _g('2/1/3', 'EG WZ HZ01 Aktueller Sollwert', const Dpt(9, 1)),
        _g('2/1/4', 'EG WZ HZ01 Betriebsart', const Dpt(20, 102)),
        _g('2/1/5', 'EG WZ HZ01 Status Betriebsart', const Dpt(20, 102)),
        _g('2/1/6', 'EG WZ HZ01 Stellgröße', const Dpt(5, 1)),
        _g('2/1/7', 'EG WZ HZ01 Sollwertverschiebung', const Dpt(9, 2)),
        _g('2/1/8', 'EG WZ HZ01 Status Sollwertverschiebung', const Dpt(9, 2)),
      ])
        g.address: g,
    });
    final entities = HaConfig.fromCatalog(catalog);
    final text = HaConfig.toYaml(entities, catalog: catalog);
    expect(schemaErrors(text), isEmpty, reason: text);

    final light = entities.singleWhere((e) => e.platform == HaPlatform.light);
    expect(light.addresses, {
      'address': _a('1/1/1'),
      'state_address': _a('1/1/2'),
      'brightness_address': _a('1/1/3'),
      'brightness_state_address': _a('1/1/4'),
    });
    expect(light.uncertain, isFalse);

    final cover = entities.singleWhere((e) => e.platform == HaPlatform.cover);
    expect(cover.addresses, {
      'move_long_address': _a('3/1/1'),
      'move_short_address': _a('3/1/2'),
      'angle_address': _a('3/1/5'),
      'angle_state_address': _a('3/1/6'),
      'position_address': _a('3/1/3'),
      'position_state_address': _a('3/1/4'),
    });

    final climate = entities.singleWhere((e) => e.platform == HaPlatform.climate);
    expect(climate.addresses, {
      'temperature_address': _a('2/1/1'),
      'target_temperature_state_address': _a('2/1/3'),
      'target_temperature_address': _a('2/1/2'),
      'setpoint_shift_address': _a('2/1/7'),
      'setpoint_shift_state_address': _a('2/1/8'),
      'operation_mode_address': _a('2/1/4'),
      'operation_mode_state_address': _a('2/1/5'),
      'command_value_state_address': _a('2/1/6'),
    });
    expect(climate.options['setpoint_shift_mode'], 'DPT9002');
    expect(climate.uncertain, isFalse);
  });

  test('Unsicheres wird markiert: neutraler Name, fehlender DPT, nur Haupttyp', () {
    final catalog = GroupCatalog({
      for (final g in [
        _g('1/2/1', 'Garten Pumpe Schalten', const Dpt(1, 1)),
        _g('1/2/2', 'Garten Pumpe Status', const Dpt(1, 1)),
        _g('1/2/10', 'OG Flur X Schalten', const Dpt(1, 1)),
        _g('1/2/11', 'OG Flur X Sperre', const Dpt(1, 3)),
        _g('1/3/1', 'EG KÜ L03 Schalten', null),
        _g('1/3/2', 'EG KÜ L03 Rückmeldung', null),
        _g('4/0/9', 'Zähler "Garage" Status', const Dpt(12)),
      ])
        g.address: g,
    });
    final entities = HaConfig.fromCatalog(catalog);
    final text = HaConfig.toYaml(entities, catalog: catalog);
    expect(schemaErrors(text), isEmpty, reason: text);

    final pump = entities.firstWhere((e) => e.addresses['address'] == _a('1/2/1'));
    expect(pump.platform, HaPlatform.switchPlatform);
    expect(pump.uncertain, isFalse); // Pumpe ist ein Verbraucher, kein Licht

    final neutral = entities.firstWhere((e) => e.addresses['address'] == _a('1/2/10'));
    expect(neutral.platform, HaPlatform.switchPlatform);
    expect(neutral.doubts, containsAll([HaDoubt.lightOrSwitch, HaDoubt.noState]));

    final noDpt = entities.firstWhere((e) => e.addresses['address'] == _a('1/3/1'));
    expect(noDpt.platform, HaPlatform.light);
    expect(noDpt.doubts, contains(HaDoubt.noDpt));

    final counter = entities.firstWhere((e) => e.platform == HaPlatform.sensor);
    expect(counter.options['type'], '4byte_unsigned');
    expect(counter.doubts, contains(HaDoubt.typeGuessed));
    // Anführungszeichen im Namen sauber escaped.
    expect((loadYaml(text) as YamlMap)['sensor'][0]['name'], 'Zähler "Garage" Status');
    expect(text, contains('# Prüfen:'));
  });

  test('Sensor-Typen nach xknx bzw. als DPT-Nummer', () {
    expect(HaConfig.sensorType(const Dpt(9, 1)), 'temperature');
    expect(HaConfig.sensorType(const Dpt(9, 7)), 'humidity');
    expect(HaConfig.sensorType(const Dpt(14, 56)), 'power');
    expect(HaConfig.sensorType(const Dpt(14, 19)), '14.019');
    expect(HaConfig.sensorType(const Dpt(9)), '2byte_float');
    expect(HaConfig.sensorType(const Dpt(1, 1)), isNull);
    expect(HaConfig.sensorType(const Dpt(20, 102)), isNull);
  });

  test('Gerätevorschläge: Wetterstation nach sendendem Gerät, nur übernommene in der Datei', () {
    final catalog = demoCatalog();
    final entities = HaConfig.fromCatalog(catalog);
    final devices = HaConfig.devices(entities, catalog);
    final weather = devices.firstWhere((d) => d.source == HaDeviceSource.busDevice && d.id == 'knx_1_2_20');
    final weatherAddresses = {
      for (final e in entities)
        if (weather.entities.contains(e.id)) e.addresses['state_address'],
    };
    expect(weatherAddresses, containsAll([_a('4/0/0'), _a('4/0/1'), _a('4/0/2')]));
    expect(weather.room, 'Wetter');
    // Kein Vorschlag fasst eine Entität doppelt.
    final all = [for (final d in devices) ...d.entities];
    expect(all.toSet(), hasLength(all.length));
    expect({for (final d in devices) d.id}, hasLength(devices.length));

    // Ohne Übernahme bleibt die Datei wie bisher.
    expect(HaConfig.toYaml(entities, catalog: catalog), isNot(contains('device:')));

    final text = HaConfig.toYaml(entities, catalog: catalog, devices: [weather]);
    expect(schemaErrors(text), isEmpty, reason: text);
    final sensors = (loadYaml(text) as YamlMap)['sensor'] as YamlList;
    final outdoor = sensors.firstWhere((e) => e['state_address'] == '4/0/0') as YamlMap;
    expect(outdoor['device'], {'id': 'knx_1_2_20', 'name': weather.name});
    final withDevice = [
      for (final p in (loadYaml(text) as YamlMap).values)
        ...(p as YamlList).where((e) => (e as YamlMap).containsKey('device')),
    ];
    expect(withDevice, hasLength(weather.entities.length));
  });

  test('Gerätevorschläge: Objekt mit mehreren Entitäten aus dem Namensschema', () {
    final catalog = GroupCatalog({
      for (final g in [
        _g('2/1/1', 'EG KÜ HZ01 Ist-Temperatur', const Dpt(9, 1)),
        _g('2/1/2', 'EG KÜ HZ01 Sollwert', const Dpt(9, 1)),
        _g('2/1/3', 'EG KÜ HZ01 Status Fenster', const Dpt(1, 19)),
        _g('2/1/4', 'EG KÜ HZ01 Status Luftfeuchte', const Dpt(9, 7)),
        _g('1/1/1', 'EG KÜ L01 Schalten', const Dpt(1, 1)),
        _g('1/1/2', 'EG KÜ L01 Rückmeldung Schalten', const Dpt(1, 1)),
      ])
        g.address: g,
    });
    final entities = HaConfig.fromCatalog(catalog);
    final devices = HaConfig.devices(entities, catalog);
    // Die Leuchte ist eine einzige Entität: kein eigenes Gerät.
    final device = devices.single;
    expect(device.id, 'eg_kue_hz01');
    expect(device.source, HaDeviceSource.nameScheme);
    expect(device.room, 'EG KÜ');
    expect(device.entities, hasLength(3)); // Regler, Fenster, Luftfeuchte

    final text = HaConfig.toYaml(entities, catalog: catalog, devices: devices);
    expect(schemaErrors(text), isEmpty, reason: text);
    expect((loadYaml(text) as YamlMap)['climate'][0]['device']['id'], 'eg_kue_hz01');
    expect((loadYaml(text) as YamlMap)['light'][0].containsKey('device'), isFalse);
  });

  test('Geräte-Kennung', () {
    expect(HaConfig.slug('EG KÜ HZ01'), 'eg_kue_hz01');
    expect(HaConfig.slug(' Wetter-Station (Dach) '), 'wetter_station_dach');
  });
}
