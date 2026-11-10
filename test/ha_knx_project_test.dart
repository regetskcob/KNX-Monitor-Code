import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/ha_knx_project_parser.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/project_check.dart';

// Shape of xknxproject's KNXProject as Home Assistant's knx/get_knx_project returns it; own data.
Map<String, Object?> _project({bool withLoaded = true}) => {
  'info': {'name': 'Testhaus', 'group_address_style': 'ThreeLevel'},
  'devices': {
    '1.1.5': {
      'name': '',
      'hardware_name': 'Schaltaktor 4-fach',
      'order_number': 'AKS-0416',
      'description': 'Verteiler',
      'manufacturer_name': 'MDT technologies',
      'individual_address': '1.1.5',
      'application': 'M-0083_A-0001-10-AAAA',
      'product_id': 'M-0083_H-1_P-AKS',
      'serial_number': 'AIN5ogXG',
      if (withLoaded) ...{
        'last_download': '2026-10-17T14:24:40',
        'individual_address_loaded': true,
        'application_program_loaded': true,
        'communication_part_loaded': false,
        'medium_config_loaded': true,
        'parameters_loaded': true,
      },
    },
    '1.1.50': {
      'name': 'Taster Küche',
      'hardware_name': 'Taster',
      'individual_address': '1.1.50',
      'manufacturer_name': 'MDT technologies',
      if (withLoaded) 'last_download': null,
    },
  },
  'communication_objects': {
    '1.1.5/M-0083_A-0001-10-AAAA_O-0_R-1': {
      'number': 0,
      'text': 'Kanal A',
      'function_text': 'Schalten',
      'device_address': '1.1.5',
      'module_def': null,
      'dpts': [
        {'main': 1, 'sub': 1},
      ],
      'group_address_links': ['1/1/0', '1/0/0'],
      'flags': {
        'read': false,
        'write': true,
        'communication': true,
        'transmit': false,
        'update': false,
        'read_on_init': false,
      },
    },
    '1.1.5/M-0083_A-0001-10-AAAA_O-1_R-2': {
      'number': 1,
      'text': 'Kanal A',
      'function_text': 'Status',
      'device_address': '1.1.5',
      'module_def': null,
      'dpts': [
        {'main': 1, 'sub': 1},
      ],
      'group_address_links': ['1/4/0'],
      'flags': {
        'read': true,
        'write': false,
        'communication': true,
        'transmit': true,
        'update': false,
        'read_on_init': false,
      },
    },
    '1.1.50/M-0083_A-0002-10-BBBB_MD-1_M-1_MI-1_O-3-0_R-5': {
      'number': 3,
      'text': 'Taste 1',
      'function_text': '',
      'device_address': '1.1.50',
      'module_def': {'definition': 'MD-1', 'root_number': 3},
      'dpts': <Object?>[],
      'group_address_links': ['1/1/0'],
      'flags': {
        'read': false,
        'write': false,
        'communication': true,
        'transmit': true,
        'update': false,
        'read_on_init': false,
      },
    },
  },
  'group_addresses': {
    '1/0/0': {'name': 'Zentral Aus', 'raw_address': 2048, 'address': '1/0/0', 'dpt': null, 'description': ''},
    '1/1/0': {
      'name': 'Küche Licht',
      'raw_address': 2304,
      'address': '1/1/0',
      'dpt': {'main': 1, 'sub': 1},
      'description': 'Decke',
    },
    '1/4/0': {'name': 'Küche Licht Status', 'raw_address': 3072, 'address': '1/4/0', 'dpt': null, 'description': ''},
  },
  'group_ranges': {
    '1': {
      'name': 'Licht',
      'group_addresses': <String>[],
      'group_ranges': {
        '1/0': {
          'name': 'Zentral',
          'group_addresses': ['1/0/0'],
          'group_ranges': <String, Object?>{},
        },
        '1/1': {
          'name': 'Schalten',
          'group_addresses': ['1/1/0'],
          'group_ranges': <String, Object?>{},
        },
        '1/4': {
          'name': 'Status',
          'group_addresses': ['1/4/0'],
          'group_ranges': <String, Object?>{},
        },
      },
    },
  },
  'locations': {
    'Haus': {
      'type': 'Building',
      'name': 'Haus',
      'devices': <String>[],
      'spaces': {
        'EG': {
          'type': 'Floor',
          'name': 'EG',
          'devices': <String>[],
          'spaces': {
            'Küche': {
              'type': 'Room',
              'name': 'Küche',
              'devices': ['1.1.5'],
              'spaces': <String, Object?>{},
            },
          },
        },
      },
    },
  },
};

