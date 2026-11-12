import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

import 'fake_gateway.dart';

/// Ereigniskanal /ws/events (docs/event-channel.md).
void main() {
  late EventChannel channel;
  late HttpServer server;

  Future<void> start(EventChannel c) async {
    channel = c;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    // As in server.dart: who connects and with which role (here from test headers).
    server.listen(
      (r) => r.uri.path == eventsPath
          ? channel.serve(r, owner: r.headers.value('x-owner'), admin: r.headers.value('x-admin') != '0')
          : (r.response..statusCode = 404).close(),
    );
  }

  tearDown(() async {
    await channel.close();
    await server.close(force: true);
  });

  Uri url([String query = '']) => Uri.parse('ws://127.0.0.1:${server.port}$eventsPath$query');

  /// Verbindet und liefert die Nachrichten als JSON.
  Future<(WebSocket, _Messages)> connect([String query = '']) async {
    // Closed by each test.
    // ignore: close_sinks
    final ws = await WebSocket.connect(url(query).toString());
    return (ws, _Messages(ws.map((m) => (jsonDecode(m as String) as Map).cast<String, Object?>())));
  }

  Future<void> until(bool Function() ok, {Duration timeout = const Duration(seconds: 5)}) async {
    final end = DateTime.now().add(timeout);
    while (!ok()) {
      if (DateTime.now().isAfter(end)) fail('Zeit abgelaufen');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('Format: hello, Ereignis mit Folgenummer und Zeit, Herzschlag', () async {
    await start(
      EventChannel(
        server: '1.12.0',
        epoch: 'e1',
        heartbeat: const Duration(milliseconds: 200),
        clock: () => DateTime.utc(2026, 11, 11, 10),
      ),
    );
    final (ws, messages) = await connect();
    expect(await messages.next, {
      'v': 1,
      'type': 'hello',
      'seq': 0,
      'epoch': 'e1',
      'server': '1.12.0',
      'heartbeat_s': 0,
      'resumed': false,
    });
    await until(() => channel.clientCount == 1);
    channel.publish(HomeAssistant.watcherEvent, {'watcher_id': 'w1', 'name': 'Wind'});
    expect(await messages.next, {
      'v': 1,
      'type': 'event',
      'seq': 1,
      'time': '2026-11-11T10:00:00.000Z',
      'event': 'knx_monitor_watcher',
      'data': {'watcher_id': 'w1', 'name': 'Wind'},
    });
    // Herzschlag mit der letzten Folgenummer, auch ohne neue Ereignisse.
    expect(await messages.next, {'v': 1, 'type': 'heartbeat', 'seq': 1, 'time': '2026-11-11T10:00:00.000Z'});
    await ws.close();
    await until(() => channel.clientCount == 0);
  });

  test('Ringpuffer: nach Abbruch nur das Verpasste, Lücke und Neustart erkennbar', () async {
    await start(EventChannel(epoch: 'e1', ringSize: 4));
    for (var i = 1; i <= 3; i++) {
      channel.publish(HomeAssistant.alarmEvent, {'n': i});
    }
    // Zuletzt Nr. 1 gesehen: 2 und 3 kommen nach dem hello, nichts fehlt.
    var (ws, messages) = await connect('?since=1&epoch=e1');
    var hello = await messages.next;
    expect(hello['seq'], 3);
    expect(hello['resumed'], isTrue);
    expect([(await messages.next)['seq'], (await messages.next)['seq']], [2, 3]);
    await ws.close();

    // Alles gesehen: nichts nachzuholen.
    (ws, messages) = await connect('?since=3&epoch=e1');
    expect((await messages.next)['resumed'], isTrue);
    channel.publish(HomeAssistant.busEvent, {'connected': true});
    expect((await messages.next)['seq'], 4);
    await ws.close();

    // Zu lange weg: der Ring hält nur 4 (5..8), 3 und 4 fehlen.
    for (var i = 5; i <= 8; i++) {
      channel.publish(HomeAssistant.alarmEvent, {'n': i});
    }
    (ws, messages) = await connect('?since=2&epoch=e1');
    hello = await messages.next;
    expect(hello['resumed'], isFalse);
    expect([for (var i = 0; i < 4; i++) (await messages.next)['seq']], [5, 6, 7, 8]);
    await ws.close();

    // Server neu gestartet (andere Epoche): nichts nachholen, die Lücke ist unbekannt.
    (ws, messages) = await connect('?since=2&epoch=alt');
    hello = await messages.next;
    expect(hello['resumed'], isFalse);
    expect(hello['epoch'], 'e1');
    channel.publish(HomeAssistant.busEvent, {'connected': false});
    expect((await messages.next)['seq'], 9);
    await ws.close();
  });

  test('langsamer Client wird getrennt, die anderen bekommen weiter alles', () async {
    await start(EventChannel(maxQueuedBytes: 64 * 1024));
    // Handshake von Hand und danach nie mehr lesen.
    final stalled = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
    final closed = Completer<void>();
    stalled.write(
      'GET $eventsPath HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n'
      'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n',
    );
    final (ws, messages) = await connect();
    await messages.next; // hello
    await until(() => channel.clientCount == 2);
    final big = 'x' * 4000;
    var received = 0;
    final all = Completer<void>();
    unawaited(() async {
      while (received < 3000) {
        if ((await messages.next)['type'] == 'event') received++;
      }
      all.complete();
    }());
    for (var i = 0; i < 3000; i++) {
      channel.publish(HomeAssistant.watcherEvent, {'raw': big});
      // Kurz Luft holen, damit der lesende Client mitkommt.
      if (i % 50 == 0) await Future<void>.delayed(Duration.zero);
    }
    await all.future.timeout(const Duration(seconds: 20));
    expect(channel.dropped, 1);
    await until(() => channel.clientCount == 1);
    // Der Server hat die Verbindung hart beendet.
    stalled.listen(null, onDone: closed.complete, onError: (Object _) => closed.complete());
    await closed.future.timeout(const Duration(seconds: 5));
    stalled.destroy();
    await ws.close();
  });

  test('höchstens maxClients, nur WebSocket, große Nachricht vom Client beendet', () async {
    await start(EventChannel(maxClients: 1));
    final (ws, messages) = await connect();
    await messages.next;
    await until(() => channel.clientCount == 1);
    final client = HttpClient();
    final busy = await (await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}$eventsPath'))).close();
    await busy.drain<void>();
    expect(busy.statusCode, HttpStatus.upgradeRequired);
    await expectLater(WebSocket.connect(url().toString()), throwsA(isA<WebSocketException>()));
    client.close();

    ws.add('x' * 2000);
    await messages.end;
    // dart:io refuses the frame before assembling it (maxPayloadLength).
    expect(ws.closeCode, WebSocketStatus.protocolError);
    await until(() => channel.clientCount == 0);
  });

  test('Plätze: höchstens 2 je Gerät, der letzte Platz nur mit Admin-Recht', () async {
    await start(EventChannel(maxClients: 4));
    final open = <WebSocket>[];
    Future<bool> join(String owner, {bool admin = false}) async {
      try {
        final ws = await WebSocket.connect(url().toString(), headers: {'x-owner': owner, 'x-admin': admin ? '1' : '0'});
        ws.listen((_) {}, onError: (Object _) {});
        open.add(ws);
        return true;
      } on WebSocketException {
        return false;
      }
    }

    // Ein Betrachter belegt nicht mehr als zwei Plätze ...
    expect([await join('viewer-a'), await join('viewer-a'), await join('viewer-a')], [true, true, false]);
    // ... ein zweiter bekommt einen, der letzte bleibt für Admin-Geräte frei.
    expect([await join('viewer-b'), await join('viewer-b')], [true, false]);
    expect(await join('integration', admin: true), isTrue);
    // Jetzt ist alles voll, auch für Admins.
    expect(await join('admin-2', admin: true), isFalse);
    expect(channel.clientCount, 4);
    // Ein Platz wird frei: wieder verfügbar.
    await open.first.close();
    await until(() => channel.clientCount == 3);
    expect(await join('viewer-c'), isFalse, reason: 'der letzte Platz bleibt für Admins');
    expect(await join('admin-2', admin: true), isTrue);
    for (final ws in open) {
      await ws.close();
    }
  });

  test('Zugang geändert: alle Verbindungen werden geschlossen', () async {
    await start(EventChannel());
    final (ws, messages) = await connect();
    await messages.next;
    await until(() => channel.clientCount == 1);
    await channel.closeClients();
    await messages.end.timeout(const Duration(seconds: 5));
    expect(ws.closeCode, WebSocketStatus.policyViolation);
  });

  test('nicht kodierbares Ereignis: nur ins Log, keine Lücke in der Folge', () async {
    await start(EventChannel());
    channel.publish(HomeAssistant.watcherEvent, {'value': double.nan});
    expect(channel.seq, 0);
    channel.publish(HomeAssistant.watcherEvent, {'value': 1.5});
    expect(channel.seq, 1);
  });

  test('gleiche Quelle: Home Assistant und Kanal bekommen dieselben Ereignisse', () async {
    await start(EventChannel());
    // Core-API des Supervisors.
    final fired = <(String, Map<String, Object?>)>[];
    final core = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    core.listen((r) async {
      final body = (jsonDecode(await utf8.decodeStream(r)) as Map).cast<String, Object?>();
      fired.add((r.uri.path.substring('/api/events/'.length), body));
      await (r.response..statusCode = 200).close();
    });
    final gw = await FakeGateway.start();
    final dir = await Directory.systemTemp.createTemp('knx_events');
    final mqtt = <String>[];
    final bus = BusService(
      dir,
      describe: (_, _) async => null,
      installation: {'id': 'a', 'name': 'Zuhause'},
      event: serverEventSink(
        channel: channel,
        homeAssistant: HomeAssistant(token: 't', base: Uri.parse('http://127.0.0.1:${core.port}/')),
        others: (type, _) => mqtt.add(type),
      ),
    );
    final (ws, messages) = await connect();
    await messages.next;
    try {
      await bus.start();
      await bus.update({'enabled': true, 'host': '127.0.0.1', 'port': gw.port});
      final event = await messages.next.timeout(const Duration(seconds: 10));
      await until(() => fired.isNotEmpty);
      expect(event['event'], HomeAssistant.busEvent);
      expect(fired.single.$1, event['event']);
      expect(fired.single.$2, event['data']);
      expect(event['data'], {'connected': true, 'state': 'connected', 'installation': 'Zuhause'});
      expect(mqtt, [HomeAssistant.busEvent]);
    } finally {
      await ws.close();
      await bus.shutdown();
      await gw.close();
      await core.close(force: true);
      await dir.delete(recursive: true);
    }
  });

  test('Sec-WebSocket-Accept wie in RFC 6455', () {
    expect(EventChannel.acceptKey('dGhlIHNhbXBsZSBub25jZQ=='), 's3pPLMBiTxaQ9kYGzzhZRbK+xOo=');
  });
}

/// Nachrichten einer Verbindung der Reihe nach.
class _Messages {
  _Messages(Stream<Map<String, Object?>> stream) : _it = StreamIterator(stream);
  final StreamIterator<Map<String, Object?>> _it;

  Future<Map<String, Object?>> get next async {
    if (!await _it.moveNext()) throw StateError('Verbindung geschlossen');
    return _it.current;
  }

  /// Wartet, bis der Server die Verbindung beendet (`WebSocket.done` wartet
  /// auch auf das eigene Schließen).
  Future<void> get end async {
    while (await _it.moveNext()) {}
  }
}
