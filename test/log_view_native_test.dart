import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizont/horizont.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/log_view.dart';
import 'package:knx_monitor/ui/telegram_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<TelegramLog> pump(WidgetTester tester, {required double width}) async {
    CatalogStore.instance.catalog = demoCatalog();
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tunnel = KnxTunnel('192.0.2.1');
    addTearDown(tunnel.dispose);
    final log = TelegramLog();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: LogView(data: log, tunnel: tunnel, title: const Kennung('Gira X1'), exportTitle: 'Test'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    return log;
  }

  testWidgets('Telefon: Suche im Fokus, Titelzeile weg, Abbrechen leert und holt sie zurück', (tester) async {
    await pump(tester, width: 390);
    final search = find.byType(TextField).first;
    double barHeight() => tester.getSize(find.byType(AppBar)).height;
    final full = tester.getRect(search).top;
    expect(barHeight(), greaterThan(0));

    await tester.tap(search);
    await tester.pumpAndSettle();
    expect(tester.getRect(search).top, lessThan(full), reason: 'Suchfeld rückt nach oben');
    expect(find.text('Abbrechen'), findsOneWidget);
    await tester.enterText(search, '1/2/3');
    await tester.pump();

    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(find.text('Abbrechen'), findsNothing);
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(tester.getRect(search).top, full);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('Tablet behält die Titelzeile', (tester) async {
    await pump(tester, width: 820);
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(find.text('Abbrechen'), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('Mac: Cmd+F sucht, Esc leert, Leertaste pausiert nur außerhalb des Felds', (tester) async {
    final log = await pump(tester, width: 1100);
    final search = find.byType(TextField).first;
    final field = tester.widget<TextField>(search);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(log.paused, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(log.paused, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(field.focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(log.paused, isFalse, reason: 'beim Tippen gehört die Leertaste dem Feld');

    field.controller!.text = '1/2/3';
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(field.focusNode!.hasFocus, isFalse);
    expect(field.controller!.text, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(log.paused, isTrue, reason: 'nach Esc wirkt die Leertaste wieder');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Rechtsklick auf ein Telegramm: Menü, Filtern', (tester) async {
    final log = await pump(tester, width: 1100);
    log.add(
      Telegram(
        time: DateTime(2026, 11, 1, 12),
        source: 0x1101,
        destination: 0x0A03,
        type: TelegramType.write,
        data: Uint8List.fromList([1]),
        isSmall: true,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Live').first);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    final row = find.byType(TelegramRow).first;
    await tester.tap(row, buttons: kSecondaryButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.text('Details öffnen'), findsOneWidget);
    expect(find.text('Auswählen'), findsOneWidget);
    await tester.tap(find.text('Filtern'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, isNotEmpty);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
