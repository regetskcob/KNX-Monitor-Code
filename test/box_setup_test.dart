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
  Map<String, Object?>? boxInfo;
  var boxInfoStatus = HttpStatus.ok;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    requests.clear();
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
    expect(jsonDecode(pairBody!), {'name': 'iPhone'});
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
