import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

/// Nachgebauter Home-Assistant-WebSocket mit KNX-Integration.
class _FakeHa {
  _FakeHa._(this.server) {
    server.listen((r) async {
      final ws = await WebSocketTransformer.upgrade(r);
      client = ws;
      ws.add(jsonEncode({'type': 'auth_required'}));
      ws.listen((m) {
        final j = jsonDecode(m as String) as Map<String, Object?>;
        received.add(j);
        switch (j['type']) {
          case 'auth':
            ws.add(jsonEncode({'type': j['access_token'] == 'token' ? 'auth_ok' : 'auth_invalid'}));
          case 'knx/subscribe_telegrams':
            subscription = j['id']! as int;
            ws.add(jsonEncode({'id': j['id'], 'type': 'result', 'success': true}));
          case 'call_service':
            ws.add(jsonEncode({'id': j['id'], 'type': 'result', 'success': true}));
        }
      });
    });
  }

  static Future<_FakeHa> start() async => _FakeHa._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer server;
  WebSocket? client;
  int? subscription;
  final received = <Map<String, Object?>>[];

  String get url => 'ws://127.0.0.1:${server.port}';

  void telegram(Map<String, Object?> t) => client!.add(jsonEncode({'id': subscription, 'type': 'event', 'event': t}));
}

void main() {
  test('Telegramme aus Home Assistant als cEMI', () {
    expect(
      cemiFromHa({
        'destination': '1/2/3',
        'source': '1.1.5',
        'direction': 'Incoming',
        'telegramtype': 'GroupValueWrite',
        'payload': 1,
      }),
      [0x29, 0x00, 0xBC, 0xE0, 0x11, 0x05, 0x0A, 0x03, 0x01, 0x00, 0x81],
    );
    expect(
      cemiFromHa({
        'destination': '1/2/4',
        'source': '0.0.0',
        'direction': 'Outgoing',
        'telegramtype': 'GroupValueResponse',
        'payload': [12, 26],
      }),
      [0x2E, 0x00, 0xBC, 0xE0, 0x00, 0x00, 0x0A, 0x04, 0x03, 0x00, 0x40, 12, 26],
    );
    expect(cemiFromHa({'destination': '1/2/3', 'source': '1.1.5', 'telegramtype': 'GroupValueRead', 'payload': null}), [
      0x29,
      0x00,
      0xBC,
      0xE0,
      0x11,
      0x05,
      0x0A,
      0x03,
      0x01,
      0x00,
      0x00,
    ]);
  });

  test('verbindet, empfängt, sendet über knx.send/knx.read', () async {
    final ha = await _FakeHa.start();
    addTearDown(() => ha.server.close(force: true));
    final link = HaLink(url: ha.url, token: 'token');
    await link.connect();
    final frames = <Uint8List>[];
    link.frames.listen(frames.add);
    ha.telegram({
      'destination': '1/2/3',
      'source': '1.1.5',
      'direction': 'Incoming',
      'telegramtype': 'GroupValueWrite',
      'payload': [0x0C, 0x1A],
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(frames.single.sublist(6, 8), [0x0A, 0x03]);

    await link.send(Uint8List.fromList([0x11, 0x00, 0xBC, 0xE0, 0, 0, 0x0A, 0x03, 0x01, 0x00, 0x81]));
    await link.send(Uint8List.fromList([0x11, 0x00, 0xBC, 0xE0, 0, 0, 0x0A, 0x04, 0x03, 0x00, 0x80, 0x0C, 0x1A]));
    await link.send(Uint8List.fromList([0x11, 0x00, 0xBC, 0xE0, 0, 0, 0x0A, 0x03, 0x01, 0x00, 0x00]));
    final calls = ha.received.where((m) => m['type'] == 'call_service').toList();
    expect(calls.map((c) => c['service']), ['send', 'send', 'read']);
    expect((calls[0]['service_data']! as Map)['payload'], 1);
    expect((calls[1]['service_data']! as Map)['payload'], [12, 26]);
    expect((calls[2]['service_data']! as Map)['address'], '1/2/3');

    await expectLater(
      link.send(Uint8List.fromList([0x11, 0x00, 0xB0, 0x60, 0, 0, 0x11, 0x05, 0x00, 0x80])),
      throwsA(isA<LinkException>()),
    );
    await link.close();
  });

  test('falsches Token wird gemeldet', () async {
    final ha = await _FakeHa.start();
    addTearDown(() => ha.server.close(force: true));
    final link = HaLink(url: ha.url, token: 'falsch');
    await expectLater(link.connect(), throwsA(isA<LinkException>()));
  });
}
