import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

import 'fake_gateway.dart';

/// Schreibtelegramm 1.1.5 → 1/2/3, Wert 1 (DPT 1).
final writeOn = [0x29, 0x00, 0xBC, 0xE0, 0x11, 0x05, 0x0A, 0x03, 0x01, 0x00, 0x81];

/// L_Data.req: GroupValueWrite an 1/2/3, Wert 0.
final requestOff = Uint8List.fromList([0x11, 0x00, 0xBC, 0xE0, 0x00, 0x00, 0x0A, 0x03, 0x01, 0x00, 0x80]);

void main() {
  late FakeGateway gw;
  setUp(() async => gw = await FakeGateway.start());
  tearDown(() => gw.close());

  group('KnxIpTunnel', () {
    for (final tcp in [false, true]) {
      test('${tcp ? 'TCP' : 'UDP'}: verbindet, empfängt und sendet', () async {
        final tunnel = KnxIpTunnel(host: '127.0.0.1', port: gw.port, tcp: tcp);
        await tunnel.connect();
        expect(tunnel.address, 0x1126);
        final frames = <Uint8List>[];
        tunnel.frames.listen(frames.add);
        gw.indicate(writeOn);
        await until(() => frames.isNotEmpty);
        expect(frames.first, writeOn);
        await tunnel.send(requestOff);
        await until(() => gw.requests.length == 1 && frames.length == 2);
        expect(frames.last[0], 0x2E); // Bestätigung
        await tunnel.close();
      });
    }

    test('fordert feste Tunneladresse an', () async {
      final tunnel = KnxIpTunnel(host: '127.0.0.1', port: gw.port, requestedAddress: 0x11F0);
      await tunnel.connect();
      expect(tunnel.address, 0x11F0);
      expect(gw.connectCris.single, [6, 4, 2, 0, 0x11, 0xF0]);
      await tunnel.close();
    });

    test('belegte Tunneladresse: nimmt einen freien Platz', () async {
      final tunnel = KnxIpTunnel(host: '127.0.0.1', port: gw.port, requestedAddress: 0x11F5);
      await tunnel.connect();
      expect(tunnel.address, 0x1126);
      expect(gw.connects, 2);
      await tunnel.close();
    });

    test('Tunnelling v1: Extended CRI abgelehnt, Basis-CRI klappt', () async {
      gw.v1Only = true;
      final tunnel = KnxIpTunnel(host: '127.0.0.1', port: gw.port, requestedAddress: 0x11F0);
      await tunnel.connect();
      expect(gw.connectCris.last, [4, 4, 2, 0]);
      await tunnel.close();
    });

    test('ohne Ausweichen: Fehler mit Statuscode', () async {
      final tunnel = KnxIpTunnel(host: '127.0.0.1', port: gw.port, requestedAddress: 0x11F5, fallback: false);
      expect(
        tunnel.connect(),
        throwsA(isA<LinkException>().having((e) => e.status, 'status', KnxIpStatus.connectionInUse)),
      );
    });

    test('keine freien Tunnel: verständliche Meldung', () async {
      gw.full = true;
      final tunnel = KnxIpTunnel(host: '127.0.0.1', port: gw.port);
      await expectLater(
        tunnel.connect(),
        throwsA(isA<LinkException>().having((e) => e.message, 'message', contains('keine freien Tunnel'))),
      );
    });

    test('Trennung durch das Gateway wird gemeldet', () async {
      final tunnel = KnxIpTunnel(host: '127.0.0.1', port: gw.port);
      await tunnel.connect();
      gw.kick();
      expect(await tunnel.lost.timeout(const Duration(seconds: 2)), contains('beendet'));
    });

    test('UDP: Wiederholung wird nur quittiert, nicht doppelt gemeldet', () async {
      final tunnel = KnxIpTunnel(host: '127.0.0.1', port: gw.port);
      await tunnel.connect();
      final frames = <Uint8List>[];
      tunnel.frames.listen(frames.add);
      gw.indicate(writeOn);
      await until(() => frames.length == 1);
      gw.repeatLast();
      gw.indicate(writeOn);
      await until(() => frames.length == 2);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(frames, hasLength(2));
      await tunnel.close();
    });
  });

  test('telegramJson entspricht Telegram.toJson der App', () {
    final t = DateTime.fromMicrosecondsSinceEpoch(1700000000000000);
    expect(telegramJson(Uint8List.fromList(writeOn), t), {
      't': 1700000000000000,
      's': 0x1105,
      'd': 0x0A03,
      'y': 2,
      'x': '01',
      'm': true,
      'r': '2900BCE011050A03010081',
    });
    // 2-Byte-Wert (DPT 9), Antwort, wiederholt, über Koppler (Hop 5)
    final response = [0x29, 0x00, 0x9C, 0xD0, 0x11, 0x05, 0x0A, 0x04, 0x03, 0x00, 0x40, 0x0C, 0x1A];
    expect(telegramJson(Uint8List.fromList(response), t), {
      't': 1700000000000000,
      's': 0x1105,
      'd': 0x0A04,
      'y': 1,
      'x': '0C1A',
      'rp': true,
      'h': 5,
      'r': '29009CD011050A040300400C1A',
    });
    // Einzeladressiert → kein Gruppentelegramm
    expect(telegramJson(Uint8List.fromList([0x29, 0x00, 0xB0, 0x60, 0x11, 0x05, 0x11, 0x06, 0x00, 0x80]), t), isNull);
  });

  group('BusService', () {
    late Directory data;
    late BusService bus;
    final notes = <String>[];

    setUp(() async {
      data = await Directory.systemTemp.createTemp('knx_bus');
      notes.clear();
      bus = BusService(
        data,
        notify: ({required id, required title, required message}) async => notes.add(title),
        describe: (_, _) async => null,
      );
      await bus.start();
    });
    tearDown(() async {
      await bus.shutdown();
      await data.delete(recursive: true);
    });

    Future<_WsClient> client() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async => bus.serve(await WebSocketTransformer.upgrade(r)));
      final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}');
      return _WsClient(ws, server);
    }

    test('verbindet nach Konfiguration, verteilt, sendet, zeichnet auf', () async {
      final a = await client();
      final b = await client();
      await bus.update({'enabled': true, 'host': '127.0.0.1', 'port': gw.port, 'flushSeconds': 0});
      await until(() => bus.state == 'connected');
      await until(() => a.states.any((s) => s['state'] == 'connected'));

      gw.indicate(writeOn);
      await until(() => a.frames.isNotEmpty && b.frames.isNotEmpty);
      expect(a.frames.first, writeOn);

      a.send(7, requestOff);
      await until(() => a.results.containsKey(7));
      expect(a.results[7], 0);
      expect(gw.requests.single, requestOff);
      // Bestätigung sehen beide – der andere Tab sieht das Telegramm als „gesendet“.
      await until(() => b.frames.length == 2);
      expect(b.frames.last[0], 0x2E);

      await bus.recorder.flush();
      final day = File('${data.path}/history/${Recorder.dayName(DateTime.now())}.ndjson');
      final lines = (await day.readAsLines()).map((l) => jsonDecode(l) as Map<String, Object?>).toList();
      expect(lines, hasLength(2));
      expect(lines.first['d'], 0x0A03);
      expect(lines.last['o'], true);
      await a.close();
      await b.close();
    });

    test('verbindet nach Trennung sofort neu', () async {
      await bus.update({'enabled': true, 'host': '127.0.0.1', 'port': gw.port});
      await until(() => bus.state == 'connected');
      gw.kick();
      await until(() => gw.connects == 2 && bus.state == 'connected');
      expect(bus.lastLost, isNotNull);
    });

    test('Tunnel für den Busmonitor freigeben, zurücknehmen und beim Trennen zurückholen', () async {
      final a = await client();
      await bus.update({'enabled': true, 'host': '127.0.0.1', 'port': gw.port});
      await until(() => bus.state == 'connected');
      a.release(true);
      await until(() => a.states.any((s) => s['state'] == 'yielded'));
      expect(bus.state, 'yielded');
      // Konfiguration ändern verbindet nicht vorzeitig neu.
      await bus.update({'tunnelAddress': '1.1.241'});
      expect(bus.state, 'yielded');
      var before = gw.connects;
      a.release(false);
      await until(() => gw.connects > before && bus.state == 'connected');

      a.release(true);
      await until(() => bus.state == 'yielded');
      before = gw.connects;
      await a.close();
      await until(() => gw.connects > before && bus.state == 'connected');
    });

    test('Ereignisse für Home Assistant: Bus verbunden, Wächter, Bus getrennt', () async {
      final events = <(String, Map<String, Object?>)>[];
      final dir = await Directory.systemTemp.createTemp('knx_bus_events');
      final own = BusService(
        dir,
        describe: (_, _) async => null,
        event: (type, data) async => events.add((type, data)),
        installation: {'id': 'a', 'name': 'Zuhause'},
      );
      await own.start();
      // Zweistufige Adressen: Das Ereignis nutzt den Stil des Projekts.
      await File('${dir.path}/catalog.json').writeAsString(jsonEncode({'style': 'twoLevel', 'groups': []}));
      await File('${dir.path}/watch_rules.json').writeAsString(
        jsonEncode({
          'rules': [
            {
              'id': 'licht',
              'address': 0x0A03,
              'label': '1/2/3 Licht',
              'check': {'any': true},
            },
          ],
        }),
      );
      await own.update({'enabled': true, 'host': '127.0.0.1', 'port': gw.port});
      await until(() => events.any((e) => e.$1 == 'knx_monitor_bus'));
      expect(events.first.$2, {'connected': true, 'state': 'connected', 'installation': 'Zuhause'});

      gw.indicate(writeOn);
      await until(() => events.any((e) => e.$1 == 'knx_monitor_watcher'));
      final hit = events.firstWhere((e) => e.$1 == 'knx_monitor_watcher').$2;
      expect(hit['watcher_id'], 'licht');
      expect(hit['address'], '1/515');
      expect(hit['source'], '1.1.5');
      expect(hit['raw'], '01');
      expect(hit['installation'], 'Zuhause');
      expect(hit.containsKey('value'), isFalse);

      // Gateway beendet den Tunnel und ist danach weg: genau ein „getrennt“,
      // nicht eines je Verbindungsversuch.
      gw.kick();
      await gw.close();
      await until(
        () => events.where((e) => e.$1 == 'knx_monitor_bus').length == 2,
        timeout: const Duration(seconds: 5),
      );
      await Future<void>.delayed(const Duration(seconds: 4));
      final bus = events.where((e) => e.$1 == 'knx_monitor_bus').toList();
      expect(bus, hasLength(2));
      expect(bus.last.$2['connected'], isFalse);
      await own.shutdown();
      await dir.delete(recursive: true);
    });

    test('Wächter: Mitteilung an Home Assistant und Treffer an die Ansicht', () async {
      await File('${data.path}/watch_rules.json').writeAsString(
        jsonEncode({
          'rules': [
            {
              'id': 'w1',
              'address': 0x0A03,
              'name': 'Licht',
              'label': '1/2/3 Licht',
              'check': {'any': true},
            },
          ],
        }),
      );
      final a = await client();
      await bus.update({'enabled': true, 'host': '127.0.0.1', 'port': gw.port});
      await until(() => bus.state == 'connected');
      gw.indicate(writeOn);
      await until(() => a.hits.isNotEmpty);
      expect(a.hits.single['ids'], ['w1']);
      expect((a.hits.single['line']! as Map)['d'], 0x0A03);
      expect(notes, contains('Wächter: Licht'));
      await a.close();
    });

    test('Gerätesitzung exklusiv je Ansicht', () async {
      final a = await client();
      final b = await client();
      await bus.update({'enabled': true, 'host': '127.0.0.1', 'port': gw.port});
      await until(() => bus.state == 'connected');
      final connect = Uint8List.fromList([0x11, 0x00, 0xB0, 0x60, 0x00, 0x00, 0x11, 0x05, 0x00, 0x80]);
      final disconnect = Uint8List.fromList([0x11, 0x00, 0xB0, 0x60, 0x00, 0x00, 0x11, 0x05, 0x00, 0x81]);
      a.send(1, connect);
      await until(() => a.results.containsKey(1));
      b.send(2, connect);
      await until(() => b.results.containsKey(2));
      expect(b.results[2], 4); // belegt
      a.send(3, disconnect);
      await until(() => a.results.containsKey(3));
      b.send(4, connect);
      await until(() => b.results.containsKey(4));
      expect(b.results[4], 0);
      await a.close();
      await b.close();
    });

    test('meldet Alarm einmal beim Wechsel in den aktiven Zustand', () async {
      await File('${data.path}/catalog.json').writeAsString(
        jsonEncode({
          'groups': [
            {
              'a': 0x0A03,
              'n': 'Rauchmelder Flur',
              'd': [1, 5],
            },
          ],
        }),
      );
      await bus.update({'enabled': true, 'host': '127.0.0.1', 'port': gw.port});
      await until(() => bus.state == 'connected');
      gw.indicate(writeOn);
      gw.indicate(writeOn);
      await until(() => notes.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(notes, ['Alarm: Rauchmelder Flur']);
    });

    test('Probeverbinden: gescheiterte neue Verbindung lässt die bisherige stehen', () async {
      await bus.update({'enabled': true, 'host': '127.0.0.1', 'port': gw.port});
      await until(() => bus.state == 'connected');
      final saved = await File('${data.path}/server.json').readAsString();
      final other = await FakeGateway.start();
      addTearDown(other.close);
      other.full = true;
      await expectLater(
        bus.update({'host': '127.0.0.1', 'port': other.port, 'probe': true}),
        throwsA(isA<BusProbeException>().having((e) => e.problem, 'problem', 'noFreeTunnel')),
      );
      expect(bus.config.port, gw.port);
      expect(await File('${data.path}/server.json').readAsString(), saved);
      await until(() => bus.state == 'connected' && gw.connects == 2);

      // Klappt sie, wird umgestellt – ohne zweiten Verbindungsaufbau.
      other.full = false;
      await bus.update({'host': '127.0.0.1', 'port': other.port, 'probe': true});
      await until(() => bus.state == 'connected');
      expect(bus.config.port, other.port);
      expect(other.connects, 2, reason: 'ein abgelehnter, ein erfolgreicher Versuch');
      expect(jsonDecode(await File('${data.path}/server.json').readAsString())['port'], other.port);
    });

    test('Grund des Fehlers im Status für die Verbindungshilfe', () async {
      gw.full = true;
      await bus.update({'enabled': true, 'host': '127.0.0.1', 'port': gw.port});
      await until(() => bus.error != null);
      expect(bus.status()['problem'], 'noFreeTunnel');
    });

    test('kaputte server.json: beiseitelegen, Sicherung übernehmen, sonst Hinweis im Status', () async {
      await bus.update({'enabled': true, 'host': '127.0.0.1', 'port': gw.port});
      await bus.update({'retentionDays': 30});
      await bus.shutdown();
      await File('${data.path}/server.json').writeAsString('{kaputt');
      bus = BusService(data, describe: (_, _) async => null);
      await bus.start();
      expect(bus.config.host, '127.0.0.1', reason: 'aus server.json.bak');
      expect(bus.configLost, isFalse);
      expect(data.listSync().map((f) => f.uri.pathSegments.last), contains(startsWith('server.json.corrupt-')));

      await bus.shutdown();
      await File('${data.path}/server.json').writeAsString('{kaputt');
      await File('${data.path}/server.json.bak').delete();
      bus = BusService(data, describe: (_, _) async => null);
      await bus.start();
      expect(bus.config.enabled, isFalse);
      expect(bus.status()['configLost'], isTrue);
      await bus.update({'enabled': true, 'host': '127.0.0.1', 'port': gw.port});
      expect(bus.status().containsKey('configLost'), isFalse);
    });

    test('ohne Gateway: nicht verbunden, versucht weiter', () async {
      await bus.update({'enabled': true, 'host': '127.0.0.1', 'port': 1});
      await until(() => bus.error != null, timeout: const Duration(seconds: 8));
      expect(bus.state, isNot('connected'));
    });

    test('Status gibt Passwörter nicht heraus', () async {
      await bus.update({
        'secure': {'userId': 2, 'userPassword': 'geheim'},
      });
      final json = jsonEncode(bus.status());
      expect(json, isNot(contains('geheim')));
      expect(json, contains('"hasUserPassword":true'));
      // leeres Passwort aus der App = unverändert
      await bus.update({
        'secure': {'userId': 2, 'userPassword': ''},
      });
      expect(bus.config.secure['userPassword'], 'geheim');
    });
  });

  group('Recorder', () {
    late Directory data;
    setUp(() async => data = await Directory.systemTemp.createTemp('knx_rec'));
    tearDown(() => data.delete(recursive: true));

    test('packt alte Tage, liest sie gleich, räumt nach Tagen auf', () async {
      final dir = Directory('${data.path}/history')..createSync();
      final now = DateTime.now();
      String day(int back) => Recorder.dayName(DateTime(now.year, now.month, now.day - back));
      File('${dir.path}/${day(1)}.ndjson').writeAsStringSync('{"t":1}\n');
      File('${dir.path}/${day(10)}.ndjson').writeAsStringSync('{"t":2}\n');
      File('${dir.path}/${day(0)}.ndjson').writeAsStringSync('{"t":3}\n');
      final rec = Recorder(data, retentionDays: 7);
      await rec.start();
      final names = dir.listSync().map((e) => e.uri.pathSegments.last).toSet();
      expect(names, {'${day(1)}.ndjson.gz', '${day(0)}.ndjson'});
      final unpacked = utf8.decode(gzip.decode(File('${dir.path}/${day(1)}.ndjson.gz').readAsBytesSync()));
      expect(unpacked, '{"t":1}\n');
    });

    test('Größenlimit löscht älteste Tage, nie heute', () async {
      final dir = Directory('${data.path}/history')..createSync();
      final now = DateTime.now();
      String day(int back) => Recorder.dayName(DateTime(now.year, now.month, now.day - back));
      final big = 'x' * (600 * 1024);
      for (final back in [0, 1, 2]) {
        File('${dir.path}/${day(back)}.ndjson.gz').writeAsStringSync(big);
      }
      final rec = Recorder(data, retentionDays: 30, maxMegabytes: 1)..retentionDays = 30;
      await rec.start();
      final names = dir.listSync().map((e) => e.uri.pathSegments.last).toSet();
      expect(names, {'${day(0)}.ndjson.gz'});
    });

    test('Auswertung: Heatmap, Tage, aktivste Adressen und Absender', () async {
      final rec = Recorder(data, flushInterval: const Duration(hours: 1));
      await rec.start();
      final now = DateTime.now();
      final monday9 = DateTime(now.year, now.month, now.day, 9);
      for (var i = 0; i < 3; i++) {
        rec.add({'t': monday9.microsecondsSinceEpoch, 's': 0x1105, 'd': 0x0A03, 'y': 2, 'x': '01'});
      }
      rec.add({'t': monday9.microsecondsSinceEpoch, 's': 0x1126, 'd': 0x0A04, 'y': 2, 'x': '01', 'o': true});
      final stats = await rec.stats(1);
      expect(stats['total'], 4);
      expect((stats['heatmap']! as List)[monday9.weekday - 1][9], 4);
      expect(stats['groups'], [
        [0x0A03, 3],
        [0x0A04, 1],
      ]);
      expect(stats['senders'], [
        [0x1105, 3],
      ]);
    });

    test('voller Puffer zählt verworfene Telegramme', () {
      final rec = Recorder(data, flushInterval: const Duration(hours: 1));
      for (var i = 0; i < Recorder.maxBuffered + 3; i++) {
        rec.add({'t': i});
      }
      expect(rec.dropped, 3);
    });
  });

  test('Verfügbarkeit erklärt Lücken', () async {
    final data = await Directory.systemTemp.createTemp('knx_avail');
    addTearDown(() => data.delete(recursive: true));
    final a = Availability(data);
    final t0 = DateTime(2026, 10, 1, 12);
    for (var m = 0; m < 5; m++) {
      await a.beat(connected: true, telegrams: 3, now: t0.add(Duration(minutes: m)));
    }
    // Verbindung weg
    await a.beat(connected: false, telegrams: 0, now: t0.add(const Duration(minutes: 5)));
    await a.beat(connected: false, telegrams: 0, now: t0.add(const Duration(minutes: 6)));
    await a.beat(connected: true, telegrams: 1, now: t0.add(const Duration(minutes: 7)));
    // Add-on lief eine Stunde nicht
    await a.beat(connected: true, telegrams: 2, now: t0.add(const Duration(minutes: 67)));
    final outages = await a.outages(t0, t0.add(const Duration(minutes: 67)));
    expect(outages.map((o) => o['kind']), ['disconnected', 'offline']);
    expect(outages.first['from'], t0.add(const Duration(minutes: 4)).millisecondsSinceEpoch);
    expect(outages.first['to'], t0.add(const Duration(minutes: 7)).millisecondsSinceEpoch);
  });
}

class _WsClient {
  _WsClient(this.ws, this.server) {
    ws.listen((m) {
      final b = m as List<int>;
      switch (b[0]) {
        case 0x01:
          frames.add(Uint8List.fromList(b.sublist(1)));
        case 0x02:
          states.add(jsonDecode(utf8.decode(b.sublist(1))) as Map<String, Object?>);
        case 0x03:
          hits.add(jsonDecode(utf8.decode(b.sublist(1))) as Map<String, Object?>);
        case 0x11:
          results[(b[1] << 8) | b[2]] = b[3];
      }
    });
  }

  final WebSocket ws;
  final HttpServer server;
  final frames = <Uint8List>[];
  final states = <Map<String, Object?>>[];
  final hits = <Map<String, Object?>>[];
  final results = <int, int>{};

  void send(int id, Uint8List cemi) => ws.add(Uint8List.fromList([0x10, id >> 8, id & 0xFF, ...cemi]));

  void release(bool release) => ws.add(Uint8List.fromList([0x12, release ? 1 : 0]));

  Future<void> close() async {
    await ws.close();
    await server.close(force: true);
  }
}
