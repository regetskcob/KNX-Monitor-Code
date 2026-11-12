import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/model/box_connection.dart';
import 'package:knx_monitor/model/box_setup.dart';
import 'package:knx_monitor/platform/addon.dart';
import 'package:knx_monitor/platform/box_link.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Einrichtung aus dem Aufkleber-QR-Code gegen eine nachgebaute Box: WLAN,
/// Koppeln mit dem Box-Passwort, Uhr, Gateway – ohne Browser.
void main() {
  late HttpServer server;
  final requests = <String>[];
  Map<String, Object?>? configured;
  var gateways = <Map<String, Object?>>[];
  String? pairBody;
  String? claimBody;
  String? claimAuth;
  var claimStatus = HttpStatus.ok;
  Map<String, Object?>? boxInfo;
  var boxInfoStatus = HttpStatus.ok;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    requests.clear();
    claimBody = null;
    claimAuth = null;
    claimStatus = HttpStatus.ok;
    configured = null;
    boxInfo = null;
    boxInfoStatus = HttpStatus.ok;
    gateways = [
      {'host': '192.168.1.22', 'port': 3671, 'dibs': ''},
    ];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final auth = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
      final path = request.uri.path;
      requests.add('${request.method} $path');
      final body = await utf8.decodeStream(request);
      Object? answer;
      if (path == '/api/box/pair') {
        // Nur mit dem Box-Passwort vom Aufkleber.
        if (auth != 'Basic ${base64.encode(utf8.encode('app:box#pass'))}') {
          request.response.statusCode = HttpStatus.unauthorized;
          return request.response.close();
        }
        pairBody = body;
        answer = {'key': 'geraetezugang', 'id': 'a1', 'name': 'KNX-Box-1A2B'};
      } else if (path == '/api/box/claim') {
        // Einmal-Code von der Kopplungsseite: im Rumpf, ohne Anmeldung, nur einmal gültig.
        claimAuth = auth;
        claimBody = body;
        if (claimStatus != HttpStatus.ok || (jsonDecode(body) as Map)['code'] != 'einmal-code') {
          request.response.statusCode = claimStatus == HttpStatus.ok ? HttpStatus.forbidden : claimStatus;
          return request.response.close();
        }
        answer = {'key': 'geraetezugang', 'id': 'b2', 'name': 'KNX-Box-1A2B'};
      } else if (auth != 'Bearer geraetezugang') {
        request.response.statusCode = HttpStatus.unauthorized;
        return request.response.close();
      } else if (path == '/api/box') {
        if (boxInfoStatus != HttpStatus.ok) {
          request.response.statusCode = boxInfoStatus;
          return request.response.close();
        }
        answer = boxInfo ?? <String, Object?>{};
      } else if (path == '/api/box/time') {
        answer = {
          'result': 'set',
          'clock': {'source': 'client', 'synced': true},
        };
      } else if (path == '/api/bus' && request.method == 'GET') {
        answer = {
          'state': 'disconnected',
          'config': {'host': ''},
        };
      } else if (path == '/api/bus') {
        configured = (jsonDecode(body) as Map).cast<String, Object?>();
        answer = {'state': 'connecting', 'config': configured};
      } else if (path == '/api/discover') {
        answer = gateways;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(answer));
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    Addon.box = null;
  });

  BoxLink setupLink() => BoxLink.parse(
    'knxmonitor://box?url=http%3A%2F%2F127.0.0.1%3A${server.port}%2F&name=KNX-Box-1A2B'
    '&ssid=KNX-Box-1A2B&wifi=wlanpass12&pw=box%23pass',
  )!;

  group('Kopplungslink mit Einmal-Code', () {
    BoxLink codeLink([String code = 'einmal-code']) =>
        BoxLink.parse('knxmonitor://box?url=http%3A%2F%2F127.0.0.1%3A${server.port}%2F&code=$code&name=KNX-Box-1A2B')!;

    test('die App tauscht den Code gegen den Gerätezugang und speichert nur den', () async {
      final setup = BoxSetup(
        codeLink(),
        deviceName: 'iPhone',
        joinWifi: (_, _) async => fail('kein WLAN im Link'),
        reachable: (_) async => true,
        choosePassword: () async => fail('nicht mit dem Aufkleber gekoppelt'),
      );
      await setup.run();
      expect(setup.error, isNull, reason: '$requests');
      expect(setup.states[BoxSetupStep.wifi], BoxStepState.skipped);
      expect(setup.states[BoxSetupStep.pair], BoxStepState.done);
      expect(jsonDecode(claimBody!), {
        'code': 'einmal-code',
        'name': 'iPhone',
        'app': matches(RegExp(r'^[0-9a-f]{32}$')),
      });
      // Der Code steht nur im Rumpf: kein Authorization-Kopf, nichts in der Adresse.
      expect(claimAuth, isEmpty);
      expect(requests.where((r) => r.contains('claim')), ['POST /api/box/claim']);
      expect(requests, isNot(contains('POST /api/box/pair')));
      expect(Addon.box?.key, 'geraetezugang');
      expect(Addon.box?.code, isEmpty);
      expect('${BoxConnection.instance.saved?.toUri()}', isNot(contains('einmal-code')));
      expect(requests, contains('POST /api/box/time'));
    });

    test('abgelaufener oder benutzter Code: verständlicher Fehler, nichts gekoppelt', () async {
      final setup = BoxSetup(codeLink('schon-benutzt'), deviceName: 'iPhone', reachable: (_) async => true);
      await setup.run();
      expect(setup.states[BoxSetupStep.pair], BoxStepState.failed);
      expect(setup.error, contains('Kopplungscode'));
      expect(setup.states[BoxSetupStep.time], BoxStepState.waiting);
      expect(Addon.box, isNull);
    });

    test('Sperre der Box nach Fehlversuchen wird als solche gemeldet', () async {
      claimStatus = HttpStatus.tooManyRequests;
      final setup = BoxSetup(codeLink(), deviceName: 'iPhone', reachable: (_) async => true);
      await setup.run();
      expect(setup.states[BoxSetupStep.pair], BoxStepState.failed);
      expect(setup.error, contains('Fehlversuche'));
      expect(Addon.box, isNull);
    });

    test('ältere Box ohne Tausch (401/404): derselbe Fehler, nichts gekoppelt', () async {
      for (final status in [HttpStatus.unauthorized, HttpStatus.notFound]) {
        claimStatus = status;
        final setup = BoxSetup(codeLink(), deviceName: 'iPhone', reachable: (_) async => true);
        await setup.run();
        expect(setup.states[BoxSetupStep.pair], BoxStepState.failed, reason: '$status');
        expect(Addon.box, isNull);
      }
    });

    test('Link mit Schlüssel (Box bis 1.11.2) koppelt wie bisher, ohne Tausch', () async {
      final link = BoxLink.parse(
        'knxmonitor://box?url=http%3A%2F%2F127.0.0.1%3A${server.port}%2F&key=geraetezugang&name=KNX-Box-1A2B',
      )!;
      final setup = BoxSetup(link, deviceName: 'iPhone', reachable: (_) async => true);
      await setup.run();
      expect(setup.error, isNull);
      expect(setup.states[BoxSetupStep.pair], BoxStepState.skipped);
      expect(requests, isNot(contains('POST /api/box/claim')));
      expect(Addon.box?.key, 'geraetezugang');
    });
  });

  group('unverschlüsselt zu einer Adresse im Internet', () {
    for (final (what, query) in [
      ('Schlüssel', 'key=geraetezugang'),
      ('Einmal-Code', 'code=einmal-code'),
      ('Box-Passwort', 'pw=box%23pass'),
    ]) {
      test('$what geht nicht hinaus: Kopplung scheitert mit Erklärung, nichts gespeichert', () async {
        final link = BoxLink.parse('knxmonitor://box?url=http%3A%2F%2Fbox.example.com%2F&$query')!;
        await BoxConnection.instance.forget();
        final setup = BoxSetup(link, deviceName: 'iPhone', reachable: (_) async => true);
        await setup.run();
        expect(setup.states[BoxSetupStep.pair], BoxStepState.failed);
        expect(setup.error, allOf(contains('box.example.com'), contains('unverschlüsselt')));
        expect(Addon.box, isNull);
        expect(BoxConnection.instance.saved, isNull);
        expect(requests, isEmpty);
      });
    }
  });

  test('Fehler beim Abfragen der Pflicht koppelt nicht einfach weiter', () async {
    boxInfoStatus = HttpStatus.internalServerError;
    final setup = BoxSetup(
      setupLink(),
      deviceName: 'iPhone',
      joinWifi: (_, _) async => 'joined',
      reachable: (_) async => true,
      choosePassword: () async => true,
    );
    await setup.run();
    expect(setup.states[BoxSetupStep.pair], BoxStepState.failed);
    expect(requests, isNot(contains('POST /api/box/time')));
  });

  test('ältere Box ohne Info koppelt ohne Pflicht', () async {
    boxInfoStatus = HttpStatus.notFound;
    final setup = BoxSetup(
      setupLink(),
      deviceName: 'iPhone',
      joinWifi: (_, _) async => 'joined',
      reachable: (_) async => true,
      choosePassword: () async => fail('ältere Box fragt nicht'),
    );
    await setup.run();
    expect(setup.states[BoxSetupStep.pair], BoxStepState.done);
  });

  group('Box verlangt ein eigenes Passwort', () {
    setUp(() => boxInfo = {'role': 'admin', 'mustChangePassword': true, 'passwordChangeRequired': true});

    test('wird beim Koppeln gesetzt, vor Uhr und Gateway', () async {
      var asked = 0;
      late BoxSetup setup;
      setup = BoxSetup(
        setupLink(),
        deviceName: 'iPhone',
        joinWifi: (_, _) async => 'joined',
        reachable: (_) async => true,
        choosePassword: () async {
          asked++;
          expect(requests, isNot(contains('POST /api/box/time')));
          expect(setup.states[BoxSetupStep.pair], BoxStepState.running);
          boxInfo = {'role': 'admin'};
          return true;
        },
      );
      await setup.run();
      expect(asked, 1);
      expect(setup.error, isNull);
      expect(setup.states[BoxSetupStep.pair], BoxStepState.done);
      expect(requests, contains('POST /api/box/time'));
    });

    test('ohne eigenes Passwort geht es nicht weiter', () async {
      final setup = BoxSetup(
        setupLink(),
        deviceName: 'iPhone',
        joinWifi: (_, _) async => 'joined',
        reachable: (_) async => true,
        choosePassword: () async => false,
      );
      await setup.run();
      expect(setup.states[BoxSetupStep.pair], BoxStepState.failed);
      expect(setup.error, BoxSetup.passwordMissing);
      expect(setup.states[BoxSetupStep.time], BoxStepState.waiting);
    });
  });

  test('vom Aufkleber bis zum eingestellten Gateway', () async {
    final joined = <String>[];
    final setup = BoxSetup(
      setupLink(),
      deviceName: 'iPhone',
      joinWifi: (ssid, password) async {
        joined.add('$ssid/$password');
        return 'joined';
      },
      reachable: (_) async => true,
    );
    await setup.run();
    expect(setup.error, isNull, reason: '$requests');
    // Die App nennt beim Koppeln auch ihre Instanz (docs/keys.md).
    expect(jsonDecode(pairBody!), {'name': 'iPhone', 'app': matches(RegExp(r'^[0-9a-f]{32}$'))});
    expect(joined, ['KNX-Box-1A2B/wlanpass12']);
    expect(setup.states.values, everyElement(BoxStepState.done));
    // Gespeichert ist der Gerätezugang, nicht das Box-Passwort.
    expect(Addon.box?.key, 'geraetezugang');
    expect(BoxConnection.instance.saved?.password, isEmpty);
    expect(setup.timeResult, 'set');
    expect(configured, {'enabled': true, 'mode': 'udp', 'host': '192.168.1.22', 'port': 3671});
    expect(setup.gateway, '192.168.1.22');
  });

  test('mehrere Gateways: Auswahl bleibt beim Nutzer', () async {
    gateways = [
      {'host': '192.168.1.22', 'port': 3671, 'dibs': ''},
      {'host': '192.168.1.23', 'port': 3671, 'dibs': ''},
    ];
    final setup = BoxSetup(
      setupLink(),
      deviceName: 'iPhone',
      joinWifi: (_, _) async => 'unsupported',
      reachable: (_) async => true,
    );
    await setup.run();
    expect(setup.states[BoxSetupStep.wifi], BoxStepState.manual);
    expect(setup.states[BoxSetupStep.gateway], BoxStepState.manual);
    expect(setup.gateways, hasLength(2));
    expect(configured, isNull);
  });

  test('WLAN abgelehnt: Abbruch, nichts gekoppelt', () async {
    final setup = BoxSetup(
      setupLink(),
      deviceName: 'iPhone',
      joinWifi: (_, _) async => 'denied',
      reachable: (_) async => true,
    );
    await setup.run();
    expect(setup.states[BoxSetupStep.wifi], BoxStepState.failed);
    expect(setup.error, 'denied');
    expect(setup.states[BoxSetupStep.pair], BoxStepState.waiting);
    expect(requests, isEmpty);
  });

  test('Box antwortet nicht: Fehler nach der Wartezeit', () async {
    final setup = BoxSetup(
      setupLink(),
      deviceName: 'iPhone',
      joinWifi: (_, _) async => 'joined',
      reachable: (_) async => false,
      reachTimeout: Duration.zero,
    );
    await setup.run();
    expect(setup.states[BoxSetupStep.reach], BoxStepState.failed);
    expect(setup.error, 'unreachable');
  });
}
