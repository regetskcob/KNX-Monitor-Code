import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/export/telegram_files.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';

void main() {
  setUp(() {
    CatalogStore.instance.catalog = GroupCatalog({
      parseGroup('2/0/0')!: GroupInfo(address: parseGroup('2/0/0')!, name: '=Temperatur, "EG"', dpt: const Dpt(9, 1)),
    });
  });

  final ind = Telegram.fromCemi(
    Uint8List.fromList([0x29, 0x00, 0xBC, 0xE0, 0x11, 0x32, 0x10, 0x00, 0x03, 0x00, 0x80, 0x0C, 0x24]),
    time: DateTime(2026, 10, 14, 15, 20, 1, 234),
  )!;
  final read = Telegram(
    time: DateTime(2026, 10, 14, 15, 20, 2),
    source: 0x1126,
    destination: parseGroup('2/0/0')!,
    type: TelegramType.read,
    data: Uint8List.fromList([0]),
    isSmall: true,
    outgoing: true,
  );

  test('CSV: Quoting und Schutz vor Formel-Injection', () {
    final csv = buildCsv([read, ind]);
    final lines = csv.split('\r\n');
    expect(lines.first, startsWith('"time","type","source"'));
    expect(lines[1], contains('"write"'));
    expect(lines[1], contains('"\'=Temperatur, ""EG"""')); // escaped and quoted
    expect(lines[1], contains('"0C24"'));
    expect(lines[2], contains('"read"'));
    expect(lines[2], contains('"1"')); // sent
  });

  test('CSV: Zahlen bleiben Zahlen, Zeit mit Offset, BOM', () {
    expect(csvCell(-3.5), '"-3.5"');
    expect(csvCell('-12'), '"-12"');
    expect(csvCell('-3,5 °C'), '"\'-3,5 °C"');
    expect(csvCell('+SUM(A1)'), '"\'+SUM(A1)"');
    expect(
      isoWithOffset(DateTime.utc(2026, 1, 1)),
      matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}[+-]\d\d:\d\d$')),
    );
    expect(buildCsv([ind]).split('\r\n')[1], startsWith('"${isoWithOffset(ind.time)}"'));
    expect(csvBytes('Küche').take(3), [0xEF, 0xBB, 0xBF]);
  });

  test('ETS-XML: Export und Import ergeben dieselben Telegramme', () {
    final xml = buildEtsXml([ind, read], host: '192.168.1.22');
    expect(xml, contains('<CommunicationLog xmlns="http://knx.org/xml/telegrams/01">'));
    expect(
      xml,
      contains(
        'RawData="2900BCE01132100003008'
                '00C24"'
            .replaceAll(' ', ''),
      ),
    );
    final r = parseEtsXml(xml, name: 'Import');
    expect(r.telegrams, hasLength(2));
    expect(r.telegrams.first.destinationText, '2/0/0');
    expect(r.telegrams.first.data, [0x0C, 0x24]);
    expect(r.telegrams.first.time, ind.time);
    expect(r.telegrams.last.type, TelegramType.read);
    expect(r.telegrams.last.outgoing, isTrue); // rekonstruiert als L_Data.con
  });

  test('ETS-XML: ungültige Datei', () {
    expect(() => parseEtsXml('<foo/>', name: 'x'), throwsFormatException);
    expect(() => parseEtsXml('kein xml', name: 'x'), throwsFormatException);
  });

  // The add-on writes the same file from its history (`/api/export/ets-xml`,
  // ha-addon/knx_monitor/server/lib/src/ets_xml.dart); its test compares
  // against the same fixture.
  test('ETS-XML: gleiches Format wie das Add-on (gemeinsame Fixture)', () {
    const fixtures = 'ha-addon/knx_monitor/server/test/fixtures/ets_xml';
    final telegrams = [
      for (final line in File('$fixtures/history.ndjson').readAsLinesSync())
        Telegram.fromJson(jsonDecode(line) as Map<String, Object?>),
    ];
    expect(buildEtsXml(telegrams), File('$fixtures/history.xml').readAsStringSync());
  });

  group('ETS-XML anderer Programme', () {
    // knx-telegram-store 0.15 (Home Assistant), writer `format_telegram_element`
    // in src/knx_telegram_store/formats/ets_xml.py; SpectrumKNX
    // (martinhoefling/SpectrumKNX, backend/api.py) uses it with this
    // ConnectionName: no RecordStart/RecordStop, six fraction digits.
    test('Home Assistant / SpectrumKNX', () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<CommunicationLog xmlns="http://knx.org/xml/telegrams/01">
  <Telegram Timestamp="2026-06-27T13:54:24.409694Z" ConnectionName="Spectrum KNX Export" Service="L_Data.ind" FrameFormat="CommonEmi" RawData="2900BCE0113210000300800C24" />
  <Telegram Timestamp="2026-06-27T13:54:25.000000Z" ConnectionName='My "Log"' Service="L_Data.ind" FrameFormat="CommonEmi" RawData="2900BCE010180504010081" />
</CommunicationLog>
''';
      final r = parseEtsXml(xml, name: 'HA');
      expect(r.telegrams, hasLength(2));
      expect(r.telegrams.first.time.toUtc(), DateTime.utc(2026, 6, 27, 13, 54, 24, 409, 694));
      expect(r.telegrams.first.data, [0x0C, 0x24]);
      expect(r.telegrams.last.destinationText, '0/5/4');
      expect(r.telegrams.last.data, [0x01]);
    });

    // Written by SpectrumKNX's own export (backend/telegram_export.py,
    // stored_to_record, xknx 4.0, knx-telegram-store 0.15.2), not by hand.
    // The other way round, its reader decodes our history.xml fixture.
    test('SpectrumKNX-Export (mit deren Code erzeugt)', () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<CommunicationLog xmlns="http://knx.org/xml/telegrams/01">
  <Telegram Timestamp="2026-11-04T18:30:00.123000Z" ConnectionName="SpectrumKNX" Service="L_Data.ind" FrameFormat="CommonEmi" RawData="2900BCE0110A0A03010081" />
  <Telegram Timestamp="2026-11-04T18:30:01.123000Z" ConnectionName="SpectrumKNX" Service="L_Data.ind" FrameFormat="CommonEmi" RawData="2900BCE0110A0A03010080" />
  <Telegram Timestamp="2026-11-04T18:30:02.123000Z" ConnectionName="SpectrumKNX" Service="L_Data.ind" FrameFormat="CommonEmi" RawData="2900BCE01114100102008080" />
  <Telegram Timestamp="2026-11-04T18:30:03.123000Z" ConnectionName="SpectrumKNX" Service="L_Data.ind" FrameFormat="CommonEmi" RawData="2900BCE0111E19070300800C1A" />
  <Telegram Timestamp="2026-11-04T18:30:04.123000Z" ConnectionName="SpectrumKNX" Service="L_Data.ind" FrameFormat="CommonEmi" RawData="2900BCE011011907010000" />
  <Telegram Timestamp="2026-11-04T18:30:05.123000Z" ConnectionName="SpectrumKNX" Service="L_Data.ind" FrameFormat="CommonEmi" RawData="2900BCE0111E19070300400C1A" />
  <Telegram Timestamp="2026-11-04T18:30:06.123000Z" ConnectionName="SpectrumKNX" Service="L_Data.ind" FrameFormat="CommonEmi" RawData="2900BCE0FFFAFFFF05008041C80000" />
</CommunicationLog>
''';
      final t = parseEtsXml(xml, name: 'SpectrumKNX').telegrams;
      expect(t, hasLength(7));
      expect(t.first.time.toUtc(), DateTime.utc(2026, 11, 4, 18, 30, 0, 123));
      expect(
        [t[0].sourceText, t[0].destinationText, t[0].type, t[0].data],
        [
          '1.1.10',
          '1/2/3',
          TelegramType.write,
          [1],
        ],
      );
      expect(t[1].data, [0]);
      expect(
        [t[2].destinationText, t[2].data],
        [
          '2/0/1',
          [0x80],
        ],
      );
      expect(
        [t[3].destinationText, t[3].data],
        [
          '3/1/7',
          [0x0C, 0x1A],
        ],
      );
      expect([t[4].sourceText, t[4].type], ['1.1.1', TelegramType.read]);
      expect(
        [t[5].type, t[5].data],
        [
          TelegramType.response,
          [0x0C, 0x1A],
        ],
      );
      expect(
        [t[6].sourceText, t[6].destinationText, t[6].data],
        [
          '15.15.250',
          '31/7/255',
          [0x41, 0xC8, 0x00, 0x00],
        ],
      );
    });

    // ETS 6 sample from knx-telegram-store's tests (tests/test_formats_ets_xml.py):
    // seven fraction digits, TransportSecurity, RecordStop without fraction.
    test('ETS 6', () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<CommunicationLog xmlns="http://knx.org/xml/telegrams/01">
  <RecordStart Timestamp="2026-06-27T13:54:21.8676962Z" ConnectionName="Test" Mode="LinkLayer" />
  <Telegram Timestamp="2026-06-27T13:54:24.4096945Z" ConnectionName="Test" Service="L_Data.ind" FrameFormat="CommonEmi" RawData="2900BCD01129010302008019" TransportSecurity="true" />
  <Telegram Timestamp="2026-06-27T13:54:25.9198766Z" Service="L_Data.ind" FrameFormat="CommonEmi" RawData="2900BCE010180504010081" />
  <RecordStop Timestamp="2026-06-27T13:56:00Z" />
</CommunicationLog>
''';
      final r = parseEtsXml(xml, name: 'ETS');
      expect(r.telegrams, hasLength(2));
      expect(r.telegrams.first.destinationText, '0/1/3');
      expect(r.telegrams.first.data, [0x19]);
      // Seven digits are cut to microseconds, like knx-telegram-store does.
      expect(r.telegrams.first.time.toUtc(), DateTime.utc(2026, 6, 27, 13, 54, 24, 409, 694));
      expect(r.telegrams.last.time.toUtc(), DateTime.utc(2026, 6, 27, 13, 54, 25, 919, 876));
    });

    // Gira logger sample from knx-telegram-store's tests: busmonitor frames
    // (cEMI 2B with raw TP1 frame), local time marked "Z", real offset in a comment.
    test('Gira: Busmonitor-Rahmen und Zeitzonen-Kommentar', () {
      const xml = '''<CommunicationLog xmlns="http://knx.org/xml/telegrams/01">
<!-- timezone offset +01:00 hour -->
  <Telegram Timestamp="2026-03-05T00:00:38.994Z" Service="L_Busmon.ind" FrameFormat="CommonEmi" RawData="2B090301030604BAD64193BC1012143DE3008000C8C3" />
  <Telegram Timestamp="2026-03-05T00:00:38.999Z" Service="L_Busmon.ind" FrameFormat="CommonEmi" RawData="2B090301040604BAD6A0ACCC" />
</CommunicationLog>
''';
      final r = parseEtsXml(xml, name: 'Gira');
      expect(r.telegrams, hasLength(1), reason: 'die Quittung (CC) ist kein Telegramm');
      final t = r.telegrams.single;
      expect(t.time.toUtc(), DateTime.utc(2026, 3, 4, 23, 0, 38, 994));
      expect(t.sourceText, '1.0.18');
      expect(t.destinationText, '2/4/61');
      expect(t.type, TelegramType.write);
      expect(t.data, [0x00, 0xC8]);
      expect(t.hopCount, 6);
      // Wrong checksum: broken frame, skipped.
      expect(
        () => parseEtsXml(xml.replaceFirst('00C8C3', '00C8C4').replaceFirst(RegExp('.*ACCC.*\n'), ''), name: 'x'),
        throwsFormatException,
      );
    });

    // node-red-contrib-knx-ultimate (nodes/knxUltimateLogger.js): no XML
    // declaration, toISOString() timestamps, lowercase hex.
    test('knx-ultimate: ohne Deklaration, Kleinbuchstaben', () {
      const xml = '''<CommunicationLog xmlns="http://knx.org/xml/telegrams/01">
 <Telegram Timestamp="2026-06-27T13:54:24.409Z" Service="L_Data.ind" FrameFormat="CommonEmi" RawData="2900bce0113210000300800c24" />
<RecordStop Timestamp="2026-06-27T13:54:24.409Z" />
</CommunicationLog>''';
      expect(parseEtsXml(xml, name: 'nr').telegrams.single.data, [0x0C, 0x24]);
    });

    test('Präfix, BOM, fehlende RawData, Zeit ohne Zone, L_Data.req', () {
      const xml = '''﻿<?xml version="1.0"?>
<knx:CommunicationLog xmlns:knx="http://knx.org/xml/telegrams/01">
  <knx:Telegram Timestamp="2026-06-27T13:54:20" Service="L_Data.ind" />
  <knx:Telegram knx:Timestamp="2026-06-27T13:54:21" Service="L_Data.req" RawData="1100BCE0112610000100 81" />
  <knx:Telegram Timestamp=" 2026-06-27T13:54:22+02:00 " RawData="2900BCE0113210000300800C24" />
</knx:CommunicationLog>''';
      final r = parseEtsXml(xml, name: 'x');
      expect(r.telegrams, hasLength(2));
      expect(r.telegrams.first.time.toUtc(), DateTime.utc(2026, 6, 27, 11, 54, 22));
      expect(r.telegrams.last.time.toUtc(), DateTime.utc(2026, 6, 27, 13, 54, 21), reason: 'ohne Zone = UTC');
      expect(r.telegrams.last.outgoing, isTrue);
      expect(r.telegrams.last.data, [0x01]);
    });
  });
}
