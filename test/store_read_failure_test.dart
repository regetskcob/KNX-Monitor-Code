import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/model/annotation.dart';
import 'package:knx_monitor/model/commissioning.dart';
import 'package:knx_monitor/model/company.dart';
import 'package:knx_monitor/model/export_history.dart';
import 'package:knx_monitor/model/health.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/platform/file_cipher.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Key implements FileKeySource {
  _Key(this.value);
  final Uint8List? value;
  @override
  Future<Uint8List?> load(Future<void> Function() onCreated) async => value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  final key = Uint8List.fromList(List.filled(32, 7));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('read_failure');
    AppStorage.instance = IoStorage(dir);
    InstallationStore.instance.debugReset();
    await InstallationStore.instance.load();
  });
  tearDown(() => dir.delete(recursive: true));

  group('Unverständlicher Inhalt wird vor dem Weitermachen beiseitegelegt', () {
    Future<void> check(String path, Future<void> Function() load, {bool scoped = true}) async {
      final prefix = scoped ? 'installations/${InstallationStore.instance.active.id}/' : '';
      await AppStorage.instance.write('$prefix$path', '{kaputt');
      await load();
      final folder = File('${dir.path}/$prefix$path').parent;
      final copies = [
        for (final f in folder.listSync())
          if (f.uri.pathSegments.last.startsWith('${path.split('/').last}.corrupt-')) f as File,
      ];
      expect(copies, hasLength(1), reason: path);
      expect(copies.single.readAsStringSync(), '{kaputt');
    }

    test('Kommentare', () => check('annotations.json', AnnotationStore.instance.load));
    test('Exportverlauf', () => check('exports/index.json', ExportHistory.instance.load));
    test('Firma', () => check('company.json', CompanyStore.instance.load, scoped: false));
    test('Inbetriebnahme', () => check('commissioning.json', Commissioning.instance.reload));
    test('Gesundheit', () => check('health.json', HealthCheck.instance.reload));
    test('Projekt', () => check('catalog.json', CatalogStore.instance.reload));
    test('eigene Typen', () => check('dpt_overrides.json', CatalogStore.instance.reload));
    test('Angelerntes', () => check('learned.json', CatalogStore.instance.reload));
  });

  group('Datei nicht lesbar, Store speichert danach leer', () {
    test('ohne Schlüssel: Speichern scheitert, Datei bleibt', () async {
      final path = 'installations/${InstallationStore.instance.active.id}/annotations.json';
      await IoStorage(dir, _Key(key)).write(path, '[]');
      final before = File('${dir.path}/$path').readAsStringSync();
      AppStorage.instance = IoStorage(dir, _Key(null));
      await AnnotationStore.instance.load();
      expect(AnnotationStore.instance.all, isEmpty);
      await expectLater(AppStorage.instance.write(path, '[]'), throwsA(isA<StorageLockedException>()));
      expect(File('${dir.path}/$path').readAsStringSync(), before);
    });

    test('beschädigt: Original liegt danach beiseite', () async {
      final s = IoStorage(dir, _Key(key));
      await s.write('k.json', 'alt');
      final broken = '${encryptedHeader}QUJD\n';
      File('${dir.path}/k.json').writeAsStringSync(broken);
      await expectLater(s.read('k.json'), throwsA(isA<StorageCorruptException>()));
      await s.write('k.json', '[]');
      final aside = dir.listSync().where((f) => f.path.contains('k.json.corrupt-')).single as File;
      expect(aside.readAsStringSync(), broken);
      expect(await s.read('k.json'), '[]');
    });

    test('beschädigt, vorige Fassung gelesen: Sie wird beim Speichern nicht verdrängt', () async {
      final s = IoStorage(dir, _Key(key));
      await s.write('k.json', 'vorige');
      final good = File('${dir.path}/k.json').readAsStringSync();
      await s.write('k.json', 'aktuell');
      File('${dir.path}/k.json').writeAsStringSync('${encryptedHeader}QUJD\n');
      expect(await s.read('k.json'), 'vorige');
      await s.write('k.json', 'neu');
      expect(File('${dir.path}/k.json.prev').readAsStringSync(), good);
    });

    test('Klartext mit falscher Kodierung wird beim Speichern nicht gelöscht', () async {
      final s = IoStorage(dir, _Key(key));
      File('${dir.path}/k.json').writeAsBytesSync([0xFF, 0xFE, 0x00]);
      await expectLater(s.read('k.json'), throwsA(isA<StorageCorruptException>()));
      await s.write('k.json', '[]');
      final aside = dir.listSync().where((f) => f.path.contains('k.json.corrupt-')).single as File;
      expect(aside.readAsBytesSync(), [0xFF, 0xFE, 0x00]);
    });

    test('Abbruch zwischen den Umbenennungen: vorige Fassung statt leer', () async {
      final s = IoStorage(dir);
      await s.write('k.json', 'eins');
      await s.write('k.json', 'zwei');
      File('${dir.path}/k.json').deleteSync();
      expect(await s.read('k.json'), 'eins');
    });
  });

  group('Index verloren', () {
    final store = InstallationStore.instance;

    Future<void> breakIndex(AppStorage root) async {
      for (final f in ['installations.json', 'installations.json.bak', 'installations.json.prev']) {
        final file = File('${dir.path}/$f');
        if (file.existsSync()) file.writeAsStringSync('{kaputt');
      }
      store.debugReset();
      await store.load();
    }

    test('Anlagen kommen aus ihren Ordnern zurück', () async {
      final root = AppStorage.instance;
      final a = await store.create('Halle');
      final b = await store.create('Müller');
      final c = await store.create('Ohne alles');
      await ScopedStorage(root, 'installations/${a.id}/').write('catalog.json', jsonEncode({'project': 'Halle ETS'}));
      await ScopedStorage(
        root,
        'installations/${b.id}/',
      ).write('customer.json', jsonEncode({'customer': 'Frau Müller'}));
      await ScopedStorage(root, 'installations/${c.id}/').write('annotations.json', '[]');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(InstallationStore.scopedKey(a.id, 'gateway_host'), '10.0.0.9');
      await store.switchTo(b.id);

      await breakIndex(root);

      expect(store.byId(a.id)?.name, 'Halle ETS');
      expect(store.byId(a.id)?.gateway?.host, '10.0.0.9');
      expect(store.byId(b.id)?.name, 'Frau Müller');
      expect(store.byId(c.id)?.name, 'Anlage wiederhergestellt');
      expect(store.active.id, b.id);
      expect(await ScopedStorage(root, 'installations/${a.id}/').read('catalog.json'), isNotNull);
      expect(jsonDecode(File('${dir.path}/installations.json').readAsStringSync()), containsPair('version', 1));
    });

    test('Index beschädigt verschlüsselt: ebenso', () async {
      AppStorage.instance = IoStorage(dir, _Key(key));
      store.debugReset();
      final root = AppStorage.instance;
      await store.load();
      final a = await store.create('Halle');
      await ScopedStorage(root, 'installations/${a.id}/').write('catalog.json', jsonEncode({'project': 'Halle ETS'}));
      for (final f in dir.listSync().whereType<File>()) {
        if (f.path.contains('installations.json')) f.writeAsStringSync('${encryptedHeader}QUJD\n');
      }
      store.debugReset();
      await store.load();
      expect(store.byId(a.id)?.name, 'Halle ETS');
    });

    test('ohne Schlüssel: bricht ab, statt eine neue Liste anzulegen', () async {
      AppStorage.instance = IoStorage(dir, _Key(key));
      store.debugReset();
      await store.load();
      await store.create('Halle'); // schreibt den Index verschlüsselt
      final index = File('${dir.path}/installations.json');
      final before = index.readAsStringSync();
      AppStorage.instance = IoStorage(dir, _Key(null));
      store.debugReset();
      await expectLater(store.load(), throwsA(isA<StorageLockedException>()));
      expect(index.readAsStringSync(), before);
    });
  });
}
