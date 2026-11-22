import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/knx/dpt_codec.dart';
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

  // Glossary (CLAUDE.md): one English word per German term, checked against the ARB files.
  // "site" survives only as "on site" (vor Ort), in compounds (site survey, site manager) and as
  // the name of a placeholder.
  test('Glossar: englische Begriffe einheitlich', () {
    Map<String, Object?> arb(String lang) =>
        jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map<String, Object?>;
    final de = arb('de'), en = arb('en');
    final wrong = <String>[];
    for (final MapEntry(:key, value: german) in de.entries) {
      final english = en[key];
      if (key.startsWith('@') || german is! String || english is! String) continue;
      final lower = english.toLowerCase();
      void need(RegExp term, RegExp translation, String name) {
        if (term.hasMatch(german) && !translation.hasMatch(lower)) wrong.add('$key: $name ($english)');
      }

      need(RegExp('Durchklingel'), RegExp('ring-through'), 'ring-through test');
      need(RegExp('Klangquittung'), RegExp('sound acknowledgement'), 'sound acknowledgement');
      need(RegExp('[Aa]n(ge)?lern|[Aa]nzulernen'), RegExp('teach|taught'), 'teach-in');
      if (RegExp('roll call|learned').hasMatch(lower)) wrong.add('$key: roll call/learned ($english)');
      final site = RegExp(r'(?<!on )\bsites?\b(?! (survey|notes?|manager|visit)|\})').hasMatch(lower);
      // The tour tells the building (Anlage) from its profile in the app (Installation); there "site" stays.
      if (site && key != 'tourConnectText' && RegExp(r'\bAnlagen?\b').hasMatch(german)) {
        wrong.add('$key: installation, not site ($english)');
      }
    }
    expect(wrong, isEmpty);
  });
}
