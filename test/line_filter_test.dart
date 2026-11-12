import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizont/horizont.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/filter.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/device_sheet.dart';
import 'package:knx_monitor/ui/diagnostics_screen.dart';
import 'package:knx_monitor/ui/log_view.dart';
import 'package:knx_monitor/ui/topology_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tapping a line (device sheet, topology, line scan) filters the monitor by its senders
/// (`von:1.1.*`) and opens the live list with it.
void main() {
  Widget app(Widget home) => MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('de'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocaleController.instance.debugSetLocale(const Locale('de'));
  });
  tearDown(() => CatalogStore.instance.catalog = GroupCatalog.empty);

  test('Linien-Suche: von:1.1.*, in beiden Sprachen erkannt', () {
    expect(lineQuery(0x11), 'von:1.1.*');
    expect(isLineQuery('von:1.1.*'), isTrue);
    expect(isLineQuery('from:15.15.*'), isTrue);
    expect(isLineQuery('von:1.1.5'), isFalse);
    expect(isLineQuery('1.1.*'), isFalse);
  });

  testWidgets('Geräteblatt: Linie zeigt die Linie im Monitor', (tester) async {
    String? query;
    await tester.pumpWidget(
      app(
        Scaffold(
          body: DeviceTraffic(address: 0x1105, log: TelegramLog(), onLineFilter: (q) => query = q),
        ),
      ),
    );
    await tester.tap(find.byTooltip(s.devLineShow('1.1')));
    expect(query, 'von:1.1.*');
  });

  for (final size in const [Size(1680, 1050), Size(393, 852)]) {
    testWidgets('Topologie: Linie zeigt die Linie im Monitor ($size)', (tester) async {
      CatalogStore.instance.catalog = demoCatalog();
      String? query;
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(TopologyScreen(log: TelegramLog(), onFilter: (q) => query = q)));
      await tester.pump(const Duration(seconds: 1));
      // Wide in the device tree's line header (icon with tooltip), otherwise on the line card.
      final button = find.bySemanticsLabel(s.devLineShow('1.1')).first;
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      expect(query, 'von:1.1.*');
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Linienscan: gescannte Linie im Monitor zeigen', (tester) async {
    CatalogStore.instance.catalog = demoCatalog();
    final tunnel = DemoTunnel();
    await tunnel.connect();
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? query;
    await tester.pumpWidget(app(DiagnosticsScreen(tunnel: tunnel, log: TelegramLog(), onFilter: (q) => query = q)));
    await tester.tap(find.text(s.scanStart));
    await tester.pump();
    await tester.tap(find.text(s.commonCancel));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text(s.devLineShow('1.1')));
    expect(query, 'von:1.1.*');
    await tunnel.disconnect();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Monitor: Linien-Filter von außen öffnet die Live-Liste', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tunnel = KnxTunnel('192.0.2.1');
    addTearDown(tunnel.dispose);
    final filter = StreamController<String>.broadcast();
    addTearDown(filter.close);
    await tester.pumpWidget(
      app(
        LogView(
          data: TelegramLog(),
          tunnel: tunnel,
          title: const Kennung('Gira X1'),
          exportTitle: 'Test',
          filter: filter.stream,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(s.liveWaiting), findsNothing);
    filter.add('von:1.1.*');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(s.liveWaiting), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, 'von:1.1.*');
  });
}
