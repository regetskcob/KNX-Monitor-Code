// Security review of the DALI implementation: any device on the bus can send any telegram with
// any sender address. Nothing may grow without bound, and the emergency lighting log must never
// claim more than its data carry. These tests rebuild the review's proofs of concept.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/commissioning.dart';
import 'package:knx_monitor/model/dali.dart';
import 'package:knx_monitor/model/dali_commissioning.dart';
import 'package:knx_monitor/model/dali_log.dart';
import 'package:knx_monitor/model/server_features.dart';
import 'package:knx_monitor/model/watch_rules.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart' show IoStorage;

import 'dali_fakes.dart';
import 'memory_storage.dart';

/// Counts the writes per file.
class CountingStorage extends MemoryStorage {
  final writes = <String, int>{};

  @override
  Future<void> write(String path, String text) {
    writes[path] = (writes[path] ?? 0) + 1;
    return super.write(path, text);
  }
}

const _setup = 'installations/default/dali.json';
const _state = 'installations/default/dali_state.json';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = DaliStore.instance;
  final log = DaliTestLog.instance;
  late CountingStorage storage;
  final t0 = DateTime(2026, 11, 10, 2);
  final result = ga('5/2/16');
  final status = ga('5/1/16');

  setUp(() {
    storage = CountingStorage();
    AppStorage.instance = storage;
    DaliProfiles.debugSet(const []);
    store.debugReset();
    log.debugReset();
    Commissioning.instance.debugReset();
    ServerFeatures.instance.update(null);
    CatalogStore.instance
      ..overrides = {}
      ..catalog = daliCatalog();
  });

  tearDown(() async {
    await store.flush();
    CatalogStore.instance
      ..overrides = {}
      ..catalog = GroupCatalog.empty;
    LocaleController.instance.debugSetLocale(const Locale('de'));
  });

  group('H2/H3: Prüfbuch behauptet nicht mehr, als die Daten tragen', () {
    test('ein gefälschtes „bestanden“ von 0x7777 wird nicht dem Gateway zugeschrieben', () {
      final now = t0.add(const Duration(days: 60));
      store.observe(tg(result, '0300500000FF', at: t0)); // duration failed, from the gateway
      store.observe(tg(result, '0300500000FF', at: t0.add(const Duration(days: 1)))); // no news
      store.observe(tg(result, '111050005CFF', source: 0x7777, at: now.subtract(const Duration(days: 1))));
      final forged = log.entries.where((e) => e.foreign).toList();
      expect(forged, isNotEmpty);
      expect(forged.every((e) => e.source == 0x7777 && e.gateway == gatewayPa), isTrue);
      final row = log.overview(now).single;
      // Still failed and overdue: the forged pass counts for nothing, but it is visible.
      expect((row.failed, row.foreign), (true, forged.length));
      expect(row.lastDuration!.result, EmergencyResult.failed);
      expect(store.overall(store.gear(gatewayPa, 16)!), DaliState.testFailed);
    });

    test('ein gefälschter Status „läuft“ → „normal“ macht keine Wiederholung zum neuen Test', () {
      store.observe(tg(result, '100050005CFF', at: t0));
      store.observe(tg(status, '7055', source: 0x7777, at: t0.add(const Duration(days: 7))));
      store.observe(tg(status, '1055', source: 0x7777, at: t0.add(const Duration(days: 7))));
      store.observe(tg(result, '100050005CFF', at: t0.add(const Duration(days: 7, minutes: 1))));
      expect(log.entries.length, 1);
      // The gateway's own status does.
      store.observe(tg(status, '7055', at: t0.add(const Duration(days: 8))));
      store.observe(tg(status, '1055', at: t0.add(const Duration(days: 8))));
      store.observe(tg(result, '100050005CFF', at: t0.add(const Duration(days: 8, minutes: 1))));
      expect(log.entries.length, 2);
    });

    test('erstmals gesehene Ergebnisse: Alter unbekannt, weder aktuell noch überfällig', () {
      store.observe(tg(result, '100050005CFF', at: t0));
      final row = log.overview(t0.add(const Duration(days: 1))).single;
      expect((row.functionDue, row.durationDue, row.open), (TestDue.unknownAge, TestDue.none, true));
      expect(log.entries.single.first, isTrue);
    });

    test('durchgefallener Test: Leuchte, Gruppe und Gateway zeigen ihn, nicht „in Ordnung“', () {
      final gear = store.gear(gatewayPa, 16)!;
      store
        ..editGear(gear, groups: {3}, emergency: true)
        ..observe(tg(status, '1055', at: t0))
        ..observe(tg(result, '0300500000FF', at: t0));
      expect(gear.state, DaliState.ok, reason: 'no fault reported');
      expect(store.overall(gear), DaliState.testFailed);
      expect(store.needsAttention(gear), isTrue);
      expect(store.groupState(store.group(gatewayPa, 3)!), DaliState.testFailed);
      expect(store.gearOf(gatewayPa).first, same(gear), reason: 'needs a look: first');
    });
  });

  group('M1: Absender begrenzt', () {
    test('geteilte Diagnose-Adresse: ein fremder Absender wird nie dem Projekt-Gateway zugeschrieben', () {
      store.observe(tg(diag, '010C', source: 0x7777));
      expect(store.gear(gatewayPa, 12), isNull);
      expect(store.gateway(0x7777)!.trusted, isFalse);
    });

    test('1-Bit-Fehlerobjekte nur vom Gateway', () {
      store.observe(tg(ga('1/7/0'), '', bit: 1, source: 0x7777));
      expect(store.gear(gatewayPa, 0)?.faults, isNull);
    });
  });

  group('M3: dali.json und dali_state.json', () {
    test('Einrichtung und Zustand getrennt; Lebenszeichen nicht bei jedem Telegramm geschrieben', () async {
      store.observe(tg(diag, '000C', at: t0));
      store.editGear(store.gear(gatewayPa, 12)!, name: 'Flur EG Leuchte 2');
      await store.flush();
      final setup = jsonDecode(storage.files[_setup]!) as Map<String, Object?>;
      final gear = (setup['gear']! as List).cast<Map<String, Object?>>();
      expect(gear.any((g) => g.containsKey('f') || g.containsKey('t')), isFalse, reason: 'no runtime state');
      expect(gear.any((g) => g['n'] == 'Flur EG Leuchte 2'), isTrue);
      final before = (storage.writes[_setup] ?? 0, storage.writes[_state] ?? 0);
      for (var i = 0; i < 200; i++) {
        store.observe(tg(diag, '000C', at: t0.add(Duration(seconds: i))));
      }
      await store.flush();
      // Nothing changed but liveness: the setup is not written, the state at most once.
      expect(storage.writes[_setup] ?? 0, before.$1);
      expect((storage.writes[_state] ?? 0) - before.$2, lessThanOrEqualTo(1));
      // A fault is saved right away.
      store.observe(tg(diag, '010C', at: t0.add(const Duration(minutes: 5))));
      await store.flush();
      expect(storage.files[_state], contains('"f":1'));
    });

    test('L4: ein Zeitstempel außerhalb des Bereichs verwirft nur den einen Eintrag', () async {
      storage.files[_setup] = jsonEncode({
        'gateways': [
          {'a': gatewayPa},
        ],
        'gear': [
          {'gw': gatewayPa, 'a': 5, 'n': 'Bleibt'},
        ],
      });
      storage.files[_state] = jsonEncode({
        'gear': [
          {
            'gw': gatewayPa,
            'a': 5,
            'f': 1,
            'since': 9000000000000000,
            'h': [
              [9000000000000000, 1],
              [1794222251000, 1],
            ],
          },
        ],
      });
      store
        ..debugReset()
        ..debugAllowLoad();
      await store.load();
      final gear = store.gear(gatewayPa, 5)!;
      expect((gear.name, gear.faults, gear.since, gear.events.length), ('Bleibt', 1, null, 1));
      expect(storage.files.keys.where((k) => k.contains('.corrupt')), isEmpty);
    });
  });

  group('H1: Prüfbuch begrenzt', () {
    test(
      'eine zu große Jahresdatei wird bis zur Grenze gelesen, nicht verworfen, und als unvollständig markiert',
      () async {
        final entry = jsonEncode(
          EmergencyTest(
            time: t0,
            group: result,
            gateway: gatewayPa,
            address: 16,
            kind: EmergencyTestKind.function,
            result: EmergencyResult.passed,
            raw: '110050005CFF',
          ).toJson(),
        );
        storage.files['installations/default/dali_tests/2026.ndjson'] =
            '$entry\n${'x' * (emergencyLogReadBytes + 100)}\n';
        log
          ..debugReset()
          ..debugAllowLoad();
        await log.load();
        expect(log.entries.length, 1);
        expect(log.limitedYears, {2026});
      },
    );

    test('L2: führt der Server das Prüfbuch, baut die App nichts nach und schreibt nichts', () async {
      ServerFeatures.instance.update({
        'features': ['dali'],
      });
      expect(await log.rebuildFromHistory(), isNull);
      store.observe(tg(result, '110050005CFF', at: t0));
      await pumpEventQueue();
      expect(storage.files.keys.where((k) => k.contains('dali_tests')), isEmpty);
    });
  });

  group('L3: Inbetriebnahme', () {
    test('„falsche Zuordnung“ nur mit passendem Wert vom Gateway und ohne eigene Rückmeldung', () async {
      final tunnel = FakeTunnel();
      final g2 = store.group(gatewayPa, 2)!;
      // Another group's status, but with the other value, and one from a foreign sender.
      tunnel.answer = (dest, {small, required read}) => [
        tg(ga('1/6/3'), '', bit: 0),
        tg(ga('1/6/1'), '', bit: 1, source: 0x7777),
      ];
      final quiet = await switchDaliGroup(tunnel, g2, on: true, window: const Duration(milliseconds: 30));
      expect((quiet.feedback, quiet.foreign), (null, false));
      // The own group answers and another one too: no wrong assignment.
      tunnel.answer = (dest, {small, required read}) => [tg(ga('1/6/3'), '', bit: 1), tg(ga('1/6/2'), '', bit: 1)];
      final own = await switchDaliGroup(tunnel, g2, on: true, window: const Duration(milliseconds: 30));
      expect((own.foreign, own.answeredBy!.group), (false, 2));
      tunnel.dispose();
    });
  });

  test('L7: kaputte Wächter-Einträge werden übersprungen, nicht geworfen', () {
    expect(WatchRule.tryParse({'id': 'a', 'address': 1, 'title': 7, 'sound': 'ja', 'bits': 'x'})!.title, isNull);
    expect(WatchRule.tryParse({'id': 3, 'address': 1}), isNull);
    expect(WatchRule.tryParse({'id': 'a', 'address': 'x'}), isNull);
    expect(WatchRule.tryParse({'id': 'a', 'address': 70000}), isNull);
    expect(WatchRule.tryParse('kaputt'), isNull);
  });

  test('L5: beiseitegelegte Kopien werden mit der Anlage gelöscht', () async {
    final dir = await Directory.systemTemp.createTemp('dali_corrupt');
    addTearDown(() => dir.delete(recursive: true));
    final io = IoStorage(dir);
    final scoped = ScopedStorage(io, 'installations/abc/');
    await scoped.write('dali.json', '{}');
    await keepCorrupt(scoped, 'dali.json', 'kaputt');
    await keepCorrupt(scoped, 'dali_state.json', 'kaputt');
    final folder = Directory('${dir.path}/installations/abc');
    expect(folder.listSync().where((f) => f.path.contains('.corrupt-')).length, 2);
    await deleteCorruptCopies(scoped, 'dali.json');
    final left = folder.listSync().map((f) => f.uri.pathSegments.last).toList();
    expect(left.where((n) => n.startsWith('dali.json.corrupt-')), isEmpty);
    expect(left.where((n) => n.startsWith('dali_state.json.corrupt-')).length, 1);
  });

  test('Abwärtskompatibel: ohne DALI keine Datei, kein Zustand', () async {
    CatalogStore.instance.catalog = GroupCatalog.empty;
    store.debugReset();
    expect(store.isEmpty, isTrue);
    await store.flush();
    expect(storage.writes, isEmpty);
    expect(kIsWeb, isFalse);
  });
}
