import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/chart_cards.dart';
import 'package:knx_monitor/ui/charts_overview.dart';
import 'package:horizont/horizont.dart';
import 'package:knx_monitor/model/saved_charts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SavedCharts.instance.reset();
  });

  test('anlegen, umbenennen an gleicher Stelle, löschen, freie Namen', () async {
    final c = SavedCharts.instance;
    await c.useScope('Haus A');
    await c.put('Wetter', [1, 2, 3]);
    await c.put('Heizung', [4]);
    expect(c.uniqueName('Wetter'), 'Wetter 2');
    await c.put('Draußen', [1, 2], from: 'Wetter');
    expect(c.charts.keys, ['Draußen', 'Heizung']);
    expect(c.charts['Draußen'], [1, 2]);
    await c.put('Viel', List.generate(20, (i) => i));
    expect(c.charts['Viel'], hasLength(SavedCharts.maxSeries));
    await c.remove('Heizung');
    expect(c.charts.keys, ['Draußen', 'Viel']);

    // Übersteht einen Neustart.
    c.reset();
    await c.useScope('Haus A');
    expect(c.charts.keys, ['Draußen', 'Viel']);

    // Andere Anlage, eigene Diagramme.
    await c.useScope('Haus B');
    expect(c.isEmpty, isTrue);
    await c.useScope('Haus A');
    expect(c.charts, hasLength(2));
  });

  test('für Add-on und Dashboard-Karte: Reihen mit Adresse und Beschriftung', () async {
    final c = SavedCharts.instance;
    await c.useScope('Haus A');
    await c.put('Heizung', [0x0A01, 0x0A02]);
    final json = c.serverJson();
    expect(json['scope'], 'Haus A');
    expect(json['allowed'], isA<bool>());
    final chart = (json['charts']! as List).single as Map<String, Object?>;
    expect(chart['name'], 'Heizung');
    final series = (chart['series']! as List).cast<Map<String, Object?>>();
    expect(series.map((s) => s['address']), [0x0A01, 0x0A02]);
    expect(series.first['label'], '1/2/1');
    expect(series.first, containsPair('off', isA<String>()));
    expect(series.first, containsPair('on', isA<String>()));
  });

  test('alte gemeinsame Diagramme wandern in die erste geöffnete Anlage', () async {
    SharedPreferences.setMockInitialValues({'chart_selections': '{"Alt":[1,2]}'});
    final c = SavedCharts.instance;
    await c.useScope('Haus A');
    expect(c.charts['Alt'], [1, 2]);
    await c.useScope('Haus B');
    expect(c.isEmpty, isTrue);
  });

  testWidgets('Bibliothek: Vorlagen aus dem Projekt übernehmen, einzeln und alle', (tester) async {
    CatalogStore.instance.catalog = demoCatalog();
    var now = DateTime(2026, 10, 21, 14);
    DemoTunnel.clock = () => now = now.add(const Duration(milliseconds: 900));
    final tunnel = DemoTunnel();
    final log = TelegramLog()..addAll(tunnel.simulate());
    tunnel.dispose();
    DemoTunnel.clock = DateTime.now;
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await SavedCharts.instance.useScope('Demo');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ChartsOverview(log: log),
      ),
    );
    await tester.pump();
    expect(find.text(s.chartTemplatesIntro), findsOneWidget);
    Finder head(String title) => find.byWidgetPredicate((w) => w is HorizontSectionHeader && w.title == title);
    expect(head(s.chartRecipeClimate), findsOneWidget);
    expect(find.text('${s.chartRecipeClimate} · EG KÜ'), findsOneWidget);

    // Eine übernehmen: Sie wird ein eigenes Diagramm und ist markiert.
    final kitchen = find.ancestor(of: find.text('${s.chartRecipeClimate} · EG KÜ'), matching: find.byType(ChartCard));
    await tester.tap(find.descendant(of: kitchen, matching: find.text(s.chartTemplateAdopt)));
    await tester.pumpAndSettle();
    final first = SavedCharts.instance.charts.keys.single;
    expect(first, startsWith(s.chartRecipeClimate));
    expect(head(s.chartsSaved), findsOneWidget);
    expect(find.text(s.chartTemplateAdopted), findsOneWidget);

    // Alle Raumklima-Vorlagen: die übrigen sieben, keine doppelt.
    final climateHead = find.byWidgetPredicate((w) => w is HorizontSectionHeader && w.title == s.chartRecipeClimate);
    await tester.tap(find.descendant(of: climateHead, matching: find.text(s.chartTemplatesAdoptAll)));
    await tester.pumpAndSettle();
    expect(SavedCharts.instance.charts.keys.where((n) => n.startsWith(s.chartRecipeClimate)), hasLength(8));
  });
}
