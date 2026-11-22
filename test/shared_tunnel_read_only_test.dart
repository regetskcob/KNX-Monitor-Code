import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/shared_tunnel.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/platform/addon.dart';

/// Server mit Nur-Lesen: meldet `readOnly` im Status und lehnt jedes Senden
/// mit Ergebnis 6 ab.
class _ReadOnlyServer implements AddonSocket {
  final _messages = StreamController<Uint8List>();

  void status(Map<String, Object?> j) => _messages.add(Uint8List.fromList([0x02, ...utf8.encode(jsonEncode(j))]));

  @override
  Stream<Uint8List> get messages => _messages.stream;

  @override
  void send(List<int> data) {
    if (data.first == 0x10) {
      _messages.add(Uint8List.fromList([0x11, data[1], data[2], 6, ...utf8.encode('Nur-Lesen ist an')]));
    }
  }

  @override
  void close() => _messages.close();
}

void main() {
  test('Nur-Lesen des Servers: Status bekannt, Senden scheitert mit eigenem Text', () async {
    final server = _ReadOnlyServer();
    final tunnel = SharedTunnel(open: () async => server);
    addTearDown(tunnel.dispose);
    final connecting = tunnel.connect();
    await Future<void>.delayed(Duration.zero);
    server.status({'state': 'connected', 'readOnly': true});
    await connecting;

    expect(tunnel.readOnly, isTrue);
    await expectLater(
      tunnel.write(0x0A03, small: 1),
      throwsA(isA<KnxException>().having((e) => e.message, 'message', s.addonReadOnly)),
    );
  });

  test('nach dem Trennen zählt der alte Status nicht: connect wartet auf den neuen', () async {
    var server = _ReadOnlyServer();
    final tunnel = SharedTunnel(open: () async => server);
    addTearDown(tunnel.dispose);
    var connecting = tunnel.connect();
    await Future<void>.delayed(Duration.zero);
    server.status({'state': 'connected'});
    await connecting;
    await tunnel.disconnect();

    // Meanwhile the server lost the bus.
    server = _ReadOnlyServer();
    connecting = tunnel.connect(timeout: const Duration(milliseconds: 100));
    await Future<void>.delayed(Duration.zero);
    server.status({'state': 'connecting', 'error': 'Gateway antwortet nicht'});
    await expectLater(
      connecting,
      throwsA(isA<KnxException>().having((e) => e.message, 'message', 'Gateway antwortet nicht')),
    );
    expect(tunnel.state.value, TunnelState.disconnected);
    expect(tunnel.error.value, 'Gateway antwortet nicht');
  });

  test('zweites connect während des Wartens: beide enden mit dem ersten Status', () async {
    final server = _ReadOnlyServer();
    final tunnel = SharedTunnel(open: () async => server);
    addTearDown(tunnel.dispose);
    final a = tunnel.connect(timeout: const Duration(milliseconds: 300));
    await Future<void>.delayed(Duration.zero);
    final b = tunnel.connect(timeout: const Duration(milliseconds: 300));
    await Future<void>.delayed(Duration.zero);
    server.status({'state': 'connected'});
    await Future.wait([a, b]);
    expect(tunnel.state.value, TunnelState.connected);
  });
}
