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

  test('device access goes over the tap point on the device line, group telegrams over the first', () async {
    final a = _Fake('a', address: 0x11FA), b = _Fake('b', address: 0x12FA);
    final m = MultiTunnel([a, b], names: ['A', 'B'], retryDelays: const [Duration(hours: 1)]);
    await m.connect();
    Uint8List to(int address) => buildLData(destination: address, group: false, tpdu: [0x80]);
    await m.sendFrame(to(0x1214)); // 1.2.20: over b
    expect((a.sent.length, b.sent.length), (0, 1));
    await m.sendFrame(to(0x1105)); // 1.1.5: over a
    expect((a.sent.length, b.sent.length), (1, 1));
    await m.sendFrame(to(0x1307)); // 1.3.7: no tap point there, over the first
    expect((a.sent.length, b.sent.length), (2, 1));
    await m.write(0x0A03, small: 1); // a group address that happens to look like line 0.10
    expect((a.sent.length, b.sent.length), (3, 1));
    // The tap point on the device line is gone: over the first again, never unsent.
    b.drop();
    await m.sendFrame(to(0x1214));
    expect((a.sent.length, b.sent.length), (4, 1));
    m.dispose();
  });

  test('a tap point dropping in the middle of the window does not hold the telegram back', () async {
    final a = _Fake('a'), b = _Fake('b');
    final m = MultiTunnel([a, b], names: ['A', 'B'], retryDelays: const [Duration(hours: 1)]);
    final got = <Telegram>[];
    final sub = m.telegrams.listen(got.add);
    await m.connect();
    a.inject(_t(6));
    await Future<void>.delayed(Duration.zero);
    expect(got, isEmpty, reason: 'waits for b within the window');
    b.drop();
    await Future<void>.delayed(const Duration(milliseconds: 160));
    expect(got.single.sightings, isEmpty);
    expect(m.state.value, TunnelState.connected);
    await sub.cancel();
    m.dispose();
  });

  test('double press and repetition stay separate entries, matched in order', () async {
    final a = _Fake('a'), b = _Fake('b');
    final m = MultiTunnel([a, b], names: ['A', 'B']);
    final got = <Telegram>[];
    final sub = m.telegrams.listen(got.add);
    await m.connect();
    // The same telegram twice in quick succession at both tap points.
    a
      ..inject(_t(6))
      ..inject(_t(6));
    b
      ..inject(_t(5))
      ..inject(_t(5));
    await Future<void>.delayed(Duration.zero);
    expect(got, hasLength(2));
    expect(got.every((t) => t.sightings.length == 1), isTrue);
    // A repetition (repeat flag) is another frame: it does not merge with the original.
    final repeated = Telegram(
      time: DateTime.now(),
      source: 0x1105,
      destination: 0x0A03,
      type: TelegramType.write,
      data: Uint8List.fromList([1]),
      isSmall: true,
      repeated: true,
    );
    a.inject(_t(6));
    b.inject(repeated);
    await Future<void>.delayed(const Duration(milliseconds: 160));
    expect(got, hasLength(4));
    expect(got.skip(2).every((t) => t.sightings.isEmpty), isTrue);
    await sub.cancel();
    m.dispose();
  });

  test('a silent tap point is not waited for; gaps follow the tap points', () async {
    final a = _Fake('a'), b = _Fake('b');
    final m = MultiTunnel([a, b], names: ['A', 'B'], retryDelays: const [Duration(hours: 1)]);
    final got = <Telegram>[];
    final sub = m.telegrams.listen(got.add);
    await m.connect();
    expect(tapGaps.since, isNotNull);
    for (var i = 0; i < TapSilence.threshold + 1; i++) {
      a.inject(_t(6));
    }
    await Future<void>.delayed(const Duration(milliseconds: 160));
    expect(m.tapPoints.value[1].silent, isTrue);
    got.clear();
    a.inject(_t(6));
    await Future<void>.delayed(Duration.zero);
    expect(got, hasLength(1), reason: 'leaves at once');
    b.drop();
    // (Just after connecting still counts to the gap before it, hence the look ahead.)
    final soon = DateTime.now().add(const Duration(seconds: 3));
    expect(tapGaps.state(1, soon), TapSeen.away);
    expect(tapGaps.state(0, soon), TapSeen.listening);
    await sub.cancel();
    m.dispose();
    expect(tapGaps.since, isNull);
  });

  test('one tunnel alone: no labels, no gaps, telegrams untouched', () async {
    final a = _Fake('a', address: 0x1123);
    final got = <Telegram>[];
    final sub = a.telegrams.listen(got.add);
    await a.connect();
    final t = _t(6);
    a.inject(t);
    await Future<void>.delayed(Duration.zero);
    expect(identical(got.single, t), isTrue);
    expect(tapLabels.value, isEmpty);
    expect(a.tapPoints.value, isEmpty);
    expect(tapGaps.since, isNull);
    expect(seenAtOneTapOnly(t), isFalse);
    await sub.cancel();
    a.dispose();
  });
}
