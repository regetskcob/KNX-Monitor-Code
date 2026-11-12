import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/main.dart';
import 'package:knx_monitor/model/commissioning.dart';
import 'package:knx_monitor/model/expert_mode.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/theme/app_icons.dart';
import 'package:knx_monitor/ui/common.dart';
import 'package:knx_monitor/ui/communication_map_screen.dart';
import 'package:knx_monitor/ui/object_board.dart';
import 'package:knx_monitor/ui/value_board.dart';

/// Rundgang durch alle Ansichten am echten Gateway, mit Screenshots
/// (build/tour/). Aufruf (Gerät = Geräte-Id, App bleibt installiert):
///   flutter drive --profile --keep-app-running --driver=test_driver/integration_test.dart \
///     --target=integration_test/tour_test.dart -d GERÄT
///
/// Stellt am Ende Sprache und Expertenmodus wieder her.
/// Ohne Verbindung zu Flutter auf dem Mac (z. B. iOS-Beta): Screenshots in der
/// App ablegen (Application Support/tour/) und per devicectl abholen.
/// Bauen mit `flutter build ios --profile -t integration_test/tour_test.dart --dart-define=TOUR_LOCAL=true`.
const _local = bool.fromEnvironment('TOUR_LOCAL');

Future<List<int>> _render(WidgetTester tester) async {
  final view = tester.binding.renderViews.first;
  // debugLayer ist im Profil-Build null – direkt die Ebene der RenderView nehmen.
  // ignore: invalid_use_of_protected_member
  final layer = view.layer! as OffsetLayer;
  // Die Wurzelebene skaliert bereits um den Pixelfaktor: Bereich in Pixeln, Faktor 1.
  final image = await layer.toImage(Offset.zero & view.flutterView.physicalSize, pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

Future<void> _saveLocal(WidgetTester tester, String name) async {
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/tour')..createSync(recursive: true);
  File('${dir.path}/$name.png').writeAsBytesSync(await _render(tester));
}

/// Bild selbst rendern und wie `takeScreenshot` an den Treiber geben (der
/// schreibt build/tour/). `takeScreenshot` kann macOS nicht und lieferte im
/// iOS-Simulator zeitweise nur den Startbildschirm; Android müsste dafür erst
/// die Oberfläche umstellen.
Future<void> _reportShot(IntegrationTestWidgetsFlutterBinding binding, WidgetTester tester, String name) async {
  final data = binding.reportData ??= <String, dynamic>{};
  ((data['screenshots'] ??= <dynamic>[]) as List<dynamic>).add(<String, dynamic>{
    'screenshotName': name,
    'bytes': await _render(tester),
  });
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Rundgang', (tester) async {
    var n = 0;
    final log = <String>[];
    Future<void> wait(int ms) async {
      await Future<void>.delayed(Duration(milliseconds: ms));
      await tester.pump();
    }

    Future<void> shot(String name) async {
      await tester.pump();
      n++;
      final file = '${n.toString().padLeft(2, '0')}_$name';
      if (_local) {
        await _saveLocal(tester, file);
      } else {
        await _reportShot(binding, tester, file);
      }
    }

    Future<bool> tapFinder(Finder f, String what, {int wait_ = 900}) async {
      if (f.evaluate().isEmpty) {
        log.add('FEHLT: $what');
        return false;
      }
      // Außerhalb des Bildschirms gebaute Elemente erst einblenden (Telefon).
      try {
        await tester.ensureVisible(f.first);
        await wait(300);
      } on Object {
        // nicht scrollbar – direkt tippen
      }
      await tester.tap(f.first);
      await wait(wait_);
      return true;
    }

    Future<bool> tapText(String text, {int wait_ = 900}) => tapFinder(find.text(text), 'Text „$text“', wait_: wait_);
    Future<bool> tapTooltip(String text) => tapFinder(find.byTooltip(text), 'Tooltip „$text“', wait_: 700);

    /// Reiter: am Telefon nur Symbol mit Tooltip, sonst mit Text.
    Future<bool> tapTab(String label, {int wait_ = 1500}) => find.text(label).evaluate().isNotEmpty
        ? tapText(label, wait_: wait_)
        : tapFinder(find.byTooltip(label), 'Reiter „$label“', wait_: wait_);

    /// Zurück wie die Systemgeste (respektiert PopScope); schließt auch Blätter.
    Future<void> back() async {
      await tester.state<NavigatorState>(find.byType(Navigator).last).maybePop();
      await wait(900);
    }

    /// Monitor sichtbar: sein Filterfeld (Reiter fehlen am Mac, und die
    /// Seitenleiste steht am Tablet auch neben den Werkzeugseiten).
    bool onMonitor() => find
        .byWidgetPredicate(
          (w) => w is TextField && [s.filterHint, s.filterHintProject].contains(w.decoration?.hintText),
        )
        .hitTestable()
        .evaluate()
        .isNotEmpty;

    /// Menü öffnen – am Tablet steht es in der Seitenleiste (ggf. einblenden).
    Future<void> openMenu() async {
      if (find.byTooltip(s.menuTitle).evaluate().isNotEmpty) {
        await tapTooltip(s.menuTitle);
      } else if (find.byTooltip(s.sidebarShow).evaluate().isNotEmpty) {
        await tapTooltip(s.sidebarShow);
      }
    }

    /// Zurück bis zum Monitor.
    Future<void> toMonitor() async {
      for (var i = 0; i < 4 && !onMonitor(); i++) {
        await back();
      }
    }

    Future<void> scroll(double dy) async {
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      await tester.dragFrom(Offset(size.width * 0.45, size.height * 0.7), Offset(0, -dy));
      await wait(800);
    }

    /// Opens a tool from the menu. A [required] one that cannot be reached fails the walk-through;
    /// otherwise it is only logged (pages that depend on platform or tier).
    Future<bool> openTool(String title, {bool required = true}) async {
      await toMonitor();
      await openMenu();
      // Telefon: Liste ist länger als der Bildschirm – erst hinscrollen.
      // Seitenleiste am Tablet bleibt gescrollt: erst nach oben, dann nach unten suchen.
      // Welche Liste die Seitenleiste ist, hängt vom Layout ab (Telefon:
      // Menüseite, Tablet quer: neben dem Inhalt) – alle der Reihe nach probieren.
      // Lists that can be hit first: dragging one hidden behind another only fills the log with
      // warnings; they still come last, in case the title is only there.
      bool reachable(Element list) => find.byElementPredicate((e) => e == list).hitTestable().evaluate().isNotEmpty;
      final all = find.byType(Scrollable).evaluate().toList().reversed;
      final lists = [...all.where(reachable), ...all.where((l) => !reachable(l))];
      outer:
      for (final list in lists) {
        for (final step in [-300.0, 300.0]) {
          if (find.text(title).hitTestable().evaluate().isNotEmpty) break outer;
          try {
            await tester.scrollUntilVisible(
              find.text(title),
              step,
              scrollable: find.byElementPredicate((e) => e == list),
              maxScrolls: 15,
            );
          } on Object {
            // in dieser Liste bzw. Richtung nicht gefunden
          }
        }
      }
      if (find.text(title).evaluate().isEmpty) {
        log.add('${required ? 'NICHT ERREICHT' : 'FEHLT: Werkzeug'}: $title');
        return false;
      }
      return tapText(title, wait_: 1500);
    }

    Future<void> waitWhileCancel({int seconds = 90}) async {
      for (var i = 0; i < seconds && find.text(s.commonCancel).evaluate().isNotEmpty; i++) {
        await wait(1000);
      }
      await wait(800);
    }

    Future<void> connect() async {
      // Das Gateway-Feld an seinem Platzhalter: Es ist nicht mehr das erste Feld der Seite, seit
      // die Verbindungsart (mit Tunneladresse) davor steht.
      final host = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == '192.168.1.10');
      if ((tester.widget<TextField>(host).controller?.text ?? '').isEmpty) {
        // enterText erreicht auf dem Gerät die Texteingabe nicht – Controller direkt setzen.
        tester.widget<TextField>(host).controller!.text = const String.fromEnvironment(
          'GATEWAY',
          defaultValue: '192.168.1.22',
        );
        await wait(300);
      }
      await tapText(s.connectButton, wait_: 50);
    }

    // Ladezeiten in ms (ab runApp, also ohne Start der Engine).
    final times = <String>[];
    final clock = Stopwatch()..start();
    runApp(const KnxMonitorApp());
    // Simulator und langsame Geräte brauchen im Debug länger bis zum Verbinden-Bildschirm.
    for (var i = 0; i < 330 && find.byType(TextFormField).evaluate().isEmpty; i++) {
      await wait(100);
    }
    times.add('Verbinden-Bildschirm ${clock.elapsedMilliseconds}');
    await wait(3000);
    // Erst nach dem Laden der Einstellungen merken, sonst gilt der Vorgabewert.
    final wasExpert = ExpertMode.instance.value;
    final wasLocale = LocaleController.instance.locale;
    // Topologie, Karte, Abgleich, Diagnose, Inbetriebnahme und Busmonitor
    // gibt es nur im Expertenmodus – für den ganzen Rundgang einschalten.
    await ExpertMode.instance.set(true);
    await wait(500);
    await shot('verbinden');

    // --- Verbinden: schnelle Bildfolge, um Übergangsartefakte zu sehen ---------
    clock.reset();
    await connect();
    for (var i = 0; i < 40 && !onMonitor(); i++) {
      await wait(100);
    }
    if (onMonitor()) times.add('Verbinden bis Monitor ${clock.elapsedMilliseconds}');
    // Belegte Tunnel (z. B. von einer gerade beendeten Sitzung) gibt das
    // Gateway erst nach ~2 min frei – so lange erneut versuchen.
    for (var attempt = 0; attempt < 6 && !onMonitor(); attempt++) {
      await wait(4000);
      if (onMonitor()) break;
      await wait(26000);
      // Langsame Geräte verbinden erst nach mehr als 4 s – dann nicht erneut.
      if (onMonitor()) break;
      log.add('Verbinden: neuer Versuch ${attempt + 1}');
      await connect();
    }
    for (var i = 0; i < 6; i++) {
      await shot('verbinden_folge_$i');
      await wait(150);
    }
    // Ohne Verbindung gibt es keinen Rundgang: Am 10.11.2026 meldete der Test „bestanden“,
    // obwohl das Gateway keinen freien Tunnel hatte und 30 Ansichten nie erreicht wurden.
    expect(
      onMonitor(),
      isTrue,
      reason: 'Nicht verbunden (Screenshot verbinden_folge_5): Gateway erreichbar, Tunnel frei?',
    );
    await wait(20000); // Telegramme sammeln
    await shot('uebersicht');
    for (var i = 0; i < 3; i++) {
      await scroll(700);
      await shot('uebersicht_scroll_$i');
    }
    await scroll(-5000);

    for (final label in [s.activityLast60s, s.activityLastHour, s.activityToday]) {
      if (find.text(label).evaluate().isNotEmpty) {
        await tapText(label);
        await shot('zeitraum_nach_$label');
      }
    }

    // --- Karte → Details (zweispaltig am iPad) ----------------------------------
    if (await tapFinder(find.byType(ValueCard), 'Wertkarte', wait_: 1200)) {
      await shot('details');
      // Telefon: Details als Blatt → zurück; iPad: Detailspalte → Karte erneut antippen.
      if (find.byType(BottomSheet).evaluate().isNotEmpty) {
        await back();
      } else {
        await tapFinder(find.byType(ValueCard), 'Wertkarte (schließen)', wait_: 800);
      }
    }

    // --- Objekte → Objektdetail ----------------------------------------------------
    await tapTab(s.tabObjects);
    await shot('objekte');
    if (await tapFinder(find.byType(ObjectCard), 'Objektkarte', wait_: 1500)) {
      await shot('objekt_detail');
      await back();
    }

    await tapTab(s.tabLive);
    await shot('live');
    await tapTab(s.tabOverview);

    // --- Werkzeuge ------------------------------------------------------------------
    await openTool(s.statsTitle);
    await shot('statistik');

    await openTool(s.topoTitle);
    await shot('topologie');
    // Only the fold's head: the metric strip above carries the same word. Phone and tablet fold
    // the devices of a line; from 1200 pt (Mac, iPad landscape) they stand in the tree by
    // distribution board and sensors, without a fold, and a device opens beside the lines.
    final devicesHead = find.descendant(of: find.byType(SectionTitle), matching: find.textContaining(s.topoDevices));
    final folded = devicesHead.evaluate().isNotEmpty;
    if (!folded || await tapFinder(devicesHead, 'Geräteliste aufklappen')) {
      await shot('topologie_geraete');
      if (await tapFinder(find.textContaining('1.1.1').hitTestable(), 'Gerät 1.1.x', wait_: 1500)) {
        await shot('geraetefenster');
        // Back closes the sheet, or the details beside the lines first (wide).
        await back();
      }
    }

    await openTool(s.mapTitle);
    await shot('karte_uebersicht');
    // Nur in der Karte suchen – am Tablet hat auch die Seitenleiste Pfeile. Das Telefon zeigt eine
    // Liste mit Pfeilen; ab 600 pt die Gerätekarte, deren Knoten (Gerät 1.1.x) sich antippen lassen.
    final map = find.byType(CommunicationMapScreen);
    final arrows = find.descendant(of: map, matching: find.byIcon(AppIcons.next));
    final mapEntry = arrows.evaluate().isNotEmpty
        ? arrows
        : find.descendant(of: map, matching: find.textContaining(RegExp(r'^\d+\.\d+\.\d+$'))).hitTestable();
    if (await tapFinder(mapEntry, 'Karten-Eintrag', wait_: 1200)) {
      await shot('karte_knoten');
      await back();
      await shot('karte_zurueck');
    }

    await openTool(s.checkTitle);
    await wait(1500);
    await shot('projekt_abgleich');

    await openTool(s.recordingsTitle);
    await shot('aufnahmen');

    await openTool(s.diagnosticsTitle);
    await shot('diagnose');

    // Gesundheit: echter Lauf.
    await openTool(s.healthTitle);
    await shot('gesundheit_start');
    // Ohne Adressen zum Lesen bietet Gesundheit nur „Nur auswerten“ an.
    final runNow = find.textContaining(s.healthRunNow(0).split('(').first.trim());
    if (await tapFinder(runNow.evaluate().isEmpty ? find.text(s.healthPassive) : runNow, 'Gesundheit starten')) {
      await shot('gesundheit_laeuft');
      await waitWhileCancel();
      await shot('gesundheit_ergebnis');
      await scroll(900);
      await shot('gesundheit_ergebnis_scroll');
    }

    // Inbetriebnahme: Checkliste anlegen und lesen (nur wenn noch keine existiert).
    await openTool(s.commTitle);
    final hadChecklist = Commissioning.instance.items.isNotEmpty;
    await shot('inbetriebnahme_start');
    if (!hadChecklist &&
        await tapFinder(find.textContaining(s.commStart(0).split('0').first.trim()), 'Checkliste anlegen')) {
      await waitWhileCancel();
      await shot('inbetriebnahme_ergebnis');
      if (await tapFinder(find.byIcon(AppIcons.next), 'Prüfpunkt', wait_: 1000)) {
        await shot('inbetriebnahme_punkt');
        await back();
      }
      await scroll(800);
      await shot('inbetriebnahme_scroll');
    }

    // Pages rebuilt for wide windows in November 2026: each once, only looked at. A page behind
    // the paywall shows "Plus und Pro" instead, which is one of the rebuilt pages too.
    for (final (title, name) in [
      (s.reactTitle, 'reaktionszeiten'),
      (s.loadTitle, 'strom_last'),
      (s.watchTitle, 'waechter'),
      (s.customerTitle, 'kundenakte'),
      (s.handoverTitle, 'uebergabepaket'),
      (s.siteDocsTitle, 'fotodoku'),
      (s.annotationsTitle, 'kommentare'),
      (s.companyTitle, 'firma'),
      (s.learnTitle, 'anlernen'),
      (s.exportsTitle, 'exporte'),
      (s.lessonsTitle, 'knx_lernen'),
    ]) {
      if (await openTool(title, required: false)) await shot('breit_$name');
    }

    // Busmonitor zuletzt (übernimmt kurz den Tunnel).
    await openTool(s.busmonTitle);
    await wait(8000);
    await shot('busmonitor');
    await toMonitor();
    await wait(6000);
    await shot('nach_busmonitor');

    // --- Expertenmodus ----------------------------------------------------------------
    await ExpertMode.instance.set(true);
    await wait(800);
    await shot('experte');
    await tapTab(s.tabLive);
    await shot('experte_live');
    await tapTab(s.tabOverview);
    await ExpertMode.instance.set(wasExpert);
    await wait(500);

    // --- Englisch: zurück zum Verbinden, umstellen, neu verbinden -------------------------
    // Monitor → Verbinden; die Rückfrage „Verbindung trennen?“ bestätigen.
    Future<void> disconnect() async {
      await toMonitor();
      await back();
      // Mac and tablet: the monitor is the root there, "back" does nothing. Disconnect from the
      // sidebar instead (since the walk-through of 10 Nov 2026 the English part was skipped).
      if (find.text(s.monitorLeaveTitle).evaluate().isEmpty && onMonitor()) {
        await openTool(s.monitorDisconnect, required: false);
      }
      // „Trennen“ steht auch in der Seitenleiste – die liegt aber hinter dem
      // Dialog (adaptiv: auf iOS kein Material-Dialog).
      if (find.text(s.monitorLeaveTitle).evaluate().isNotEmpty) {
        await tapFinder(find.text(s.monitorDisconnect).hitTestable(), 'Trennen bestätigen');
      }
      await wait(1500);
    }

    await disconnect();
    Future<void> toLanguage() async {
      try {
        await tester.scrollUntilVisible(find.text('English'), 300, scrollable: find.byType(Scrollable).first);
      } on Object {
        // passt ohne Scrollen auf den Bildschirm
      }
    }

    await toLanguage();
    if (await tapText('English', wait_: 1200)) {
      await shot('english_connect');
      await connect();
      await wait(8000);
      await shot('english_overview');
      await openMenu();
      await shot('english_tools');
      await toMonitor();
      await disconnect();
      await toLanguage();
      await tapText(wasLocale.languageCode == 'de' ? 'Deutsch' : 'English', wait_: 800);
      await shot('zurueck_deutsch');
    } else {
      log.add('NICHT ERREICHT: Sprachwechsel auf dem Verbinden-Bildschirm');
    }

    if (_local) await AppStorage.instance.write('tour/log.txt', log.isEmpty ? 'alles gefunden' : log.join('\n'));
    // Sprache und Expertenmodus in jedem Fall zurückstellen (auch wenn ein Schritt fehlschlug).
    await LocaleController.instance.setLocale(wasLocale);
    await ExpertMode.instance.set(wasExpert);
    // ignore: avoid_print
    print('TOUR-LOG: ${log.isEmpty ? 'alles gefunden' : log.join(' | ')}');
    // Eine ganze Ansicht, die nicht aufging, ist ein Fehler; ein einzelner Knopf darin
    // („FEHLT“) bleibt ein Hinweis im Protokoll, weil er vom Projekt abhängen kann.
    expect(log.where((l) => l.startsWith('NICHT ERREICHT')), isEmpty);
    // ignore: avoid_print
    print('TOUR-ZEIT: ${times.join(' | ')}');
  });
}
