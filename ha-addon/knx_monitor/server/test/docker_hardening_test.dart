import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/box.dart';
import 'package:knx_monitor_server/bus.dart';
import 'package:knx_monitor_server/files.dart';
import 'package:test/test.dart';

/// Security review before 1.9.10 (Docker): every finding that was fixed has
/// a test here, so that it stays fixed.
void main() {
  group('Container-Umgebung', () {
    test('ALLOW_ALL im Netzwerk nur mit ALLOW_ALL_EXPOSED', () {
      expect(refuseToStart({'ALLOW_ALL': '1', 'BIND': '0.0.0.0'}, firstStart: true), contains('ALLOW_ALL_EXPOSED'));
      expect(refuseToStart({'ALLOW_ALL': '1', 'BIND': '192.168.1.5'}, firstStart: true), isNotNull);
      expect(refuseToStart({'ALLOW_ALL': '1', 'BIND': '0.0.0.0', 'ALLOW_ALL_EXPOSED': '1'}, firstStart: true), isNull);
      expect(refuseToStart({'ALLOW_ALL': '1', 'BIND': '127.0.0.1'}, firstStart: true), isNull);
      expect(refuseToStart({'ALLOW_ALL': '1'}, firstStart: true), isNull);
    });

    test('Docker: erstes Passwort mindestens 8 Zeichen, später zählt das gespeicherte', () {
      expect(refuseToStart({'BOX': '1'}, firstStart: true), contains('BOX_PASSWORD fehlt'));
      expect(refuseToStart({'BOX': '1', 'BOX_PASSWORD': '1234'}, firstStart: true), contains('zu kurz'));
      expect(refuseToStart({'BOX': '1', 'BOX_PASSWORD': '12345678'}, firstStart: true), isNull);
      expect(refuseToStart({'BOX': '1', 'BOX_PASSWORD': '1234'}, firstStart: false), isNull);
      // Die echte Box hat ihr Aufkleber-Passwort.
      expect(refuseToStart({'BOX': '1', 'BOX_STICKER': '1'}, firstStart: true), isNull);
    });

    test('Geheimnisse aus Dateien (Docker secrets), direkt gesetzte gewinnen', () async {
      final dir = await Directory.systemTemp.createTemp('knx_secret');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/pw')..writeAsStringSync('geheim-123\n');
      expect(withSecretFiles({'BOX_PASSWORD_FILE': file.path})['BOX_PASSWORD'], 'geheim-123');
      expect(
        withSecretFiles({'BOX_PASSWORD_FILE': file.path, 'BOX_PASSWORD': 'direkt-123'})['BOX_PASSWORD'],
        'direkt-123',
      );
      expect(withSecretFiles({'MQTT_PASSWORD_FILE': file.path})['MQTT_PASSWORD'], 'geheim-123');
      expect(() => withSecretFiles({'BOX_PASSWORD_FILE': '${dir.path}/fehlt'}), throwsA(isA<ContainerEnvException>()));
    });
  });

  group('UDP-Relay', () {
    List<int> knx(int service, [int extra = 0]) {
      final length = 6 + extra;
      return [0x06, 0x10, service >> 8, service & 0xFF, length >> 8, length & 0xFF, ...List.filled(extra, 0)];
    }

    test('nur vollständige KNXnet/IP-Pakete', () {
      expect(relayPacketWellFormed(knx(0x0201, 8)), isTrue); // SEARCH_REQUEST
      expect(relayPacketWellFormed(knx(0x0420, 15)), isTrue); // TUNNELLING_REQUEST
      expect(relayPacketWellFormed(knx(0x0950, 40)), isTrue); // SECURE_WRAPPER
      // Längenfeld passt nicht: z. B. eine DNS-Anfrage mit Transaktions-ID 0x0610.
      expect(relayPacketWellFormed([0x06, 0x10, 0x01, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0, 3, 1, 2, 3]), isFalse);
      expect(relayPacketWellFormed([...knx(0x0201, 8), 0xFF]), isFalse);
      // Unbekannter Dienst, auch in bekannter Familie.
      expect(relayPacketWellFormed(knx(0x0101, 2)), isFalse);
      expect(relayPacketWellFormed(knx(0x02FF)), isFalse);
      expect(relayPacketWellFormed([0x06, 0x10]), isFalse);
    });

    test('Ziele: lokale Netze, Loopback nur auf 3671, kein Internet', () {
      bool ok(String ip, int port) => relayTargetAllowed(InternetAddress(ip), port);
      expect(ok('192.168.1.20', 3671), isTrue);
      expect(ok('10.0.0.5', 3672), isTrue);
      expect(ok('224.0.23.12', 3671), isTrue);
      expect(ok('127.0.0.1', 3671), isTrue);
      expect(ok('127.0.0.53', 53), isFalse, reason: 'DNS-Resolver des Hosts');
      expect(ok('127.0.0.1', 11211), isFalse);
      expect(ok('8.8.8.8', 3671), isFalse);
      expect(ok('224.0.0.251', 5353), isFalse);
      expect(ok('192.168.1.20', 0), isFalse);
    });

    test('Suchantworten von jedem Gateway', () {
      expect(relaySearchResponse(knx(0x0202, 8)), isTrue);
      expect(relaySearchResponse(knx(0x020C, 8)), isTrue);
      expect(relaySearchResponse(knx(0x0420, 8)), isFalse);
    });
  });

  group('Anmeldung im Container', () {
    late Directory data;
    late BoxAccess access;
    late HttpServer server;
    late DateTime now;
    final client = HttpClient();

    String basic(String password) => 'Basic ${base64.encode(utf8.encode('x:$password'))}';

    Future<void> open({required bool lanAccess}) async {
      access = await BoxAccess.open(
        data,
        initialPassword: 'richtig123',
        iterations: 1000,
        clock: () => now,
        container: true,
        initialLanAccess: lanAccess,
        fromWlan: (peer) => peer.isLoopback,
      );
    }

    setUp(() async {
      data = await Directory.systemTemp.createTemp('knx_docker');
      now = DateTime(2026, 11, 7, 12);
      await open(lanAccess: false);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final role = await access.guard(request);
        if (role == null || await access.handle(request, role)) return;
        request.response.write('ok ${role.name}');
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      await access.flush();
      await data.delete(recursive: true);
    });

    Future<(int, String, HttpHeaders)> send(
      String path, {
      String method = 'GET',
      String? auth,
      String? host,
      String? body,
      String? cookie,
    }) async {
      final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:${server.port}$path'));
      if (auth != null) request.headers.set(HttpHeaders.authorizationHeader, auth);
      if (host != null) request.headers.host = host;
      if (cookie != null) request.headers.set(HttpHeaders.cookieHeader, cookie);
      if (body != null) request.write(body);
      final response = await request.close();
      return (response.statusCode, await utf8.decodeStream(response), response.headers);
    }

    test('ohne LAN_ACCESS nur unter localhost (gegen DNS-Rebinding)', () async {
      expect((await send('/api/x', auth: basic('richtig123'))).$1, 200);
      expect((await send('/api/x', auth: basic('richtig123'), host: 'localhost')).$1, 200);
      final (status, text, _) = await send('/api/x', auth: basic('richtig123'), host: 'evil.example');
      expect(status, 403);
      expect(text, contains('LAN_ACCESS=yes'));
    });

    test('Sperre nach Fehlversuchen trifft gekoppelte Apps nicht, falsche Tokens schon', () async {
      final key = (jsonDecode(
        (await send('/api/box/pair', method: 'POST', auth: basic('richtig123'), body: '{}')).$2,
      ) as Map)['key'];
      for (var i = 0; i < 6; i++) {
        await send('/api/x', auth: basic('falsch-$i'));
      }
      expect((await send('/api/x', auth: basic('richtig123'))).$1, 429);
      expect((await send('/api/x', auth: 'Bearer $key')).$1, 200);
      expect((await send('/api/x', auth: 'Bearer falsch')).$1, 429);
    });

    test('Admin-Zugang nur mit dem Passwort, nicht mit Sitzung oder Token', () async {
      final (_, _, headers) = await send('/api/box', auth: basic('richtig123'));
      final cookie = headers[HttpHeaders.setCookieHeader]!.first.split(';').first;
      final key = (jsonDecode(
        (await send('/api/box/pair', method: 'POST', auth: basic('richtig123'), body: '{}')).$2,
      ) as Map)['key'];
      expect((await send('/api/box/pair', method: 'POST', auth: 'Bearer $key', body: '{}')).$1, 403);
      // Ohne Origin lehnt schon die Herkunftsprüfung ab; mit stimmt sie, das Koppeln nicht.
      final request = await client.openUrl('POST', Uri.parse('http://127.0.0.1:${server.port}/api/box/pair'));
      request.headers
        ..set(HttpHeaders.cookieHeader, cookie)
        ..set('origin', 'http://127.0.0.1:${server.port}');
      request.write('{}');
      final response = await request.close();
      await response.drain<void>();
      expect(response.statusCode, 403);
    });

    test('„Alle sperren“ beendet auch Browser-Sitzungen', () async {
      final (_, _, headers) = await send('/api/box', auth: basic('richtig123'));
      final cookie = headers[HttpHeaders.setCookieHeader]!.first.split(';').first;
      expect((await send('/api/x', cookie: cookie)).$1, 200);
      await access.revokeAll();
      expect((await send('/api/x', cookie: cookie)).$1, 401);
    });
  });

  group('Dateien und Verlauf', () {
    test('Groß-/Kleinschreibung umgeht die Sperre der Geheimnisse nicht', () async {
      final data = await Directory.systemTemp.createTemp('knx_case');
      addTearDown(() => data.delete(recursive: true));
      await File('${data.path}/secure_keys.json').writeAsString('{}');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen(
        (request) => serveFile(request, data, request.uri.path.substring(1), admin: false, owner: 'd1', viewOnly: true),
      );
      final client = HttpClient();
      for (final name in ['Secure_Keys.json', 'SERVER.JSON', 'Export.json', 'Report_Settings.json', 'x.TMP']) {
        final response = await (await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}/$name'))).close();
        await response.drain<void>();
        expect(response.statusCode, 403, reason: name);
      }
    });

    test('Verlauf: Beginn weit in der Zukunft wird abgelehnt', () {
      String? error;
      final now = DateTime(2026, 11, 7);
      final far = historyQuery(
        {'a': '1', 'from': '8639999000000000', 'to': '8640000000000000'},
        onError: (e) => error = e,
        now: () => now,
      );
      expect(far, isNull);
      expect(error, contains('Zukunft'));
      final ok = historyQuery({
        'a': '1',
        'from': '${now.millisecondsSinceEpoch}',
        'to': '${now.add(const Duration(days: 1)).millisecondsSinceEpoch}',
      }, now: () => now);
      expect(ok, isNotNull);
    });

    test('Wächter: eine kaputte Regel schaltet die anderen nicht ab', () async {
      final data = await Directory.systemTemp.createTemp('knx_watch_bad');
      addTearDown(() => data.delete(recursive: true));
      await File('${data.path}/watch_rules.json').writeAsString(
        jsonEncode({
          'rules': [
            {'id': 'kaputt', 'address': '1', 'check': <String, Object?>{}},
            'kein Objekt',
            {
              'id': 'gut',
              'address': 0x0A03,
              'label': '1/2/3',
              'check': {'any': true},
            },
          ],
        }),
      );
      final set = WatchRuleSet(data, notify: ({required id, required title, required message}) async {});
      final line = {
        't': DateTime(2026, 11, 7).microsecondsSinceEpoch,
        's': 0x1105,
        'd': 0x0A03,
        'y': 2,
        'x': '01',
        'm': true,
      };
      expect(await set.check(line), ['gut']);
    });
  });
}
