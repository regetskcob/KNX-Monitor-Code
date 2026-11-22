import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/routing_tunnel.dart';
import 'package:knx_monitor/platform/udp.dart';

class _Udp implements UdpEndpoint {
  bool closed = false;
  final incoming = StreamController<({String host, Uint8List data})>();
  @override
  Stream<({String host, Uint8List data})> get datagrams => incoming.stream;
  @override
  int get port => 0;
  @override
  void send(List<int> data, String host, int port) {}
  @override
  void close() {
    closed = true;
    unawaited(incoming.close());
  }
}

void main() {
  const tick = Duration(seconds: 20);

  void run(void Function(FakeAsync async, RoutingTunnel tunnel, _Udp udp, void Function(Object) net) body) {
    fakeAsync((async) {
      Object net = <String>['192.168.1.5'];
      final udp = _Udp();
      final tunnel = RoutingTunnel(
        address: 0x11FF,
        open: (_, _) async => udp,
        networkAddresses: () async => net is List<String> ? net as List<String> : throw net,
      );
      unawaited(tunnel.connect());
      async.flushMicrotasks();
      expect(tunnel.state.value, TunnelState.connected);
      body(async, tunnel, udp, (v) => net = v);
      tunnel.disconnect();
      async.flushMicrotasks();
    });
  }

  test('ruhiger Bus im selben Netz bleibt verbunden, auch stundenlang', () {
    run((async, tunnel, _, _) {
      async.elapse(const Duration(hours: 6));
      expect(tunnel.state.value, TunnelState.connected);
    });
  });

  test('Netz weg: nach zwei Prüfungen getrennt, Socket zu', () {
    run((async, tunnel, udp, net) {
      net(<String>[]);
      async.elapse(tick);
      expect(tunnel.state.value, TunnelState.connected, reason: 'einmal zählt nicht');
      async.elapse(tick);
      expect(tunnel.state.value, TunnelState.disconnected);
      expect(tunnel.error.value, isNotNull);
      expect(udp.closed, isTrue);
    });
  });

  test('kurzer Aussetzer trennt nicht', () {
    run((async, tunnel, _, net) {
      net(<String>[]);
      async.elapse(tick);
      net(<String>['192.168.1.5']);
      async.elapse(tick * 3);
      expect(tunnel.state.value, TunnelState.connected);
    });
  });

  test('anderes Netz: neu beitreten nötig', () {
    run((async, tunnel, _, net) {
      net(<String>['10.0.0.7']);
      async.elapse(tick * 2);
      expect(tunnel.state.value, TunnelState.disconnected);
    });
  });

  test('weitere Adresse (VPN) stört nicht', () {
    run((async, tunnel, _, net) {
      net(<String>['192.168.1.5', '10.8.0.2']);
      async.elapse(tick * 5);
      expect(tunnel.state.value, TunnelState.connected);
    });
  });

  test('System antwortet nicht: bleibt verbunden', () {
    run((async, tunnel, _, net) {
      net(StateError('nicht lesbar'));
      async.elapse(tick * 5);
      expect(tunnel.state.value, TunnelState.connected);
    });
  });

  test('trennen während der Netzabfrage hinterlässt keinen Timer', () {
    fakeAsync((async) {
      final net = Completer<List<String>>();
      final tunnel = RoutingTunnel(address: 0x11FF, open: (_, _) async => _Udp(), networkAddresses: () => net.future);
      unawaited(tunnel.connect());
      async.flushMicrotasks();
      expect(tunnel.state.value, TunnelState.connected);
      tunnel.disconnect();
      net.complete(['192.168.1.5']);
      async.flushMicrotasks();
      expect(async.periodicTimerCount, 0);
    });
  });

  test('ROUTING_LOST_MESSAGE wird gezählt', () {
    run((async, tunnel, udp, _) {
      udp.incoming.add((
        host: '192.168.1.9',
        data: Uint8List.fromList([0x06, 0x10, 0x05, 0x31, 0x00, 0x0A, 0x04, 0x00, 0x00, 0x07]),
      ));
      async.flushMicrotasks();
      expect(tunnel.lostByRouter.value, 7);
    });
  });
}
