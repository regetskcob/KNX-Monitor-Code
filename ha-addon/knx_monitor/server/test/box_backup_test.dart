import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:knx_monitor_server/box.dart';
import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

/// Gesamtsicherung der Box (box_backup.dart): Sicherung und Rückweg, Rechte,
/// verschlüsselte Schlüssel, manipulierte Dateien, große Verläufe.
void main() {
  late Directory source;
  late Directory target;

  setUp(() async {
    source = await Directory.systemTemp.createTemp('backup-source');
    target = await Directory.systemTemp.createTemp('backup-target');
    BoxBackup.iterations = 1000;
    BoxBackup.minIterations = 1000;
  });
  tearDown(() async {
    BoxBackup.iterations = 600000;
    BoxBackup.minIterations = 100000;
    BoxBackup.maxBytes = 0xFFFFFFFF;
    BoxBackup.maxEntryBytes = 0xFFFFFFFF;
    BoxBackup.reserveBytes = 256 * 1024 * 1024;
    for (final d in [source, target]) {
      if (await d.exists()) await d.delete(recursive: true);
    }
  });

  Future<void> write(Directory root, String path, Object content) async {
    final file = File('${root.path}/$path');
    await file.parent.create(recursive: true);
    if (content is List<int>) {
      await file.writeAsBytes(content);
    } else {
      await file.writeAsString('$content');
    }
  }

  Future<String?> read(Directory root, String path) async {
    final file = File('${root.path}/$path');
    return await file.exists() ? file.readAsString() : null;
  }

  const groupKey = 'AAECAwQFBgcICQoLDA0ODw==';
  const tunnelPassword = 'tunnel-geheim-123';
  const influxToken = 'influx-token-geheim';
  const smtpPassword = 'smtp-geheim';
  final packedDay = gzip.encode(utf8.encode('{"t":1,"d":2305,"y":2,"x":"01"}\n' * 500));

  /// A box with two installations, server files in the root and everything secret.
  Future<Installations> fill(Directory data) async {
    await write(data, 'catalog.json', '{"project":"Musterhaus"}');
    final installations = await Installations.open(data);
    await installations.create(id: 'baustelle', name: 'Baustelle Nord');
    final a = 'installations/default';
    await write(data, '$a/catalog.json', '{"project":"Musterhaus","groups":[]}');
    await write(data, '$a/history/2026-11-01.ndjson.gz', packedDay);
    await write(data, '$a/history/2026-11-02.ndjson', '{"t":2,"d":2305,"y":2,"x":"00"}\n');
    await write(data, '$a/status/availability-2026-11.ndjson', '{"t":1,"c":true,"n":3}\n');
    await write(data, '$a/watch_rules.json', '{"rules":[{"id":"w1"}]}');
    await write(data, '$a/dali_tests/2026.ndjson', '{"test":"function"}\n');
    await write(data, '$a/home_plan.json', '{"rooms":[]}');
    await write(data, '$a/floor_view_images/abc.jpg.b64', 'AAAA');
    await write(data, '$a/secure_sequence.json', '{"4353":50}');
    await write(
      data,
      '$a/server.json',
      jsonEncode({
        'enabled': true,
        'mode': 'secure',
        'host': '192.168.1.10',
        // Otherwise the recorder's retention (7 days) removes the test days after the restore.
        'retentionDays': 3650,
        'secure': {'userId': 2, 'userPassword': tunnelPassword, 'deviceAuthentication': 'auth-geheim'},
      }),
    );
    // Copies with the same secrets, temporary files and a link must stay out.
    await write(
      data,
      '$a/server.json.bak',
      jsonEncode({
        'secure': {'userPassword': tunnelPassword},
      }),
    );
    await write(data, '$a/catalog.json.1234.tmp', '{}');
    await write(
      data,
      '$a/secure_keys.json',
      jsonEncode({
        'groupKeys': {'2305': groupKey},
      }),
    );
    await write(data, '$a/export.json', jsonEncode({'influxToken': influxToken}));
    await write(data, '$a/report_settings.json', jsonEncode({'smtpPassword': smtpPassword}));
    await Link('${data.path}/$a/recordings').create('/etc');
    await write(data, 'installations/baustelle/catalog.json', '{"project":"Nord"}');
    // The server's own files in the root.
    await write(data, 'access.json', '{"password":{"hash":"x"},"devices":[]}');
    await write(data, 'ha_integration.json', '{"token":"ha-geheim"}');
    await write(data, 'mcp.json', '{"enabled":true,"token":"mcp-geheim"}');
    await write(data, 'restarts.ndjson', '{}\n');
    return installations;
  }

  Future<Uint8List> backupOf(Directory data, {String? password, List<int>? chunks}) async {
    final out = BytesBuilder();
    final secrets = await collectSecrets(data);
    await writeBoxBackup(
      data,
      (bytes) async {
        chunks?.add(bytes.length);
        out.add(bytes);
      },
      serverVersion: 'test',
      key: password == null ? null : await SecretsKey.derive(password),
      secrets: secrets,
      withheld: password == null ? secretKinds(secrets) : const [],
      box: {'name': 'Testbox'},
    );
    return out.takeBytes();
  }

  /// Entries of a zip, unpacked by Dart's own reader for comparison.
  Map<String, List<int>> entriesOf(Uint8List zip) {
    final out = <String, List<int>>{};
    final d = ByteData.sublistView(zip);
    var end = zip.length - 22;
    while (d.getUint32(end, Endian.little) != 0x06054b50) {
      end--;
    }
    var p = d.getUint32(end + 16, Endian.little);
    for (var n = d.getUint16(end + 10, Endian.little); n > 0; n--) {
      final nameLength = d.getUint16(p + 28, Endian.little);
      final name = utf8.decode(zip.sublist(p + 46, p + 46 + nameLength));
      final compressed = d.getUint32(p + 20, Endian.little);
      final offset = d.getUint32(p + 42, Endian.little);
      final start = offset + 30 + d.getUint16(offset + 26, Endian.little) + d.getUint16(offset + 28, Endian.little);
      out[name] = ZLibDecoder(raw: true).convert(zip.sublist(start, start + compressed));
      p += 46 + nameLength + d.getUint16(p + 30, Endian.little) + d.getUint16(p + 32, Endian.little);
    }
    return out;
  }

  /// A zip with [entries] in this order, written again by the server's zip writer.
  Future<Uint8List> zipFrom(Map<String, List<int>> entries) async {
    final out = BytesBuilder();
    final zip = ZipStream((bytes) async => out.add(bytes));
    for (final MapEntry(:key, :value) in entries.entries) {
      await zip.addStream(key, DateTime(2026, 11, 11), Stream.value(value));
    }
    await zip.close();
    return out.takeBytes();
  }

  group('Sicherung schreiben', () {
    test('enthält alle Anlagen, aber keine Serverdateien, Kopien und Geheimnisse im Klartext', () async {
      await fill(source);
      final zip = await backupOf(source, password: 'ein langes passwort');
      final entries = entriesOf(zip);
      expect(entries.keys, containsAll(['manifest.json', 'secrets.json', 'installations.json']));
      expect(entries.keys.where((k) => k.startsWith('installations/default/')).toSet(), {
        'installations/default/catalog.json',
        'installations/default/history/2026-11-01.ndjson.gz',
        'installations/default/history/2026-11-02.ndjson',
        'installations/default/status/availability-2026-11.ndjson',
        'installations/default/watch_rules.json',
        'installations/default/dali_tests/2026.ndjson',
        'installations/default/home_plan.json',
        'installations/default/floor_view_images/abc.jpg.b64',
        'installations/default/server.json',
      });
      expect(entries.keys, contains('installations/baustelle/catalog.json'));
      // Packed days go in as they are.
      expect(entries['installations/default/history/2026-11-01.ndjson.gz'], packedDay);
      final plain = latin1.decode(zip);
      for (final secret in [
        groupKey,
        tunnelPassword,
        'auth-geheim',
        influxToken,
        smtpPassword,
        'ha-geheim',
        'mcp-geheim',
      ]) {
        expect(plain.contains(secret), isFalse, reason: secret);
      }
      final server = jsonDecode(utf8.decode(entries['installations/default/server.json']!)) as Map;
      expect(server['host'], '192.168.1.10');
      expect(server['secure'], {'userId': 2});
      final manifest = jsonDecode(utf8.decode(entries['manifest.json']!)) as Map;
      expect(manifest, containsPair('format', 'busclear-box-backup'));
      expect(manifest, containsPair('version', 1));
      expect(manifest, containsPair('secrets', true));
      expect(manifest['box'], containsPair('name', 'Testbox'));
      expect((manifest['installations'] as List).map((i) => (i as Map)['id']), ['default', 'baustelle']);
    });

    test('ohne Passwort bleiben die Schlüssel draußen, das Manifest sagt welche', () async {
      await fill(source);
      final entries = entriesOf(await backupOf(source));
      expect(entries.keys, isNot(contains('secrets.json')));
      final manifest = jsonDecode(utf8.decode(entries['manifest.json']!)) as Map;
      expect(manifest['secrets'], false);
      expect(manifest['withheld'], ['keyring', 'ipSecure', 'dataExport', 'report']);
    });

    test('großer Verlauf geht in kleinen Stücken hinaus, nicht am Stück', () async {
      final installations = await Installations.open(source);
      final random = Random(1);
      final line = StringBuffer();
      final day = File('${installations.root.path}/history/2026-11-03.ndjson');
      await day.parent.create(recursive: true);
      final sink = day.openWrite();
      for (var i = 0; i < 200000; i++) {
        line
          ..clear()
          ..write('{"t":$i,"s":${random.nextInt(65535)},"d":${random.nextInt(65535)},"y":2,"x":"');
        line.write(random.nextInt(1 << 30).toRadixString(16));
        sink.writeln('$line"}');
      }
      await sink.close();
      final size = await day.length();
      expect(size, greaterThan(10 * 1024 * 1024));
      final chunks = <int>[];
      final zip = await backupOf(source, chunks: chunks);
      expect(chunks.reduce(max), lessThan(1024 * 1024));
      expect(entriesOf(zip)['installations/default/history/2026-11-03.ndjson'], await day.readAsBytes());
    });
  });

  group('Server', () {
    late InstallationService service;
    late BoxBackupService backups;
    late HttpServer server;
    final client = HttpClient();
    var readOnly = false;
    var current = 'box-passwort';

    Future<void> startOn(
      Directory data, {
      bool box = true,
      Future<bool> Function(HttpRequest request, Object? current)? confirm,
    }) async {
      service = InstallationService(
        await Installations.open(data),
        (root, installation) => BusService(root, describe: (_, _) async => null, installation: installation),
      );
      await service.start();
      backups = BoxBackupService(
        data,
        service,
        serverVersion: 'test',
        readOnly: readOnly,
        confirmPassword: confirm ?? (box ? (_, given) async => given == current : null),
      );
      await backups.start();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (await backups.serve(request, admin: request.headers.value('x-admin') != '0')) return;
        request.response.statusCode = 404;
        await request.response.close();
      });
    }

    tearDown(() async {
      readOnly = false;
      await service.shutdown();
      await server.close(force: true);
    });

    Future<(int, List<int>)> send(
      String path, {
      String method = 'GET',
      Object? json,
      List<int>? body,
      bool admin = true,
    }) async {
      final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:${server.port}$path'));
      if (!admin) request.headers.set('x-admin', '0');
      if (json != null) request.write(jsonEncode(json));
      if (body != null) request.add(body);
      final response = await request.close();
      final builder = BytesBuilder();
      await response.forEach(builder.add);
      return (response.statusCode, builder.takeBytes());
    }

    Future<(int, Object?)> sendJson(
      String path, {
      String method = 'GET',
      Object? json,
      List<int>? body,
      bool admin = true,
    }) async {
      final (status, bytes) = await send(path, method: method, json: json, body: body, admin: admin);
      final text = utf8.decode(bytes);
      try {
        return (status, text.isEmpty ? null : jsonDecode(text));
      } on FormatException {
        return (status, text);
      }
    }

    Future<Map<String, Object?>> upload(List<int> zip) async {
      final (status, summary) = await sendJson('/api/backup/restore', method: 'PUT', body: zip);
      expect(status, 200, reason: '$summary');
      return (summary! as Map).cast<String, Object?>();
    }

    test('Roundtrip: Sicherung herunterladen, auf neuer Box wiederherstellen', () async {
      await fill(source);
      await startOn(source);
      var (status, ticket) = await sendJson('/api/backup', method: 'POST', json: {'password': 'ein langes passwort'});
      expect(status, 200);
      expect(ticket, containsPair('secrets', true));
      final id = (ticket! as Map)['ticket'] as String;
      expect((await send('/api/backup/download?ticket=$id&check=1')).$1, 204);
      final (downloaded, zip) = await send('/api/backup/download?ticket=$id');
      expect(downloaded, 200);
      // A ticket holds for one download.
      expect((await send('/api/backup/download?ticket=$id')).$1, 404);
      await service.shutdown();
      await server.close(force: true);

      // A freshly flashed box: its own password, nothing else.
      await write(target, 'access.json', '{"neu":true}');
      await startOn(target);
      final boxKey = service.installations.boxKey;
      final summary = await upload(zip);
      expect(summary['secrets'], true);
      expect((summary['installations']! as List).map((i) => (i as Map)['name']), ['Musterhaus', 'Baustelle Nord']);
      // Nothing changed until confirmed.
      expect(service.installations.list.map((i) => i.id), ['default']);
      (status, _) = await sendJson(
        '/api/backup/restore/apply',
        method: 'POST',
        json: {'stage': summary['stage'], 'password': 'ein langes passwort', 'current': current},
      );
      expect(status, 200);
      expect(service.installations.list.map((i) => i.id), ['default', 'baustelle']);
      // The box keeps its own key; the installations keep theirs.
      expect(service.installations.boxKey, boxKey);
      final a = 'installations/default';
      expect(await File('${target.path}/$a/history/2026-11-01.ndjson.gz').readAsBytes(), packedDay);
      expect(await read(target, '$a/dali_tests/2026.ndjson'), '{"test":"function"}\n');
      expect(jsonDecode((await read(target, '$a/secure_keys.json'))!), {
        'groupKeys': {'2305': groupKey},
      });
      expect(jsonDecode((await read(target, '$a/export.json'))!), {'influxToken': influxToken});
      // Sequence numbers come back only from the encrypted part.
      expect(jsonDecode((await read(target, '$a/secure_sequence.json'))!), {'4353': 50});
      final serverJson = jsonDecode((await read(target, '$a/server.json'))!) as Map;
      expect(serverJson['secure'], {
        'userId': 2,
        'userPassword': tunnelPassword,
        'deviceAuthentication': 'auth-geheim',
      });
      // Server files of the box stay as they were and nothing of the old box came along.
      expect(await read(target, 'access.json'), '{"neu":true}');
      expect(await read(target, 'ha_integration.json'), isNull);
      expect(await read(target, 'mcp.json'), isNull);
      expect(await Link('${target.path}/$a/recordings').exists(), isFalse);
      // The previous state is kept.
      final (_, state) = await sendJson('/api/backup');
      final previous = ((state! as Map)['previous'] as List).single as Map;
      expect(
        await Directory('${target.path}/restore-previous/${previous['name']}/installations/default').exists(),
        isTrue,
      );
      expect(await Directory('${target.path}/restore-staging').exists(), isFalse);
      // It can be downloaded and deleted.
      final (_, again) = await sendJson('/api/backup', method: 'POST', json: {'previous': previous['name']});
      expect((again! as Map)['fileName'], 'busclear-box-vorher-${previous['name']}.zip');
      expect((await send('/api/backup/previous/${previous['name']}', method: 'DELETE')).$1, 204);
      expect(await Directory('${target.path}/restore-previous/${previous['name']}').exists(), isFalse);
    });

    test('ohne Passwort: alles außer Schlüsseln, nur nach ausdrücklicher Wahl', () async {
      await fill(source);
      final zip = await backupOf(source, password: 'ein langes passwort');
      await startOn(target);
      final summary = await upload(zip);
      var (status, answer) = await sendJson(
        '/api/backup/restore/apply',
        method: 'POST',
        json: {'stage': summary['stage'], 'current': current},
      );
      expect(status, 422);
      expect(answer, containsPair('problem', 'passwordMissing'));
      (status, answer) = await sendJson(
        '/api/backup/restore/apply',
        method: 'POST',
        json: {'stage': summary['stage'], 'password': 'falsches passwort!', 'current': current},
      );
      expect(status, 422);
      expect(answer, containsPair('problem', 'backupPassword'));
      expect(service.installations.list.map((i) => i.id), ['default']);
      (status, answer) = await sendJson(
        '/api/backup/restore/apply',
        method: 'POST',
        json: {'stage': summary['stage'], 'withoutSecrets': true, 'current': current},
      );
      expect(status, 200);
      expect(answer, containsPair('secretsSkipped', true));
      final a = 'installations/default';
      expect(await read(target, '$a/catalog.json'), isNotNull);
      expect(await read(target, '$a/secure_keys.json'), isNull);
      expect(await read(target, '$a/export.json'), isNull);
      expect((jsonDecode((await read(target, '$a/server.json'))!) as Map)['secure'], {'userId': 2});
    });

    test('Sequenznummern von KNX Data Secure sinken nicht', () async {
      await fill(source);
      final zip = await backupOf(source);
      await write(target, 'catalog.json', '{"project":"Musterhaus"}');
      await write(
        target,
        'installations.json',
        jsonEncode({
          'version': 1,
          'active': 'default',
          'list': [
            {'id': 'default', 'name': 'x', 'created': 0},
          ],
        }),
      );
      await write(target, 'installations/default/secure_sequence.json', '{"4353":100,"4354":7}');
      await startOn(target);
      final summary = await upload(zip);
      final (status, _) = await sendJson(
        '/api/backup/restore/apply',
        method: 'POST',
        json: {'stage': summary['stage'], 'current': current},
      );
      expect(status, 200);
      expect(jsonDecode((await read(target, 'installations/default/secure_sequence.json'))!), {'4353': 100, '4354': 7});
    });

    test('Rechte: nur Admin, Nur-Lesen sperrt Wiederherstellen, Box-Passwort nötig', () async {
      await fill(source);
      final zip = await backupOf(source);
      await startOn(target);
      for (final (method, path) in [
        ('GET', '/api/backup'),
        ('POST', '/api/backup'),
        ('GET', '/api/backup/download?ticket=x'),
        ('POST', '/api/backup/form'),
        ('PUT', '/api/backup/restore'),
        ('POST', '/api/backup/restore/apply'),
        ('DELETE', '/api/backup/previous/20261111-120000'),
      ]) {
        final (status, text) = await sendJson(path, method: method, admin: false);
        expect(status, 403, reason: '$method $path');
        expect(text, 'Nur mit dem Box-Passwort.');
      }
      final summary = await upload(zip);
      var (status, answer) = await sendJson(
        '/api/backup/restore/apply',
        method: 'POST',
        json: {'stage': summary['stage'], 'current': 'falsch'},
      );
      expect(status, 403);
      expect(answer, 'Das aktuelle Passwort stimmt nicht.');
      (status, answer) = await sendJson(
        '/api/backup/restore/apply',
        method: 'POST',
        json: {'stage': 'anders', 'current': current},
      );
      expect(status, 409);
      expect(service.installations.list.map((i) => i.id), ['default']);
      await service.shutdown();
      await server.close(force: true);

      readOnly = true;
      await startOn(target);
      (status, answer) = await sendJson('/api/backup/restore', method: 'PUT', body: zip);
      expect(status, 409);
      expect(answer, containsPair('problem', 'readOnly'));
      // Backing up stays possible.
      expect((await sendJson('/api/backup', method: 'POST', json: {})).$1, 200);
    });

    test('zu kurzes Passwort wird abgelehnt', () async {
      await startOn(target);
      final (status, answer) = await sendJson('/api/backup', method: 'POST', json: {'password': 'kurz'});
      expect(status, 400);
      expect(answer, containsPair('problem', 'passwordShort'));
    });

    test('Formular im Browser liefert die Datei direkt', () async {
      await fill(source);
      await startOn(source);
      final (status, zip) = await send(
        '/api/backup/form',
        method: 'POST',
        body: utf8.encode('password=ein+langes+passwort&password2=ein+langes+passwort'),
      );
      expect(status, 200);
      expect(entriesOf(Uint8List.fromList(zip)).keys, contains('secrets.json'));
      final request = await client.postUrl(Uri.parse('http://127.0.0.1:${server.port}/api/backup/form'));
      request
        ..followRedirects = false
        ..write('password=ein+langes+passwort&password2=x');
      final response = await request.close();
      await response.drain<void>();
      // Back to the page with a notice, not JSON in the browser.
      expect(response.statusCode, 303);
      expect(response.headers.value(HttpHeaders.locationHeader), '/pair?backup=mismatch');
      expect(BoxAccess.backupNotice('mismatch'), contains('stimmen nicht überein'));
    });
  });

  group('Review 11.11.', () {
    late InstallationService service;
    late BoxBackupService backups;
    late HttpServer server;
    final client = HttpClient();
    const current = 'box-passwort';

    Future<void> startOn(Directory data, {Future<bool> Function(HttpRequest, Object?)? confirm}) async {
      service = InstallationService(
        await Installations.open(data),
        (root, installation) => BusService(root, describe: (_, _) async => null, installation: installation),
      );
      await service.start();
      backups = BoxBackupService(
        data,
        service,
        serverVersion: 'test',
        confirmPassword: confirm ?? (_, given) async => given == current,
      );
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (await backups.serve(request, admin: true)) return;
        request.response.statusCode = 404;
        await request.response.close();
      });
    }

    tearDown(() async {
      await service.shutdown();
      await server.close(force: true);
    });

    Future<(int, Object?)> call(String path, {String method = 'GET', Object? json, List<int>? body}) async {
      final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:${server.port}$path'));
      if (json != null) request.write(jsonEncode(json));
      if (body != null) request.add(body);
      final response = await request.close();
      final text = await utf8.decodeStream(response);
      try {
        return (response.statusCode, text.isEmpty ? null : jsonDecode(text));
      } on FormatException {
        return (response.statusCode, text);
      }
    }

    Future<String> stage(List<int> zip) async {
      final (status, summary) = await call('/api/backup/restore', method: 'PUT', body: zip);
      expect(status, 200, reason: '$summary');
      return (summary! as Map)['stage']! as String;
    }

    test('M1: während des Wiederherstellens kein zweites Hochladen und kein Verwerfen', () async {
      await fill(source);
      final zip = await backupOf(source, password: 'ein langes passwort');
      final gate = Completer<void>();
      await startOn(
        target,
        confirm: (_, given) async {
          await gate.future;
          return given == current;
        },
      );
      final id = await stage(zip);
      final applying = call(
        '/api/backup/restore/apply',
        method: 'POST',
        json: {'stage': id, 'password': 'ein langes passwort', 'current': current},
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final other = await zipFrom({
        'manifest.json': utf8.encode(jsonEncode({'format': 'busclear-box-backup', 'version': 1})),
        'installations.json': utf8.encode(
          jsonEncode({
            'active': 'x',
            'list': [
              {'id': 'x', 'name': 'Fremd', 'created': 0},
            ],
          }),
        ),
      });
      expect((await call('/api/backup/restore', method: 'PUT', body: other)).$1, 409);
      expect((await call('/api/backup/restore', method: 'DELETE')).$1, 409);
      gate.complete();
      final (status, answer) = await applying;
      expect(status, 200, reason: '$answer');
      expect(service.installations.list.map((i) => i.name), ['Musterhaus', 'Baustelle Nord']);
      expect(await read(target, 'installations/default/catalog.json'), contains('Musterhaus'));
    });

    test('M3: veränderter Klartextteil wird mit Passwort abgewiesen, unveränderter angenommen', () async {
      await fill(source);
      final entries = entriesOf(await backupOf(source, password: 'ein langes passwort'));
      expect(entries.keys.last, 'secrets.json');
      await startOn(target);
      Future<(int, Object?)> restore(Map<String, List<int>> changed) async => call(
        '/api/backup/restore/apply',
        method: 'POST',
        json: {'stage': await stage(await zipFrom(changed)), 'password': 'ein langes passwort', 'current': current},
      );

      // server.json pointed at the attacker, original secrets.json moved over.
      final server = jsonDecode(utf8.decode(entries['installations/default/server.json']!)) as Map;
      var (status, answer) = await restore({
        ...entries,
        'installations/default/server.json': utf8.encode(jsonEncode({...server, 'host': '203.0.113.9'})),
      });
      expect(status, 422);
      expect(answer, containsPair('problem', 'tampered'));
      // An added file, a renamed installation, a changed history day.
      (status, answer) = await restore({
        for (final e in entries.entries)
          if (e.key != 'secrets.json') e.key: e.value,
        'installations/default/learned.json': utf8.encode('{}'),
        'secrets.json': entries['secrets.json']!,
      });
      expect(answer, containsPair('problem', 'tampered'));
      final index = utf8.decode(entries['installations.json']!).replaceFirst('Musterhaus', 'Musterhauz');
      (status, answer) = await restore({...entries, 'installations.json': utf8.encode(index)});
      expect(answer, containsPair('problem', 'tampered'));
      final day = 'installations/default/history/2026-11-02.ndjson';
      (status, answer) = await restore({...entries, day: utf8.encode('{"t":3,"d":2305,"y":2,"x":"01"}\n')});
      expect(answer, containsPair('problem', 'tampered'));
      expect(await read(target, 'installations/default/secure_keys.json'), isNull);
      // Unchanged, only packed again: restored.
      (status, answer) = await restore(entries);
      expect(status, 200, reason: '$answer');
      expect(jsonDecode((await read(target, 'installations/default/server.json'))!)['host'], '192.168.1.10');
    });

    test('N2/N3: Folgenummern nur aus dem verschlüsselten Teil, höchste aus Keyring und vorigem Stand', () async {
      await fill(source);
      await write(source, 'installations/default/secure_sequence.json', jsonEncode({'4353': 50, '4354': 1 << 60}));
      final key = (jsonDecode((await read(source, 'installations.json'))!)['list'] as List).first['key'];
      final zip = await backupOf(source, password: 'ein langes passwort');
      // The previous state knows the installation under another id, by its key.
      await write(
        target,
        'installations.json',
        jsonEncode({
          'version': 1,
          'active': 'alt',
          'list': [
            {'id': 'alt', 'name': 'Alt', 'created': 0, 'key': key},
          ],
        }),
      );
      await write(
        target,
        'installations/alt/secure_keys.json',
        jsonEncode({
          'sequence': {'4353': 300},
        }),
      );
      await write(target, 'installations/alt/secure_sequence.json', jsonEncode({'4355': 9}));
      await startOn(target);
      final (status, _) = await call(
        '/api/backup/restore/apply',
        method: 'POST',
        json: {'stage': await stage(zip), 'password': 'ein langes passwort', 'current': current},
      );
      expect(status, 200);
      expect(jsonDecode((await read(target, 'installations/default/secure_sequence.json'))!), {'4353': 300, '4355': 9});
    });

    test('Stromausfall mitten im Austausch: beim Start kommt der vorige Stand zurück', () async {
      await write(
        target,
        'restore-previous/20261111-120000/installations.json',
        '{"version":1,"active":"a","list":[{"id":"a","name":"Alt","created":0}]}',
      );
      await write(target, 'restore-previous/20261111-120000/installations/a/catalog.json', '{"project":"Alt"}');
      await write(target, 'installations/neu/catalog.json', '{"project":"halb"}');
      await write(target, 'restore-swap.json', '{"aside":"20261111-120000"}');
      await BoxBackupService.recover(target);
      expect(await read(target, 'installations/a/catalog.json'), '{"project":"Alt"}');
      expect(await read(target, 'installations/neu/catalog.json'), isNull);
      expect(await read(target, 'installations.json'), contains('Alt'));
      expect(await File('${target.path}/restore-swap.json').exists(), isFalse);
      expect(await Directory('${target.path}/restore-previous/20261111-120000').exists(), isFalse);
      // Without a journal nothing happens.
      await BoxBackupService.recover(target);
      expect(await read(target, 'installations/a/catalog.json'), '{"project":"Alt"}');
    });

    test('N6: höchstens eine Schlüsselableitung gleichzeitig', () async {
      BoxBackup.iterations = 300000;
      final first = SecretsKey.derive('ein langes passwort');
      await expectLater(
        SecretsKey.derive('ein langes passwort'),
        throwsA(isA<BoxBackupException>().having((e) => e.status, 'status', 429)),
      );
      await first;
      BoxBackup.iterations = 1000;
      await SecretsKey.derive('ein langes passwort');
    });
  });

  group('Manipulierte Dateien', () {
    /// A zip with [files] (name → content), written by the server's own zip writer.
    Future<Uint8List> zipOf(Map<String, String> files) async {
      final out = BytesBuilder();
      final zip = ZipStream((bytes) async => out.add(bytes));
      for (final MapEntry(:key, :value) in files.entries) {
        await zip.add(key, DateTime(2026, 11, 11), (w) => w(value));
      }
      await zip.close();
      return out.takeBytes();
    }

    Map<String, String> valid() => {
      'manifest.json': jsonEncode({'format': 'busclear-box-backup', 'version': 1}),
      'installations.json': jsonEncode({
        'active': 'a',
        'list': [
          {'id': 'a', 'name': 'A', 'created': 0},
        ],
      }),
      'installations/a/catalog.json': '{"project":"A"}',
    };

    Future<Object> refusal(Uint8List zip, {int? free}) async {
      final file = File('${source.path}/upload.zip');
      await file.writeAsBytes(zip);
      final tree = Directory('${source.path}/tree');
      try {
        await unpackBoxBackup(file, tree, free: free ?? 1 << 40);
        return 'angenommen';
      } on BoxBackupException catch (e) {
        return e;
      }
    }

    test('eine gültige Datei wird entpackt', () async {
      final file = File('${source.path}/upload.zip');
      await file.writeAsBytes(await zipOf(valid()));
      final result = await unpackBoxBackup(file, Directory('${source.path}/tree'), free: 1 << 40);
      expect(result.list.single['id'], 'a');
      expect(await read(source, 'tree/installations/a/catalog.json'), '{"project":"A"}');
    });

    test('IP-Secure-Passwörter aus dem Klartextteil werden verworfen', () async {
      final file = File('${source.path}/upload.zip');
      await file.writeAsBytes(
        await zipOf({
          ...valid(),
          'installations/a/server.json': jsonEncode({
            'host': '10.0.0.2',
            'secure': {'userId': 2, 'userPassword': 'klartext', 'deviceAuthentication': 'auth'},
          }),
        }),
      );
      await unpackBoxBackup(file, Directory('${source.path}/tree'), free: 1 << 40);
      final server = jsonDecode((await read(source, 'tree/installations/a/server.json'))!) as Map;
      expect(server['host'], '10.0.0.2');
      expect(server['secure'], {'userId': 2});
    });

    for (final name in [
      'installations/a/../../access.json',
      '../access.json',
      '/etc/passwd',
      'access.json',
      'installations.json.bak',
      'installations/a/secure_keys.json',
      'installations/a/Secure_Keys.json',
      'installations/a/server.json.bak',
      'installations/a/export.json',
      'installations/a/report_settings.json',
      'installations/a/secure_sequence.json',
      'installations/a/team/members.json',
      'installations/a/cloud_sync/state.json',
      'installations/a/history/../../../x',
      'installations/a/.hidden',
      r'installations/a/history\x',
      'installations/a/unbekannt.json',
      'installations/../x/catalog.json',
      'restore-previous/x/installations.json',
    ]) {
      test('Pfad abgewiesen: $name', () async {
        final refused = await refusal(await zipOf({...valid(), name: 'x'}));
        expect(refused, isA<BoxBackupException>());
        expect(await File('${source.path}/access.json').exists(), isFalse);
        expect(await File('/etc/passwd').readAsString(), isNot('x'));
      });
    }

    test('N1: riesiges Zentralverzeichnis wird nicht gelesen', () async {
      final file = File('${source.path}/upload.zip');
      final raf = await file.open(mode: FileMode.write);
      const size = 40 * 1024 * 1024;
      await raf.setPosition(size);
      final end = ByteData(22)
        ..setUint32(0, 0x06054b50, Endian.little)
        ..setUint16(8, 1, Endian.little)
        ..setUint16(10, 1, Endian.little)
        ..setUint32(12, size, Endian.little)
        ..setUint32(16, 0, Endian.little);
      await raf.writeFrom(end.buffer.asUint8List());
      await raf.close();
      await expectLater(
        unpackBoxBackup(file, Directory('${source.path}/tree'), free: 1 << 40),
        throwsA(isA<BoxBackupException>()),
      );
    });

    test('Dateien einer Installation, die nicht in der Liste steht', () async {
      expect(await refusal(await zipOf({...valid(), 'installations/b/catalog.json': '{}'})), isA<BoxBackupException>());
    });

    test('doppelter Name, auch in anderer Schreibweise', () async {
      final files = valid();
      final zip = await zipOf({...files, 'installations/a/Catalog.json': '{}'});
      expect(await refusal(zip), isA<BoxBackupException>());
    });

    test('Entpack-Bombe: mehr Daten als angegeben', () async {
      final zip = await zipOf({...valid(), 'installations/a/learned.json': '0' * (4 * 1024 * 1024)});
      // Declared size in the central directory: 10 bytes.
      final d = ByteData.sublistView(zip);
      var end = zip.length - 22;
      while (d.getUint32(end, Endian.little) != 0x06054b50) {
        end--;
      }
      var p = d.getUint32(end + 16, Endian.little);
      while (true) {
        final n = d.getUint16(p + 28, Endian.little);
        if (utf8.decode(zip.sublist(p + 46, p + 46 + n)) == 'installations/a/learned.json') break;
        p += 46 + n + d.getUint16(p + 30, Endian.little) + d.getUint16(p + 32, Endian.little);
      }
      d.setUint32(p + 24, 10, Endian.little);
      expect(await refusal(zip), isA<BoxBackupException>());
      final partial = File('${source.path}/tree/installations/a/learned.json');
      expect(!await partial.exists() || await partial.length() <= 10, isTrue);
    });

    test('Größengrenzen und freier Speicher', () async {
      final zip = await zipOf({...valid(), 'installations/a/learned.json': '0' * 100000});
      BoxBackup.maxEntryBytes = 50000;
      expect(await refusal(zip), isA<BoxBackupException>().having((e) => e.problem, 'problem', 'tooLarge'));
      BoxBackup.maxEntryBytes = 0xFFFFFFFF;
      BoxBackup.maxBytes = 50000;
      expect(await refusal(zip), isA<BoxBackupException>().having((e) => e.problem, 'problem', 'tooLarge'));
      BoxBackup.maxBytes = 0xFFFFFFFF;
      BoxBackup.reserveBytes = 0;
      expect(await refusal(zip, free: 1000), isA<BoxBackupException>().having((e) => e.problem, 'problem', 'space'));
    });

    test('neuere Version, fremdes Format, ohne Installation, keine ZIP-Datei', () async {
      expect(
        await refusal(
          await zipOf({
            ...valid(),
            'manifest.json': jsonEncode({'format': 'busclear-box-backup', 'version': 2}),
          }),
        ),
        isA<BoxBackupException>().having((e) => e.problem, 'problem', 'newer'),
      );
      expect(
        await refusal(
          await zipOf({
            ...valid(),
            'manifest.json': jsonEncode({'format': 'knx-monitor-backup', 'version': 1}),
          }),
        ),
        isA<BoxBackupException>(),
      );
      expect(await refusal(await zipOf({...valid()}..remove('manifest.json'))), isA<BoxBackupException>());
      expect(
        await refusal(
          await zipOf(
            {...valid(), 'installations.json': '{"list":[{"id":"../x","name":"x"}]}'}
              ..remove('installations/a/catalog.json'),
          ),
        ),
        isA<BoxBackupException>(),
      );
      expect(
        await refusal(Uint8List.fromList(utf8.encode('{"format":"knx-monitor-backup"}'))),
        isA<BoxBackupException>(),
      );
      expect(await refusal(Uint8List(0)), isA<BoxBackupException>());
    });

    test('kaputte Prüfsumme', () async {
      final zip = await zipOf(valid());
      final d = ByteData.sublistView(zip);
      var end = zip.length - 22;
      while (d.getUint32(end, Endian.little) != 0x06054b50) {
        end--;
      }
      final p = d.getUint32(end + 16, Endian.little);
      d.setUint32(p + 16, d.getUint32(p + 16, Endian.little) ^ 1, Endian.little);
      expect(await refusal(zip), isA<BoxBackupException>());
    });

    test('verschlüsselter Teil mit zu wenigen Runden oder kaputt', () async {
      final sealed = await sealSecrets({
        'a': {'secure_keys.json': {}},
      }, 'ein langes passwort');
      BoxBackup.minIterations = 5000;
      expect(await refusal(await zipOf({...valid(), 'secrets.json': jsonEncode(sealed)})), isA<BoxBackupException>());
      BoxBackup.minIterations = 1000;
      expect(
        await refusal(
          await zipOf({
            ...valid(),
            'secrets.json': jsonEncode({...sealed, 'data': 'kein base64!'}),
          }),
        ),
        isA<BoxBackupException>(),
      );
      expect(
        await refusal(await zipOf({...valid(), 'secrets.json': jsonEncode(sealed)})),
        isNot(isA<BoxBackupException>()),
      );
    });

    test('Schlüssel nur für Installationen der Sicherung, nur bekannte Arten', () async {
      final sealed = await sealSecrets({
        'a': {
          'secure_keys.json': {'groupKeys': <String, Object?>{}},
          'access.json': {'x': 1},
        },
        'b': {
          'secure_keys.json': {'groupKeys': <String, Object?>{}},
        },
      }, 'ein langes passwort');
      final opened = await openSecrets(sealed, 'ein langes passwort', {'a'});
      expect(opened!.installations, {
        'a': {
          'secure_keys.json': {'groupKeys': <String, Object?>{}},
        },
      });
      expect(await openSecrets(sealed, 'falsch falsch falsch', {'a'}), isNull);
      final tampered = {...sealed, 'data': base64Encode(base64Decode(sealed['data']! as String)..[0] ^= 1)};
      expect(await openSecrets(tampered, 'ein langes passwort', {'a'}), isNull);
    });
  });

  test('Integrität: jeder Eintrag mit SHA-256, auch der Verlauf; ältere Dateien ohne bleiben lesbar', () {
    const day = 'installations/a/history/2026-11-01.ndjson';
    UnpackedBoxBackup backup(String sha) => UnpackedBoxBackup(
      manifest: const {},
      active: 'a',
      list: const [],
      secrets: null,
      files: 1,
      bytes: 10,
      entries: {'manifest.json': (size: 2, crc: 1, sha256: 'aa'), day: (size: 10, crc: 7, sha256: sha)},
    );
    List<Object?> list(Object? daySha, {Object? manifestSha = 'aa'}) => [
      ['manifest.json', 2, 1, manifestSha],
      [day, 10, 7, daySha],
    ];
    verifyIntegrity(backup('bb'), list('bb'));
    // Same size and CRC-32, different content: only the SHA-256 tells.
    expect(() => verifyIntegrity(backup('cc'), list('bb')), throwsA(isA<BoxBackupException>()));
    // A development build before every entry got its hash: history without one is accepted,
    // anything else without one is not.
    verifyIntegrity(backup('cc'), list(null));
    expect(() => verifyIntegrity(backup('bb'), list('bb', manifestSha: null)), throwsA(isA<BoxBackupException>()));
  });

  test('PBKDF2-HMAC-SHA256: bekannte Testvektoren', () {
    String hex(List<int> b) => [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
    final p = utf8.encode('password'), salt = utf8.encode('salt');
    expect(hex(pbkdf2Sha256(p, salt, 1)), '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
    expect(hex(pbkdf2Sha256(p, salt, 2)), 'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
    expect(hex(pbkdf2Sha256(p, salt, 4096)), 'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a');
  });

  test('backupCarries: Positivliste der Pfade', () {
    expect(backupCarries('catalog.json'), isTrue);
    expect(backupCarries('history/2026-11-01.ndjson.gz'), isTrue);
    expect(backupCarries('dali_tests/2026.ndjson'), isTrue);
    expect(backupCarries('server.json'), isTrue);
    for (final no in [
      'secure_keys.json',
      'SECURE_KEYS.json',
      'secure_keys.json.bak',
      'server.json.bak',
      'export.json',
      'access.json',
      'catalog.json.1.tmp',
      'history/x.ndjson.prev',
      'exports/secure_keys.json',
      'secure_sequence.json',
      'team/members.json',
      'cloud_sync/state.json',
      '../catalog.json',
      'history/.x',
      'a/b/c/d/e/f/g/h/i',
    ]) {
      expect(backupCarries(no), isFalse, reason: no);
    }
  });
}
