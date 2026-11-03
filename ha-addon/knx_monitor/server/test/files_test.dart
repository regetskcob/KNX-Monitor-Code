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
