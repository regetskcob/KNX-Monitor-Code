import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/active_tunnel.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/channel_control.dart';
import 'package:knx_monitor/model/lock_prefs.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/model/write_notice.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:knx_monitor/ui/room_control_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'window.dart';

final _t0 = DateTime(2026, 11, 14, 9);
int _ga(String s) => parseGroup(s)!;

Telegram _bit(int seconds, String dest, int value, {TelegramType type = TelegramType.write}) => Telegram(
  time: _t0.add(Duration(seconds: seconds)),
  source: parseIndividual('1.1.10')!,
  destination: _ga(dest),
  type: type,
  data: Uint8List.fromList([value]),
  isSmall: true,
);

class _FakeTunnel extends KnxTunnel {
  _FakeTunnel(this.log) : super('test') {
    state.value = TunnelState.connected;
  }

  final TelegramLog log;
  final written = <(int, int)>[];
  final reads = <int>[];

  @override
  Future<bool?> write(int destination, {int? small, List<int> data = const []}) async {
    written.add((destination, small!));
    return true;
  }

  /// Nur die Küche antwortet auf Lesen.
  @override
  Future<bool?> read(int destination) async {
    reads.add(destination);
    if (destination == _ga('1/4/1')) log.add(_bit(100 + reads.length, '1/4/1', 0, type: TelegramType.response));
    return true;
  }
}

void main() {
  late Directory dir;

  /// Echte Zeit für Dateien (Sperr-Deutung) und die Fristen der Rückmeldungen.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('knx_rooms');
    AppStorage.instance = IoStorage(dir);
    LockPrefs.instance.debugReset();
    WriteNotice.instance.debugDismiss();
    GroupInfo g(String a, String name, Dpt dpt) => GroupInfo(address: _ga(a), name: name, dpt: dpt);
    CatalogStore.instance.catalog = GroupCatalog({
      for (final x in [
        g('1/0/1', 'Küche Decke Schalten', const Dpt(1, 1)),
        g('1/4/1', 'Küche Decke Status', const Dpt(1, 1)),
        g('1/0/2', 'Bad Spiegel Schalten', const Dpt(1, 1)),
        g('1/4/2', 'Bad Spiegel Status', const Dpt(1, 1)),
        g('1/0/3', 'Flur Wand Schalten', const Dpt(1, 1)),
        g('3/1/0', 'Küche Rollladen Auf/Ab fahren', const Dpt(1, 8)),
        g('2/2/1', 'Küche Stellwert Heizen', const Dpt(1, 1)),
        g('1/3/1', 'Küche Decke Sperre', const Dpt(1, 1)),
      ])
        x.address: x,
    });
  });

  tearDown(() async {
    activeTunnel.value = null;
    await dir.delete(recursive: true);
  });

  test('Schaltbares je Raum: Licht und Rollladen, kein Heizventil, nie die Sperre', () {
    final rooms = roomControls(CatalogStore.instance.catalog);
    final all = [for (final r in rooms.values) ...r];
    expect(all.map((c) => c.control.address), containsAll([_ga('1/0/1'), _ga('1/0/2'), _ga('1/0/3'), _ga('3/1/0')]));
    expect(all.map((c) => c.control.address), isNot(contains(_ga('1/3/1'))));
    expect(all.map((c) => c.control.address), isNot(contains(_ga('2/2/1'))));
    expect(all.firstWhere((c) => c.control.address == _ga('1/0/1')).control.status, _ga('1/4/1'));
  });

  test('Befehl gegen Rückmeldung: passt, widerspricht, fehlt, antwortet nicht', () {
    const c = ChannelControl(ControlKind.toggle, 1, status: 2);
    Map<int, Telegram> latest(List<Telegram> ts) => {for (final t in ts) t.destination == _ga('1/0/1') ? 1 : 2: t};
    expect(statusFinding(const ChannelControl(ControlKind.toggle, 1), {}), StatusFinding.noStatus);
    expect(statusFinding(c, {}), StatusFinding.unknown);
    expect(statusFinding(c, latest([_bit(0, '1/0/1', 1), _bit(1, '1/4/1', 1)])), StatusFinding.ok);
    expect(
      statusFinding(c, latest([_bit(0, '1/0/1', 1), _bit(1, '1/4/1', 0)])),
      StatusFinding.mismatch,
      reason: 'Status kam sofort und sagt Aus: gesperrt oder falsch verknüpft',
    );
    expect(
      statusFinding(c, latest([_bit(10, '1/0/1', 1), _bit(0, '1/4/1', 0)])),
      StatusFinding.mismatch,
      reason: 'auf den Befehl kam keine Rückmeldung mehr',
    );
    expect(
      statusFinding(c, latest([_bit(0, '1/0/1', 1), _bit(600, '1/4/1', 0)])),
      StatusFinding.ok,
      reason: 'später von woanders ausgeschaltet: der Status ist die Wahrheit',
    );
    expect(statusFinding(c, latest([_bit(0, '1/4/1', 1)]), unanswered: {2}), StatusFinding.silent);
  });

  testWidgets('Seite: schalten per Schalter, Rückmeldungen lesen zeigt die stummen', (tester) async {
    final log = TelegramLog()..addAll([_bit(0, '1/4/1', 0), _bit(0, '1/4/2', 0)]);
    final tunnel = _FakeTunnel(log);
    activeTunnel.value = tunnel;
    await pumpWindow(tester, RoomControlScreen(log: log), const Size(375, 2400));
    expect(find.text('Küche'), findsOneWidget);
    expect(find.textContaining('keine Rückmeldung im Projekt'), findsOneWidget, reason: 'Flur Wand');

    await tester.tap(find.byType(Switch).first);
    await settle(tester);
    expect(tunnel.written, isNotEmpty);
    expect(tunnel.written.single.$2, 1);
    expect(find.textContaining('keine Rückmeldung'), findsWidgets);

    await tester.tap(find.text('Rückmeldungen lesen'));
    await settle(tester);
    expect(tunnel.reads.toSet(), {_ga('1/4/1'), _ga('1/4/2')});
    expect(find.textContaining('Rückmeldung antwortet nicht auf Lesen'), findsOneWidget, reason: 'nur das Bad');

    await pumpWindow(tester, RoomControlScreen(log: log), const Size(375, 2400), textScale: 2);
    await pumpWindow(tester, RoomControlScreen(log: log), wideWindow);
    await tester.pumpWidget(const SizedBox());
  });
}
