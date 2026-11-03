import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/main.dart';
import 'package:knx_monitor/model/expert_mode.dart';
import 'package:knx_monitor/ui/more_menu.dart';
import 'package:knx_monitor/ui/object_board.dart';
import 'package:knx_monitor/ui/telegram_row.dart';
import 'package:knx_monitor/ui/value_board.dart';
import 'package:knx_monitor/ui/weekly_report_screen.dart';

/// Querverknüpfungen und Ladezeiten am echten Gateway, mit Screenshots
/// (build/tour/). Sendet nichts auf den Bus und liest nicht aktiv.
///   flutter drive --profile --keep-app-running --driver=test_driver/integration_test.dart \
///     --target=integration_test/links_test.dart -d GERÄT
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

  testWidgets('Querverknüpfungen', (tester) async {
    var n = 0;
    final results = <String>[];
    final times = <String>[];

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

    Future<void> back() async {
      await tester.state<NavigatorState>(find.byType(Navigator).last).maybePop();
      await wait(700);
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

    /// Ein Weg: läuft er durch, steht OK im Protokoll, sonst der Fehler.
    Future<void> way(String name, Future<void> Function() run) async {
      try {
        await run();
        results.add('OK $name');
      } on Object catch (e) {
        results.add('FEHLER $name: ${e.toString().split('\n').first}');
      }
      await toMonitor();
    }

    void expectFound(Finder f, String what) {
      if (f.evaluate().isEmpty) throw StateError('nicht gefunden: $what');
    }

    Future<void> tap(Finder f, String what, {int after = 900}) async {
      expectFound(f, what);
      try {
        await tester.ensureVisible(f.first);
        await wait(200);
      } on Object {
        // nicht scrollbar
      }
      await tester.tap(f.first, warnIfMissed: false);
      await wait(after);
    }

    /// Zeit von [action] bis [ready] steht, dazu das längste Bild im Fenster
    /// danach: zeigt Ruckler, die eine reine Wartezeit nicht zeigt.
    Future<void> timed(String name, Future<void> Function() action, bool Function() ready) async {
      var worst = 0;
      void onTimings(List<ui.FrameTiming> all) {
        for (final t in all) {
          final ms = t.totalSpan.inMilliseconds;
          if (ms > worst) worst = ms;
        }
      }

      SchedulerBinding.instance.addTimingsCallback(onTimings);
      final clock = Stopwatch()..start();
      await action();
      var i = 0;
      while (!ready() && i++ < 400) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
      final elapsed = clock.elapsedMilliseconds;
      await wait(1200);
      SchedulerBinding.instance.removeTimingsCallback(onTimings);
      times.add('$name ${ready() ? elapsed : 'NIE'} ms, längstes Bild $worst ms');
    }

    runApp(const KnxMonitorApp());
    for (var i = 0; i < 330 && find.byType(TextFormField).evaluate().isEmpty; i++) {
      await wait(100);
    }
    await wait(3000);
    final wasExpert = ExpertMode.instance.value;
    await ExpertMode.instance.set(true);
    await wait(500);
    await tap(find.text(s.connectButton), 'Verbinden', after: 100);
    // Belegte Tunnel gibt das Gateway erst nach rund 2 Minuten frei: erneut versuchen.
    for (var attempt = 0; attempt < 8 && !onMonitor(); attempt++) {
      for (var i = 0; i < 300 && !onMonitor(); i++) {
        await wait(100);
      }
      if (!onMonitor() && find.text(s.connectButton).evaluate().isNotEmpty) {
        await tester.tap(find.text(s.connectButton).first);
      }
    }
    await wait(20000); // Telegramme sammeln
    await shot('monitor');

    final phone = MediaQuery.sizeOf(tester.element(find.byType(Navigator).first)).width < 600;

    // --- Ansichten ------------------------------------------------------------
    for (final (label, ready) in [
      (s.tabObjects, () => find.byType(ObjectCard).evaluate().isNotEmpty),
      (s.tabLive, () => find.byType(TelegramRow).evaluate().isNotEmpty),
      (s.tabOverview, () => find.byType(ValueCard).evaluate().isNotEmpty),
    ]) {
      // Am breiten Mac stehen Übersicht und Live nebeneinander, ohne Umschalter.
      if (find.text(label).evaluate().isEmpty) continue;
      await timed('Ansicht $label', () => tester.tap(find.text(label).first), ready);
    }

    // --- Werkzeuge: Wechsel über Seitenleiste bzw. Menü ------------------------
    final tools = [
      s.statsTitle,
      s.topoTitle,
      s.mapTitle,
      s.checkTitle,
      s.chartsTitle,
      s.recordingsTitle,
      s.diagnosticsTitle,
      s.healthTitle,
      s.commTitle,
      s.busmonTitle,
      s.ackTitle,
      s.watchTitle,
      s.secTitle,
      s.reactTitle,
      s.loadTitle,
      s.customerTitle,
      s.srTitle,
      s.handoverTitle,
      s.lessonsTitle,
      s.annotationsTitle,
      s.siteDocsTitle,
      s.manualTitle,
      s.companyTitle,
    ];
    Future<bool> reveal(String title) async {
      if (phone) {
        if (find.byTooltip(s.menuTitle).evaluate().isEmpty) await toMonitor();
        await tester.tap(find.byTooltip(s.menuTitle).first);
        await wait(500);
      }
      final inMenu = find.byType(MoreSidebar).evaluate().isNotEmpty
          ? find.descendant(of: find.byType(MoreSidebar).first, matching: find.text(title))
          : find.text(title);
      for (final list in find.byType(Scrollable).evaluate().toList().reversed) {
        for (final step in [-300.0, 300.0]) {
          if (inMenu.hitTestable().evaluate().isNotEmpty) return true;
          try {
            await tester.scrollUntilVisible(
              inMenu.hitTestable(),
              step,
              scrollable: find.byElementPredicate((e) => e == list),
              maxScrolls: 15,
            );
          } on Object {
            // weiter
          }
        }
      }
      return inMenu.hitTestable().evaluate().isNotEmpty;
    }

    for (final title in tools) {
      await way('Werkzeug $title', () async {
        if (!await reveal(title)) throw StateError('nicht im Menü');
        final item = find.byType(MoreSidebar).evaluate().isNotEmpty
            ? find.descendant(of: find.byType(MoreSidebar).first, matching: find.text(title))
            : find.text(title);
        await timed(
          'Werkzeug $title',
          () => tester.tap(item.hitTestable().first),
          () => find.widgetWithText(AppBar, title).evaluate().isNotEmpty,
        );
        await shot('werkzeug_$title');
      });
    }

    // Direkter Wechsel Werkzeug zu Werkzeug, wie mit der Seitenleiste am iPad.
    if (!phone) {
      await way('Werkzeug zu Werkzeug', () async {
        await reveal(s.statsTitle);
        for (final title in [s.statsTitle, s.topoTitle, s.healthTitle, s.busmonTitle, s.mapTitle, s.statsTitle]) {
          await reveal(title);
          final item = find.descendant(of: find.byType(MoreSidebar).first, matching: find.text(title));
          await timed(
            'Wechsel zu $title',
            () => tester.tap(item.hitTestable().first),
            () => find.widgetWithText(AppBar, title).evaluate().isNotEmpty,
          );
        }
      });
    }

    // --- Querverknüpfungen ------------------------------------------------------
    // Am iPad bleibt das Detailblatt neben der Übersicht stehen, und ein zweiter
    // Tipp auf dieselbe Karte schließt es: nur tippen, wenn es zu ist.
    Future<void> openDetails() async {
      if (find.text(s.detailsFilter).evaluate().isNotEmpty) return;
      await tap(find.byType(ValueCard), 'Wertkarte', after: 1200);
    }

    await way('Karte → Details', () async {
      await openDetails();
      await shot('details');
    });
    await way('Details → Gerät', () async {
      await openDetails();
      final sender = find.textContaining(RegExp(s.columnSender, caseSensitive: false));
      if (sender.hitTestable().evaluate().isEmpty) {
        await tester.scrollUntilVisible(sender, 300, scrollable: find.byType(Scrollable).last);
      }
      await tap(sender, 'Absender', after: 1000);
      await shot('details_absender');
    });
    await way('Details → Menü → Karte', () async {
      await openDetails();
      // Der Kopf des Blatts kann aus dem vorigen Weg weggescrollt sein.
      if (find.byTooltip(s.commonMore).evaluate().isEmpty) {
        await tester.scrollUntilVisible(find.byTooltip(s.commonMore), -300, scrollable: find.byType(Scrollable).last);
      }
      await tap(find.byTooltip(s.commonMore), 'Menü ⋯');
      await shot('details_menue');
      await tap(find.text(s.mapTitle).last, 'Karte');
      await shot('details_karte');
    });
    await way('Details → Filtern → Monitor', () async {
      await openDetails();
      await tap(find.text(s.detailsFilter).last, 'Filtern');
      await shot('details_gefiltert');
      if (find.text(s.detailsFilterOff).evaluate().isNotEmpty) {
        await tap(find.text(s.detailsFilterOff).last, 'Filter aus');
      }
      // Am Telefon schließt das Blatt beim Filtern: Filter im Feld leeren.
      final field = find.byWidgetPredicate((w) => w is TextField && w.controller?.text.isNotEmpty == true);
      if (field.evaluate().isNotEmpty) {
        await tester.enterText(field.first, '');
        await wait(500);
      }
    });
    await way('Live → Details', () async {
      final tabs = find.text(s.tabLive).evaluate().isNotEmpty;
      if (tabs) await tap(find.text(s.tabLive).first, 'Live');
      await tap(find.byType(TelegramRow), 'Zeile', after: 1200);
      await shot('live_details');
      // Am Telefon liegt das Blatt über den Reitern: erst schließen.
      if (phone) await back();
      if (tabs) await tester.tap(find.text(s.tabOverview).first, warnIfMissed: false);
      await wait(600);
    });
    await way('Objekt → Detail → Adresse', () async {
      await tap(find.text(s.tabObjects).first, 'Objekte');
      await tap(find.byType(ObjectCard), 'Objektkarte', after: 1200);
      await shot('objekt_detail');
      await back();
      await tester.tap(find.text(s.tabOverview).first, warnIfMissed: false);
      await wait(600);
    });
    await way('Gesundheit aus der Box → Wochenbericht → Prüfung', () async {
      await tap(find.byType(HealthStatusLine), 'Box');
      await shot('box_ziel');
    });
    await way('Statistik → Filter im Monitor', () async {
      await reveal(s.statsTitle);
      await tester.tap(find.text(s.statsTitle).hitTestable().first);
      await wait(1200);
      await tap(find.byType(InkWell).hitTestable().at(4), 'Zeile', after: 1200);
      await shot('statistik_filter');
    });
    await way('Topologie → Gerät', () async {
      await reveal(s.topoTitle);
      await tester.tap(find.text(s.topoTitle).hitTestable().first);
      await wait(1500);
      await tap(find.textContaining('1.1.').hitTestable(), 'Gerät', after: 1200);
      await shot('topologie_geraet');
    });
    await way('Karte → Gerät → alle Geräte', () async {
      await reveal(s.mapTitle);
      await tester.tap(find.text(s.mapTitle).hitTestable().first);
      await wait(1500);
      await shot('karte');
      // Am Telefon startet die Karte mit den Gruppenadressen.
      if (find.textContaining('1.1.').hitTestable().evaluate().isEmpty) {
        await tap(find.textContaining(' · ').last, 'Geräte');
      }
      await tap(find.textContaining('1.1.').hitTestable(), 'Gerät in der Karte', after: 1000);
      await shot('karte_auswahl');
    });

    // Tunnel freigeben: Das Gateway hat nur wenige, und die App bleibt nach dem Test offen.
    await toMonitor();
    await back();
    if (find.text(s.monitorDisconnect).evaluate().isNotEmpty) {
      await tester.tap(find.text(s.monitorDisconnect).last);
      await wait(1500);
    }
    await ExpertMode.instance.set(wasExpert);
    // ignore: avoid_print
    print('LINKS: ${results.join(' | ')}');
    // ignore: avoid_print
    print('ZEITEN: ${times.join(' | ')}');
  });
}
