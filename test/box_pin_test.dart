import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/platform/addon.dart';
import 'package:knx_monitor/platform/addon_io.dart';
import 'package:knx_monitor/platform/box_link.dart';

/// HTTPS zur Box: Die App vertraut nur dem Zertifikat aus dem QR-Code.
void main() {
  late Directory dir;
  late HttpServer server;
  late String fp;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('box_pin');
    final made = await Process.run('bash', ['box/files/tls-cert.sh', dir.path]);
    expect(made.exitCode, 0, reason: '${made.stderr}');
    fp = (made.stdout as String).trim();
    final context = SecurityContext()
      ..useCertificateChain('${dir.path}/cert.pem')
      ..usePrivateKey('${dir.path}/key.pem');
    server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
    server.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final ws = await WebSocketTransformer.upgrade(request);
        ws.add(utf8.encode('hallo'));
        return;
      }
      if (request.uri.path == '/api/box') {
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'box': true}));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  tearDown(() => Addon.box = null);

  BoxLink link(String fingerprint) =>
      BoxLink.parse('knxmonitor://box?url=https%3A%2F%2F127.0.0.1%3A${server.port}%2F&key=zugang&fp=$fingerprint')!;

  test('richtiger Fingerabdruck: Anfragen und WebSocket gehen durch', () async {
    Addon.box = link(fp);
    expect(await Addon.reachable(link(fp)), isTrue);
    expect(await Addon.boxInfo(), {'box': true});
    final socket = await Addon.openBus();
    expect(utf8.decode(await socket.messages.first), 'hallo');
    socket.close();
  });

  test('anderes Zertifikat: keine Verbindung, auch nicht ohne Prüfung im Link', () async {
    final other = 'A' * 43;
    expect(await Addon.reachable(link(other)), isFalse);
    Addon.box = link(other);
    await expectLater(Addon.boxInfo(), throwsA(isA<AddonException>()));
    await expectLater(Addon.openBus(), throwsA(isA<AddonException>()));
    // Ohne Fingerabdruck gilt die normale Prüfung: selbst signiert ist abgelehnt.
    Addon.box = BoxLink(url: Uri.parse('https://127.0.0.1:${server.port}/'), key: 'zugang');
    await expectLater(Addon.boxInfo(), throwsA(isA<AddonException>()));
  });

  test('Fingerabdruck wird wie auf der Box gerechnet', () async {
    final pem = await File('${dir.path}/cert.pem').readAsString();
    final body = pem.replaceAll(RegExp(r'-----[A-Z ]+-----|\s'), '');
    expect(certificateFingerprint(base64.decode(body)), fp);
  });
}
