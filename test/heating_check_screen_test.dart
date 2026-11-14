import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/ui/heating_check_screen.dart';

import 'window.dart';

final _now = DateTime(2026, 11, 13, 20);
int _ga(String s) => parseGroup(s)!;

Telegram _t(String dest, List<int> data) => Telegram(
  time: _now,
  source: parseIndividual('1.1.30')!,
  destination: _ga(dest),
  type: TelegramType.write,
  data: Uint8List.fromList(data),
  isSmall: false,
);

void main() {
  testWidgets('Räume mit Urteil in Klartext, Auffälliges zuerst; Telefon, große Schrift und breit', (tester) async {
    HeatingCheckScreen.clock = () => _now;
    addTearDown(() => HeatingCheckScreen.clock = DateTime.now);
    GroupInfo g(String a, String name, Dpt dpt) => GroupInfo(address: _ga(a), name: name, dpt: dpt);
    CatalogStore.instance.catalog = GroupCatalog({
      for (final x in [
        g('2/0/1', 'OG Bad Ist-Temperatur', const Dpt(9, 1)),
        g('2/1/1', 'OG Bad Soll-Temperatur', const Dpt(9, 1)),
        g('2/2/1', 'OG Bad Stellwert Heizen (%)', const Dpt(5, 1)),
        g('2/0/2', 'OG Kind Ist-Temperatur', const Dpt(9, 1)),
        g('2/1/2', 'OG Kind Soll-Temperatur', const Dpt(9, 1)),
        g('2/2/2', 'OG Kind Stellwert Heizen (%)', const Dpt(5, 1)),
      ])
        x.address: x,
    });
    final log = TelegramLog()
      ..addAll([
        _t('2/0/1', encodeDpt9(21.4)!),
        _t('2/1/1', encodeDpt9(21.5)!),
        _t('2/2/1', [51]),
        _t('2/0/2', encodeDpt9(18.0)!),
        _t('2/1/2', encodeDpt9(21.0)!),
        _t('2/2/2', [0]),
      ]);
    final screen = HeatingCheckScreen(log: log);

    await pumpWindow(tester, screen, phoneWindow);
    expect(find.text('Regler fordert keine Wärme an'), findsOneWidget);
    expect(find.text('In Ordnung'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('OG Kind')).dy,
      lessThan(tester.getTopLeft(find.text('OG Bad')).dy),
      reason: 'Auffälliges zuerst',
    );
    expect(find.text('18,0 °C'), findsOneWidget);

    await pumpWindow(tester, screen, phoneWindow, textScale: 2);
    await pumpWindow(tester, screen, wideWindow);
    expect(
      tester.getTopLeft(find.text('OG Bad')).dx,
      greaterThan(wideWindow.width / 2),
      reason: 'breit: Räume nebeneinander',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
