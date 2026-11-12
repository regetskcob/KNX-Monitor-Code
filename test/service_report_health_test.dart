import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/customer.dart';
import 'package:knx_monitor/model/health.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/model/service_report.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/service_report_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The checklist item "health check on the bus" of a maintenance report runs the app's own health
/// check and takes its result, instead of being rated by hand.
void main() {
  Future<void> prepare(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('service_health');
      AppStorage.instance = IoStorage(dir);
      addTearDown(() => dir.delete(recursive: true));
      InstallationStore.instance.debugReset();
      await InstallationStore.instance.load();
      CustomerStore.instance.debugReset();
    });
  }

  Widget app(Widget home) => MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('de'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: home,
  );

  CheckResult selected(WidgetTester tester) => tester
      .widgetList<ChoiceBar<CheckResult>>(find.byType(ChoiceBar<CheckResult>))
      .elementAt(maintenanceCheckKeys.indexOf('health'))
      .selected;

  testWidgets('connected: "Jetzt prüfen" runs the check, rates the item and takes the run as evidence', (tester) async {
    await prepare(tester);
    final store = CatalogStore.instance..beginDemo(demoCatalog());
    HealthCheck.instance.startDemo();
    final tunnel = DemoTunnel();
    await tunnel.connect();
    final log = TelegramLog()..addAll(tunnel.simulate());

    await tester.pumpWidget(app(ServiceReportScreen(maintenance: true, tunnel: tunnel, log: log)));
    for (var i = 0; i < 50 && find.text('Jetzt prüfen').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(find.textContaining('Noch nicht geprüft'), findsOneWidget);
    expect(selected(tester), CheckResult.unchecked);

    await tester.tap(find.text('Jetzt prüfen'));
    // The run reads from storage (real time) and sweeps the status addresses (timers).
    for (var i = 0; i < 1500 && HealthCheck.instance.runs.isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pump();
    final run = HealthCheck.instance.last!;
    // The demo house stages faults on purpose: the item is rated "attention", not by hand.
    expect(run.findings, isNotEmpty);
    expect(selected(tester), CheckResult.attention);
    expect(find.textContaining('Zuletzt geprüft'), findsOneWidget);
    expect(find.textContaining('${run.findings.length} Befund'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The demo's timers must be gone before the test ends.
    await tester.pumpWidget(const SizedBox.shrink());
    await tunnel.disconnect();
    tunnel.dispose();
    store.endDemo();
    HealthCheck.instance.debugReset();
  });

  testWidgets('without a connection: no button, a hint how to get one, rating by hand stays', (tester) async {
    await prepare(tester);
    HealthCheck.instance.debugReset();
    await tester.pumpWidget(app(const ServiceReportScreen(maintenance: true)));
    for (var i = 0; i < 50 && find.text('Bei diesem Besuch geprüft').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(find.text('Jetzt prüfen'), findsNothing);
    expect(find.textContaining('Zum Prüfen die Anlage verbinden'), findsOneWidget);
    expect(selected(tester), CheckResult.unchecked);
  });
}
