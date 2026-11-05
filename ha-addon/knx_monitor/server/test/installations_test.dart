import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:knx_monitor_server/files.dart';
import 'package:test/test.dart';

/// Installationen: Der Datenordner wird beim ersten Start zur Installation
/// „default“, jede weitere bekommt eigenen Katalog, Busverbindung und
/// Verlauf; die nicht aktiven bleiben lesbar.
void main() {
  late Directory data;

  setUp(() async => data = await Directory.systemTemp.createTemp('installations'));
  tearDown(() => data.delete(recursive: true));

  Future<void> write(String path, String text) async {
    final file = File('${data.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  Future<String?> read(String path) async {
    final file = File('${data.path}/$path');
    return await file.exists() ? file.readAsString() : null;
  }

  group('Migration', () {
    test('bisheriger Datenordner wird „default“, Serverdateien bleiben im Root', () async {
      await write('access.json', '{"a":1}');
      await write('time-request.json', '{}');
      await write('server.json', '{"retentionDays":30}');
      await write('catalog.json', '{"project":"Musterhaus","groups":[]}');
      await write('dpt_overrides.json', '{}');
      await write('secure_keys.json', '{"groupKeys":{}}');
      await write('health.json', '[]');
      await write('history/2026-10-01.ndjson', '{"t":1}\n');
      await write('history/unsynced-123.ndjson', '{"mono":1}\n');
      await write('status/availability-2026-10.ndjson', '{"t":1}\n');
      await write('unsynced-5.ndjson', '{"mono":2}\n');

      final installations = await Installations.open(data);
      expect(installations.activeId, 'default');
      expect(installations.active.name, 'Musterhaus');
      expect(installations.root.path, '${data.path}/installations/default');

      for (final moved in [
        'server.json',
        'catalog.json',
        'dpt_overrides.json',
        'secure_keys.json',
        'health.json',
        'history/2026-10-01.ndjson',
        'history/unsynced-123.ndjson',
        'status/availability-2026-10.ndjson',
        'unsynced-5.ndjson',
      ]) {
        expect(await read('installations/default/$moved'), isNotNull, reason: moved);
        expect(await read(moved), isNull, reason: moved);
      }
      expect(await read('access.json'), '{"a":1}');
      expect(await read('time-request.json'), '{}');

      final index = jsonDecode((await read('installations.json'))!) as Map<String, Object?>;
      expect(index['version'], 1);
      expect(index['active'], 'default');
      expect((index['list']! as List).single, containsPair('name', 'Musterhaus'));
    });

    test('zweiter Start ändert nichts', () async {
      await write('catalog.json', '{"project":"A"}');
      await Installations.open(data);
      final before = await read('installations.json');
      // Neue Datei im Root nach der Migration wird nicht mehr verschoben.
      await write('catalog.json', '{"project":"B"}');
      final again = await Installations.open(data);
      expect(await read('installations.json'), before);
      expect(again.list.single.name, 'A');
      expect(await read('catalog.json'), '{"project":"B"}');
    });

    test('leerer Datenordner: Installation ohne Projektnamen', () async {
      final installations = await Installations.open(data);
      expect(installations.list.single.name, Installations.defaultName);
      expect(await installations.root.exists(), isTrue);
    });
  });

  group('Verwalten', () {
    test('anlegen mit Id der App, umbenennen, löschen – nicht die aktive', () async {
      final installations = await Installations.open(data);
      final created = await installations.create(id: '3f2a9c01be77', name: '  Kunde Meier ');
      expect(created.name, 'Kunde Meier');
      expect(await installations.rootOf(created.id).exists(), isTrue);
      final generated = await installations.create(name: 'Zweite');
      expect(Installations.validId.hasMatch(generated.id), isTrue);

      await expectLater(
        installations.create(id: '3f2a9c01be77', name: 'doppelt'),
        throwsA(isA<InstallationException>().having((e) => e.status, 'status', 409)),
      );
      await expectLater(
        installations.create(id: '../x', name: 'böse'),
        throwsA(isA<InstallationException>().having((e) => e.status, 'status', 400)),
      );
      await expectLater(
        installations.create(name: ' '),
        throwsA(isA<InstallationException>().having((e) => e.status, 'status', 400)),
      );

      await installations.rename(created.id, 'Meier, Ulm');
      await expectLater(
        installations.delete('default'),
        throwsA(isA<InstallationException>().having((e) => e.status, 'status', 409)),
      );
      await installations.delete(generated.id);
      expect(await installations.rootOf(generated.id).exists(), isFalse);

      final reopened = await Installations.open(data);
      expect(reopened.list.map((i) => i.name), [Installations.defaultName, 'Meier, Ulm']);
    });
  });

  group('Server', () {
    late InstallationService service;
    late HttpServer server;
    final client = HttpClient();

    setUp(() async {
      await write('catalog.json', '{"project":"Alt"}');
      service = InstallationService(
        await Installations.open(data),
        (root, installation) => BusService(root, describe: (_, _) async => null, installation: installation),
      );
      await service.start();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      // Wie server.dart; „x-admin: 0“ steht für einen Gerätezugang.
      server.listen((request) async {
        final path = request.uri.path;
        final admin = request.headers.value('x-admin') != '0';
        if (await serveInstallations(request, service, admin: admin)) return;
        if (path == '/ws/bus') return service.bus.serve(await WebSocketTransformer.upgrade(request));
        if (path.startsWith('/api/files/')) {
          return serveFile(request, service.installations.root, path.substring('/api/files/'.length));
        }
        request.response.statusCode = 404;
        await request.response.close();
      });
    });

    tearDown(() async {
      await service.shutdown();
      await server.close(force: true);
    });

    Future<(int, String)> send(
      String path, {
      String method = 'GET',
      Object? json,
      String? body,
      bool admin = true,
    }) async {
      final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:${server.port}$path'));
      if (!admin) request.headers.set('x-admin', '0');
      if (json != null) request.write(jsonEncode(json));
      if (body != null) request.write(body);
      final response = await request.close();
      return (response.statusCode, await utf8.decodeStream(response));
    }

    test('anlegen, wechseln, Dateien je Installation, alte nur lesen', () async {
      var (status, text) = await send('/api/installations');
      expect(status, 200);
      expect(jsonDecode(text), {
        'active': 'default',
        'list': [
          {'id': 'default', 'name': 'Alt', 'created': isA<int>(), 'active': true},
        ],
      });

      (status, text) = await send('/api/installations', method: 'POST', json: {'id': 'b1', 'name': 'Neu'});
      expect(status, 201);
      expect(jsonDecode(text), containsPair('id', 'b1'));
      expect((await send('/api/installations', method: 'POST', json: {'id': 'b1', 'name': 'x'})).$1, 409);

      // Busverbindung der neuen Installation liegt schon bereit.
      await write('installations/b1/server.json', '{"retentionDays":42}');
      (status, text) = await send('/api/installations/active', method: 'POST', json: {'id': 'b1'});
      expect(status, 200);
      expect(jsonDecode(text), containsPair('active', 'b1'));
      expect(service.bus.config.retentionDays, 42);
      expect(service.bus.status()['installation'], {'id': 'b1', 'name': 'Neu'});
      expect(jsonDecode((await read('installations.json'))!), containsPair('active', 'b1'));

      // /api/files/ zeigt jetzt in b1.
      expect((await send('/api/files/catalog.json')).$1, 404);
      expect((await send('/api/files/catalog.json', method: 'PUT', body: '{"project":"Neu"}')).$1, 204);
      expect(await read('installations/b1/catalog.json'), '{"project":"Neu"}');
      expect(await read('installations/default/catalog.json'), '{"project":"Alt"}');

      // Alte Installation: lesen ja, schreiben nein. Ein Gerät ohne Admin-Recht sieht nur
      // die aktive: frühere Kunden und Baustellen gehen es nichts an.
      (status, text) = await send('/api/installations/default/files/catalog.json');
      expect((status, text), (200, '{"project":"Alt"}'));
      expect((await send('/api/installations/default/files/catalog.json', admin: false)).$1, 403);
      expect((await send('/api/installations/default/files/history/', admin: false)).$1, 403);
      expect((await send('/api/installations/b1/files/catalog.json', admin: false)).$1, 200);
      (status, text) = await send('/api/installations', admin: false);
      expect(jsonDecode(text), {
        'active': 'b1',
        'list': [containsPair('id', 'b1')],
      });
      expect(((jsonDecode((await send('/api/installations')).$2) as Map)['list'] as List).length, 2);
      for (final method in ['PUT', 'POST', 'DELETE']) {
        expect((await send('/api/installations/default/files/catalog.json', method: method, body: '{}')).$1, 405);
      }
      expect(await read('installations/default/catalog.json'), '{"project":"Alt"}');
      expect((await send('/api/installations/zzz/files/catalog.json')).$1, 404);

      // Gepackte Verlaufstage: Liste ohne .gz, entpackt geliefert.
      final day = File('${data.path}/installations/default/history/2026-10-01.ndjson.gz');
      await day.parent.create(recursive: true);
      await day.writeAsBytes(gzip.encode(utf8.encode('{"t":1}\n')));
      (status, text) = await send('/api/installations/default/files/history/');
      expect(jsonDecode(text), [
        {'name': '2026-10-01.ndjson', 'size': await day.length()},
      ]);
      expect((await send('/api/installations/default/files/history/2026-10-01.ndjson')).$2, '{"t":1}\n');

      // Umbenennen, löschen – die aktive nicht.
      (status, text) = await send('/api/installations/b1', method: 'PATCH', json: {'name': 'Kunde B'});
      expect(status, 200);
      expect(service.bus.status()['installation'], {'id': 'b1', 'name': 'Kunde B'});
      expect((await send('/api/installations/b1', method: 'DELETE')).$1, 409);
      expect((await send('/api/installations/default', method: 'DELETE')).$1, 204);
      expect(await Directory('${data.path}/installations/default').exists(), isFalse);
      expect((await send('/api/installations/active', method: 'POST', json: {'id': 'default'})).$1, 404);
    });

    test('Gerätezugang: lesen ja, verwalten nein', () async {
      expect((await send('/api/installations', admin: false)).$1, 200);
      expect((await send('/api/installations', method: 'POST', json: {'name': 'x'}, admin: false)).$1, 403);
      expect((await send('/api/installations/active', method: 'POST', json: {'id': 'default'}, admin: false)).$1, 403);
      expect((await send('/api/installations/default', method: 'PATCH', json: {'name': 'x'}, admin: false)).$1, 403);
      expect((await send('/api/installations/default', method: 'DELETE', admin: false)).$1, 403);
      expect(service.installations.list.single.name, 'Alt');
    });

    test('Verzeichnis und Busverbindungen nie über die Dateiablage', () async {
      await write('installations/default/server.json', '{"secure":{"userPassword":"geheim"}}');
      for (final path in [
        '/api/files/installations.json',
        '/api/files/server.json',
        '/api/files/installations/default/server.json',
        '/api/installations/default/files/server.json',
        '/api/installations/default/files/installations/',
      ]) {
        for (final method in ['GET', 'PUT', 'POST', 'DELETE']) {
          final (status, _) = await send(path, method: method, body: method == 'GET' ? null : '{}');
          expect(status, anyOf(403, 405), reason: '$method $path');
        }
      }
      expect(await read('installations/default/server.json'), '{"secure":{"userPassword":"geheim"}}');
      expect(jsonDecode((await read('installations.json'))!), containsPair('active', 'default'));
      expect(jsonDecode((await send('/api/files/history/')).$2), isEmpty);
      // Den Ordner selbst listet die Ablage nicht (wie bisher den Datenordner).
      expect((await send('/api/installations/default/files/')).$1, 400);
    });

    test('Wechsel schließt offene Ansichten, Status nennt die Installation', () async {
      final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}/ws/bus');
      final states = <Map<String, Object?>>[];
      final done = Completer<void>();
      ws.listen((m) {
        if (m is List<int> && m.first == 0x02) {
          states.add(jsonDecode(utf8.decode(m.sublist(1))) as Map<String, Object?>);
        }
      }, onDone: done.complete);
      await until(() => states.isNotEmpty);
      expect(states.first['installation'], {'id': 'default', 'name': 'Alt'});
      await service.installations.create(id: 'b2', name: 'Zwei');
      await service.activate('b2');
      await done.future.timeout(const Duration(seconds: 5));
      expect(ws.closeCode, WebSocketStatus.goingAway);
    });

    test('Auswertung und Ausfälle einer anderen Installation', () async {
      final now = DateTime.now();
      await service.bus.recorder.flush();
      await write(
        'installations/default/history/${Recorder.dayName(now)}.ndjson',
        '${jsonEncode({'t': now.microsecondsSinceEpoch, 'd': 2563, 's': 4357})}\n',
      );
      await service.installations.create(id: 'c', name: 'Drei');
      await service.activate('c');
      expect((await service.recorderOf('default').stats(7))['total'], 1);
      expect((await service.recorderOf('c').stats(7))['total'], 0);
      final availability = service.availabilityOf('default');
      await availability.beat(connected: true, telegrams: 1, now: now.subtract(const Duration(minutes: 10)));
      await availability.beat(connected: false, telegrams: 0, now: now.subtract(const Duration(minutes: 9)));
      expect(
        await File('${data.path}/installations/default/status/availability-${_month(now)}.ndjson').exists(),
        isTrue,
      );
      expect(await service.availabilityOf('default').outages(now.subtract(const Duration(hours: 1)), now), isNotEmpty);
    });
  });
  group('Ausfallsicherheit', () {
    test('kaputter Index: Liste aus den Ordnern, kaputte Datei bleibt liegen', () async {
      await write('installations/aaaaaaaaaaaa/catalog.json', '{"project":"Musterhaus","groups":[]}');
      await write('installations/bbbbbbbbbbbb/catalog.json', '{"project":"Büro","groups":[]}');
      await write('installations.json', '{"version":1,"list":[{"id":');
      final installations = await Installations.open(data);
      expect(installations.list.map((i) => i.name).toSet(), {'Musterhaus', 'Büro'});
      final corrupt = await data.list().where((e) => e.path.contains('installations.json.corrupt-')).toList();
      expect(corrupt, hasLength(1));
    });

    test('kaputter Index: Sicherung vom letzten Speichern wird übernommen', () async {
      await write('catalog.json', '{"project":"Musterhaus","groups":[]}');
      final first = await Installations.open(data);
      await first.create(name: 'Büro');
      await first.create(name: 'Lager'); // Zweites Speichern: Sicherung enthält „Büro“.
      await write('installations.json', 'kaputt');
      final again = await Installations.open(data);
      expect(again.list.map((i) => i.name), containsAll(['Musterhaus', 'Büro']));
      // Der gerettete Stand ist wieder der Index, der kaputte liegt daneben.
      expect(jsonDecode((await read('installations.json'))!), isA<Map<String, Object?>>());
      expect(await data.list().where((e) => e.path.contains('installations.json.corrupt-')).length, 1);
    });

    test('„active“ mit falschem Typ bricht den Start nicht ab', () async {
      await write(
        'installations.json',
        jsonEncode({
          'version': 1,
          'active': 7,
          'list': [
            {'id': 'aaaaaaaaaaaa', 'name': 'Musterhaus', 'created': 0},
          ],
        }),
      );
      final installations = await Installations.open(data);
      expect(installations.activeId, 'aaaaaaaaaaaa');
    });

    test('ein kaputter Eintrag nimmt die anderen nicht mit', () async {
      await write(
        'installations.json',
        jsonEncode({
          'version': 2,
          'active': 'aaaaaaaaaaaa',
          'list': [
            {'id': 'aaaaaaaaaaaa', 'name': 'Musterhaus', 'created': 0},
            {'id': 42},
          ],
        }),
      );
      final installations = await Installations.open(data);
      expect(installations.list.map((i) => i.name), ['Musterhaus']);
      expect(installations.activeId, 'aaaaaaaaaaaa');
    });
  });
}

String _month(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue);
}
