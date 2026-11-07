import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/box.dart';
import 'package:test/test.dart';

/// The login page of box and Docker: password only, no browser dialog.
void main() {
  late Directory data;
  late BoxAccess access;
  late HttpServer server;
  late DateTime now;
  final client = HttpClient();

  Future<void> open({bool sticker = false, String password = 'richtig123'}) async {
    access = await BoxAccess.open(
      data,
      initialPassword: password,
      name: 'KNX Monitor',
      iterations: 1000,
      clock: () => now,
      container: !sticker,
      sticker: sticker,
      initialLanAccess: true,
    );
  }

  setUp(() async {
    data = await Directory.systemTemp.createTemp('knx_login');
    now = DateTime(2026, 11, 7, 12);
    await open();
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

  String origin() => 'http://127.0.0.1:${server.port}';

  /// A browser request: Sec-Fetch headers, an Origin on POST.
  Future<HttpClientResponse> browser(
    String path, {
    String method = 'GET',
    Map<String, String>? form,
    String? cookie,
    bool page = true,
    String? from,
    String site = 'same-origin',
  }) async {
    final request = await client.openUrl(method, Uri.parse('${origin()}$path'));
    request.followRedirects = false;
    request.headers
      ..set('sec-fetch-mode', page ? 'navigate' : 'cors')
      ..set('sec-fetch-site', site);
    if (page) request.headers.set(HttpHeaders.acceptHeader, 'text/html,application/xhtml+xml');
    if (cookie != null) request.headers.set(HttpHeaders.cookieHeader, cookie);
    if (form != null) {
      request.headers
        ..contentType = ContentType('application', 'x-www-form-urlencoded')
        ..set('origin', from ?? origin());
      request.write(Uri(queryParameters: form).query);
    }
    return request.close();
  }

  String? cookieOf(HttpClientResponse response) =>
      response.headers[HttpHeaders.setCookieHeader]?.first.split(';').first;

  Future<String> login({String password = 'richtig123', String next = '/'}) async {
    final response = await browser('/login', method: 'POST', form: {'password': password, 'next': next});
    await response.drain<void>();
    expect(response.statusCode, HttpStatus.seeOther);
    return cookieOf(response)!;
  }

  test('Seite ohne Sitzung: Weiterleitung zur Anmeldung, kein Browser-Dialog', () async {
    final response = await browser('/charts?x=1');
    await response.drain<void>();
    expect(response.statusCode, HttpStatus.seeOther);
    expect(response.headers.value(HttpHeaders.locationHeader), '/login?next=%2Fcharts%3Fx%3D1');
    expect(response.headers.value(HttpHeaders.wwwAuthenticateHeader), isNull);
    final root = await browser('/');
    await root.drain<void>();
    expect(root.headers.value(HttpHeaders.locationHeader), '/login');
  });

  test('API-Aufruf des Browsers: 401 ohne Dialog, Werkzeuge behalten Basic', () async {
    final xhr = await browser('/api/bus', page: false);
    await xhr.drain<void>();
    expect(xhr.statusCode, 401);
    expect(xhr.headers.value(HttpHeaders.wwwAuthenticateHeader), isNull);
    final curl = await (await client.getUrl(Uri.parse('${origin()}/api/bus'))).close();
    await curl.drain<void>();
    expect(curl.statusCode, 401);
    expect(curl.headers.value(HttpHeaders.wwwAuthenticateHeader), startsWith('Basic'));
    // Auch wenn ein Werkzeug HTML verlangt: kein Browser, also Basic statt Weiterleitung.
    final html = await client.getUrl(Uri.parse('${origin()}/'));
    html.followRedirects = false;
    html.headers.set(HttpHeaders.acceptHeader, 'text/html');
    final tool = await html.close();
    await tool.drain<void>();
    expect(tool.statusCode, 401);
    expect(tool.headers.value(HttpHeaders.wwwAuthenticateHeader), startsWith('Basic'));
  });

  test('Anmeldeseite: nur ein Passwortfeld, kein Benutzername', () async {
    final response = await browser('/login?next=/charts');
    final html = await utf8.decodeStream(response);
    expect(response.statusCode, 200);
    expect(response.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
    expect(html, contains('type="password"'));
    expect(html, isNot(contains('username')));
    expect(html, contains('value="/charts"'));
  });

  test('richtiges Passwort: Sitzung und zurück zur Seite', () async {
    final response = await browser('/login', method: 'POST', form: {'password': 'richtig123', 'next': '/charts'});
    await response.drain<void>();
    expect(response.statusCode, HttpStatus.seeOther);
    expect(response.headers.value(HttpHeaders.locationHeader), '/charts');
    final cookie = cookieOf(response)!;
    expect(response.headers[HttpHeaders.setCookieHeader]!.first, contains('HttpOnly; SameSite=Strict'));
    final page = await browser('/charts', cookie: cookie);
    expect(await utf8.decodeStream(page), 'ok admin');
    // Schon angemeldet: die Anmeldeseite leitet weiter.
    final again = await browser('/login', cookie: cookie);
    await again.drain<void>();
    expect(again.headers.value(HttpHeaders.locationHeader), '/');
  });

  test('falsches Passwort: Hinweis, nach fünf Versuchen gesperrt', () async {
    for (var i = 0; i < 5; i++) {
      final response = await browser('/login', method: 'POST', form: {'password': 'falsch-$i'});
      final html = await utf8.decodeStream(response);
      expect(response.statusCode, 401);
      expect(html, contains('stimmt nicht'));
      expect(cookieOf(response), isNull);
    }
    final locked = await browser('/login', method: 'POST', form: {'password': 'richtig123'});
    final html = await utf8.decodeStream(locked);
    expect(locked.statusCode, 429);
    expect(html, contains('warten'));
    expect(cookieOf(locked), isNull);
    now = now.add(const Duration(minutes: 1));
    expect(await login(), isNotEmpty);
  });

  test('nur eigene Formulare (gegen Login-CSRF)', () async {
    final foreign = await browser(
      '/login',
      method: 'POST',
      form: {'password': 'richtig123'},
      from: 'http://evil.example',
      site: 'cross-site',
    );
    await foreign.drain<void>();
    expect(foreign.statusCode, 403);
    expect(cookieOf(foreign), isNull);
  });

  test('Weiterleitung nur auf eigene Pfade', () {
    expect(BoxAccess.safeNext('/charts?a=1'), '/charts?a=1');
    for (final bad in [
      '//evil.example',
      '/\\evil.example',
      'https://evil.example',
      'evil',
      '/login',
      '/logout',
      null,
    ]) {
      expect(BoxAccess.safeNext(bad), '/', reason: '$bad');
    }
  });

  test('Abmelden beendet die Sitzung, nur per eigenem Formular', () async {
    final cookie = await login();
    final get = await browser('/logout', cookie: cookie);
    await get.drain<void>();
    expect(get.statusCode, 405);
    final foreign = await browser('/logout', method: 'POST', form: {}, cookie: cookie, from: 'http://evil.example');
    await foreign.drain<void>();
    expect(foreign.statusCode, 403);
    final out = await browser('/logout', method: 'POST', form: {}, cookie: cookie);
    await out.drain<void>();
    expect(out.statusCode, HttpStatus.seeOther);
    expect(out.headers.value(HttpHeaders.locationHeader), '/login');
    expect(out.headers[HttpHeaders.setCookieHeader]!.first, contains('Max-Age=0'));
    final after = await browser('/api/bus', page: false, cookie: cookie);
    await after.drain<void>();
    expect(after.statusCode, 401);
  });

  test('Box mit Aufkleber-Passwort: nach der Anmeldung zuerst ein eigenes setzen', () async {
    await access.flush();
    await data.delete(recursive: true);
    data = await Directory.systemTemp.createTemp('knx_login');
    await open(sticker: true, password: 'aufkleber1');
    final response = await browser('/login', method: 'POST', form: {'password': 'aufkleber1', 'next': '/charts'});
    await response.drain<void>();
    expect(response.headers.value(HttpHeaders.locationHeader), '/pair');
  });

  test('Passwort ändern beendet die Sitzung', () async {
    final cookie = await login();
    await access.changePassword('neues-passwort');
    final response = await browser('/', cookie: cookie);
    await response.drain<void>();
    expect(response.headers.value(HttpHeaders.locationHeader), '/login');
  });
}
