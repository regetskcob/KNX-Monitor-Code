import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:knx_monitor_server/files.dart';
import 'package:test/test.dart';

/// Die Dateiablage `/api/files/` gibt Daten der App heraus, nie die des
/// Servers: Ein gekoppeltes Gerät durfte sonst das Box-Passwort lesen oder
/// `access.json` überschreiben.
void main() {
  late Directory data;
  late HttpServer server;
  final client = HttpClient();

  setUp(() async {
    data = await Directory.systemTemp.createTemp('files');
    for (final name in [
      'access.json',
      'server.json',
      'box-password.txt',
      'time-request.json',
      'lan-access',
      'access.json.bak',
      'installations.json.corrupt-1',
      'catalog.json',
    ]) {
      await File('${data.path}/$name').writeAsString('{"name":"$name"}');
    }
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    // „x-owner: <id>“ steht für ein gekoppeltes Gerät ohne Admin-Recht, „x-view: 1“ für eins nur zum Ansehen.
    server.listen(
      (request) => serveFile(
        request,
        data,
        request.uri.path.substring(1),
        admin: request.headers.value('x-owner') == null,
        owner: request.headers.value('x-owner'),
        viewOnly: request.headers.value('x-view') == '1',
      ),
    );
  });

  tearDown(() async {
    await server.close(force: true);
    await data.delete(recursive: true);
  });

  Future<(int, String)> send(
    String path, {
    String method = 'GET',
    String? body,
    String? owner,
    bool view = false,
  }) async {
    final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:${server.port}/$path'));
    if (owner != null) request.headers.set('x-owner', owner);
    if (view) request.headers.set('x-view', '1');
    if (body != null) request.write(body);
    final response = await request.close();
    return (response.statusCode, await utf8.decodeStream(response));
  }

  test('fertige Tage: gepackt an gzip-Clients, sonst entpackt', () async {
    await Directory('${data.path}/history').create();
    const line = '{"t":1,"s":1,"d":1,"y":2,"x":"01"}\n';
    await File('${data.path}/history/2026-11-03.ndjson.gz').writeAsBytes(gzip.encode(utf8.encode(line * 100)));
    // dart:io asks for gzip and unpacks by itself: the content is the same.
    final (status, text) = await send('history/2026-11-03.ndjson');
    expect(status, 200);
    expect(text, line * 100);
    final raw = HttpClient()..autoUncompress = false;
    addTearDown(raw.close);
    Future<HttpClientResponse> get(String encoding) async {
      final request = await raw.getUrl(Uri.parse('http://127.0.0.1:${server.port}/history/2026-11-03.ndjson'));
      request.headers.set(HttpHeaders.acceptEncodingHeader, encoding);
      return request.close();
    }

    final packed = await get('gzip');
    expect(packed.headers.value(HttpHeaders.contentEncodingHeader), 'gzip');
    expect(utf8.decode(gzip.decode(await packed.fold<List<int>>([], (a, b) => a..addAll(b)))), line * 100);
    final plain = await get('identity');
    expect(plain.headers.value(HttpHeaders.contentEncodingHeader), isNull);
    expect(await utf8.decodeStream(plain), line * 100);
  });

  test('Daten der App: lesen und schreiben', () async {
    expect((await send('catalog.json')).$1, 200);
    expect((await send('catalog.json', method: 'PUT', body: '{}')).$1, 204);
    expect(await File('${data.path}/catalog.json').readAsString(), '{}');
  });

  test('Dateien des Servers: weder lesen noch schreiben noch löschen', () async {
    for (final name in [
      'access.json',
      'server.json',
      'box-password.txt',
      'time-request.json',
      'lan-access',
      'access.json.bak',
      'installations.json.corrupt-1',
    ]) {
      for (final method in ['GET', 'PUT', 'POST', 'DELETE']) {
        final (status, _) = await send(name, method: method, body: method == 'GET' ? null : '{}');
        expect(status, 403, reason: '$method $name');
      }
      expect(await File('${data.path}/$name').readAsString(), '{"name":"$name"}');
    }
  });

  test('Liste zeigt die Dateien des Servers nicht', () async {
    await Directory('${data.path}/sub').create();
    await File('${data.path}/sub/a.json').writeAsString('1');
    expect(jsonDecode((await send('sub/')).$2), [
      {'name': 'a.json', 'size': 1},
    ]);
  });

  test('gleichzeitige Schreibvorgänge: jeder ganz, keiner halb', () async {
    // Früher teilten sich alle die Zwischendatei „<datei>.tmp“: Einer benannte die halb
    // geschriebene des anderen um, oder das Umbenennen schlug fehl.
    final bodies = [
      for (var i = 0; i < 20; i++) jsonEncode({'n': i, 'pad': 'x' * (50000 + i)}),
    ];
    final results = await Future.wait([for (final b in bodies) send('catalog.json', method: 'PUT', body: b)]);
    expect(results.map((r) => r.$1), everyElement(204));
    expect(bodies, contains(await File('${data.path}/catalog.json').readAsString()));
    expect(data.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
  });

  group('Gerät ohne Admin-Recht', () {
    Future<Map<String, Object?>> stored(String name) async =>
        jsonDecode(await File('${data.path}/$name').readAsString()) as Map<String, Object?>;

    test('Wächter: eigene ändern und löschen, fremde bleiben', () async {
      await File('${data.path}/watch_rules.json').writeAsString(
        jsonEncode({
          'rules': [
            {'id': 'admin-1', 'address': 1},
            {'id': 'b-1', 'address': 2, 'owner': 'B'},
          ],
        }),
      );
      // A schickt seine Liste: ohne die fremden, mit einem Versuch, die des Admins zu ändern.
      var (status, _) = await send(
        'watch_rules.json',
        method: 'PUT',
        owner: 'A',
        body: jsonEncode({
          'rules': [
            {'id': 'a-1', 'address': 3},
            {'id': 'admin-1', 'address': 99},
            {'id': 'b-1', 'address': 99, 'owner': 'A'},
          ],
        }),
      );
      expect(status, 204);
      expect((await stored('watch_rules.json'))['rules'], [
        {'id': 'admin-1', 'address': 1},
        {'id': 'b-1', 'address': 2, 'owner': 'B'},
        {'id': 'a-1', 'address': 3, 'owner': 'A'},
      ]);
      // A löscht seine Regeln: die anderen bleiben.
      (status, _) = await send('watch_rules.json', method: 'PUT', owner: 'A', body: '{"rules":[]}');
      expect(status, 204);
      expect(((await stored('watch_rules.json'))['rules']! as List).map((r) => (r as Map)['id']), ['admin-1', 'b-1']);
      // Ungültiges ändert nichts.
      for (final body in ['kaputt', '[]', '{"rules":{}}', '{"rules":[{"address":1}]}']) {
        expect(
          (await send('watch_rules.json', method: 'PUT', owner: 'A', body: body)).$1,
          400,
          reason: body,
        );
      }
      expect(((await stored('watch_rules.json'))['rules']! as List), hasLength(2));
    });

    test('Diagramme: Freischaltung „allowed“ bleibt, wie sie ist', () async {
      expect(
        (await send(
          'charts.json',
          method: 'PUT',
          owner: 'A',
          body: jsonEncode({
            'allowed': true,
            'scope': 'a',
            'charts': [
              {'name': 'Temperatur', 'series': []},
            ],
          }),
        )).$1,
        204,
      );
      // Ohne gespeicherten Wert schaltet ein Gerät die Karte nicht frei.
      expect(await stored('charts.json'), {
        'scope': 'a',
        'allowed': false,
        'charts': [
          {'name': 'Temperatur', 'series': [], 'owner': 'A'},
        ],
      });
      await File('${data.path}/charts.json').writeAsString(
        jsonEncode({
          'allowed': true,
          'charts': [
            {'name': 'Strom', 'series': []},
          ],
        }),
      );
      await send('charts.json', method: 'PUT', owner: 'A', body: '{"allowed":false,"charts":[{"name":"Strom"}]}');
      expect(await stored('charts.json'), {
        'allowed': true,
        'charts': [
          {'name': 'Strom', 'series': []},
        ],
      });
    });

    test('nur zum Ansehen: schreibt gar nichts', () async {
      for (final name in ['charts.json', 'watch_rules.json', 'catalog.json']) {
        expect(
          (await send(name, method: 'PUT', owner: 'V', view: true, body: '{}')).$1,
          403,
          reason: name,
        );
      }
      expect((await send('catalog.json', owner: 'V', view: true)).$1, 200);
    });
  });

  test('Speicherbudget: gleichzeitige Uploads über 32 MiB warten', () async {
    // Ein einzelner großer Upload geht immer (Katalog bis 64 MiB).
    final budget = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => budget.close(force: true));
    final started = Completer<void>();
    budget.listen((request) async {
      try {
        final bytes = await readBody(request, 64 * 1024 * 1024);
        request.response.statusCode = bytes == null ? 413 : 204;
      } on BodyBudgetException {
        return answerBusy(request.response);
      }
      await request.response.close();
    });
    Future<HttpClientRequest> open(int length) async {
      final request = await client.openUrl('PUT', Uri.parse('http://127.0.0.1:${budget.port}/'));
      request.contentLength = length;
      return request;
    }

    // Der erste kündigt 30 MiB an und schickt erst einmal nur einen Teil.
    final first = await open(30 * 1024 * 1024);
    first.add(Uint8List(1024));
    await first.flush();
    unawaited(() async {
      while (bodiesInFlight == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      started.complete();
    }());
    await started.future;
    // Der zweite passt nicht mehr daneben.
    final second = await open(8 * 1024 * 1024);
    second.add(Uint8List(8 * 1024 * 1024));
    final answer = await second.close();
    expect(answer.statusCode, HttpStatus.serviceUnavailable);
    expect(answer.headers.value(HttpHeaders.retryAfterHeader), isNotNull);
    await answer.drain<void>();
    first.add(Uint8List(30 * 1024 * 1024 - 1024));
    expect((await first.close()).statusCode, 204);
    expect(bodiesInFlight, 0);
  });
}
