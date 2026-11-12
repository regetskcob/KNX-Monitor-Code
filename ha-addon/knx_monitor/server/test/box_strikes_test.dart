import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/box.dart';
import 'package:test/test.dart';

/// Failed attempts and lockouts survive a restart (`access-strikes.json`) but never lock out for
/// good. The clock is injected; a "restart" is a second [BoxAccess.open] on the same data folder.
void main() {
  late Directory data;
  late DateTime now;
  late BoxAccess access;
  late HttpServer server;
  final client = HttpClient();

  String basic(String password) => 'Basic ${base64.encode(utf8.encode('box:$password'))}';

  File strikes() => File('${data.path}/${BoxAccess.strikesFileName}');

  Map<String, Object?> stored() =>
      ((jsonDecode(strikes().readAsStringSync()) as Map)['strikes'] as Map).cast<String, Object?>();

  Future<void> start() async {
    access = await BoxAccess.open(
      data,
      initialPassword: 'richtig123',
      iterations: 1000,
      clock: () => now,
      peerOf: (r) => r.headers.value('x-peer') ?? 'a',
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final role = await access.guard(request);
      if (role == null || await access.handle(request, role)) return;
      request.response.write('ok ${role.name}');
      await request.response.close();
    });
  }

  /// Like a restart of the box: memory is gone, the data folder stays.
  Future<void> restart() async {
    await access.flush();
    await server.close(force: true);
    await start();
  }

  Future<(int, String?)> send(String auth, {String peer = 'a', String path = '/api/bus'}) async {
    final request = await client.openUrl('GET', Uri.parse('http://127.0.0.1:${server.port}$path'));
    request.headers
      ..set(HttpHeaders.authorizationHeader, auth)
      ..set('x-peer', peer);
    final response = await request.close();
    await response.drain<void>();
    return (response.statusCode, response.headers.value(HttpHeaders.retryAfterHeader));
  }

  Future<void> fail(int times, {String peer = 'a'}) async {
    for (var i = 0; i < times; i++) {
      expect((await send(basic('falsch$i'), peer: peer)).$1, 401);
    }
  }

  setUp(() async {
    data = await Directory.systemTemp.createTemp('box_strikes');
    now = DateTime(2026, 11, 11, 12);
    await start();
  });

  tearDown(() async {
    await server.close(force: true);
    await access.flush();
    await data.delete(recursive: true);
  });

  test('laufende Sperre übersteht den Neustart und endet wie vorher', () async {
    await fail(5);
    expect(await send(basic('richtig123')), (429, '31'));
    now = now.add(const Duration(seconds: 10));
    await restart();
    // The right password waits for the rest as well: 30 s since the fifth failed attempt.
    expect(await send(basic('richtig123')), (429, '21'));
    now = now.add(const Duration(seconds: 20));
    expect((await send(basic('richtig123'))).$1, 200);
  });

  test('der Zähler läuft nach dem Neustart weiter: sechster Fehlversuch sperrt doppelt so lang', () async {
    await fail(5);
    now = now.add(const Duration(seconds: 31));
    await restart();
    await fail(1);
    expect(await send(basic('richtig123')), (429, '61'));
    // Another sender is not affected.
    expect((await send(basic('richtig123'), peer: 'b')).$1, 200);
  });

  test('auch Fehlversuche unter der Schwelle zählen nach dem Neustart weiter', () async {
    await fail(4);
    await restart();
    await fail(1);
    expect((await send(basic('richtig123'))).$1, 429);
  });

  test('ein Neustart je Versuch bringt keine frischen Versuche', () async {
    for (var i = 0; i < 5; i++) {
      await fail(1);
      await restart();
    }
    expect((await send(basic('richtig123'))).$1, 429);
  });

  test('das richtige Passwort löscht den Eintrag, auch in der Datei', () async {
    await fail(3);
    await fail(2, peer: 'b');
    await access.flush();
    expect(stored().keys, unorderedEquals(['a', 'b']));
    expect((stored()['a']! as Map)['count'], 3);
    expect((await send(basic('richtig123'))).$1, 200);
    await access.flush();
    expect(stored().keys, ['b']);
    expect((await send(basic('richtig123'), peer: 'b')).$1, 200);
    await access.flush();
    expect(strikes().existsSync(), isFalse);
  });

  test('ohne Änderung wird nichts geschrieben', () async {
    // Successful sign-ins without a failed attempt before: no file.
    expect((await send(basic('richtig123'))).$1, 200);
    expect((await send(basic('richtig123'))).$1, 200);
    await access.flush();
    expect(strikes().existsSync(), isFalse);
    await fail(5);
    await access.flush();
    // Requests refused during the lockout change nothing: the file stays as it is.
    strikes().writeAsStringSync('${strikes().readAsStringSync()}\n');
    final marked = strikes().readAsStringSync();
    for (var i = 0; i < 20; i++) {
      expect((await send(basic('falsch'))).$1, 429);
    }
    await access.flush();
    expect(strikes().readAsStringSync(), marked);
  });

  test('die Datei liegt nicht in der Datei-API und enthält kein Passwort', () async {
    await fail(2);
    await access.flush();
    final text = strikes().readAsStringSync();
    expect(text, isNot(contains('falsch')));
    expect(text, isNot(contains('richtig123')));
    expect(data.listSync().map((e) => e.uri.pathSegments.last).where((n) => n.endsWith('.tmp')), isEmpty);
  });

  group('sperrt nie auf Dauer aus', () {
    test('Uhr zurückgestellt: höchstens die Wartezeit, die zum Zähler gehört', () async {
      // A lockout from a time when the clock was a year ahead.
      strikes().writeAsStringSync(
        jsonEncode({
          'version': 1,
          'strikes': {
            'a': {'count': 5, 'until': now.add(const Duration(days: 365)).millisecondsSinceEpoch},
            'b': {'count': 400, 'until': now.add(const Duration(days: 365)).millisecondsSinceEpoch},
            'c': {'count': 2, 'until': now.add(const Duration(days: 365)).millisecondsSinceEpoch},
          },
        }),
      );
      await restart();
      expect(await send(basic('richtig123')), (429, '31'));
      expect(await send(basic('richtig123'), peer: 'b'), (429, '901'));
      expect((await send(basic('richtig123'), peer: 'c')).$1, 200);
      now = now.add(const Duration(seconds: 31));
      expect((await send(basic('richtig123'))).$1, 200);
      now = now.add(const Duration(minutes: 15));
      expect((await send(basic('richtig123'), peer: 'b')).$1, 200);
    });

    test('Uhr im Betrieb zurückgestellt: dieselbe Grenze', () async {
      await fail(5);
      now = now.subtract(const Duration(days: 30));
      expect(await send(basic('richtig123')), (429, '31'));
      now = now.add(const Duration(seconds: 31));
      expect((await send(basic('richtig123'))).$1, 200);
    });

    test('auch nach sehr vielen Fehlversuchen nie länger als 15 Minuten', () async {
      strikes().writeAsStringSync(
        jsonEncode({
          'strikes': {
            'a': {'count': 9000000000, 'until': now.millisecondsSinceEpoch},
          },
        }),
      );
      await restart();
      await fail(1);
      expect(await send(basic('richtig123')), (429, '901'));
      now = now.add(const Duration(minutes: 15, seconds: 1));
      expect((await send(basic('richtig123'))).$1, 200);
    });

    test('alte Einträge verfallen: 24 Stunden nach dem Ende der Wartezeit', () async {
      await fail(4);
      now = now.add(const Duration(hours: 23));
      await restart();
      await fail(1);
      expect((await send(basic('richtig123'))).$1, 429);
      await fail(4, peer: 'b');
      now = now.add(const Duration(hours: 24, minutes: 1));
      await restart();
      await fail(4, peer: 'b');
      expect((await send(basic('richtig123'), peer: 'b')).$1, 200);
      await access.flush();
      expect(strikes().existsSync(), isFalse);
    });

    test('Passwort-Reset am Gerät (password-reset) löscht Zähler und Sperren', () async {
      await fail(5);
      await fail(5, peer: 'b');
      expect((await send(basic('richtig123'))).$1, 429);
      await access.flush();
      expect(strikes().existsSync(), isTrue);
      File('${data.path}/password-reset').writeAsStringSync('vonderkarte1\n');
      await restart();
      expect(strikes().existsSync(), isFalse);
      expect((await send(basic('vonderkarte1'))).$1, 200);
      expect((await send(basic('vonderkarte1'), peer: 'b')).$1, 200);
      // The brake itself still applies.
      await fail(5);
      expect((await send(basic('vonderkarte1'))).$1, 429);
    });

    test('unlesbare Datei: verworfen, die Box bleibt erreichbar', () async {
      for (final broken in ['kaputt', '[]', '{"strikes":7}', '{"strikes":{"a":{"count":"x","until":null},"":1}}']) {
        strikes().writeAsStringSync(broken);
        await restart();
        expect((await send(basic('richtig123'))).$1, 200, reason: broken);
      }
      strikes().writeAsStringSync('kaputt');
      await restart();
      expect(strikes().existsSync(), isFalse);
    });
  });

  test('begrenzt: höchstens 1024 Absender, eine übergroße Datei wird verworfen', () async {
    final until = now.add(const Duration(minutes: 5)).millisecondsSinceEpoch;
    strikes().writeAsStringSync(
      jsonEncode({
        'version': 1,
        'strikes': {
          for (var i = 0; i < 3000; i++) 'peer$i': {'count': 7, 'until': until},
          'x' * 65: {'count': 7, 'until': until},
        },
      }),
    );
    await restart();
    expect((await send(basic('richtig123'), peer: 'peer0')).$1, 429);
    expect((await send(basic('richtig123'), peer: 'peer2999')).$1, 200);
    await fail(1);
    await access.flush();
    expect(stored().length, lessThanOrEqualTo(1024));
    expect(strikes().lengthSync(), lessThan(128 * 1024));

    strikes().writeAsStringSync('{"strikes":{"a":{"count":9,"until":$until}},"pad":"${'x' * 600000}"}');
    await restart();
    expect((await send(basic('richtig123'))).$1, 200);
  });

  test('Sperre der Passwort-Bestätigung je Gerät übersteht den Neustart', () async {
    final key = await access.pair('Tablet', admin: true);
    Future<int> confirm() async {
      final request = await client.openUrl('POST', Uri.parse('http://127.0.0.1:${server.port}/api/box/password'));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      request.write(jsonEncode({'password': 'neuesneues1', 'current': 'geraten'}));
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    }

    for (var i = 0; i < 5; i++) {
      expect(await confirm(), 403);
    }
    expect(await confirm(), 429);
    await restart();
    expect(await confirm(), 429);
    // The device access itself stays usable.
    expect((await send('Bearer $key')).$1, 200);
  });
}
