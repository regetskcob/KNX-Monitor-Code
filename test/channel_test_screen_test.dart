import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/active_tunnel.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/channel_test.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/model/write_notice.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:knx_monitor/ui/channel_test_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'window.dart';

final _aktor = parseIndividual('1.1.10')!;
int _ga(String s) => parseGroup(s)!;

/// Tunnel, der Schreibbefehle merkt und wie ein Aktor mit dem Status antwortet (Kanal B nicht).
class _FakeTunnel extends KnxTunnel {
  _FakeTunnel(this.log) : super('test') {
    state.value = TunnelState.connected;
  }

  final TelegramLog log;
  final sent = <(int, int)>[];

  /// Was der Bus auf einen Schreibbefehl meldet; `null` = keine Bestätigung.
  bool? ack = true;

  @override
  Future<bool?> write(int destination, {int? small, List<int> data = const []}) async {
    if (ack != true) return ack;
    sent.add((destination, small!));
    if (destination == _ga('1/0/1')) {
      log.add(
        Telegram(
          time: DateTime(2026, 11, 13, 12, 0, sent.length),
          source: _aktor,
          destination: _ga('1/4/1'),
          type: TelegramType.write,
          data: Uint8List.fromList([small]),
          isSmall: true,
        ),
      );
    }
    return true;
  }
}

void main() {
  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('knx_channel_test');
    AppStorage.instance = IoStorage(dir);
    ChannelTestStore.instance.debugReset();
    WriteNotice.instance.debugDismiss();
    GroupInfo g(String a, String name, String text, {bool sends = false}) => GroupInfo(
      address: _ga(a),
      name: name,
      dpt: const Dpt(1, 1),
      links: [GroupLink(device: _aktor, text: text, sends: sends)],
    );
    CatalogStore.instance.catalog = GroupCatalog(
      {
        for (final x in [
          g('1/0/1', 'Küche Decke Schalten', 'Kanal A – Schalten'),
          g('1/4/1', 'Küche Decke Status', 'Kanal A – Status', sends: true),
          g('1/0/2', 'Flur Schalten', 'Kanal B – Schalten'),
          g('1/4/2', 'Flur Status', 'Kanal B – Status', sends: true),
        ])
          x.address: x,
      },
      devices: {_aktor: DeviceInfo(address: _aktor, name: 'Schaltaktor UV')},
    );
  });

  tearDown(() async {
    activeTunnel.value = null;
    await dir.delete(recursive: true);
  });

  /// Wartet echte Zeit ab (Dateien) und den Ablauf der Rückmeldefrist.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('Einschalten, bewerten, ausschalten, nächster Kanal; fehlende Rückmeldung fällt auf', (tester) async {
    final log = TelegramLog();
    final tunnel = _FakeTunnel(log);
    activeTunnel.value = tunnel;
    await pumpWindow(tester, ChannelTestScreen(device: _aktor, log: log), const Size(800, 2000));
    await settle(tester);
    expect(find.text('0/2'), findsOneWidget);

    await tester.tap(find.text('Einschalten'));
    await settle(tester);
    expect(tunnel.sent, [(_ga('1/0/1'), 1)]);
    expect(find.text('Rückmeldung bestätigt'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Richtige Last'));
    await settle(tester);
    expect(tunnel.sent.last, (_ga('1/0/1'), 0), reason: 'wieder ausgeschaltet');
    expect(find.text('1/2'), findsOneWidget);

    // Kanal B: der Aktor meldet nichts zurück.
    await tester.tap(find.text('Einschalten'));
    await settle(tester);
    expect(find.text('Keine Rückmeldung'), findsWidgets);
    await tester.enterText(find.byType(TextField), 'Lampe im Bad geht an');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Falsche Last'));
    await settle(tester);
    expect(tunnel.sent.last, (_ga('1/0/2'), 0));
    expect(find.text('Alle Kanäle sind geprüft'), findsOneWidget);
    expect(find.textContaining('1 Kanal ist auffällig'), findsOneWidget);
    expect(find.textContaining('Lampe im Bad geht an'), findsOneWidget);

    // Gespeichert: ein neuer Bildschirm kennt die Ergebnisse.
    await pumpWindow(tester, ChannelTestScreen(device: _aktor, log: log), const Size(801, 2000));
    await settle(tester);
    expect(find.text('2/2'), findsOneWidget);
  });

  testWidgets('Verlassen mit eingeschaltetem Kanal schaltet ihn wieder aus', (tester) async {
    final log = TelegramLog();
    final tunnel = _FakeTunnel(log);
    activeTunnel.value = tunnel;
    await pumpWindow(tester, ChannelTestScreen(device: _aktor, log: log), const Size(800, 2000));
    await settle(tester);
    await tester.tap(find.text('Einschalten'));
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    expect(tunnel.sent, [(_ga('1/0/1'), 1), (_ga('1/0/1'), 0)]);
  });

  testWidgets('Bus bestätigt das Telegramm nicht: Kanal gilt nicht als eingeschaltet', (tester) async {
    final log = TelegramLog();
    final tunnel = _FakeTunnel(log)..ack = null;
    activeTunnel.value = tunnel;
    await pumpWindow(tester, ChannelTestScreen(device: _aktor, log: log), const Size(800, 2000));
    await settle(tester);
    await tester.tap(find.text('Einschalten'));
    await settle(tester);
    expect(find.textContaining('nicht gesendet'), findsOneWidget);
    expect(find.text('Was hat reagiert?'), findsNothing);
    expect(find.text('Einschalten'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    expect(tunnel.sent, isEmpty, reason: 'nichts eingeschaltet, also auch nichts auszuschalten');
  });
}
