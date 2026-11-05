import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/box.dart';
import 'package:test/test.dart';

/// Der echte Server als Prozess: was nur zusammen mit `bin/server.dart` gilt.
void main() {
  late Directory data;
  late Directory web;
  late int port;
  Process? server;

  Future<int> freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final free = socket.port;
    await socket.close();
    return free;
  }

  Future<(int, String)> get(String path) async {
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(Uri.parse('http://127.0.0.1:$port/$path'))).close();
      return (response.statusCode, await utf8.decodeStream(response));
    } finally {
      client.close();
    }
  }

  Future<void> start({Map<String, String> env = const {}}) async {
    server = await Process.start(
      'dart',
      ['run', 'bin/server.dart'],
      environment: {'PORT': '$port', 'DATA_DIR': data.path, 'WEB_DIR': web.path, ...env},
    );
    server!.stdout.drain<void>();
    server!.stderr.drain<void>();
    for (var i = 0; i < 300; i++) {
      try {
        await get('healthz');
        return;
      } on SocketException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    fail('Server antwortet nicht');
  }

  setUp(() async {
    data = await Directory.systemTemp.createTemp('knx_proc');
    web = await Directory.systemTemp.createTemp('knx_web');
    await File('${web.path}/index.html').writeAsString('<base href="/">');
    port = await freePort();
  });

  tearDown(() async {
    server?.kill(ProcessSignal.sigkill);
    await server?.exitCode;
    server = null;
    await data.delete(recursive: true);
    await web.delete(recursive: true);
  });

  test('Watchdog: Lebenszeichen ohne Ingress und ohne Daten, sonst bleibt alles gesperrt', () async {
    await start();
    final (status, body) = await get('healthz');
    expect(status, 200, reason: 'der Supervisor verlangt eine Antwort unter 300');
    expect(body, 'ok');
    expect((await get('api/bus')).$1, HttpStatus.forbidden);
    expect((await get('api/report')).$1, HttpStatus.forbidden);
    expect((await get('api/export/ets-xml?from=0&to=1000')).$1, HttpStatus.forbidden);
    expect((await get('')).$1, HttpStatus.forbidden);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('Box: Lebenszeichen ohne Anmeldung und ohne Daten, sonst bleibt alles gesperrt', () async {
    await start(env: {'BOX': '1', 'BOX_PASSWORD': 'test-pass', 'LAN_ACCESS': 'yes'});
    expect(await get('healthz'), (200, 'ok'));
    expect((await get('api/bus')).$1, HttpStatus.unauthorized);
    expect((await get('')).$1, HttpStatus.unauthorized);
  }, timeout: const Timeout(Duration(minutes: 2)));

  group('Box: Rollen', () {
    late String password;
    late String device;
    late String admin;

    Future<(int, String)> call(String method, String path, String auth, {Object? body}) async {
      final client = HttpClient();
      try {
        final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:$port/$path'));
        request.headers.set(HttpHeaders.authorizationHeader, auth);
        if (body is String) request.write(body);
        final response = await request.close();
        return (response.statusCode, await utf8.decodeStream(response));
      } finally {
        client.close();
      }
    }

    setUp(() async {
      await start(env: {'BOX': '1', 'BOX_PASSWORD': 'test-pass', 'LAN_ACCESS': 'yes'});
      password = 'Basic ${base64.encode(utf8.encode('x:test-pass'))}';
      final page = (await call('POST', 'pair', password, body: 'name=Gast')).$2;
      device = 'Bearer ${RegExp(r'key=([A-Za-z0-9_-]+)').firstMatch(page)![1]}';
      final paired = (await call('POST', 'api/box/pair', password, body: '{"name":"App"}')).$2;
      admin = 'Bearer ${(jsonDecode(paired) as Map)['key']}';
    });

    test('Busverbindung ändern nur mit Admin-Recht, Unverändertes geht durch', () async {
      expect((await call('GET', 'api/bus', device)).$1, 200);
      final (status, _) = await call('PUT', 'api/bus', device, body: '{"enabled":true,"host":"192.0.2.9"}');
      expect(status, HttpStatus.forbidden);
      expect((await call('GET', 'api/bus', admin)).$2, isNot(contains('192.0.2.9')));
      // Die App schickt beim Verbinden immer alles mit.
      expect((await call('PUT', 'api/bus', device, body: '{"probe":true}')).$1, 200);
      expect((await call('PUT', 'api/bus', admin, body: '{"retentionDays":30}')).$1, 200);
      expect((await call('PUT', 'api/bus', device, body: '{"retentionDays":30}')).$1, 200);
      expect((await call('PUT', 'api/bus', device, body: '{"retentionDays":31}')).$1, HttpStatus.forbidden);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Keyring: Gerät ohne Admin-Recht weder lesen noch schreiben noch sehen', () async {
      expect((await call('PUT', 'api/files/secure_keys.json', device, body: '{}')).$1, HttpStatus.forbidden);
      expect((await call('PUT', 'api/files/secure_keys.json', admin, body: '{"a":1}')).$1, HttpStatus.noContent);
      expect((await call('GET', 'api/files/secure_keys.json', admin)).$2, '{"a":1}');
      expect((await call('GET', 'api/files/secure_keys.json', device)).$1, HttpStatus.forbidden);
      expect((await call('DELETE', 'api/files/secure_keys.json', device)).$1, HttpStatus.forbidden);
      final (_, installations) = await call('GET', 'api/installations', device);
      final id = (jsonDecode(installations) as Map)['active'];
      expect((await call('GET', 'api/installations/$id/files/secure_keys.json', device)).$1, HttpStatus.forbidden);
      expect((await call('GET', 'api/installations/$id/files/secure_keys.json', admin)).$2, '{"a":1}');
      await call('PUT', 'api/files/catalog.json', admin, body: '{}');
      expect((await call('GET', 'api/files/./', device)).$1, isNot(200));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Schreiben: eigene Diagramme und Wächter ja, Projekt und Verlauf nein', () async {
      expect((await call('PUT', 'api/files/charts.json', device, body: '{}')).$1, HttpStatus.noContent);
      expect((await call('PUT', 'api/files/watch_rules.json', device, body: '{}')).$1, HttpStatus.noContent);
      expect((await call('PUT', 'api/files/catalog.json', device, body: '{}')).$1, HttpStatus.forbidden);
      expect((await call('POST', 'api/files/charts.json', device, body: 'x')).$1, HttpStatus.forbidden);
      expect((await call('DELETE', 'api/files/history/2026-10-30.ndjson', device)).$1, HttpStatus.forbidden);
      expect((await call('PUT', 'api/files/catalog.json', admin, body: '{"p":1}')).$1, HttpStatus.noContent);
      expect((await call('GET', 'api/files/catalog.json', device)).$2, '{"p":1}');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('ETS-Datei: lesen wie der Verlauf, auch ohne Admin-Recht', () async {
      final (_, installations) = await call('GET', 'api/installations', device);
      final id = (jsonDecode(installations) as Map)['active'];
      final now = DateTime.now();
      final day = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final line = jsonEncode({
        't': now.microsecondsSinceEpoch,
        's': 4402,
        'd': 4096,
        'y': 2,
        'x': '01',
        'm': true,
        'r': '2900BCE011321000010081',
      });
      File('${data.path}/installations/$id/history/$day.ndjson')
        ..createSync(recursive: true)
        ..writeAsStringSync('$line\n', mode: FileMode.append);
      final from = now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
      final to = now.add(const Duration(hours: 1)).millisecondsSinceEpoch;
      final (status, xml) = await call('GET', 'api/export/ets-xml?from=$from&to=$to', device);
      expect(status, 200);
      expect(xml, contains('RawData="2900BCE011321000010081"'));
      // Without admin rights only the active installation; whether another one exists stays open.
      expect((await call('GET', 'api/export/ets-xml?from=$from&to=$to&installation=gibts-nicht', device)).$1, 403);
      expect((await call('GET', 'api/export/ets-xml?from=$from&to=$to&installation=gibts-nicht', admin)).$1, 404);
      expect((await call('GET', 'api/export/ets-xml?from=$to&to=$from', device)).$1, 400);
      // The browser asks with check=1 before the download link: same checks, no body.
      expect(await call('GET', 'api/export/ets-xml?from=$from&to=$to&check=1', device), (204, ''));
      expect((await call('GET', 'api/export/ets-xml?from=$to&to=$from&check=1', device)).$1, 400);
      expect((await call('GET', 'api/export/ets-xml?from=$from&to=$to', 'Bearer falsch')).$1, HttpStatus.unauthorized);
      // The export settings next to it stay admin-only.
      expect((await call('PUT', 'api/export', device, body: '{}')).$1, HttpStatus.forbidden);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Roh-Relay nur mit Admin-Recht', () async {
      expect((await call('GET', 'ws', device)).$1, HttpStatus.forbidden);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('WebSockets: ohne Kompression, zu große Nachricht beendet die Verbindung', () async {
      for (final (path, auth) in [('ws', admin), ('ws/bus', device)]) {
        final ws = await WebSocket.connect(
          'ws://127.0.0.1:$port/$path',
          headers: {HttpHeaders.authorizationHeader: auth},
          compression: CompressionOptions.compressionDefault,
        );
        ws.listen((_) {}, onError: (Object _) {});
        // The server did not agree to permessage-deflate.
        expect(ws.extensions, isNot(contains('permessage-deflate')), reason: path);
        ws.add(List.filled(70 * 1024, 0));
        await ws.done.timeout(const Duration(seconds: 10));
        expect(ws.closeCode, WebSocketStatus.messageTooBig, reason: path);
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Installationen: ohne Admin-Recht nur die aktive', () async {
      final (status, created) = await call('POST', 'api/installations', admin, body: '{"name":"Kunde Alt"}');
      expect(status, HttpStatus.created);
      final other = (jsonDecode(created) as Map)['id'];
      final list = jsonDecode((await call('GET', 'api/installations', device)).$2) as Map;
      expect((list['list'] as List).map((i) => (i as Map)['id']), [list['active']]);
      expect(((jsonDecode((await call('GET', 'api/installations', admin)).$2) as Map)['list'] as List), hasLength(2));
      for (final path in [
        'api/bus/availability?installation=$other',
        'api/bus/stats?installation=$other',
        'api/export/ets-xml?all=1&installation=$other',
        'api/installations/$other/files/catalog.json',
      ]) {
        expect((await call('GET', path, device)).$1, HttpStatus.forbidden, reason: path);
      }
      expect((await call('GET', 'api/bus/availability?installation=$other', admin)).$1, 200);
      expect((await call('GET', 'api/bus/availability?installation=${list['active']}', device)).$1, 200);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Verfügbarkeit: unsinniger Zeitraum 400', () async {
      for (final q in ['from=0&to=8640000000000000', 'from=-5&to=10', 'from=10&to=5']) {
        expect((await call('GET', 'api/bus/availability?$q', device)).$1, HttpStatus.badRequest, reason: q);
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Wächter eines Geräts: mit seiner Id markiert, die des Admins bleiben', () async {
      await call('PUT', 'api/files/watch_rules.json', admin, body: '{"rules":[{"id":"a","address":1}]}');
      expect((await call('PUT', 'api/files/watch_rules.json', device, body: '{"rules":[]}')).$1, HttpStatus.noContent);
      expect(
        (await call('PUT', 'api/files/watch_rules.json', device, body: '{"rules":[{"id":"d","address":2}]}')).$1,
        HttpStatus.noContent,
      );
      final rules = (jsonDecode((await call('GET', 'api/files/watch_rules.json', admin)).$2) as Map)['rules'] as List;
      expect(rules.map((r) => (r as Map)['id']), ['a', 'd']);
      expect((rules.last as Map)['owner'], isA<String>());
      expect((rules.first as Map).containsKey('owner'), isFalse);
      // Nur ansehen: schreibt gar nichts.
      final page = (await call('POST', 'pair', password, body: 'name=Flur&viewOnly=1')).$2;
      final viewer = 'Bearer ${RegExp(r'key=([A-Za-z0-9_-]+)').firstMatch(page)![1]}';
      expect((await call('PUT', 'api/files/watch_rules.json', viewer, body: '{"rules":[]}')).$1, HttpStatus.forbidden);
      expect((await call('PUT', 'api/files/charts.json', viewer, body: '{}')).$1, HttpStatus.forbidden);
      // Wartungstermin nur mit Admin-Recht.
      expect((await call('POST', 'api/report/maintenance', device, body: '{"due":1}')).$1, HttpStatus.forbidden);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Box darf in keinem fremden Rahmen erscheinen', () async {
      final client = HttpClient();
      addTearDown(client.close);
      for (final path in ['', 'api/bus', 'healthz']) {
        final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/$path'));
        request.headers.set(HttpHeaders.authorizationHeader, device);
        final response = await request.close();
        await response.drain<void>();
        expect(response.headers.value('x-frame-options'), 'DENY', reason: path);
        expect(response.headers.value('content-security-policy'), "frame-ancestors 'none'", reason: path);
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  test('ALLOW_ALL: nur Anfragen an localhost (gegen DNS-Rebinding)', () async {
    await start(env: {'ALLOW_ALL': '1'});
    final client = HttpClient();
    addTearDown(client.close);
    Future<int> withHost(String host) async {
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/api/bus'));
      request.headers.host = host;
      request.headers.port = port;
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    }

    expect(await withHost('angreifer.example'), HttpStatus.forbidden);
    expect(await withHost('127.0.0.1.nip.io'), HttpStatus.forbidden);
    expect(await withHost('localhost'), 200);
    expect(await withHost('127.0.0.1'), 200);
    // Das Lebenszeichen bleibt für den Watchdog offen.
    expect((await get('healthz')).$1, 200);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('Box: HTTPS mit eigenem Zertifikat, Cookie nur dort „Secure“', () async {
    final dir = await Directory.systemTemp.createTemp('knx_tls');
    addTearDown(() => dir.delete(recursive: true));
    final made = await Process.run('bash', ['../../../box/files/tls-cert.sh', dir.path]);
    expect(made.exitCode, 0, reason: '${made.stderr}');
    final fp = (made.stdout as String).trim();
    final tlsPort = await freePort();
    await start(
      env: {
        'BOX': '1',
        'BOX_PASSWORD': 'test-pass',
        'LAN_ACCESS': 'yes',
        'TLS_CERT': '${dir.path}/cert.pem',
        'TLS_KEY': '${dir.path}/key.pem',
        'TLS_PORT': '$tlsPort',
      },
    );
    final url = Uri.parse('https://127.0.0.1:$tlsPort/api/box');
    final auth = 'Basic ${base64.encode(utf8.encode('x:test-pass'))}';

    Future<HttpClientResponse> over(HttpClient client) async {
      for (var i = 0; ; i++) {
        try {
          final request = await client.getUrl(url);
          request.headers.set(HttpHeaders.authorizationHeader, auth);
          return await request.close();
        } on SocketException {
          if (i > 50) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    }

    // Wie die App: niemandem vertrauen außer dem Fingerabdruck.
    String? seen;
    final pinned = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..badCertificateCallback = (cert, host, port) {
        seen = derFingerprint(cert.der);
        return seen == fp;
      };
    addTearDown(pinned.close);
    final response = await over(pinned);
    expect(response.statusCode, 200);
    expect(seen, fp);
    expect(response.headers[HttpHeaders.setCookieHeader]!.first, contains('Secure'));
    final info = jsonDecode(await utf8.decodeStream(response)) as Map;
    expect(info['tls'], {'port': tlsPort, 'fingerprint': fp});

    final wrong = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..badCertificateCallback = ((cert, host, port) => false);
    addTearDown(wrong.close);
    await expectLater(over(wrong), throwsA(isA<HandshakeException>()));

    // Über HTTP läuft es weiter, das Cookie bleibt ohne „Secure“.
    final plain = HttpClient();
    addTearDown(plain.close);
    final request = await plain.getUrl(Uri.parse('http://127.0.0.1:$port/api/box'));
    request.headers.set(HttpHeaders.authorizationHeader, auth);
    final overHttp = await request.close();
    expect(overHttp.statusCode, 200);
    expect(overHttp.headers[HttpHeaders.setCookieHeader]!.first, isNot(contains('Secure')));
    await overHttp.drain<void>();
  }, timeout: const Timeout(Duration(minutes: 2)));

  group('Neustarts', () {
    const env = {'ALLOW_ALL': '1'};

    Future<Map<String, Object?>> status() async => jsonDecode((await get('api/bus')).$2) as Map<String, Object?>;

    Future<void> stop(ProcessSignal signal) async {
      server!.kill(signal);
      await server!.exitCode;
      server = null;
    }

    test('SIGKILL zählt beim nächsten Start, SIGTERM nicht', () async {
      await start(env: env);
      expect((await status()).containsKey('restarts'), isFalse);
      await stop(ProcessSignal.sigterm);

      await start(env: env);
      expect((await status()).containsKey('restarts'), isFalse, reason: 'sauberer Stopp');
      await stop(ProcessSignal.sigkill);

      await start(env: env);
      final restarts = (await status())['restarts']! as Map;
      expect(restarts['count'], 1);
      expect((restarts['last'] as Map)['reason'], anyOf('unknown', 'host'));
      final list = jsonDecode((await get('api/restarts')).$2) as List;
      expect(list, hasLength(1));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('kaputte Dateien verhindern den Start nicht', () async {
      await Directory('${data.path}/running.json').create();
      await File('${data.path}/restarts.ndjson').writeAsBytes([0xFF, 0xFE, 0x00]);
      await start(env: env);
      expect((await get('healthz')).$1, 200);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  test('Web-App: ETag und gzip, unbekannte API 404, fremde Methoden 405', () async {
    await File('${web.path}/main.dart.js').writeAsString('console.log("x");\n' * 2000);
    await start(env: {'ALLOW_ALL': '1'});
    final client = HttpClient()..autoUncompress = false;
    addTearDown(client.close);
    Future<HttpClientResponse> send(String method, String path, [Map<String, String> headers = const {}]) async {
      final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:$port/$path'));
      headers.forEach(request.headers.set);
      return request.close();
    }

    final first = await send('GET', 'main.dart.js', {'Accept-Encoding': 'gzip'});
    final packed = await first.fold<List<int>>([], (a, b) => a..addAll(b));
    expect(first.statusCode, 200);
    expect(first.headers.value(HttpHeaders.contentEncodingHeader), 'gzip');
    expect(utf8.decode(gzip.decode(packed)), startsWith('console.log'));
    expect(packed.length, lessThan(36000 ~/ 10));
    final tag = first.headers.value(HttpHeaders.etagHeader)!;
    final again = await send('GET', 'main.dart.js', {'If-None-Match': tag});
    expect(again.statusCode, 304);
    await again.drain<void>();
    for (final (method, path, code) in [('GET', 'api/gibt-es-nicht', 404), ('TRACE', 'api/bus', 405)]) {
      final r = await send(method, path);
      expect(r.statusCode, code, reason: '$method $path');
      await r.drain<void>();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('Docker ohne BOX_PASSWORD startet nicht und loggt kein Passwort', () async {
    final result = await Process.run(
      'dart',
      ['run', 'bin/server.dart'],
      environment: {'PORT': '$port', 'DATA_DIR': data.path, 'WEB_DIR': web.path, 'BOX': '1'},
    );
    expect(result.exitCode, 78);
    expect('${result.stderr}', contains('BOX_PASSWORD fehlt'));
    expect('${result.stdout}', isNot(contains('Passwort')));
    expect(File('${data.path}/access.json').existsSync(), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('config.yaml zeigt den Watchdog auf das Lebenszeichen', () async {
    final config = await File('../config.yaml').readAsString();
    expect(config, contains('watchdog: http://[HOST]:[PORT:8765]/healthz'));
  });
}
