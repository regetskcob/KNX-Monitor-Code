import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/box.dart';
import 'package:test/test.dart';

/// Aufkleber-Passwort, Sperre je Absender und HTTPS-Angaben der Box.
void main() {
  late Directory data;
  late HttpServer server;
  late BoxAccess access;
  final client = HttpClient();

  String basic(String password) => 'Basic ${base64.encode(utf8.encode('box:$password'))}';

  Future<void> open({String? initial = 'aufkleber1', bool sticker = true, int iterations = 1000}) async {
    access = await BoxAccess.open(
      data,
      initialPassword: initial,
      name: 'KNX-Box-1A2B',
      iterations: iterations,
      sticker: sticker,
      // Mehrere Absender über Loopback: im Kopf statt in der Adresse.
      peerOf: (r) => r.headers.value('x-peer') ?? 'a',
    );
    await access.settled;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final role = await access.guard(request);
      if (role == null || await access.handle(request, role)) return;
      request.response.write('ok ${role.name}');
      await request.response.close();
    });
  }

  Future<(int, String, HttpHeaders)> send(
    String path, {
    String? auth,
    String method = 'GET',
    String? body,
    String? accept,
    String? peer,
  }) async {
    final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:${server.port}$path'));
    request.followRedirects = false;
    if (auth != null) request.headers.set(HttpHeaders.authorizationHeader, auth);
    if (accept != null) request.headers.set(HttpHeaders.acceptHeader, accept);
    if (peer != null) request.headers.set('x-peer', peer);
    if (body != null) request.write(body);
    final response = await request.close();
    return (response.statusCode, await utf8.decodeStream(response), response.headers);
  }

  Future<void> reopen({bool sticker = true, String? initial = 'aufkleber1'}) async {
    await access.flush();
    await server.close(force: true);
    await open(sticker: sticker, initial: initial);
  }

  setUp(() async {
    data = await Directory.systemTemp.createTemp('box_security');
  });

  tearDown(() async {
    await server.close(force: true);
    await access.flush();
    await data.delete(recursive: true);
  });

  group('neue Box: Passwort vom Aufkleber', () {
    test('Koppeln geht, sonst nichts bis zum eigenen Passwort', () async {
      await open();
      expect(access.mustChangePassword, isTrue);
      expect(access.changeRequired, isTrue);

      expect((await send('/api/bus', auth: basic('aufkleber1'))).$1, HttpStatus.preconditionRequired);
      final (pairStatus, pairBody, _) = await send(
        '/api/box/pair',
        auth: basic('aufkleber1'),
        method: 'POST',
        body: '{"name":"iPad"}',
      );
      expect(pairStatus, 200);
      final key = (jsonDecode(pairBody) as Map)['key'] as String;
      final bearer = 'Bearer $key';

      // Auch der Gerätezugang kommt vorher nur bis zum Ändern.
      expect((await send('/api/bus', auth: bearer)).$1, HttpStatus.preconditionRequired);
      expect((await send('/ws/bus', auth: bearer)).$1, HttpStatus.preconditionRequired);
      expect((await send('/api/files/secure_keys.json', auth: bearer)).$1, HttpStatus.preconditionRequired);
      final info = jsonDecode((await send('/api/box', auth: bearer)).$2) as Map;
      expect(info['mustChangePassword'], isTrue);
      expect(info['passwordChangeRequired'], isTrue);

      // Dasselbe Passwort ist kein eigenes.
      expect(
        (await send('/api/box/password', auth: bearer, method: 'POST', body: '{"password":"aufkleber1"}')).$1,
        HttpStatus.badRequest,
      );
      expect(access.mustChangePassword, isTrue);

      expect(
        (await send('/api/box/password', auth: bearer, method: 'POST', body: '{"password":"eigenes-pw-1"}')).$1,
        200,
      );
      expect(access.mustChangePassword, isFalse);
      expect((await send('/api/bus', auth: bearer)).$2, 'ok admin');
      expect((await send('/api/bus', auth: basic('aufkleber1'))).$1, 401);
      expect((await send('/api/bus', auth: basic('eigenes-pw-1'), peer: 'b')).$2, 'ok admin');
      // Der Host räumt danach die Boot-Partition auf.
      expect(await File('${data.path}/sticker-scrub').readAsString(), 'box\n');
    });

    test('der Stand übersteht einen Neustart', () async {
      await open();
      await reopen();
      expect(access.changeRequired, isTrue, reason: 'sonst reicht Strom aus und wieder an');
      await access.changePassword('eigenes-pw-1');
      await reopen();
      expect(access.mustChangePassword, isFalse);
    });

    test('mit dem Aufkleber gekoppelte fremde Geräte fallen beim Ändern weg', () async {
      await open();
      final (_, mine, _) = await send(
        '/api/box/pair',
        auth: basic('aufkleber1'),
        method: 'POST',
        body: '{"name":"ich"}',
      );
      final (_, theirs, _) = await send(
        '/api/box/pair',
        auth: basic('aufkleber1'),
        method: 'POST',
        body: '{"name":"Foto"}',
      );
      final myKey = 'Bearer ${(jsonDecode(mine) as Map)['key']}';
      final theirKey = 'Bearer ${(jsonDecode(theirs) as Map)['key']}';
      expect(
        (await send('/api/box/password', auth: myKey, method: 'POST', body: '{"password":"eigenes-pw-1"}')).$1,
        200,
      );
      expect((await send('/api/bus', auth: myKey)).$2, 'ok admin');
      expect((await send('/api/bus', auth: theirKey, peer: 'b')).$1, 401);
    });

    test('Browser landet auf /pair und sieht nur das Passwortfeld', () async {
      await open();
      final (status, _, headers) = await send('/', auth: basic('aufkleber1'), accept: 'text/html');
      expect(status, HttpStatus.seeOther);
      expect(headers.value(HttpHeaders.locationHeader), '/pair');
      final (pageStatus, page, _) = await send('/pair', auth: basic('aufkleber1'), accept: 'text/html');
      expect(pageStatus, 200);
      expect(page, contains('/pair/password'));
      expect(page, isNot(contains('action="/pair/revoke"')));
      expect((await send('/pair', auth: basic('aufkleber1'), method: 'POST', body: 'name=x')).$1, 428);
      expect(
        (await send('/pair/password', auth: basic('aufkleber1'), method: 'POST', body: 'password=eigenes-pw-1')).$1,
        200,
      );
      expect(access.mustChangePassword, isFalse);
    });

    test('ohne Aufkleber (Docker) keine Pflicht und kein Aufräumen', () async {
      await open(sticker: false);
      expect(access.mustChangePassword, isFalse);
      expect((await send('/api/bus', auth: basic('aufkleber1'))).$2, 'ok admin');
      await access.changePassword('eigenes-pw-1');
      expect(await File('${data.path}/sticker-scrub').exists(), isFalse);
    });
  });

  group('aktualisierte Box aus 1.9.1', () {
    Future<void> oldBox(String password) async {
      await open(sticker: false, initial: password);
      await access.pair('altes iPad', admin: true);
      await access.flush();
      await server.close(force: true);
    }

    test('Passwort vom Aufkleber gilt noch: fragt nach, sperrt nicht', () async {
      await oldBox('aufkleber1');
      await open();
      expect(access.mustChangePassword, isTrue);
      expect(access.changeRequired, isFalse);
      expect((await send('/api/bus', auth: basic('aufkleber1'))).$2, 'ok admin');
      expect(access.devices, hasLength(1));

      // Einmal zum Ändern geschickt; danach geht es weiter.
      final (first, _, headers) = await send('/', auth: basic('aufkleber1'), accept: 'text/html');
      expect(first, HttpStatus.seeOther);
      final cookie = headers[HttpHeaders.setCookieHeader]!.first.split(';').first;
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}/'));
      request.headers
        ..set(HttpHeaders.acceptHeader, 'text/html')
        ..set(HttpHeaders.cookieHeader, cookie);
      final response = await request.close();
      expect(response.statusCode, 200);
      await response.drain<void>();

      await access.changePassword('eigenes-pw-1');
      expect(access.mustChangePassword, isFalse);
      expect(access.devices, hasLength(1), reason: 'bei freiwilligem Ändern bleiben die Geräte');
      expect(await File('${data.path}/sticker-scrub').readAsString(), 'box\n');
    });

    test('schon geändert: keine Frage, alte Angaben kommen von der Karte', () async {
      await oldBox('eigenes-pw-1');
      await open(initial: 'aufkleber1');
      expect(access.mustChangePassword, isFalse);
      expect(access.changeRequired, isFalse);
      expect((await send('/api/bus', auth: basic('eigenes-pw-1'))).$2, 'ok admin');
      expect(await File('${data.path}/sticker-scrub').readAsString(), 'box\n');
    });

    test('Prüfung nur einmal', () async {
      await oldBox('eigenes-pw-1');
      await open(initial: 'aufkleber1');
      await File('${data.path}/sticker-scrub').delete();
      await reopen(initial: 'aufkleber1');
      expect(await File('${data.path}/sticker-scrub').exists(), isFalse);
    });
  });

  group('Wiederherstellen und WLAN', () {
    test('Passwort von der SD-Karte: gilt, Geräte bleiben, Datei weg', () async {
      await open();
      await access.pair('iPad', admin: true);
      await access.flush();
      await server.close(force: true);
      await File('${data.path}/password-reset').writeAsString('neu-von-karte\n');
      await open(initial: null);
      expect(access.mustChangePassword, isFalse);
      expect(access.devices, hasLength(1));
      expect(await File('${data.path}/password-reset').exists(), isFalse);
      expect((await send('/api/bus', auth: basic('neu-von-karte'))).$2, 'ok admin');
    });

    test('zu kurzes Passwort von der Karte gilt nicht', () async {
      await open();
      await access.changePassword('eigenes-pw-1');
      await reopen();
      await access.flush();
      await server.close(force: true);
      await File('${data.path}/password-reset').writeAsString('kurz\n');
      await open(initial: null);
      expect(await File('${data.path}/password-reset').exists(), isFalse);
      expect((await send('/api/bus', auth: basic('eigenes-pw-1'))).$2, 'ok admin');
    });

    test('POST /api/box/wifi: legt die Bitte für den Host ab, prüft das Passwort', () async {
      await open();
      await access.changePassword('eigenes-pw-1');
      final auth = basic('eigenes-pw-1');
      for (final bad in ['kurz', 'mit leerzeichen', r'mit$dollar', 'mit"quote', "mit'quote", r'mit\slash', 'x' * 64]) {
        expect(
          (await send('/api/box/wifi', auth: auth, method: 'POST', body: jsonEncode({'password': bad}))).$1,
          HttpStatus.badRequest,
          reason: bad,
        );
      }
      expect(await File('${data.path}/wifi-request').exists(), isFalse);
      expect((await send('/api/box/wifi', auth: auth, method: 'POST', body: '{"password":"Neues-Wlan;1:x"}')).$1, 200);
      expect(await File('${data.path}/wifi-request').readAsString(), 'Neues-Wlan;1:x\n');
    });

    test('Docker: kein WLAN zum Ändern', () async {
      await open(sticker: false);
      expect(
        (await send(
          '/api/box/wifi',
          auth: basic('aufkleber1'),
          method: 'POST',
          body: '{"password":"Neues-Wlan-1"}',
        )).$1,
        HttpStatus.conflict,
      );
    });

    test('Gerät ohne Admin-Recht ändert kein WLAN', () async {
      await open();
      await access.changePassword('eigenes-pw-1');
      final key = await access.pair('Gast');
      expect(
        (await send('/api/box/wifi', auth: 'Bearer $key', method: 'POST', body: '{"password":"Neues-Wlan-1"}')).$1,
        HttpStatus.forbidden,
      );
    });
  });

  group('Sperre je Absender', () {
    test('Fehlversuche des einen bremsen den anderen nicht', () async {
      await open(sticker: false);
      for (var i = 0; i < 5; i++) {
        await send('/api/bus', auth: basic('falsch'), peer: 'a');
      }
      expect((await send('/api/bus', auth: basic('aufkleber1'), peer: 'a')).$1, 429);
      expect((await send('/api/bus', auth: basic('aufkleber1'), peer: 'b')).$1, 200);
    });

    test('viele gleichzeitige Prüfungen werden abgewiesen, statt den Pi zu belegen', () async {
      await open(sticker: false, iterations: 200000);
      final results = await Future.wait([
        for (var i = 0; i < 8; i++) send('/api/bus', auth: basic('falsch-$i'), peer: 'a').then((r) => r.$1),
      ]);
      expect(results.where((s) => s == 429).length, greaterThanOrEqualTo(5));
      expect(results.where((s) => s == 401).length, lessThanOrEqualTo(3));
    }, timeout: const Timeout(Duration(minutes: 1)));
  });

  group('HTTPS-Angaben', () {
    test('Kopplungslink: Fingerabdruck, Port 443 lässt die HTTP-Adresse für ältere Apps', () async {
      await open(sticker: false);
      access.tlsFingerprint = 'abc';
      final link = access.pairingLink('10.42.0.1', 'k');
      expect(link.queryParameters['url'], 'http://10.42.0.1/');
      expect(link.queryParameters['fp'], 'abc');
    });

    test('anderer Port: HTTPS-Adresse im Link', () async {
      await open(sticker: false);
      access
        ..tlsFingerprint = 'abc'
        ..tlsPort = 8443;
      expect(access.pairingLink('nas.local:8765', 'k').queryParameters['url'], 'https://nas.local:8443/');
    });

    test('ohne Zertifikat wie bisher', () async {
      await open(sticker: false);
      final link = access.pairingLink('10.42.0.1', 'k');
      expect(link.queryParameters.containsKey('fp'), isFalse);
    });

    test('/api/box nennt Fingerabdruck und Port', () async {
      await open(sticker: false);
      access.tlsFingerprint = 'abc';
      final info = jsonDecode((await send('/api/box', auth: basic('aufkleber1'))).$2) as Map;
      expect(info['tls'], {'port': 443, 'fingerprint': 'abc'});
    });
  });

  group('Fingerabdruck', () {
    test('entspricht openssl und liest ein echtes Zertifikat', () async {
      final dir = await Directory.systemTemp.createTemp('box_tls');
      addTearDown(() => dir.delete(recursive: true));
      await File('../../../box/files/tls-cert.sh').exists();
      final made = await Process.run('bash', ['../../../box/files/tls-cert.sh', dir.path]);
      expect(made.exitCode, 0, reason: '${made.stderr}');
      final fp = (made.stdout as String).trim();
      final pem = await File('${dir.path}/cert.pem').readAsString();
      expect(certificateFingerprint(pem), fp);
      final tls = await BoxTls.load('${dir.path}/cert.pem', '${dir.path}/key.pem');
      expect(tls?.fingerprint, fp);
      // Zweiter Lauf behält das Zertifikat: Der QR-Code bleibt gültig.
      final again = await Process.run('bash', ['../../../box/files/tls-cert.sh', dir.path]);
      expect((again.stdout as String).trim(), fp);
    });

    test('fehlendes Zertifikat: ohne HTTPS weiter', () async {
      expect(await BoxTls.load('/gibt/es/nicht', '/auch/nicht'), isNull);
      expect(await BoxTls.load(null, null), isNull);
    });
  });
}
