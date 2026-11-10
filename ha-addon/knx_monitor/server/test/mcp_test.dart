import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

/// Group address, device and catalog helpers for the cases below (own data, no real installation).
int ga(String s) => parseGroupAddress(s)!;
int pa(String s) => parseIndividual(s)!;

Map<String, Object?> link(String device, String flags, {bool sends = false, String? ref, int? object}) => {
  'd': pa(device),
  'o': ?object,
  'f': flags,
  if (sends) 's': true,
  'r': ?ref,
};

Map<String, Object?> catalogJson() => {
  'v': 1,
  'project': 'Testhaus',
  'groups': [
    {
      'a': ga('1/1/1'),
      'n': 'Küche Licht',
      'p': 'Licht › Schalten',
      'd': [1, 1],
      'l': [link('1.1.50', 'CT', sends: true), link('1.1.5', 'CW', ref: 'M-0083_A-1_O-0_R-1')],
    },
    // Status without R: the actuator sends it, nobody answers reads.
    {
      'a': ga('1/4/1'),
      'n': 'Küche Licht Status',
      'p': 'Licht › Rückmeldung',
      'd': [1, 1],
      'l': [link('1.1.5', 'CT', sends: true, ref: 'M-0083_A-1_O-1_R-2'), link('1.1.50', 'CWTU')],
    },
    // Two senders.
    {
      'a': ga('1/1/2'),
      'n': 'Flur Licht',
      'l': [link('1.1.50', 'CT', sends: true), link('1.1.51', 'CT', sends: true), link('1.1.5', 'CW')],
    },
    // Object without C.
    {
      'a': ga('1/1/5'),
      'n': 'Keller',
      'd': [1, 1],
      'l': [link('1.1.5', 'W', ref: 'M-0083_A-1_O-7_R-7')],
    },
    // Written by Home Assistant only.
    {
      'a': ga('1/1/6'),
      'n': 'Garten',
      'd': [1, 1],
      'l': [link('1.1.5', 'CW')],
    },
    {
      'a': ga('2/0/0'),
      'n': 'Temperatur Küche',
      'd': [9, 1],
      'l': [link('1.1.60', 'CRT', sends: true)],
    },
  ],
  'devices': [
    {
      'a': pa('1.1.5'),
      'n': 'Aktor',
      'pd': ['groups'],
    },
    {'a': pa('1.1.50'), 'n': 'Taster'},
    {'a': pa('1.1.51'), 'n': 'Taster 2'},
    {'a': pa('1.1.60'), 'n': 'Fühler'},
    {'a': pa('1.1.120'), 'n': 'Binäreingang', 'np': true},
    {
      'a': pa('1.2.0'),
      'n': 'Koppler',
      'pd': ['groups'],
    },
    {'a': pa('1.1.36'), 'n': 'X1 · Tunnel 1', 'tu': pa('1.1.30')},
  ],
  'xs': [ga('1/1/6')],
};

