import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/horizon_rail.dart';
import 'package:knx_monitor/ui/object_board.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late TelegramLog log;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CatalogStore.instance.catalog = demoCatalog();
    var now = DateTime(2026, 10, 21, 14);
    DemoTunnel.clock = () => now = now.add(const Duration(milliseconds: 900));
    final tunnel = DemoTunnel();
    log = TelegramLog()..addAll(tunnel.simulate());
    tunnel.dispose();
    DemoTunnel.clock = DateTime.now;
  });

  Future<void> pump(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ObjectBoard(data: log, matches: (_) => true, onFilter: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Breit: Gliederung rechts, Antippen springt zum Raum', (tester) async {
    await pump(tester, 1400);
    expect(find.byType(HorizonRail), findsOneWidget);
    final scroll = tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller!;
    expect(scroll.offset, 0);
    // Letzte Marke der Gliederung antippen: die Liste scrollt nach unten.
    final marks = find.descendant(of: find.byType(HorizonRail), matching: find.byType(GestureDetector));
    await tester.tap(marks.last);
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
  });

  testWidgets('Schmal: keine Gliederung', (tester) async {
    await pump(tester, 900);
    expect(find.byType(HorizonRail), findsNothing);
  });
}
