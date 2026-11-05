import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/busmon.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/shared_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/platform/addon.dart';

import 'fake_gateway.dart';

void main() {
  late FakeGateway gateway;
  setUp(() async => gateway = await FakeGateway.start());
  tearDown(() => gateway.close());

  test('keine freien Tunnel (0x24) wird als solcher gemeldet', () async {
    gateway.full = true;
    final tunnel = KnxTunnel('127.0.0.1', port: gateway.port);
    await expectLater(
      tunnel.connect(),
      throwsA(isA<KnxException>().having((e) => e.message, 'message', s.errorNoFreeTunnel)),
    );
    tunnel.dispose();
  });

  test('Tunneling-Request mit zu großer Kopflänge wird verworfen, ohne Absturz', () async {
    final tunnel = KnxTunnel('127.0.0.1', port: gateway.port);
    await tunnel.connect();
    // Connection header claims 240 bytes, the packet has 4: before, sublistView threw.
    gateway.sendTunnelRequest([0xF0, 0x01, 0x00, 0x00]);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(tunnel.state.value, TunnelState.connected);
    tunnel.dispose();
  });

  test('feste Tunneladresse per Extended CRI', () async {
    final tunnel = KnxTunnel('127.0.0.1', port: gateway.port, requestedAddress: 0x11F0);
    await tunnel.connect();
    expect(gateway.connectCris.single, [6, 4, 2, 0, 0x11, 0xF0]);
    tunnel.dispose();
  });

  test('Tunnelling v1: ohne feste Adresse erneut versucht', () async {
    gateway.rejectExtended = true;
    final tunnel = KnxTunnel('127.0.0.1', port: gateway.port, requestedAddress: 0x11F0);
    await tunnel.connect();
    expect(gateway.connectCris, [
      [6, 4, 2, 0, 0x11, 0xF0],
      [4, 4, 2, 0],
    ]);
    expect(tunnel.state.value, TunnelState.connected);
    tunnel.dispose();
  });

  test('Fehler des Add-on-Servers: Meldung und Grund aus der Antwort', () {
    final e = Addon.errorOf(utf8.encode(jsonEncode({'error': 'Gateway antwortet nicht', 'problem': 'noResponse'})));
    expect(e?.message, 'Gateway antwortet nicht');
    expect(connectProblemNamed(e?.problem), ConnectProblem.noResponse);
    expect(Addon.errorOf(utf8.encode('Internal Server Error')), isNull);
    expect(connectProblemNamed('unbekannt'), isNull);
    // Älterer oder fehlerhafter Server: `problem` kein Text – Meldung bleibt.
    final odd = Addon.errorOf(utf8.encode(jsonEncode({'error': 'Gateway antwortet nicht', 'problem': 3})));
    expect(odd?.message, 'Gateway antwortet nicht');
    expect(odd?.problem, isNull);
  });

  group('SharedTunnel (Add-on)', () {
    late _FakeSocket socket;
    late SharedTunnel tunnel;
    setUp(() {
      socket = _FakeSocket();
      tunnel = SharedTunnel(host: '192.168.1.10', open: () async => socket);
    });
    tearDown(() => tunnel.dispose());

    void status(Map<String, Object?> j) => socket.receive([0x02, ...utf8.encode(jsonEncode(j))]);

    test('verbunden, sobald der Server verbunden meldet; Frames werden Telegramme', () async {
      final connecting = tunnel.connect();
      await Future<void>.delayed(Duration.zero);
      status({
        'state': 'connected',
        'address': 0x1126,
        'config': {'mode': 'tcp', 'host': '192.168.1.10'},
      });
      await connecting;
      expect(tunnel.state.value, TunnelState.connected);
      expect(tunnel.tunnelAddress, 0x1126);
      expect(tunnel.kind, 'Add-on · TCP');

      final got = <Telegram>[];
      tunnel.telegrams.listen(got.add);
      socket.receive([0x01, 0x29, 0x00, 0xBC, 0xE0, 0x11, 0x05, 0x0A, 0x03, 0x01, 0x00, 0x81]);
      await Future<void>.delayed(Duration.zero);
      expect(got.single.destination, 0x0A03);
    });

    test('Senden: Ergebnis des Servers, Bestätigung über den Frame', () async {
      final connecting = tunnel.connect();
      await Future<void>.delayed(Duration.zero);
      status({'state': 'connected'});
      await connecting;
      socket.onSend = (m) {
        expect(m[0], 0x10);
        socket.receive([0x11, m[1], m[2], 0]);
        // Bestätigung wie vom Gateway
        socket.receive([0x01, 0x2E, 0x00, 0xBC, 0xE0, 0x11, 0x26, 0x0A, 0x03, 0x01, 0x00, 0x80]);
      };
      expect(await tunnel.write(0x0A03, small: 0), isTrue);

      socket.onSend = (m) => socket.receive([0x11, m[1], m[2], 4]);
      await expectLater(
        tunnel.write(0x0A03, small: 1),
        throwsA(isA<KnxException>().having((e) => e.message, 'message', s.addonDeviceBusy)),
      );
    });

    test('Server verliert den Bus: Ansicht zeigt Grund, ohne zu trennen', () async {
      final connecting = tunnel.connect();
      await Future<void>.delayed(Duration.zero);
      status({'state': 'connected'});
      await connecting;
      status({'state': 'connecting', 'error': 'Gateway antwortet nicht mehr'});
      await Future<void>.delayed(Duration.zero);
      expect(tunnel.state.value, TunnelState.disconnected);
      expect(tunnel.error.value, 'Gateway antwortet nicht mehr');
      expect(tunnel.attached, isTrue);
    });

    test('Server erreicht das Gateway nicht: Grund für die Verbindungshilfe', () async {
      final connecting = tunnel.connect(timeout: const Duration(milliseconds: 50));
      await Future<void>.delayed(Duration.zero);
      status({'state': 'disconnected', 'error': 'Gateway antwortet nicht', 'problem': 'noResponse'});
      await expectLater(
        connecting,
        throwsA(isA<KnxException>().having((e) => e.problem, 'problem', ConnectProblem.noResponse)),
      );
      expect(tunnel.error.value, 'Gateway antwortet nicht');
    });

    test('Wächter-Treffer vom Server werden mit Telegramm gemeldet', () async {
      final hits = <({List<String> ids, Telegram telegram})>[];
      tunnel.watchHits.listen(hits.add);
      final connecting = tunnel.connect();
      await Future<void>.delayed(Duration.zero);
      status({'state': 'connected'});
      await connecting;
      socket.receive([
        0x03,
        ...utf8.encode(
          jsonEncode({
            'ids': ['w1'],
            'line': {'t': 0, 's': 0x1105, 'd': 0x0A03, 'y': 2, 'x': '01', 'm': true},
          }),
        ),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(hits.single.ids, ['w1']);
      expect(hits.single.telegram.destination, 0x0A03);
    });

    test('KNX-HAT im Busmonitor: Rohframes kommen über den gemeinsamen Tunnel', () async {
      final connecting = tunnel.connect();
      await Future<void>.delayed(Duration.zero);
      status({
        'state': 'connected',
        'config': {'mode': 'hat', 'hatBusmonitor': false},
      });
      await connecting;
      expect(tunnel.kind, 'Add-on · KNX-HAT');
      expect(tunnel.supportsBusMonitor, isFalse, reason: 'Link Layer: kein zweiter Tunnelplatz');
      status({
        'state': 'connected',
        'config': {'mode': 'hat', 'hatBusmonitor': true},
      });
      await Future<void>.delayed(Duration.zero);
      expect(tunnel.serverBusMonitor, isTrue);
      expect(tunnel.supportsBusMonitor, isTrue);
      final frames = <BusmonFrame>[];
      final telegrams = <Telegram>[];
      tunnel.busmon.listen(frames.add);
      tunnel.telegrams.listen(telegrams.add);
      // Rohframe und die vom Server umgesetzte Fassung, dann die Quittung.
      socket.receive([
        0x01, 0x2B, 0x00, 0xBC, 0x11, 0x05, 0x09, 0x01, 0xE1, 0x00, 0x81, 0x3F, //
      ]);
      socket.receive([0x01, 0x29, 0x00, 0xBC, 0xE0, 0x11, 0x05, 0x09, 0x01, 0x01, 0x00, 0x81]);
      socket.receive([0x01, 0x2B, 0x00, 0xCC]);
      await Future<void>.delayed(Duration.zero);
      expect(frames.map((f) => f.kind), [BusmonKind.data, BusmonKind.ack]);
      expect(telegrams.single.destination, 0x0901);
    });

    test('Busmonitor: Tunnel freigeben wartet auf den Server, ohne Fehler', () async {
      final connecting = tunnel.connect();
      await Future<void>.delayed(Duration.zero);
      status({'state': 'connected'});
      await connecting;
      final sent = <List<int>>[];
      socket.onSend = (m) {
        sent.add(m);
        if (m[1] == 1) status({'state': 'yielded'});
      };
      await tunnel.releaseTunnel(true);
      expect(sent.single, [0x12, 1]);
      expect(tunnel.state.value, TunnelState.disconnected);
      expect(tunnel.error.value, isNull); // kein automatisches Neuverbinden
      expect(tunnel.attached, isTrue);

      await tunnel.releaseTunnel(false);
      expect(sent.last, [0x12, 0]);
      status({'state': 'connected'});
      await Future<void>.delayed(Duration.zero);
      expect(tunnel.state.value, TunnelState.connected);
    });
  });
}

class _FakeSocket implements AddonSocket {
  final _messages = StreamController<Uint8List>.broadcast();
  void Function(List<int>)? onSend;

  void receive(List<int> m) => _messages.add(Uint8List.fromList(m));

  @override
  Stream<Uint8List> get messages => _messages.stream;

  @override
  void send(List<int> data) => onSend?.call(data);

  @override
  void close() => _messages.close();
}
