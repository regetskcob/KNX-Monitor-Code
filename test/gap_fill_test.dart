import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/shared_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/history_store.dart';
import 'package:knx_monitor/monitor_model.dart';
import 'package:knx_monitor/platform/addon.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Add-on bzw. Box: Bricht die Verbindung zum Server ab (App im Hintergrund),
// zeichnet der Server weiter auf. Nach dem Wiederverbinden holt die Ansicht
// das Verpasste aus dem Tagesverlauf nach – an der richtigen Stelle.
void main() {
  late Directory dir;
  final history = HistoryStore.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('knx_gap');
    AppStorage.instance = IoStorage(dir);
    await history.load();
    await history.setRetention(3);
  });

  tearDown(() => dir.delete(recursive: true));

  Telegram t(DateTime time, int ga) => Telegram(
    time: time,
    source: 0x1105,
    destination: ga,
    type: TelegramType.write,
    data: Uint8List.fromList([1]),
    isSmall: true,
  );

  test('nach dem Wiederverbinden steht das Verpasste zwischen alt und neu', () async {
    final tunnel = SharedTunnel(open: () async => _NoSocket());
    final model = MonitorModel(tunnel);
    addTearDown(model.dispose);
    // Erst das Auffüllen beim Öffnen abwarten (der Tag ist noch leer).
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final start = DateTime.now().subtract(const Duration(minutes: 1));
    final before = t(start, 0x0101);
    final missed = [
      t(start.add(const Duration(seconds: 10)), 0x0102),
      t(start.add(const Duration(seconds: 20)), 0x0103),
    ];
    final after = t(start.add(const Duration(seconds: 30)), 0x0104);

    tunnel.state.value = TunnelState.connected;
    model.add(before);
    // Verbindung weg; der Server schreibt weiter.
    tunnel.error.value = 'weg';
    tunnel.state.value = TunnelState.disconnected;
    for (final m in missed) {
      history.add(m);
    }
    await history.flush();
    // Wieder da: das erste neue Telegramm kommt, bevor der Verlauf gelesen ist.
    tunnel.error.value = null;
    tunnel.state.value = TunnelState.connected;
    model.add(after);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(model.log.map((e) => e.destination), [0x0101, 0x0102, 0x0103, 0x0104]);
    expect(model.total, 4);
  });

  /// Live [before], Abbruch, [missed] nur beim Server, wieder da, live [after].
  Future<MonitorModel> run(Telegram before, List<Telegram> missed, Telegram after, {bool pause = false}) async {
    final tunnel = SharedTunnel(open: () async => _NoSocket());
    final model = MonitorModel(tunnel);
    addTearDown(model.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    tunnel.state.value = TunnelState.connected;
    model.add(before);
    if (pause) model.setPaused(true);
    tunnel.error.value = 'weg';
    tunnel.state.value = TunnelState.disconnected;
    for (final m in missed) {
      history.add(m);
    }
    await history.flush();
    tunnel.error.value = null;
    tunnel.state.value = TunnelState.connected;
    model.add(after);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return model;
  }

  test('pausiert: die sichtbaren Zeilen bleiben, das Nachgeladene wartet mit', () async {
    final start = DateTime.now().subtract(const Duration(minutes: 1));
    final model = await run(
      t(start, 0x0101),
      [t(start.add(const Duration(seconds: 10)), 0x0102)],
      t(start.add(const Duration(seconds: 30)), 0x0104),
      pause: true,
    );
    expect(model.visibleLog.map((e) => e.destination), [0x0101]);
    expect(model.pending, 2);
    model.setPaused(false);
    expect(model.visibleLog.map((e) => e.destination), [0x0101, 0x0102, 0x0104]);
  });

  test('über Mitternacht: beide Tage werden gelesen', () async {
    final midnight = DateUtils.dateOnly(DateTime.now());
    // Kurz nach Mitternacht reicht die Zeit nicht für „danach“ – dann auslassen.
    if (DateTime.now().difference(midnight).inSeconds < 30) return;
    final model = await run(t(midnight.subtract(const Duration(seconds: 10)), 0x0101), [
      t(midnight.subtract(const Duration(seconds: 5)), 0x0102),
      t(midnight.add(const Duration(seconds: 5)), 0x0103),
    ], t(DateTime.now(), 0x0104));
    expect(model.log.map((e) => e.destination), [0x0101, 0x0102, 0x0103, 0x0104]);
  });

  test('ohne Abbruch wird nichts nachgeladen', () async {
    final tunnel = SharedTunnel(open: () async => _NoSocket());
    final model = MonitorModel(tunnel);
    addTearDown(model.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final start = DateTime.now().subtract(const Duration(minutes: 1));
    tunnel.state.value = TunnelState.connected;
    model.add(t(start, 0x0101));
    history.add(t(start.add(const Duration(seconds: 10)), 0x0102));
    await history.flush();
    // Gewolltes Trennen und Verbinden: kein Fehler, also keine Lücke.
    tunnel.state.value = TunnelState.disconnected;
    tunnel.state.value = TunnelState.connected;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(model.log.map((e) => e.destination), [0x0101]);
  });
}

class _NoSocket implements AddonSocket {
  @override
  Stream<Uint8List> get messages => const Stream.empty();

  @override
  void send(List<int> data) {}

  @override
  void close() {}
}
