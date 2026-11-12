import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/health.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/monitor_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Before, the quiet check never ran in the demo house: the last row of the overview's green box
  // read "Diese Woche wurde noch nicht geprüft." for the whole visit.
  testWidgets('Demo-Haus: Wochenampel ist nach kurzer Zeit geprüft', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = CatalogStore.instance..beginDemo(demoCatalog());
    HealthCheck.instance.startDemo();
    final tunnel = DemoTunnel();
    await tunnel.connect();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: MonitorScreen(tunnel: tunnel),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(HealthCheck.instance.runs, isEmpty);
    expect(find.text('Diese Woche wurde noch nicht geprüft.'), findsOneWidget);

    for (var i = 0; i < MonitorScreen.demoPassiveAfter.inSeconds + 2; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    final run = HealthCheck.instance.runs.single;
    expect(run.passive, isTrue);
    expect(find.text('Diese Woche wurde noch nicht geprüft.'), findsNothing);
    // Only what the demo house stages on purpose: humidity with the wrong length, the heating
    // actuator's repeats and the faults of the DALI gateway.
    const staged = {
      FindingKind.dptSize,
      FindingKind.repeats,
      FindingKind.lampFault,
      FindingKind.gearFault,
      FindingKind.testFailed,
      FindingKind.testOverdue,
    };
    // All of them, and nothing else: an empty run would leave the light green.
    expect({for (final f in run.findings) f.kind}, staged);

    await tester.pumpWidget(const SizedBox.shrink());
    await tunnel.disconnect();
    tunnel.dispose();
    store.endDemo();
    HealthCheck.instance.debugReset();
  });
}
