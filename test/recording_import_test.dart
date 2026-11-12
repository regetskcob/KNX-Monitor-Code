import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/export/telegram_files.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/annotation.dart';
import 'package:knx_monitor/model/recording.dart';
import 'package:knx_monitor/model/recording_import.dart';

Telegram _t(
  DateTime time, {
  int destination = 0x0801,
  TelegramType type = TelegramType.write,
  List<int> data = const [1],
  bool small = true,
  bool outgoing = false,
  bool repeated = false,
  int hop = 6,
  TelegramPriority priority = TelegramPriority.low,
}) => Telegram(
  time: time,
  source: 0x1105,
  destination: destination,
  type: type,
  data: Uint8List.fromList(data),
  isSmall: small,
  outgoing: outgoing,
  repeated: repeated,
  hopCount: hop,
  priority: priority,
);

/// What a telegram is, without the raw frame (an export rebuilds it).
List<Object?> _key(Telegram t) => [
  t.time.microsecondsSinceEpoch,
  t.source,
  t.destination,
  t.type,
  t.data.toList(),
  t.isSmall,
  t.outgoing,
  t.repeated,
  t.hopCount,
  t.priority,
];

final _telegrams = [
  _t(DateTime(2025, 3, 30, 1, 59, 59, 120, 7)),
  // The night the clocks go forward, and microseconds.
  _t(DateTime(2025, 3, 30, 3, 0, 0, 0, 1), type: TelegramType.read, data: const [0]),
  _t(DateTime(2025, 3, 30, 3, 0, 1), destination: 0x1A07, data: const [0x0C, 0x24], small: false, hop: 5),
  _t(DateTime(2025, 3, 30, 3, 0, 2), type: TelegramType.response, data: const [0x3F], outgoing: true),
  _t(DateTime(2025, 3, 30, 3, 0, 3), data: const [0], repeated: true, priority: TelegramPriority.urgent),
  _t(DateTime(2025, 3, 30, 3, 0, 4), destination: 0x7FFF, data: List.filled(14, 0x41), small: false),
];

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

Matcher _throwsImport(RecordingImportError error) =>
    throwsA(isA<RecordingImportException>().having((e) => e.error, 'error', error));

