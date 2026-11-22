import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/busmon.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/model/channel_control.dart';
import 'package:knx_monitor/model/channel_test.dart';
import 'package:knx_monitor/model/device_channels.dart';
import 'package:knx_monitor/model/heating_check.dart';

void main() {
  test('an empty bus monitor frame is unknown, not an error', () {
    expect(BusmonFrame.fromRaw(Uint8List(0), time: DateTime(2026)).kind, BusmonKind.unknown);
  });

  test('underfloor heating and storeys count as room heating, the floor sensor does not', () {
    HeatingRole? role(String name, Dpt dpt) => heatingRole(GroupInfo(address: 1, name: name), dpt);
    expect(role('Fußbodenheizung Bad Stellwert', const Dpt(5, 1)), HeatingRole.valve);
    expect(role('Ground floor living actual temperature', const Dpt(9, 1)), HeatingRole.actual);
    expect(role('Bodentemperatur Bad', const Dpt(9, 1)), isNull);
    expect(role('Vorlauf Temperatur', const Dpt(9, 1)), isNull);
    expect(role('Bad Fußboden Temperatur', const Dpt(9, 1)), isNull);
    expect(role('Boden-Temperatur Bad', const Dpt(9, 1)), isNull);
    expect(role('Floor-Temperature Bath', const Dpt(9, 1)), isNull);
  });

  test('channels without a label keep their own result', () {
    ChannelTest fresh() => ChannelTest.of(1, [
      DeviceChannel('', const [], title: 'Licht Flur'),
      DeviceChannel('', const [], title: 'Licht Bad'),
    ]);
    final test = fresh();
    test.rate(test.items[1], ChannelResult.ok);
    final restored = fresh()..restore(test.toJson());
    expect(restored.items[0].result, ChannelResult.open);
    expect(restored.items[1].result, ChannelResult.ok);
  });

  test('every gate asks before sending, motors and actuators do not', () {
    for (final name in [
      'Hallentor auf',
      'Kipptor',
      'Schwingtor Garage',
      'Flügeltor',
      'Tor 2',
      'Smartlock Haustür',
      'Keylock',
    ]) {
      expect(isCaution(name), isTrue, reason: name);
    }
    for (final name in ['Motor Pumpe', 'Schaltaktor Kanal A', 'Ventilator Bad', 'Block 3 Licht', 'Uhr Clock']) {
      expect(isCaution(name), isFalse, reason: name);
    }
  });

  test('unlabeled channel results saved by 1.12.0 still come back, one each', () {
    ChannelTest fresh() => ChannelTest.of(1, [
      DeviceChannel('', const [], title: 'Licht Flur'),
      DeviceChannel('', const [], title: 'Licht Bad'),
    ]);
    final restored = fresh()
      ..restore([
        {'l': '', 'r': 'ok'},
        {'l': '', 'r': 'noReaction'},
      ]);
    expect(restored.items.map((i) => i.result), [ChannelResult.ok, ChannelResult.noReaction]);
  });
}
