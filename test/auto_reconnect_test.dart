import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/model/auto_reconnect.dart';

import 'fake_gateway.dart';

void main() {
  late FakeGateway gateway;
  late KnxTunnel tunnel;
  late AutoReconnect auto;

  setUp(() async {
    gateway = await FakeGateway.start();
    tunnel = KnxTunnel('127.0.0.1', port: gateway.port);
    await tunnel.connect();
    auto = AutoReconnect(tunnel, delays: const [Duration(milliseconds: 100), Duration(milliseconds: 200)]);
  });

  tearDown(() async {
    auto.dispose();
    await tunnel.disconnect();
    gateway.close();
  });

  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; i < 50 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(condition(), isTrue);
  }

  test('nach Abbruch: neu verbinden, bei vollem Gateway weiter versuchen', () async {
    gateway.full = true;
    gateway.kick();
    await waitFor(() => tunnel.state.value == TunnelState.disconnected && auto.retryAt != null);

    // Erster Versuch scheitert (voll) → nächster Versuch geplant.
    await waitFor(() => !auto.busy && auto.retryAt != null && tunnel.error.value != null);
    gateway.full = false;
    await waitFor(() => tunnel.state.value == TunnelState.connected);
    expect(auto.retryAt, isNull);
  });

  test('gewolltes Trennen löst keinen Versuch aus', () async {
    await tunnel.disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(auto.retryAt, isNull);
    expect(tunnel.state.value, TunnelState.disconnected);
  });
}
