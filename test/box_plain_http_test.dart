import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/platform/addon.dart';
import 'package:knx_monitor/platform/addon_io.dart';
import 'package:knx_monitor/platform/box_link.dart';

/// Every connection the app's HTTP clients open is noted here, and none leaves this machine: a
/// test that got past the refusal would otherwise talk to the network.
class _Watch extends HttpOverrides {
  final opened = <Uri>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) => super.createHttpClient(context)
    ..findProxy = ((_) => 'DIRECT')
    ..connectionFactory = (uri, proxyHost, proxyPort) {
      opened.add(uri);
      if (uri.host != '127.0.0.1') throw SocketException('Test: keine Verbindung nach außen ($uri)');
      return Socket.startConnect(uri.host, uri.port);
    };
}

/// Finding A of the code review (KNX-Monitor-Code#3): device access, box password and pairing code
/// never go over unencrypted HTTP to an address outside the local network. The app refuses before
/// it opens a connection.
void main() {
  final watch = _Watch();
  late HttpServer server;
  final seen = <({String method, String path, String? auth, String body})>[];

  setUpAll(() async {
    HttpOverrides.global = watch;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final auth = request.headers.value(HttpHeaders.authorizationHeader);
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        seen.add((method: 'WS', path: request.uri.path, auth: auth, body: ''));
        // Closed with the test server.
        // ignore: close_sinks
        final ws = await WebSocketTransformer.upgrade(request);
        ws.add(utf8.encode('hallo'));
        return;
      }
      final body = await utf8.decodeStream(request);
      seen.add((method: request.method, path: request.uri.path, auth: auth, body: body));
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        request.uri.path.endsWith('/list') ? '[]' : jsonEncode({'key': 'geraetezugang', 'ok': true}),
      );
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
    HttpOverrides.global = null;
  });

  setUp(() {
    watch.opened.clear();
    seen.clear();
  });

  tearDown(() => Addon.box = null);

  Matcher refused(String address) => throwsA(
    isA<AddonException>()
        .having((e) => e.problem, 'problem', plainRefusedProblem)
        .having((e) => e.message, 'message', allOf(contains(address), contains('unverschlüsselt'))),
  );

  /// Everything in `addon_io.dart` that sends the device access, one call each.
  Map<String, Future<Object?> Function()> everyRequest(Directory dir, void Function() touched) => {
    'GET': () => addonGet('api/bus'),
    'GET (Liste)': () => addonGetList('api/list'),
    'PUT': () => addonPut('api/bus', const {'enabled': true}),
    'PATCH': () => addonPatch('api/installations/default', const {'name': 'x'}),
    'POST': () => addonPost('api/report/generate', const {}),
    'DELETE': () => addonDelete('api/installations/default'),
    'Datei lesen': () => addonGetFile('catalog.json'),
    'Datei schreiben': () => addonPutFile('catalog.json', utf8.encode('{}')),
    'Download': () => addonDownload('api/export/ets-xml', 'export.xml'),
    'Download in Datei': () => addonDownloadToFile('api/backup', '${dir.path}/sicherung.zip', null, null),
    'Upload': () => addonUpload(
      'api/backup/restore',
      Stream<List<int>>.multi((controller) {
        touched();
        controller
          ..add(utf8.encode('geheim'))
          ..close();
      }),
      6,
      null,
    ),
    'WebSocket': Addon.openBus,
  };

  group('ohne Fingerabdruck an eine fremde Adresse', () {
    for (final host in ['box.example.com', '203.0.113.7', 'box.example.com:8765', '[2001:db8::1]']) {
      test('$host: keine Anfrage geht hinaus, kein Authorization-Kopf entsteht', () async {
        final dir = await Directory.systemTemp.createTemp('box_plain');
        addTearDown(() => dir.delete(recursive: true));
        final link = BoxLink.parse('knxmonitor://box?url=${Uri.encodeQueryComponent('http://$host/')}&key=zugang')!;
        expect(link.encrypted, isFalse);
        expect(link.isLocal, isFalse);
        Addon.box = link;
        var bodyRead = false;
        final requests = everyRequest(dir, () => bodyRead = true);
        for (final MapEntry(key: what, value: send) in requests.entries) {
          await expectLater(send(), refused(link.address), reason: what);
        }
        expect(watch.opened, isEmpty);
        expect(seen, isEmpty);
        expect(bodyRead, isFalse, reason: 'der Upload wurde gelesen');
        expect(dir.listSync(), isEmpty, reason: 'eine Download-Datei blieb liegen');
      });
    }

    test('Koppeln mit dem Box-Passwort und Tausch des Einmal-Codes: ebenso abgelehnt', () async {
      final setup = BoxLink.parse('knxmonitor://box?url=http%3A%2F%2Fbox.example.com%2F&pw=box%23pass')!;
      await expectLater(Addon.pairBox(setup, setup.password, 'iPhone'), refused('box.example.com'));
      final code = BoxLink.parse('knxmonitor://box?url=http%3A%2F%2Fbox.example.com%2F&code=einmal')!;
      await expectLater(Addon.claimBox(code, 'iPhone'), refused('box.example.com'));
      expect(watch.opened, isEmpty);
    });

    test('die Ablehnung nennt Adresse und Grund, für das Koppeln schon vorab', () {
      final link = BoxLink(url: Uri.parse('http://box.example.com:8765/'), key: 'zugang');
      expect(Addon.refusal(link), allOf(contains('box.example.com:8765'), contains('HTTPS')));
    });

    test('ohne Zugang im Link entsteht kein Kopf: Die Regel greift nicht', () async {
      // A server without access protection (development mode): the request carries nothing secret.
      Addon.box = BoxLink(url: Uri.parse('http://box.example.com/'));
      await expectLater(
        addonGet('api/bus'),
        throwsA(isA<AddonException>().having((e) => e.problem, 'problem', isNull)),
      );
      expect(watch.opened.single.host, 'box.example.com');
    });
  });

  group('lokale Adresse ohne Fingerabdruck', () {
    BoxLink local([String query = 'key=zugang']) =>
        BoxLink.parse('knxmonitor://box?url=http%3A%2F%2F127.0.0.1%3A${server.port}%2F&$query')!;

    test('alles geht wie bisher, mit dem Gerätezugang im Kopf', () async {
      final dir = await Directory.systemTemp.createTemp('box_plain');
      addTearDown(() => dir.delete(recursive: true));
      Addon.box = local();
      expect(await addonGet('api/bus'), containsPair('ok', true));
      expect(await addonGetList('api/list'), isEmpty);
      expect(await addonPut('api/bus', const {'enabled': true}), containsPair('ok', true));
      await addonPost('api/report/generate', const {});
      await addonDelete('api/installations/default');
      expect(await addonGetFile('catalog.json'), isNotNull);
      await addonPutFile('catalog.json', utf8.encode('{}'));
      expect(await addonDownload('api/export/ets-xml', 'export.xml'), isNotNull);
      expect(await addonUpload('api/backup/restore', Stream.value(utf8.encode('geheim')), 6, null), isNotEmpty);
      final socket = await Addon.openBus();
      expect(utf8.decode(await socket.messages.first), 'hallo');
      socket.close();
      expect(seen, hasLength(10));
      expect(seen.map((r) => r.auth), everyElement('Bearer zugang'));
      expect(seen.last.method, 'WS');
    });

    test('Koppeln mit dem Box-Passwort und Tausch des Einmal-Codes', () async {
      expect(await Addon.pairBox(local('pw=box%23pass'), 'box#pass', 'iPhone'), 'geraetezugang');
      expect(seen.single.auth, 'Basic ${base64.encode(utf8.encode('app:box#pass'))}');
      seen.clear();
      expect(await Addon.claimBox(local('code=einmal'), 'iPhone', app: 'a' * 32), 'geraetezugang');
      expect(seen.single.path, '/api/box/claim');
      expect(seen.single.auth, isNull);
      expect(jsonDecode(seen.single.body), {'code': 'einmal', 'name': 'iPhone', 'app': 'a' * 32});
    });

    test('Heimnetz, WLAN der Box, .local und localhost zählen als lokal', () {
      for (final host in [
        '10.42.0.1',
        '192.168.178.20:8765',
        '172.16.0.5',
        '169.254.1.1',
        'knx-box.local',
        'localhost:8765',
        '[fe80::1]',
        '[fd00::5]',
        '[::1]',
      ]) {
        expect(
          Addon.refusal(BoxLink(url: Uri.parse('http://$host/'), key: 'zugang')),
          isNull,
          reason: host,
        );
      }
    });
  });

  group('HTTPS', () {
    test('fremde Adresse mit Fingerabdruck: nicht abgelehnt, die Verbindung wird versucht', () async {
      // `.invalid` never exists: the attempt ends at the name, not at the rule.
      final link = BoxLink.parse('knxmonitor://box?url=http%3A%2F%2Fbox.invalid%2F&key=zugang&fp=${'A' * 43}')!;
      expect(link.url.scheme, 'https');
      expect(Addon.refusal(link), isNull);
      Addon.box = link;
      await expectLater(
        addonGet('api/bus'),
        throwsA(isA<AddonException>().having((e) => e.problem, 'problem', isNull)),
      );
    });

    test('fremde HTTPS-Adresse ohne Fingerabdruck: nicht abgelehnt, die Anfrage geht über TLS', () async {
      Addon.box = BoxLink(url: Uri.parse('https://box.example.com/'), key: 'zugang');
      await expectLater(
        addonGet('api/bus'),
        throwsA(isA<AddonException>().having((e) => e.problem, 'problem', isNull)),
      );
      expect(watch.opened.single.scheme, 'https');
    });
  });
}
