import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/model/full_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_storage.dart';

class _Rings implements BackupKeyrings {
  Map<String, String> data = {};
  @override
  Future<Map<String, String>> read() async => data;
  @override
  Future<void> write(Map<String, String> rings) async => data = rings;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FullBackup.iterations = 10;
    FullBackup.minIterations = 1;
  });

  test('Hin und zurück auf ein leeres Gerät', () async {
    SharedPreferences.setMockInitialValues({'inst:a:x': 3, 'app_lock_enabled': true, 'sb-p-auth-token': 'geheim'});
    final source = MemoryStorage();
    await source.write('installations/a/customers.json', '{"name":"Müller"}');
    await source.write('installations/a/history/2026-10-30.ndjson', 'zeile\n');
    final rings = _Rings()..data = {'knx_keyring:a': '{"k":1}'};
    final bytes = await FullBackup(
      storage: source,
      paths: () async => ['installations/a/customers.json', 'installations/a/history/2026-10-30.ndjson'],
      keyrings: rings,
    ).create('richtig123456');
    expect(String.fromCharCodes(bytes), isNot(contains('Müller')));

    SharedPreferences.setMockInitialValues({});
    final target = MemoryStorage();
    final newRings = _Rings();
    final count = await FullBackup(
      storage: target,
      paths: () async => [],
      keyrings: newRings,
    ).restore(bytes, 'richtig123456');
    expect(count, 2);
    expect(await target.read('installations/a/customers.json'), '{"name":"Müller"}');
    expect(newRings.data, {'knx_keyring:a': '{"k":1}'});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('inst:a:x'), 3);
    expect(prefs.getBool('app_lock_enabled'), isNull, reason: 'Sperre bleibt auf dem Gerät');
    expect(prefs.getString('sb-p-auth-token'), isNull, reason: 'Anmeldung gehört nicht in die Datei');
  });

  test('Daten des Betriebs bleiben draußen', () async {
    SharedPreferences.setMockInitialValues({});
    final source = MemoryStorage();
    await source.write('team/active.json', '{}');
    await source.write('team/c1/entries.jsonl', 'kunde');
    await source.write('a.json', 'x');
    final bytes = await FullBackup(
      storage: source,
      paths: () async => ['team/active.json', 'team/c1/entries.jsonl', 'a.json'],
      keyrings: _Rings(),
    ).create('richtig123456');
    final target = MemoryStorage();
    expect(
      await FullBackup(storage: target, paths: () async => [], keyrings: _Rings()).restore(bytes, 'richtig123456'),
      1,
    );
    expect(await target.read('team/c1/entries.jsonl'), isNull);
  });

  test('falsches Passwort und fremde Datei ändern nichts', () async {
    SharedPreferences.setMockInitialValues({});
    final source = MemoryStorage();
    await source.write('a.json', 'x');
    final backup = FullBackup(storage: source, paths: () async => ['a.json'], keyrings: _Rings());
    final bytes = await backup.create('richtig123456');
    final target = MemoryStorage();
    final restore = FullBackup(storage: target, paths: () async => [], keyrings: _Rings());
    await expectLater(restore.restore(bytes, 'falsch123456'), throwsA(isA<BackupException>()));
    await expectLater(restore.restore(Uint8List.fromList('kein json'.codeUnits), 'x'), throwsA(isA<BackupException>()));
    expect(await target.read('a.json'), isNull);
  });

  group('Erinnerung', () {
    final now = DateTime.utc(2030, 6, 1);
    Duration days(int n) => Duration(days: n);

    test('nur mit Daten und erst nach 30 Tagen', () {
      final old = now.subtract(days(31));
      expect(BackupReminder.isDue(hasData: false, now: now, last: old), isFalse);
      expect(BackupReminder.isDue(hasData: true, now: now, last: old), isTrue);
      expect(BackupReminder.isDue(hasData: true, now: now, last: now.subtract(days(29))), isFalse);
      expect(BackupReminder.isDue(hasData: true, now: now), isFalse);
    });

    test('wegklicken verschiebt, Sicherung auch', () {
      final old = now.subtract(days(40));
      expect(BackupReminder.isDue(hasData: true, now: now, last: old, dismissed: now.subtract(days(1))), isFalse);
      expect(BackupReminder.isDue(hasData: true, now: now, since: old, last: now.subtract(days(1))), isFalse);
    });

    test('nie gesichert: Frist läuft ab dem ersten Bemerken, nicht ab sofort', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await BackupReminder.check(hasCustomerRecords: true, installations: 1, now: now), isFalse);
      expect(await BackupReminder.check(hasCustomerRecords: true, installations: 1, now: now.add(days(29))), isFalse);
      expect(await BackupReminder.check(hasCustomerRecords: true, installations: 1, now: now.add(days(30))), isTrue);
      await BackupReminder.dismiss(now: now.add(days(30)));
      expect(await BackupReminder.check(hasCustomerRecords: true, installations: 1, now: now.add(days(31))), isFalse);
      await BackupReminder.markDone(now: now.add(days(40)));
      expect(await BackupReminder.lastBackup(), now.add(days(40)));
      expect(await BackupReminder.check(hasCustomerRecords: true, installations: 1, now: now.add(days(69))), isFalse);
    });

    test('ohne Kundenakte und mit einer Anlage nie, mit zwei Anlagen schon', () async {
      SharedPreferences.setMockInitialValues({});
      final later = now.add(days(90));
      expect(await BackupReminder.check(hasCustomerRecords: false, installations: 1, now: now), isFalse);
      expect(await BackupReminder.check(hasCustomerRecords: false, installations: 1, now: later), isFalse);
      expect(await BackupReminder.check(hasCustomerRecords: false, installations: 2, now: now), isFalse);
      expect(await BackupReminder.check(hasCustomerRecords: false, installations: 2, now: later), isTrue);
    });

    test('Datum der letzten Sicherung reist nicht mit der Datei', () async {
      SharedPreferences.setMockInitialValues({});
      await BackupReminder.markDone(now: now);
      final bytes = await FullBackup(
        storage: MemoryStorage(),
        paths: () async => [],
        keyrings: _Rings(),
      ).create('zwölf-zeichen-lang');
      SharedPreferences.setMockInitialValues({});
      await FullBackup(
        storage: MemoryStorage(),
        paths: () async => [],
        keyrings: _Rings(),
      ).restore(bytes, 'zwölf-zeichen-lang');
      expect(await BackupReminder.lastBackup(), isNull);
    });
  });

  group('Zu groß für den Speicher', () {
    tearDown(() => FullBackup.maxBytes = 256 * 1024 * 1024);

    test('klarer Fehler mit Größe statt Absturz oder stiller Lücke', () async {
      SharedPreferences.setMockInitialValues({});
      final source = MemoryStorage();
      await source.write('installations/a/history/2026-10-30.ndjson', 'x' * 2000);
      await source.write('team/geheim.json', 'y' * 5000);
      final backup = FullBackup(
        storage: source,
        paths: () async => ['installations/a/history/2026-10-30.ndjson', 'team/geheim.json'],
        keyrings: _Rings(),
      );
      expect(await backup.estimateBytes(), 2000, reason: 'nur was mit in die Sicherung käme');
      FullBackup.maxBytes = 1000;
      await expectLater(
        backup.create('richtig123456'),
        throwsA(
          isA<BackupException>().having((e) => e.message, 'message', 'tooLarge').having((e) => e.bytes, 'bytes', 2000),
        ),
      );
      FullBackup.maxBytes = 5000;
      expect(await backup.create('richtig123456'), isNotEmpty);
    });
  });
}
