import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/rf_info.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/health.dart';

/// L_Data.ind from 1.1.5 to 1/0/1 (switch on) with RF medium information.
Uint8List frame({int info = 0x32, int lfn = 0}) => Uint8List.fromList([
  0x29, 10, //
  0x02, 0x08, info, 0x00, 0xFA, 0x12, 0x34, 0x56, 0x78, lfn,
  0xBC, 0xE0, 0x11, 0x05, 0x08, 0x01, 0x01, 0x00, 0x81,
]);

Telegram at(int seconds, {int info = 0x32, int lfn = 0}) {
  final t = Telegram.fromCemi(frame(info: info, lfn: lfn))!;
  return t.atTap(0, time: DateTime(2026, 11, 22, 12, 0, seconds));
}

void main() {
  test('reads the RF medium information', () {
    final rf = RfInfo.parse(frame(info: 0x23, lfn: 5))!;
    expect(rf.signal, RfSignal.medium);
    expect(rf.retransmitterSignal, RfSignal.none);
    expect(rf.batteryOk, isTrue);
    expect(rf.transmitOnly, isTrue);
    expect(rf.serialOrDomain, '00FA12345678');
    expect(rf.frameNumber, 5);
  });

  test('frames without additional information or from TP have none', () {
    expect(RfInfo.parse([0x29, 0, 0xBC, 0xE0, 0x11, 0x05, 0x08, 0x01, 0x01, 0x00, 0x81]), isNull);
    expect(RfInfo.parse([0x29, 4, 0x03, 0x02, 0x00, 0x00, 0xBC]), isNull);
    expect(RfInfo.parse([0x29, 20, 0x02]), isNull);
    expect(RfInfo.parse(const []), isNull);
  });

  test('the telegram still decodes with the additional information', () {
    final t = Telegram.fromCemi(frame())!;
    expect(t.source, 0x1105);
    expect(t.destination, 0x0801);
  });

  test('statistics: lost frames from gaps, retries from repeats, latest battery', () {
    final log = [
      at(0, lfn: 0),
      at(1, lfn: 0), // retry
      at(10, lfn: 1),
      at(20, lfn: 4), // 2 and 3 lost
      at(30, lfn: 5, info: 0x10), // weak, battery low
    ];
    final st = RfDeviceStats.of(0x1105, log)!;
    expect(st.frames, 5);
    expect(st.repeated, 1);
    expect(st.lost, 2);
    expect(st.batteryOk, isFalse);
    expect(st.signal, RfSignal.weak);
    expect(st.weakShare, closeTo(0.2, 1e-9));
    expect(RfDeviceStats.of(0x1106, log), isNull);
  });

  test('findings: low battery, and lost frames from 5 %', () {
    final log = [at(0, lfn: 0, info: 0x20), at(10, lfn: 1, info: 0x20), at(20, lfn: 3, info: 0x20)];
    final kinds = {for (final f in rfFindings(log)) f.kind};
    expect(kinds, {FindingKind.rfBattery, FindingKind.rfLost});
    expect(rfFindings([at(0, lfn: 0), at(10, lfn: 1)]), isEmpty);
  });

  test('no losses across a pause in listening, no retries from a second tap point', () {
    final paused = [at(0, lfn: 1), at(59, lfn: 4).atTap(0, time: DateTime(2026, 11, 22, 13))];
    expect(RfDeviceStats.of(0x1105, paused)!.lost, 0);
    final twice = [at(0, lfn: 1), at(0, lfn: 1).atTap(1, time: DateTime(2026, 11, 22, 12, 0, 0, 40))];
    final st = RfDeviceStats.of(0x1105, twice)!;
    expect(st.repeated, 0);
    expect(st.frames, 1);
  });

  test('all senders in one pass, frames without RF info are left out', () {
    final other = Telegram.fromCemi(
      Uint8List.fromList([0x29, 0, 0xBC, 0xE0, 0x11, 0x06, 0x08, 0x01, 0x01, 0x00, 0x81]),
    )!;
    expect(RfDeviceStats.all([at(0), other, at(10, lfn: 1)]).keys, [0x1105]);
  });
}
