import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/busmon.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/busmonitor_panels.dart';
import 'package:knx_monitor/ui/device_sheet.dart';
import 'package:knx_monitor/ui/diagnostics_screen.dart';

/// Senders in the bus monitor and in the diagnostics open their device sheet, as in the live
/// list, overview and topology.
void main() {
  Widget app(Widget home) => MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('de'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  setUp(() => LocaleController.instance.debugSetLocale(const Locale('de')));
  tearDown(() => CatalogStore.instance.catalog = GroupCatalog.empty);

  testWidgets('Busmonitor: Absender in den Rahmendetails öffnet das Geräteblatt', (tester) async {
    final body = [0xBC, 0x11, 0x05, 0x0A, 0x03, 0xE1, 0x00, 0x81];
    final frame = BusmonFrame.fromRaw(
      Uint8List.fromList([...body, ~body.fold<int>(0, (a, b) => a ^ b) & 0xFF]),
      time: DateTime(2026, 11, 7),
    );
    await tester.pumpWidget(
      app(
        Scaffold(
          body: SingleChildScrollView(
            child: BusmonFrameDetails(frame: frame, log: TelegramLog()),
          ),
        ),
      ),
    );
    final link = find.byType(DeviceLink);
    expect(link, findsOneWidget);
    expect(tester.getSize(link).height, greaterThanOrEqualTo(44));
    final semantics = tester.getSemantics(link).getSemanticsData();
    expect(semantics.hint, s.devOpenHint);
    expect(semantics.hasAction(SemanticsAction.tap), isTrue);
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.byType(DeviceTraffic), findsOneWidget);

    // Opened from the bus monitor without a way back: no line button in the sheet.
    expect(find.byType(LineFilterButton), findsNothing);
    Navigator.of(tester.element(find.byType(DeviceTraffic))).pop();
    await tester.pumpAndSettle();

    // With the monitor's filter passed on, the sheet offers the line, and it sets the filter.
    final filters = <String>[];
    await tester.pumpWidget(
      app(
        Scaffold(
          body: SingleChildScrollView(
            child: BusmonFrameDetails(frame: frame, log: TelegramLog(), onFilter: filters.add),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(DeviceLink));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(LineFilterButton));
    await tester.pumpAndSettle();
    expect(filters.single, endsWith('1.1.*'));

    // Without monitor traffic nothing to open: plain text as before.
    await tester.pumpWidget(
      app(
        Scaffold(
          body: SingleChildScrollView(child: BusmonFrameDetails(frame: frame)),
        ),
      ),
    );
    expect(find.byType(DeviceLink), findsNothing);
  });

  testWidgets('Diagnose: gefundenes Gerät der Adressprüfung öffnet das Geräteblatt', (tester) async {
    CatalogStore.instance.catalog = demoCatalog();
    final tunnel = DemoTunnel();
    await tunnel.connect();
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(DiagnosticsScreen(tunnel: tunnel, log: TelegramLog())));
    await tester.enterText(find.widgetWithText(TextField, '').first, '1.1.10');
    await tester.tap(find.text(s.diagCheck));
    // The demo devices answer with delays: real ones for the tunnel, fake ones for the timers.
    for (var i = 0; i < 50 && find.byType(DeviceLink).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    final link = find.byType(DeviceLink);
    expect(link, findsOneWidget);
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.byType(DeviceTraffic), findsOneWidget);
    await tunnel.disconnect();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
