import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  var projectLoaded = true;
  var oldHomeAssistant = false;

  setUp(() async {
    projectLoaded = true;
    oldHomeAssistant = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      // Not closed here on purpose: the fake server closes it with the request.
      // ignore: close_sinks
      final ws = await WebSocketTransformer.upgrade(r);
      ws.add(jsonEncode({'type': 'auth_required'}));
      ws.listen((raw) {
        final m = jsonDecode(raw as String) as Map<String, Object?>;
        if (m['type'] == 'auth') {
          ws.add(jsonEncode({'type': m['access_token'] == 'geheim' ? 'auth_ok' : 'auth_invalid'}));
          return;
        }
        void reply(Object? result, {bool ok = true}) => ws.add(
          jsonEncode({
            'id': m['id'],
            'type': 'result',
            'success': ok,
            if (ok) 'result': result else 'error': {'code': 'unknown_command', 'message': 'Unknown command.'},
          }),
        );
        switch (m['type']) {
          case 'knx/get_knx_project':
            reply({
              'project_loaded': projectLoaded,
              'knxproject': projectLoaded
                  ? {
                      'info': {'name': 'Haus'},
                    }
                  : null,
            });
          case 'knx/get_entities_by_group':
            reply({'1/1/1': <Object?>[], '1/4/1': <Object?>[]}, ok: !oldHomeAssistant);
          case 'knx/get_expose_groups':
            reply({
              'sensor.aussen': ['8/1/2'],
            }, ok: !oldHomeAssistant);
        }
      });
    });
  });

  tearDown(() => server.close(force: true));

  HaKnxProject client({String token = 'geheim'}) =>
      HaKnxProject(token: token, websocket: 'ws://127.0.0.1:${server.port}/core/websocket');

  test('Projekt und Adressen, die Home Assistant beschreibt', () async {
    final r = (await client().fetch())!;
    expect(r['loaded'], isTrue);
    expect((r['project']! as Map)['info'], {'name': 'Haus'});
    expect(r['ha_groups'], ['1/1/1', '1/4/1', '8/1/2']);
  });

  test('ohne Projekt in der Integration', () async {
    projectLoaded = false;
    final r = (await client().fetch())!;
    expect(r['loaded'], isFalse);
    expect(r.containsKey('project'), isFalse);
  });

  test('ältere Home-Assistant-Version: Projekt ja, externe Sender nein', () async {
    oldHomeAssistant = true;
    final r = (await client().fetch())!;
    expect(r['loaded'], isTrue);
    expect(r['ha_groups'], isEmpty);
  });

  test('ohne Supervisor nichts, falscher Token Fehler', () async {
    expect(
      await HaKnxProject(token: null).fetch(),
      Platform.environment['SUPERVISOR_TOKEN'] == null ? isNull : isNotNull,
    );
    expect(client(token: 'falsch').fetch(), throwsStateError);
  });
}
