import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

/// The server's health check (health_check.dart, issue #12): the rules it shares with the app
/// (`lib/model/health.dart`; the cases marked "as in the app" are those of the app's
/// `test/health_test.dart`), the schedule, one run at a time, and the routes below `/api/ha/`.

int ga(String s) {
  final p = s.split('/').map(int.parse).toList();
  return p[0] << 11 | p[1] << 8 | p[2];
}

int pa(String s) {
  final p = s.split('.').map(int.parse).toList();
  return p[0] << 12 | p[1] << 8 | p[2];
}

final temp = ga('2/0/0');
final hum = ga('2/1/0');
final wind = ga('8/1/1');
final noDpt = ga('9/0/0');
final presence = ga('8/3/0');
final scene = ga('5/0/1');

/// The project of the app's health tests, as the app stores it for the server.
Map<String, Object?> catalogJson() => {
  'groups': [
    {
      'a': temp,
      'n': 'EG FL Ist-Temperatur',
      'd': [9, 1],
    },
    {
      'a': hum,
      'n': 'EG FL Feuchte',
      'd': [9, 7],
    },
    {
      'a': wind,
      'n': 'Wind',
      'd': [9, 5],
    },
    {'a': noDpt, 'n': 'Ohne DPT Status'},
    {
      'a': presence,
      'n': 'Präsenz',
      'd': [1, 18],
    },
    {
      'a': scene,
      'n': 'Szene',
      'd': [17, 1],
    },
  ],
  'devices': [
    {'a': pa('1.1.7'), 'n': 'Taster Flur'},
    {'a': pa('1.1.50'), 'n': 'Wetterstation'},
  ],
};

class _Link implements BusLink {
  final sent = <Uint8List>[];
  final _frames = StreamController<Uint8List>.broadcast();
  final _lost = Completer<String>();
  @override
  Stream<Uint8List> get frames => _frames.stream;
  @override
  int? get address => 0x1101;
  @override
  String get label => 'Test';
  @override
  Future<void> connect() async {}
  @override
  Future<void> send(Uint8List cemi) async => sent.add(cemi);
  @override
  Future<String> get lost => _lost.future;
  @override
  Future<void> close() async {
    if (!_lost.isCompleted) _lost.complete('Getrennt');
    await _frames.close();
  }
}

