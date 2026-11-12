import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/model/commissioning.dart';
import 'package:knx_monitor/model/dali.dart';
import 'package:knx_monitor/model/dali_log.dart';
import 'package:knx_monitor/model/health.dart';
import 'package:knx_monitor/model/plan.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/model/write_notice.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/dali_commissioning_screen.dart';
import 'package:knx_monitor/ui/dali_details.dart';
import 'package:knx_monitor/ui/dali_log_screen.dart';
import 'package:knx_monitor/ui/dali_screen.dart';
import 'package:knx_monitor/ui/dali_watch.dart';
import 'package:knx_monitor/ui/dali_widgets.dart';
import 'package:knx_monitor/ui/health_screen.dart';
import 'package:knx_monitor/ui/watch_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dali_fakes.dart';
import 'memory_storage.dart';

void main() {
  final store = DaliStore.instance;
  final log = DaliTestLog.instance;
  late FakeTunnel tunnel;
  final now = DateTime(2026, 11, 10, 12);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppStorage.instance = MemoryStorage();
    DaliProfiles.debugSet(const []);
    store.debugReset();
    log.debugReset();
    Commissioning.instance.debugReset();
    WriteNotice.instance.debugDismiss();
    CatalogStore.instance
      ..overrides = {}
      ..catalog = daliCatalog();
    tunnel = FakeTunnel();
  });

  tearDown(() async {
    tunnel.dispose();
    await store.flush();
    CatalogStore.instance.catalog = GroupCatalog.empty;
  });

  /// A lamp failure at 12 (named), a driver failure at 3, healthy luminaires, a failed test at 16.
  void fill() {
    for (var a = 0; a < 16; a++) {
      store.observe(tg(diag, '00${a.toRadixString(16).padLeft(2, '0')}', at: now.subtract(const Duration(days: 5))));
    }
    store.observe(tg(diag, '010C', at: now.subtract(const Duration(days: 3))));
    store.observe(tg(diag, '0203', at: now.subtract(const Duration(hours: 5))));
    store.editGear(store.gear(gatewayPa, 12)!, name: 'Flur EG Leuchte 2', room: 'Flur EG', groups: {1});
    store.rename(store.group(gatewayPa, 1)!, 'Flur EG');
    store.observe(tg(ga('5/2/16'), '0300500000FF', at: now.subtract(const Duration(days: 9))));
  }

  /// The store saves two seconds after a change: done before the test ends.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await store.flush();
      await Commissioning.instance.flush();
    });
    await tester.pump(const Duration(seconds: 3));
  }

  Future<void> pump(WidgetTester tester, Widget home, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: home));
    await tester.pump();
  }

  testWidgets('Ohne Gateway: sagt, was zu tun ist; der Menüeintrag erscheint nur mit DALI', (tester) async {
    expect(daliKnown(), isTrue);
    CatalogStore.instance.catalog = GroupCatalog.empty;
    store.debugReset();
    expect(daliKnown(), isFalse);
    CatalogStore.instance.overrides = {diag: const Dpt(237, 600)};
    expect(daliKnown(), isTrue, reason: 'a DALI type chosen by hand');
    CatalogStore.instance.overrides = {};
    await pump(tester, DaliScreen(tunnel: tunnel, log: TelegramLog(), now: () => now), const Size(400, 800));
    expect(find.text('DALI-Beleuchtung'), findsOneWidget);
    expect(find.text('Kein DALI-Gateway erkannt.'), findsOneWidget);
    expect(find.text('ETS-Projekt'), findsOneWidget);
    expect(find.text('Mithören'), findsOneWidget);
    await settle(tester);
  });

  testWidgets('Telefon: Fehler zuerst, durchgefallener Test zählt mit, Symbol und Dauer', (tester) async {
    fill();
    final handle = tester.ensureSemantics();
    await pump(tester, DaliScreen(tunnel: tunnel, log: TelegramLog(), now: () => now), const Size(400, 900));
    // Lamp failure, driver failure and the failed emergency test.
    expect(find.text('3 Fehler'), findsOneWidget);
    expect(find.text('Flur EG Leuchte 2'), findsOneWidget);
    expect(find.textContaining('Lampenfehler · EVG 12 · Flur EG · G1'), findsOneWidget);
    expect(find.text('seit 3 Tagen'), findsOneWidget);
    expect(find.text('seit 5 Std.'), findsOneWidget);
    expect(find.text('Notlicht 16'), findsOneWidget);
    expect(find.text('Test durchgefallen'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Notlicht 16')).dy, lessThan(tester.getTopLeft(find.text('Gruppen')).dy));
    expect(find.text('G1 Flur EG'), findsOneWidget);
    expect(find.text('0 von 1 in Ordnung'), findsOneWidget);
    expect(find.byType(DaliCell), findsNothing);
    // Reading says that it sends.
    expect(find.textContaining('sendet dafür Leseanforderungen'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Lampenfehler')), findsWidgets);
    await tester.scrollUntilVisible(find.text('Notlicht-Prüfbuch'), 300);
    expect(find.text('Notlicht-Prüfbuch'), findsWidgets);
    expect(tester.takeException(), isNull);
    handle.dispose();
    await settle(tester);
  });

  testWidgets('Blatt einer Notleuchte mit durchgefallenem Test: roter Kasten, nicht „in Ordnung“', (tester) async {
    fill();
    store.observe(tg(ga('5/1/16'), '1055', at: now.subtract(const Duration(days: 9))));
    store.editGear(store.gear(gatewayPa, 16)!, groups: {3}, emergency: true);
    await pump(tester, DaliScreen(tunnel: tunnel, log: TelegramLog(), now: () => now), const Size(400, 900));
    await tester.tap(find.text('Notlicht 16'));
    await tester.pumpAndSettle();
    // The first result seen: its age is unknown, so the box says so instead of "9 days".
    expect(find.text('Dauertest durchgefallen · Alter unbekannt'), findsOneWidget);
    expect(find.textContaining('in Ordnung seit'), findsNothing);
    expect(find.text('ETS-Objekt: Notleuchte 16 Status'), findsNothing);
    expect(find.text('ETS-Objekt: Notleuchte 16 Testergebnis'), findsOneWidget);
    Navigator.of(tester.element(find.text('Dauertest durchgefallen · Alter unbekannt'))).pop();
    await tester.pumpAndSettle();
    // The group with the emergency luminaire is not green either.
    final icon = tester.widget<DaliStateIcon>(
      find.descendant(
        of: find.ancestor(of: find.text('Gruppe 3'), matching: find.byType(Row)).first,
        matching: find.byType(DaliStateIcon),
      ),
    );
    expect(icon.state, DaliState.testFailed);
    expect(tester.takeException(), isNull);
    await settle(tester);
  });

  testWidgets('Breit: Gruppen links, Raster mit 8 Spalten, Leuchte rechts, Prüfbuch beschriftet, Legende vollständig', (
    tester,
  ) async {
    fill();
    final handle = tester.ensureSemantics();
    await pump(tester, DaliScreen(tunnel: tunnel, log: TelegramLog(), now: () => now), const Size(1500, 1000));
    expect(find.byType(DaliCell), findsNWidgets(64));
    expect(find.text('17 belegt'), findsOneWidget);
    expect(tester.getTopLeft(find.text('G1 Flur EG')).dx, lessThan(tester.getTopLeft(find.byType(DaliCell).first).dx));
    final cells = tester.widgetList<DaliCell>(find.byType(DaliCell)).toList();
    expect(tester.getTopLeft(find.byWidget(cells[7])).dy, tester.getTopLeft(find.byWidget(cells[0])).dy);
    expect(tester.getTopLeft(find.byWidget(cells[8])).dy, greaterThan(tester.getTopLeft(find.byWidget(cells[0])).dy));
    expect(find.bySemanticsLabel('Adresse 12, Flur EG Leuchte 2, Lampenfehler'), findsOneWidget);
    expect(find.bySemanticsLabel('Adresse 40, frei'), findsOneWidget);
    expect(find.bySemanticsLabel('Adresse 16, Notlicht 16, Notleuchte, Test durchgefallen'), findsOneWidget);
    expect(cells[16].state, DaliState.testFailed);
    // Legend: failed test and free addresses too.
    expect(find.text('Test durchgefallen'), findsWidgets);
    expect(find.text('frei'), findsOneWidget);
    // A labelled way into the log, and the read hint.
    expect(find.widgetWithText(OutlinedButton, 'Notlicht-Prüfbuch'), findsOneWidget);
    expect(find.textContaining('sendet dafür Leseanforderungen'), findsOneWidget);
    expect(find.textContaining('Tippe eine Adresse an'), findsOneWidget);
    await tester.tap(find.byWidget(cells[12]));
    await tester.pump();
    expect(find.text('Lampenfehler seit 3 Tagen'), findsOneWidget);
    expect(find.text('Raum Flur EG · EVG 12 · Gateway 1.1.40'), findsOneWidget);
    expect(find.text('Nur diese Leuchte melden'), findsOneWidget);
    await tester.tap(find.text('G1 Flur EG'));
    await tester.pump();
    expect(tester.widget<DaliCell>(find.byType(DaliCell).at(12)).dimmed, isFalse);
    expect(tester.widget<DaliCell>(find.byType(DaliCell).at(3)).dimmed, isTrue);
    expect(tester.takeException(), isNull);
    handle.dispose();
    await settle(tester);
  });

  testWidgets('Große Schrift 2,0: Telefon stapelt die Dauer, breit nimmt das Layout der Schrift entsprechend', (
    tester,
  ) async {
    fill();
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, DaliScreen(tunnel: tunnel, log: TelegramLog(), now: () => now), const Size(400, 1600));
    // The duration below the name, not beside it.
    expect(
      tester.getTopLeft(find.text('seit 3 Tagen')).dy,
      greaterThan(tester.getTopLeft(find.text('Flur EG Leuchte 2')).dy),
    );
    expect(tester.takeException(), isNull);
    // 820 wide at scale 2 is a phone's room: the list, no squeezed grid.
    await pump(tester, DaliScreen(tunnel: tunnel, log: TelegramLog(), now: () => now), const Size(820, 1600));
    expect(find.byType(DaliCell), findsNothing);
    // 1640 wide: grid, columns fixed (4 or 8), cells at least a finger wide, no detail panel.
    await pump(tester, DaliScreen(tunnel: tunnel, log: TelegramLog(), now: () => now), const Size(1640, 2400));
    final cells = tester.widgetList<DaliCell>(find.byType(DaliCell)).toList();
    expect(cells.length, 64);
    final perRow = cells
        .where((c) => tester.getTopLeft(find.byWidget(c)).dy == tester.getTopLeft(find.byWidget(cells[0])).dy)
        .length;
    expect(perRow, anyOf(4, 8));
    expect(tester.getSize(find.byType(DaliCell).first).width, greaterThanOrEqualTo(44));
    expect(find.textContaining('Tippe eine Adresse an'), findsNothing);
    expect(tester.takeException(), isNull);
    await settle(tester);
  });

  testWidgets('Gateway ohne Meldung: nicht eingeklappt, neutrales Kennzeichen, Lesen mit Hinweis', (tester) async {
    // A second gateway in the project that has reported and is healthy, so there is folding.
    final catalog = daliCatalog();
    final other = pa('1.1.41');
    final otherDiag = ga('1/4/21');
    CatalogStore.instance.catalog = GroupCatalog(
      {
        ...catalog.groups,
        otherDiag: GroupInfo(
          address: otherDiag,
          name: 'Diagnose OG',
          dpt: const Dpt(237, 600),
          links: [GroupLink(device: other, sends: true)],
        ),
      },
      devices: {
        ...catalog.devices,
        other: DeviceInfo(address: other, name: 'DALI-Gateway OG'),
      },
    );
    store.observe(tg(otherDiag, '0001', source: other, at: now.subtract(const Duration(minutes: 5))));
    await pump(tester, DaliScreen(tunnel: tunnel, log: TelegramLog(), now: () => now), const Size(400, 1200));
    expect(find.text('noch keine Meldung'), findsOneWidget);
    expect(find.text('Noch keine Meldung empfangen.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Diagnose jetzt lesen · ≈ 4 s'), findsOneWidget);
    expect(find.textContaining('Liest 5 Adressen und sendet dafür Leseanforderungen'), findsOneWidget);
    // The healthy one folds, the silent one does not.
    expect(find.text('in Ordnung'), findsOneWidget);
    await settle(tester);
  });

  testWidgets('Stilles Gateway: Warnung statt „in Ordnung“; zyklisches Lesen steht im Kopf', (tester) async {
    store.observe(tg(diag, '000C', at: now.subtract(const Duration(days: 4))));
    store.updateSettings((x) => x.poll = true);
    await pump(tester, DaliScreen(tunnel: tunnel, log: TelegramLog(), now: () => now), const Size(400, 900));
    expect(find.text('still seit 4 Tagen'), findsOneWidget);
    expect(find.text('in Ordnung'), findsNothing);
    expect(find.text('Liest die Diagnose stündlich'), findsOneWidget);
    await settle(tester);
  });

  testWidgets('Vorschlag beim Mithören: übernehmen, erst dann zählt er', (tester) async {
    store.observe(tg(diag, '010C', source: pa('1.1.99'), at: now));
    await pump(tester, DaliScreen(tunnel: tunnel, log: TelegramLog(), now: () => now), const Size(400, 1200));
    expect(find.textContaining('Beim Mithören gefunden'), findsOneWidget);
    await tester.tap(find.text('Übernehmen'));
    await tester.pump();
    expect(store.gateway(pa('1.1.99'))!.trusted, isTrue);
    expect(find.textContaining('Beim Mithören gefunden'), findsNothing);
    await settle(tester);
  });

  testWidgets('Herstellerprofil: Hinweis mit Symbol und „Mehr“-Knopf ab 44 pt, Texte in der Sprache', (tester) async {
    DaliProfiles.debugSet([
      DaliProfile.fromJson({
        'id': 'p',
        'name': 'Testgateway',
        'source': {'de': 'Handbuch S. 3', 'en': 'Manual p. 3'},
        'note': {'de': 'Nur Ausgang A.', 'en': 'Output A only.'},
        'match': {
          'product': ['dg 64'],
        },
        'rules': [
          {'role': 'gearFault', 'first': 230},
        ],
      })!,
    ]);
    store.debugReset();
    await pump(tester, DaliScreen(tunnel: tunnel, log: TelegramLog(), now: () => now), const Size(400, 1200));
    expect(find.textContaining('noch nicht an echten Telegrammen geprüft'), findsOneWidget);
    final more = find.widgetWithText(TextButton, 'Mehr');
    expect(tester.getSize(more).height, greaterThanOrEqualTo(44));
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.text('Handbuch S. 3\n\nNur Ausgang A.'), findsOneWidget);
    await settle(tester);
  });

  testWidgets('„Zur Leuchte“: öffnet am Telefon das Blatt, breit die Zelle', (tester) async {
    fill();
    await pump(
      tester,
      DaliScreen(tunnel: tunnel, log: TelegramLog(), now: () => now, gear: '$gatewayPa:12'),
      const Size(400, 900),
    );
    await tester.pumpAndSettle();
    expect(find.text('Lampenfehler seit 3 Tagen'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await pump(
      tester,
      DaliScreen(tunnel: tunnel, log: TelegramLog(), now: () => now, gear: '$gatewayPa:12'),
      const Size(1500, 1000),
    );
    expect(tester.widget<DaliCell>(find.byType(DaliCell).at(12)).selected, isTrue);
    expect(find.text('Lampenfehler seit 3 Tagen'), findsOneWidget);
    await settle(tester);
  });

  testWidgets('Details: Abschnitt DALI, Werte ohne Monospace, Hinweis mit Link bei falscher Länge', (tester) async {
    fill();
    await pump(
      tester,
      Scaffold(
        body: ListView(
          children: [
            DaliTelegramSection(telegram: tg(diag, '010C')),
            DaliTelegramSection(telegram: tg(diag, '0A3F00')),
            DaliTelegramSection(telegram: tg(ga('1/5/0'), '', bit: 1)),
          ],
        ),
      ),
      const Size(400, 900),
    );
    expect(find.text('Rohwert 01 0C'), findsOneWidget);
    expect(find.text('gesetzt'), findsOneWidget);
    // Two fault flags and the query flag: badges alike.
    expect(find.text('nicht gesetzt'), findsNWidgets(3));
    expect(find.text('Flur EG Leuchte 2'), findsOneWidget);
    expect(find.textContaining('DPT 237.600 erwartet 2 Byte, empfangen 3.'), findsOneWidget);
    expect(find.text('Issue #6 öffnen'), findsOneWidget);
    await settle(tester);
  });

  testWidgets('Prüfbuch: überfällig mit Bezug, fremde Ergebnisse sichtbar, Menü mit Text', (tester) async {
    fill();
    log.record([
      EmergencyTest(
        time: now.subtract(const Duration(days: 41)),
        group: ga('5/2/16'),
        gateway: gatewayPa,
        address: 16,
        kind: EmergencyTestKind.function,
        result: EmergencyResult.passed,
        raw: 'AA',
      ),
      EmergencyTest(
        time: now.subtract(const Duration(days: 1)),
        group: ga('5/2/16'),
        gateway: gatewayPa,
        address: 16,
        kind: EmergencyTestKind.function,
        result: EmergencyResult.passed,
        raw: 'BB',
        source: 0x7777,
        foreign: true,
      ),
    ]);
    await pump(tester, DaliLogScreen(now: () => now), const Size(400, 900));
    await tester.pump();
    expect(find.text('Notlicht 16'), findsOneWidget);
    expect(find.text('Adr. 16'), findsOneWidget);
    expect(find.text('durchgefallen'), findsOneWidget);
    expect(find.text('Funktionstest überfällig: kein neues Ergebnis seit 41 Tagen'), findsOneWidget);
    expect(find.textContaining('anderen Absender als dem Gateway'), findsOneWidget);
    expect(find.text('Alle · 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Mehr'));
    await tester.pumpAndSettle();
    expect(find.text('Aus dem Tagesverlauf nachbauen'), findsOneWidget);
    expect(find.text('Prüfabstände'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notlicht 16'));
    await tester.pumpAndSettle();
    expect(find.textContaining('fremder Absender 7.7.119'), findsOneWidget);
    expect(find.textContaining('erstmals gesehen, Testzeitpunkt unbekannt'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await settle(tester);
  });

  testWidgets('Wächter-Dialog: langer Gateway-Name läuft nicht über; Vorlage auf der Wächter-Seite', (tester) async {
    final catalog = daliCatalog();
    final other = pa('1.1.41');
    final otherDiag = ga('1/4/21');
    CatalogStore.instance.catalog = GroupCatalog(
      {
        ...catalog.groups,
        otherDiag: GroupInfo(
          address: otherDiag,
          name: 'Diagnose OG',
          dpt: const Dpt(237, 600),
          links: [GroupLink(device: other, sends: true)],
        ),
      },
      devices: {
        ...catalog.devices,
        other: DeviceInfo(address: other, name: 'DALI-Gateway OG Büros Nord und Süd mit sehr langem Namen'),
      },
    );
    Plan.instance.demo = true;
    addTearDown(() => Plan.instance.demo = false);
    await pump(tester, const WatchScreen(), const Size(360, 800));
    expect(find.text('DALI-Fehler melden'), findsOneWidget);
    await tester.tap(find.text('DALI-Fehler melden'));
    await tester.pumpAndSettle();
    expect(find.text('Wächter anlegen'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'the gateway dropdown fits the dialog');
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    await settle(tester);
  });

  testWidgets('Wächter nur für übernommene Gateways: Vorschlag beim Mithören öffnet keinen Dialog', (tester) async {
    // The project knows the diagnostic address but no gateway sending it: only a gateway seen on the
    // bus, a suggestion. No menu entry, and the entry point refuses it.
    CatalogStore.instance.catalog = GroupCatalog({
      diag: GroupInfo(address: diag, name: 'Diagnose', dpt: const Dpt(237, 600)),
    });
    store.observe(tg(diag, '010C', source: pa('1.1.99'), at: now));
    final seen = store.gateway(pa('1.1.99'))!;
    expect(seen.trusted, isFalse);
    expect(store.gateways.any((g) => g.trusted), isFalse);
    Plan.instance.demo = true;
    addTearDown(() => Plan.instance.demo = false);
    await pump(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () => addDaliWatch(context, gateway: seen),
                child: const Text('dieses'),
              ),
              TextButton(onPressed: () => addDaliWatch(context), child: const Text('irgendeins')),
            ],
          ),
        ),
      ),
      const Size(400, 800),
    );
    for (final label in ['dieses', 'irgendeins']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing, reason: label);
      expect(tester.takeException(), isNull, reason: label);
      expect(find.textContaining('Wächter gibt es erst für ein übernommenes Gateway'), findsOneWidget, reason: label);
      ScaffoldMessenger.of(tester.element(find.text(label))).removeCurrentSnackBar();
      await tester.pumpAndSettle();
    }
    await pump(tester, DaliScreen(tunnel: tunnel, log: TelegramLog(), now: () => now), const Size(400, 1200));
    await tester.tap(find.byTooltip('Mehr'));
    await tester.pumpAndSettle();
    expect(find.text('DALI-Fehler melden'), findsNothing);
    await settle(tester);
  });

  testWidgets('Inbetriebnahme: Einschalten, falsche Zuordnung wird gemeldet und bewertet', (tester) async {
    final g2 = store.group(gatewayPa, 2)!;
    tunnel.answer = (dest, {small, required read}) => [if (dest == g2.switchGroup) tg(ga('1/6/3'), '', bit: small)];
    await pump(
      tester,
      DaliCommissioningScreen(tunnel: tunnel, window: const Duration(milliseconds: 20)),
      const Size(500, 1200),
    );
    expect(find.text('Einschalten'), findsNWidgets(4));
    await tester.tap(find.text('Einschalten').at(2));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(tunnel.writes, [(g2.switchGroup, 1)]);
    expect(find.text('Rückmeldung kam von Gruppe 3, geschaltet wurde Gruppe 2.'), findsOneWidget);
    expect(find.text('Ausschalten'), findsOneWidget);
    await tester.tap(find.text('Falsche Leuchte'));
    await tester.pump();
    final item = Commissioning.instance.items[g2.switchGroup]!;
    expect((item.state, item.foreign, item.note), (CheckState.issue, true, 'Falsche Leuchte'));
    expect(tester.takeException(), isNull);
    await settle(tester);
  });

  testWidgets('Gesundheitscheck: Beleuchtung mit den schwersten Befunden vorgewählt, Befund als Titel', (tester) async {
    final h = HealthCheck.instance..debugReset();
    h.runs.add(
      HealthRun(
        now,
        [
          HealthFinding(FindingKind.alwaysSilent, ga('1/4/20')),
          HealthFinding(FindingKind.lampFault, gatewayPa, count: 2),
        ],
        asked: 1,
        answered: 0,
      ),
    );
    await pump(tester, HealthScreen(tunnel: tunnel, log: TelegramLog()), const Size(400, 900));
    expect(find.text('2 Leuchten melden Lampenfehler'), findsOneWidget);
    expect(find.textContaining('1.1.40'), findsWidgets);
    h.debugReset();
    await settle(tester);
  });
}
