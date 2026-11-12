import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart' show Locale;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/export/dali_export.dart';
import 'package:knx_monitor/export/pdf_export.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/alarm_notifier.dart';
import 'package:knx_monitor/model/alarms.dart';
import 'package:knx_monitor/model/commissioning.dart';
import 'package:knx_monitor/model/dali.dart';
import 'package:knx_monitor/model/dali_alarms.dart';
import 'package:knx_monitor/model/dali_commissioning.dart';
import 'package:knx_monitor/model/dali_health.dart';
import 'package:knx_monitor/model/dali_labels.dart';
import 'package:knx_monitor/model/dali_log.dart';
import 'package:knx_monitor/model/dali_service.dart';
import 'package:knx_monitor/model/dali_watch.dart';
import 'package:knx_monitor/model/health.dart';
import 'package:knx_monitor/model/server_features.dart';
import 'package:knx_monitor/model/service_report.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/model/watch_rules.dart';
import 'package:knx_monitor/platform/storage.dart';

import 'dali_fakes.dart';
import 'memory_storage.dart';

const _file = 'installations/default/dali.json';
const _stateFile = 'installations/default/dali_state.json';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = DaliStore.instance;
  final log = DaliTestLog.instance;
  late MemoryStorage storage;
  final t0 = DateTime(2026, 11, 10, 12);

  setUp(() {
    storage = MemoryStorage();
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

  group('Projekt', () {
    test('Gateway über die DALI-Typen, Rollen aus Objekttexten, kein Aktor wird Gateway', () {
      final p = store.project;
      expect(p.gateways.keys, [gatewayPa]);
      expect(p.objects[diag]!.role, DaliRole.diagnostic);
      expect(p.objects[ga('1/5/3')]!.role, DaliRole.groupSwitch);
      expect((p.objects[ga('1/6/3')]!.role, p.objects[ga('1/6/3')]!.index), (DaliRole.groupStatus, 3));
      expect((p.objects[ga('1/7/0')]!.role, p.objects[ga('1/7/0')]!.index), (DaliRole.lampFault, 0));
      expect((p.objects[ga('1/7/1')]!.role, p.objects[ga('1/7/1')]!.index), (DaliRole.gearFault, 1));
      expect((p.objects[ga('5/2/16')]!.role, p.objects[ga('5/2/16')]!.index), (DaliRole.emergencyResult, 16));
      expect(p.objects.containsKey(ga('2/0/1')), isFalse);
      final gw = store.gateways.single;
      expect((gw.projectName, gw.location, gw.inProject), ('DALI-Gateway', 'EG › Flur/Büro', true));
      expect(store.groupsOf(gatewayPa).map((g) => g.group), [0, 1, 2, 3]);
      expect(store.group(gatewayPa, 3)!.switchGroup, ga('1/5/3'));
      expect(store.group(gatewayPa, 3)!.statusGroup, ga('1/6/3'));
      final converter = store.gear(gatewayPa, 16)!;
      expect((converter.emergency, converter.statusGroup, converter.resultGroup), (true, ga('5/1/16'), ga('5/2/16')));
    });

    test('Texte, die bis 64 zählen, zählen ab 1', () {
      final a = ga('1/7/64');
      final catalog = daliCatalog();
      CatalogStore.instance.catalog = GroupCatalog({
        ...catalog.groups,
        a: GroupInfo(
          address: a,
          name: 'EVG 64 Fehler',
          dpt: const Dpt(1, 5),
          links: [GroupLink(device: gatewayPa, text: 'EVG 64 Fehler', sends: true)],
        ),
      }, devices: catalog.devices)..groups.remove(ga('1/7/0'));
      expect(store.project.objects[a]!.index, 63);
      expect(store.project.objects[ga('1/7/1')]!.index, 0);
    });

    test('Profil: Erkennung über Hersteller und Produkt, Regeln nach Objektnummer und Text', () {
      final profile = DaliProfile.fromJson({
        'id': 'test',
        'name': 'Testgateway',
        'match': {
          'manufacturer': ['acme'],
          'product': ['dg 64'],
        },
        'gearBase': 1,
        'rules': [
          {'role': 'gearFault', 'first': 230, 'step': 11, 'count': 64},
          {'role': 'lampFault', 'text': r'^Ballast (\d+) lamp'},
          {'role': 'nonsense', 'first': 1},
          {'role': 'faultCount', 'text': '(unclosed'},
          'no rule',
        ],
      })!;
      expect(profile.status, DaliProfileStatus.documented);
      expect(profile.rules.length, 2);
      DaliProfiles.debugSet([profile]);
      final byNumber = ga('3/0/1');
      final byText = ga('3/0/2');
      CatalogStore.instance.catalog = GroupCatalog(
        {
          byNumber: GroupInfo(
            address: byNumber,
            name: 'x',
            dpt: const Dpt(1, 5),
            links: [GroupLink(device: gatewayPa, object: 252, sends: true)],
          ),
          byText: GroupInfo(
            address: byText,
            name: 'y',
            dpt: const Dpt(1, 5),
            links: [GroupLink(device: gatewayPa, object: 5, text: 'Ballast 7 lamp fault', sends: true)],
          ),
        },
        devices: {gatewayPa: DeviceInfo(address: gatewayPa, name: 'GW', product: 'DG 64', manufacturer: 'ACME GmbH')},
      );
      final p = store.project;
      expect(p.gateways[gatewayPa]!.profile!.id, 'test');
      // Object 252 = 230 + 2 × 11: third ballast, counted from 0. Text "Ballast 7": minus gearBase.
      expect((p.objects[byNumber]!.role, p.objects[byNumber]!.index), (DaliRole.gearFault, 2));
      expect((p.objects[byText]!.role, p.objects[byText]!.index), (DaliRole.lampFault, 6));
      expect(DaliProfile.fromJson({'id': 'x', 'name': 'x', 'match': <String, Object?>{}}), isNull);
      expect(DaliProfile.fromJson('kaputt'), isNull);
    });

    test('Die ausgelieferten Profile sind lesbar und ehrlich als ungeprüft markiert', () async {
      DaliProfiles.debugSet(const []);
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final paths = manifest.listAssets().where((p) => p.startsWith('assets/dali_profiles/')).toList();
      expect(paths, isNotEmpty);
      for (final path in paths) {
        final json = jsonDecode(await rootBundle.loadString(path)) as Map<String, Object?>;
        final profile = DaliProfile.fromJson(json);
        expect(profile, isNotNull, reason: path);
        expect(profile!.status, DaliProfileStatus.documented, reason: path);
        expect(json['statusNote'], 'from documentation, not yet verified against real telegrams', reason: path);
        expect(profile.source, isNotEmpty, reason: path);
        expect(profile.rules, isNotEmpty, reason: path);
      }
    });
  });

  group('Telegramme', () {
    test('Lampenfehler setzen und zurücknehmen, je Leuchte, Abfragen zählen nicht', () async {
      final changes = <DaliChange>[];
      final sub = store.changes.listen(changes.add);
      store.observe(tg(diag, '000C', at: t0));
      expect(store.gear(gatewayPa, 12)!.state, DaliState.ok);
      store.observe(tg(diag, '010C', at: t0.add(const Duration(minutes: 1))));
      store.observe(tg(diag, '0003', at: t0.add(const Duration(minutes: 1))));
      store.observe(tg(diag, '008D', at: t0.add(const Duration(minutes: 2)))); // query for 13
      store.observe(tg(diag, '010C', at: t0.add(const Duration(minutes: 3)))); // repeated
      await pumpEventQueue();
      final gear = store.gear(gatewayPa, 12)!;
      expect(
        (gear.state, gear.since, gear.lastReport),
        (DaliState.lampFault, t0.add(const Duration(minutes: 1)), t0.add(const Duration(minutes: 3))),
      );
      expect(gear.events.map((e) => e.faults), [0, 1]);
      expect(store.gear(gatewayPa, 13), isNull);
      expect(store.gear(gatewayPa, 3)!.state, DaliState.ok);
      expect(changes.length, 1);
      expect(daliAlarmTitle(changes.single), 'Lampenfehler: EVG 12');
      store.observe(tg(diag, '000C', at: t0.add(const Duration(minutes: 9))));
      await pumpEventQueue();
      expect(daliAlarmTitle(changes.last), 'Wieder in Ordnung: EVG 12');
      expect(store.faultyGear, isEmpty);
      await sub.cancel();
    });

    test('Gruppe statt Gerät, EVG-Fehler schlägt Lampenfehler, falsche Länge ändert nichts', () {
      store.observe(tg(diag, '0343'));
      expect(store.group(gatewayPa, 3)!.state, DaliState.gearFault);
      expect(store.gear(gatewayPa, 3), isNull);
      store.observe(tg(diag, '010C00'));
      store.observe(tg(diag, '080C'));
      expect(store.gear(gatewayPa, 12), isNull);
    });

    test('Fehlerobjekte je EVG (1 Bit), Konverterstatus, Testergebnis ins Prüfbuch', () {
      store.observe(tg(ga('1/7/0'), '', bit: 1));
      store.observe(tg(ga('1/7/1'), '', bit: 1));
      expect(store.gear(gatewayPa, 0)!.state, DaliState.lampFault);
      expect(store.gear(gatewayPa, 1)!.state, DaliState.gearFault);
      store.observe(tg(ga('1/7/0'), '', bit: 0));
      expect(store.gear(gatewayPa, 0)!.state, DaliState.ok);

      store.observe(tg(ga('5/1/16'), '5256'));
      final converter = store.gear(gatewayPa, 16)!;
      expect((converter.state, converter.mode), (DaliState.converterFault, ConverterMode.emergency));
      store.observe(tg(ga('5/2/16'), '1300500000FF', at: t0));
      store.observe(tg(ga('5/2/16'), '1300500000FF', at: t0.add(const Duration(hours: 1))));
      expect(log.entries.map((e) => (e.kind, e.result, e.address)), [
        (EmergencyTestKind.function, EmergencyResult.passed, 16),
        (EmergencyTestKind.duration, EmergencyResult.failed, 16),
      ]);
      expect(daliNameOf(tg(ga('5/2/16'), '1300500000FF')), 'Notlicht 16');
    });

    test('Ohne Projekt: Gateway und Leuchten entstehen beim Mithören, sobald der Typ gewählt ist', () {
      CatalogStore.instance.catalog = GroupCatalog.empty;
      store.observe(tg(diag, '010C'));
      expect(store.isEmpty, isTrue);
      CatalogStore.instance.overrides = {diag: const Dpt(237, 600)};
      store.observe(tg(diag, '010C'));
      final gw = store.gateways.single;
      expect((gw.address, gw.inProject, gw.trusted), (gatewayPa, false, false));
      expect(gw.diagnosticGroups, {diag});
      expect(store.gear(gatewayPa, 12)!.state, DaliState.lampFault);
      // A suggestion: nothing is read for it and nothing saved before it is taken over.
      expect(store.readableAddresses(), isEmpty);
      expect(store.toSetupJson()['gateways'], isEmpty);
      store.confirmGateway(gw);
      expect(gw.trusted, isTrue);
      expect(store.readableAddresses(), [diag]);
      expect((store.toSetupJson()['gateways']! as List).single, containsPair('ok', true));
      store.removeGateway(gw);
      expect(store.isEmpty, isTrue);
    });

    test(
      '30.000 gefälschte Absender: höchstens 16 Vorschläge, dali.json bleibt klein, Projekt-Gateway unberührt',
      () async {
        final started = DateTime.now();
        for (var pa = 0x2000; pa < 0x2000 + 30000; pa++) {
          store.observe(tg(diag, '010C', source: pa));
        }
        expect(DateTime.now().difference(started), lessThan(const Duration(seconds: 10)));
        expect(store.gateways.where((g) => !g.trusted).length, DaliStore.maxSuggestions);
        // Reports from foreign senders are not the project gateway's.
        expect(store.gear(gatewayPa, 12), isNull);
        expect(store.faultyGear, isEmpty);
        await store.flush();
        final setup = storage.files[_file] ?? '';
        final state = storage.files[_stateFile] ?? '';
        expect(setup.length + state.length, lessThan(64 * 1024));
        expect(state, isNot(contains('${0x2000}')));
      },
    );

    test('Namen aus dem Modell im Klartext des Monitors', () {
      store.observe(tg(diag, '010C'));
      expect(CatalogStore.instance.value(tg(diag, '010C')), 'EVG 12 · Lampenfehler');
      store.editGear(store.gear(gatewayPa, 12)!, name: 'Flur EG Leuchte 2', room: 'Flur EG', groups: {1, 99});
      expect(CatalogStore.instance.value(tg(diag, '010C')), 'Flur EG Leuchte 2 · Lampenfehler');
      expect(store.gear(gatewayPa, 12)!.groups, {1});
      expect(activeAlarm(tg(diag, '010C')), AlarmKind.fault);
      expect(activeAlarm(tg(diag, '000C')), isNull);
      expect(activeAlarm(tg(diag, '018C')), isNull);
    });
  });

  group('dali.json', () {
    test('ohne DALI entsteht keine Datei', () async {
      CatalogStore.instance.catalog = GroupCatalog.empty;
      store.observe(tg(ga('2/0/0'), '0C24'));
      store.updateSettings((x) => x.functionDays = 7);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await store.flush();
      expect(storage.files, isEmpty);
    });

    test('speichern und wieder laden: Zustand, Namen, Einstellungen; Rollen für den Server', () async {
      store.observe(tg(diag, '010C', at: t0));
      store.editGear(store.gear(gatewayPa, 12)!, name: 'Flur EG Leuchte 2', room: 'Flur EG', groups: {1});
      store.rename(store.group(gatewayPa, 1)!, 'Flur EG');
      store.updateSettings(
        (x) => x
          ..functionDays = 7
          ..poll = true,
      );
      await store.flush();
      final json = jsonDecode(storage.files[_file]!) as Map<String, Object?>;
      expect(json['v'], 1);
      expect(((json['objects']! as Map)['$diag'] as Map)['r'], 'diagnostic');
      expect(((json['objects']! as Map)['${ga('5/2/16')}'] as Map), {'gw': gatewayPa, 'r': 'emergencyResult', 'i': 16});

      store
        ..debugReset()
        ..debugAllowLoad();
      await store.load();
      final gear = store.gear(gatewayPa, 12)!;
      expect((gear.name, gear.room, gear.state, gear.since), ('Flur EG Leuchte 2', 'Flur EG', DaliState.lampFault, t0));
      expect(gear.groups, {1});
      expect(store.group(gatewayPa, 1)!.name, 'Flur EG');
      expect(store.group(gatewayPa, 1)!.switchGroup, ga('1/5/1'));
      expect((store.settings.functionDays, store.settings.poll), (7, true));
    });

    test('kaputte, fremde und riesige Dateien: nichts stürzt ab, Unsinn wird übersprungen', () async {
      for (final text in [
        'kein json',
        '[]',
        '{"gateways": "viele", "gear": 7}',
        jsonEncode({
          'gateways': [
            {'a': 'x'},
            {'a': 70000},
            {'a': gatewayPa, 'n': 5},
            null,
          ],
          'gear': [
            {'gw': gatewayPa, 'a': 64},
            {
              'gw': gatewayPa,
              'a': 5,
              'f': 99,
              'g': [1, 'zwei', 17],
              'h': [
                [1, 2, 3],
                'x',
                [5, 9],
              ],
              'n': 'x' * 500,
            },
            'nichts',
          ],
          'groups': [
            {'gw': gatewayPa, 'g': 16},
          ],
          'settings': {'functionDays': -3, 'pollMinutes': 'oft'},
        }),
        'x' * (5 * 1024 * 1024),
      ]) {
        storage.files[_file] = text;
        store
          ..debugReset()
          ..debugAllowLoad();
        await store.load();
        expect(store.gateways.map((g) => g.address), [
          gatewayPa,
        ], reason: text.substring(0, text.length < 20 ? text.length : 20));
        expect(store.settings.functionDays, 30);
      }
      storage.files[_file] = jsonEncode({
        'gear': [
          {
            'gw': gatewayPa,
            'a': 5,
            'f': 99,
            'g': [1, 'zwei', 17],
            'n': 'x' * 500,
          },
        ],
      });
      store
        ..debugReset()
        ..debugAllowLoad();
      await store.load();
      final gear = store.gear(gatewayPa, 5)!;
      expect((gear.faults, gear.name!.length), (null, 120));
      expect(gear.groups, {1});
    });

    test('Demo: eigener Zustand im Speicher, danach ist der der Anlage unverändert zurück', () async {
      store.observe(tg(diag, '010C', at: t0));
      await store.flush();
      final saved = storage.files[_file];
      DemoTunnel.active = true;
      addTearDown(() => DemoTunnel.active = false);
      CatalogStore.instance.beginDemo(demoCatalog());
      expect(store.gateways.single.address, DemoDali.gateway);
      expect(store.gear(DemoDali.gateway, 12)!.name, 'Flur EG Leuchte 2');
      expect(store.gear(DemoDali.gateway, 18)!.emergency, isTrue);
      expect(log.overview(DateTime.now()).where((r) => r.failed).single.gear!.address, 18);
      expect(log.overview(DateTime.now()).where((r) => r.overdue).single.gear!.address, 16);
      // The gateway's own result telegrams bring nothing new into the demo log.
      final before = log.entries.length;
      store.observe(tg(DemoDali.result(18), '1300500000FF', source: DemoDali.gateway));
      expect(log.entries.length, before);
      store.observe(tg(DemoDali.diagnostic, '010C', source: DemoDali.gateway));
      await store.flush();
      CatalogStore.instance.endDemo();
      DemoTunnel.active = false;
      expect(store.gateways.single.address, gatewayPa);
      expect(store.gear(gatewayPa, 12)!.state, DaliState.lampFault);
      expect(log.entries, isEmpty);
      await store.flush();
      expect(storage.files[_file], saved);
    });
  });

  group('Alarme', () {
    test('Mitteilung erst nach 30 s Bestand, je Leuchte, zurück nur nach gemeldetem Fehler', () async {
      final sent = <(String, String, String)>[];
      final on = ValueNotifier(true);
      var server = false;
      var clock = t0;
      final notifier = DaliAlarmNotifier(
        send: ({required id, required title, required body}) async => sent.add((id, title, body)),
        enabled: on,
        serverNotifies: () => server,
        now: () => clock,
      );
      Future<void> at(int seconds) async {
        clock = t0.add(Duration(seconds: seconds));
        notifier.flush();
        await pumpEventQueue();
      }

      store.observe(tg(diag, '000C', at: t0));
      store.editGear(store.gear(gatewayPa, 12)!, name: 'Flur EG Leuchte 2', room: 'Flur EG');
      store.observe(tg(diag, '010C', at: t0.add(const Duration(seconds: 1))));
      store.observe(tg(diag, '010D', at: t0.add(const Duration(seconds: 1))));
      await at(20);
      expect(sent, isEmpty, reason: 'not settled yet');
      await at(31);
      expect(sent.map((s) => s.$2), ['Lampenfehler: Flur EG Leuchte 2', 'Lampenfehler: EVG 13']);
      expect(sent.first.$1, 'knx_dali_$gatewayPa:12');
      expect(sent.first.$3, 'EVG 12 · Flur EG · Gateway 1.1.40 · 12:00:01');
      // Flickering: nothing.
      for (var i = 0; i < 20; i++) {
        store.observe(tg(diag, i.isEven ? '000C' : '010C', at: t0.add(Duration(seconds: 40 + i))));
      }
      await at(70);
      expect(sent.length, 2);
      // Back to normal and holding: reported.
      store.observe(tg(diag, '000C', at: t0.add(const Duration(seconds: 80))));
      await at(111);
      expect(sent.last.$2, 'Wieder in Ordnung: Flur EG Leuchte 2');
      // Off, or the server reports itself: nothing from the app.
      on.value = false;
      store.observe(tg(diag, '0214', at: t0.add(const Duration(seconds: 120))));
      await at(151);
      on.value = true;
      server = true;
      store.observe(tg(diag, '0215', at: t0.add(const Duration(seconds: 160))));
      await at(191);
      expect(sent.length, 3);
      await notifier.dispose();
    });

    test('64 Leuchten zugleich: fünf Mitteilungen und eine Sammelmitteilung; durchgefallener Test meldet', () async {
      final sent = <String>[];
      var clock = t0;
      final notifier = DaliAlarmNotifier(
        send: ({required id, required title, required body}) async => sent.add(title),
        enabled: ValueNotifier(true),
        now: () => clock,
      );
      for (var a = 0; a < 64; a++) {
        store.observe(tg(diag, '01${a.toRadixString(16).padLeft(2, '0')}', at: t0));
      }
      clock = t0.add(const Duration(seconds: 31));
      notifier.flush();
      await pumpEventQueue();
      expect(sent.length, 6);
      expect(sent.last, 'DALI: 59 weitere Leuchten melden Fehler oder Änderungen');
      sent.clear();
      store.observe(tg(ga('5/2/16'), '0300500000FF', at: clock));
      clock = clock.add(const Duration(minutes: 2));
      notifier.flush();
      await pumpEventQueue();
      expect(sent, ['Notlichttest durchgefallen: Notlicht 16']);
      await notifier.dispose();
    });

    test('Die Alarm-Mitteilung je Gruppenadresse lässt die Diagnose-Adresse aus', () async {
      final sent = <String>[];
      final telegrams = [tg(diag, '010C'), tg(diag, '000C')];
      final notifier = AlarmNotifier(
        Stream.fromIterable(telegrams),
        send: ({required id, required title, required body}) async => sent.add(title),
        enabled: ValueNotifier(true),
      );
      await pumpEventQueue();
      expect(sent, isEmpty);
      await notifier.dispose();
    });
  });

  group('Wächter', () {
    test('Vorlage: Regel auf der Diagnose-Adresse, optional eine Leuchte oder Gruppe', () {
      final gw = store.gateways.single;
      final all = daliWatchRules(gw).single;
      expect(all.address, diag);
      expect(all.describe(), 'DALI-Fehler · DALI-Gateway 1.1.40');
      final log = TelegramLog();
      expect(all.matches(tg(diag, '010C'), log), isTrue);
      expect(all.matches(tg(diag, '000C'), log), isFalse);
      expect(all.matches(tg(diag, '018C'), log), isFalse);
      expect(all.matches(tg(diag, '010C', type: TelegramType.read), log), isFalse);
      expect(all.matches(tg(ga('1/7/0'), '010C'), log), isFalse);

      store.observe(tg(diag, '000C'));
      final one = daliWatchRules(gw, target: store.gear(gatewayPa, 12)).single;
      expect(one.matches(tg(diag, '020C'), log), isTrue);
      expect(one.matches(tg(diag, '020D'), log), isFalse);
      expect(one.matches(tg(diag, '024C'), log), isFalse);
      final group = daliWatchRules(gw, target: DaliGroup(gatewayPa, 3)).single;
      expect(group.matches(tg(diag, '0143'), log), isTrue);
      expect(group.matches(tg(diag, '0103'), log), isFalse);
    });

    test('bits geht nur an einen Server, der es kann; ältere Apps feuern nie', () {
      final rule = daliWatchRules(store.gateways.single).single;
      expect(rule.serverCheck(), isNull);
      ServerFeatures.instance.update({
        'features': ['bitsCheck', 'dali', 7],
      });
      expect(rule.serverCheck(), {
        'bits': {'bytes': 2, 'mask': 0x0700, 'zero': 0x80},
      });
      ServerFeatures.instance.update({'state': 'connected'});
      expect(rule.serverCheck(), isNull);
      // Stored and read again; an app that does not know `bits` sees a value no telegram has.
      final json = jsonDecode(jsonEncode(rule.toJson())) as Map<String, Object?>;
      expect(json['value'], 'bits');
      final again = WatchRule.fromJson(json);
      expect(again.bits, rule.bits);
      expect(again.describe(), rule.describe());
      final old = WatchRule.fromJson({...json}..remove('bits'));
      expect(old.matches(tg(diag, '010C'), TelegramLog()), isFalse);
    });
  });

  group('Gesundheitscheck', () {
    List<Telegram> traffic(DateTime from, DateTime to, {int source = 0x110A}) => [
      for (var t = from; t.isBefore(to); t = t.add(const Duration(minutes: 10)))
        tg(ga('2/0/0'), '0C24', at: t, source: source),
    ];

    test('Lampen- und EVG-Fehler je Gateway gezählt, Texte ohne Zugriff auf die Ablage', () {
      store.observe(tg(diag, '010C', at: t0));
      store.observe(tg(diag, '010D', at: t0.add(const Duration(minutes: 5))));
      store.observe(tg(diag, '0203', at: t0));
      final findings = lightingFindings(store: store, tests: const [], telegrams: const [], now: t0);
      expect(findings.map((f) => (f.kind, f.address, f.count)), [
        (FindingKind.lampFault, gatewayPa, 2),
        (FindingKind.gearFault, gatewayPa, 1),
      ]);
      expect(findings.first.since, t0);
      // The finding is the title, the gateway the detail.
      expect(findingTitle(findings.first), '2 Leuchten melden Lampenfehler');
      expect(findingTitle(findings.last), '1 EVG meldet einen Fehler');
      expect(findingDetail(findings.first), '1.1.40  DALI-Gateway');
      expect(findings.first.kind.area, HealthArea.lighting);
      expect(FindingKind.lampFault.device, isTrue);
      expect(HealthFinding.fromJson(findings.first.toJson())!.key, findings.first.key);
    });

    test('Gateway stumm: nur wenn der Bus in der Zeit wirklich mitgehört wurde', () {
      final now = t0.add(const Duration(days: 4));
      store.observe(tg(diag, '000C', at: t0));
      // Nothing heard since: the app was closed, no finding.
      expect(lightingFindings(store: store, tests: const [], telegrams: const [], now: now), isEmpty);
      // Heard the bus for two days without the gateway: finding.
      final heard = traffic(now.subtract(const Duration(hours: 47)), now);
      final silent = lightingFindings(store: store, tests: const [], telegrams: heard, now: now).single;
      expect((silent.kind, silent.address, silent.since), (FindingKind.gatewaySilent, gatewayPa, t0));
      expect(findingTitle(silent), 'Gateway hat sich seit 10.11. 12:00 nicht gemeldet');
      // Only a few hours heard, or the gateway among the senders: no finding.
      expect(
        lightingFindings(
          store: store,
          tests: const [],
          telegrams: traffic(now.subtract(const Duration(hours: 5)), now),
          now: now,
        ),
        isEmpty,
      );
      expect(
        lightingFindings(
          store: store,
          tests: const [],
          telegrams: [
            ...heard,
            tg(ga('1/6/0'), '', bit: 1, at: now.subtract(const Duration(hours: 1))),
          ],
          now: now,
        ),
        isEmpty,
      );
      expect(
        heardFor([t0, t0.add(const Duration(minutes: 10)), t0.add(const Duration(hours: 3))], t0, now).inMinutes,
        10,
      );
    });
  });

  group('Prüfbuch', () {
    EmergencyTest entry(EmergencyTestKind kind, DateTime at, {bool passed = true, String raw = 'AA'}) => EmergencyTest(
      time: at,
      group: ga('5/2/16'),
      gateway: gatewayPa,
      address: 16,
      kind: kind,
      result: passed ? EmergencyResult.passed : EmergencyResult.failed,
      raw: raw,
    );

    test('nur anhängen, nach Jahr getrennt, gleiche Einträge nur einmal', () async {
      log.record([
        entry(EmergencyTestKind.function, DateTime(2025, 12, 30, 2)),
        entry(EmergencyTestKind.function, DateTime(2026, 1, 30, 2)),
      ]);
      log.record([entry(EmergencyTestKind.function, DateTime(2026, 1, 30, 2))]);
      await pumpEventQueue();
      expect(storage.files.keys.where((k) => k.contains('dali_tests')), [
        'installations/default/dali_tests/2025.ndjson',
        'installations/default/dali_tests/2026.ndjson',
      ]);
      final first = storage.files['installations/default/dali_tests/2026.ndjson']!;
      expect(first.trim().split('\n').length, 1);
      log.record([entry(EmergencyTestKind.duration, DateTime(2026, 2, 1, 2), passed: false)]);
      await pumpEventQueue();
      expect(storage.files['installations/default/dali_tests/2026.ndjson'], startsWith(first));

      // Read again, with a broken line in between and a file that is not a log.
      storage.files['installations/default/dali_tests/2026.ndjson'] =
          '${storage.files['installations/default/dali_tests/2026.ndjson']!}kaputt\n';
      storage.files['installations/default/dali_tests/notes.txt'] = 'x';
      log
        ..debugReset()
        ..debugAllowLoad();
      await log.load();
      expect(log.entries.length, 3);
    });

    test('der Server führt das Prüfbuch: die App schreibt nicht mit', () async {
      ServerFeatures.instance.update({
        'features': ['dali'],
      });
      log.record([entry(EmergencyTestKind.function, t0)]);
      await pumpEventQueue();
      expect(log.entries.length, 1);
      expect(storage.files.keys.where((k) => k.contains('dali_tests')), isEmpty);
    });

    test('Übersicht: überfällig, durchgefallen, noch kein Ergebnis', () {
      final now = DateTime(2026, 11, 10);
      expect(log.overview(now).single.open, isTrue);
      expect(log.overview(now).single.overdue, isFalse);
      log.record([
        entry(EmergencyTestKind.function, now.subtract(const Duration(days: 41))),
        entry(EmergencyTestKind.duration, now.subtract(const Duration(days: 9)), passed: false),
      ]);
      final row = log.overview(now).single;
      expect(
        (row.gear!.address, row.functionDue, row.durationDue, row.failed, row.overdue),
        (16, TestDue.overdue, TestDue.current, true, true),
      );
      store.updateSettings((x) => x.functionDays = 90);
      expect(log.overview(now).single.overdue, isFalse);
      final findings = lightingFindings(store: store, tests: log.overview(now), telegrams: const [], now: now);
      expect(findings.map((f) => (f.kind, f.count)), [(FindingKind.testFailed, 1)]);
    });

    test('CSV und Daten fürs PDF: dieselben Spalten, Formeln entschärft', () async {
      final now = DateTime(2026, 11, 10);
      store.editGear(store.gear(gatewayPa, 16)!, name: '=Notleuchte Treppenhaus', room: 'Treppenhaus', emergency: true);
      log.record([
        entry(EmergencyTestKind.duration, now.subtract(const Duration(days: 9)), passed: false, raw: '1300500000FF'),
      ]);
      final data = EmergencyLogData.collect(from: now.subtract(const Duration(days: 30)), to: now);
      expect(data.luminaires.single.attention, isTrue);
      expect(data.luminaires.single.note, 'durchgefallen');
      expect(data.rows.single.address, '16');
      final lines = buildEmergencyCsv(data).trim().split('\r\n');
      expect(lines.length, 2);
      expect(lines.first, startsWith('"Zeit","Leuchte","Raum","DALI-Gateway","DALI-Adresse","Gruppenadresse","Test"'));
      expect(
        lines.last,
        contains('"\'=Notleuchte Treppenhaus","Treppenhaus","1.1.40 EG › Flur/Büro","16","5/2/16","Dauertest"'),
      );
      expect(lines.last, endsWith('"1300500000FF","",""'));
      expect(EmergencyLogData.collect(from: now, to: now).rows, isEmpty);

      // The PDF builds from the same data (many rows: more than one page).
      final many = EmergencyLogData(
        from: data.from,
        to: data.to,
        functionDays: 30,
        durationDays: 365,
        luminaires: data.luminaires,
        rows: [for (var i = 0; i < 120; i++) data.rows.single],
        gaps: [(from: DateTime(2026, 10, 3), to: DateTime(2026, 10, 9))],
      );
      final pdf = await buildPdf(EmergencyLogPdf(many));
      expect(String.fromCharCodes(pdf.take(4)), '%PDF');
      expect(pdf.length, greaterThan(10000));
    });
  });

  group('Inbetriebnahme', () {
    test('Rückmeldung der eigenen Gruppe; von einer anderen: falsche Zuordnung', () async {
      final tunnel = FakeTunnel();
      final g2 = store.group(gatewayPa, 2)!;
      final g3 = store.group(gatewayPa, 3)!;
      tunnel.answer = (dest, {small, required read}) => [
        // The gateway reports group 3's state when group 2 is switched.
        tg(dest == g2.switchGroup ? g3.statusGroup! : ga('1/6/${dest & 0xFF}'), '', bit: small),
      ];
      final own = await switchDaliGroup(tunnel, g3, on: true, window: const Duration(milliseconds: 50));
      expect((own.foreign, own.answeredBy!.group), (false, 3));
      recordDaliSwitch(own);
      final item = Commissioning.instance.items[g3.switchGroup]!;
      expect((item.state, item.foreign, item.value, item.source), (CheckState.seen, false, 'Ein', gatewayPa));

      final wrong = await switchDaliGroup(tunnel, g2, on: true, window: const Duration(milliseconds: 50));
      expect((wrong.foreign, wrong.answeredBy!.group), (true, 3));
      recordDaliSwitch(wrong);
      final flagged = Commissioning.instance.items[g2.switchGroup]!;
      expect(flagged.foreign, isTrue);
      expect(flagged.note, 'Rückmeldung kam von Gruppe 3, geschaltet wurde Gruppe 2.');
      expect(tunnel.writes, [(g3.switchGroup, 1), (g2.switchGroup, 1)]);
      expect(Commissioning.instance.items.keys.toList(), [g2.switchGroup, g3.switchGroup]);

      tunnel.answer = null;
      final silent = await switchDaliGroup(tunnel, g3, on: false, window: const Duration(milliseconds: 20));
      expect(silent.feedback, isNull);
      Commissioning.instance.mark(g3.switchGroup!, CheckState.ok);
      recordDaliSwitch(silent);
      // A rating by hand stays.
      expect(Commissioning.instance.items[g3.switchGroup]!.state, CheckState.ok);
      tunnel.dispose();
    });
  });

  group('Lesen', () {
    test('Diagnose lesen: nur lesbare Objekte des Gateways, nie im Nur-lesen-Modus', () async {
      final tunnel = FakeTunnel();
      expect(store.readableAddresses(), [diag, ga('1/7/0'), ga('1/7/1'), ga('5/1/16'), ga('5/2/16')]);
      tunnel.answer = (dest, {small, required read}) => [
        if (dest == diag) tg(diag, '010C', type: TelegramType.response),
      ];
      final sub = tunnel.telegrams.listen(store.observe);
      expect(DaliStore.canRead(tunnel), isTrue);
      // The sweep waits for late answers; not worth three seconds here.
      final answered = store.readDiagnostics(tunnel);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(tunnel.reads, containsAll([diag, ga('1/7/0')]));
      expect(store.gear(gatewayPa, 12)!.state, DaliState.lampFault);
      expect(await answered, 1);
      await sub.cancel();
      tunnel.dispose();
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('zyklisches Lesen: Standard aus, im Abstand, nicht ohne Verbindung', () async {
      final tunnel = FakeTunnel();
      var now = t0;
      final poller = DaliPoller(tunnel, check: const Duration(days: 1), now: () => now, firstDelay: Duration.zero);
      expect(store.settings.poll, isFalse);
      expect(await poller.tick(), isFalse);
      expect(tunnel.reads, isEmpty);
      store.updateSettings((x) => x.poll = true);
      expect(await poller.tick(), isTrue);
      final once = store.readableAddresses();
      expect(tunnel.reads, once);
      now = now.add(const Duration(minutes: 30));
      expect(await poller.tick(), isFalse);
      now = now.add(const Duration(minutes: 31));
      await tunnel.disconnect();
      expect(await poller.tick(), isFalse);
      expect(tunnel.reads, once);
      // Every gateway reported within the interval (another view read, or it sends by itself):
      // no round.
      await tunnel.connect();
      tunnel.state.value = TunnelState.connected;
      store.observe(tg(diag, '000C', at: now));
      now = now.add(const Duration(minutes: 61));
      store.observe(tg(diag, '000C', at: now.subtract(const Duration(minutes: 5))));
      expect(await poller.tick(), isFalse);
      expect(tunnel.reads, once);
      // The first round waits a random part of the interval.
      final later = DaliPoller(tunnel, check: const Duration(days: 1), now: () => now, random: Random(1));
      expect(await later.tick(), isFalse);
      later.dispose();
      poller.dispose();
      tunnel.dispose();
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  test('Servicebericht: offene Fehler und durchgefallene Tests je Leuchte, in der Sprache des Berichts', () {
    final now = DateTime(2026, 11, 10);
    store.observe(tg(diag, '010C', at: DateTime(2026, 11, 7, 9)));
    store.editGear(store.gear(gatewayPa, 12)!, name: 'Flur EG Leuchte 2');
    log.record([
      EmergencyTest(
        time: DateTime(2026, 11, 1, 2),
        group: ga('5/2/16'),
        gateway: gatewayPa,
        address: 16,
        kind: EmergencyTestKind.duration,
        result: EmergencyResult.failed,
        raw: 'AA',
      ),
    ]);
    final issues = collectDaliIssues(now);
    expect(issues.map((i) => i.kind), [DaliIssueKind.fault, DaliIssueKind.testFailed]);
    final run = HealthRun(
      now,
      [
        HealthFinding(FindingKind.lampFault, gatewayPa, count: 1),
        HealthFinding(FindingKind.gatewaySilent, gatewayPa, since: now),
      ],
      asked: 0,
      answered: 0,
    );
    final lines = buildServiceEvidence(null, run, issues).health;
    expect(lines.map((l) => (l.level, l.title)), [
      (ServiceLevel.watch, 'Gateway hat sich seit 10.11. 00:00 nicht gemeldet'),
      (ServiceLevel.fix, 'Lampenfehler: Flur EG Leuchte 2'),
      (ServiceLevel.fix, 'Notlichttest durchgefallen: Notlicht 16'),
    ]);
    expect(lines[1].detail, 'EVG 12 · Gateway 1.1.40 · seit 07.11.2026');
    expect(lines[2].detail, 'Dauertest am 01.11.2026');
    LocaleController.instance.debugSetLocale(const Locale('en'));
    expect(daliServiceLines(issues).first.title, 'Lamp failure: Flur EG Leuchte 2');
  });
}
