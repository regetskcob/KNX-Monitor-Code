import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/main.dart';
import 'package:knx_monitor/model/annotation.dart';
import 'package:knx_monitor/model/expert_mode.dart';
import 'package:knx_monitor/ui/telegram_row.dart';

/// Kurzer Rundgang durch Kommentare, Fehler melden und Zeitleiste am echten
/// Gateway, nur lesend: keine Leseanfragen, kein Schreiben auf den Bus.
/// Angelegte Kommentare werden am Ende wieder gelöscht.
///   flutter drive --profile --keep-app-running --driver=test_driver/integration_test.dart \
///     --target=integration_test/annotation_tour_test.dart -d GERÄT
Future<List<int>> _render(WidgetTester tester) async {
  final view = tester.binding.renderViews.first;
  // ignore: invalid_use_of_protected_member
  final layer = view.layer! as OffsetLayer;
  final image = await layer.toImage(Offset.zero & view.flutterView.physicalSize, pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Kommentare', (tester) async {
    var n = 0;
    final log = <String>[];
    Future<void> wait(int ms) async {
      await Future<void>.delayed(Duration(milliseconds: ms));
      await tester.pump();
    }

    Future<void> shot(String name) async {
      await tester.pump();
      n++;
      final data = binding.reportData ??= <String, dynamic>{};
      ((data['screenshots'] ??= <dynamic>[]) as List<dynamic>).add(<String, dynamic>{
        'screenshotName': '${n.toString().padLeft(2, '0')}_$name',
        'bytes': await _render(tester),
      });
    }

    Future<bool> tapFinder(Finder f, String what, {int wait_ = 1000}) async {
      if (f.evaluate().isEmpty) {
        log.add('FEHLT: $what');
        return false;
      }
      try {
        await tester.ensureVisible(f.first);
        await wait(300);
      } on Object {
        // nicht scrollbar
      }
      await tester.tap(f.first, warnIfMissed: false);
      await wait(wait_);
      return true;
    }

    Future<bool> tapText(String text, {int wait_ = 1000}) => tapFinder(find.text(text), '„$text“', wait_: wait_);
    Future<bool> tapTab(String label) => find.text(label).evaluate().isNotEmpty
        ? tapText(label, wait_: 1500)
        : tapFinder(find.byTooltip(label), 'Reiter „$label“', wait_: 1500);

    Future<void> back() async {
      await tester.state<NavigatorState>(find.byType(Navigator).last).maybePop();
      await wait(1000);
    }

    bool onMonitor() => find
        .byWidgetPredicate(
          (w) => w is TextField && [s.filterHint, s.filterHintProject].contains(w.decoration?.hintText),
        )
        .hitTestable()
        .evaluate()
        .isNotEmpty;

    Future<void> toMonitor() async {
      for (var i = 0; i < 5 && !onMonitor(); i++) {
        await back();
      }
    }

    Future<void> openTool(String title) async {
      await toMonitor();
      if (find.byTooltip(s.menuTitle).evaluate().isNotEmpty) {
        await tapFinder(find.byTooltip(s.menuTitle), 'Menü', wait_: 700);
      } else if (find.byTooltip(s.sidebarShow).evaluate().isNotEmpty) {
        await tapFinder(find.byTooltip(s.sidebarShow), 'Seitenleiste', wait_: 700);
      }
      for (final step in [-300.0, 300.0]) {
        if (find.text(title).hitTestable().evaluate().isNotEmpty) break;
        try {
          await tester.scrollUntilVisible(find.text(title), step, scrollable: find.byType(Scrollable).last);
        } on Object {
          // in diese Richtung nicht gefunden
        }
      }
      await tapText(title, wait_: 1500);
    }

    /// Notiz im offenen Kommentardialog setzen (enterText wirkt auf Geräten nicht).
    Future<void> note(String text) async {
      final field = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == s.annotationNoteHint);
      if (field.evaluate().isEmpty) {
        log.add('FEHLT: Notizfeld');
        return;
      }
      tester.widget<TextField>(field.first).controller!.text = text;
      await wait(300);
    }

    runApp(const KnxMonitorApp());
    for (var i = 0; i < 40 && find.byType(TextFormField).evaluate().isEmpty; i++) {
      await wait(1000);
    }
    final wasExpert = ExpertMode.instance.value;
    final before = {for (final a in AnnotationStore.instance.all) a.id};
    await ExpertMode.instance.set(true);
    await wait(500);

    final host = find.byType(TextFormField).first;
    if ((tester.widget<TextFormField>(host).controller?.text ?? '').isEmpty) {
      tester.widget<TextFormField>(host).controller!.text = '192.168.1.22';
      await wait(300);
    }
    // Belegte Tunnel gibt das Gateway erst nach etwa 2 min frei – so lange erneut versuchen.
    for (var attempt = 0; attempt < 6 && !onMonitor(); attempt++) {
      await tapText(s.connectButton, wait_: 50);
      for (var i = 0; i < 30 && !onMonitor(); i++) {
        await wait(1000);
      }
      if (!onMonitor()) log.add('Verbinden: Versuch ${attempt + 1} ohne Erfolg');
    }
    await wait(15000); // Telegramme sammeln

    // --- Telegramm kommentieren ---------------------------------------------------------
    await tapTab(s.tabLive);
    await shot('live');
    if (await tapFinder(find.byType(TelegramRow), 'Telegrammzeile', wait_: 1500)) {
      await shot('telegramm_details');
      if (await tapText(s.annotationAdd, wait_: 1200)) {
        await shot('kommentieren');
        // Abfrage „Nur kommentieren / Auch aufnehmen“, falls angeboten.
        if (find.text(s.annotationChoiceOnly).evaluate().isNotEmpty) {
          await tapText(s.annotationChoiceOnly, wait_: 1200);
        }
        await note('Testlauf: Kommentar am Telegramm');
        await shot('kommentar_dialog');
        await tapText(s.commonSave, wait_: 1500);
        await shot('kommentar_gespeichert');
      }
      await back();
    }
    await wait(1500);
    await shot('live_mit_faehnchen');

    // --- Fehler melden -------------------------------------------------------------------
    await openTool(s.reportTitle);
    await shot('fehler_melden_start');
    if (await tapText(s.reportStart, wait_: 4000)) {
      await tapText(s.reportNow, wait_: 3000);
      await tapText(s.reportNow, wait_: 1500);
      await shot('fehler_melden_marken');
      if (await tapText(s.reportFinish, wait_: 3000)) {
        await shot('diagnosepaket');
        await wait(3000);
        await shot('diagnosepaket_spaeter');
        await back(); // Paket nicht teilen
      }
    }

    // --- Kommentare-Übersicht --------------------------------------------------------------
    await openTool(s.annotationsTitle);
    await shot('kommentare');

    // --- Aufnahmen → Zeitleiste ------------------------------------------------------------
    await openTool(s.recordingsTitle);
    await shot('aufnahmen');
    final rows = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_RecordingRow');
    if (await tapFinder(rows, 'Aufnahme', wait_: 2500)) {
      await shot('aufnahme');
      if (await tapFinder(find.byTooltip(s.timelineTitle), 'Zeitleiste', wait_: 2500)) {
        await shot('zeitleiste');
        await back();
      }
      if (await tapFinder(find.byTooltip(s.findingsTitle), 'Befund', wait_: 2500)) {
        await shot('befund');
        await back();
      }
    }
    await toMonitor();

    // --- Aufräumen: Kommentare dieses Laufs löschen -------------------------------------------
    for (final a in [...AnnotationStore.instance.all]) {
      if (!before.contains(a.id)) await AnnotationStore.instance.remove(a);
    }
    await ExpertMode.instance.set(wasExpert);
    // ignore: avoid_print
    print('TOUR-LOG: ${log.isEmpty ? 'alles gefunden' : log.join(' | ')}');
  });
}
