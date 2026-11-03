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
}
