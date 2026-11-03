import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/main.dart';
import 'package:knx_monitor/model/expert_mode.dart';
import 'package:knx_monitor/model/watch_rules.dart';

/// Wächter im Demo-Haus (kein Bus): Regel auf die Außenhelligkeit (4/0/2,
/// sendet oft), dann muss der Hinweis „Wächter: …“ mit Ton kommen.
///   flutter drive --driver=test_driver/integration_test.dart --target=integration_test/watch_test.dart -d GERÄT
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Wächter löst im Demo-Haus aus', (tester) async {
    Future<void> wait(int ms) async {
      await Future<void>.delayed(Duration(milliseconds: ms));
      await tester.pump();
    }

    runApp(const KnxMonitorApp());
    for (var i = 0; i < 40 && find.byType(TextFormField).evaluate().isEmpty; i++) {
      await wait(1000);
    }
    final wasExpert = ExpertMode.instance.value;
    await ExpertMode.instance.set(false); // „Demo ansehen“ steht ohne Expertenmodus
    await wait(800);
    const rule = WatchRule(id: 'test-demo', address: 0x2002); // 4/0/2
    await WatchRules.instance.add(rule);
    await tester.tap(find.text(s.connectDemoShort));
    var hit = false;
    for (var i = 0; i < 60 && !hit; i++) {
      await wait(500);
      hit = find.textContaining(s.watchHit('').trim()).evaluate().isNotEmpty;
    }
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
    }
    // macOS kennt keine Screenshots im integration_test.
    if (!Platform.isMacOS) await binding.takeScreenshot('watch_hit');
    await WatchRules.instance.remove(rule.id);
    await ExpertMode.instance.set(wasExpert);
    expect(hit, isTrue, reason: 'Hinweis „Wächter: 4/0/2 …“ erwartet (${formatGroup(rule.address)})');
  });
}
