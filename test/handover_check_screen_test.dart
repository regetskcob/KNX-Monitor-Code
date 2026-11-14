import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/handover_check.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:knx_monitor/ui/handover_check_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'window.dart';

void main() {
  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('knx_handover_check');
    AppStorage.instance = IoStorage(dir);
    HandoverCheckStore.instance.debugReset();
    await CatalogStore.instance.reload();
  });

  tearDown(() async => dir.delete(recursive: true));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('Projekt wird erkannt, alter Stand fällt auf, Haken bleiben; Telefon und breit', (tester) async {
    final device = parseIndividual('1.1.10')!;
    GroupInfo g(int n) => GroupInfo(
      address: parseGroup('1/0/$n')!,
      name: 'Licht $n',
      dpt: const Dpt(1, 1),
      links: [GroupLink(device: device)],
    );
    await tester.runAsync(
      () => CatalogStore.instance.adopt(
        GroupCatalog(
          {for (var n = 1; n <= 30; n++) parseGroup('1/0/$n')!: g(n)},
          devices: {device: DeviceInfo(address: device, name: 'Schaltaktor')},
        ),
        name: 'haus.knxproj',
      ),
    );
    // 30 bekannte Adressen senden, dazu zwei, die das Projekt nicht kennt.
    final log = TelegramLog()
      ..addAll([
        for (final a in [for (var n = 1; n <= 30; n++) '1/0/$n', '5/0/1', '5/0/2'])
          Telegram(
            time: DateTime(2026, 11, 13),
            source: device,
            destination: parseGroup(a)!,
            type: TelegramType.write,
            data: Uint8List.fromList([1]),
            isSmall: true,
          ),
      ]);
    // In der App angelernt: gehört nicht zur übergebenen Datei, zählt also weiter als fehlend.
    await tester.runAsync(
      () => CatalogStore.instance.learn([GroupInfo(address: parseGroup('5/0/1')!, name: 'Angelernt')]),
    );
    final screen = HandoverCheckScreen(log: log);
    await pumpWindow(tester, screen, const Size(375, 6000));
    await settle(tester);
    expect(find.text('Von der App erkannt'), findsOneWidget, reason: 'die Projektdatei');
    expect(find.textContaining('2 Adressen senden auf dem Bus'), findsOneWidget);
    expect(find.text('1/9'), findsOneWidget);
    expect(find.text('Nachricht für 8 offene Punkte'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Trifft nicht zu').at(2));
    await settle(tester);
    expect(find.text('2/9'), findsOneWidget);
    expect(HandoverCheckStore.instance.check.states[HandoverItem.keyring], HandoverState.notNeeded);

    await pumpWindow(tester, screen, const Size(375, 6000), textScale: 2);
    await pumpWindow(tester, screen, wideWindow);
    await settle(tester);
    expect(find.text('2/9'), findsOneWidget, reason: 'gespeichert');
    await tester.pumpWidget(const SizedBox());
  });
}
