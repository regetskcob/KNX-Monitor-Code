import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/bus_replay.dart';
import 'package:knx_monitor/model/recording.dart';
import 'package:knx_monitor/monitor_model.dart';

void main() {
  final start = DateTime(2026, 10, 14, 12);

  Telegram t(int s, int ga, {TelegramType type = TelegramType.write, DateTime? time}) => Telegram(
    time: time ?? start.add(Duration(seconds: s)),
    source: 0x1105,
    destination: ga,
    type: type,
    data: Uint8List.fromList([1]),
    isSmall: true,
  );

  test('nur Schreibtelegramme der gewählten Adressen', () {
    final all = [t(0, 1), t(1, 2, type: TelegramType.read), t(2, 2), t(3, 3, type: TelegramType.response), t(4, 1)];
    expect(BusReplay.writesOf(all), hasLength(3));
    expect(BusReplay.writesOf(all, addresses: {1}).map((t) => t.time.second), [0, 4]);
  });

  test('Originaltakt, gekürzte Pausen, nicht quittiert, Abbruch', () async {
    final waits = <Duration>[];
    final sent = <int>[];
    final replay = BusReplay(
      telegrams: [t(0, 1), t(2, 2), t(62, 3), t(63, 4)],
      maxGap: const Duration(seconds: 5),
      wait: (d) async => waits.add(d),
      send: (t) async {
        sent.add(t.destination);
        if (t.destination == 3) return false;
        if (t.destination == 4) throw const KnxException('weg');
        return true;
      },
    );
    await replay.run();
    expect(sent, [1, 2, 3, 4]);
    expect(waits, [const Duration(seconds: 2), const Duration(seconds: 5), const Duration(seconds: 1)]);
    expect((replay.sent, replay.failed, replay.error), (2, 1, 'weg'));
    expect(replay.done, isTrue);
  });

  test('Stopp bricht eine lange Pause ab', () async {
    final sent = <int>[];
    final replay = BusReplay(
      telegrams: [t(0, 1), t(3600, 2)],
      send: (t) async {
        sent.add(t.destination);
        return true;
      },
    );
    final run = replay.run();
    await Future<void>.delayed(Duration.zero);
    replay.stop();
    await run;
    expect(sent, [1]);
    expect(replay.stopped && replay.done, isTrue);
  });

  test('Aufnahme mit Vorlauf enthält die letzten 10 Sekunden', () async {
    final tunnel = KnxTunnel('test');
    final model = MonitorModel(tunnel);
    final now = DateTime.now();
    tunnel.inject(t(0, 1, time: now.subtract(const Duration(seconds: 30))));
    tunnel.inject(t(0, 2, time: now.subtract(const Duration(seconds: 5))));
    tunnel.inject(t(0, 3, time: now.subtract(const Duration(seconds: 1))));
    await Future<void>.delayed(Duration.zero);

    model.startRecording(preRoll: MonitorModel.preRoll);
    expect(model.recorder!.telegrams.map((t) => t.destination), [2, 3]);
    expect(now.difference(model.recorder!.started).inSeconds, inInclusiveRange(9, 10));
    model.stopRecording(name: 'x');

    model.startRecording();
    expect(model.recorder!.telegrams, isEmpty);
    model.dispose();
  });

  test('Bearbeitete Kopie lässt das Original unverändert', () {
    final original = Recording(
      id: 'a',
      name: 'Probe',
      started: start,
      ended: start.add(const Duration(seconds: 5)),
      telegrams: [t(0, 1), t(1, 2)],
    );
    final changed = original.telegrams[0].withValue(data: [0x0C, 0x1A]);
    final copy = original.copyWith(name: 'Probe · bearbeitet', telegrams: [changed]);
    expect(copy.id, isNot(original.id));
    expect(original.telegrams, hasLength(2));
    expect(original.telegrams[0].isSmall, isTrue);
    expect(copy.telegrams.single.isSmall, isFalse);
    expect(copy.telegrams.single.data, [0x0C, 0x1A]);
    expect(original.telegrams[1].withValue(small: 0).data, [0]);
  });
}
