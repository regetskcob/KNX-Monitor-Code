import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/shared_tunnel.dart';
import 'package:knx_monitor/platform/addon.dart';
import 'package:knx_monitor/platform/box_link.dart';

void main() {
  group('Fingerabdruck', () {
    const fp = 'jK1PqKwwtOKFC1d_AVd6dneK-nohe-3-pLjcLzacW-w';

    test('wechselt auf HTTPS, ältere Apps lesen weiter die HTTP-Adresse', () {
      final link = BoxLink.parse('knxmonitor://box?url=http%3A%2F%2F10.42.0.1%2F&fp=$fp&pw=aufkleber1')!;
      expect(link.fp, fp);
      expect('${link.url}', 'https://10.42.0.1/');
      expect(link.needsPairing, isTrue);
    });

    test('bleibt beim Koppeln und Speichern erhalten', () {
      final link = BoxLink.parse('knxmonitor://box?url=http%3A%2F%2F10.42.0.1%2F&fp=$fp&pw=aufkleber1')!;
      final saved = link.paired('zugang');
      expect(saved.fp, fp);
      expect(BoxLink.parse('${saved.toUri()}'), saved);
      expect(BoxLink.parse('${saved.toUri()}')!.url.scheme, 'https');
    });

    test('HTTPS-Adresse mit eigenem Port (Docker) bleibt, wie sie ist', () {
      final link = BoxLink.parse('knxmonitor://box?url=https%3A%2F%2Fnas.local%3A8443%2F&fp=$fp&key=abc')!;
      expect('${link.url}', 'https://nas.local:8443/');
    });

    test('ungültiger Fingerabdruck: kein Link', () {
      expect(BoxLink.parse('knxmonitor://box?url=http%3A%2F%2F10.42.0.1%2F&fp=kurz&key=abc'), isNull);
    });

    test('ohne Fingerabdruck wie bisher', () {
      final link = BoxLink.parse('knxmonitor://box?url=http%3A%2F%2F10.42.0.1%2F&key=abc')!;
      expect(link.url.scheme, 'http');
      expect(link.toUri().queryParameters.containsKey('fp'), isFalse);
    });
  });

  group('BoxLink.parse', () {
    test('Link aus dem QR-Code', () {
      final link = BoxLink.parse('knxmonitor://box?url=http://10.42.0.1:8765&key=abc_DEF-123&name=KNX-Box-1A2B')!;
      expect(link.url, Uri.parse('http://10.42.0.1:8765/'));
      expect(link.key, 'abc_DEF-123');
      expect(link.name, 'KNX-Box-1A2B');
      expect(link.label, 'KNX-Box-1A2B');
      expect(link.address, '10.42.0.1:8765');
    });

    test('Einrichtungslink vom Aufkleber: WLAN und Passwort, Passwort nie gespeichert', () {
      final link = BoxLink.parse(
        'knxmonitor://box?url=http%3A%2F%2F10.42.0.1%2F&name=KNX-Box-1A2B&ssid=KNX-Box-1A2B'
        '&wifi=wlan%26pass%3D12&pw=box%23pass',
      )!;
      expect(link.ssid, 'KNX-Box-1A2B');
      expect(link.wifi, 'wlan&pass=12');
      expect(link.password, 'box#pass');
      expect(link.needsPairing, isTrue);
      final saved = link.paired('geraetezugang');
      expect(saved.needsPairing, isFalse);
      expect(saved.password, isEmpty);
      expect('${saved.toUri()}', isNot(contains('pw=')));
      expect(BoxLink.parse('${saved.toUri()}'), saved);
      // WPA2-Grenzen
      expect(BoxLink.parse('knxmonitor://box?url=http://10.42.0.1/&ssid=x&wifi=kurz'), isNull);
    });

    test('hin und zurück', () {
      final link = BoxLink(url: Uri.parse('http://knx-box.local:8765'), key: 'k1', name: 'Baustelle Süd');
      expect(BoxLink.parse('${link.toUri()}'), link);
    });

    test('Route, wie Android und iOS sie an Flutter geben', () {
      expect(BoxLink.parse('/?url=http%3A%2F%2F10.42.0.1%3A8765%2F&key=k')?.address, '10.42.0.1:8765');
      expect(BoxLink.parse('/box?url=http://10.42.0.1:8765/')?.key, '');
    });

    test('Kopplungsseite der Box und bloße Adresse', () {
      final page = BoxLink.parse('http://knx-box.local:8765/pair?key=xyz')!;
      expect(page.url, Uri.parse('http://knx-box.local:8765/'));
      expect(page.key, 'xyz');
      expect(BoxLink.parse('10.42.0.1')!.url, Uri.parse('http://10.42.0.1/'));
      expect(BoxLink.parse('knx-box.local:8765')!.url, Uri.parse('http://knx-box.local:8765/'));
      expect(BoxLink.parse(' knx-box.local:80 ')!.url, Uri.parse('http://knx-box.local/'));
    });

    test('bloße Adresse mit Box-Passwort von Hand koppelt wie der Einrichtungslink', () {
      final bare = BoxLink.parse('10.42.0.1')!;
      expect(bare.needsPairing, isFalse);
      final manual = bare.withPassword('box#pass');
      expect(manual.needsPairing, isTrue);
      expect(manual.password, 'box#pass');
      expect(manual.url, Uri.parse('http://10.42.0.1/'));
      expect(bare.withPassword(''), same(bare));
      final paired = BoxLink.parse('knxmonitor://box?url=http://knx-box.local/&key=abc')!;
      expect(paired.withPassword('box#pass'), same(paired));
      final setup = BoxLink.parse('knxmonitor://box?url=http%3A%2F%2F10.42.0.1%2F&pw=vom-aufkleber')!;
      expect(setup.withPassword('anderes').password, 'vom-aufkleber');
    });

    test('lehnt Fremdes ab', () {
      for (final text in [
        '',
        '/',
        'knxmonitor://box',
        'knxmonitor://box?url=ftp://10.42.0.1',
        'knxmonitor://box?url=javascript:alert(1)',
        'knxmonitor://box?url=http://user:pw@10.42.0.1',
        'knxmonitor://box?url=http://10.42.0.1&key=a%20b',
        'mailto:someone@example.com',
      ]) {
        expect(BoxLink.parse(text), isNull, reason: text);
      }
    });
  });

  group('Box-Transport (nativ)', () {
    late HttpServer server;
    final headers = <String?>[];

    setUp(() async {
      headers.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final auth = request.headers.value(HttpHeaders.authorizationHeader);
        headers.add(auth);
        if (auth != 'Bearer geheim') {
          request.response.statusCode = HttpStatus.unauthorized;
          await request.response.close();
          return;
        }
        if (request.uri.path == '/ws/bus') {
          // Not closed on purpose: the test server closes it with the request.
          // ignore: close_sinks
          final ws = await WebSocketTransformer.upgrade(request);
          ws.add([
            0x02,
            ...utf8.encode(jsonEncode({'state': 'connected', 'address': 0x1101})),
          ]);
          ws.listen((m) {
            final data = m as List<int>;
            if (data.first == 0x10) ws.add([0x11, data[1], data[2], 0]); // angenommen
          });
          return;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'path': request.uri.path,
            'config': {'enabled': true},
          }),
        );
        await request.response.close();
      });
    });

    tearDown(() async {
      Addon.box = null;
      await server.close(force: true);
    });

    BoxLink box(String key) => BoxLink(url: Uri.parse('http://127.0.0.1:${server.port}'), key: key);

    test('Status mit Gerätezugang', () async {
      Addon.box = box('geheim');
      expect(Addon.available, isTrue);
      expect(Addon.embedded, isFalse);
      expect((await Addon.status())['path'], '/api/bus');
      expect(headers.single, 'Bearer geheim');
    });

    test('falscher Zugang wird verständlich gemeldet', () async {
      Addon.box = box('falsch');
      await expectLater(Addon.status(), throwsA(isA<AddonException>()));
      await expectLater(Addon.openBus(), throwsA(isA<AddonException>()));
    });

    test('gemeinsamer Tunnel über die Box', () async {
      Addon.box = box('geheim');
      final tunnel = SharedTunnel();
      await tunnel.connect();
      expect(tunnel.state.value, TunnelState.connected);
      expect(tunnel.tunnelAddress, 0x1101);
      expect(tunnel.kind, startsWith('Box'));
      await tunnel.disconnect();
      tunnel.dispose();
    });

    test('nicht erreichbar', () async {
      final port = server.port;
      await server.close(force: true);
      Addon.box = BoxLink(url: Uri.parse('http://127.0.0.1:$port'));
      await expectLater(Addon.status(), throwsA(isA<AddonException>()));
      // tearDown schließt erneut; ein frischer Server verhindert den Fehler dort.
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    });
  });
}
