import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/filter.dart';
import 'package:knx_monitor/model/telegram_log.dart';

/// ETS kennt drei Adressdarstellungen; die App übernimmt die des Projekts.
void main() {
  tearDown(() => CatalogStore.instance.catalog = GroupCatalog.empty);

  Telegram t(int ga) => Telegram(
    time: DateTime(2026),
    source: 0x1101,
    destination: ga,
    type: TelegramType.write,
    data: Uint8List.fromList([1]),
    isSmall: true,
  );

  test('2-stufig: CSV, Anzeige, Filter', () {
    final c = GroupCatalog.parseCsv('"Group name";"Address";"DatapointType"\n"Küche Licht";"1/515";"DPST-1-1"\n');
    expect(c.style, GroupStyle.twoLevel);
    CatalogStore.instance.catalog = c;
    final ga = (1 << 11) | 515;
    expect(c[ga]!.name, 'Küche Licht');
    expect(formatGroup(ga), '1/515');
    expect(parseGroup('1/515'), ga);
    final log = TelegramLog();
    expect(TelegramFilter.parse('1/515').matches(t(ga), log), isTrue);
    expect(TelegramFilter.parse('1/5*').matches(t(ga), log), isTrue);
    expect(TelegramFilter.parse('1/516').matches(t(ga), log), isFalse);
  });

  test('frei: CSV, Anzeige, Filter, Eingabe', () {
    final c = GroupCatalog.parseCsv('Group name,Address\nBad Lüftung,2563\nBad Licht,2564\n');
    expect(c.style, GroupStyle.free);
    CatalogStore.instance.catalog = c;
    expect(formatGroup(2563), '2563');
    expect(parseGroup('2563'), 2563);
    final log = TelegramLog();
    expect(TelegramFilter.parse('2563').matches(t(2563), log), isTrue);
    expect(TelegramFilter.parse('2563').matches(t(2564), log), isFalse);
    expect(TelegramFilter.parse('256*').matches(t(2564), log), isTrue);
  });

  test('3-stufig bleibt Standard; einzelne Zahl ist dort keine Adresse', () {
    CatalogStore.instance.catalog = GroupCatalog.empty;
    expect(formatGroup(0x0A03), '1/2/3');
    expect(parseGroup('5'), isNull);
    expect(GroupCatalog.fromJson(GroupCatalog({}, style: GroupStyle.free).toJson()).style, GroupStyle.free);
  });
}