void main() {
  late Directory data;
  late McpTools tools;
  final now = DateTime(2026, 11, 9, 12);

  Map<String, Object?> line(DateTime t, String src, String dst, {int y = 2, String x = '01', bool small = true}) => {
    't': t.microsecondsSinceEpoch,
    's': pa(src),
    'd': ga(dst),
    'y': y,
    'x': x,
    if (small) 'm': true,
  };

  setUp(() async {
    data = await Directory.systemTemp.createTemp('busclear_mcp');
    await File('${data.path}/catalog.json').writeAsString(jsonEncode(catalogJson()));
    await File('${data.path}/dpt_overrides.json').writeAsString(
      jsonEncode({
        '${ga('1/1/2')}': [1, 1],
      }),
    );
    await File('${data.path}/name_overrides.json').writeAsString(jsonEncode({'${ga('1/1/5')}': 'Keller Licht'}));
    await Directory('${data.path}/history').create();
    final today = [
      line(now.subtract(const Duration(hours: 1)), '1.1.50', '1/1/1'),
      line(now.subtract(const Duration(minutes: 59)), '1.1.5', '1/4/1'),
      line(now.subtract(const Duration(minutes: 30)), '1.1.60', '2/0/0', x: '0c33', small: false),
      line(now.subtract(const Duration(minutes: 20)), '1.1.60', '2/0/0', x: '0c8a', small: false),
      line(now.subtract(const Duration(minutes: 10)), '1.1.30', '2/0/0', y: 0, x: '00'),
    ];
    final yesterday = [
      line(now.subtract(const Duration(days: 1, hours: 1)), '1.1.60', '2/0/0', x: '0c00', small: false),
    ];
    await File('${data.path}/history/2026-11-09.ndjson').writeAsString(today.map(jsonEncode).join('\n'));
    await File('${data.path}/history/2026-11-08.ndjson').writeAsString(yesterday.map(jsonEncode).join('\n'));
    final alarms = AlarmWatch(data, notify: ({required id, required title, required message}) async {});
    tools = McpTools(
      McpSource(
        data: data,
        recorder: Recorder(data, clock: () => now),
        alarms: alarms,
        status: () => {'state': 'connected'},
      ),
      now: () => now,
    );
  });

  tearDown(() => data.delete(recursive: true));

  test('liest dieselben Dateien, die die App schreibt', () {
    final app = File('../../../lib/catalog_store.dart').readAsStringSync();
    expect(app, contains("_path = '$appCatalogFile'"));
    expect(app, contains("_overridesPath = '$appDptOverridesFile'"));
    expect(app, contains("_namesPath = '$appNameOverridesFile'"));
  });

  test('Übersicht', () async {
    final o = await tools.overview();
    expect(o['project'], 'Testhaus');
    expect(o['group_addresses'], 6);
    expect(o['devices'], 6);
    expect((o['history']! as Map)['days'], 2);
    expect(o['connection'], {'state': 'connected'});
  });

  group('search_telegrams', () {
    test('neueste zuerst, mit Namen, Typ und Wert', () async {
      final r = await tools.searchTelegrams({'group_address': '2/0/0', 'type': 'write'});
      final list = (r['telegrams']! as List).cast<Map<String, Object?>>();
      expect(list, hasLength(2));
      // 0C8A = 23.24 °C, the newer of the two writes.
      expect(list.first['value'], closeTo(23.24, 0.01));
      expect(list.first['name'], 'Temperatur Küche');
      expect(list.first['source_name'], 'Fühler');
      expect(list.first['dpt'], '9.001');
    });

    test('Zeitraum über mehrere Tage, Grenze, Werte filtern', () async {
      final all = await tools.searchTelegrams({'group_address': '2/0/0', 'from': '2026-11-08T00:00:00'});
      expect(all['count'], 4);
      final limited = await tools.searchTelegrams({'from': '2026-11-08T00:00:00', 'limit': 2});
      expect(limited['count'], 2);
      expect(limited['more'], isTrue);
      final warm = await tools.searchTelegrams({'group_address': '2/0/0', 'min': 23, 'from': '2026-11-08T00:00:00'});
      expect(warm['count'], 1);
      final reads = await tools.searchTelegrams({'type': 'read'});
      expect(((reads['telegrams']! as List).single as Map)['source'], '1.1.30');
      expect(((reads['telegrams']! as List).single as Map).containsKey('value'), isFalse);
    });

    test('ungültige Angaben werden erklärt', () async {
      expect(() => tools.searchTelegrams({'group_address': 'x'}), throwsA(isA<McpToolError>()));
      expect(() => tools.searchTelegrams({'from': 'gestern'}), throwsA(isA<McpToolError>()));
      expect(() => tools.searchTelegrams({'from': '2026-01-01T00:00:00'}), throwsA(isA<McpToolError>()));
    });
  });

  test('device_activity', () async {
    final r = await tools.deviceActivity({'device': '1.1.60', 'days': 2});
    expect(r['name'], 'Fühler');
    expect(r['telegrams_per_day'], {'2026-11-08': 1, '2026-11-09': 2});
    expect(r['total'], 3);
    expect((r['sent_to']! as List).single, containsPair('group_address', '2/0/0'));
    expect(r['last_heard'], now.subtract(const Duration(minutes: 20)).toIso8601String());
    final silent = await tools.deviceActivity({'device': '1.1.120'});
    expect(silent['total'], 0);
    expect(silent['last_heard'], isNull);
  });

  test('project_check: dieselben Regeln wie die App', () async {
    final r = await tools.projectCheck({});
    final checks = r['checks']! as Map<String, Object?>;
    List<Object?> items(String kind) => ((checks[kind] as Map?)?['items'] as List?) ?? const [];
    String first(String kind, String key) => (items(kind).first as Map)[key] as String;
    expect(first('read_without_read_flag', 'group_address'), '1/4/1');
    expect(first('multiple_senders', 'group_address'), '1/1/2');
    expect(first('object_without_communication', 'group_address'), '1/1/5');
    // 1/1/6 is written by Home Assistant: not "without sender".
    expect(items('without_sender').map((i) => (i as Map)['group_address']), isNot(contains('1/1/6')));
    expect(items('device_never_programmed').map((i) => (i as Map)['device']), ['1.1.120']);
    // The coupler counts for "download pending" but not for "without links".
    expect(items('device_download_pending').map((i) => (i as Map)['device']), ['1.1.5', '1.2.0']);
    expect(items('device_without_links').map((i) => (i as Map)['device']), ['1.1.120']);
    expect(items('no_dpt').map((i) => (i as Map)['group_address']), ['1/1/2']);
  });

  test('project_vs_bus: unerwartete Sender, Befehle ohne Rückmeldung, Belege', () async {
    DateTime at(int minutes, [int seconds = 0]) => now.subtract(Duration(minutes: minutes, seconds: -seconds));
    final more = [
      // Three commands from the push button, the actuator answers only the first.
      line(at(50), '1.1.50', '1/1/1'),
      line(at(50, 1), '1.1.5', '1/4/1'),
      line(at(40), '1.1.50', '1/1/1'),
      line(at(30), '1.1.50', '1/1/1'),
      // The actuator sends on its command address: not a sender according to the project.
      line(at(25), '1.1.5', '1/1/1'),
      // Both project senders of 1/1/2 are heard.
      line(at(20), '1.1.50', '1/1/2'),
      line(at(19), '1.1.51', '1/1/2'),
      // Two reads of the status without R, unanswered.
      line(at(15), '1.1.30', '1/4/1', y: 0, x: '00'),
      line(at(14), '1.1.30', '1/4/1', y: 0, x: '00'),
    ];
    final file = File('${data.path}/history/2026-11-09.ndjson');
    await file.writeAsString('\n${more.map(jsonEncode).join('\n')}', mode: FileMode.append);
    final r = await tools.projectVsBus({'days': 1});
    List<Map<String, Object?>> items(String k) => ((r[k]! as Map)['items'] as List).cast<Map<String, Object?>>();
    expect(items('unexpected_senders').single, containsPair('device', '1.1.5'));
    expect(items('unexpected_senders').single, containsPair('group_address', '1/1/1'));
    final fb = items('commands_without_feedback').single;
    expect(fb['command'], '1/1/1');
    expect(fb['status'], '1/4/1');
    // Including the command of the basic setup an hour ago, answered only a minute later.
    expect(fb['commands'], 4);
    expect(fb['answered'], 1);
    final senders = items('multiple_senders').single;
    expect(senders['confirmed'], isTrue);
    expect(senders['heard'], {'1.1.50': 1, '1.1.51': 1});
    expect(items('read_without_answer').single, containsPair('reads', 2));
    expect(items('read_without_answer').single, containsPair('answered', 0));
  });

  test('project_vs_bus: Datentypen, lange Zustände, nächtliche Auslösungen', () async {
    final catalog = catalogJson();
    catalog['groups'] = [
      ...catalog['groups']! as List,
      {
        'a': ga('4/1/13'),
        'n': 'EG KÜ F01 Gekippt',
        'd': [1, 19],
      },
      {
        'a': ga('8/3/13'),
        'n': 'OG FL M01 Anwesenheit',
        'd': [1, 18],
      },
      {'a': ga('2/0/9'), 'n': 'Bad Ist-Temperatur'},
      {'a': ga('1/0/7'), 'n': 'OG FL Licht An/Aus'},
    ];
    await File('${data.path}/catalog.json').writeAsString(jsonEncode(catalog));
    final byDay = <String, List<Map<String, Object?>>>{};
    void add(Map<String, Object?> l) {
      final day = Recorder.dayName(DateTime.fromMicrosecondsSinceEpoch(l['t']! as int));
      (byDay[day] ??= []).add(l);
    }

    // Contact: "gekippt" = 1 every 30 minutes for three days.
    for (var t = now.subtract(const Duration(days: 3)); t.isBefore(now); t = t.add(const Duration(minutes: 30))) {
      add(line(t, '1.1.127', '4/1/13'));
    }
    // Presence at 1, 2 and 3 o'clock on three nights.
    for (final day in [7, 8, 9]) {
      for (final h in [1, 2, 3]) {
        add(line(DateTime(2026, 11, day, h), '1.1.100', '8/3/13'));
      }
    }
    // Without a type: two bytes, and 1 bit on/off.
    add(line(now.subtract(const Duration(hours: 2)), '1.1.70', '2/0/9', x: '0c33', small: false));
    add(line(now.subtract(const Duration(hours: 3)), '1.1.70', '2/0/9', x: '0c35', small: false));
    add(line(now.subtract(const Duration(hours: 2)), '1.1.50', '1/0/7'));
    add(line(now.subtract(const Duration(hours: 1)), '1.1.50', '1/0/7', x: '00'));
    for (final MapEntry(:key, :value) in byDay.entries) {
      await File('${data.path}/history/$key.ndjson')
          .writeAsString('\n${value.map(jsonEncode).join('\n')}', mode: FileMode.append);
    }
    final r = await tools.projectVsBus({'days': 4});
    List<Map<String, Object?>> items(String k) => ((r[k]! as Map)['items'] as List).cast<Map<String, Object?>>();
    final dpts = {for (final d in items('dpt_suggestions')) d['group_address']: (d['dpt'], d['certainty'])};
    expect(dpts['2/0/9'], ('DPST-9-1', 'high'));
    expect(dpts['1/0/7'], ('DPST-1-1', 'high'));
    final state = items('long_states').single;
    expect(state['group_address'], '4/1/13');
    expect(state['since_period_start'], isTrue);
    expect(state['telegrams'], greaterThan(100));
    final night = items('night_activity').single;
    expect(night['group_address'], '8/3/13');
    expect(night['nights'], 3);
    expect(night['triggers_per_night'], 3.0);
  });

  test('editor_handover: Korrekturen eindeutig, Rest als Notiz', () async {
    final r = await tools.editorHandover();
    final ops = (r['operations']! as List).map(jsonEncode).toList();
    expect(
      ops,
      contains(
        jsonEncode({
          'op': 'set_group_address_dpt',
          'params': {'group_address': '1/1/2', 'dpt': 'DPST-1-1'},
        }),
      ),
    );
    expect(
      ops,
      contains(
        jsonEncode({
          'op': 'rename_group_address',
          'params': {'group_address': '1/1/5', 'name': 'Keller Licht'},
        }),
      ),
    );
    expect(
      ops,
      contains(
        jsonEncode({
          'op': 'set_com_object_flag',
          'params': {
            'device_address': '1.1.5',
            'com_object_ref_id': 'M-0083_A-1_O-1_R-2',
            'flag': 'read',
            'value': true,
          },
        }),
      ),
    );
    expect(ops.where((o) => o.contains('communication')), hasLength(1));
    final notes = (r['notes']! as List).cast<Map<String, Object?>>();
    expect(notes.firstWhere((n) => n['device_address'] == '1.2.0')['lines'], ['[Busclear] Download pending: groups.']);
    expect(notes.expand((n) => n['lines']! as List).every((l) => (l as String).startsWith('[Busclear] ')), isTrue);
  });

  test('findings: Bericht über die letzten Tage', () async {
    final r = await tools.findings({'days': 2});
    expect(r['findings'], isA<List<Object?>>());
    expect((r['traffic']! as Map)['total'], greaterThan(0));
  });

  test('ohne Projekt', () async {
    await File('${data.path}/catalog.json').delete();
    expect((await tools.projectCheck({}))['message'], contains('No project'));
    expect((await tools.editorHandover())['message'], contains('No project'));
  });

  group('McpService', () {
    late HttpServer server;
    late McpService mcp;
    late Uri endpoint;

    setUp(() async {
      mcp = McpService(data, () => tools.source, version: 'test');
      await mcp.load();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      endpoint = Uri.parse('http://127.0.0.1:${server.port}${McpService.path}');
      server.listen((request) async {
        if (mcp.authorized(request)) return mcp.serve(request);
        // Stands in for the normal login: the test request with "admin" is the admin.
        if (await mcp.serveSettings(request, admin: request.headers.value('x-admin') == '1')) return;
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    Future<(int, Object?)> post(Object body, {String? token, Uri? uri}) async {
      final client = HttpClient();
      try {
        final req = await client.postUrl(uri ?? endpoint);
        req.headers.contentType = ContentType.json;
        if (token != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        req.write(jsonEncode(body));
        final res = await req.close();
        final text = await utf8.decodeStream(res);
        return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
      } finally {
        client.close();
      }
    }

    Future<Map<String, Object?>> settings(Map<String, Object?>? change, {bool admin = true}) async {
      final client = HttpClient();
      try {
        final uri = endpoint.replace(path: McpService.settingsPath);
        final req = change == null ? await client.getUrl(uri) : await client.putUrl(uri);
        if (admin) req.headers.set('x-admin', '1');
        if (change != null) req.write(jsonEncode(change));
        final res = await req.close();
        final text = await utf8.decodeStream(res);
        if (res.statusCode != 200) return {'status': res.statusCode};
        return jsonDecode(text) as Map<String, Object?>;
      } finally {
        client.close();
      }
    }

    test('aus, bis ein Admin es einschaltet; nur mit Token', () async {
      expect((await post({'jsonrpc': '2.0', 'id': 1, 'method': 'ping'})).$1, 403);
      expect(await settings(null), {'enabled': false, 'token': null, 'path': McpService.path});
      expect((await settings({'enabled': true}, admin: false))['status'], 403);
      final on = await settings({'enabled': true});
      final token = on['token']! as String;
      expect(token.length, greaterThan(30));
      expect((await post({'jsonrpc': '2.0', 'id': 1, 'method': 'ping'})).$1, 403);
      expect((await post({'jsonrpc': '2.0', 'id': 1, 'method': 'ping'}, token: 'falsch')).$1, 403);
      expect((await post({'jsonrpc': '2.0', 'id': 1, 'method': 'ping'}, token: token)).$1, 200);
      // Survives a restart.
      final again = McpService(data, () => tools.source);
      await again.load();
      expect(again.enabled, isTrue);
      // New token: the old one stops working.
      final renewed = (await settings({'renew': true}))['token'];
      expect(renewed, isNot(token));
      expect((await post({'jsonrpc': '2.0', 'id': 1, 'method': 'ping'}, token: token)).$1, 403);
      await settings({'enabled': false});
      expect((await post({'jsonrpc': '2.0', 'id': 1, 'method': 'ping'}, token: renewed! as String)).$1, 403);
    });

    test('Härtung: Größe, Batch, neuer Token beim Einschalten, nur HTTPS wo möglich', () async {
      final token = (await settings({'enabled': true}))['token']! as String;
      final big = {'jsonrpc': '2.0', 'id': 1, 'method': 'ping', 'pad': 'x' * (McpService.maxBody + 1)};
      expect((await post(big, token: token)).$1, 413);
      final batch = [
        for (var i = 0; i < McpService.maxBatch + 1; i++) {'jsonrpc': '2.0', 'id': i, 'method': 'ping'},
      ];
      expect(((await post(batch, token: token)).$2! as Map)['error'], containsPair('message', 'batch too large'));
      // Off and on again: the old token is dead.
      await settings({'enabled': false});
      final fresh = (await settings({'enabled': true}))['token'];
      expect(fresh, isNot(token));
      expect((await post({'jsonrpc': '2.0', 'id': 1, 'method': 'ping'}, token: token)).$1, 403);
      // Server with HTTPS: a plain request with the right token is refused.
      final strict = McpService(data, () => tools.source, plainHttp: (_) => true);
      await strict.load();
      expect(strict.enabled, isTrue);
      final client = HttpClient();
      final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      probe.listen((r) async {
        r.response.statusCode = strict.authorized(r) ? 200 : 403;
        await r.response.close();
      });
      final req = await client.postUrl(Uri.parse('http://127.0.0.1:${probe.port}${McpService.path}'));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $fresh');
      expect((await req.close()).statusCode, 403);
      client.close();
      await probe.close(force: true);
    });

    test('initialize, tools/list, tools/call, Fehler', () async {
      final token = (await settings({'enabled': true}))['token']! as String;
      final (status, init) = await post({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {'protocolVersion': '2025-06-18', 'capabilities': <String, Object?>{}},
      }, token: token);
      expect(status, 200);
      expect(((init! as Map)['result'] as Map)['serverInfo'], containsPair('name', 'busclear'));
      expect((await post({'jsonrpc': '2.0', 'method': 'notifications/initialized'}, token: token)).$1, 202);
      final list = (await post({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'}, token: token)).$2! as Map;
      final names = [for (final t in (list['result'] as Map)['tools'] as List) (t as Map)['name']];
      expect(names, [
        'overview',
        'search_telegrams',
        'device_activity',
        'findings',
        'project_check',
        'project_vs_bus',
        'editor_handover',
      ]);
      final call =
          (await post({
                'jsonrpc': '2.0',
                'id': 3,
                'method': 'tools/call',
                'params': {'name': 'overview', 'arguments': <String, Object?>{}},
              }, token: token)).$2!
              as Map;
      expect(((call['result'] as Map)['structuredContent'] as Map)['project'], 'Testhaus');
      final bad =
          (await post({
                'jsonrpc': '2.0',
                'id': 4,
                'method': 'tools/call',
                'params': {
                  'name': 'search_telegrams',
                  'arguments': {'group_address': 'x'},
                },
              }, token: token)).$2!
              as Map;
      expect((bad['result'] as Map)['isError'], isTrue);
      final unknown = (await post({'jsonrpc': '2.0', 'id': 5, 'method': 'resources/list'}, token: token)).$2! as Map;
      expect((unknown['error'] as Map)['code'], -32601);
    });
  });
}
