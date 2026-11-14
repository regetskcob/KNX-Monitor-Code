import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/lock_prefs.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:knx_monitor/ui/locks_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'window.dart';

final _t0 = DateTime(2026, 11, 13, 14);
final _weather = parseIndividual('1.2.20')!;
final _button = parseIndividual('1.1.30')!;
final _blind = parseIndividual('1.1.12')!;
int _ga(String s) => parseGroup(s)!;

Telegram _bit(int minutes, String dest, int value, {int? source}) => Telegram(
  time: _t0.add(Duration(minutes: minutes)),
  source: source ?? _weather,
  destination: _ga(dest),
  type: TelegramType.write,
  data: Uint8List.fromList([value]),
  isSmall: true,
);

void main() {
  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('knx_locks');
    AppStorage.instance = IoStorage(dir);
    LockPrefs.instance.debugReset();
    LocksScreen.clock = () => _t0.add(const Duration(minutes: 90));
    CatalogStore.instance.catalog = GroupCatalog(
      {
        _ga('3/3/0'): GroupInfo(
          address: _ga('3/3/0'),
          name: 'Küche Rollladen Sperre',
          dpt: const Dpt(1, 1),
          links: [GroupLink(device: _blind, text: 'Kanal A – Sperren')],
        ),
        _ga('1/3/1'): GroupInfo(address: _ga('1/3/1'), name: 'Flur PM Sperre', dpt: const Dpt(1, 1)),
      },
      devices: {
        _weather: DeviceInfo(address: _weather, name: 'Wetterstation'),
        _button: DeviceInfo(address: _button, name: 'Taster Küche'),
        _blind: DeviceInfo(address: _blind, name: 'Jalousieaktor'),
      },
    );
  });

  tearDown(() async {
    LocksScreen.clock = DateTime.now;
    await dir.delete(recursive: true);
  });

  testWidgets('Jetzt gesperrt mit Wer und Seit, Verlauf mit Beginn, Ende, Dauer; Deutung umdrehen', (tester) async {
    final log = TelegramLog()
      ..addAll([
        _bit(0, '3/3/0', 1),
        _bit(29, '3/3/0', 0, source: _button),
        _bit(60, '3/3/0', 1),
        _bit(70, '1/3/1', 0),
      ]);
    final screen = LocksScreen(log: log);
    await pumpWindow(tester, screen, const Size(375, 2400));
    await tester.pump();
    // Läuft seit 15:00, also 30 min.
    expect(find.textContaining('seit 15:00 · gesperrt von Wetterstation'), findsOneWidget);
    expect(find.text('30 min'), findsOneWidget);
    expect(find.textContaining('wirkt auf Jalousieaktor'), findsOneWidget);
    expect(
      find.textContaining('14:00 – 14:29 · 29 min · gesperrt von Wetterstation · gelöst von Taster Küche'),
      findsOneWidget,
    );

    // „Flur PM Sperre“ sendet 0: frei. Umgedreht gilt die 0 als gesperrt.
    expect(find.textContaining('frei · 15:10 · 1 sperrt'), findsOneWidget);
    await tester.tap(find.byTooltip('Deutung umdrehen').last);
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('gesperrt · 15:10 · 0 sperrt'), findsOneWidget);
    expect(find.textContaining('seit 15:10'), findsOneWidget);

    await pumpWindow(tester, screen, const Size(375, 2400), textScale: 2);
    await pumpWindow(tester, screen, wideWindow);
    await tester.pumpWidget(const SizedBox());
  });
}
