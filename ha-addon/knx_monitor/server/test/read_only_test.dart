import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

import 'fake_gateway.dart';

/// L_Data.req: GroupValueWrite an 1/2/3, Wert 0.
final requestOff = Uint8List.fromList([0x11, 0x00, 0xBC, 0xE0, 0x00, 0x00, 0x0A, 0x03, 0x01, 0x00, 0x80]);

/// Schreibtelegramm 1.1.5 → 1/2/3, Wert 1 (DPT 1).
final writeOn = [0x29, 0x00, 0xBC, 0xE0, 0x11, 0x05, 0x0A, 0x03, 0x01, 0x00, 0x81];

List<int> knxip(int service, [List<int> body = const []]) {
  final length = 6 + body.length;
  return [0x06, 0x10, service >> 8, service & 0xFF, length >> 8, length & 0xFF, ...body];
}

void main() {
  group('Relay bei Nur-Lesen', () {
    test('lässt Verwaltung durch', () {
      for (final service in [0x0201, 0x0203, 0x0205, 0x0207, 0x0209, 0x020A, 0x020B, 0x0311, 0x0421, 0x0422]) {
        expect(relayMaySendReadOnly(knxip(service)), isTrue, reason: service.toRadixString(16));
      }
    });

    test('sperrt alles, was ein Telegramm oder eine Einstellung trägt', () {
      for (final service in [0x0420, 0x0530, 0x0310, 0x0424, 0x0950, 0x0951]) {
        expect(relayMaySendReadOnly(knxip(service, [0x04, 0x01, 0x00, 0x00, ...requestOff])), isFalse);
      }
    });

    test('sperrt kaputte Pakete', () {
      expect(relayMaySendReadOnly(const []), isFalse);
      expect(relayMaySendReadOnly(const [0x06, 0x10, 0x02]), isFalse);
      expect(relayMaySendReadOnly(const [0x06, 0x13, 0x02, 0x05, 0x00, 0x06]), isFalse);
    });
  });

  group('BusService bei Nur-Lesen', () {
    late FakeGateway gw;
    late Directory data;
    late BusService bus;

    setUp(() async {
      gw = await FakeGateway.start();
      data = await Directory.systemTemp.createTemp('knx_read_only');
      bus = BusService(data, describe: (_, _) async => null, readOnly: true);
      await bus.start();
    });
    tearDown(() async {
      await bus.shutdown();
      await data.delete(recursive: true);
      await gw.close();
    });

    test('zeichnet auf, sendet aber nichts und meldet es', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async => bus.serve(await WebSocketTransformer.upgrade(r)));
      final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}');
      final frames = <List<int>>[];
      final states = <Map<String, Object?>>[];
      final results = <int, (int, String)>{};
      ws.listen((m) {
        final b = m as List<int>;
        switch (b[0]) {
          case 0x01:
            frames.add(b.sublist(1));
          case 0x02:
            states.add(jsonDecode(utf8.decode(b.sublist(1))) as Map<String, Object?>);
          case 0x11:
            results[(b[1] << 8) | b[2]] = (b[3], utf8.decode(b.sublist(4)));
        }
      });

      await bus.update({'enabled': true, 'host': '127.0.0.1', 'port': gw.port});
      await until(() => bus.state == 'connected');
      await until(() => states.any((s) => s['state'] == 'connected'));
      expect(states.last['readOnly'], true);

      gw.indicate(writeOn);
      await until(() => frames.isNotEmpty);

      ws.add(Uint8List.fromList([0x10, 0x00, 0x07, ...requestOff]));
      await until(() => results.containsKey(7));
      expect(results[7]!.$1, 6);
      expect(results[7]!.$2, readOnlyMessage);
      expect(gw.requests, isEmpty);

      await ws.close();
      await server.close(force: true);
    });
  });

  test('ReadOnlyLink lehnt Senden ab, ohne die Verbindung anzufassen', () async {
    final gw = await FakeGateway.start();
    final link = ReadOnlyLink(KnxIpTunnel(host: '127.0.0.1', port: gw.port));
    await link.connect();
    expect(link.address, 0x1126);
    await expectLater(link.send(requestOff), throwsA(isA<LinkException>()));
    expect(gw.requests, isEmpty);
    await link.close();
    await gw.close();
  });
}
