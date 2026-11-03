import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

/// Ziele von Bericht und Export: keine Cloud-Metadaten über den Server.
void main() {
  test('Link-Local und Metadaten werden schon beim Speichern abgelehnt', () {
    for (final url in [
      'http://169.254.169.254/latest/meta-data/',
      'http://169.254.0.1:8086',
      'https://[fe80::1]/',
      'http://[::ffff:169.254.169.254]/',
      'http://[fd00:ec2::254]/',
      'http://0.0.0.0:8086',
      'http://224.0.0.1/',
      'http://255.255.255.255/',
      'http://[::]/',
    ]) {
      expect(parseOutboundTarget(url), isNull, reason: url);
    }
  });

  test('Heimnetz, Loopback und Internet bleiben erlaubt', () {
    for (final url in [
      'http://192.168.1.10:8086',
      'http://10.0.0.5:8086',
      'http://172.17.0.2:8086',
      'http://127.0.0.1:8086',
      'http://[::1]:8086',
      'https://ntfy.sh',
      'http://influx.local:8086',
    ]) {
      expect(parseOutboundTarget(url), isNotNull, reason: url);
    }
  });

  test('Name, der auf eine verbotene Adresse zeigt: geht nicht hinaus', () async {
    // Namen prüft dieselbe Stelle; hier die Adresse direkt, weil sich DNS im Test
    // nicht fälschen lässt.
    final result = await postOutbound(Uri.parse('http://169.254.169.254/'), body: const []);
    expect(result.ok, isFalse);
    expect(result.code, 'blocked');
  });

  test('erlaubtes Ziel bekommt die Anfrage weiterhin', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((r) async {
      await r.drain<void>();
      await r.response.close();
    });
    final result = await postOutbound(Uri.parse('http://localhost:${server.port}/'), body: const [1]);
    expect(result.ok, isTrue);
  });

  test('Bericht und Export nehmen verbotene Ziele nicht an', () async {
    final data = await Directory.systemTemp.createTemp('outbound');
    addTearDown(() => data.delete(recursive: true));
    final bus = BusService(data);
    await expectLater(
      bus.exporter.update({'influx': true, 'influxUrl': 'http://169.254.169.254/'}),
      throwsA(isA<FormatException>()),
    );
  });
}
