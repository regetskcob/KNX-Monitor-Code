import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/filter.dart';
import 'package:knx_monitor/model/telegram_log.dart';

void main() {
  final log = TelegramLog();
  Telegram t(String ga, String src, {TelegramType type = TelegramType.write, bool repeated = false}) => Telegram(
    time: DateTime(2026),
    source: parseIndividual(src)!,
    destination: parseGroup(ga)!,
    type: type,
    data: Uint8List.fromList([1]),
    isSmall: true,
    repeated: repeated,
  );

  setUp(() {
    CatalogStore.instance.catalog = GroupCatalog({
      parseGroup('1/2/13')!: GroupInfo(address: parseGroup('1/2/13')!, name: 'Küche Decke', dpt: const Dpt(1, 1)),
      parseGroup('2/0/0')!: GroupInfo(address: parseGroup('2/0/0')!, name: 'Ist-Temperatur', dpt: const Dpt(9, 1)),
    });
  });

  bool m(String query, Telegram tg) => TelegramFilter.parse(query).matches(tg, log);

  test('Gruppenadressen mit Platzhaltern und Bereichen', () {
    final k = t('1/2/13', '1.1.5');
    expect(m('1/2/13', k), isTrue);
    expect(m('1/2/1', k), isFalse); // vollständige Adresse = exakt
    expect(m('1/2/1*', k), isTrue);
    expect(m('1/*/13', k), isTrue);
    expect(m('1/2', k), isTrue);
    expect(m('1', k), isTrue);
    expect(m('11', k), isFalse);
    expect(m('2/*/*', k), isFalse);
  });

  test('Absender, Typ, DPT, Text, UND/ODER/NICHT', () {
    final k = t('1/2/13', '1.1.5');
    final temp = t('2/0/0', '1.2.20', type: TelegramType.response);
    expect(m('1.1.*', k), isTrue);
    expect(m('von:1.2', temp), isTrue);
    expect(m('typ:a', temp), isTrue);
    expect(m('type:w|r', temp), isFalse);
    expect(m('dpt:9', temp), isTrue);
    expect(m('dpt:9.001', temp), isTrue);
    expect(m('dpt:1', temp), isFalse);
    expect(m('küche', k), isTrue);
    expect(m('küche 1.1.5', k), isTrue); // UND
    expect(m('küche 1.2.*', k), isFalse);
    expect(m('bad, küche', k), isTrue); // ODER
    expect(m('-küche', k), isFalse); // NICHT
    expect(m('', k), isTrue);
  });

  test('ist: Auffälligkeiten', () {
    expect(m('ist:wiederholt', t('1/2/13', '1.1.5', repeated: true)), isTrue);
    expect(m('is:repeated', t('1/2/13', '1.1.5')), isFalse);
    expect(m('ist:projekt', t('5/5/5', '1.1.5')), isTrue);
  });

  test('Umlaute egal: kuche, kueche und küche finden Küche', () {
    final k = t('1/2/13', '1.1.5');
    expect(m('kuche', k), isTrue);
    expect(m('kueche', k), isTrue);
    expect(m('KÜCHE decke', k), isTrue);
    expect(m('kachel', k), isFalse);
  });

  test('Richtung: eigene und empfangene Telegramme', () {
    final own = Telegram(
      time: DateTime(2026),
      source: 0x1126,
      destination: parseGroup('1/2/13')!,
      type: TelegramType.write,
      data: Uint8List.fromList([1]),
      isSmall: true,
      outgoing: true,
    );
    final received = t('1/2/13', '1.1.5');
    expect(m('ist:eigen', own), isTrue);
    expect(m('is:own', received), isFalse);
    expect(m('ist:fremd', received), isTrue);
  });

  test('ODER-Gruppen: Index der passenden Gruppe für Farbmarken', () {
    final f = TelegramFilter.parse('2/0/0, küche');
    expect(f.groupCount, 2);
    expect(f.groupOf(t('1/2/13', '1.1.5'), log), 1);
    expect(f.groupOf(t('2/0/0', '1.1.5'), log), 0);
    expect(f.groupOf(t('3/0/0', '1.1.5'), log), isNull);
  });

  test('Kontext: Telegramme kurz vor und nach jedem Treffer', () {
    Telegram at(int second, String ga) => Telegram(
      time: DateTime(2026, 1, 1, 12, 0, second),
      source: 0x1105,
      destination: parseGroup(ga)!,
      type: TelegramType.write,
      data: Uint8List.fromList([1]),
      isSmall: true,
    );
    final list = [at(0, '3/0/0'), at(8, '3/0/1'), at(9, '3/0/2'), at(10, '1/2/13'), at(12, '3/0/3'), at(20, '3/0/4')];
    final r = withContext(list, (x) => x.destination == parseGroup('1/2/13'), const Duration(seconds: 2));
    expect(r.visible.map((x) => x.time.second), [8, 9, 10, 12]);
    expect(r.context.map((x) => x.time.second).toSet(), {8, 9, 12});
    final none = withContext(list, (x) => x.destination == parseGroup('1/2/13'), Duration.zero);
    expect(none.visible.single.time.second, 10);
    expect(none.context, isEmpty);
  });

  test('Uhrzeit: Anfang oder Bereich ohne Ende (Lastspitzen, Heatmap)', () {
    Telegram at(int h, int m_, int sec) => Telegram(
      time: DateTime(2026, 1, 1, h, m_, sec),
      source: 0x1105,
      destination: parseGroup('1/2/13')!,
      type: TelegramType.write,
      data: Uint8List.fromList([1]),
      isSmall: true,
    );
    expect(m('zeit:14:05:07', at(14, 5, 7)), isTrue);
    expect(m('zeit:14:05:07', at(14, 5, 8)), isFalse);
    expect(m('time:14:05', at(14, 5, 59)), isTrue);
    expect(m('zeit:14', at(15, 0, 0)), isFalse);
    expect(m('zeit:14:05-14:10', at(14, 9, 59)), isTrue);
    expect(m('zeit:14:05-14:10', at(14, 10, 0)), isFalse);
    expect(m('zeit:14:55-14:60', at(14, 59, 59)), isTrue);
    expect(m('zeit:14:55-14:60', at(15, 0, 0)), isFalse);
    expect(m('zeit:14:05 1/2/13', at(14, 5, 1)), isTrue);
  });
}
