import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/secure/keyring_store.dart';
import 'package:knx_monitor/knx/secure/package_crypto.dart';
import 'package:knx_monitor/model/box_keyring_consent.dart';
import 'package:knx_monitor/model/full_backup.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/platform/addon.dart';
import 'package:knx_monitor/platform/box_link.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_storage.dart';

class _Rings implements BackupKeyrings {
  Map<String, String> data = {};
  @override
  Future<Map<String, String>> read() async => data;
  @override
  Future<void> write(Map<String, String> rings) async => data = rings;
}

/// Eine von Hand gebaute Sicherung, wie sie ein Angreifer verschicken könnte.
Uint8List craft({
  Map<String, String> files = const {},
  Map<String, Object?> prefs = const {},
  int rounds = 1000,
  String password = 'richtig123456',
  List<int>? zip,
}) {
  final archive = Archive();
  void add(String name, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  files.forEach(add);
  add('prefs.json', jsonEncode(prefs));
  add('keyrings.json', '{}');
  final plain = Uint8List.fromList(zip ?? ZipEncoder().encode(archive));
  final salt = Uint8List(16);
  final nonce = Uint8List(12);
  final key = pbkdf2(utf8.encode(password), salt, rounds == 1000 ? rounds : 10, 32);
  final sealed = aesGcm(
    encrypt: true,
    key: key,
    nonce: nonce,
    aad: Uint8List.fromList(utf8.encode('${FullBackup.format}/${FullBackup.version}')),
    data: plain,
  );
  return utf8.encode(
    jsonEncode({
      'format': FullBackup.format,
      'version': FullBackup.version,
      'kdf': {'name': 'PBKDF2-HMAC-SHA256', 'iterations': rounds, 'salt': base64Encode(salt)},
      'cipher': {'name': 'AES-256-GCM', 'nonce': base64Encode(nonce)},
      'data': base64Encode(sealed),
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FullBackup.iterations = 10;
    FullBackup.minIterations = 1000;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => FullBackup.maxRestoreBytes = 512 * 1024 * 1024);

  Future<int> restore(Uint8List file, MemoryStorage target) =>
      FullBackup(storage: target, paths: () async => [], keyrings: _Rings()).restore(file, 'richtig123456');

  group('Kauf und Freischaltung', () {
    test('kein Schlüssel davon geht in die Datei', () async {
      for (final key in [
        'plan_tier',
        'plan_beta_reward_until',
        'plan_paid_tier',
        'flutter.plan_paid_seen',
        'rc_app_user_id',
        'com.revenuecat.userdefaults',
        'purchases_cache',
        'inst:a:plan_tier',
      ]) {
        expect(FullBackup.keepsOut(key), isTrue, reason: key);
      }
      for (final key in ['inst:a:gateway_host', 'history_days', 'floorplan_scale', 'arc_mode']) {
        expect(FullBackup.keepsOut(key), isFalse, reason: key);
      }
    });

    test('beim Erstellen raus', () async {
      FullBackup.minIterations = 1;
      SharedPreferences.setMockInitialValues({'plan_paid_tier': 'pro', 'inst:a:x': 1});
      final source = MemoryStorage();
      final bytes = await FullBackup(
        storage: source,
        paths: () async => [],
        keyrings: _Rings(),
      ).create('richtig123456');
      SharedPreferences.setMockInitialValues({});
      await restore(bytes, MemoryStorage());
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('inst:a:x'), 1);
      expect(prefs.getString('plan_paid_tier'), isNull);
    });

    test('gefälschte Datei setzt kein dauerhaftes Pro', () async {
      final file = craft(
        prefs: {'plan_beta_reward_until': '2099-01-01T00:00:00Z', 'plan_tier': 'pro', 'history_days': 7},
      );
      await restore(file, MemoryStorage());
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('plan_beta_reward_until'), isNull);
      expect(prefs.getString('plan_tier'), isNull);
      expect(prefs.getInt('history_days'), 7);
    });
  });

  group('Pfade', () {
    for (final path in [
      r'..\..\evil.json',
      r'a\..\..\b.json',
      '../evil.json',
      'a/../../evil.json',
      '/etc/passwd',
      'C:/evil.json',
      r'C:\evil.json',
      'a//b.json',
      './a.json',
      'shared_preferences.json',
      'nicht-lesbar/a.json',
    ]) {
      test('„$path“ nicht', () async {
        expect(FullBackup.safePath(path), isFalse);
        final target = MemoryStorage();
        await expectLater(
          restore(craft(files: {'files/ok.json': '1', 'files/$path': 'x'}), target),
          throwsA(isA<BackupException>().having((e) => e.message, 'message', 'open')),
        );
        expect(await target.read('ok.json'), isNull, reason: 'gar nichts geschrieben');
      });
    }

    test('normale Pfade gehen, Betrieb bleibt draußen', () async {
      final target = MemoryStorage();
      final n = await restore(
        craft(files: {'files/installations/a/catalog.json': '1', 'files/team/x.json': '2'}),
        target,
      );
      expect(n, 1);
      expect(await target.read('installations/a/catalog.json'), '1');
      expect(await target.read('team/x.json'), isNull);
    });
  });

  group('Grenzen', () {
    test('Runden aus der Datei: zu wenige oder zu viele werden abgelehnt', () async {
      for (final rounds in [999, 2000001, 1 << 40]) {
        await expectLater(
          restore(craft(rounds: rounds), MemoryStorage()),
          throwsA(isA<BackupException>().having((e) => e.message, 'message', 'open')),
          reason: '$rounds',
        );
      }
    });

    test('ausgepackt zu groß: abgelehnt', () async {
      FullBackup.maxRestoreBytes = 1000;
      await expectLater(
        restore(craft(files: {'files/gross.json': 'x' * 5000}), MemoryStorage()),
        throwsA(isA<BackupException>()),
      );
    });
  });

  group('Keyring zur Box', () {
    late HttpServer server;
    final puts = <String>[];

    setUp(() async {
      puts.clear();
      HttpOverrides.global = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        await request.drain<void>();
        if (request.method == 'PUT') puts.add(request.uri.path);
        request.response.statusCode = 200;
        request.response.write('{}');
        await request.response.close();
      });
      InstallationStore.instance.debugReset();
      FlutterSecureStorage.setMockInitialValues({'knx_keyring:default': '{"k":1}'});
      Addon.box = BoxLink(url: Uri.parse('http://127.0.0.1:${server.port}/'));
    });

    tearDown(() async {
      Addon.box = null;
      BoxKeyringConsent.ask = null;
      await server.close(force: true);
    });

    test('nie ohne Zustimmung, weder beim Teilen noch beim Abgleich', () async {
      await KeyringStore.instance.shareWithBox();
      await KeyringStore.instance.syncWithBox();
      BoxKeyringConsent.ask = (_) async => false;
      await KeyringStore.instance.shareWithBox();
      await KeyringStore.instance.syncWithBox();
      expect(puts, isEmpty);
    });

    test('mit Zustimmung für genau diese Box', () async {
      BoxLink? asked;
      BoxKeyringConsent.ask = (b) async {
        asked = b;
        return true;
      };
      await KeyringStore.instance.shareWithBox();
      expect(asked?.address, '127.0.0.1:${server.port}');
      expect(puts, hasLength(1));
    });
  });

  group('Neueres Format', () {
    late Directory dir;
    final store = InstallationStore.instance;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('format_newer');
      AppStorage.instance = IoStorage(dir);
      store.debugReset();
    });
    tearDown(() async {
      store.debugReset();
      await dir.delete(recursive: true);
    });

    test('schreibt das Format mit', () async {
      await store.load();
      final j = jsonDecode(File('${dir.path}/installations.json').readAsStringSync()) as Map;
      expect(j['format'], InstallationStore.storageFormat);
      expect(j['version'], 1, reason: 'ältere Versionen lesen dieses Feld');
    });

    test('verweigert und fasst nichts an', () async {
      final index = File('${dir.path}/installations.json');
      final text = jsonEncode({
        'version': 1,
        'format': InstallationStore.storageFormat + 1,
        'list': [
          {'id': 'x', 'name': 'Von morgen', 'neu': true},
        ],
      });
      index.writeAsStringSync(text);
      await store.load();
      expect(store.tooNew, isTrue);
      await store.create('Neu');
      expect(index.readAsStringSync(), text, reason: 'kein neuer Index');
      expect(File('${dir.path}/installations.json.bak').existsSync(), isFalse);
    });

    test('heutiges Format öffnet normal', () async {
      await store.load();
      final a = await store.create('Halle');
      store.debugReset();
      await store.load();
      expect(store.tooNew, isFalse);
      expect(store.byId(a.id)?.name, 'Halle');
    });
  });
}
