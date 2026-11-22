import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';

import 'fake_gateway.dart';

/// States of the app's own tunnel that the happy path never reaches.
void main() {
  late FakeGateway gateway;
  setUp(() async => gateway = await FakeGateway.start());
  tearDown(() => gateway.close());

  test('dispose während des Verbindens: kein Tunnel ohne Besitzer', () async {
    final tunnel = KnxTunnel('127.0.0.1', port: gateway.port);
    final connecting = tunnel.connect();
    tunnel.dispose();
    await connecting;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(tunnel.state.value, TunnelState.disconnected);
    expect(gateway.connectCris, isEmpty);
    // Disposed stays disposed.
    await tunnel.connect();
    expect(tunnel.state.value, TunnelState.disconnected);
  });

  test('trennen während des Verbindens: ein neuer Versuch bleibt unberührt', () async {
    final tunnel = KnxTunnel('127.0.0.1', port: gateway.port);
    final first = tunnel.connect();
    await tunnel.disconnect();
    await tunnel.connect();
    await first;
    expect(tunnel.state.value, TunnelState.connected);
    expect(gateway.connectCris, hasLength(1));
    tunnel.dispose();
  });

  test('zwei Sendungen an dieselbe Adresse: je eine eigene Bestätigung, nacheinander', () async {
    final tunnel = KnxTunnel('127.0.0.1', port: gateway.port);
    await tunnel.connect();
    gateway.holdConfirmations = true;
    final ga = parseGroup('1/2/3')!;
    final a = tunnel.write(ga, small: 1);
    final b = tunnel.write(ga, small: 0);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(gateway.requests, hasLength(1), reason: 'der zweite Frame wartet auf die Bestätigung des ersten');
    gateway.release();
    expect(await a, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(gateway.requests, hasLength(2));
    gateway.release();
    expect(await b, isTrue);
    tunnel.dispose();
  });

  test('zweimal kein Tunnel-ACK: Verbindung gilt als verloren', () async {
    final tunnel = KnxTunnel('127.0.0.1', port: gateway.port);
    await tunnel.connect();
    gateway.dropAcks = true;
    await expectLater(tunnel.write(parseGroup('1/2/3')!, small: 1), throwsA(isA<KnxException>()));
    expect(tunnel.state.value, TunnelState.disconnected);
    expect(tunnel.error.value, isNotNull);
    tunnel.dispose();
  });

  test('Gateway trennt: Zustand und Grund', () async {
    final tunnel = KnxTunnel('127.0.0.1', port: gateway.port);
    await tunnel.connect();
    gateway.kick();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(tunnel.state.value, TunnelState.disconnected);
    expect(tunnel.error.value, isNotNull);
    tunnel.dispose();
  });
}
