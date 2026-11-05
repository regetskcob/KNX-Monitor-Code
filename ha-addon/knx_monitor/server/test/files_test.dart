import 'dart:convert';
import 'dart:io';

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
    server.listen((request) => serveFile(request, data, request.uri.path.substring(1)));
  });

  tearDown(() async {
    await server.close(force: true);
    await data.delete(recursive: true);
  });

  Future<(int, String)> send(String path, {String method = 'GET', String? body}) async {
    final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:${server.port}/$path'));
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
}
