import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/export_history.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/exports_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('knx_exports');
    AppStorage.instance = IoStorage(dir);
    ExportHistory.instance
      ..debugReset()
      ..storage = () => AppStorage.instance;
  });
  tearDown(() => dir.delete(recursive: true));

  test('Verlauf hält die letzten fünf, jüngste zuerst, und räumt Dateien weg', () async {
    final history = ExportHistory.instance;
    for (var i = 0; i < 7; i++) {
      await history.add('Datei $i.pdf', Uint8List.fromList([i, i, i]), 'application/pdf');
    }
    expect(history.entries.map((e) => e.name), [
      'Datei 6.pdf',
      'Datei 5.pdf',
      'Datei 4.pdf',
      'Datei 3.pdf',
      'Datei 2.pdf',
    ]);
    expect(await history.read(history.entries.first), [6, 6, 6]);
    // Nur die gemerkten Dateien liegen noch in der Ablage (plus Verzeichnis).
    expect((await AppStorage.instance.list('exports')).where((f) => f.name.endsWith('.b64')), hasLength(5));

    // Neu geladen: aus dem Verzeichnis.
    history.debugReset();
    await history.load();
    expect(history.entries, hasLength(5));
    await history.remove(history.entries.first);
    expect(history.entries.first.name, 'Datei 5.pdf');
  });

  test('Exporte aus dem Demo-Haus landen nicht im Verlauf', () async {
    DemoTunnel.active = true;
    addTearDown(() => DemoTunnel.active = false);
    await ExportHistory.instance.add('Aufgaben für die ETS.pdf', Uint8List(2048), 'application/pdf');
    expect(ExportHistory.instance.entries, isEmpty);
  });

  test('Zu große Dateien merkt sich der Verlauf nicht', () async {
    await ExportHistory.instance.add('riesig.zip', Uint8List(ExportHistory.maxBytes + 1), 'application/zip');
    expect(ExportHistory.instance.entries, isEmpty);
  });

  testWidgets('Seite zeigt Telegramme, Berichte, Gesamtexport und letzte Exporte', (tester) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    CatalogStore.instance.catalog = GroupCatalog.empty;
    await tester.runAsync(() => ExportHistory.instance.add('Bus-Statistik.pdf', Uint8List(2048), 'application/pdf'));
    final log = TelegramLog()
      ..add(
        Telegram(
          time: DateTime(2026, 10, 23, 10),
          source: 0x1101,
          destination: 0x0801,
          type: TelegramType.write,
          data: Uint8List.fromList([1]),
          isSmall: true,
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ExportsScreen(log: log, title: 'KNX-Telegramme', onSelect: () {}),
      ),
    );
    await tester.pump();
    expect(find.text(s.exportAllPdf), findsWidgets);
    expect(find.text(s.exportsReports), findsOneWidget);
    expect(find.text(s.exportsBundle), findsOneWidget);
    expect(find.text('Bus-Statistik.pdf'), findsOneWidget);
    // Telegramm-PDF und Statistik sind vorausgewählt.
    expect(find.text(s.exportsBundleButton(2)), findsOneWidget);
    await tester.tap(find.widgetWithText(CheckboxListTile, s.exportAllCsv));
    await tester.pump();
    expect(find.text(s.exportsBundleButton(3)), findsOneWidget);
    // Ohne Gesundheitslauf und Inbetriebnahme: nicht wählbar.
    expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, s.healthPdfTitle)).enabled, isFalse);
    // Ohne Verbindung lässt sich die Gesundheit nicht prüfen; der Hinweis sagt warum.
    final check = find.widgetWithText(OutlinedButton, s.exportsCheck);
    expect(check, findsOneWidget);
    expect(tester.widget<OutlinedButton>(check).onPressed, isNull);
    expect(find.byTooltip(s.exportsCheckOffline), findsOneWidget);

    // Die Seite folgt dem Zustand, ohne sie neu zu öffnen (Zeilen, Knöpfe,
    // „Läuft …“): hier ein neues Telegramm im Monitor.
    expect(find.text(s.telegramCount(2)), findsNothing);
    log.add(
      Telegram(
        time: DateTime(2026, 10, 23, 10, 1),
        source: 0x1101,
        destination: 0x0802,
        type: TelegramType.write,
        data: Uint8List.fromList([0]),
        isSmall: true,
      ),
    );
    await tester.pump();
    expect(find.text(s.telegramCount(2)), findsWidgets);
  });
}
