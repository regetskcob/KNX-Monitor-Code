import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

void main() {
  test('Link der Mitteilungen: Seite des Add-ons aus der Supervisor-Antwort', () {
    expect(
      panelPathOf({
        'data': {'slug': '2541da37_knx_monitor'},
      }),
      '/hassio/ingress/2541da37_knx_monitor',
    );
    expect(
      panelPathOf({
        'data': {'slug': 'x)](javascript:'},
      }),
      isNull,
    );
    expect(panelPathOf({'result': 'error'}), isNull);
  });

  group('HomeAssistant', () {
    late HttpServer server;
    final requests = <(String, String, String?, Object?)>[];
    var components = <String>['knx', 'mqtt'];

    setUp(() async {
      requests.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        final body = await utf8.decodeStream(r);
        requests.add((
          r.method,
          r.uri.path,
          r.headers.value(HttpHeaders.authorizationHeader),
          body.isEmpty ? null : jsonDecode(body),
        ));
        if (r.uri.path == '/core/api/config') {
          r.response.headers.contentType = ContentType.json;
          r.response.write(jsonEncode({'components': components}));
        }
        await r.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    HomeAssistant ha() => HomeAssistant(token: 'geheim', base: Uri.parse('http://127.0.0.1:${server.port}/core/'));

    test('Ereignis über die Supervisor-API', () async {
      await ha().fire(HomeAssistant.busEvent, {'connected': false, 'state': 'disconnected'});
      expect(requests.single.$1, 'POST');
      expect(requests.single.$2, '/core/api/events/knx_monitor_bus');
      expect(requests.single.$3, 'Bearer geheim');
      expect(requests.single.$4, {'connected': false, 'state': 'disconnected'});
    });

    test('KNX-Integration erkennen', () async {
      final h = ha();
      expect(await h.refreshKnx(), isTrue);
      components = ['mqtt'];
      expect(await h.refreshKnx(), isFalse);
      expect(h.knx, isFalse);
    });

    test('ohne Supervisor: nichts senden, nichts wissen', () async {
      final h = HomeAssistant(token: null, base: Uri.parse('http://127.0.0.1:${server.port}/core/'));
      expect(h.available, isFalse);
      await h.fire(HomeAssistant.alarmEvent, {});
      expect(await h.refreshKnx(), isNull);
      expect(requests, isEmpty);
    });

    test('nicht erreichbar: kein Fehler nach außen', () async {
      final h = HomeAssistant(token: 'x', base: Uri.parse('http://127.0.0.1:1/core/'));
      await h.fire(HomeAssistant.watcherEvent, {});
      expect(await h.refreshKnx(), isNull);
    });
  });

  group('Treffer und Wechsel für Ereignisse', () {
    late Directory data;
    final notes = <String>[];

    setUp(() async {
      data = await Directory.systemTemp.createTemp('knx_ha');
      notes.clear();
    });
    tearDown(() => data.delete(recursive: true));

    Map<String, Object?> line(int ga, String hex, {bool small = false, int seconds = 0}) => {
      't': DateTime(2026, 10, 25, 12, 0, seconds).microsecondsSinceEpoch,
      's': 0x1105,
      'd': ga,
      'y': 2,
      'x': hex,
      if (small) 'm': true,
    };

    test('Wächter: jeder Treffer nach der Sperrzeit, auch ohne Mitteilung', () async {
      await File('${data.path}/watch_rules.json').writeAsString(
        jsonEncode({
          'rules': [
            {
              'id': 'wind',
              'address': 0x4101,
              'label': '8/1/1 Wind > 10',
              'name': 'Windgeschwindigkeit',
              'check': {
                'num': [9, 5],
                'op': 'greater',
                'n': 10,
              },
            },
          ],
        }),
      );
      final set = WatchRuleSet(data, notify: ({required id, required title, required message}) async => notes.add(id));
      final hits = <WatchHit>[];
      // 0x0C B0 = 24,0 (DPT 9); innerhalb einer Minute nur eine Mitteilung.
      await set.check(line(0x4101, '0CB0'), onHit: hits.add);
      await set.check(line(0x4101, '0CB0', seconds: 10), onHit: hits.add);
      expect(hits, hasLength(2));
      expect(notes, hasLength(1));
      expect(hits.first.id, 'wind');
      expect(hits.first.name, 'Windgeschwindigkeit');
      expect(hits.first.value, closeTo(24.0, 0.01));
    });

    test('DPT 21.001: Alarm endet als Alarm, nicht als Störung', () async {
      await File('${data.path}/catalog.json').writeAsString(
        jsonEncode({
          'groups': [
            {
              'a': 0x0802,
              'n': 'Zentrale Status',
              'd': [21, 1],
            },
          ],
        }),
      );
      final changes = <AlarmChange>[];
      final alarms = AlarmWatch(
        data,
        notify: ({required id, required title, required message}) async {},
        onChange: changes.add,
      );
      await alarms.check(line(0x0802, '08')); // Bit 3: Alarm
      await alarms.check(line(0x0802, '00', seconds: 1));
      expect(changes.map((c) => (c.kind, c.active)), [('alarm', true), ('alarm', false)]);
    });

    test('Alarm: an und aus, auch bei abgeschalteten Mitteilungen', () async {
      await File('${data.path}/catalog.json').writeAsString(
        jsonEncode({
          'style': 'threeLevel',
          'groups': [
            {
              'a': 0x0801,
              'n': 'Rauchmelder Flur',
              'd': [1, 5],
            },
          ],
        }),
      );
      final changes = <AlarmChange>[];
      final alarms = AlarmWatch(
        data,
        notify: ({required id, required title, required message}) async => notes.add(id),
        onChange: changes.add,
      )..enabled = false;
      await alarms.check(line(0x0801, '01', small: true));
      await alarms.check(line(0x0801, '01', small: true, seconds: 1));
      await alarms.check(line(0x0801, '00', small: true, seconds: 2));
      expect(notes, isEmpty);
      expect(changes.map((c) => c.active), [true, false]);
      expect(changes.first.groupAddress, '1/0/1');
      expect(changes.first.name, 'Rauchmelder Flur');
      expect(changes.first.kind, 'alarm');
    });

    test('Alarm: in der App korrigierter Name ersetzt den aus dem Projekt', () async {
      await File('${data.path}/catalog.json').writeAsString(
        jsonEncode({
          'style': 'threeLevel',
          'groups': [
            {
              'a': 0x0801,
              'n': 'Rauchmeldr Flur',
              'd': [1, 5],
            },
          ],
        }),
      );
      final alarms = AlarmWatch(data, notify: ({required id, required title, required message}) async {});
      await alarms.loadCatalog();
      expect(alarms.nameOf(0x0801), 'Rauchmeldr Flur');
      await File('${data.path}/name_overrides.json').writeAsString(jsonEncode({'${0x0801}': 'Rauchmelder Flur'}));
      await alarms.loadCatalog();
      expect(alarms.nameOf(0x0801), 'Rauchmelder Flur');
      await File('${data.path}/name_overrides.json').delete();
      await alarms.loadCatalog();
      expect(alarms.nameOf(0x0801), 'Rauchmeldr Flur');
    });

    test('Alarm: angelernte Adressen ohne ETS-Projekt, das Projekt hat Vorrang', () async {
      final catalog = File('${data.path}/catalog.json');
      if (await catalog.exists()) await catalog.delete();
      await File('${data.path}/learned.json').writeAsString(
        jsonEncode({
          'groups': [
            {
              'a': 0x0801,
              'n': 'Rauchmelder Keller',
              'd': [1, 5],
            },
            {'a': 0x0802, 'n': 'Wassermelder Bad'},
          ],
          'devices': <Object>[],
        }),
      );
      final notes = <String>[];
      final alarms = AlarmWatch(
        data,
        notify: ({required id, required title, required message}) async => notes.add(title),
      );
      await alarms.loadCatalog();
      expect(alarms.nameOf(0x0801), 'Rauchmelder Keller');
      expect(alarms.dptMainOf(0x0801), 1);
      await alarms.check(line(0x0801, '01', small: true));
      expect(notes.single, contains('Rauchmelder Keller'));

      // The project wins, the learned type fills in a missing one, a correction replaces both.
      await catalog.writeAsString(
        jsonEncode({
          'style': 'threeLevel',
          'groups': [
            {'a': 0x0801, 'n': 'RM Keller'},
          ],
        }),
      );
      await alarms.loadCatalog();
      expect(alarms.nameOf(0x0801), 'RM Keller');
      expect(alarms.dptMainOf(0x0801), 1);
      expect(alarms.nameOf(0x0802), 'Wassermelder Bad');
      await File('${data.path}/name_overrides.json').writeAsString(jsonEncode({'${0x0802}': 'Wassermelder Gäste-WC'}));
      await alarms.loadCatalog();
      expect(alarms.nameOf(0x0802), 'Wassermelder Gäste-WC');

      // Old project that left the address without a name: the learned name applies.
      await catalog.writeAsString(
        jsonEncode({
          'style': 'threeLevel',
          'groups': [
            {'a': 0x0801, 'n': 'Neue Gruppenadresse'},
          ],
        }),
      );
      await alarms.loadCatalog();
      expect(alarms.nameOf(0x0801), 'Rauchmelder Keller');

      // Its own address counts as unnamed, any other number is a maintained name.
      for (final (name, expected) in [('1/0/1', 'Rauchmelder Keller'), ('123', '123'), ('1/2', '1/2')]) {
        await catalog.writeAsString(
          jsonEncode({
            'style': 'threeLevel',
            'groups': [
              {'a': 0x0801, 'n': name},
            ],
          }),
        );
        await alarms.loadCatalog();
        expect(alarms.nameOf(0x0801), expected, reason: name);
      }
      await File('${data.path}/name_overrides.json').delete();
      await File('${data.path}/learned.json').delete();
      await catalog.delete();
    });
  });
}