void main() {
  test('Adressen, Bereiche, Datentypen, Geräte und Verknüpfungen', () {
    final c = parseHaKnxProject(_project(), haGroups: ['1/0/0', '9/9/9x']);
    expect(c.projectName, 'Testhaus');
    expect(c.length, 3);
    final licht = c[parseGroup('1/1/0')!]!;
    expect(licht.path, 'Licht › Schalten');
    expect(licht.description, 'Decke');
    expect(licht.links.map((l) => (formatIndividual(l.device), l.sends)), [('1.1.5', false), ('1.1.50', true)]);
    expect(licht.links.first.ref, 'M-0083_A-0001-10-AAAA_O-0_R-1');
    expect(licht.links.first.text, 'Kanal A – Schalten');
    expect(licht.links.first.object, 0);
    // Objekt aus einem Modul: Nummer nicht sicher.
    expect(licht.links.last.object, isNull);
    // Datentyp vom Objekt, wenn die Adresse keinen hat.
    expect(c[parseGroup('1/4/0')!]!.dpt, const Dpt(1, 1));
    // Zweite Adresse des Aktor-Eingangs: hört.
    expect(c[parseGroup('1/0/0')!]!.links.single.sends, isFalse);

    final aktor = c.devices[parseIndividual('1.1.5')]!;
    expect(aktor.name, 'Schaltaktor 4-fach');
    expect(aktor.location, 'EG › Küche');
    expect(aktor.serial, '008379A205C6');
    expect(aktor.pendingDownload, [DownloadPart.groups]);
    expect(c.devices[parseIndividual('1.1.50')]!.neverProgrammed, isTrue);
    expect(c.manufacturers[0x83], 'MDT technologies');
    expect(c.externalSenders, {parseGroup('1/0/0')!});
    expect(GroupCatalog.fromJson(c.toJson()).externalSenders, {parseGroup('1/0/0')!});
  });

  // KNX RF: xknxproject names the medium per line in the topology.
  test('radio line: devices of a line with medium RF are marked', () {
    expect(parseHaKnxProject(_project()).rfLines, isEmpty);
    final c = parseHaKnxProject({
      ..._project(),
      'topology': {
        '1': {
          'name': 'Haus',
          'lines': {
            '1': {
              'name': 'Funk',
              'medium_type': 'Radio Frequency (RF)',
              'devices': ['1.1.50'],
            },
            '0': {
              'name': 'Hauptlinie',
              'medium_type': 'Twisted Pair (TP)',
              'devices': ['1.1.5'],
            },
          },
        },
      },
    });
    expect(c.devices[0x1132]!.rf, isTrue);
    expect(c.devices[0x1105]!.rf, isFalse);
    expect(c.rfLines, {0x11});
  });

  test('medium names of all three sources', () {
    for (final rf in ['MT-2', 'RF', 'rf', 'Radio Frequency (RF)', 'KNX RF']) {
      expect(isRfMedium(rf), isTrue, reason: rf);
    }
    for (final other in [null, 7, '', 'MT-0', 'TP', 'Twisted Pair (TP)', 'KNXnet/IP (IP)', 'Powerline (PL)', 'surf']) {
      expect(isRfMedium(other), isFalse, reason: '$other');
    }
  });

  test('ältere xknxproject-Version ohne Download-Angaben: kein Befund', () {
    final c = parseHaKnxProject(_project(withLoaded: false));
    expect(c.devices.values.where((d) => d.neverProgrammed || d.pendingDownload.isNotEmpty), isEmpty);
  });

  test('Prüfung: von Home Assistant beschrieben zählt als Sender', () {
    final without = ProjectLint.of(parseHaKnxProject(_project()));
    expect(without.withoutSender.map((g) => formatGroup(g.address)), contains('1/0/0'));
    final c = parseHaKnxProject(_project(), haGroups: ['1/0/0']);
    CatalogStore.instance.catalog = c;
    expect(ProjectLint.of(c).withoutSender.map((g) => formatGroup(g.address)), isNot(contains('1/0/0')));
  });

  test('kein Projekt', () {
    expect(() => parseHaKnxProject({'info': <String, Object?>{}}), throwsFormatException);
  });
}