void main() {
  final expected = [for (final t in _telegrams) _key(t)];

  group('round trips of what the app writes', () {
    test('ETS telegram file', () {
      final found = readRecordingFile(_bytes(buildEtsXml(_telegrams.reversed.toList())), fileName: 'a.xml');
      expect(found.format, RecordingFormat.etsXml);
      expect([for (final t in found.telegrams) _key(t)], expected);
      expect(found.skipped, isEmpty);
      expect(found.first, _telegrams.first.time);
      expect(found.last, _telegrams.last.time);
    });

    test('CSV, with byte order mark as exported', () {
      final found = readRecordingFile(csvBytes(buildCsv(_telegrams)), fileName: 'a.csv');
      expect(found.format, RecordingFormat.csv);
      expect([for (final t in found.telegrams) _key(t)], expected);
      expect(found.skipped, isEmpty);
    });

    test('CSV saved again by a spreadsheet with semicolons', () {
      final csv = buildCsv(_telegrams).replaceAll('","', '";"');
      final found = readRecordingFile(_bytes(csv), fileName: 'a.csv');
      expect([for (final t in found.telegrams) _key(t)], expected);
    });

    test('recording file keeps name, note, comments; screenshots stay with the original', () {
      final original = Recording(
        id: 'abc',
        name: 'Abnahme Meier',
        note: 'Flur flackert',
        started: DateTime(2025, 3, 30, 1),
        ended: DateTime(2025, 3, 30, 4),
        gateway: 'Gira X1',
        telegrams: _telegrams,
        annotations: [
          Annotation(id: 'n1', time: DateTime(2025, 3, 30, 3), note: 'jetzt', shots: ['shot1']),
        ],
      );
      final found = readRecordingFile(_bytes(jsonEncode(original.toJson())), fileName: 'abc.json');
      expect(found.format, RecordingFormat.recording);
      expect([for (final t in found.telegrams) _key(t)], expected);
      final saved = found.toRecording(name: found.original!.name, installation: 'haus', now: DateTime(2026, 11, 11));
      expect(saved.id, isNot('abc'));
      expect(saved.name, 'Abnahme Meier');
      expect(saved.note, 'Flur flackert');
      expect(saved.started, DateTime(2025, 3, 30, 1));
      expect(saved.ended, DateTime(2025, 3, 30, 4));
      expect(saved.installation, 'haus');
      expect(saved.annotations.single.note, 'jetzt');
      expect(saved.annotations.single.shots, isEmpty);
      expect(saved.imported!.file, 'abc.json');
      expect(saved.imported!.format, 'recording');
      // And the mark survives saving.
      final again = Recording.fromJson(jsonDecode(jsonEncode(saved.toJson())) as Map<String, Object?>);
      expect(again.imported!.at, DateTime(2026, 11, 11));
      expect(again.imported!.file, 'abc.json');
    });

    test('history day (one telegram per line), with a truncated last line', () {
      final lines = [for (final t in _telegrams) jsonEncode(t.toJson())];
      final found = readRecordingFile(_bytes('${lines.join('\n')}\n{"t":17,"s":1'), fileName: '2025-03-30.jsonl');
      expect(found.format, RecordingFormat.history);
      expect([for (final t in found.telegrams) _key(t)], expected);
      expect(found.skipped, {TelegramSkip.line: 1});
    });

    test('zip of ETS files, as the add-on exports the whole history', () {
      final a = _bytes(buildEtsXml(_telegrams.sublist(0, 2)));
      final b = _bytes(buildEtsXml(_telegrams.sublist(2)));
      final zip = Uint8List.fromList(
        ZipEncoder().encode(
          Archive()
            ..addFile(ArchiveFile('knx-monitor-2025-03-31.xml', b.length, b))
            ..addFile(ArchiveFile('knx-monitor-2025-03-30.xml', a.length, a)),
        ),
      );
      expect(looksLikeEtsZip(zip), isTrue);
      final found = readRecordingFile(zip, fileName: 'knx-monitor.zip');
      expect(found.format, RecordingFormat.etsZip);
      expect([for (final t in found.telegrams) _key(t)], expected);
    });

    test('an old recording without the mark is not an import', () {
      final r = Recording.fromJson(
        jsonDecode(
          jsonEncode(
            Recording(id: 'x', name: 'n', started: DateTime(2025), ended: DateTime(2025), telegrams: const []).toJson(),
          ),
        ) as Map<String, Object?>,
      );
      expect(r.imported, isNull);
    });
  });

  group('ETS exports', () {
    // ETS 5 group monitor: namespace, RecordStart with more attributes, seven fraction digits,
    // Windows line ends, byte order mark.
    const ets5 =
        '﻿<?xml version="1.0" encoding="utf-8"?>\r\n'
        '<CommunicationLog xmlns="http://knx.org/xml/telegrams/01">\r\n'
        '  <RecordStart Timestamp="2024-02-11T09:15:00.1234567Z" Mode="LinkLayer" Host="WERKSTATT-PC" '
        'ConnectionName="KNX USB Interface" ConnectionOptions="Type=Usb" ConnectorType="Usb" MediumType="TP" />\r\n'
        '  <Telegram Timestamp="2024-02-11T09:15:01.0001234Z" Service="L_Data.ind" FrameFormat="CommonEmi" '
        'RawData="2900BCE0110A0A03010081" />\r\n'
        '  <Telegram Timestamp="2024-02-11T09:15:02.5Z" Service="L_Data.con" FrameFormat="CommonEmi" '
        'RawData="2E00BCE011FA0A03010080" />\r\n'
        '  <RecordStop Timestamp="2024-02-11T09:20:00Z" />\r\n'
        '</CommunicationLog>\r\n';

    test('ETS 5 group monitor', () {
      final found = readRecordingFile(_bytes(ets5), fileName: 'Gruppenmonitor.xml');
      expect(found.format, RecordingFormat.etsXml);
      expect(found.telegrams, hasLength(2));
      expect(found.first.toUtc(), DateTime.utc(2024, 2, 11, 9, 15, 1, 0, 123));
      expect(found.telegrams.first.destinationText, '1/2/3');
      expect(found.telegrams.first.data, [1]);
      expect(found.telegrams.last.outgoing, isTrue);
    });

    test('UTF-16 with byte order mark, as Windows tools save', () {
      final text = ets5.substring(1).replaceFirst('utf-8', 'utf-16');
      final bytes = Uint8List.fromList([
        0xFF,
        0xFE,
        for (final unit in text.codeUnits) ...[unit & 0xFF, unit >> 8],
      ]);
      expect(readRecordingFile(bytes, fileName: 'a.xml').telegrams, hasLength(2));
    });

    // ETS 6 bus monitor: prefixed namespace, L_Busmon.ind with raw TP1 frames including
    // acknowledgements, a device telegram, a telegram without RawData and one without a time.
    test('ETS 6 bus monitor with a prefix: what cannot be read is counted by reason', () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<t:CommunicationLog xmlns:t="http://knx.org/xml/telegrams/01">
  <t:RecordStart Timestamp="2026-03-05T00:00:38.0000000Z" Mode="Busmonitor" Host="PC" ConnectionName="IP" MediumType="TP" />
  <t:Telegram Timestamp="2026-03-05T00:00:38.9940000Z" Service="L_Busmon.ind" FrameFormat="CommonEmi" RawData="2B090301030604BAD64193BC1012143DE3008000C8C3" TransportSecurity="false" />
  <t:Telegram Timestamp="2026-03-05T00:00:38.9990000Z" Service="L_Busmon.ind" FrameFormat="CommonEmi" RawData="2B090301040604BAD6A0ACCC" />
  <t:Telegram Timestamp="2026-03-05T00:00:39.1000000Z" Service="L_Busmon.ind" FrameFormat="CommonEmi" RawData="2B0703010504025E00CC" />
  <t:Telegram Timestamp="2026-03-05T00:00:39.2000000Z" Service="L_Data.ind" FrameFormat="CommonEmi" RawData="2900B06011051101004300" />
  <t:Telegram Timestamp="2026-03-05T00:00:39.3000000Z" Service="L_Data.ind" FrameFormat="CommonEmi" />
  <t:Telegram Service="L_Data.ind" FrameFormat="CommonEmi" RawData="2900BCE0110A0A03010081" />
  <t:Telegram Timestamp="gestern" Service="L_Data.ind" FrameFormat="CommonEmi" RawData="2900BCE0110A0A03010081" />
  <t:Telegram Timestamp="2026-03-05T00:00:40Z" Service="L_Data.ind" FrameFormat="CommonEmi" RawData="keinhex" />
  <t:RecordStop Timestamp="2026-03-05T00:01:00Z" />
</t:CommunicationLog>''';
      final found = readRecordingFile(_bytes(xml), fileName: 'Busmonitor.xml');
      expect(found.telegrams, hasLength(1));
      expect(found.telegrams.single.sourceText, '1.0.18');
      expect(found.skipped, {TelegramSkip.frame: 4, TelegramSkip.noData: 1, TelegramSkip.time: 2});
      expect(found.skippedCount, 7);
    });
  });

  group('hostile and wrong files', () {
    test('entity expansion: a document type is refused unread', () {
      const bomb = '''<?xml version="1.0"?>
<!DOCTYPE CommunicationLog [
  <!ENTITY a "2900BCE0110A0A03010081">
  <!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">
  <!ENTITY c "&b;&b;&b;&b;&b;&b;&b;&b;&b;&b;">
  <!ENTITY d "&c;&c;&c;&c;&c;&c;&c;&c;&c;&c;">
]>
<CommunicationLog xmlns="http://knx.org/xml/telegrams/01">
  <Telegram Timestamp="2026-03-05T00:00:40Z" Service="L_Data.ind" RawData="&d;" />
</CommunicationLog>''';
      expect(() => readRecordingFile(_bytes(bomb), fileName: 'b.xml'), _throwsImport(RecordingImportError.doctype));
      expect(() => parseEtsXml(bomb, name: 'b'), throwsFormatException);
    });

    test('an external entity is refused the same way', () {
      const xxe =
          '<!DOCTYPE x [<!ENTITY f SYSTEM "file:///etc/passwd">]>'
          '<CommunicationLog><Telegram Timestamp="2026-03-05T00:00:40Z" RawData="&f;"/></CommunicationLog>';
      expect(() => readRecordingFile(_bytes(xxe), fileName: 'x.xml'), _throwsImport(RecordingImportError.doctype));
    });

    test('an undeclared entity is not expanded, the telegram is just unreadable', () {
      const xml =
          '<CommunicationLog><Telegram Timestamp="2026-03-05T00:00:40Z" RawData="&lol;"/>'
          '<Telegram Timestamp="2026-03-05T00:00:41Z" RawData="2900BCE0110A0A03010081"/></CommunicationLog>';
      final found = readRecordingFile(_bytes(xml), fileName: 'x.xml');
      expect(found.telegrams, hasLength(1));
      expect(found.skipped, {TelegramSkip.frame: 1});
    });

    test('oversized: bytes', () {
      const limits = RecordingImportLimits(maxBytes: 1024);
      expect(
        () => readRecordingFile(Uint8List(1025), fileName: 'big.xml', limits: limits),
        _throwsImport(RecordingImportError.tooLarge),
      );
    });

    test('oversized: telegrams, in every format', () {
      const limits = RecordingImportLimits(maxTelegrams: 3);
      final files = {
        'a.xml': _bytes(buildEtsXml(_telegrams)),
        'a.csv': csvBytes(buildCsv(_telegrams)),
        'a.jsonl': _bytes([for (final t in _telegrams) jsonEncode(t.toJson())].join('\n')),
        'a.json': _bytes(
          jsonEncode(
            Recording(
              id: 'x',
              name: 'n',
              started: DateTime(2025),
              ended: DateTime(2025),
              telegrams: _telegrams,
            ).toJson(),
          ),
        ),
      };
      for (final MapEntry(:key, :value) in files.entries) {
        expect(
          () => readRecordingFile(value, fileName: key, limits: limits),
          _throwsImport(RecordingImportError.tooMany),
          reason: key,
        );
      }
      // Exactly at the limit is fine.
      expect(
        readRecordingFile(_bytes(buildEtsXml(_telegrams.sublist(0, 3))), fileName: 'a.xml', limits: limits).telegrams,
        hasLength(3),
      );
    });

    test('a huge RawData attribute is not decoded', () {
      final xml =
          '<CommunicationLog><Telegram Timestamp="2026-03-05T00:00:40Z" RawData="${'29' * 100000}"/>'
          '<Telegram Timestamp="2026-03-05T00:00:41Z" RawData="2900BCE0110A0A03010081"/></CommunicationLog>';
      final found = readRecordingFile(_bytes(xml), fileName: 'x.xml');
      expect(found.skipped, {TelegramSkip.frame: 1});
    });

    test('zip bomb: the directory is checked before anything unpacks', () {
      final big = Uint8List(64 * 1024);
      final zip = Uint8List.fromList(
        ZipEncoder().encode(Archive()..addFile(ArchiveFile('knx-monitor-2025-03-30.xml', big.length, big))),
      );
      expect(
        () => readRecordingFile(
          zip,
          fileName: 'a.zip',
          limits: const RecordingImportLimits(maxBytes: 32 * 1024),
        ),
        _throwsImport(RecordingImportError.archive),
      );
    });

    test('a zip with anything but ETS files is not ours', () {
      final zip = Uint8List.fromList(
        ZipEncoder().encode(
          Archive()
            ..addFile(ArchiveFile('a.xml', 1, [0x20]))
            ..addFile(ArchiveFile('manifest.json', 2, utf8.encode('{}'))),
        ),
      );
      expect(looksLikeEtsZip(zip), isFalse);
      expect(() => readRecordingFile(zip, fileName: 'a.zip'), _throwsImport(RecordingImportError.unknownFormat));
    });

    test('unknown formats say so', () {
      for (final text in ['Hallo', 'a,b,c\n1,2,3', '[1,2,3]', '{"foo": 1}', '', '   ']) {
        expect(
          () => readRecordingFile(_bytes(text), fileName: 'x'),
          _throwsImport(RecordingImportError.unknownFormat),
          reason: text,
        );
      }
    });

    test('recognized but without a telegram, or damaged', () {
      expect(
        () => readRecordingFile(_bytes('<CommunicationLog/>'), fileName: 'x.xml'),
        _throwsImport(RecordingImportError.empty),
      );
      expect(
        () => readRecordingFile(_bytes('<html><body>404</body></html>'), fileName: 'x.xml'),
        _throwsImport(RecordingImportError.empty),
      );
      expect(
        () => readRecordingFile(_bytes(buildCsv(const [])), fileName: 'x.csv'),
        _throwsImport(RecordingImportError.empty),
      );
      // A recording file whose key data is missing.
      expect(
        () => readRecordingFile(
          _bytes(
            jsonEncode({
              'telegrams': [_telegrams.first.toJson()],
            }),
          ),
          fileName: 'x.json',
        ),
        _throwsImport(RecordingImportError.damaged),
      );
    });

    test('foreign entries in a recording file are skipped, not fatal', () {
      final json = Recording(
        id: 'x',
        name: 'n',
        started: DateTime(2025),
        ended: DateTime(2025),
        telegrams: _telegrams.sublist(0, 2),
      ).toJson();
      json['telegrams'] = <Object?>[
        ...json['telegrams']! as List,
        'text',
        {'t': 'gestern', 's': 1, 'd': 2, 'y': 0, 'x': ''},
        {'t': 5, 's': 1, 'd': 2, 'y': 99, 'x': ''},
      ];
      final found = readRecordingFile(_bytes(jsonEncode(json)), fileName: 'x.json');
      expect(found.telegrams, hasLength(2));
      expect(found.skipped, {TelegramSkip.line: 2, TelegramSkip.time: 1});
    });
  });
}
