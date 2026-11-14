import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/model/value_snapshot.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:knx_monitor/ui/snapshot_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'window.dart';

final _t0 = DateTime(2026, 11, 14, 8);

Telegram _bit(int minutes, String dest, int value, {String source = '1.1.10'}) => Telegram(
  time: _t0.add(Duration(minutes: minutes)),
  source: parseIndividual(source)!,
  destination: parseGroup(dest)!,
  type: TelegramType.write,
  data: Uint8List.fromList([value]),
  isSmall: true,
);

void main() {
  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('knx_snapshot');
    AppStorage.instance = IoStorage(dir);
    ValueSnapshotStore.instance.debugReset();
    SnapshotScreen.clock = () => _t0.add(const Duration(minutes: 5));
    GroupInfo g(String a, String name) => GroupInfo(address: parseGroup(a)!, name: name, dpt: const Dpt(1, 1));
    CatalogStore.instance.catalog = GroupCatalog(
      {
        for (final x in [g('1/4/1', 'Küche Decke Status'), g('1/4/3', 'Bad Spiegel Status')]) x.address: x,
      },
      devices: {parseIndividual('1.1.11')!: DeviceInfo(address: parseIndividual('1.1.11')!, name: 'Schaltaktor Bad')},
    );
  });

  tearDown(() async {
    SnapshotScreen.clock = DateTime.now;
    await dir.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('Stand festhalten, danach: Geändertes mit vorher/jetzt, stummes Gerät mit Namen', (tester) async {
    final log = TelegramLog()..addAll([_bit(0, '1/4/1', 1), _bit(0, '1/4/3', 1, source: '1.1.11')]);
    await pumpWindow(tester, SnapshotScreen(log: log), const Size(375, 2000));
    await settle(tester);
    await tester.tap(find.text('Stand festhalten (2 Werte)'));
    await settle(tester);
    expect(find.textContaining('Stand von 08:05 mit 2 Werten'), findsOneWidget);

    log.add(_bit(30, '1/4/1', 0));
    await tester.pump(const Duration(seconds: 4));
    expect(find.textContaining('vorher Ein · jetzt Aus'), findsOneWidget);
    expect(find.textContaining('Schaltaktor Bad'), findsOneWidget);

    await pumpWindow(tester, SnapshotScreen(log: log), const Size(375, 2000), textScale: 2);
    await pumpWindow(tester, SnapshotScreen(log: log), wideWindow);
    await tester.pumpWidget(const SizedBox());
  });
}
