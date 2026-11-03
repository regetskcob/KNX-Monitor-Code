import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/dpt_codec.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';

Telegram _write(List<int> data, {bool small = false}) => Telegram(
  time: DateTime(2026),
  source: 0x1105,
  destination: 1,
  type: TelegramType.write,
  data: Uint8List.fromList(data),
  isSmall: small,
);

void main() {
  group('ETS-CSV', () {
    test('Format 3/1 mit Bereichen, Komma, BOM', () {
      const csv =
          '﻿"Main","Middle","Sub","Address","Central","Unfiltered","Description","DatapointType","Security"\n'
          '"Licht","","","1/-/-","","","","",""\n'
          '"","Schalten","","1/1/-","","","","",""\n'
          '"","","Küche ""Insel""","1/1/7","","","","DPST-1-1","Auto"\n'
          '"Klima","","","3/-/-","","","","",""\n'
          '"","Ist","","3/0/-","","","","",""\n'
          '"","","Temp, Bad","3/0/1","","","","DPST-9-1","Auto"\n';
      final c = GroupCatalog.parseCsv(csv);
      expect(c.length, 2);
      final k = c[parseGroup('1/1/7')!]!;
      expect(k.name, 'Küche "Insel"');
      expect(k.path, 'Licht › Schalten');
      expect(k.dpt.toString(), '1.001');
      expect(c[parseGroup('3/0/1')!]!.name, 'Temp, Bad');
      expect(c[parseGroup('3/0/1')!]!.path, 'Klima › Ist');
    });

    test('Format 1/1 mit Semikolon und Latin-1', () {
      const csv =
          '"Group name";"Address";"Central";"Unfiltered";"Description";"DatapointType";"Security"\r\n'
          '"Rollo Süd";"2/3/4";"";"";"";"DPST-1-8";"Auto"\r\n'
          '"Helligkeit";"4/0/9";"";"";"";"DPT-9";"Auto"\r\n';
      final c = GroupCatalog.parseCsv(GroupCatalog.decodeBytes(Uint8List.fromList(latin1.encode(csv))));
      expect(c[parseGroup('2/3/4')!]!.name, 'Rollo Süd');
      expect(c[parseGroup('4/0/9')!]!.dpt.toString(), '9.xxx');
    });

    test('ungültige Datei', () {
      expect(() => GroupCatalog.parseCsv('foo,bar\n1,2'), throwsFormatException);
    });
  });

  group('DPT', () {
    test('dekodiert mit Einheit und Labels', () {
      expect(decodeDpt(const Dpt(9, 1), _write([0x0C, 0x24])), '21,2 °C');
      expect(decodeDpt(const Dpt(1, 8), _write([1], small: true)), 'Ab');
      expect(decodeDpt(const Dpt(5, 1), _write([0xFF])), '100 %');
      expect(decodeDpt(const Dpt(3, 7), _write([0x09], small: true)), 'Heller · 1/1');
      expect(decodeDpt(const Dpt(10, 1), _write([0x6E, 0x2F, 0x00])), 'Mi 14:47:00');
      expect(decodeDpt(const Dpt(11, 1), _write([0x0E, 0x0A, 0x1A])), '14.10.2026');
      expect(
        decodeDpt(const Dpt(19, 1), _write([0x7E, 0x0A, 0x0E, 0x6E, 0x2F, 0x00, 0x21, 0x00])),
        '14.10.2026 14:47:00',
      );
      expect(decodeDpt(const Dpt(9, 1), _write([1])), isNull); // falsche Länge
    });

    test('DPT 9 Hin- und Rückweg', () {
      for (final v in [0.0, 21.2, -5.5, 0.01, 670760.0, 1234.5]) {
        expect(decodeDpt9(encodeDpt9(v)!), closeTo(v, v.abs() * 0.01 + 0.01));
      }
      expect(encodeDpt9(1e9), isNull);
    });

    test('kodiert Eingaben', () {
      expect(encodeForDpt(const Dpt(5, 1), '50 %')!.data, [128]);
      expect(encodeForDpt(const Dpt(9, 1), '21,2')!.data, [0x0C, 0x24]);
      expect(encodeForDpt(const Dpt(1, 1), '1')!.small, 1);
      expect(encodeForDpt(const Dpt(5, 1), '120'), isNull);
    });
  });

  group('Senden', () {
    test('baut L_Data.req', () {
      final ga = parseGroup('1/2/3')!;
      expect(buildGroupRequest(ga, TelegramType.read), [0x11, 0, 0xBC, 0xE0, 0, 0, 0x0A, 0x03, 1, 0, 0x00]);
      expect(buildGroupRequest(ga, TelegramType.write, small: 1), [0x11, 0, 0xBC, 0xE0, 0, 0, 0x0A, 0x03, 1, 0, 0x81]);
      expect(buildGroupRequest(ga, TelegramType.write, data: [0x0C, 0x24]), [
        0x11,
        0,
        0xBC,
        0xE0,
        0,
        0,
        0x0A,
        0x03,
        3,
        0,
        0x80,
        0x0C,
        0x24,
      ]);
    });

    test('Gruppenadressen und Hex parsen', () {
      expect(parseGroup('31/7/255'), 0xFFFF);
      expect(parseGroup('1/234'), (1 << 11) | 234);
      expect(parseGroup('32/0/0'), isNull);
      expect(parseGroup('1/2/x'), isNull);
      expect(parseHex('0c 1A'), [0x0C, 0x1A]);
      expect(parseHex('abc'), isNull);
    });
  });
}
