import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/ui/coupler_sheet.dart';
import 'package:knx_monitor/ui/device_sheet.dart';
import 'package:knx_monitor/ui/topology_screen.dart';

void main() {
  for (final size in const [Size(1376, 1032), Size(1032, 1376), Size(402, 874)]) {
    testWidgets('Topologie mit Demo-Haus rendert ($size)', (tester) async {
      CatalogStore.instance.catalog = demoCatalog();
      final log = TelegramLog();
      for (final g in demoCatalog().groups.values.take(30)) {
        final sender = g.links.where((l) => l.sends).firstOrNull?.device ?? 0x1101;
        log.add(
          Telegram(
            time: DateTime(2026),
            source: sender,
            destination: g.address,
            type: TelegramType.write,
            data: Uint8List.fromList([1]),
            isSmall: true,
          ),
        );
      }
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TopologyScreen(log: log, onFilter: (_) {}),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(find.byType(TopologyScreen), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });
  }

  for (final size in const [Size(1180, 820), Size(393, 852)]) {
    testWidgets('Koppler antippen zeigt seinen Verkehr ($size)', (tester) async {
      CatalogStore.instance.catalog = demoCatalog();
      var now = DateTime(2026, 10, 14, 21, 50);
      DemoTunnel.clock = () => now = now.add(const Duration(milliseconds: 900));
      final tunnel = DemoTunnel();
      final log = TelegramLog()..addAll(tunnel.simulate());
      tunnel.dispose();
      DemoTunnel.clock = DateTime.now;
      String? filter;
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TopologyScreen(log: log, onFilter: (q) => filter = q),
        ),
      );
      // Geräte sind aufgeklappt: der Koppler kann weiter unten liegen.
      // Breit steht der Koppler als Grafik zwischen den Linien, schmal im Baum
      // bzw. unter der Linie – derselbe Knopf mit derselben Beschriftung.
      final coupler = find
          .byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Koppler 1.2.0, Verkehr anzeigen')
          .first;
      // Breit pulsiert die Kopplergrafik mit dem Verkehr: dort Bilder in festen
      // Schritten statt pumpAndSettle; schmal (Blatt) wie gewohnt.
      Future<void> settle() async {
        if (size.width < 840) {
          await tester.pumpAndSettle();
          return;
        }
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.scrollUntilVisible(coupler, 300, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(coupler);
      await settle();
      expect(coupler, findsOneWidget);
      await tester.tap(coupler);
      await settle();
      expect(find.byType(CouplerTrafficView), findsOneWidget);
      expect(find.text('KOPPLER 1.2.0 · LINIE 1.1 ↔ 1.2'), findsOneWidget);
      // Zeile antippen filtert den Monitor auf die Adresse.
      final row = find.text('4/0/1').last;
      await tester.ensureVisible(row);
      await tester.tap(row);
      await settle();
      expect(filter, '4/0/1');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
    });
  }

  testWidgets('Ab 1200: Gerätebaum links, Gerät und Koppler im Detailbereich', (tester) async {
    CatalogStore.instance.catalog = demoCatalog();
    var now = DateTime(2026, 10, 14, 21, 50);
    DemoTunnel.clock = () => now = now.add(const Duration(milliseconds: 900));
    final tunnel = DemoTunnel();
    final log = TelegramLog()..addAll(tunnel.simulate());
    tunnel.dispose();
    DemoTunnel.clock = DateTime.now;
    String? filter;
    await tester.binding.setSurfaceSize(const Size(1680, 1050));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TopologyScreen(log: log, onFilter: (q) => filter = q),
      ),
    );
    // Linienübergreifende Adressen als eigene Spalte ab 1600 (der Titel trägt weiche Trennstellen).
    expect(find.textContaining(RegExp('^Linien\u00ad?über\u00ad?greifend', caseSensitive: false)), findsOneWidget);
    expect(find.byType(DeviceTraffic), findsNothing);
    final device = CatalogStore.instance.catalog.devices.values.first;
    final row = find.text(device.name).first;
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(DeviceTraffic), findsOneWidget);
    await tester.tap(find.text('Im Monitor filtern'));
    expect(filter, startsWith('von:'));
    // Koppler im Baum ersetzt das Gerät im Detailbereich.
    // Im Baum (erste Liste) steht der Koppler als eigene Zeile.
    final coupler = find.descendant(
      of: find.byType(ListView).first,
      matching: find.bySemanticsLabel(RegExp(r'^Koppler 1\.2\.0, Verkehr anzeigen$')),
    );
    await tester.scrollUntilVisible(coupler, 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(coupler);
    await tester.pumpAndSettle();
    await tester.tap(coupler);
    await tester.pumpAndSettle();
    expect(find.byType(DeviceTraffic), findsNothing);
    expect(find.byType(CouplerTrafficView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Ohne Projekt und Verkehr: Hinweis statt Fehler (breit)', (tester) async {
    CatalogStore.instance.catalog = GroupCatalog.fromJson({'groups': []});
    await tester.binding.setSurfaceSize(const Size(1366, 1024));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TopologyScreen(log: TelegramLog(), onFilter: (_) {}),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('ETS-Projekt'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });
}
