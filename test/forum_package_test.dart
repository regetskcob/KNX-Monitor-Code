import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/export/forum_package.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';

int _ga(String s) => parseGroup(s)!;
int _pa(String s) => parseIndividual(s)!;

final _catalog = GroupCatalog(
  {
    _ga('1/1/1'): GroupInfo(address: _ga('1/1/1'), name: 'Küche Familie Müller Decke', dpt: const Dpt(1, 1)),
    _ga('1/4/1'): GroupInfo(address: _ga('1/4/1'), name: 'Küche Decke | Status', dpt: const Dpt(1, 1)),
  },
  devices: {
    _pa('1.1.10'): DeviceInfo(address: _pa('1.1.10'), name: 'Aktor Keller Müller', product: 'SA 8'),
    _pa('1.1.30'): DeviceInfo(address: _pa('1.1.30'), name: 'Taster Küche [EG]'),
  },
  projectName: 'Haus Müller',
);

Telegram _t(int ms, String source, String ga, {bool outgoing = false}) => Telegram(
  time: DateTime(2026, 10, 29, 20, 15).add(Duration(milliseconds: ms)),
  source: _pa(source),
  destination: _ga(ga),
  type: TelegramType.write,
  data: Uint8List.fromList([1]),
  isSmall: true,
  outgoing: outgoing,
);

final _telegrams = [_t(180, '1.1.10', '1/4/1'), _t(0, '1.1.30', '1/1/1'), _t(400, '1.1.255', '1/1/1', outgoing: true)];

void main() {
  test('Markdown: Tabelle, GAs mit DPT, Geräte, Meta ohne Kennungen', () {
    final text = ForumPackage.build(
      telegrams: _telegrams,
      catalog: _catalog,
      format: ForumFormat.markdown,
      connection: 'IP Secure · 192.168.1.20:3671 · knx.fritz.box',
      appVersion: '1.9.0',
    );
    expect(text, contains('- Busclear 1.9.0'));
    expect(text, contains('- Verbindung: IP Secure · <ip> · <host>'));
    expect(text, isNot(contains('192.168')));
    expect(text, contains('| Zeit | Absender | GA | Name | Art | Wert |'));
    // Zeitlich sortiert, Absender des Tasters zuerst.
    final rows = text.split('\n').where((l) => l.startsWith('| 20:15')).toList();
    expect(rows.first, contains('| 1.1.30 | 1/1/1 | Küche Familie Müller Decke | Write |'));
    expect(rows.last, contains('1.1.255 (diese App)'));
    // Senkrechte Striche im Namen dürfen die Tabelle nicht sprengen.
    expect(text, contains(r'Küche Decke \| Status'));
    expect(text, contains('| 1/4/1 | Küche Decke \\| Status | DPT 1.001 |'));
    expect(text, contains('| 1.1.10 | Aktor Keller Müller |'));
    // Projektname wird immer ersetzt.
    expect(text, isNot(contains('Haus Müller')));
  });

  test('BBCode mit Ersatznamen: Adressen und DPT bleiben, Namen nicht', () {
    final text = ForumPackage.build(
      telegrams: _telegrams,
      catalog: _catalog,
      format: ForumFormat.bbcode,
      pseudonymize: true,
      appVersion: '1.9.0',
    );
    expect(text, startsWith('[B]Mitschnitt aus Busclear[/B]'));
    expect('[CODE]'.allMatches(text).length, 3);
    expect('[/CODE]'.allMatches(text).length, 3);
    expect(text, isNot(contains('Müller')));
    expect(text, isNot(contains('Küche')));
    expect(text, contains('GA 1'));
    expect(text, contains('DPT 1.001'));
    // Produkt bleibt, ohne Produkt ein neutraler Name; Klammern entschärft.
    expect(text, contains('SA 8'));
    expect(text, contains('Gerät 1'));
    expect(text, isNot(contains('[EG]')));
  });

  test('Lange Mitschnitte werden gekürzt', () {
    final many = [for (var i = 0; i < 100; i++) _t(i * 10, '1.1.30', '1/1/1')];
    final text = ForumPackage.build(telegrams: many, catalog: _catalog, format: ForumFormat.markdown);
    expect(text.split('\n').where((l) => l.startsWith('| 20:15')).length, ForumPackage.maxRows);
    expect(text, contains('gekürzt auf die ersten 60'));
  });

  test('Aufnahme: Gateway-Bezeichnung als Verbindung, ohne IP-Adresse', () {
    final text = ForumPackage.build(
      telegrams: _telegrams,
      catalog: _catalog,
      format: ForumFormat.markdown,
      connection: 'IP-Router · 192.168.1.10',
    );
    expect(text, contains('- Verbindung: IP-Router · <ip>'));
    expect(text, isNot(contains('192.168')));
  });
}
