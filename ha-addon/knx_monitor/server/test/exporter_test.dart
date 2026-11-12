import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:knx_monitor_server/files.dart';
import 'package:test/test.dart';

class _Source implements ExportSource {
  @override
  bool connected = true;
  @override
  int recorderDropped = 3;
  @override
  Map<String, Object?>? busmon;
  @override
  bool timeKnown = true;
  @override
  String formatGroup(int group) => '1/0/$group';
  @override
  String? nameOf(int group) => group == 1 ? 'Temperatur "Küche", EG' : null;
  @override
  (int, int?)? dptOf(int group) => group == 1 ? (9, 1) : null;
}

void main() {
  late Directory data;
  late _Source source;
  late List<String> logged;
  late DataExporter exporter;
  final t = DateTime(2026, 10, 30, 12);

  Map<String, Object?> line({int d = 1, int s = 0x1105, String x = '0c1a', bool rp = false, int y = 2}) => {
    't': t.microsecondsSinceEpoch,
    's': s,
    'd': d,
    'y': y,
    'x': x,
    if (rp) 'rp': true,
  };

  setUp(() async {
    data = await Directory.systemTemp.createTemp('knx_export');
    source = _Source();
    logged = [];
    exporter = DataExporter(data, source: source, log: logged.add, now: () => t);
  });
  tearDown(() async {
    await exporter.stop();
    await data.delete(recursive: true);
  });

  Future<int> freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  test('Standard aus: kein Port, kein Versand, keine Zähler', () async {
    final port = await freePort();
    await exporter.start();
    exporter.settings.prometheusPort = port;
    exporter.add(line());
    await exporter.flush();
    expect(exporter.telegrams, 0);
    expect(exporter.status()['prometheusRunning'], isFalse);
    await expectLater(Socket.connect(InternetAddress.loopbackIPv4, port), throwsA(isA<SocketException>()));
    expect(await File('${data.path}/export.json').exists(), isFalse);
  });

  group('Prometheus', () {
    late int port;
    Future<(int, String)> scrape({String? token, String path = 'metrics'}) async {
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/$path'));
        if (token != null) request.headers.set('authorization', 'Bearer $token');
        final response = await request.close();
        return (response.statusCode, await utf8.decodeStream(response));
      } finally {
        client.close();
      }
    }

    setUp(() async => port = await freePort());

    test('erzeugt ein Token, nennt es einmal und antwortet nie ohne', () async {
      final token = await exporter.update({'prometheus': true, 'prometheusPort': port});
      expect(token, isNotNull);
      expect(exporter.status().toString(), isNot(contains(token!)));
      expect((await scrape()).$1, HttpStatus.unauthorized);
      expect((await scrape(token: 'falsch')).$1, HttpStatus.unauthorized);
      expect((await scrape(token: token, path: 'anderes')).$1, HttpStatus.notFound);
      final (status, body) = await scrape(token: token);
      expect(status, 200);
      expect(body, contains('knx_monitor_connected 1'));
      // Beim nächsten Speichern bleibt es.
      expect(await exporter.update({'prometheusPort': port}), isNull);
      expect((await scrape(token: token)).$1, 200);
    });

    test('ohne includeValues nur Zähler des Busses, keine Anlagendaten', () async {
      final token = (await exporter.update({'prometheus': true, 'prometheusPort': port}))!;
      exporter
        ..add(line(rp: true))
        ..add(line());
      final body = (await scrape(token: token)).$2;
      expect(body, contains('knx_monitor_telegrams_total 2'));
      expect(body, contains('knx_monitor_repeats_total 1'));
      expect(body, contains('knx_monitor_recorder_dropped_total 3'));
      expect(body, isNot(contains('Küche')));
      expect(body, isNot(contains('1/0/1')));
      expect(body, isNot(contains('1.1.5')));
    });

    test('mit includeValues Werte, Namen sauber maskiert', () async {
      final token = (await exporter.update({'prometheus': true, 'prometheusPort': port, 'includeValues': true}))!;
      exporter
        ..add(line())
        ..add(line(y: 0, d: 2, x: '00'));
      final body = (await scrape(token: token)).$2;
      expect(body, contains(r'knx_monitor_group_value{ga="1/0/1",name="Temperatur \"Küche\", EG"} '));
      expect(body, contains('knx_monitor_sender_telegrams_total{source="1.1.5"} 2'));
      expect(body, isNot(contains('1/0/2')), reason: 'Leseanfrage hat keinen Wert');
    });

    test('belegter Port stört nichts, steht im Status', () async {
      final blocker = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      addTearDown(blocker.close);
      await exporter.update({'prometheus': true, 'prometheusPort': port});
      expect(exporter.status()['prometheusError'], 'bind');
      exporter.add(line());
      expect(exporter.telegrams, 1);
    });

    test('nur aus dem lokalen Netz', () {
      for (final local in ['10.1.2.3', '172.16.0.1', '192.168.1.1', '100.64.0.1', '169.254.0.1', '127.0.0.1']) {
        expect(isLocalPeer(InternetAddress(local)), isTrue, reason: local);
      }
      for (final remote in ['8.8.8.8', '172.32.0.1', '100.128.0.1', '2001:4860:4860::8888']) {
        expect(isLocalPeer(InternetAddress(remote)), isFalse, reason: remote);
      }
    });
  });

  group('InfluxDB', () {
    late HttpServer target;
    late List<HttpRequest> requests;
    late List<String> bodies;
    var answer = 204;
    var port = 0;

    setUp(() async {
      requests = [];
      bodies = [];
      answer = 204;
      target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = target.port;
      target.listen((r) async {
        requests.add(r);
        bodies.add(await utf8.decodeStream(r));
        r.response.statusCode = answer;
        await r.response.close();
      });
    });
    tearDown(() => target.close(force: true));

    Map<String, Object?> v2([Map<String, Object?> extra = const {}]) => {
      'influx': true,
      'influxUrl': 'http://127.0.0.1:$port/db',
      'influxOrg': 'haus',
      'influxBucket': 'knx',
      'influxToken': 'tk_secret',
      ...extra,
    };

    test('v2: Ziel, Token im Kopf, Zähler; Werte nur mit Schalter', () async {
      await exporter.update(v2());
      exporter.add(line());
      await exporter.flush();
      final r = requests.single;
      expect(r.uri.path, '/db/api/v2/write');
      expect(r.uri.queryParameters, {'org': 'haus', 'bucket': 'knx', 'precision': 'ms'});
      expect(r.headers.value('authorization'), 'Token tk_secret');
      expect(bodies.single, contains('knx_monitor_bus connected=1i,telegrams_total=1i'));
      expect(bodies.single, isNot(contains('Küche')));
    });

    test('v1: Datenbank statt Organisation', () async {
      await exporter.update({'influx': true, 'influxUrl': 'http://127.0.0.1:$port', 'influxDatabase': 'knx'});
      await exporter.flush();
      expect(requests.single.uri.path, '/write');
      expect(requests.single.uri.queryParameters['db'], 'knx');
      expect(requests.single.headers.value('authorization'), isNull);
    });

    test('mit includeValues Zeile je Wert, Tags maskiert', () async {
      await exporter.update(v2({'includeValues': true}));
      exporter.add(line());
      await exporter.flush();
      expect(bodies.single, contains(r'knx_monitor_group,ga=1/0/1,name=Temperatur\ "Küche"\,\ EG value='));
      expect(bodies.single, contains(' ${t.millisecondsSinceEpoch}'));
    });

    test('Fehlschlag: Puffer bleibt, Abstand wächst, Log ohne Adresse und Token', () async {
      answer = 500;
      await exporter.update(v2({'includeValues': true}));
      exporter.add(line());
      await exporter.flush();
      expect(exporter.influxError, 'http500');
      expect(exporter.status()['buffered'], greaterThan(0));
      final calls = requests.length;
      await exporter.flush(); // noch in der Wartezeit
      expect(requests.length, calls);
      for (final message in logged) {
        expect(message, isNot(contains('tk_secret')));
        expect(message, isNot(contains('127.0.0.1')));
      }
      expect(jsonEncode(exporter.status()), isNot(contains('tk_secret')));
    });

    test('nicht erreichbar: flush kehrt zurück, Puffer ist begrenzt', () async {
      await exporter.update(v2({'includeValues': true}));
      await target.close(force: true);
      for (var i = 0; i < DataExporter.maxBuffered + 50; i++) {
        exporter.add(line());
      }
      expect(exporter.droppedLines, 50);
      await exporter.flush();
      expect(exporter.influxError, 'network');
      expect(exporter.status()['buffered'], DataExporter.maxBuffered);
    });

    test('ohne gesicherte Uhr nichts senden', () async {
      source.timeKnown = false;
      await exporter.update(v2());
      await exporter.flush();
      expect(requests, isEmpty);
    });

    test('ungültiges Ziel wird abgelehnt, nichts ändert sich', () async {
      for (final url in ['ftp://x', '', 'http://u:p@host/']) {
        await expectLater(exporter.update(v2({'influxUrl': url})), throwsFormatException, reason: url);
      }
      await expectLater(exporter.update({'influx': true, 'influxUrl': 'http://x'}), throwsFormatException);
      expect(exporter.settings.influx, isFalse);
      expect(await File('${data.path}/export.json').exists(), isFalse);
    });
  });

  group('Ablage und Schnittstelle', () {
    late HttpServer server;
    var admin = true;

    setUp(() async {
      admin = true;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (await serveExport(request, exporter, admin: admin)) return;
        await serveFile(request, data, request.uri.path.substring('/api/files/'.length));
      });
    });
    tearDown(() => server.close(force: true));

    Future<(int, String)> call(String method, String path, [Object? body]) async {
      final client = HttpClient();
      try {
        final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:${server.port}/$path'));
        if (body != null) request.write(body is String ? body : jsonEncode(body));
        final response = await request.close();
        return (response.statusCode, await utf8.decodeStream(response));
      } finally {
        client.close();
      }
    }

    test('Tokens gehen nur hinein; Datei ist über die Ablage gesperrt', () async {
      final (status, text) = await call('PUT', 'api/export', {
        'influx': true,
        'influxUrl': 'http://192.168.1.2:8086',
        'influxOrg': 'o',
        'influxBucket': 'b',
        'influxToken': 'tk_secret',
      });
      expect(status, 200);
      expect(text, isNot(contains('tk_secret')));
      expect(((jsonDecode(text) as Map)['settings'] as Map)['hasInfluxToken'], isTrue);
      expect((await call('GET', 'api/export')).$2, isNot(contains('tk_secret')));
      expect((await call('GET', 'api/files/export.json')).$1, HttpStatus.forbidden);
      // Leer heißt „unverändert“, ausdrücklich gelöscht ist gelöscht.
      final (_, again) = await call('PUT', 'api/export', {'influxToken': ''});
      expect(((jsonDecode(again) as Map)['settings'] as Map)['hasInfluxToken'], isTrue);
      final (_, cleared) = await call('PUT', 'api/export', {'clearInfluxToken': true});
      expect(((jsonDecode(cleared) as Map)['settings'] as Map)['hasInfluxToken'], isFalse);
    });

    test('MQTT-Telegrammstrom: nur Admin, ohne Broker 404, unpassende Werte 422', () async {
      expect((await call('PUT', 'api/export/mqtt', {'enabled': true})).$1, HttpStatus.notFound);
      final seen = <Map<String, Object?>>[];
      exporter
        ..mqttTelegrams = (() => {'enabled': seen.isNotEmpty})
        ..mqttConfigure = (changes) async {
          if (changes['filter'] == 'quatsch') throw const FormatException('Filter nicht lesbar');
          seen.add(changes);
          return {'enabled': true};
        };
      admin = false;
      expect((await call('PUT', 'api/export/mqtt', {'enabled': true})).$1, HttpStatus.forbidden);
      expect(seen, isEmpty);
      admin = true;
      final (bad, error) = await call('PUT', 'api/export/mqtt', {'filter': 'quatsch'});
      expect(bad, HttpStatus.unprocessableEntity);
      expect(error, contains('Filter nicht lesbar'));
      expect((await call('PUT', 'api/export/mqtt', [1])).$1, HttpStatus.badRequest);
      expect((await call('PUT', 'api/export/mqtt', '{kein json')).$1, HttpStatus.badRequest);
      final (ok, text) = await call('PUT', 'api/export/mqtt', {'enabled': true});
      expect(ok, 200);
      expect(((jsonDecode(text) as Map)['mqttTelegrams'] as Map)['enabled'], isTrue);
      expect(seen.single, {'enabled': true});
    });

    test('neues InfluxDB-Ziel ohne neues Token: das alte Token geht nicht mit', () async {
      bool hasToken(String text) => ((jsonDecode(text) as Map)['settings'] as Map)['hasInfluxToken'] == true;
      final first = {
        'influx': true,
        'influxUrl': 'http://192.168.1.2:8086',
        'influxOrg': 'o',
        'influxBucket': 'b',
        'influxToken': 'tk_secret',
      };
      expect(hasToken((await call('PUT', 'api/export', first)).$2), isTrue);
      expect(hasToken((await call('PUT', 'api/export', {...first, 'influxToken': ''})).$2), isTrue);
      final moved = {...first, 'influxUrl': 'http://192.168.1.3:8086', 'influxToken': ''};
      expect(hasToken((await call('PUT', 'api/export', moved)).$2), isFalse);
      expect(hasToken((await call('PUT', 'api/export', {...moved, 'influxToken': 'tk_new'})).$2), isTrue);
    });

    test('nur Admin ändert; ungültiges Ziel 422', () async {
      admin = false;
      expect((await call('PUT', 'api/export', {'influx': true})).$1, HttpStatus.forbidden);
      expect((await call('POST', 'api/export/test', const {})).$1, HttpStatus.forbidden);
      admin = true;
      expect(
        (await call('PUT', 'api/export', {'influx': true, 'influxUrl': 'nix'})).$1,
        HttpStatus.unprocessableEntity,
      );
    });

    test('Einstellungen überleben den Neustart, kaputte Datei heißt aus', () async {
      await exporter.update({'includeValues': true});
      final next = DataExporter(data, source: source, log: logged.add);
      await next.start();
      expect(next.settings.includeValues, isTrue);
      await File('${data.path}/export.json').writeAsString('{kaputt');
      final broken = DataExporter(data, source: source, log: logged.add);
      await broken.start();
      expect(broken.active, isFalse);
      expect(broken.settings.includeValues, isFalse);
    });
  });

  group('Grafana-Vorlage', () {
    test('Prometheus: alle Abfragen nutzen Metriken, die es gibt', () async {
      final port = await freePort();
      await exporter.update({'prometheus': true, 'prometheusPort': port, 'includeValues': true});
      source.busmon = {'acks': 1};
      exporter.add(line());
      final known = RegExp(
        r'^# TYPE (\S+)',
        multiLine: true,
      ).allMatches(exporter.prometheusText()).map((m) => m[1]).toSet();
      final board = jsonDecode(jsonEncode(grafanaDashboard('prometheus'))) as Map<String, Object?>;
      expect(board['title'], 'Busclear');
      expect((board['__inputs']! as List).cast<Map<Object?, Object?>>().single['pluginId'], 'prometheus');
      final used = <String>{};
      for (final panel in (board['panels']! as List).cast<Map<Object?, Object?>>()) {
        for (final target in (panel['targets'] as List).cast<Map<Object?, Object?>>()) {
          used.addAll(RegExp(r'knx_monitor_\w+').allMatches(target['expr'] as String).map((m) => m[0]!));
        }
      }
      expect(used, isNotEmpty);
      expect(known.containsAll(used), isTrue, reason: 'unbekannt: ${used.difference(known)}');
    });

    test('InfluxDB: Felder stimmen mit dem Line Protocol überein', () async {
      await exporter.update({
        'influx': true,
        'influxUrl': 'http://127.0.0.1:1',
        'influxOrg': 'o',
        'influxBucket': 'b',
        'includeValues': true,
      });
      exporter.add(line());
      final board = grafanaDashboard('influxdb');
      final queries = [
        for (final panel in (board['panels']! as List).cast<Map<Object?, Object?>>())
          for (final target in (panel['targets'] as List).cast<Map<Object?, Object?>>()) target['query'] as String,
      ];
      expect(queries, isNotEmpty);
      const fields = {
        'knx_monitor_bus': {'connected', 'telegrams_total', 'repeats_total', 'dropped_total'},
        'knx_monitor_group': {'value'},
      };
      for (final q in queries) {
        final m = RegExp(r'_measurement == "(\w+)" and r\._field == "(\w+)"').firstMatch(q)!;
        expect(fields[m[1]], contains(m[2]), reason: q);
      }
    });

    test('unbekannte Art fällt auf Prometheus zurück, kein Geheimnis in der Vorlage', () async {
      expect(grafanaDashboard('unbekannt')['uid'], 'knx-monitor-prometheus');
      expect(jsonEncode(grafanaDashboard('influxdb')), isNot(contains('tk_')));
    });
  });

  test('Export stört den Bus nicht: Zeilen ohne Felder werden übergangen', () async {
    await exporter.update({'prometheus': true, 'prometheusPort': await freePort(), 'includeValues': true});
    exporter.add({'t': 'kein Wert'});
    exporter.add(line());
    expect(exporter.telegrams, greaterThan(0));
  });

  test('BusService: Export ist aus und im Status der Datei nicht vorhanden', () async {
    final bus = BusService(data);
    await bus.start();
    expect(bus.exporter.active, isFalse);
    await bus.shutdown();
    expect(await File('${data.path}/export.json').exists(), isFalse);
  });
}
