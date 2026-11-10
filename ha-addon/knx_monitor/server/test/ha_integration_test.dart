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

  test('watchers: id and name only, no conditions or addresses', () async {
    await File('${data.path}/watch_rules.json').writeAsString(
      jsonEncode({
        'rules': [
          {
            'id': 'w1',
            'address': 2305,
            'label': '1/1/1 Fenster Bad = 1',
            'name': 'Fenster Bad offen',
            'check': {
              'values': [1],
              'small': true,
            },
          },
          {
            'id': 'w2',
            'address': 2306,
            'label': '1/1/2 Wind > 10',
            'check': {'any': true},
          },
        ],
      }),
    );
    final (code, body) = await call('GET', '/api/ha/watchers', token: ha.token);
    expect(code, HttpStatus.ok);
    expect(body, [
      {'id': 'w1', 'name': 'Fenster Bad offen'},
      {'id': 'w2', 'name': '1/1/2 Wind > 10'},
    ]);
  });

  group('silent addresses', () {
    // Seven days of history: the temperature every 5 minutes until a day ago,
    // the humidity every 5 minutes until now, a switch three times.
    const temperature = 0x0A03; // 1/2/3
    const humidity = 0x0A04; // 1/2/4
    const button = 0x0A05; // 1/2/5
    late DateTime now;

    Future<void> writeHistory() async {
      final byDay = <String, StringBuffer>{};
      void line(int ga, DateTime t, {int type = 2, bool own = false}) {
        (byDay[Recorder.dayName(t)] ??= StringBuffer()).writeln(
          jsonEncode({'t': t.microsecondsSinceEpoch, 's': 4402, 'd': ga, 'y': type, 'x': '0C1A', if (own) 'o': true}),
        );
      }

      final start = now.subtract(const Duration(days: 7));
      for (var t = start; t.isBefore(now); t = t.add(const Duration(minutes: 5))) {
        if (t.isBefore(now.subtract(const Duration(days: 1)))) line(temperature, t);
        line(humidity, t);
      }
      for (var i = 0; i < 3; i++) {
        line(button, now.subtract(Duration(hours: 30 + i)));
      }
      final dir = Directory('${data.path}/history')..createSync(recursive: true);
      for (final MapEntry(:key, :value) in byDay.entries) {
        File('${dir.path}/$key.ndjson').writeAsStringSync('$value', mode: FileMode.append);
      }
    }

    setUp(() async {
      now = DateTime.now();
      await writeHistory();
      await File('${data.path}/catalog.json').writeAsString(
        jsonEncode({
          'groups': [
            {'a': temperature, 'n': 'Temperatur Bad'},
          ],
        }),
      );
      // Recording on and connected for a week (no gateway in the test).
      bus.config.enabled = true;
      bus.state = 'connected';
      bus.since = now.subtract(const Duration(days: 7));
      await ha.cycles.check();
    });

    test('lists the sensor that stopped after day 6, with interval and last time', () async {
      final (code, body) = await call('GET', '/api/ha/silent', token: ha.token);
      expect(code, HttpStatus.ok);
      final list = (body! as List).cast<Map<String, Object?>>();
      expect(list, hasLength(1));
      expect(list.single['address'], '1/2/3');
      expect(list.single['interval_s'], 300);
      final last = DateTime.parse(list.single['last']! as String);
      expect(now.difference(last).inHours, inInclusiveRange(23, 24));
      final (_, state) = await call('GET', '/api/ha/state', token: ha.token);
      expect((state! as Map)['silent'], 1);
      // Diagnostics: only how many.
      final (_, diagnostics) = await call('GET', '/api/ha/diagnostics', token: ha.token);
      expect((diagnostics! as Map)['silent'], 1);
      expect(jsonEncode(diagnostics), isNot(contains('1/2/3')));
    });

    test('name from the catalog', () async {
      final (_, body) = await call('GET', '/api/ha/silent', token: ha.token);
      expect(((body! as List).single as Map)['name'], 'Temperatur Bad');
    });

    test('nothing while recording is off or the bus is gone', () async {
      bus.config.enabled = false;
      expect((await call('GET', '/api/ha/silent', token: ha.token)).$2, isEmpty);
      bus.config.enabled = true;
      bus.state = 'disconnected';
      expect((await call('GET', '/api/ha/silent', token: ha.token)).$2, isEmpty);
      expect(ha.state()['silent'], 0);
      // Just reconnected: the sensor has not had its chance yet.
      bus.state = 'connected';
      bus.since = DateTime.now().subtract(const Duration(minutes: 5));
      expect((await call('GET', '/api/ha/silent', token: ha.token)).$2, isEmpty);
    });

    // 10 Nov 2026: a repair after 81 minutes without "EG WC Präsenz" is noise.
    test('a short silence is not reported: at least twelve hours', () async {
      const presence = 0x0A06; // 1/2/6, every 5 minutes until six hours ago
      final byDay = <String, StringBuffer>{};
      for (
        var t = now.subtract(const Duration(days: 3));
        t.isBefore(now.subtract(const Duration(hours: 6)));
        t = t.add(const Duration(minutes: 5))
      ) {
        (byDay[Recorder.dayName(t)] ??= StringBuffer()).writeln(
          jsonEncode({'t': t.microsecondsSinceEpoch, 's': 4402, 'd': presence, 'y': 2, 'x': '01'}),
        );
      }
      for (final MapEntry(:key, :value) in byDay.entries) {
        File('${data.path}/history/$key.ndjson').writeAsStringSync('$value', mode: FileMode.append);
      }
      await ha.cycles.check();
      final (_, body) = await call('GET', '/api/ha/silent', token: ha.token);
      expect([for (final e in (body! as List).cast<Map<String, Object?>>()) e['address']], ['1/2/3']);
    });

    // While the recording was paused (or the server not running) no address could be heard.
    // The heartbeats tell: once a minute while recording, none in between.
    Future<void> heartbeats(List<(Duration, Duration)> agoRanges) async {
      final byMonth = <String, StringBuffer>{};
      for (final (from, to) in agoRanges) {
        for (var t = now.subtract(from); t.isBefore(now.subtract(to)); t = t.add(const Duration(minutes: 1))) {
          (byMonth['${t.year}-${t.month.toString().padLeft(2, '0')}'] ??= StringBuffer()).writeln(
            jsonEncode({'t': t.millisecondsSinceEpoch, 'c': true, 'n': 1}),
          );
        }
      }
      final dir = Directory('${bus.availability.data.path}/status')..createSync(recursive: true);
      for (final MapEntry(:key, :value) in byMonth.entries) {
        File('${dir.path}/availability-$key.ndjson').writeAsStringSync('$value');
      }
    }

    test('time the recording did not cover does not count', () async {
      // The temperature stopped a day ago. Of that day the recording was paused from 20 until
      // 2 hours ago: 6 hours of real silence, not 24.
      await heartbeats([
        (const Duration(days: 3), const Duration(hours: 20)),
        (const Duration(hours: 2), Duration.zero),
      ]);
      await ha.cycles.check();
      expect((await call('GET', '/api/ha/silent', token: ha.token)).$2, isEmpty);
    });

    test('a bus that is quiet but recorded still lets a stopped address be reported', () async {
      // Heartbeats all the time: the day of silence is real.
      await heartbeats([(const Duration(days: 3), Duration.zero)]);
      await ha.cycles.check();
      expect(((await call('GET', '/api/ha/silent', token: ha.token)).$2! as List), hasLength(1));
    });

    test('hours from the settings: 1 to 168, anything else is twelve', () {
      expect(CycleWatch.parseMinSilence(6), const Duration(hours: 6));
      expect(CycleWatch.parseMinSilence(' 24 '), const Duration(hours: 24));
      for (final bad in [null, 0, 169, -3, 'bald', 1.5]) {
        expect(CycleWatch.parseMinSilence(bad), const Duration(hours: 12), reason: '$bad');
      }
    });

    test('leaves the list as soon as the address sends again', () async {
      ha.cycles.observe(bus, {'t': now.microsecondsSinceEpoch, 'd': temperature, 'y': 2, 'x': '0C1A'});
      expect((await call('GET', '/api/ha/silent', token: ha.token)).$2, isEmpty);
    });

    test('ignore is kept in cycle_watch.json and ends when it sends again', () async {
      var (code, _) = await call('POST', '/api/ha/silent/ignore', token: ha.token, body: {'address': '1/2/4'});
      expect(code, HttpStatus.notFound, reason: 'the humidity is not silent');
      (code, _) = await call('POST', '/api/ha/silent/ignore', token: ha.token, body: {'address': 3});
      expect(code, HttpStatus.badRequest);
      (code, _) = await call('POST', '/api/ha/silent/ignore', token: ha.token, body: {'address': '1/2/3'});
      expect(code, HttpStatus.ok);
      expect((await call('GET', '/api/ha/silent', token: ha.token)).$2, isEmpty);
      final file = File('${data.path}/cycle_watch.json');
      expect(jsonDecode(file.readAsStringSync())['ignored'], contains('$temperature'));
      // Still ignored after a restart and a new check.
      ha.stop();
      ha = create();
      await ha.start(tick: const Duration(hours: 1));
      await ha.cycles.check();
      expect((await call('GET', '/api/ha/silent', token: ha.token)).$2, isEmpty);
      // Sends again: no longer ignored, and reported again if it stops once more.
      ha.cycles.observe(bus, {'t': now.microsecondsSinceEpoch, 'd': temperature, 'y': 2, 'x': '0C1A'});
      await until(() => !file.readAsStringSync().contains('$temperature'));
    });

    test('completed days are read once, the open day at every check', () async {
      // Pack all days but today, as the recorder does after midnight.
      final today = Recorder.dayName(now);
      for (final f in Directory('${data.path}/history').listSync().whereType<File>()) {
        final name = f.uri.pathSegments.last;
        if (!name.endsWith('.ndjson') || name.startsWith(today)) continue;
        File('${f.path}.gz').writeAsBytesSync(gzip.encode(f.readAsBytesSync()));
        f.deleteSync();
      }
      await ha.cycles.check();
      final first = ha.cycles.daysRead;
      await ha.cycles.check();
      expect(ha.cycles.daysRead - first, 1, reason: 'only today is read again');
      final list = (await call('GET', '/api/ha/silent', token: ha.token)).$2! as List;
      expect(list.single['address'], '1/2/3');
      // A changed packed day (other size) is read again.
      final yesterday = File(
        '${data.path}/history/${Recorder.dayName(now.subtract(const Duration(days: 1)))}.ndjson.gz',
      );
      yesterday.writeAsBytesSync(gzip.encode([...gzip.decode(yesterday.readAsBytesSync()), ...utf8.encode('\n')]));
      final before = ha.cycles.daysRead;
      await ha.cycles.check();
      expect(ha.cycles.daysRead - before, 2);
    });

    test('a sender that came back while the server was down is not ignored any more', () async {
      await call('POST', '/api/ha/silent/ignore', token: ha.token, body: {'address': '1/2/3'});
      final day = Recorder.dayName(now);
      File('${data.path}/history/$day.ndjson').writeAsStringSync(
        '${jsonEncode({'t': now.microsecondsSinceEpoch, 's': 4402, 'd': temperature, 'y': 2, 'x': '0C1A'})}\n',
        mode: FileMode.append,
      );
      await ha.cycles.check();
      expect(jsonDecode(File('${data.path}/cycle_watch.json').readAsStringSync())['ignored'], isEmpty);
    });
  });

  test('without token access (box, Docker): no token, the token check never passes', () async {
    // The add-on's own announcement from setUp first.
    await until(() => calls.any((c) => c.$2 == '/discovery'));
    calls.clear();
    ha.stop();
    final box = HaIntegration(data, () => bus, version: '1.9.7', port: 8765, tokenAccess: false);
    await box.start(tick: const Duration(hours: 1));
    expect(box.token, isNull);
    final token = jsonDecode(File('${data.path}/ha_integration.json').readAsStringSync()) as Map;
    expect(token.containsKey('token'), isFalse);
    expect(calls.where((c) => c.$2 == '/discovery'), isEmpty);
    box.stop();
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
