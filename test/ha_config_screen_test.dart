import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/ui/ha_config_screen.dart';

import 'window.dart';

void main() {
  setUp(() => CatalogStore.instance.catalog = demoCatalog());
  tearDown(() => CatalogStore.instance.catalog = GroupCatalog.empty);

  testWidgets('breites Fenster: Filter neben der Erklärung, Geräte und Räume in Spalten', (tester) async {
    await pumpWindow(tester, const HaConfigScreen(), wideWindow);
    // Erklärung links, Filter rechts daneben auf gleicher Höhe.
    final explain = tester.getTopLeft(find.textContaining('Busclear leitet'));
    final types = tester.getTopLeft(find.text('Typen'));
    expect(types.dx, greaterThan(wideWindow.width / 2));
    expect(types.dy, closeTo(explain.dy, 8));
    // Gerätevorschläge und darunter die Räume: Schalter in mehreren Spalten bis an den rechten Rand.
    final columns = columnsOf(tester, find.byType(Switch)).toList()..sort();
    expect(columns.length, greaterThanOrEqualTo(2));
    expect(columns.last, greaterThan(wideWindow.width * 0.8));
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
    expect(columnsOf(tester, find.byType(Switch)).length, greaterThanOrEqualTo(3));
  });

  testWidgets('Telefon und schmales Fenster: alles untereinander in einer Spalte', (tester) async {
    for (final size in [phoneWindow, const Size(800, 1000)]) {
      await pumpWindow(tester, const HaConfigScreen(), size);
      final explain = tester.getTopLeft(find.textContaining('Busclear leitet'));
      final types = tester.getTopLeft(find.text('Typen'));
      expect(types.dx, lessThan(size.width / 2), reason: '$size');
      expect(types.dy, greaterThan(explain.dy + 100), reason: '$size');
    }
    // Bei 800 pt (die Testschrift ist breiter als die echte, am Telefon passt die Gerätezeile mit
    // ihr nicht): Geräte und Räume bleiben eine Spalte.
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pump();
    expect(columnsOf(tester, find.byType(Switch)), hasLength(1));
    await pumpWindow(tester, const HaConfigScreen(), wideWindow, textScale: 2);
  });

  testWidgets('Telefon: Gerätezeile bricht um statt überzulaufen, auch bei doppelter Schrift', (tester) async {
    for (final scale in [1.0, 2.0]) {
      await pumpWindow(tester, const HaConfigScreen(), phoneWindow, textScale: scale);
      await tester.dragUntilVisible(find.text('Alle übernehmen'), find.byType(ListView), const Offset(0, -200));
      expect(tester.takeException(), isNull, reason: 'Schrift $scale');
      expect(
        tester.getBottomRight(find.text('Keine')).dx,
        lessThanOrEqualTo(phoneWindow.width),
        reason: 'Schrift $scale',
      );
    }
  });
}
