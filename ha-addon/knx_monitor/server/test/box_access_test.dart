import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/box.dart';
import 'package:test/test.dart';

void main() {
  late Directory data;
  late BoxAccess access;
  late HttpServer server;
  late DateTime now;
  final client = HttpClient();

  String basic(String password) => 'Basic ${base64.encode(utf8.encode('box:$password'))}';

  setUp(() async {
    data = await Directory.systemTemp.createTemp('box_access');
    now = DateTime(2026, 10, 17, 12);
    access = await BoxAccess.open(
      data,
      initialPassword: 'richtig123',
      name: 'KNX-Box-1A2B',
      iterations: 1000,
      clock: () => now,
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    // Wie server.dart: erst prüfen, dann Box-Seiten, sonst „ok“ bzw. WebSocket.
    server.listen((request) async {
      final role = await access.guard(request);
      if (role == null || await access.handle(request, role)) return;
      if (request.uri.path.startsWith('/ws')) {
        final ws = await WebSocketTransformer.upgrade(request);
        ws.add('hallo');
        await ws.close();
        return;
      }
      request.response.write('ok ${role.name}');
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await access.flush();
    // Ein Speichervorgang kann noch nachlaufen – dann ist das Verzeichnis kurz nicht leer.
    for (var i = 0; ; i++) {
      try {
        await data.delete(recursive: true);
        break;
      } on FileSystemException {
        if (i == 9) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });

  Uri url(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  Future<(int, String, HttpHeaders)> send(
    String path, {
    String method = 'GET',
    String? auth,
    String? origin,
    String? body,
    String? cookie,
    String? site,
  }) async {
    final request = await client.openUrl(method, url(path));
    if (auth != null) request.headers.set(HttpHeaders.authorizationHeader, auth);
    if (origin != null) request.headers.set('origin', origin);
    if (cookie != null) request.headers.set(HttpHeaders.cookieHeader, '${BoxAccess.sessionCookie}=$cookie');
    if (site != null) request.headers.set('sec-fetch-site', site);
    if (body != null) {
      request.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
      request.write(body);
    }
    final response = await request.close();
    return (response.statusCode, await utf8.decodeStream(response), response.headers);
  }

  Future<String> pairDevice([String name = 'iPad']) async {
    final (status, html, _) = await send('/pair', method: 'POST', auth: basic('richtig123'), body: 'name=$name');
    expect(status, 200);
    final link = RegExp(r'href="(knxmonitor://[^"]+)"').firstMatch(html)!.group(1)!;
    return Uri.parse(link.replaceAll('&amp;', '&')).queryParameters['key']!;
  }

  test('erstes Passwort nur im Speicher, nie im Klartext auf der Platte', () async {
    expect(access.firstPassword, 'richtig123');
    expect(File('${data.path}/box-password.txt').existsSync(), isFalse);
    final stored = await File('${data.path}/access.json').readAsString();
    expect(stored, isNot(contains('richtig123')));
    // Zweiter Start: kein neues Passwort, alter Stand gilt; die Klartext-Datei
    // älterer Versionen wird weggeräumt.
    await File('${data.path}/box-password.txt').writeAsString('richtig123\n');
    final again = await BoxAccess.open(data, iterations: 1000);
    expect(File('${data.path}/box-password.txt').existsSync(), isFalse);
    expect(again.firstPassword, isNull);
    expect(again.checkPassword('richtig123'), isTrue);
  });

  test('ältere Box mit vielen Runden wird beim Anmelden umgestellt', () async {
    final dir = Directory.systemTemp.createTempSync('box_rehash');
    addTearDown(() => dir.deleteSync(recursive: true));
    await BoxAccess.open(dir, initialPassword: 'richtig123', iterations: 3000);
    final now = await BoxAccess.open(dir, iterations: 1000);
    final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => srv.close(force: true));
    srv.listen((q) async {
      await now.guard(q);
      await q.response.close();
    });
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.get('127.0.0.1', srv.port, '/x');
    request.headers.set(HttpHeaders.authorizationHeader, 'Basic ${base64.encode(utf8.encode('a:richtig123'))}');
    await (await request.close()).drain<void>();
    Map<String, Object?> stored() =>
        (jsonDecode(File('${dir.path}/access.json').readAsStringSync()) as Map)['password'] as Map<String, Object?>;
    for (var i = 0; i < 100 && stored()['iterations'] != 1000; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(stored()['iterations'], 1000);
    expect(now.checkPassword('richtig123'), isTrue);
    await now.flush();
  });

  test('Passwortprüfung blockiert den Server nicht', () async {
    final dir = Directory.systemTemp.createTempSync('box_slow');
    addTearDown(() => dir.deleteSync(recursive: true));
    final slow = await BoxAccess.open(dir, initialPassword: 'richtig123', iterations: 400000);
    var ticks = 0;
    final timer = Timer.periodic(const Duration(milliseconds: 5), (_) => ticks++);
    addTearDown(timer.cancel);
    expect(await slow.verifyPassword('richtig123'), isTrue);
    expect(ticks, greaterThan(1), reason: 'Ereignisschleife lief weiter');
    expect(await slow.verifyPassword('falsch'), isFalse);
  });

  test('ohne Anmeldung: 401 mit Basic-Aufforderung, auf allen Pfaden', () async {
    for (final path in ['/', '/index.html', '/api/bus', '/api/files/catalog.json', '/pair', '/ws/bus']) {
      final (status, _, headers) = await send(path);
      expect(status, 401, reason: path);
      expect(headers.value(HttpHeaders.wwwAuthenticateHeader), startsWith('Basic'), reason: path);
    }
  });

  test('Box-Passwort öffnet alles', () async {
    expect((await send('/api/bus', auth: basic('richtig123'))).$2, 'ok admin');
    expect((await send('/api/bus', auth: basic('falsch'))).$1, 401);
    final (_, info, _) = await send('/api/box', auth: basic('richtig123'));
    expect(jsonDecode(info), {'box': true, 'name': 'KNX-Box-1A2B', 'role': 'admin', 'lanAccess': false});
  });

  test('Koppeln: QR-Code mit Link, Zugang wirkt, Sperren wirkt', () async {
    final (_, html, _) = await send('/pair', method: 'POST', auth: basic('richtig123'), body: 'name=iPad+Bauleitung');
    expect(html, contains('<svg'));
    expect(html, contains('iPad Bauleitung'));
    final link = Uri.parse(RegExp(r'href="(knxmonitor://[^"]+)"').firstMatch(html)!.group(1)!.replaceAll('&amp;', '&'));
    expect(link.queryParameters['url'], 'http://127.0.0.1:${server.port}/');
    expect(link.queryParameters['name'], 'KNX-Box-1A2B');
    final key = link.queryParameters['key']!;
    expect(key, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    // Nur der Hash liegt auf der Platte.
    expect(await File('${data.path}/access.json').readAsString(), isNot(contains(key)));

    expect((await send('/api/bus', auth: 'Bearer $key')).$2, 'ok device');
    expect(access.devices.single.lastUsed, now);

    await send('/pair/revoke', method: 'POST', auth: basic('richtig123'), body: 'id=${access.devices.single.id}');
    expect(access.devices, isEmpty);
    expect((await send('/api/bus', auth: 'Bearer $key')).$1, 401);
  });

  test('Sperren und Passwortwechsel trennen offene Verbindungen', () async {
    var closed = 0;
    access.onAccessChanged = () => closed++;
    final key = await access.pair('Tablet');
    await access.revoke(access.devices.single.id);
    expect(closed, 1, reason: key.isEmpty ? '' : 'nach dem Sperren');
    await access.revokeAll();
    expect(closed, 2);
    await access.changePassword('nochneues123');
    expect(closed, 3);
  });

  test('gültiger Gerätezugang setzt Fehlversuche nicht zurück', () async {
    final key = await access.pair('Tablet');
    for (var round = 0; round < 3; round++) {
      await send('/api/bus', auth: basic('falsch$round'));
      now = now.add(const Duration(minutes: 10));
      expect((await send('/api/bus', auth: 'Bearer $key')).$1, isNot(401));
    }
    // Dies sind der vierte und fünfte Fehlversuch: Der Zähler lief trotz Gerätezugang weiter.
    expect((await send('/api/bus', auth: basic('vier'))).$1, 401);
    expect((await send('/api/bus', auth: basic('fuenf'))).$1, 401);
    expect((await send('/api/bus', auth: basic('sechs'))).$1, 429);
  });

  test('nur ansehen: eigene Rolle, gespeichert, auf der Seite markiert', () async {
    final (status, html, _) = await send(
      '/pair',
      method: 'POST',
      auth: basic('richtig123'),
      body: 'name=Flur&viewOnly=1',
    );
    expect(status, 200);
    final key = Uri.parse(RegExp(r'href="(knxmonitor://[^"]+)"').firstMatch(html)!.group(1)!.replaceAll('&amp;', '&'))
        .queryParameters['key']!;
    expect((await send('/api/bus', auth: 'Bearer $key')).$2, 'ok viewer');
    expect((await send('/ws', auth: 'Bearer $key')).$1, 403);
    expect(access.devices.single.viewOnly, isTrue);
    expect(BoxRole.viewer.maySend, isFalse);
    expect(BoxRole.device.maySend, isTrue);
    expect((await send('/pair', auth: basic('richtig123'))).$2, contains('nur ansehen'));
    // Survives a restart of the box (access.json).
    await access.flush();
    final again = await BoxAccess.open(data, initialPassword: 'richtig123', clock: () => now);
    expect(again.devices.single.viewOnly, isTrue);
    // Pairing with the box password (app) is always full access.
    final normal = await pairDevice('iPad');
    expect((await send('/api/bus', auth: 'Bearer $normal')).$2, 'ok device');
  });

  test('Gerätezugang: kein Roh-Relay, kein Koppeln', () async {
    final key = await pairDevice();
    expect((await send('/ws', auth: 'Bearer $key')).$1, 403);
    expect((await send('/pair', auth: 'Bearer $key')).$1, 403);
    expect((await send('/pair', method: 'POST', auth: 'Bearer $key', body: 'name=x')).$1, 403);
  });

  test('WebSocket /ws/bus: mit Zugang ja, ohne nein', () async {
    final key = await pairDevice();
    final ws = await WebSocket.connect(
      'ws://127.0.0.1:${server.port}/ws/bus',
      headers: {'Authorization': 'Bearer $key'},
    );
    expect(await ws.first, 'hallo');
    await expectLater(WebSocket.connect('ws://127.0.0.1:${server.port}/ws/bus'), throwsA(isA<WebSocketException>()));
  });

  test('fremde Herkunft abgelehnt, eigene erlaubt', () async {
    final own = 'http://127.0.0.1:${server.port}';
    expect((await send('/api/bus', method: 'PUT', auth: basic('richtig123'), origin: own)).$1, 200);
    expect((await send('/api/bus', method: 'PUT', auth: basic('richtig123'), origin: 'http://evil.example')).$1, 403);
    expect((await send('/api/bus', method: 'PUT', auth: basic('richtig123'), origin: 'null')).$1, 403);
    final (status, _, _) = await send(
      '/pair',
      method: 'POST',
      auth: basic('richtig123'),
      origin: 'http://evil.example',
      body: 'name=x',
    );
    expect(status, 403);
    expect(access.devices, isEmpty);
  });

  test('Bremse nach 5 Fehlversuchen, verdoppelt', () async {
    for (var i = 0; i < 4; i++) {
      expect((await send('/api/bus', auth: basic('falsch'))).$1, 401);
    }
    expect((await send('/api/bus', auth: 'Bearer falsch')).$1, 401); // 5.
    final (status, _, headers) = await send('/api/bus', auth: basic('richtig123'));
    expect(status, 429);
    expect(headers.value(HttpHeaders.retryAfterHeader), '31');
    now = now.add(const Duration(seconds: 31));
    expect((await send('/api/bus', auth: basic('falsch'))).$1, 401); // 6. → 60 s
    expect((await send('/api/bus', auth: basic('richtig123'))).$1, 429);
    now = now.add(const Duration(seconds: 61));
    expect((await send('/api/bus', auth: basic('richtig123'))).$1, 200);
    // Erfolg setzt zurück.
    expect((await send('/api/bus', auth: basic('falsch'))).$1, 401);
    expect((await send('/api/bus', auth: basic('richtig123'))).$1, 200);
  });

  test('Passwort ändern', () async {
    final (_, short, _) = await send(
      '/pair/password',
      method: 'POST',
      auth: basic('richtig123'),
      body: 'password=kurz',
    );
    expect(short, contains('mindestens 8'));
    // Without or with a wrong current password nothing changes.
    for (final body in ['password=neues-passwort', 'current=falsch12&password=neues-passwort']) {
      final (_, page, _) = await send('/pair/password', method: 'POST', auth: basic('richtig123'), body: body);
      expect(page, contains('aktuelle Passwort stimmt nicht'));
    }
    expect(access.checkPassword('richtig123'), isTrue);
    await send(
      '/pair/password',
      method: 'POST',
      auth: basic('richtig123'),
      body: 'current=richtig123&password=neues-passwort',
    );
    expect((await send('/api/bus', auth: basic('richtig123'))).$1, 401);
    expect((await send('/api/bus', auth: basic('neues-passwort'))).$1, 200);
  });

  group('Sitzungs-Cookie', () {
    String? cookieOf(HttpHeaders headers) {
      final set = headers[HttpHeaders.setCookieHeader]?.single;
      if (set == null) return null;
      return RegExp('^${BoxAccess.sessionCookie}=([^;]+)').firstMatch(set)!.group(1);
    }

    Future<String> login() async {
      final (status, _, headers) = await send('/api/bus', auth: basic('richtig123'));
      expect(status, 200);
      return cookieOf(headers)!;
    }

    String own() => 'http://127.0.0.1:${server.port}';

    test('nach Basic gesetzt: HttpOnly, SameSite=Strict, Path=/, ohne Secure', () async {
      final (_, _, headers) = await send('/api/bus', auth: basic('richtig123'));
      final set = headers[HttpHeaders.setCookieHeader]!.single;
      expect(set, matches(RegExp('^${BoxAccess.sessionCookie}=[A-Za-z0-9_-]{43};')));
      expect(set, contains('HttpOnly'));
      expect(set, contains('SameSite=Strict'));
      expect(set, contains('Path=/'));
      expect(set, isNot(contains('Secure')));
      // Falsches Passwort und Gerätezugang bekommen keins.
      expect((await send('/api/bus', auth: basic('falsch'))).$3[HttpHeaders.setCookieHeader], isNull);
      final key = await pairDevice();
      expect((await send('/api/bus', auth: 'Bearer $key')).$3[HttpHeaders.setCookieHeader], isNull);
    });

    test('ersetzt Basic, auch beim WebSocket; kein neues bei jeder Anfrage', () async {
      final cookie = await login();
      expect((await send('/api/bus', cookie: cookie)).$2, 'ok admin');
      expect((await send('/api/bus', method: 'PUT', cookie: cookie, origin: own())).$2, 'ok admin');
      expect(
        (await send('/api/bus', auth: basic('richtig123'), cookie: cookie)).$3[HttpHeaders.setCookieHeader],
        isNull,
      );
      final ws = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/ws/bus',
        headers: {'Cookie': '${BoxAccess.sessionCookie}=$cookie', 'Origin': own()},
      );
      expect(await ws.first, 'hallo');
      expect((await send('/api/bus', cookie: 'erfunden')).$1, 401);
    });

    test('unbekanntes Schema fällt nicht aufs Cookie zurück', () async {
      final cookie = await login();
      final (status, _, headers) = await send(
        '/api/bus',
        method: 'PUT',
        auth: 'Digest x',
        cookie: cookie,
        origin: 'http://evil.example',
      );
      expect(status, 401);
      expect(headers.value(HttpHeaders.wwwAuthenticateHeader), startsWith('Basic'));
      expect((await send('/api/bus', auth: 'Digest x', cookie: cookie, site: 'cross-site')).$1, 401);
    });

    test('fremde Herkunft abgelehnt, ohne Herkunft nur lesen', () async {
      final cookie = await login();
      expect((await send('/api/bus', method: 'PUT', cookie: cookie, origin: 'http://evil.example')).$1, 403);
      expect((await send('/api/bus', method: 'PUT', cookie: cookie)).$1, 403);
      expect((await send('/api/bus', cookie: cookie, site: 'cross-site')).$1, 403);
      expect((await send('/api/bus', cookie: cookie, site: 'same-site')).$1, 403);
      expect((await send('/api/bus', cookie: cookie, site: 'same-origin')).$1, 200);
      final (status, _, _) = await send(
        '/pair',
        method: 'POST',
        cookie: cookie,
        origin: 'http://evil.example',
        body: 'name=x',
      );
      expect(status, 403);
      expect(access.devices, isEmpty);
      await expectLater(
        WebSocket.connect(
          'ws://127.0.0.1:${server.port}/ws/bus',
          headers: {'Cookie': '${BoxAccess.sessionCookie}=$cookie', 'Origin': 'http://evil.example'},
        ),
        throwsA(isA<WebSocketException>()),
      );
      await expectLater(
        WebSocket.connect(
          'ws://127.0.0.1:${server.port}/ws/bus',
          headers: {'Cookie': '${BoxAccess.sessionCookie}=$cookie'},
        ),
        throwsA(isA<WebSocketException>()),
      );
    });

    test('läuft ab; Basic erneuert vor dem Ablauf', () async {
      final cookie = await login();
      now = now.add(BoxAccess.sessionLifetime ~/ 2 - const Duration(minutes: 1));
      expect(
        (await send('/api/bus', auth: basic('richtig123'), cookie: cookie)).$3[HttpHeaders.setCookieHeader],
        isNull,
      );
      now = now.add(const Duration(minutes: 2));
      final (_, _, headers) = await send('/api/bus', auth: basic('richtig123'), cookie: cookie);
      final fresh = cookieOf(headers)!;
      expect(fresh, isNot(cookie));
      now = now.add(BoxAccess.sessionLifetime ~/ 2);
      final (status, _, expired) = await send('/api/bus', cookie: cookie);
      expect(status, 401);
      expect(expired.value(HttpHeaders.wwwAuthenticateHeader), startsWith('Basic'));
      expect((await send('/api/bus', cookie: fresh)).$1, 200);
      // Abgelaufene Cookies zählen nicht als Fehlversuch.
      for (var i = 0; i < 6; i++) {
        expect((await send('/api/bus', cookie: cookie)).$1, 401);
      }
      expect((await send('/api/bus', auth: basic('richtig123'))).$1, 200);
    });

    test('Passwortwechsel verwirft alle Sitzungen', () async {
      final first = await login();
      final second = await login();
      expect(second, isNot(first));
      await send(
        '/pair/password',
        method: 'POST',
        cookie: first,
        origin: own(),
        body: 'current=richtig123&password=neues-passwort',
      );
      expect(access.checkPassword('neues-passwort'), isTrue);
      expect((await send('/api/bus', cookie: first)).$1, 401);
      expect((await send('/api/bus', cookie: second)).$1, 401);
    });

    test('Benutzername egal, im Anmeldedialog genannt', () async {
      final (status, _, headers) = await send('/api/bus');
      expect(status, 401);
      expect(headers.value(HttpHeaders.wwwAuthenticateHeader), contains('Benutzername beliebig'));
      final anyone = 'Basic ${base64.encode(utf8.encode('irgendwer:richtig123'))}';
      expect((await send('/api/bus', auth: anyone)).$2, 'ok admin');
    });
  });

  test('manifest.json ohne Anmeldung, sonst nichts', () async {
    expect((await send('/manifest.json')).$1, 200);
    expect((await send('/manifest.json', method: 'POST')).$1, 401);
    expect((await send('/index.html')).$1, 401);
  });

  test('QR-Code ist gültiges SVG', () {
    final svg = qrSvg('knxmonitor://box?url=http://10.42.0.1:8765/&key=abc');
    expect(svg, startsWith('<svg'));
    expect(RegExp(r'viewBox="0 0 (\d+) \1"').hasMatch(svg), isTrue);
  });

  group('Verwaltung aus der App (JSON)', () {
    test('Koppeln mit dem Passwort ergibt einen Admin-Zugang', () async {
      final (status, body, _) = await send(
        '/api/box/pair',
        method: 'POST',
        auth: basic('richtig123'),
        body: '{"name":"iPhone Bauleitung"}',
      );
      expect(status, 200);
      final j = jsonDecode(body) as Map<String, Object?>;
      expect(j['name'], 'KNX-Box-1A2B');
      final key = j['key']! as String;
      expect(key.length, 43);
      final (listStatus, list, _) = await send('/api/box/devices', auth: 'Bearer $key');
      expect(listStatus, 200);
      expect(jsonDecode(list), [containsPair('self', true)]);
      expect((jsonDecode(list) as List).single, containsPair('admin', true));
      // Ein Admin-Gerät darf auch neue Geräte koppeln.
      expect((await send('/api/box/pair', method: 'POST', auth: 'Bearer $key', body: '{}')).$1, 200);
    });

    test('Gerät aus /pair (ohne Admin) darf nicht verwalten', () async {
      final key = await pairDevice();
      for (final (path, method) in [
        ('/api/box/devices', 'GET'),
        ('/api/box/pair', 'POST'),
        ('/api/box/password', 'POST'),
        ('/api/box/devices/revoke', 'POST'),
      ]) {
        expect((await send(path, method: method, auth: 'Bearer $key', body: method == 'POST' ? '{}' : null)).$1, 403);
      }
      expect((await send('/api/box/pair', auth: basic('falsch12'))).$1, 401);
    });

    test('Sperren und Passwort ändern', () async {
      final (_, body, _) = await send('/api/box/pair', method: 'POST', auth: basic('richtig123'), body: '{}');
      final j = jsonDecode(body) as Map<String, Object?>;
      final other = await pairDevice('iPad');
      final id = access.devices.firstWhere((d) => !d.admin).id;
      expect(
        (await send('/api/box/devices/revoke', method: 'POST', auth: 'Bearer ${j['key']}', body: '{"id":"$id"}')).$1,
        200,
      );
      expect((await send('/api/bus', auth: 'Bearer $other')).$1, 401);
      expect(
        (await send('/api/box/password', method: 'POST', auth: 'Bearer ${j['key']}', body: '{"password":"kurz"}')).$1,
        400,
      );
      // A token alone is not enough (lost tablet): the current password is needed.
      for (final body in ['{"password":"neues-passwort"}', '{"password":"neues-passwort","current":"falsch12"}']) {
        expect((await send('/api/box/password', method: 'POST', auth: 'Bearer ${j['key']}', body: body)).$1, 403);
      }
      expect(
        (await send('/api/box/devices/revoke', method: 'POST', auth: 'Bearer ${j['key']}', body: '{"id":"*"}')).$1,
        403,
      );
      expect(
        (await send(
          '/api/box/password',
          method: 'POST',
          auth: 'Bearer ${j['key']}',
          body: '{"password":"neues-passwort","current":"richtig123"}',
        )).$1,
        200,
      );
      expect(access.checkPassword('neues-passwort'), isTrue);
      expect((await send('/api/box/devices', method: 'POST', auth: 'Bearer ${j['key']}', body: '{}')).$1, 405);
    });
  });

  group('Zugriff über das Kabel', () {
    // Wie ein Absender am Kabel: der Testserver sieht nur 127.0.0.1.
    Future<void> fromLan({bool initial = false, bool fresh = false, bool container = false}) async {
      await access.flush();
      if (fresh) await File('${data.path}/access.json').delete();
      access = await BoxAccess.open(
        data,
        initialPassword: 'richtig123',
        iterations: 1000,
        clock: () => now,
        initialLanAccess: initial,
        fromWlan: (_) => false,
        container: container,
      );
    }

    test('Docker: LAN_ACCESS gilt bei jedem Start, auch nach dem ersten', () async {
      await fromLan(container: true, fresh: true);
      expect((await send('/api/bus', auth: basic('richtig123'))).$1, 403);
      // Später LAN_ACCESS=yes gesetzt und neu gestartet: frei.
      await fromLan(initial: true, container: true);
      expect(access.lanAccess, isTrue);
      expect((await send('/api/bus', auth: basic('richtig123'))).$1, 200);
      // Und wieder zurück auf no.
      await fromLan(container: true);
      expect(access.lanAccess, isFalse);
    });

    test('Docker: Meldung ohne Box-WLAN, Schalter nur lesend', () async {
      await fromLan(container: true, fresh: true);
      final (status, text, _) = await send('/api/bus', auth: basic('richtig123'));
      expect(status, 403);
      expect(text, contains('LAN_ACCESS=yes'));
      expect(text, isNot(contains('WLAN')));
      await fromLan(initial: true, container: true);
      final (_, info, _) = await send('/api/box', auth: basic('richtig123'));
      expect(jsonDecode(info), allOf(containsPair('container', true), containsPair('lanAccess', true)));
      expect(
        (await send('/api/box/lan', method: 'POST', auth: basic('richtig123'), body: '{"enabled":false}')).$1,
        409,
      );
      expect(access.lanAccess, isTrue);
      final (_, html, _) = await send('/pair', auth: basic('richtig123'));
      expect(html, contains('Zugriff aus dem Netzwerk'));
      expect(html, isNot(contains('action="/pair/lan"')));
      expect(html, isNot(contains('Box-Passwort')));
      expect((await send('/pair/lan', method: 'POST', auth: basic('richtig123'), body: 'enabled=0')).$1, 200);
      expect(access.lanAccess, isTrue);
    });

    test('Docker: Anmeldedialog ohne „KNX-Box“', () async {
      await fromLan(initial: true, container: true, fresh: true);
      final (status, _, headers) = await send('/api/bus');
      expect(status, 401);
      expect(headers.value(HttpHeaders.wwwAuthenticateHeader), contains('KNX Monitor'));
    });

    test('WLAN der Box und die Box selbst: ja, sonst nein', () {
      bool wlan(String a) => BoxAccess.wlanPeer(InternetAddress(a));
      expect(wlan('10.42.0.17'), isTrue);
      expect(wlan('127.0.0.1'), isTrue);
      expect(wlan('192.168.1.20'), isFalse);
      expect(wlan('10.42.1.5'), isFalse);
      expect(wlan('169.254.3.4'), isFalse);
    });

    test('standardmäßig aus: 403 auch mit Passwort, ohne Bremse', () async {
      await fromLan();
      for (var i = 0; i < 6; i++) {
        final (status, text, _) = await send('/api/bus', auth: basic('richtig123'));
        expect(status, 403);
        expect(text, contains('Kabel'));
      }
      expect((await send('/pair')).$1, 403);
    });

    test('LAN_ACCESS=yes gibt frei, bis die App es ändert', () async {
      await fromLan(initial: true, fresh: true);
      expect((await send('/api/bus', auth: basic('richtig123'))).$1, 200);
      await access.setLanAccess(false);
      await fromLan(initial: true);
      expect(access.lanAccess, isFalse);
      expect((await send('/api/bus', auth: basic('richtig123'))).$1, 403);
    });

    test('Schalter aus der App: nur mit Admin-Recht, bleibt gespeichert', () async {
      final device = await pairDevice('iPad');
      expect((await send('/api/box/lan', method: 'POST', auth: 'Bearer $device', body: '{"enabled":true}')).$1, 403);
      expect((await send('/api/box/lan', method: 'POST', auth: basic('richtig123'), body: '{"enabled":1}')).$1, 400);
      final (status, body, _) = await send(
        '/api/box/lan',
        method: 'POST',
        auth: basic('richtig123'),
        body: '{"enabled":true}',
      );
      expect(status, 200);
      expect(jsonDecode(body), {'ok': true, 'lanAccess': true});
      await fromLan();
      expect(access.lanAccess, isTrue);
      final (_, info, _) = await send('/api/box', auth: basic('richtig123'));
      expect(jsonDecode(info), containsPair('lanAccess', true));
    });

    test('Wahl für die Firewall liegt als lan-access bereit', () async {
      final file = File('${data.path}/lan-access');
      expect(await file.readAsString(), 'no\n');
      await access.setLanAccess(true);
      expect(await file.readAsString(), 'yes\n');
      await fromLan(initial: true, fresh: true);
      expect(await file.readAsString(), 'yes\n');
    });

    test('Schalter auf der Seite /pair', () async {
      final (_, html, _) = await send('/pair', auth: basic('richtig123'));
      expect(html, contains('Zugriff über das Kabel'));
      expect((await send('/pair/lan', method: 'POST', auth: basic('richtig123'), body: 'enabled=1')).$1, 200);
      expect(access.lanAccess, isTrue);
      expect((await send('/pair/lan', method: 'POST', auth: basic('richtig123'), body: 'enabled=0')).$1, 200);
      expect(access.lanAccess, isFalse);
    });
  });

  group('Ausfallsicherheit', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('access'));
    tearDown(() => dir.delete(recursive: true));

    test('kaputte access.json: Sicherung übernimmt, die Box bleibt erreichbar', () async {
      final first = await BoxAccess.open(dir, initialPassword: 'aufkleber1', iterations: 1000);
      await first.changePassword('geaendert1');
      await first.flush();
      await File('${dir.path}/access.json').writeAsString('{"password":');
      final again = await BoxAccess.open(dir, initialPassword: 'aufkleber1', iterations: 1000);
      expect(again.checkPassword('aufkleber1'), isTrue);
      expect(await dir.list().where((e) => e.path.contains('access.json.corrupt-')).length, 1);
    });

    test('kaputte access.json ohne Sicherung: Passwort vom Aufkleber', () async {
      await File('${dir.path}/access.json').writeAsString('kaputt');
      final access = await BoxAccess.open(dir, initialPassword: 'aufkleber1', iterations: 1000);
      expect(access.checkPassword('aufkleber1'), isTrue);
    });
  });
}
