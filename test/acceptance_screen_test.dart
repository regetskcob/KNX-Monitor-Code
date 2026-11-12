import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/commissioning.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/model/site_photos.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/acceptance_screen.dart';
import 'package:knx_monitor/ui/photo_pick.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final c = Commissioning.instance;
  final rm = parseGroup('1/4/0')!;
  final temp = parseGroup('2/0/0')!;
  final wind = parseGroup('3/0/0')!;

  Future<void> prepare(WidgetTester tester, {List<int> issues = const []}) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('acceptance_screen');
      AppStorage.instance = IoStorage(dir);
      InstallationStore.instance.debugReset();
      await InstallationStore.instance.load();
      SitePhotoStore.instance.debugReset();
      c.debugReset();
      CatalogStore.instance.catalog = GroupCatalog({
        rm: GroupInfo(address: rm, name: 'Licht Flur RM', path: 'Licht'),
        temp: GroupInfo(address: temp, name: 'Ist-Temperatur', path: 'Heizung'),
        wind: GroupInfo(address: wind, name: 'Windalarm', path: 'Wetter'),
      }, projectName: 'Haus Muster');
      c.prepare([rm, temp, wind]);
      c.mark(rm, CheckState.ok);
      for (final a in issues) {
        c.mark(a, CheckState.issue);
      }
      c.setNote(temp, 'Fühler defekt');
      addTearDown(() async {
        CatalogStore.instance.catalog = GroupCatalog.empty;
        debugPhotoSource = null;
        await c.flush();
        await dir.delete(recursive: true);
      });
    });
  }

  Widget app() => MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('de'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: const AcceptanceScreen(),
  );

  void size(WidgetTester tester, Size s) {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('ohne Mängel: freiwillige Angaben, aber kein Abschnitt für Fotos', (tester) async {
    await prepare(tester);
    size(tester, const Size(375, 3000));
    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.text('Angaben zum Auftrag (optional)'), findsOneWidget);
    expect(find.text('Bezug auf Norm'), findsOneWidget);
    expect(find.text('Projektnummer'), findsOneWidget);
    expect(find.text('Beginn der Gewährleistung'), findsOneWidget);
    expect(find.text('Fotos zu den Mängeln'), findsNothing);
    // Schmal: untereinander.
    final standard = tester.getRect(find.text('Bezug auf Norm'));
    final number = tester.getRect(find.text('Projektnummer'));
    expect(number.top, greaterThan(standard.bottom));
    expect(number.left, closeTo(standard.left, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Beginn der Gewährleistung: Datum wählen und wieder entfernen', (tester) async {
    await prepare(tester);
    size(tester, const Size(600, 3000));
    await tester.pumpWidget(app());
    await tester.pump();
    final pick = find.widgetWithText(OutlinedButton, 'Datum wählen');
    expect(tester.getSize(pick).height, greaterThanOrEqualTo(44));
    await tester.tap(pick);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(pick, findsNothing);
    final clear = find.byTooltip('Datum entfernen');
    expect(tester.getSize(clear).height, greaterThanOrEqualTo(44));
    await tester.tap(clear);
    await tester.pump();
    expect(pick, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('breites Fenster: Formular links, Mängel und Unterschriften rechts, die Breite wird genutzt', (
    tester,
  ) async {
    await prepare(tester, issues: [temp, wind]);
    size(tester, const Size(1400, 1200));
    await tester.pumpWidget(app());
    await tester.pump();
    final customer = tester.getRect(find.text('Kunde'));
    final signatures = tester.getRect(find.text('Unterschriften'));
    final defects = tester.getRect(find.text('Fotos zu den Mängeln'));
    // Two columns: the right one starts in the right half, next to the form, not below it.
    expect(signatures.left, greaterThan(700));
    expect(defects.left, greaterThan(700));
    expect(customer.left, lessThan(100), reason: 'the form starts at the left edge, no centred narrow column');
    expect(defects.top, lessThan(customer.top + 200));
    // The page ends within the window: nothing is pushed far down by a single long column.
    expect(tester.getRect(find.text('Protokoll erstellen')).bottom, lessThan(1200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mittlere Breite: Angaben in einer Zeile, Mängel zweispaltig; Foto hinzufügen und entfernen', (
    tester,
  ) async {
    await prepare(tester, issues: [temp, wind]);
    final jpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 40, height: 30)));
    debugPhotoSource = () async => jpeg;
    size(tester, const Size(800, 3000));
    await tester.pumpWidget(app());
    await tester.pump();
    final standard = tester.getRect(find.text('Bezug auf Norm'));
    final number = tester.getRect(find.text('Projektnummer'));
    final warranty = tester.getRect(find.text('Beginn der Gewährleistung'));
    expect(number.top, standard.top);
    expect(warranty.top, standard.top);
    expect(number.left, greaterThan(standard.right));
    expect(warranty.left, greaterThan(number.right));

    expect(find.text('Fotos zu den Mängeln'), findsOneWidget);
    expect(find.text('Fühler defekt'), findsOneWidget);
    final add = find.widgetWithText(OutlinedButton, 'Foto hinzufügen');
    expect(add, findsNWidgets(2), reason: 'je Mangel, nicht für den Punkt, der in Ordnung ist');
    expect(tester.getSize(add.first).height, greaterThanOrEqualTo(44));
    // Same row (one tile is a line taller: it has a note).
    expect(tester.getRect(add.last).top, closeTo(tester.getRect(add.first).top, 40), reason: 'zwei Spalten');
    expect(tester.getRect(add.last).left, greaterThan(tester.getRect(add.first).right));

    await tester.tap(add.first);
    // The image is normalized in the background (real time).
    for (var i = 0; i < 200 && find.byTooltip('Foto entfernen').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(find.byTooltip('Foto entfernen'), findsOneWidget);
    expect(add, findsOneWidget);
    expect(tester.getSize(find.byTooltip('Foto entfernen')).height, greaterThanOrEqualTo(44));
    // Erst mit dem Protokoll landet das Foto in der Fotodokumentation.
    expect(SitePhotoStore.instance.photos, isEmpty);
    await tester.tap(find.byTooltip('Foto entfernen'));
    await tester.pump();
    expect(add, findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
