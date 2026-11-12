import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/telegram_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wide live list (iPad, Mac, Android tablet) without a project and without taught-in names: no
/// column "Name" full of "—"; the value gets its room. With names as before.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocaleController.instance.debugSetLocale(const Locale('de'));
  });
  tearDown(() => CatalogStore.instance.catalog = GroupCatalog.empty);

  final telegram = Telegram(
    time: DateTime(2026, 11, 11, 14, 2),
    source: 0x1105,
    destination: 0x0A03,
    type: TelegramType.write,
    data: Uint8List.fromList([0x80]),
    isSmall: false,
  );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1180, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              const TelegramTableHeader(),
              TelegramRow(telegram: telegram, wide: true),
            ],
          ),
        ),
      ),
    );
  }

  // Column labels are set in capitals.
  final nameHeader = find.textContaining(RegExp('^${s.columnName}\$', caseSensitive: false));

  testWidgets('ohne Projekt: keine Spalte „Name“, der Wert bekommt den Platz', (tester) async {
    await pump(tester);
    expect(nameHeader, findsNothing);
    expect(find.text('—'), findsNothing);
    final value = tester.getSize(find.ancestor(of: find.text('0x80 · 128'), matching: find.byType(Expanded)).first);

    CatalogStore.instance.catalog = GroupCatalog({0x0A03: GroupInfo(address: 0x0A03, name: 'Dimmwert Küche')});
    // The setter for tests does not notify; a fresh tree instead.
    await tester.pumpWidget(const SizedBox.shrink());
    await pump(tester);
    expect(nameHeader, findsOneWidget);
    expect(find.text('Dimmwert Küche'), findsOneWidget);
    final narrower = tester.getSize(find.ancestor(of: find.text('0x80 · 128'), matching: find.byType(Expanded)).first);
    expect(value.width, greaterThan(narrower.width * 2));
  });

  testWidgets('Live-Spalte neben der Übersicht: ein langer Wert bleibt in seiner Zeile', (tester) async {
    tester.view.physicalSize = const Size(1800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final long = Telegram(
      time: DateTime(2026, 11, 12, 8, 50),
      source: 0x1105,
      destination: 0x0A03,
      type: TelegramType.write,
      data: Uint8List.fromList(List.generate(14, (i) => 0x41 + i)),
      isSmall: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: SizedBox(width: 470, child: TelegramRow(telegram: long)),
          ),
        ),
      ),
    );
    // The value takes its share of the 470 pt column, not 40 % of the 1800 pt window.
    expect(tester.takeException(), isNull);
  });
}
