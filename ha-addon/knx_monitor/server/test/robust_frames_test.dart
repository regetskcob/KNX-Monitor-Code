import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:knx_monitor_server/box.dart';
import 'package:knx_monitor_server/bus.dart';
import 'package:knx/secure.dart';
import 'package:test/test.dart';

import 'fake_gateway.dart';

/// Busverbindung ohne Netz: nimmt alles an und merkt es sich.
class _Link implements BusLink {
  final sent = <Uint8List>[];
  final _frames = StreamController<Uint8List>.broadcast();
  final _lost = Completer<String>();
  @override
  Stream<Uint8List> get frames => _frames.stream;
  void receive(Uint8List frame) => _frames.add(frame);
  @override
  int? get address => 0x1101;
  @override
  String get label => 'Test';
  @override
  Future<void> connect() async {}
  @override
  Future<void> send(Uint8List cemi) async => sent.add(cemi);
  @override
  Future<String> get lost => _lost.future;
  @override
  Future<void> close() async {
    if (!_lost.isCompleted) _lost.complete('Getrennt');
  }
}

/// L_Data.req an [destination] mit Gruppenbit [group] und den Bytes ab TPCI.
Uint8List _req({required bool group, int destination = 0x0A03, required List<int> tpdu}) => Uint8List.fromList([
  0x11,
  0x00,
  0xBC,
  group ? 0xE0 : 0x60,
  0x00,
  0x00,
  destination >> 8,
  destination & 0xFF,
  tpdu.length - 1,
  ...tpdu,
]);

Uint8List _bytes(Random r, int max) => Uint8List.fromList(List.generate(r.nextInt(max), (_) => r.nextInt(256)));

/// Zufällige Bytes, oft mit passendem Anfang, damit die Prüfung tiefer kommt.
Uint8List _cemiLike(Random r) {
  final b = _bytes(r, 40);
  if (b.length > 1 && r.nextBool()) b[0] = const [0x11, 0x29, 0x2E, 0x2B][r.nextInt(4)];
  return b;
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 500 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue);
}

