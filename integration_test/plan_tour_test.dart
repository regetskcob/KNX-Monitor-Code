import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/main.dart';
import 'package:knx_monitor/model/expert_mode.dart';
import 'package:knx_monitor/model/plan.dart';
import 'package:knx_monitor/model/plan_source.dart';

/// Rundgang der Freischaltung am echten Gateway, nur lesend, Stufe Free:
///   flutter drive --keep-app-running --driver=test_driver/integration_test.dart \
///     --target=integration_test/plan_tour_test.dart -d GERÄT
/// Plaketten im Menü, gesperrtes Werkzeug → Bezahlseite (nur Pro), „Plus und
/// Pro“ auf dem Verbinden-Bildschirm. Ohne RevenueCat-Schlüssel ohne Preise.
class _FreeStore extends PlanSource {
  @override
  bool get purchasable => true;
  @override
  Future<Tier> current() async => Tier.free;
  @override
  Future<List<PlanOffer>> offers() async => const [];
  @override
  Future<Tier> buy(PlanOffer offer) async => Tier.free;
  @override
  Future<Tier> restore() async => Tier.free;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Freischaltung', (tester) async {
    PlanSource.forPlatform = _FreeStore.new;
    final log = <String>[];
    var n = 0;
    Future<void> wait(int ms) async {
      await Future<void>.delayed(Duration(milliseconds: ms));
      await tester.pump();
    }

    Future<void> shot(String name) async {
      await tester.pump();
      // Selbst rendern: takeScreenshot kann macOS nicht und liefert im iOS-Simulator
      // nur den Startbildschirm (siehe tour_test.dart).
      final view = tester.binding.renderViews.first;
      // ignore: invalid_use_of_protected_member
      final layer = view.layer! as OffsetLayer;
      final image = await layer.toImage(Offset.zero & view.flutterView.physicalSize, pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final data = binding.reportData ??= <String, dynamic>{};
      ((data['screenshots'] ??= <dynamic>[]) as List<dynamic>).add(<String, dynamic>{
        'screenshotName': 'plan_${(++n).toString().padLeft(2, '0')}_$name',
        'bytes': bytes!.buffer.asUint8List(),
      });
    }

    void check(bool ok, String what) => ok ? null : log.add('FEHLT: $what');

    runApp(const KnxMonitorApp());
    for (var i = 0; i < 40 && find.byType(TextFormField).evaluate().isEmpty; i++) {
      await wait(1000);
    }
    await Plan.instance.refreshing;
    final wasExpert = ExpertMode.instance.value;
    await ExpertMode.instance.set(true);
    await wait(800);
    check(find.text(s.planTitle).evaluate().isNotEmpty, '„Plus und Pro“ auf dem Verbinden-Bildschirm');
    await tester.scrollUntilVisible(find.text(s.planTitle).first, 300, scrollable: find.byType(Scrollable).first);
    await shot('verbinden');
    await tester.tap(find.text(s.planTitle).first);
    await wait(1200);
    await shot('bezahlseite_menue');
    // Kennungen stehen in Versalien.
    bool shows(String tier) =>
        find.text(tier).evaluate().isNotEmpty || find.text(tier.toUpperCase()).evaluate().isNotEmpty;
    check(shows('Pro') && shows('Plus'), 'beide Stufen ohne Anlass');
    await tester.state<NavigatorState>(find.byType(Navigator).last).maybePop();
    await wait(900);

    // Verbinden; ohne Installation mit Adresse (frischer Simulator) das Gateway eintragen.
    final host = find.byType(TextFormField).first;
    if ((tester.widget<TextFormField>(host).controller?.text ?? '').isEmpty) {
      tester.widget<TextFormField>(host).controller!.text = const String.fromEnvironment(
        'GATEWAY',
        defaultValue: '192.168.1.22',
      );
      await wait(300);
    }
    await tester.tap(find.text(s.connectButton));
    for (
      var i = 0;
      i < 30 && find.byTooltip(s.menuTitle).evaluate().isEmpty && find.text(s.diagnosticsTitle).evaluate().isEmpty;
      i++
    ) {
      await wait(1000);
    }
    await wait(4000);
    if (find.byTooltip(s.menuTitle).evaluate().isNotEmpty || find.text(s.diagnosticsTitle).evaluate().isNotEmpty) {
      // Auf breiten Bildschirmen steht das Menü schon offen in der Seitenleiste.
      if (find.byTooltip(s.menuTitle).evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip(s.menuTitle));
        await wait(1200);
      }
      await shot('menue_free');
      check(shows('Pro'), 'Plakette PRO im Menü');
      await tester.tap(find.text(s.diagnosticsTitle));
      await wait(1500);
      await shot('diagnose_gesperrt');
      check(find.textContaining(s.diagnosticsTitle).evaluate().isNotEmpty, 'Grund auf der Bezahlseite');
      check(!shows('Plus'), 'bei Pro-Funktion nur Pro');
    } else {
      log.add('FEHLT: Monitor (Verbindung)');
    }

    await ExpertMode.instance.set(wasExpert);
    // ignore: avoid_print
    print('PLAN-LOG: ${log.isEmpty ? 'alles gefunden' : log.join(' | ')}');
  });
}
