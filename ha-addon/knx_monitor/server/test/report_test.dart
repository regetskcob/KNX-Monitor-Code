import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:knx_monitor_server/files.dart';
import 'package:test/test.dart';

/// Projekt für die Berichte: Rauchmelder, Batterie, Temperatur.
const _catalog = {
  'style': 'threeLevel',
  'groups': [
    {
      'a': 0x0801,
      'n': 'Rauchmelder Flur',
      'd': [1, 5],
    },
    {
      'a': 0x0802,
      'n': 'Batterie leer Fenster',
      'd': [1, 2],
    },
    {
      'a': 0x0803,
      'n': 'Temperatur Küche',
      'd': [9, 1],
    },
  ],
};

void main() {
  late Directory data;
  late BusService bus;
  late List<String> logged;
  var now = DateTime(2026, 11, 1, 3);
  final sensor = 0x1105;
  final other = 0x1106;

  ReportService service({
    Future<bool> Function({required String id, required String title, required String message})? ha,
  }) => ReportService(
    data,
    recorder: bus.recorder,
    alarms: bus.alarms,
    language: () => 'de',
    now: () => now,
    homeAssistant: ha,
    log: logged.add,
  );

  setUp(() async {
    data = await Directory.systemTemp.createTemp('knx_report');
    bus = BusService(data);
    logged = [];
    now = DateTime(2026, 11, 1, 3);
    await File('${data.path}/catalog.json').writeAsString(jsonEncode(_catalog));
    await Directory('${data.path}/history').create();
    await Directory('${data.path}/status').create();
  });
  tearDown(() => data.delete(recursive: true));

  /// Schreibt Verlauf und Lebenszeichen eines ganzen, verbundenen Tags.
  Future<void> day(DateTime d, {Map<int, int> senders = const {}, int ga = 0x0803, String value = '0c1a'}) async {
    final name = Recorder.dayName(d);
    final buffer = StringBuffer();
    senders.forEach((source, n) {
      for (var i = 0; i < n; i++) {
        final t = d.add(Duration(minutes: i * 1400 ~/ n + 1));
        buffer.writeln(jsonEncode({'t': t.microsecondsSinceEpoch, 's': source, 'd': ga, 'y': 2, 'x': value}));
      }
    });
    await File('${data.path}/history/$name.ndjson').writeAsString(buffer.toString());
    final beats = StringBuffer();
    for (var m = 0; m < 24 * 60; m += 1) {
      final t = d.add(Duration(minutes: m));
      beats.writeln(jsonEncode({'t': t.millisecondsSinceEpoch, 'c': true, 'n': 0}));
    }
    final month = name.substring(0, 7);
    await File('${data.path}/status/availability-$month.ndjson').writeAsString(beats.toString(), mode: FileMode.append);
  }

  group('Zeitraum', () {
    test('Monat und Quartal, auch über den Jahreswechsel', () {
      final jan = DateTime(2027, 1, 15);
      expect(ReportPeriod.lastComplete(jan, ReportSettings.monthly).id, '2026-12');
      expect(ReportPeriod.lastComplete(jan, ReportSettings.quarterly).id, '2026-Q4');
      final q = ReportPeriod.containing(DateTime(2026, 5, 2), ReportSettings.quarterly);
      expect(q.id, '2026-Q2');
      expect(q.from, DateTime(2026, 4));
      expect(q.to, DateTime(2026, 7));
    });
  });

  group('Tagessumme', () {
    test('zählt Telegramme, Wiederholungen und eigene nicht als Absender', () async {
      final d = DateTime(2026, 10, 5);
      final name = Recorder.dayName(d);
      final lines = [
        {'t': d.add(const Duration(hours: 8)).microsecondsSinceEpoch, 's': sensor, 'd': 0x0803, 'y': 2, 'x': '0c1a'},
        {
          't': d.add(const Duration(hours: 8, minutes: 1)).microsecondsSinceEpoch,
          's': sensor,
          'd': 0x0803,
          'y': 2,
          'x': '0c1b',
          'rp': true,
        },
        {
          't': d.add(const Duration(hours: 9)).microsecondsSinceEpoch,
          's': 0xFF01,
          'd': 0x0803,
          'y': 0,
          'x': '00',
          'm': true,
          'o': true,
        },
      ];
      await File('${data.path}/history/$name.ndjson').writeAsString(lines.map((l) => '${jsonEncode(l)}\n').join());
      final r = (await computeDayRollup(data.path, name))!;
      expect(r['n'], 3);
      expect((r['h']! as List)[8], 2);
      expect((r['s']! as Map)['$sensor'], [2, 1, (lines[1]['t']! as int) ~/ 1000]);
      expect((r['s']! as Map).containsKey('${0xFF01}'), isFalse);
      // Leseanfrage zählt nicht als Wert, zwei Werte = ein Wechsel.
      final g = (r['g']! as Map)['${0x0803}'] as List;
      expect(g[0], 2);
      expect(g[3], 1);
      expect(r['busy'], greaterThan(0));
    });

    test('kennt Lücken in den Lebenszeichen', () async {
      final d = DateTime(2026, 10, 6);
      final beats = [
        for (final m in [600, 601, 602, 900, 901])
          {'t': d.add(Duration(minutes: m)).millisecondsSinceEpoch, 'c': m < 900, 'n': 0},
      ];
      await File('${data.path}/status/availability-2026-10.ndjson')
          .writeAsString(beats.map((l) => '${jsonEncode(l)}\n').join());
      final r = (await computeDayRollup(data.path, Recorder.dayName(d)))!;
      final kinds = [for (final o in (r['out']! as List).cast<Map<Object?, Object?>>()) o['kind']];
      expect(kinds, ['offline', 'offline', 'disconnected', 'offline']);
      expect(r['conn'], 3);
    });

    test('ohne Verlauf und Lebenszeichen keine Summe', () async {
      expect(await computeDayRollup(data.path, '2026-10-07'), isNull);
    });
  });

  group('Bericht', () {
    /// Ein Monat im Takt: [sensor] nur bis [lastDay], [other] durchgehend.
    Future<ReportService> month({int lastDay = 31}) async {
      for (var i = 1; i <= 31; i++) {
        await day(DateTime(2026, 10, i), senders: {if (i <= lastDay) sensor: 30, other: 30});
      }
      final s = service();
      await s.load();
      await s.update({'enabled': true});
      s.settings.since = DateTime(2026, 10, 1);
      await s.tick();
      return s;
    }

    test('ein am 10. abgestecktes Gerät steht mit „seit“ im nächsten Bericht', () async {
      final s = await month(lastDay: 9);
      final report = (await s.read('2026-10'))!;
      final findings = (report['findings']! as List).cast<Map<String, Object?>>();
      final silent = findings.firstWhere((f) => f['key'] == 'deviceSilent:$sensor');
      expect(silent['label'], '1.1.5');
      expect(DateTime.fromMillisecondsSinceEpoch(silent['since']! as int).day, 9);
      expect(findings.where((f) => f['key'] == 'deviceSilent:$other'), isEmpty);
      expect(report['coverage'], {'days': 31, 'total': 31});
      expect((report['availability']! as Map)['ratio'], closeTo(1, 0.002));
      expect((report['traffic']! as Map)['total'], 9 * 30 + 31 * 30);
    });

    test('Rauchmelder und Batterie: letzter Stand aus dem Projekt, Melder dringend', () async {
      for (var i = 1; i <= 3; i++) {
        await day(DateTime(2026, 10, i), senders: {sensor: 2}, ga: 0x0801, value: i == 3 ? '01' : '00');
      }
      final s = service();
      await s.load();
      await s.update({'enabled': true});
      s.settings.since = DateTime(2026, 10, 1);
      await s.tick();
      final report = (await s.read('2026-10'))!;
      final safety = (report['safety']! as List).cast<Map<String, Object?>>();
      expect(safety.firstWhere((x) => x['address'] == 0x0801)['state'], 'active');
      expect(safety.firstWhere((x) => x['address'] == 0x0802)['state'], 'unknown');
      final finding = (report['findings']! as List).cast<Map<Object?, Object?>>().firstWhere(
        (f) => f['kind'] == 'alarmActive',
      );
      expect(finding['level'], 'critical');
      expect(finding['name'], 'Rauchmelder Flur');
    });

    test('Vergleich: neu, unverändert, behoben', () async {
      Map<String, Object?> f(String key) => {'key': key, 'kind': 'x', 'level': 'warning'};
      for (var i = 1; i <= 31; i++) {
        await day(DateTime(2026, 10, i), senders: {if (i <= 9) sensor: 30, other: 30});
      }
      final s = service();
      await s.load();
      await s.update({'enabled': true});
      s.settings.since = DateTime(2026, 10, 1);
      await Directory('${data.path}/reports').create();
      // Vorbericht von September mit einem Befund, der weg ist, und dem,
      // der bleibt.
      await File('${data.path}/reports/2026-09.json').writeAsString(
        jsonEncode({
          'id': '2026-09',
          'period': 'monthly',
          'from': DateTime(2026, 9).millisecondsSinceEpoch,
          'to': DateTime(2026, 10).millisecondsSinceEpoch,
          'generated': 0,
          'findings': [f('deviceSilent:$sensor'), f('repeats:7')],
          'resolved': const <Object?>[],
        }),
      );
      await s.tick();
      final report = (await s.read('2026-10'))!;
      final findings = (report['findings']! as List).cast<Map<Object?, Object?>>();
      expect(findings.firstWhere((x) => x['key'] == 'deviceSilent:$sensor')['status'], 'unchanged');
      expect((report['resolved']! as List).cast<Map<Object?, Object?>>().single['key'], 'repeats:7');
    });

    test('Tage ohne Lebenszeichen zählen als Ausfall, die Zeit davor nicht', () async {
      await day(DateTime(2026, 10, 10), senders: {other: 5});
      await day(DateTime(2026, 10, 13), senders: {other: 5});
      final s = service();
      await s.load();
      await s.update({'enabled': true});
      s.settings.since = DateTime(2026, 10, 1);
      await s.tick();
      final report = (await s.read('2026-10'))!;
      final availability = report['availability']! as Map;
      final outages = (availability['outages']! as List).cast<Map<Object?, Object?>>();
      expect(DateTime.fromMillisecondsSinceEpoch(outages.first['from'] as int).day, 11);
      expect(DateTime.fromMillisecondsSinceEpoch(outages.first['to'] as int).day, 13);
      expect(availability['ratio'], lessThan(1));
    });

    test('Busmonitor-Zähler: viele Ablehnungen werden zum Befund, sonst keiner', () async {
      Map<String, Object?> rollup(int naks) => {
        'day': '2026-10-05',
        'n': 0,
        'busmon': {'data': 1000, 'acks': 1000, 'naks': naks, 'busy': 0, 'damaged': 0, 'orphanAcks': 2},
      };
      Map<String, Object?> build(int naks) => buildInstallationReport(
        period: ReportPeriod.containing(DateTime(2026, 10, 5), ReportSettings.monthly),
        kind: ReportSettings.monthly,
        rollups: [rollup(naks)],
        catalog: _NoCatalog(),
        now: DateTime(2026, 11, 1),
      );
      final bad = build(50);
      expect((bad['findings']! as List).cast<Map<Object?, Object?>>().single['kind'], 'busErrors');
      expect((bad['busmon']! as Map)['orphanAcks'], 2);
      expect(build(1)['findings'], isEmpty);
    });

    test('unerwartete Neustarts stehen im Bericht, ohne Fehlertext', () async {
      final report = buildInstallationReport(
        period: ReportPeriod.containing(DateTime(2026, 10, 5), ReportSettings.monthly),
        kind: ReportSettings.monthly,
        rollups: const [],
        catalog: _NoCatalog(),
        now: DateTime(2026, 11, 1),
        restarts: [
          {'t': DateTime(2026, 10, 3).millisecondsSinceEpoch, 'reason': 'host'},
        ],
      );
      expect((report['availability']! as Map)['restarts'], hasLength(1));
      expect((report['findings']! as List).cast<Map<Object?, Object?>>().single['kind'], 'restarts');
    });

    test('hält Tagessummen, auch wenn der Verlauf längst weg ist', () async {
      await day(DateTime(2026, 10, 1), senders: {other: 5});
      final s = service();
      await s.load();
      await s.update({'enabled': true});
      s.settings.since = DateTime(2026, 10, 1);
      await s.tick();
      await File('${data.path}/history/2026-10-01.ndjson').delete();
      await File('${data.path}/reports/2026-10.json').delete();
      await s.tick();
      expect(((await s.read('2026-10'))!['traffic']! as Map)['total'], 5);
    });

    test('Zwischenstand bleibt markiert und wird vom fertigen Bericht ersetzt', () async {
      now = DateTime(2026, 10, 15, 12);
      await day(DateTime(2026, 10, 14), senders: {other: 5});
      final s = service();
      await s.load();
      await s.update({'enabled': true});
      await s.tick();
      final partial = await s.generate(null);
      expect(partial['partial'], isTrue);
      expect(partial['id'], '2026-10');
      now = DateTime(2026, 11, 1, 3);
      await s.tick();
      expect((await s.read('2026-10'))!.containsKey('partial'), isFalse);
    });
  });

  group('Standard aus', () {
    test('ohne Einschalten entsteht nichts und nichts geht hinaus', () async {
      await day(DateTime(2026, 10, 1), senders: {other: 5});
      var calls = 0;
      final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      target.listen((r) {
        calls++;
        r.response.close();
      });
      addTearDown(target.close);
      final s = service();
      await s.load();
      expect(s.settings.enabled, isFalse);
      expect(s.settings.notifyKind, 'off');
      s.settings
        ..notifyUrl = 'http://127.0.0.1:${target.port}'
        ..notifyTopic = 'x';
      await s.tick();
      expect(await Directory('${data.path}/reports').exists(), isFalse);
      expect(calls, 0);
    });

    test('eingeschaltet, aber ohne Ziel: Bericht ja, Mitteilung nein', () async {
      await day(DateTime(2026, 10, 1), senders: {other: 5});
      final s = service();
      await s.load();
      await s.update({'enabled': true});
      s.settings.since = DateTime(2026, 10, 1);
      await s.tick();
      expect(await s.read('2026-10'), isNotNull);
      expect(s.lastNotified, isNull);
      expect(s.lastNotifyError, isNull);
    });
  });

  group('Mitteilungen', () {
    late HttpServer target;
    late List<(HttpHeaders, String, String)> received;
    var answer = 200;
    var port = 0;

    setUp(() async {
      received = [];
      answer = 200;
      target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = target.port;
      target.listen((r) async {
        received.add((r.headers, r.uri.path, await utf8.decodeStream(r)));
        r.response.statusCode = answer;
        await r.response.close();
      });
    });
    tearDown(() => target.close(force: true));

    Future<ReportService> enabled(Map<String, Object?> extra) async {
      for (var i = 1; i <= 3; i++) {
        await day(DateTime(2026, 10, i), senders: {sensor: 2}, ga: 0x0801, value: '01');
      }
      final s = service();
      await s.load();
      await s.update({
        'notifyKind': 'ntfy',
        'notifyUrl': 'http://127.0.0.1:$port/geheim',
        'notifyTopic': 'anlage',
        'notifyToken': 'tk_secret',
        ...extra,
      });
      await s.update({'enabled': true});
      s.settings.since = DateTime(2026, 10, 1);
      await s.tick();
      return s;
    }

    test('ntfy bekommt nur eine Zusammenfassung, das Token im Kopf', () async {
      await enabled({});
      expect(received, isNotEmpty);
      for (final (headers, path, body) in received) {
        expect(path, '/geheim/anlage');
        expect(headers.value('authorization'), 'Bearer tk_secret');
        // Keine Namen, Adressen oder Werte der Anlage.
        expect(body, isNot(contains('Rauchmelder')));
        expect(body, isNot(contains('1/0/1')));
        expect(body, isNot(contains('1.1.5')));
      }
      expect(received.any((r) => r.$3.contains('2026-10')), isTrue);
      expect(received.any((r) => r.$3.contains('Dringend')), isTrue);
    });

    test('Dringendes nur einmal am Tag und einmal je Befund', () async {
      final s = await enabled({});
      final before = received.length;
      await s.tick();
      expect(received.length, before);
      now = now.add(const Duration(days: 1));
      await s.tick();
      expect(received.where((r) => r.$3.contains('Dringend')), hasLength(1));
    });

    test('Webhook schickt JSON mit Art und Zeitraum', () async {
      await enabled({'notifyKind': 'webhook'});
      final ready = received.map((r) => jsonDecode(r.$3) as Map).firstWhere((j) => j['kind'] == 'ready');
      expect(ready['source'], 'knx_monitor');
      expect(ready['period'], '2026-10');
    });

    test('Fehlschlag steht nur im Status und verrät weder Adresse noch Token', () async {
      answer = 500;
      final s = await enabled({});
      expect(s.lastNotifyError, 'http500');
      expect(await s.read('2026-10'), isNotNull, reason: 'der Bericht entsteht trotzdem');
      for (final line in logged) {
        expect(line, isNot(contains('tk_secret')));
        expect(line, isNot(contains('geheim')));
      }
    });

    test('Ziel nicht erreichbar: tick kehrt zurück, Bericht liegt da', () async {
      await target.close(force: true);
      final s = await enabled({});
      expect(s.lastNotifyError, 'network');
      expect(await s.read('2026-10'), isNotNull);
      for (final line in logged) {
        expect(line, isNot(contains('tk_secret')));
      }
    });

    test('Testmitteilung meldet das Ergebnis', () async {
      final s = service();
      await s.load();
      expect((await s.sendTest()).ok, isFalse, reason: 'ohne Ziel kein Versand');
      expect(received, isEmpty);
      await s.update({'notifyKind': 'webhook', 'notifyUrl': 'http://127.0.0.1:${target.port}/hook'});
      expect((await s.sendTest()).ok, isTrue);
      expect(jsonDecode(received.single.$3), containsPair('kind', 'test'));
    });

    test('Home Assistant über den vorhandenen Weg', () async {
      await day(DateTime(2026, 10, 1), senders: {other: 2});
      final sent = <String>[];
      final s = service(
        ha: ({required id, required title, required message}) async {
          sent.add(message);
          return true;
        },
      );
      await s.load();
      await s.update({'notifyKind': 'homeassistant', 'enabled': true});
      s.settings.since = DateTime(2026, 10, 1);
      await s.tick();
      expect(sent.single, contains('2026-10'));
    });

    test('Wartung fällig: einmal je Termin', () async {
      final s = await enabled({'maintenanceDue': DateTime(2026, 10, 20).millisecondsSinceEpoch});
      expect(received.where((r) => r.$3.contains('Wartung')), hasLength(1));
      now = now.add(const Duration(days: 1));
      await s.tick();
      expect(received.where((r) => r.$3.contains('Wartung')), hasLength(1));
      expect((await s.read('2026-10'))!['maintenanceDue'], DateTime(2026, 10, 20).millisecondsSinceEpoch);
    });
  });

  group('Schnittstelle', () {
    late HttpServer server;
    late Uri base;
    var admin = true;

    setUp(() async {
      admin = true;
      final s = service();
      await s.load();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = Uri.parse('http://127.0.0.1:${server.port}/');
      server.listen((request) async {
        if (await serveReports(request, s, admin: admin)) return;
        await serveFile(request, data, request.uri.path.substring('/api/files/'.length));
      });
    });
    tearDown(() => server.close(force: true));

    Future<(int, String)> call(String method, String path, [Object? body]) async {
      final client = HttpClient();
      try {
        final request = await client.openUrl(method, base.resolve(path));
        if (body != null) request.write(jsonEncode(body));
        final response = await request.close();
        return (response.statusCode, await utf8.decodeStream(response));
      } finally {
        client.close();
      }
    }

    test('Token geht hinein, aber nie wieder hinaus', () async {
      final (status, text) = await call('PUT', 'api/report', {
        'notifyKind': 'webhook',
        'notifyUrl': 'http://192.168.1.2/hook',
        'notifyToken': 'tk_secret',
      });
      expect(status, 200);
      expect(text, isNot(contains('tk_secret')));
      final settings = (jsonDecode(text) as Map)['settings'] as Map;
      expect(settings['hasNotifyToken'], isTrue);
      expect(await File('${data.path}/report_settings.json').readAsString(), contains('tk_secret'));
      // Leer heißt „unverändert“.
      final (_, again) = await call('PUT', 'api/report', {'notifyToken': ''});
      expect(((jsonDecode(again) as Map)['settings'] as Map)['hasNotifyToken'], isTrue);
      final (_, cleared) = await call('PUT', 'api/report', {'clearToken': true});
      expect(((jsonDecode(cleared) as Map)['settings'] as Map)['hasNotifyToken'], isFalse);
    });

    test('neues Ziel ohne neues Token: das alte Token geht nicht mit', () async {
      bool hasToken(String text) => ((jsonDecode(text) as Map)['settings'] as Map)['hasNotifyToken'] == true;
      final first = {'notifyKind': 'webhook', 'notifyUrl': 'http://192.168.1.2/hook', 'notifyToken': 'tk_secret'};
      expect(hasToken((await call('PUT', 'api/report', first)).$2), isTrue);
      // Dasselbe Ziel noch einmal (die App schickt immer alles): Token bleibt.
      expect(hasToken((await call('PUT', 'api/report', {...first, 'notifyToken': ''})).$2), isTrue);
      final moved = {'notifyKind': 'webhook', 'notifyUrl': 'http://192.168.1.3/hook', 'notifyToken': ''};
      expect(hasToken((await call('PUT', 'api/report', moved)).$2), isFalse);
      expect(await File('${data.path}/report_settings.json').readAsString(), isNot(contains('tk_secret')));
      // Mit neuem Token zusammen geht beides.
      expect(
        hasToken(
          (await call('PUT', 'api/report', {
            ...moved,
            'notifyUrl': 'http://192.168.1.4/hook',
            'notifyToken': 'tk_new',
          })).$2,
        ),
        isTrue,
      );
    });

    test('Datei mit dem Token ist über die Ablage gesperrt', () async {
      await File('${data.path}/report_settings.json').writeAsString('{}');
      expect((await call('GET', 'api/files/report_settings.json')).$1, HttpStatus.forbidden);
      expect((await call('GET', 'api/files/report_settings.json.tmp')).$1, HttpStatus.forbidden);
    });

    test('ungültiges Ziel wird abgelehnt, nichts ändert sich', () async {
      for (final url in ['ftp://x', 'nix', 'http://nutzer:pw@host/']) {
        final (status, _) = await call('PUT', 'api/report', {'notifyKind': 'webhook', 'notifyUrl': url});
        expect(status, HttpStatus.unprocessableEntity, reason: url);
      }
      final (_, text) = await call('GET', 'api/report');
      expect(((jsonDecode(text) as Map)['settings'] as Map)['notifyKind'], 'off');
    });

    test('nur Admin darf Ziel setzen, Test auslösen und den Wartungstermin setzen', () async {
      admin = false;
      expect((await call('PUT', 'api/report', {'enabled': true})).$1, HttpStatus.forbidden);
      expect((await call('POST', 'api/report/test', const {})).$1, HttpStatus.forbidden);
      expect((await call('POST', 'api/report/generate', const {})).$1, HttpStatus.forbidden);
      expect((await call('POST', 'api/report/maintenance', {'due': 1000})).$1, HttpStatus.forbidden);
      expect(await File('${data.path}/report_settings.json').exists(), isFalse);
      admin = true;
      expect((await call('POST', 'api/report/maintenance', {'due': 1000})).$1, HttpStatus.noContent);
    });

    test('unveränderter Wartungstermin schreibt keine Datei', () async {
      expect((await call('POST', 'api/report/maintenance', {'due': null})).$1, HttpStatus.noContent);
      expect(await File('${data.path}/report_settings.json').exists(), isFalse);
    });

    test('unbekannter Bericht und unsichere Id: 404', () async {
      expect((await call('GET', 'api/report/2026-10')).$1, HttpStatus.notFound);
      expect((await call('GET', 'api/report/..%2Fserver')).$1, HttpStatus.notFound);
    });
  });

  test('Fehler im Bericht stören den Bus nicht', () async {
    // Ein Ordner kann „reports“ nicht werden, wenn dort schon eine Datei liegt.
    await File('${data.path}/reports').writeAsString('');
    await day(DateTime(2026, 10, 1), senders: {other: 2});
    final s = service();
    await s.load();
    await s.update({'enabled': true});
    await s.tick();
    expect(s.lastError, isNotNull);
    // Die Aufzeichnung läuft unbeeindruckt.
    bus.recorder.add({'t': DateTime(2026, 11, 1, 3).microsecondsSinceEpoch, 's': 1, 'd': 2, 'y': 2, 'x': '00'});
    await bus.recorder.flush();
    expect(bus.recorder.written, 1);
  });
}

class _NoCatalog implements ReportCatalog {
  @override
  String formatGroup(int group) => '$group';
  @override
  String? nameOf(int group) => null;
  @override
  (int, int?)? dptOf(int group) => null;
  @override
  String? kindOf(int group) => null;
  @override
  String searchTextOf(int group) => '';
  @override
  Iterable<int> get groups => const [];
}
