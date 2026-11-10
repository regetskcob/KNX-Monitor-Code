import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/model/keys.dart';
import 'package:knx_monitor/platform/addon.dart';
import 'package:knx_monitor/platform/app_instance.dart';
import 'package:knx_monitor/platform/box_link.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Schlüssel nach docs/keys.md: Anlage, Box und App-Instanz sind überall dieselben, und ein
/// Schlüssel öffnet nichts.
void main() {
  group('Form', () {
    test('neuer Schlüssel ist eine UUID, jeder ein anderer', () {
      final keys = {for (var i = 0; i < 100; i++) newKey()};
      expect(keys.length, 100);
      expect(keys.every(isKey), isTrue);
      expect(keys.every((k) => k[14] == '4'), isTrue);
    });

    test('nur kleingeschriebene UUIDs gelten', () {
      for (final bad in [null, 7, '', 'default', '../x', 'B81DCE89-E81F-53E4-A829-F22314C69114', '${newKey()} ']) {
        expect(isKey(bad), isFalse, reason: '$bad');
      }
    });

    // Der Vektor steht fest: Ändert sich die Ableitung, bekäme jede Anlage aus der Zeit vor den
    // Schlüsseln auf jedem Gerät einen anderen.
    test('abgeleiteter Schlüssel ändert sich nie', () {
      expect(derivedInstallationKey('a1b2c3d4e5f6'), 'b81dce89-e81f-53e4-a829-f22314c69114');
      expect(isKey(derivedInstallationKey('a1b2c3d4e5f6')), isTrue);
      expect(isRandomInstallationId('a1b2c3d4e5f6'), isTrue);
      expect(isRandomInstallationId('default'), isFalse);
    });
  });

  group('Anlage', () {
    test('ohne gespeicherten Schlüssel: aus der Id, auf jedem Gerät derselbe', () {
      final a = Installation.fromJson({'id': 'a1b2c3d4e5f6', 'name': 'Haus', 'created': 0});
      final b = Installation(id: 'a1b2c3d4e5f6', name: 'Anders', created: DateTime(2026));
      expect(a.key, b.key);
      expect(a.keyIsPlaceholder, isFalse);
      expect(Installation.fromJson(a.toJson()).key, a.key);
    });

    test('gespeicherter Schlüssel bleibt, ein ungültiger zählt nicht', () {
      final key = newKey();
      final i = Installation.fromJson({'id': 'a1b2c3d4e5f6', 'name': 'Haus', 'created': 0, 'key': key});
      expect(i.key, key);
      expect(i.copyWith(name: 'Neu').key, key);
      final bad = Installation.fromJson({'id': 'a1b2c3d4e5f6', 'name': 'Haus', 'created': 0, 'key': '../../x'});
      expect(bad.key, derivedInstallationKey('a1b2c3d4e5f6'));
    });

    test('„default“ hat nur einen Platzhalter', () {
      final i = Installation(id: 'default', name: 'Installation', created: DateTime(2026));
      expect(i.keyIsPlaceholder, isTrue);
      expect(i.copyWith(key: newKey()).keyIsPlaceholder, isFalse);
    });
  });

  group('Box', () {
    late Directory root;
    final store = InstallationStore.instance;
    final created = <Map<String, Object?>>[];
    final written = <String>[];

    /// Eine Box mit ihrem Schlüssel und ihrer Installation „default“.
    Future<BoxLink> box(String boxKey, String key, {String name = 'Haus', String? project}) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final list = <Map<String, Object?>>[
        {'id': 'default', 'name': name, 'key': key},
      ];
      server.listen((request) async {
        final path = request.uri.path;
        final response = request.response;
        if (request.method != 'GET') written.add('${request.method} $path');
        if (path == '/api/installations' && request.method == 'GET') {
          response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'box': boxKey, 'active': 'default', 'list': list}));
        } else if (path == '/api/installations' && request.method == 'POST') {
          final body = (jsonDecode(await utf8.decodeStream(request)) as Map).cast<String, Object?>();
          created.add(body);
          list.add(body);
          response.statusCode = HttpStatus.created;
          response.write('{}');
        } else if (path == '/api/installations/default/files/catalog.json') {
          response.write(jsonEncode({'project': project ?? name, 'groups': <Object?>[]}));
        } else {
          response.statusCode = HttpStatus.notFound;
        }
        await response.close();
      });
      return BoxLink(url: Uri.parse('http://127.0.0.1:${server.port}/'));
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      root = await Directory.systemTemp.createTemp('knx_keys');
      AppStorage.instance = IoStorage(root);
      store.debugReset();
      created.clear();
      written.clear();
      await store.load();
    });

    tearDown(() async {
      Addon.box = null;
      await root.delete(recursive: true);
    });

    test('zwei Boxen nennen ihre Installation „default“: hier bleiben es zwei', () async {
      final keyA = newKey(), keyB = newKey();
      Addon.box = await box(newKey(), keyA, name: 'Haus A');
      await store.syncBox();
      expect(store.byId('default')?.key, keyA);
      expect(store.boxActive, 'default');
      expect(store.boxIdOf('default'), 'default');

      final boxB = newKey();
      Addon.box = await box(boxB, keyB, name: 'Haus B');
      await store.syncBox();
      expect(store.boxKey, boxB);
      final b = store.byKey(keyB)!;
      expect(b.id, isNot('default'));
      expect(b.name, 'Haus B');
      expect(store.boxIdOf(b.id), 'default');
      expect(store.boxActive, b.id);
      expect(store.boxList, {b.id: 'Haus B'});
      // Die erste ist unberührt, ihr Projekt auch.
      expect(store.byId('default')?.key, keyA);
      expect(store.byId('default')?.name, 'Haus A');
      expect(await File('${root.path}/installations/default/catalog.json').readAsString(), contains('Haus A'));
      expect(await File('${root.path}/installations/${b.id}/catalog.json').readAsString(), contains('Haus B'));

      // Zurück an der ersten Box: wieder ihre, nichts Drittes.
      Addon.box = await box(newKey(), keyA, name: 'Haus A');
      await store.syncBox();
      expect(store.boxActive, 'default');
      expect(store.list.length, 3, reason: 'eigene, Haus A, Haus B');
    });

    // Security Review 10.11.: Ohne Übernahme (adopt: false) blieb die aktive Anlage der zweiten
    // Box unbekannt, und das Projekt der hier aktiven Anlage wäre an sie gegangen.
    test('zweite Box ohne Übernahme: das Projekt der ersten Anlage geht nicht dorthin', () async {
      Addon.box = await box(newKey(), newKey(), name: 'Haus A');
      await store.syncBox();
      await store.switchTo('default');
      written.clear();
      Addon.box = await box(newKey(), newKey(), name: 'Haus B');
      await store.syncBox(adopt: false);
      expect(store.boxActive, InstallationStore.boxActiveUnconnected);
      expect(store.onBox('default'), isFalse);
      expect(await store.shareChangesWithBox(), isFalse);
      expect(written, isEmpty, reason: 'nichts geht an die fremde Box');
      expect(store.list.length, 2, reason: 'eigene und Haus A');
    });

    // Copilot-Review zu #250: Ein Schlüssel wird einmal gesetzt und nie ersetzt, und zwei
    // Anlagen hier teilen keinen.
    test('feststehender Schlüssel wird nicht ersetzt, doppelter nicht angelegt', () async {
      final key = newKey();
      final a = await store.create('A', key: key);
      await store.setKey(a.id, newKey());
      expect(store.byId(a.id)!.key, key);
      final b = await store.create('B');
      final derived = b.key;
      await store.setKey(b.id, key);
      expect(store.byId(b.id)!.key, derived, reason: 'gehört schon A');
      final fresh = newKey();
      await store.setKey(b.id, fresh);
      expect(store.byId(b.id)!.key, fresh, reason: 'nie gespeichert: einmal setzbar');
      await store.setKey(b.id, newKey());
      expect(store.byId(b.id)!.key, fresh);
      await expectLater(store.create('C', key: key), throwsArgumentError);
      expect(store.list.where((i) => i.key == key).length, 1);
    });

    // Review zu #250: Auch die Id allein verbindet nichts, wenn der Schlüssel nicht passt.
    test('Box nennt die Id einer hiesigen Anlage mit fremdem Schlüssel: nur ein Anspruch', () async {
      final mine = await store.create('Kunde Meier');
      await store.switchTo(mine.id);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <String>[];
      server.listen((request) async {
        requests.add('${request.method} ${request.uri.path}');
        if (request.uri.path == '/api/installations' && request.method == 'GET') {
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'box': newKey(),
                'active': mine.id,
                'list': [
                  {'id': mine.id, 'name': 'Fremd', 'key': newKey()},
                ],
              }),
            );
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
      Addon.box = BoxLink(url: Uri.parse('http://127.0.0.1:${server.port}/'));
      await store.syncBox();
      expect(store.boxClaims, {mine.id: mine.id});
      expect(store.boxActive, InstallationStore.boxActiveUnconnected);
      expect(store.onBox(mine.id), isFalse);
      expect(await store.shareChangesWithBox(), isFalse);
      expect(requests.where((r) => !r.startsWith('GET')), isEmpty);
      expect(store.byId(mine.id)!.name, 'Kunde Meier');
    });

    test('vor den Schlüsseln übernommene „default“ bekommt den der Box', () async {
      await store.create('Haus', id: 'default');
      expect(store.byId('default')!.keyIsPlaceholder, isTrue);
      final key = newKey();
      Addon.box = await box(newKey(), key);
      await store.syncBox();
      expect(store.byId('default')!.key, key);
      expect(store.list.where((i) => i.key == key).length, 1);
    });

    // docs/keys.md: Der Schlüssel benennt nur. Eine Box, die den Schlüssel einer Anlage von hier
    // behauptet, bekommt dadurch weder deren Projekt zu sehen noch überschreibt sie etwas.
    test('Box behauptet den Schlüssel einer hiesigen Anlage: nichts wird überschrieben', () async {
      final mine = await store.create('Kunde Meier');
      final storage = ScopedStorage(AppStorage.instance, 'installations/${mine.id}/');
      await storage.write('catalog.json', jsonEncode({'project': 'Meier', 'groups': <Object?>[]}));
      Addon.box = await box(newKey(), mine.key, name: 'Fremd', project: 'Untergeschoben');
      await store.syncBox();
      // Nicht verbunden: Die Box verwaltet die Anlage nicht, also geht auch nichts dorthin
      // (CatalogStore und KeyringStore teilen nur, was die Box verwaltet).
      await store.switchTo(mine.id);
      await store.syncBox();
      expect(store.boxActive, InstallationStore.boxActiveUnconnected);
      expect(await store.shareChangesWithBox(), isFalse);
      expect(written, isEmpty, reason: 'nichts geht an die Box');
      expect(store.boxList, isEmpty);
      expect(store.onBox(mine.id), isFalse);
      expect(store.boxClaims, {mine.id: 'default'});
      expect(store.byKey(mine.key)!.id, mine.id);
      expect(store.byId(mine.id)!.name, 'Kunde Meier');
      expect(await storage.read('catalog.json'), contains('Meier'));
      expect(await storage.read('catalog.json'), isNot(contains('Untergeschoben')));
      expect(store.list.where((i) => i.key == mine.key).length, 1);

      // Erst die ausdrückliche Bestätigung verbindet die beiden.
      await store.acceptBoxClaim(mine.id);
      expect(store.boxClaims, isEmpty);
      expect(store.boxActive, mine.id);
      expect(store.boxIdOf(mine.id), 'default');
      expect(await storage.read('catalog.json'), contains('Meier'));
    });
  });

  group('App-Instanz', () {
    test('ein Schlüssel je Gerät, bleibt', () async {
      SharedPreferences.setMockInitialValues({});
      final id = await AppInstance.id();
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(id), isTrue);
      expect(await AppInstance.id(), id);
    });

    test('gleichzeitige erste Aufrufe bekommen denselben Schlüssel', () async {
      SharedPreferences.setMockInitialValues({});
      final ids = await Future.wait([AppInstance.id(), AppInstance.id(), AppInstance.id()]);
      expect(ids.toSet().length, 1);
      expect(await AppInstance.id(), ids.first);
    });

    test('übernimmt die Kennung, die das Konto schon vergeben hat', () async {
      SharedPreferences.setMockInitialValues({AppInstance.prefsKey: '00112233445566778899aabbccddeeff'});
      expect(await AppInstance.id(), '00112233445566778899aabbccddeeff');
    });
  });

  // Wer eine neue Kennung erfindet, soll an docs/keys.md vorbeikommen. Erkannt wird das am
  // Zufall: Jede Datei, die welchen zieht, steht hier, entweder weil sie einen Schlüssel aus
  // docs/keys.md erzeugt oder weil es Kryptomaterial (Salz, Nonce, Token) ist. Dateien der
  // privaten Teile fehlen im öffentlichen Quellcode; die Liste darf mehr nennen, als es gibt.
  test('Zufall nur in bekannten Dateien (neue Kennung? docs/keys.md)', () {
    const known = {
      // Schlüssel und Kennungen aus docs/keys.md
      'lib/model/keys.dart',
      'lib/model/installation.dart',
      'lib/platform/app_instance.dart',
      'ha-addon/knx_monitor/server/lib/src/installations.dart',
      'ha-addon/knx_monitor/server/lib/src/box_access.dart',
      // Kryptomaterial und Kennungen, die nur an einem Ort gelten
      'lib/export/handover_package.dart',
      'lib/knx/secure/package_crypto.dart',
      'lib/knx/secure/team_crypto.dart',
      'lib/model/account.dart',
      'lib/model/app_lock.dart',
      'lib/model/betrieb/team_engine.dart',
      'lib/model/cloud_sync.dart',
      'lib/model/cloud_sync_engine.dart',
      'lib/model/full_backup.dart',
      'lib/platform/file_cipher.dart',
      'lib/platform/storage_io.dart',
      'ha-addon/knx_monitor/server/lib/src/atomic_file.dart',
      'ha-addon/knx_monitor/server/lib/src/exporter.dart',
      'ha-addon/knx_monitor/server/lib/src/ha_integration.dart',
      'ha-addon/knx_monitor/server/lib/src/mcp_server.dart',
      'ha-addon/knx_monitor/server/lib/src/mqtt_bridge.dart',
    };
    final random = RegExp(r'Random\.secure\(\)|\brandomBytes\(');
    final found = <String>{};
    for (final dir in ['lib', 'ha-addon/knx_monitor/server/lib', 'ha-addon/knx_monitor/server/bin']) {
      for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart') || f.path.contains('/l10n/')) continue;
        if (random.hasMatch(f.readAsStringSync())) found.add(f.path.replaceAll(r'\', '/'));
      }
    }
    expect(
      found.difference(known),
      isEmpty,
      reason: 'Neue Datei mit Zufall. Entsteht dort eine Kennung, gehört sie zuerst nach docs/keys.md.',
    );
  });
}
