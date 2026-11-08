import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/multi_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/tap_points.dart';

class _Fake extends KnxTunnel {
  _Fake(super.host, {this.fail = false, int? address}) {
    tunnelAddress = address;
  }
  bool fail;
  final sent = <Uint8List>[];

  @override
  Future<void> connect({Duration timeout = const Duration(seconds: 5)}) async {
    if (fail) {
      error.value = 'no response';
      throw const KnxException('no response');
    }
    error.value = null;
    state.value = TunnelState.connected;
  }

  @override
  Future<void> disconnect() async => state.value = TunnelState.disconnected;

  void drop() {
    error.value = 'lost';
    state.value = TunnelState.disconnected;
  }

  @override
  Future<bool?> sendFrame(Uint8List cemi, {Duration timeout = const Duration(seconds: 3)}) async {
    sent.add(cemi);
    return true;
  }
}

/// As SharedTunnel: frames of the server's tap points with their number.
class _Server extends KnxTunnel {
  _Server() : super('server');
  void frame(int tap, List<int> cemi) => receiveCemiAt(tap, Uint8List.fromList(cemi));
  void live(int n) => useTaps(n);
}

List<int> _ind(int hop) => [0x29, 0x00, 0xBC, 0x80 | (hop << 4), 0x11, 0x05, 0x0A, 0x03, 0x01, 0x00, 0x81];

Telegram _t(int hop) => Telegram(
  time: DateTime.now(),
  source: 0x1105,
  destination: 0x0A03,
  type: TelegramType.write,
  data: Uint8List.fromList([1]),
  isSmall: true,
  hopCount: hop,
);

void main() {
  test('merges two tap points into one telegram with a sighting', () async {
    final a = _Fake('a', address: 0x1123), b = _Fake('b', address: 0x1223);
    final m = MultiTunnel([a, b], names: ['A', 'B']);
    final got = <Telegram>[];
    final sub = m.telegrams.listen(got.add);
    await m.connect();
    expect(m.state.value, TunnelState.connected);
    expect(tapLabels.value, ['1.1', '1.2']);
    a.inject(_t(6));
    b.inject(_t(5));
    await Future<void>.delayed(Duration.zero);
    expect(got, hasLength(1));
    expect(got.single.taps.toList(), [0, 1]);
    expect(got.single.sightings.single.hopCount, 5);
    await sub.cancel();
    m.dispose();
    expect(tapLabels.value, isEmpty);
  });

  test('a dropped tap point does not disconnect the others; sending uses a live one', () async {
    final a = _Fake('a'), b = _Fake('b');
    final m = MultiTunnel([a, b], names: ['A', 'B'], retryDelays: const [Duration(hours: 1)]);
    await m.connect();
    a.drop();
    expect(m.state.value, TunnelState.connected);
    expect(m.tapPoints.value.first.connected, isFalse);
    await m.write(0x0A03, small: 1);
    expect(b.sent, hasLength(1));
    // A telegram now seen only at b leaves without waiting for a.
    final got = <Telegram>[];
    final sub = m.telegrams.listen(got.add);
    b.inject(_t(6));
    await Future<void>.delayed(Duration.zero);
    expect(got.single.tap, 1);
    await sub.cancel();
    b.drop();
    expect(m.state.value, TunnelState.disconnected);
    expect(m.error.value, isNotNull);
    m.dispose();
  });

  test('connect fails only if no tap point connects', () async {
    final a = _Fake('a', fail: true), b = _Fake('b');
    final m = MultiTunnel([a, b], names: ['A', 'B'], retryDelays: const [Duration(hours: 1)]);
    await m.connect();
    expect(m.state.value, TunnelState.connected);
    m.dispose();
    final c = MultiTunnel([_Fake('c', fail: true)], names: ['C']);
    await expectLater(c.connect(), throwsA(isA<KnxException>()));
    c.dispose();
  });

  test('server frames of two tap points (0x01 and 0x04) merge in the app', () async {
    final t = _Server()..live(2);
    final got = <Telegram>[];
    final sub = t.telegrams.listen(got.add);
    t.frame(0, _ind(6));
    t.frame(1, _ind(5));
    await Future<void>.delayed(Duration.zero);
    expect(got.single.sightings.single.tap, 1);
    t.frame(1, _ind(5));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(got.last.tap, 1);
    await sub.cancel();
    t.dispose();
  });

  test('TapPoint JSON round trip and invalid entries', () {
    const p = TapPoint(name: 'Linie 1.2', host: '10.0.0.2', mode: TapMode.tcp, window: Duration(milliseconds: 150));
    expect(TapPoint.fromJson(p.toJson()), p);
    expect(TapPoint.fromJson({'mode': 'udp', 'host': ''}), isNull);
    expect(TapPoint.fromJson({'mode': 'x', 'host': 'a'}), isNull);
    expect(TapPoint.fromJson({'mode': 'routing', 'host': ''})?.mode, TapMode.routing);
  });
}