void main() {
  group('Sendeerlaubnis ohne Admin-Recht', () {
    test('Gruppenwerte: Lesen, Antwort, Schreiben, kurz und lang', () {
      expect(deviceMaySend(_req(group: true, tpdu: [0x00, 0x00])), isTrue, reason: 'Read');
      expect(deviceMaySend(_req(group: true, tpdu: [0x00, 0x41])), isTrue, reason: 'Response kurz');
      expect(deviceMaySend(_req(group: true, tpdu: [0x00, 0x81])), isTrue, reason: 'Write kurz');
      expect(deviceMaySend(_req(group: true, tpdu: [0x00, 0x80, 0x12, 0x34])), isTrue, reason: 'Write lang');
    });

    test('gesicherter Gruppenwert (A_SecureService)', () {
      expect(deviceMaySend(_req(group: true, tpdu: [0x03, 0xF1, 0x10, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6])), isTrue);
    });

    test('Dienste an Individualadressen sind gesperrt', () {
      const device = 0x1105;
      final refused = {
        'T_Connect': [0x80],
        'A_Restart': [0x03, 0x80],
        'A_DeviceDescriptor_Read': [0x03, 0x00],
        'A_Memory_Write': [0x42, 0x81, 0x01, 0x00, 0x12],
        'A_PropertyValue_Write': [0x03, 0xD7, 0, 1, 0x10, 0x01, 0xFF],
      };
      for (final MapEntry(:key, :value) in refused.entries) {
        expect(
          deviceMaySend(_req(group: false, destination: device, tpdu: value)),
          isFalse,
          reason: key,
        );
      }
    });

    test('andere Dienste an Gruppenadressen und Systembroadcast sind gesperrt', () {
      // A_Memory_Write mit Gruppenbit: Geräte werten das nicht aus, trotzdem nicht durchlassen.
      expect(deviceMaySend(_req(group: true, tpdu: [0x02, 0x81, 0x01, 0x00, 0x12])), isFalse);
      // A_IndividualAddress_Write an 0/0/0.
      expect(deviceMaySend(_req(group: true, destination: 0, tpdu: [0x00, 0xC0, 0x11, 0x05])), isFalse);
      // Auch ein Gruppenwert: an 0/0/0 hat er nichts zu suchen.
      expect(deviceMaySend(_req(group: true, destination: 0, tpdu: [0x00, 0x81])), isFalse);
      // Nummerierte Transportschicht an eine Gruppe.
      expect(deviceMaySend(_req(group: true, tpdu: [0x40, 0x81])), isFalse);
    });

    test('falsche Längen und falscher Code', () {
      expect(deviceMaySend(const []), isFalse);
      expect(deviceMaySend(const [0x11]), isFalse);
      expect(deviceMaySend(Uint8List.fromList([0x11, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0])), isFalse);
      final tooLong = [
        ..._req(group: true, tpdu: [0x00, 0x81]),
        0x55,
      ];
      expect(deviceMaySend(tooLong), isFalse);
      final ind = _req(group: true, tpdu: [0x00, 0x81])..[0] = 0x29;
      expect(deviceMaySend(ind), isFalse);
    });
  });

  group('Absturzframes', () {
    late Directory data;
    late _Link link;
    late BusService bus;
    late HttpServer server;

    setUp(() async {
      data = await Directory.systemTemp.createTemp('robust');
      bus = BusService(data, link: (_) => link = _Link(), describe: (_, _) async => null);
      await bus.start();
      await bus.update({'enabled': true, 'mode': 'ha'});
      await _until(() => bus.state == 'connected');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        final admin = r.uri.path == '/admin';
        await bus.serve(await WebSocketTransformer.upgrade(r), admin: admin);
      });
    });

    tearDown(() async {
      await server.close(force: true);
      await bus.shutdown();
      await data.delete(recursive: true);
    });

    /// Sendet und liefert das Ergebnis (Id 7).
    Future<int> send(List<int> cemi, {String path = '/admin'}) async {
      final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}$path');
      final result = Completer<int>();
      ws.listen((m) {
        if (m is List<int> && m.isNotEmpty && m[0] == 0x11 && !result.isCompleted) result.complete(m[3]);
      });
      ws.add(Uint8List.fromList([0x10, 0, 7, ...cemi]));
      final code = await result.future.timeout(const Duration(seconds: 5));
      await ws.close();
      return code;
    }

    test('Zusatzinfo länger als der Frame: Ablehnung statt RangeError', () async {
      // Bis 1.9.1 endete das in exit(255) und einer Neustartschleife.
      final code = await send([0x11, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
      expect(code, 3);
      expect(link.sent, isEmpty);
    });

    test('Gerät ohne Admin-Recht: Gruppenwert geht, Neustart nicht', () async {
      expect(await send(_req(group: true, tpdu: [0x00, 0x81]), path: '/device'), 0);
      expect(link.sent, hasLength(1));
      expect(await send(_req(group: false, destination: 0x1105, tpdu: [0x03, 0x80]), path: '/device'), 5);
      expect(await send(_req(group: true, tpdu: [0x02, 0x81, 1, 0, 0x12]), path: '/device'), 5);
      expect(link.sent, hasLength(1));
    });

    test('Admin darf weiterhin Geräte ansprechen', () async {
      expect(await send(_req(group: false, destination: 0x1105, tpdu: [0x80])), 0);
      expect(await send(_req(group: false, destination: 0x1105, tpdu: [0x03, 0x80])), 0);
      expect(link.sent, hasLength(2));
    });

    test('Gerät ohne Admin-Recht kann den Tunnel nicht freigeben', () async {
      final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}/device');
      ws.add(Uint8List.fromList([0x12, 1]));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(bus.state, 'connected');
      await ws.close();
      final admin = await WebSocket.connect('ws://127.0.0.1:${server.port}/admin');
      admin.add(Uint8List.fromList([0x12, 1]));
      await _until(() => bus.state == 'yielded');
      await admin.close();
      await _until(() => bus.state == 'connected');
    });

    test('Fuzz: zufällige Nachrichten über den WebSocket', () async {
      final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}/admin');
      final r = Random(1);
      for (var n = 0; n < 2000; n++) {
        ws.add(Uint8List.fromList([0x10, n >> 8 & 0xFF, n & 0xFF, ..._cemiLike(r)]));
        if (n % 50 == 0) ws.add(_bytes(r, 20));
      }
      await ws.close();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(bus.state, 'connected');
    });

    test('Fuzz: kaputte Frames vom Bus halten den Server nicht an', () async {
      final r = Random(2);
      for (var n = 0; n < 5000; n++) {
        link.receive(_cemiLike(r));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(bus.state, 'connected');
    });
  });

  group('Tunnel', () {
    late FakeGateway gw;
    setUp(() async => gw = await FakeGateway.start());
    tearDown(() => gw.close());

    test('TUNNELLING_REQUEST mit zu langem Header wird verworfen', () async {
      // Bis 1.9.1 warf das eine gefälschte UDP-Antwort außerhalb jedes try.
      final tunnel = KnxIpTunnel(host: '127.0.0.1', port: gw.port);
      await tunnel.connect();
      final frames = <Uint8List>[];
      tunnel.frames.listen(frames.add);
      gw.raw([0x06, 0x10, 0x04, 0x20, 0x00, 0x0A, 0xFF, 0x01, 0x00, 0x00]);
      gw.indicate(const [0x29, 0x00, 0xBC, 0xE0, 0x11, 0x05, 0x0A, 0x03, 0x01, 0x00, 0x81]);
      await _until(() => frames.isNotEmpty);
      await tunnel.close();
    });

    test('Fuzz: zufällige Pakete vom Gateway', () async {
      final tunnel = KnxIpTunnel(host: '127.0.0.1', port: gw.port);
      await tunnel.connect();
      final r = Random(3);
      for (var n = 0; n < 3000; n++) {
        final p = _bytes(r, 40);
        if (p.length > 7 && r.nextBool()) {
          // Gültiger Kopf, damit die Pakete den Dienst erreichen; eine Trennung
          // (0x0209) würde den Tunnel zu Recht beenden, darum nicht dabei.
          const services = [0x0420, 0x0421, 0x0206, 0x0208];
          final s = services[r.nextInt(services.length)];
          p
            ..[0] = 0x06
            ..[1] = 0x10
            ..[2] = s >> 8
            ..[3] = s & 0xFF
            ..[7] = 1;
        }
        gw.raw(p);
        if (n % 200 == 0) await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tunnel.close();
    });
  });

  group('Fuzz der Parser', () {
    final r = Random(4);
    final time = DateTime(2026, 10, 31);
    test('telegramJson, busmonToLData, BusmonCounters', () {
      final counters = BusmonCounters();
      for (var n = 0; n < 50000; n++) {
        final c = _cemiLike(r);
        telegramJson(c, time);
        busmonToLData(c);
        counters.add(c);
      }
    });

    test('Data Secure', () {
      final ds = DataSecure(groupKeys: {0x0A03: Uint8List(16)}, sequenceNumbers: {0x1105: 0});
      for (var n = 0; n < 20000; n++) {
        final c = _cemiLike(r);
        if (c.length > 12 && r.nextBool()) {
          // Bis zum Schlüssel durchkommen.
          c[1] = 0;
          c[3] |= 0x80;
          c[6] = 0x0A;
          c[7] = 0x03;
          c[9] |= 0x03;
          c[10] = 0xF1;
        }
        ds.receive(c);
        ds.send(c, source: 0x1101);
      }
    });

    test('IP Secure', () {
      final session = IpSecureSession(userId: 2, userPassword: 'x');
      for (var n = 0; n < 5000; n++) {
        session.handle(_bytes(r, 80));
      }
    });

    test('FT1.2', () {
      final decoder = Ft12Decoder();
      for (var n = 0; n < 5000; n++) {
        decoder.add(_bytes(r, 64));
      }
    });

    test('KNXnet/IP-Kopf', () {
      for (var n = 0; n < 20000; n++) {
        serviceOf(_bytes(r, 12));
      }
    });
  });
}
