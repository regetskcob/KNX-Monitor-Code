import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

void main() {
  late Directory data;
  late BusService bus;
  late HttpServer supervisor;
  late List<(String, String, Map<String, Object?>?)> calls;
  late HaIntegration ha;
  late HttpServer server;
  final claims = <bool>[];

  HaIntegration create() => HaIntegration(
    data,
    () => bus,
    version: '1.9.7',
    port: 8765,
    supervisorToken: 'supervisor',
    supervisor: Uri.parse('http://127.0.0.1:${supervisor.port}/'),
    onClaim: claims.add,
  );

  setUp(() async {
    data = await Directory.systemTemp.createTemp('knx_ha');
    bus = BusService(data, describe: (_, _) async => null, installation: {'id': 'a', 'name': 'Zuhause'});
    await bus.start();
    claims.clear();
    calls = [];
    // Supervisor: own info and discovery.
    supervisor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    supervisor.listen((r) async {
      final text = await utf8.decoder.bind(r).join();
      calls.add((r.method, r.uri.path, text.isEmpty ? null : (jsonDecode(text) as Map).cast<String, Object?>()));
      expect(r.headers.value(HttpHeaders.authorizationHeader), 'Bearer supervisor');
      r.response.headers.contentType = ContentType.json;
      r.response.write(
        jsonEncode(
          r.uri.path == '/addons/self/info'
              ? {
                  'result': 'ok',
                  'data': {'hostname': 'a0d7b954-knx-monitor'},
                }
              : {
                  'result': 'ok',
                  'data': {'uuid': 'x'},
                },
        ),
      );
      await r.response.close();
    });
    ha = create();
    await ha.start(tick: const Duration(hours: 1));
    // Routing as in server.dart: the token opens only /api/ha/.
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      if (HaIntegration.handles(r.uri.path) && ha.authorized(r)) {
        await ha.serve(r);
      } else {
        r.response.statusCode = HttpStatus.forbidden;
        await r.response.close();
      }
    });
  });

  tearDown(() async {
    ha.stop();
    await server.close(force: true);
    await supervisor.close(force: true);
    await bus.shutdown();
    await data.delete(recursive: true);
  });

  Future<(int, Object?)> call(String method, String path, {String? token, Object? body}) async {
    final client = HttpClient();
    try {
      final req = await client.openUrl(method, Uri.parse('http://127.0.0.1:${server.port}$path'));
      if (token != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (body != null) req.write(jsonEncode(body));
      final res = await req.close();
      final text = await utf8.decoder.bind(res).join();
      final json = res.headers.contentType?.mimeType == 'application/json';
      return (res.statusCode, !json || text.isEmpty || res.statusCode >= 300 ? text : jsonDecode(text));
    } finally {
      client.close(force: true);
    }
  }

  test('token is created once and kept across restarts', () async {
    final token = ha.token!;
    expect(token, hasLength(64));
    ha.stop();
    final again = create();
    await again.start(tick: const Duration(hours: 1));
    expect(again.token, token);
    again.stop();
  });

  test('announces host, port and token to the Supervisor', () async {
    await until(() => calls.any((c) => c.$2 == '/discovery'));
    final discovery = calls.firstWhere((c) => c.$2 == '/discovery');
    expect(discovery.$1, 'POST');
    expect(discovery.$3!['service'], 'knx_monitor');
    expect(discovery.$3!['config'], {'host': 'a0d7b954-knx-monitor', 'port': 8765, 'token': ha.token});
  });

  test('without the right token nothing gets through', () async {
    expect((await call('GET', '/api/ha/state')).$1, HttpStatus.forbidden);
    expect((await call('GET', '/api/ha/state', token: 'wrong')).$1, HttpStatus.forbidden);
    expect((await call('GET', '/api/ha/state', token: '${ha.token}x')).$1, HttpStatus.forbidden);
    // Other endpoints stay closed even with the token.
    expect((await call('GET', '/api/bus', token: ha.token)).$1, HttpStatus.forbidden);
    expect((await call('GET', '/api/files/catalog.json', token: ha.token)).$1, HttpStatus.forbidden);
  });

  test('state carries the key figures of the MQTT device', () async {
    final (code, body) = await call('GET', '/api/ha/state', token: ha.token);
    expect(code, HttpStatus.ok);
    final state = body! as Map<String, Object?>;
    expect(state['version'], '1.9.7');
    expect(state['installation'], 'Zuhause');
    expect(
      state.keys,
      containsAll(['connected', 'recording', 'per_minute', 'today', 'bus_load', 'open_alarms', 'low_space']),
    );
    expect(state['claimed'], isFalse);
  });

  test('recording on and off', () async {
    var (code, body) = await call('POST', '/api/ha/recording', token: ha.token, body: {'on': true});
    expect(code, HttpStatus.ok);
    expect((body! as Map)['recording'], isTrue);
    expect(bus.config.enabled, isTrue);
    (code, body) = await call('POST', '/api/ha/recording', token: ha.token, body: {'on': false});
    expect((body! as Map)['recording'], isFalse);
    expect(bus.config.enabled, isFalse);
    (code, _) = await call('POST', '/api/ha/recording', token: ha.token, body: {'on': 'yes'});
    expect(code, HttpStatus.badRequest);
  });

  test('claim switches the MQTT entities off and on again, and is kept', () async {
    await call('POST', '/api/ha/claim', token: ha.token);
    expect(claims, [true]);
    expect(ha.claimed, isTrue);
    // Twice changes nothing.
    await call('POST', '/api/ha/claim', token: ha.token);
    expect(claims, [true]);
    ha.stop();
    final again = create();
    await again.start(tick: const Duration(hours: 1));
    expect(again.claimed, isTrue);
    again.stop();
    await call('DELETE', '/api/ha/claim', token: ha.token);
    expect(claims, [true, false]);
    expect(ha.claimed, isFalse);
  });

  test('claim is given back when the integration stays away', () async {
    var now = DateTime(2026, 11, 4, 12);
    ha.stop();
    final away = HaIntegration(
      data,
      () => bus,
      version: '1.9.7',
      port: 8765,
      supervisorToken: 'supervisor',
      supervisor: Uri.parse('http://127.0.0.1:${supervisor.port}/'),
      onClaim: claims.add,
      clock: () => now,
    );
    await away.start(tick: const Duration(hours: 1));
    await away.serve(await _fakeClaim(away));
    expect(away.claimed, isTrue);
    now = now.add(const Duration(minutes: 30));
    await away.checkClaim();
    expect(away.claimed, isTrue);
    now = now.add(const Duration(minutes: 31));
    await away.checkClaim();
    expect(away.claimed, isFalse);
    expect(claims, [true, false]);
    away.stop();
  });

  test('diagnostics without installation name', () async {
    final (code, body) = await call('GET', '/api/ha/diagnostics', token: ha.token);
    expect(code, HttpStatus.ok);
    final text = jsonEncode(body);
    expect(text, isNot(contains('Zuhause')));
    expect((body! as Map).containsKey('error'), isFalse, reason: 'the error text can name the gateway');
    expect((body as Map)['version'], '1.9.7');
    expect(body['storage'], isA<Map<String, Object?>>());
  });

  test('history as ETS file and report', () async {
    var (code, body) = await call('GET', '/api/ha/history?days=1', token: ha.token);
    expect(code, HttpStatus.ok);
    expect(body, startsWith('<?xml'));
    (code, body) = await call('POST', '/api/ha/report', token: ha.token);
    expect(code, HttpStatus.ok);
  });
}

/// A claim request as the integration sends it, for [HaIntegration.serve] directly.
Future<HttpRequest> _fakeClaim(HaIntegration ha) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final request = server.first;
  final client = HttpClient();
  final req = await client.post('127.0.0.1', server.port, '/api/ha/claim');
  req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${ha.token}');
  unawaited(req.close().then((r) => r.drain<void>()).whenComplete(() => client.close()));
  final r = await request;
  expect(ha.authorized(r), isTrue);
  unawaited(server.close());
  return r;
}

Future<void> until(bool Function() condition, {Duration timeout = const Duration(seconds: 5)}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) fail('condition not met after ${timeout.inSeconds} s');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
