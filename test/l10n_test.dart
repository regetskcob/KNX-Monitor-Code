import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/knx/dpt_codec.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/analysis.dart';
import 'package:knx_monitor/theme/palette.dart';
import 'package:knx_monitor/ui/connect_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Telegram _write(List<int> data, {bool small = false}) => Telegram(
  time: DateTime(2026, 10, 14),
  source: 0x1105,
  destination: 0x0A03,
  type: TelegramType.write,
  data: Uint8List.fromList(data),
  isSmall: small,
);

void main() {
  final controller = LocaleController.instance;

  tearDown(() => controller.debugSetLocale(const Locale('de')));

  test('Standard ist Deutsch', () {
    expect(controller.locale.languageCode, 'de');
    expect(decodeDpt(const Dpt(1, 1), _write([1], small: true)), 'Ein');
  });

  test('Englisch: DPT-Texte, Dezimalpunkt, Hinweise', () {
    controller.debugSetLocale(const Locale('en'));
    expect(decodeDpt(const Dpt(1, 1), _write([1], small: true)), 'On');
    expect(decodeDpt(const Dpt(1, 8), _write([0], small: true)), 'Up');
    expect(decodeDpt(const Dpt(9, 1), _write([0x0C, 0x24])), '21.2 °C');
    expect(decodeDpt(const Dpt(10, 1), _write([0x6E, 0x2F, 0x00])), 'Wed 14:47:00');
    expect(decodeDpt(const Dpt(17, 1), _write([4])), 'Scene 5');
    expect(TelegramIssue.repeated.label, 'Repeated');
    expect(Palette.label(TelegramType.response), 'Response');
    expect(s.groupAddressCount(1), '1 group address');
    expect(s.groupAddressCount(3), '3 group addresses');

    controller.debugSetLocale(const Locale('de'));
    expect(decodeDpt(const Dpt(9, 1), _write([0x0C, 0x24])), '21,2 °C');
    expect(TelegramIssue.repeated.label, 'Wiederholt');
    expect(s.groupAddressCount(3), '3 Gruppenadressen');
  });

  testWidgets('Sprachwahl auf dem Verbinden-Bildschirm wirkt sofort und wird gespeichert', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: ConnectScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Verbinden'), findsOneWidget);

    await tester.ensureVisible(find.text('English'));
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Connect'), findsOneWidget);
    // Ohne Expertenmodus: Demo statt Aufnahmen.
    expect(find.text('Try demo'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('app_language'), 'en');

    await tester.ensureVisible(find.text('Deutsch'));
    await tester.tap(find.text('Deutsch'));
    await tester.pumpAndSettle();
    expect(find.text('Verbinden'), findsOneWidget);
  });
}
