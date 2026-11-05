import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/secure/keyring_store.dart';
import 'package:knx_monitor/model/box_keyring_consent.dart';
import 'package:knx_monitor/model/full_backup.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/platform/addon.dart';
import 'package:knx_monitor/platform/box_link.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Eine über einen fremden Link gekoppelte Box bekommt nichts vom Projekt, bis der Nutzer zustimmt.
void main() {
  late Directory dir;
  late HttpServer server;
  late BoxLink box;
  final writes = <String>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('box_project');
    AppStorage.instance = IoStorage(dir);
    InstallationStore.instance.debugReset();
    writes.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.method != 'GET') writes.add('${request.method} ${request.uri.path}');
      await request.drain<void>();
      if (request.uri.path == '/api/installations') {
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'active': null, 'list': <Object?>[]}));
      } else if (request.method == 'GET') {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response
          ..headers.contentType = ContentType.json
          ..write('{}');
      }
      await request.response.close();
    });
    box = BoxLink(url: Uri.parse('http://127.0.0.1:${server.port}/'), key: 'zugang');
    Addon.box = box;
    final id = InstallationStore.instance.active.id;
    await AppStorage.instance.write('installations/$id/catalog.json', jsonEncode({'project': 'Musterhaus'}));
  });

  tearDown(() async {
    Addon.box = null;
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  test('ausstehend: weder Projekt noch Keyring noch Anlage gehen zur Box', () async {
    await BoxProjectConsent.markPending(box);
    await CatalogStore.instance.shareWithBox();
    expect(await CatalogStore.instance.syncWithBox(), isFalse);
    await KeyringStore.instance.shareWithBox();
    expect(await KeyringStore.instance.syncWithBox(), isFalse);
    await InstallationStore.instance.useOnBox(InstallationStore.instance.active.id);
    expect(writes, isEmpty);
  });

  test('nach der Zustimmung wie bisher', () async {
    await BoxProjectConsent.markPending(box);
    await BoxProjectConsent.confirm(box);
    expect(await BoxProjectConsent.allowed(box), isTrue);
    await CatalogStore.instance.shareWithBox();
    expect(writes, ['PUT /api/files/catalog.json']);
  });

  test('ohne Vermerk (eigener Scanner, ältere Kopplung) gilt die Box als bestätigt', () async {
    expect(await BoxProjectConsent.pending(box), isFalse);
  });

  test('kommt nicht aus einer Sicherung', () {
    expect(FullBackup.keepsOut('box_project_pending:http://evil/'), isTrue);
  });
}
