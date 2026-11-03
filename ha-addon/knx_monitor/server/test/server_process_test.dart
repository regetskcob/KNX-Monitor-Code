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

    test('Roh-Relay nur mit Admin-Recht', () async {
      expect((await call('GET', 'ws', device)).$1, HttpStatus.forbidden);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

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

  test('config.yaml zeigt den Watchdog auf das Lebenszeichen', () async {
    final config = await File('../config.yaml').readAsString();
    expect(config, contains('watchdog: http://[HOST]:[PORT:8765]/healthz'));
  });
}