void main() {
  final now = DateTime(2026, 10, 17, 12);
  late HealthScan scan;

  void t(
    int dest,
    List<int> data,
    DateTime time, {
    int? source,
    bool small = false,
    int type = 2,
    bool own = false,
    bool repeated = false,
  }) => scan.addTelegram(
    time: time.microsecondsSinceEpoch,
    source: source ?? pa('1.1.50'),
    destination: dest,
    type: type,
    payload: hexOf(data),
    small: small,
    outgoing: own,
    repeated: repeated,
  );

  List<(String, String?)> found([List<Map<String, Object?>>? f]) => [
    for (final x in f ?? scan.finish()) (x['kind']! as String, (x['address'] ?? x['device']) as String?),
  ];

  setUp(() => scan = HealthScan(LintCatalog.fromJson(catalogJson()), now: now));

  group('readings', () {
    test('implausible and stuck (as in the app)', () {
      t(temp, encodeDpt9(85)!, now);
      for (var i = 0; i < 14; i++) {
        t(hum, encodeDpt9(45)!, now.subtract(Duration(hours: i)));
      }
      final f = scan.finish();
      expect(found(f), unorderedEquals([('out_of_range', '2/0/0'), ('stuck', '2/1/0')]));
      final range = f.firstWhere((x) => x['kind'] == 'out_of_range');
      expect(range['severity'], 'error');
      expect(range['area'], 'readings');
      expect(range['text'], 'healthOutOfRange');
      expect(range['name'], 'EG FL Ist-Temperatur');
      expect(range['value'], closeTo(85, 0.1));
      expect(range['unit'], '°C');
      expect(range['source'], '1.1.50');
      expect(range['source_name'], 'Wetterstation');
      final stuck = f.firstWhere((x) => x['kind'] == 'stuck');
      expect(stuck['severity'], 'warning');
      expect(stuck['value'], 45);
      expect(stuck['unit'], '%');
      expect(DateTime.parse(stuck['since']! as String), now.subtract(const Duration(hours: 13)).toUtc());
    });

    test('only the newest value decides about the range, in any order of the lines', () {
      t(temp, encodeDpt9(21)!, now);
      t(temp, encodeDpt9(85)!, now.subtract(const Duration(hours: 1)));
      expect(scan.finish(), isEmpty);
    });

    test('the limits themselves are plausible, and wind has no "stuck"', () {
      t(temp, encodeDpt9(60)!, now);
      t(hum, encodeDpt9(100)!, now);
      for (var i = 0; i < 14; i++) {
        t(wind, encodeDpt9(0)!, now.subtract(Duration(hours: i)));
      }
      expect(scan.finish(), isEmpty);
    });

    test('not stuck: too few telegrams, too short a span, a changing value, older than a day', () {
      for (var i = 0; i < 11; i++) {
        t(hum, encodeDpt9(45)!, now.subtract(Duration(hours: i)));
      }
      expect(scan.finish(), isEmpty, reason: '11 telegrams');

      scan = HealthScan(LintCatalog.fromJson(catalogJson()), now: now);
      for (var i = 0; i < 14; i++) {
        t(hum, encodeDpt9(45)!, now.subtract(Duration(minutes: i * 50)));
      }
      expect(scan.finish(), isEmpty, reason: 'less than 12 hours');

      scan = HealthScan(LintCatalog.fromJson(catalogJson()), now: now);
      for (var i = 0; i < 14; i++) {
        t(hum, encodeDpt9(i == 7 ? 46 : 45)!, now.subtract(Duration(hours: i)));
      }
      expect(scan.finish(), isEmpty, reason: 'one other value');

      scan = HealthScan(LintCatalog.fromJson(catalogJson()), now: now);
      for (var i = 0; i < 14; i++) {
        t(hum, encodeDpt9(45)!, now.subtract(Duration(hours: 25 + i)));
      }
      expect(scan.finish(), isEmpty, reason: 'only the last 24 hours count');
    });
  });

  group('datapoint types', () {
    test('length and value per sender, mixed lengths without a type (as in the app)', () {
      t(temp, encodeDpt9(21)!, now);
      t(temp, [21], now, source: pa('1.1.7')); // 1 byte instead of 2
      t(temp, [21], now, source: pa('1.1.7'));
      t(wind, [0x7F, 0xFF], now, source: pa('1.2.20')); // "invalid"
      t(noDpt, [1], now, small: true);
      t(noDpt, [0, 1], now, source: pa('1.1.8'));
      final f = scan.finish();
      final size = f.firstWhere((x) => x['kind'] == 'dpt_size');
      expect(
        (size['address'], size['source'], size['actual'], size['expected'], size['count']),
        ('2/0/0', '1.1.7', 1, 2, 2),
      );
      expect(size['source_name'], 'Taster Flur');
      expect(size['dpt'], '9.001');
      expect(size['severity'], 'error');
      final value = f.firstWhere((x) => x['kind'] == 'dpt_value');
      expect((value['address'], value['source'], value['raw'], value['count']), ('8/1/1', '1.2.20', '7FFF', 1));
      final mixed = f.firstWhere((x) => x['kind'] == 'mixed_sizes');
      expect((mixed['address'], mixed['count']), ('9/0/0', 2));
      // As a full run of the app: the "invalid" marker of DPT 9 decodes to 670,760 m/s, which is
      // out of range as well.
      expect(found(f), [
        ('out_of_range', '8/1/1'),
        ('dpt_size', '2/0/0'),
        ('dpt_value', '8/1/1'),
        ('mixed_sizes', '9/0/0'),
      ]);
    });

    test('matching lengths, read requests and addresses outside the project are no findings', () {
      t(temp, encodeDpt9(21)!, now);
      t(presence, [1], now, small: true);
      t(scene, [63], now);
      t(noDpt, [1], now, small: true);
      t(noDpt, [0], now, small: true, source: pa('1.1.8'));
      // A read request carries no value.
      t(temp, [0], now, small: true, type: 0);
      // Not in the project: nothing to compare with.
      t(ga('15/7/1'), [1, 2, 3], now);
      t(ga('15/7/1'), [1], now);
      expect(found().where((f) => f.$1 != 'unanswered_reads'), isEmpty);
    });

    test('a scene number above 63 is invalid', () {
      t(scene, [64], now);
      expect(found(), [('dpt_value', '5/0/1')]);
    });
  });

  group('bus', () {
    test('a sender that repeats 5 % of at least 20 telegrams', () {
      for (var i = 0; i < 20; i++) {
        t(
          presence,
          [1],
          now.subtract(Duration(minutes: i)),
          small: true,
          source: pa('1.1.7'),
          repeated: i == 0,
        );
      }
      final f = scan.finish();
      expect(found(f), [('repeats', '1.1.7')]);
      expect(f.single['name'], 'Taster Flur');
      expect(f.single['rate'], 0.05);
      expect(f.single['count'], 20);
      expect(f.single['severity'], 'warning');
    });

    test('no finding below 20 telegrams, below 5 %, or for our own telegrams', () {
      for (var i = 0; i < 19; i++) {
        t(presence, [1], now, small: true, source: pa('1.1.7'), repeated: true);
      }
      for (var i = 0; i < 100; i++) {
        t(presence, [1], now, small: true, source: pa('1.1.8'), repeated: i < 4);
      }
      for (var i = 0; i < 40; i++) {
        t(presence, [1], now, small: true, source: pa('1.1.9'), repeated: true, own: true);
      }
      expect(scan.finish(), isEmpty);
    });

    test('two read requests without a response within 3 seconds', () {
      final start = now.subtract(const Duration(hours: 1));
      t(temp, [0], start, small: true, type: 0);
      t(temp, [0], start.add(const Duration(minutes: 1)), small: true, type: 0);
      // A response after the timeout answers nothing.
      t(temp, encodeDpt9(21)!, start.add(const Duration(minutes: 1, seconds: 4)), type: 1);
      final f = scan.finish();
      expect(found(f), [('unanswered_reads', '2/0/0')]);
      expect(f.single['count'], 2);
      expect(f.single['severity'], 'info');
    });

    test('answered reads, a single one, our own and one still within the timeout are no findings', () {
      final start = now.subtract(const Duration(hours: 1));
      for (var i = 0; i < 3; i++) {
        t(temp, [0], start.add(Duration(minutes: i)), small: true, type: 0);
        t(temp, encodeDpt9(21)!, start.add(Duration(minutes: i, seconds: 1)), type: 1);
      }
      t(hum, [0], start, small: true, type: 0);
      t(wind, [0], start, small: true, type: 0, own: true);
      t(wind, [0], start.add(const Duration(minutes: 1)), small: true, type: 0, own: true);
      t(presence, [0], start, small: true, type: 0);
      t(presence, [0], now.subtract(const Duration(seconds: 2)), small: true, type: 0);
      expect(scan.finish(), isEmpty);
    });
  });

  test('overdue addresses and DALI faults are passed in and named from the project', () {
    final last = now.subtract(const Duration(hours: 20));
    final f = scan.finish(
      overdue: [
        [temp, last.microsecondsSinceEpoch, 600],
      ],
      dali: [
        [pa('1.1.7'), 2, 0],
        [pa('1.1.9'), 0, 1],
      ],
    );
    expect(found(f), [('lamp_fault', '1.1.7'), ('gear_fault', '1.1.9'), ('overdue', '2/0/0')]);
    expect(f[0]['count'], 2);
    expect(f[0]['text'], 'daliHealthLampFault');
    expect(f[2]['interval_s'], 600);
    expect(DateTime.parse(f[2]['since']! as String), last.toUtc());
    expect(f[2]['name'], 'EG FL Ist-Temperatur');
  });

  test('DALI: luminaires count per gateway, groups and cleared faults do not', () {
    expect(
      daliFaultCounts({
        '4359:1': DaliFault.lamp,
        '4359:2': DaliFault.lamp | DaliFault.gear,
        '4359:3': 0,
        '4359:g1': DaliFault.lamp,
        '4361:5': DaliFault.converter,
        'test:7': 1,
      }),
      [
        [4359, 2, 1],
        [4361, 0, 1],
      ],
    );
  });

  test('what is kept per address and sender is bounded', () {
    scan = HealthScan(LintCatalog.fromJson(catalogJson()), now: now, maxKeys: 10);
    for (var source = 0; source < 1000; source++) {
      t(temp, [21], now, source: source);
      t(wind, [0x7F, 0xFF], now, source: source);
    }
    final f = scan.finish();
    expect(f.where((x) => x['kind'] == 'dpt_size'), hasLength(10));
    expect(f.where((x) => x['kind'] == 'dpt_value'), hasLength(10));
    expect(scan.truncated, isTrue);
  });

  test('history lines are read as the recorder writes them', () {
    final telegram = Telegram(
      time: now,
      source: pa('1.1.7'),
      destination: temp,
      type: TelegramType.write,
      data: Uint8List.fromList([21]),
      isSmall: false,
      repeated: true,
      raw: Uint8List.fromList([0x29, 0x00, 0xBC, 0xE0]),
    );
    scan.add(jsonEncode(telegram.toJson()));
    scan.add('{"t":1,"c":true,"n":3}'); // not a telegram
    scan.add('{"t":17,"s":1,"d":');
    expect(scan.telegrams, 1);
    expect(found(), [('dpt_size', '2/0/0')]);
  });

  test('the daily run is due after the quiet hour, after a day, or without a result', () {
    bool due(DateTime at, DateTime? last) => ServerHealthCheck.due(at, last, quietHour: 3);
    expect(due(DateTime(2026, 11, 11, 10), null), isTrue);
    // Ran yesterday evening: next at 3 o'clock.
    final evening = DateTime(2026, 11, 10, 20);
    expect(due(DateTime(2026, 11, 11, 2, 59), evening), isFalse);
    expect(due(DateTime(2026, 11, 11, 3), evening), isTrue);
    // Ran at 3: not again today, also not after a manual run later.
    expect(due(DateTime(2026, 11, 11, 23), DateTime(2026, 11, 11, 3)), isFalse);
    expect(due(DateTime(2026, 11, 12, 2), DateTime(2026, 11, 11, 3, 1)), isFalse);
    expect(due(DateTime(2026, 11, 12, 3), DateTime(2026, 11, 11, 3, 1)), isTrue);
    // Never older than a day, whatever the hour.
    expect(due(DateTime(2026, 11, 12, 2, 30), DateTime(2026, 11, 11, 2, 30)), isTrue);
  });

  test('the option counts only when it says yes', () {
    for (final on in [true, 'true', 'TRUE', '1', ' yes ', 'on']) {
      expect(ServerHealthCheck.parseEnabled(on), isTrue, reason: '$on');
    }
    for (final off in [false, null, '', 'false', '0', 'no', 1, 'health']) {
      expect(ServerHealthCheck.parseEnabled(off), isFalse, reason: '$off');
    }
  });

  group('service', () {
    late Directory data;
    late BusService bus;
    late _Link link;
    late DateTime clock;
    late HaIntegration ha;
    late HttpServer server;

    Future<void> startBus({bool readOnly = false}) async {
      bus = BusService(
        data,
        link: (_) => link = _Link(),
        describe: (_, _) async => null,
        installation: {'id': 'a', 'name': 'Zuhause'},
        readOnly: readOnly,
      );
      await bus.start();
      await bus.update({'enabled': true, 'mode': 'ha'});
      await until(() => bus.state == 'connected');
    }

    Future<void> startHa({
      bool enabled = true,
      Future<Map<String, Object?>> Function(HealthScanInput input)? scan,
    }) async {
      ha = HaIntegration(
        data,
        () => bus,
        version: '1.12.0',
        port: 8765,
        supervisorToken: 'supervisor',
        supervisor: Uri.parse('http://127.0.0.1:9/'),
        clock: () => clock,
        healthCheck: enabled,
        healthScan: scan,
      );
      await ha.start(tick: const Duration(hours: 1));
      // Routing as in server.dart: the token opens /api/ha/, nothing else gets in.
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        if (HaIntegration.handles(r.uri.path) && ha.authorized(r)) {
          await ha.serve(r);
        } else {
          r.response.statusCode = HttpStatus.forbidden;
          await r.response.close();
        }
      });
    }

    /// Today's history: a wrong length on the temperature and a stuck humidity.
    Future<void> writeHistory() async {
      final lines = StringBuffer();
      void line(int dest, List<int> data, DateTime time, {int? source}) => lines.writeln(
        jsonEncode({
          't': time.microsecondsSinceEpoch,
          's': source ?? pa('1.1.50'),
          'd': dest,
          'y': 2,
          'x': hexOf(data),
        }),
      );
      final midnight = DateTime(clock.year, clock.month, clock.day);
      line(temp, [21], midnight.add(const Duration(minutes: 1)), source: pa('1.1.7'));
      for (var i = 0; i < 14; i++) {
        line(hum, encodeDpt9(45)!, midnight.add(Duration(hours: i)));
      }
      final dir = Directory('${data.path}/history')..createSync(recursive: true);
      File('${dir.path}/${Recorder.dayName(clock)}.ndjson').writeAsStringSync('$lines');
    }

    setUp(() async {
      data = await Directory.systemTemp.createTemp('knx_health');
      clock = DateTime(2026, 11, 11, 14);
      await File('${data.path}/catalog.json').writeAsString(jsonEncode(catalogJson()));
    });

    tearDown(() async {
      ha.stop();
      await ha.health.idle;
      await server.close(force: true);
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
        return (res.statusCode, json && text.isNotEmpty ? jsonDecode(text) : text);
      } finally {
        client.close(force: true);
      }
    }

    test('off: the routes say "not enabled" and how to switch it on, nothing runs', () async {
      await startBus();
      await startHa(enabled: false);
      for (final (method, path) in [('GET', '/api/ha/health'), ('POST', '/api/ha/health/run')]) {
        final (code, body) = await call(method, path, token: ha.token);
        expect(code, HttpStatus.conflict, reason: path);
        expect(body, {'enabled': false, 'error': 'not_enabled', 'option': 'health_check', 'env': 'HEALTH_CHECK'});
      }
      expect(
        (await call('GET', '/api/ha/state', token: ha.token)).$2,
        containsPair('health_check', {'enabled': false}),
      );
      expect(await ha.health.tick(), isFalse);
      expect(ha.health.runs, 0);
      expect(() => ha.health.run(), throwsStateError);
      expect(bus.exporter.healthCheck, isNull, reason: 'server.dart sets the hook; without it the app shows nothing');
    });

    test('on: a run reads the history and the project, the result is kept and served', () async {
      await writeHistory();
      await startBus();
      await startHa();
      var (code, body) = await call('GET', '/api/ha/health', token: ha.token);
      expect(code, HttpStatus.ok);
      expect(body, containsPair('status', null));
      expect((body! as Map)['enabled'], isTrue);

      (code, body) = await call('POST', '/api/ha/health/run', token: ha.token, body: {});
      expect(code, HttpStatus.ok);
      final result = (body! as Map).cast<String, Object?>();
      expect(result['status'], 'faults');
      expect(result['format'], 1);
      expect(result['trigger'], 'manual');
      expect(result['read_test'], isFalse);
      expect(result['project'], isTrue);
      expect(result['telegrams'], 15);
      expect(result['truncated'], isFalse);
      expect(DateTime.parse(result['time']! as String), clock.toUtc());
      expect(result['counts'], {
        'total': 2,
        'errors': 1,
        'warnings': 1,
        'infos': 0,
        'by_kind': {'dpt_size': 1, 'stuck': 1},
      });
      final findings = (result['findings']! as List).cast<Map<String, Object?>>();
      expect(found(findings), [('dpt_size', '2/0/0'), ('stuck', '2/1/0')]);
      // No sentences from the server: only keys, numbers, addresses and names of the project.
      expect(findings.first.keys, containsAll(['kind', 'severity', 'area', 'text', 'address', 'name']));

      (code, body) = await call('GET', '/api/ha/health', token: ha.token);
      expect((body! as Map)['findings'], result['findings']);
      final (_, state) = await call('GET', '/api/ha/state', token: ha.token);
      expect((state! as Map)['health_check'], {
        'enabled': true,
        'status': 'faults',
        'time': result['time'],
        'counts': result['counts'],
      });
      // Diagnostics: no addresses and no names.
      final (_, diagnostics) = await call('GET', '/api/ha/diagnostics', token: ha.token);
      expect((diagnostics! as Map)['health_check'], {'enabled': true, 'status': 'faults', 'time': result['time']});
      expect(jsonEncode(diagnostics), isNot(contains('2/0/0')));

      // Kept across a restart of the server.
      ha.stop();
      await server.close(force: true);
      await startHa();
      expect(ha.health.summary()['status'], 'faults');
      expect(ha.health.runs, 0);
    });

    test('a quiet history is "ok", findings without an error are "hints"', () async {
      await startBus();
      await startHa();
      expect((await ha.health.run())['status'], 'ok');
      await writeHistory();
      await File('${data.path}/catalog.json').writeAsString(
        jsonEncode({
          'groups': [
            {
              'a': hum,
              'n': 'Feuchte',
              'd': [9, 7],
            },
          ],
        }),
      );
      final result = await ha.health.run();
      expect(result['status'], 'hints');
      expect((result['counts']! as Map)['warnings'], 1);
    });

    test('an address that stopped sending is "overdue", as the "stopped sending" check reports it', () async {
      // Seven days: the temperature every 5 minutes until a day ago, the humidity until now.
      final byDay = <String, StringBuffer>{};
      void line(int dest, DateTime time, double value) => (byDay[Recorder.dayName(time)] ??= StringBuffer()).writeln(
        jsonEncode({
          't': time.microsecondsSinceEpoch,
          's': pa('1.1.50'),
          'd': dest,
          'y': 2,
          'x': hexOf(encodeDpt9(value)!),
        }),
      );
      var n = 0;
      for (
        var at = clock.subtract(const Duration(days: 7));
        at.isBefore(clock);
        at = at.add(const Duration(minutes: 5))
      ) {
        if (at.isBefore(clock.subtract(const Duration(days: 1)))) line(temp, at, 21);
        line(hum, at, 40.0 + n++ % 7);
      }
      final dir = Directory('${data.path}/history')..createSync(recursive: true);
      for (final MapEntry(:key, :value) in byDay.entries) {
        File('${dir.path}/$key.ndjson').writeAsStringSync('$value');
      }
      await startBus();
      bus.since = clock.subtract(const Duration(days: 7));
      await startHa();
      final result = await ha.health.run();
      final findings = (result['findings']! as List).cast<Map<String, Object?>>();
      expect(found(findings), [('overdue', '2/0/0')]);
      expect(findings.single['interval_s'], 300);
      expect(findings.single['severity'], 'warning');
      expect(result['status'], 'hints');
      // The same list as the integration's repairs.
      expect((await call('GET', '/api/ha/silent', token: ha.token)).$2, hasLength(1));
      // Ignored there: no finding here either.
      await call('POST', '/api/ha/silent/ignore', token: ha.token, body: {'address': '2/0/0'});
      expect((await ha.health.run())['status'], 'ok');
    });

    test('only with the token (admin), as the other routes below /api/ha/', () async {
      await startBus();
      await startHa();
      for (final token in [null, 'wrong', '${ha.token}x']) {
        expect((await call('GET', '/api/ha/health', token: token)).$1, HttpStatus.forbidden);
        expect((await call('POST', '/api/ha/health/run', token: token, body: {})).$1, HttpStatus.forbidden);
      }
      expect(ha.health.runs, 0);
      // Not a JSON object: refused.
      expect((await call('POST', '/api/ha/health/run', token: ha.token, body: 'x' * 5000)).$1, HttpStatus.badRequest);
      expect(ha.health.runs, 0);
    });

    test('one run at a time: a second request waits for the first and gets its result', () async {
      await startBus();
      final gate = Completer<void>();
      var scans = 0;
      await startHa(
        scan: (input) async {
          scans++;
          await gate.future;
          return scanHealth(input);
        },
      );
      final first = call('POST', '/api/ha/health/run', token: ha.token, body: {});
      await until(() => scans == 1);
      final second = call('POST', '/api/ha/health/run', token: ha.token, body: {});
      final direct = ha.health.run();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect((await call('GET', '/api/ha/health', token: ha.token)).$2, containsPair('running', true));
      expect(await ha.health.tick(), isFalse, reason: 'no scheduled run on top of a running one');
      gate.complete();
      final results = [(await first).$2, (await second).$2, await direct];
      expect(scans, 1);
      expect(ha.health.runs, 1);
      expect(results.map((r) => (r! as Map)['time']).toSet(), hasLength(1));
      expect((await call('GET', '/api/ha/health', token: ha.token)).$2, containsPair('running', false));
    });

    for (final readOnly in [false, true]) {
      test('${readOnly ? 'read-only' : 'writable'}: a run sends nothing, and the read test is refused', () async {
        await writeHistory();
        await startBus(readOnly: readOnly);
        await startHa();
        final (code, _) = await call('POST', '/api/ha/health/run', token: ha.token, body: {});
        expect(code, HttpStatus.ok);
        // Asking for read requests: this server has no read test; in read-only mode it says why.
        final (refused, body) = await call('POST', '/api/ha/health/run', token: ha.token, body: {'read': true});
        expect(refused, HttpStatus.unprocessableEntity);
        expect(body, {'error': readOnly ? 'read_only' : 'read_test_not_supported'});
        clock = clock.add(const Duration(days: 1));
        expect(await ha.health.tick(), isTrue);
        await ha.health.idle;
        expect(ha.health.runs, 2);
        expect(link.sent, isEmpty, reason: 'nothing went to the bus connection');
      });
    }

    test('the daily run: at once without a result, then at 3 o\'clock, with the injected clock', () async {
      await writeHistory();
      await startBus();
      await startHa();
      expect(await ha.health.tick(), isTrue, reason: 'no result yet');
      await ha.health.idle;
      expect(ha.health.runs, 1);
      expect(ha.health.last()['trigger'], 'schedule');
      expect(ha.health.last()['status'], 'faults');
      // The rest of the day and the night until 3: nothing.
      for (final at in [DateTime(2026, 11, 11, 14, 1), DateTime(2026, 11, 11, 23, 59), DateTime(2026, 11, 12, 2, 59)]) {
        clock = at;
        expect(await ha.health.tick(), isFalse, reason: '$at');
      }
      clock = DateTime(2026, 11, 12, 3);
      expect(await ha.health.tick(), isTrue);
      await ha.health.idle;
      expect(ha.health.runs, 2);
      expect(DateTime.parse(ha.health.last()['time']! as String), clock.toUtc());
      // Yesterday's telegrams still count: the check reads today and yesterday.
      expect(ha.health.last()['telegrams'], 15);
      clock = DateTime(2026, 11, 12, 3, 1);
      expect(await ha.health.tick(), isFalse);
      // A manual run in the evening does not skip the night's run.
      clock = DateTime(2026, 11, 12, 20);
      await ha.health.run();
      clock = DateTime(2026, 11, 13, 3, 0, 30);
      expect(await ha.health.tick(), isTrue);
      await ha.health.idle;
      expect(ha.health.runs, 4);
    });

    test('the result is bounded: at most 200 findings, the counts cover all', () async {
      final lines = StringBuffer();
      for (var source = 1; source <= 300; source++) {
        lines.writeln(
          jsonEncode({'t': clock.microsecondsSinceEpoch - source, 's': source, 'd': temp, 'y': 2, 'x': '15'}),
        );
      }
      final dir = Directory('${data.path}/history')..createSync(recursive: true);
      File('${dir.path}/${Recorder.dayName(clock)}.ndjson').writeAsStringSync('$lines');
      await startBus();
      await startHa();
      final result = await ha.health.run();
      expect(result['findings'], hasLength(ServerHealthCheck.maxFindings));
      expect((result['counts']! as Map)['total'], 300);
      expect(result['truncated'], isTrue);
    });

    test('the bound on lines leaves out the oldest day', () async {
      final dir = Directory('${data.path}/history')..createSync(recursive: true);
      String line(DateTime time) =>
          '${jsonEncode({'t': time.microsecondsSinceEpoch, 's': pa('1.1.7'), 'd': temp, 'y': 2, 'x': '15'})}\n';
      final yesterday = clock.subtract(const Duration(days: 1));
      File('${dir.path}/${Recorder.dayName(clock)}.ndjson').writeAsStringSync(line(clock) * 3);
      File('${dir.path}/${Recorder.dayName(yesterday)}.ndjson').writeAsStringSync(line(yesterday) * 5);
      await startBus();
      await startHa();
      final scanned = await scanHealth(
        HealthScanInput(
          dataPath: data.path,
          days: [Recorder.dayName(clock), Recorder.dayName(yesterday)],
          nowMicros: clock.microsecondsSinceEpoch,
          maxLines: 4,
        ),
      );
      expect(scanned['telegrams'], 4);
      expect(scanned['truncated'], isTrue);
      final finding = (scanned['findings']! as List).single as Map;
      expect(finding['count'], 4);
      expect(DateTime.parse(finding['since'] as String), clock.toUtc(), reason: 'today was read first');
    });
  });
}

Future<void> until(bool Function() condition, {Duration timeout = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('Bedingung nicht erfüllt');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
