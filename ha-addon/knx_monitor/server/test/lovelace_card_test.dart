import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late Directory dir;
  late File template;
  late Directory config;
  var resources = <Map<String, Object?>>[];
  var yaml = false;
  final calls = <Map<String, Object?>>[];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('knx_card');
    template = File('${dir.path}/card.js')
      ..writeAsStringSync("const I = '__KNX_MONITOR_INGRESS__'; // __KNX_MONITOR_VERSION__");
    config = await Directory('${dir.path}/homeassistant').create();
    resources = [];
    yaml = false;
    calls.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      if (r.uri.path == '/addons/self/info') {
        r.response.headers.contentType = ContentType.json;
        r.response.write(
          jsonEncode({
            'result': 'ok',
            'data': {'ingress_entry': '/api/hassio_ingress/abc123'},
          }),
        );
        return r.response.close();
      }
      final ws = await WebSocketTransformer.upgrade(r);
      ws.add(jsonEncode({'type': 'auth_required'}));
      ws.listen((raw) {
        final m = jsonDecode(raw as String) as Map<String, Object?>;
        if (m['type'] == 'auth') {
          ws.add(jsonEncode({'type': m['access_token'] == 'geheim' ? 'auth_ok' : 'auth_invalid'}));
          return;
        }
        calls.add(m);
        Object? result;
        switch (m['type']) {
          case 'lovelace/resources':
            if (yaml) {
              ws.add(
                jsonEncode({
                  'id': m['id'],
                  'type': 'result',
                  'success': false,
                  'error': {'message': 'yaml'},
                }),
              );
              return;
            }
            result = resources;
          case 'lovelace/resources/create':
            resources.add({'id': 'r1', 'type': m['res_type'], 'url': m['url']});
          case 'lovelace/resources/update':
            resources = [
              for (final r in resources) r['id'] == m['resource_id'] ? {...r, 'url': m['url']} : r,
            ];
        }
        ws.add(jsonEncode({'id': m['id'], 'type': 'result', 'success': true, 'result': result}));
      });
    });
  });
  tearDown(() async {
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  LovelaceCard card({String? token = 'geheim'}) => LovelaceCard(
    template: template,
    token: token,
    config: config,
    supervisor: 'http://127.0.0.1:${server.port}',
    websocket: 'ws://127.0.0.1:${server.port}/core/websocket',
  );

  File installed() => File('${config.path}/www/knx-monitor/${LovelaceCard.fileName}');

  test('legt die Karte ab und meldet sie an, beim zweiten Start nichts', () async {
    final first = await card().install(version: '1.9.0');
    expect(first.message, 'angemeldet');
    expect(first.freshWww, isTrue);
    expect(installed().readAsStringSync(), "const I = '/api/hassio_ingress/abc123'; // 1.9.0");
    expect(resources.single['type'], 'module');
    expect(resources.single['url'], startsWith('${LovelaceCard.url}?v='));
    final second = await card().install(version: '1.9.0');
    expect(second.message, 'aktuell');
    expect(second.freshWww, isFalse);
    expect(calls.where((c) => c['type'] != 'lovelace/resources'), hasLength(1));
  });

  test('neue Fassung ersetzt die Ressource', () async {
    await card().install(version: '1.9.0');
    final old = resources.single['url'];
    expect((await card().install(version: '1.9.1')).message, 'aktualisiert');
    expect(resources, hasLength(1));
    expect(resources.single['url'], isNot(old));
  });

  test('YAML-Modus: Datei liegt, Hinweis statt Fehler', () async {
    yaml = true;
    final result = await card().install(version: '1.9.0');
    expect(result.message, contains('von Hand'));
    expect(installed().existsSync(), isTrue);
  });

  test('ohne Supervisor oder Konfigurationsordner: nichts tun', () async {
    expect((await card(token: null).install(version: '1')).message, 'ohne Supervisor');
    await config.delete();
    expect((await card().install(version: '1')).message, contains('map homeassistant_config'));
    expect(calls, isEmpty);
  });
}
