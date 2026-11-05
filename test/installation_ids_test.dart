import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/platform/addon.dart';
import 'package:knx_monitor/platform/box_link.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_storage.dart';

/// Installations-Ids von außen (Box, Sicherung, Index) werden Ordnernamen: nichts darf aus dem
/// Datenordner hinausführen.
void main() {
  late Directory root;
  late Directory data;
  final store = InstallationStore.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('knx_ids');
    data = await Directory('${root.path}/data').create();
    AppStorage.instance = IoStorage(data);
    store.debugReset();
  });

  tearDown(() async {
    Addon.box = null;
    await root.delete(recursive: true);
  });

  group('Id', () {
    for (final id in ['a1b2c3d4e5f6', 'default', 'Box_1-2', 'x' * 64]) {
      test('„$id“ ist gültig', () => expect(Installation.isValidId(id), isTrue));
    }
    for (final id in ['', '..', '../x', 'a/b', r'a\b', 'a b', 'a.b', 'x' * 65, 'a\u0000', 'ä']) {
      test('„$id“ ist ungültig', () => expect(Installation.isValidId(id), isFalse));
    }
  });

  test('Index aus einer Sicherung: ungültige Id wird übersprungen, die anderen bleiben', () async {
    await File('${data.path}/installations.json').writeAsString(
      jsonEncode({
        'version': 1,
        'format': 2,
        'list': [
          {'id': 'aaaaaaaaaaaa', 'name': 'Musterhaus', 'created': 0},
          {'id': '../../evil', 'name': 'Böse', 'created': 0},
        ],
      }),
    );
    await store.load();
    expect(store.list.map((i) => i.id), ['aaaaaaaaaaaa']);
    expect(() => Installation.fromJson({'id': '../x'}), throwsFormatException);
  });

  test('create lehnt ungültige Id ab', () async {
    await store.load();
    await expectLater(store.create('X', id: '../x'), throwsArgumentError);
  });

  test('Box liefert eine Id mit „..“: nichts außerhalb des Datenordners, gültige wird übernommen', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requested = <String>[];
    server.listen((request) async {
      requested.add(request.uri.path);
      final path = request.uri.path;
      if (path == '/api/installations') {
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'active': '../../escape',
              'list': [
                {'id': '../../escape', 'name': 'Böse'},
                {'id': 'gut123', 'name': 'Gut'},
              ],
            }),
          );
      } else if (path.endsWith('/catalog.json')) {
        request.response.write(jsonEncode({'project': 'P', 'groups': <Object?>[]}));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    await store.load();
    Addon.box = BoxLink(url: Uri.parse('http://127.0.0.1:${server.port}/'));
    await store.syncBox();
    expect(store.boxList.keys, ['gut123']);
    expect(store.boxActive, isNull);
    expect(store.byId('gut123'), isNotNull);
    expect(store.list.any((i) => i.id.contains('.')), isFalse);
    expect(requested.where((p) => p.contains('escape')), isEmpty);
    expect(File('${root.path}/escape/catalog.json').existsSync(), isFalse);
    expect(File('${data.path}/installations/gut123/catalog.json').existsSync(), isTrue);
  });

  group('Ablage', () {
    test('IoStorage verweigert Pfade aus dem Ordner hinaus', () async {
      final storage = IoStorage(data);
      for (final path in ['../x.json', 'a/../../x.json', '/etc/x.json', r'a\..\x.json', 'C:/x.json', 'a\u0000b']) {
        await expectLater(storage.write(path, 'x'), throwsArgumentError, reason: path);
        await expectLater(storage.read(path), throwsArgumentError, reason: path);
        await expectLater(storage.delete(path), throwsArgumentError, reason: path);
        await expectLater(storage.list(path), throwsArgumentError, reason: path);
      }
      expect(File('${root.path}/x.json').existsSync(), isFalse);
      await storage.write('a/b.json', 'ok');
      expect(await storage.read('a/b.json'), 'ok');
    });

    test('ScopedStorage prüft auch über einer Ablage, die selbst nicht prüft', () async {
      final base = MemoryStorage();
      final scoped = ScopedStorage(base, 'installations/../../');
      await expectLater(scoped.write('x.json', 'x'), throwsArgumentError);
      await expectLater(ScopedStorage(base, 'installations/a/').read('../../x.json'), throwsArgumentError);
      await ScopedStorage(base, 'installations/a/').write('x.json', 'x');
      expect(await base.read('installations/a/x.json'), 'x');
    });
  });
}
