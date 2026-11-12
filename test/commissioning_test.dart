import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/commissioning.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/commissioning_screen.dart';
import 'package:knx_monitor/ui/common.dart';
import 'package:knx_monitor/ui/device_sheet.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';

import 'fake_gateway.dart';

void main() {
  late FakeGateway gateway;
  late KnxTunnel tunnel;
  late Directory dir;
  final c = Commissioning.instance;
  final temp = parseGroup('2/0/0')!;
  final rm = parseGroup('1/4/0')!;
  final light = parseGroup('1/1/0')!;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('commissioning');
    AppStorage.instance = IoStorage(dir);
    c.debugReset();
    CatalogStore.instance.catalog = GroupCatalog({
      temp: GroupInfo(
        address: temp,
        name: 'EG FL Ist-Temperatur',
        path: 'Heizung › Ist-Temperatur',
        dpt: const Dpt(9, 1),
      ),
      rm: GroupInfo(address: rm, name: 'EG FL L01 Rückmeldung Schalten', path: 'Beleuchtung › Rückmeldung'),
      light: GroupInfo(address: light, name: 'EG FL L01 Schalten', path: 'Beleuchtung › Schalten'),
    });
    gateway = await FakeGateway.start();
    tunnel = KnxTunnel('127.0.0.1', port: gateway.port);
    await tunnel.connect();
  });

  tearDown(() async {
    await tunnel.disconnect();
    gateway.close();
    CatalogStore.instance.catalog = GroupCatalog.empty;
    await dir.delete(recursive: true);
  });

  test('Status-Adressen erkennen', () {
    final groups = CatalogStore.instance.catalog.groups;
    expect(isStatusGroup(groups[temp]!), isTrue);
    expect(isStatusGroup(groups[rm]!), isTrue);
    expect(isStatusGroup(groups[light]!), isFalse);
  });

  test('Lesen hakt Antworten ab, Stille wird „keine Antwort“, Handwerte bleiben', () async {
    gateway.responders[temp] = (parseIndividual('1.1.50')!, [0x0C, 0x24]);
    c.prepare([temp, rm, light]);
    c.mark(light, CheckState.ok); // vor Ort geprüft
    await c.read(tunnel, [temp, rm, light]);

    expect(c.items[temp]!.state, CheckState.answered);
    expect(c.items[temp]!.value, '21,2 °C');
    expect(c.items[temp]!.source, parseIndividual('1.1.50'));
    expect(c.items[rm]!.state, CheckState.noAnswer);
    expect(c.items[light]!.state, CheckState.ok); // nicht überschrieben
    expect(c.checked, 3);

    // Gespeichert und wieder geladen – inkl. Notiz.
    c.setNote(rm, 'Lese-Flag fehlt');
    // Gespeichert wird im Hintergrund – auf den Inhalt warten, nicht auf eine
    // feste Zeit (CI-Rechner sind langsamer).
    for (var i = 0; i < 100; i++) {
      if ((await AppStorage.instance.read('commissioning.json'))?.contains('Lese-Flag fehlt') ?? false) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    c.debugReset();
    c.debugAllowLoad();
    await c.load();
    expect(c.items[rm]!.note, 'Lese-Flag fehlt');
    expect(c.items[temp]!.value, '21,2 °C');
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets('Breit: Details rechts, Bewerten springt zum nächsten offenen Punkt', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    c.prepare([temp, rm]);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: CommissioningScreen(tunnel: tunnel),
      ),
    );
    await tester.pump();
    // Die Zeile, nicht der gleichlautende Abschnittstitel.
    await tester.tap(
      find.descendant(of: find.byType(AddressTitle), matching: find.textContaining('Ist-Temperatur')).first,
    );
    await tester.pump();
    expect(find.byKey(ValueKey(temp)), findsOneWidget);
    await tester.tap(find.text(s.commOk));
    await tester.pump();
    expect(c.items[temp]!.state, CheckState.ok);
    expect(find.byKey(ValueKey(rm)), findsOneWidget);
  });

  testWidgets('Absender in den Details öffnet das Geräteblatt', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    c.prepare([temp]);
    c.setRollCall(true);
    addTearDown(() => c.setRollCall(false));
    c.observe(
      Telegram(
        time: DateTime(2026, 11, 11, 14, 2),
        source: parseIndividual('1.1.50')!,
        destination: temp,
        type: TelegramType.write,
        data: Uint8List.fromList([0x0C, 0x24]),
        isSmall: false,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: CommissioningScreen(tunnel: tunnel, log: TelegramLog()),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.descendant(of: find.byType(AddressTitle), matching: find.textContaining('Ist-Temperatur')).first,
    );
    await tester.pump();
    final link = find.byType(DeviceLink);
    expect(link, findsOneWidget);
    expect(find.descendant(of: link, matching: find.textContaining('1.1.50')), findsOneWidget);
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.byType(DeviceTraffic), findsOneWidget);
    // Saving the observed item runs on a timer.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
