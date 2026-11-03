import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/gateway_info.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/secure/keyring_store.dart';
import 'package:knx_monitor/model/connection_options.dart';
import 'package:knx_monitor/model/health.dart';
import 'package:knx_monitor/model/history_store.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/model/expert_mode.dart';
import 'package:knx_monitor/model/pinned_sections.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/connect_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  final store = InstallationStore.instance;

  String catalog(String project, String name) => jsonEncode({
    'project': project,
    'groups': [
      {'a': 0x0801, 'n': name},
    ],
  });

  GatewayInfo info(String serial, {String name = 'GIRA X1'}) => GatewayInfo(
    name: name,
    medium: 0x02,
    programmingMode: false,
    address: 0x11ff,
    serial: serial,
    mac: 'AA:BB:CC:DD:EE:FF',
    multicast: '224.0.23.12',
    projectInstallation: 0,
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('knx_installations');
    AppStorage.instance = IoStorage(dir);
    store.debugReset();
  });

  tearDown(() => dir.delete(recursive: true));

  group('Ausfallsicherheit', () {
    test('kaputter Index: Sicherung vom letzten Speichern, kaputte Datei bleibt liegen', () async {
      SharedPreferences.setMockInitialValues({});
      await store.load();
      await store.create('Büro');
      await store.create('Lager'); // Zweites Speichern: Sicherung enthält „Büro“.
      await File('${dir.path}/installations.json').writeAsString('{"version":1,"list":[{"id":');
      store.debugReset();
      await store.load();
      expect(store.list.map((i) => i.name), contains('Büro'));
      final corrupt = await dir.list().where((e) => e.path.contains('installations.json.corrupt-')).toList();
      expect(corrupt, hasLength(1));
    });

    test('ein kaputter Eintrag nimmt die anderen nicht mit', () async {
      SharedPreferences.setMockInitialValues({});
      await File('${dir.path}/installations.json').writeAsString(
        jsonEncode({
          'version': 2,
          'list': [
            {'id': 'aaaaaaaaaaaa', 'name': 'Musterhaus', 'created': 0},
            {'id': 42},
          ],
        }),
      );
      await store.load();
      expect(store.list.map((i) => i.name), ['Musterhaus']);
    });
  });

  test('Migration: bisherige Daten werden die erste Installation', () async {
    SharedPreferences.setMockInitialValues({
      'gateway_host': '192.168.1.22',
      'gateway_port': 3671,
      'conn_mode': 'tcp',
      'pinned_sections': ['ga:2049'],
      'charts:WalkenBock': '{}',
      'history_days': 7, // bleibt global
    });
    FlutterSecureStorage.setMockInitialValues({'knx_keyring': '{"project":"WalkenBock"}'});
    await AppStorage.instance.write('catalog.json', catalog('WalkenBock', 'Licht'));
    await AppStorage.instance.write('health.json', '{}');
    await AppStorage.instance.write('history/2026-10-19.ndjson', '{}\n');

    await store.load();

    final i = store.active;
    expect(store.list, hasLength(1));
    expect(i.name, 'WalkenBock');
    expect(i.gateway?.host, '192.168.1.22');
    expect(await AppStorage.instance.read('catalog.json'), isNull);
    expect(await AppStorage.instance.read('installations/${i.id}/catalog.json'), isNotNull);
    expect(await AppStorage.instance.read('installations/${i.id}/history/2026-10-19.ndjson'), '{}\n');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('gateway_host'), isNull);
    expect(prefs.getString(store.key('gateway_host')), '192.168.1.22');
    expect(prefs.getString(store.key('charts:WalkenBock')), '{}');
    expect(prefs.getInt('history_days'), 7);

    await KeyringStore.instance.reload();
    expect(KeyringStore.instance.project, 'WalkenBock');
    await ConnectionOptions.instance.load();
    expect(ConnectionOptions.instance.mode, ConnectionMode.tcp);

    // Zweiter Start: keine erneute Migration.
    store.debugReset();
    await store.load();
    expect(store.list.single.id, i.id);
  });

  test('Start unter Last: Installationen nach der Frist – Projekt wird nachgeladen', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    // Erster Lauf legt die Installation an und verschiebt das Projekt hinein.
    await AppStorage.instance.write('catalog.json', catalog('WalkenBock', 'Licht'));
    await store.load();
    store.debugReset();
    CatalogStore.instance.catalog = GroupCatalog.empty;

    final slow = Completer<void>();
    final storesLoaded = Completer<void>();
    var notified = 0;
    void count() => notified++;
    store.addListener(count);
    addTearDown(() => store.removeListener(count));
    await store.loadWithin(
      const Duration(milliseconds: 10),
      storesLoaded: storesLoaded.future,
      load: () => slow.future.then((_) => store.load()),
    );
    // Start geht weiter: die Stores laden zunächst ohne Installation.
    await CatalogStore.instance.reload();
    expect(CatalogStore.instance.catalog.projectName, isNot('WalkenBock'));
    storesLoaded.complete();

    slow.complete();
    await pumpEventQueue();
    for (var i = 0; i < 50 && CatalogStore.instance.catalog.projectName != 'WalkenBock'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(CatalogStore.instance.catalog.projectName, 'WalkenBock');
    expect(notified, greaterThanOrEqualTo(2), reason: 'Verbinden-Bildschirm hört auf die Installationen');
  });

  test('Wechsel lädt Projekt, Keyring, Gesundheit und Einstellungen der Installation', () async {
    SharedPreferences.setMockInitialValues({
      'pinned_sections': ['ga:2049'],
    });
    FlutterSecureStorage.setMockInitialValues({});
    await AppStorage.instance.write('catalog.json', catalog('Kunde A', 'Licht A'));
    await store.load();
    final a = store.active;
    await InstallationStore.reloadStores();
    expect(CatalogStore.instance.catalog.projectName, 'Kunde A');
    expect(PinnedSections.instance.contains('ga:2049'), isTrue);

    final b = await store.create('Kunde B');
    await store.switchTo(b.id);
    expect(store.active.id, b.id);
    expect(CatalogStore.instance.catalog.groups, isEmpty);
    expect(PinnedSections.instance.contains('ga:2049'), isFalse);
    expect(HealthCheck.instance.runs, isEmpty);

    // In B importieren, zurück zu A: A unverändert, B behält seins.
    await InstallationStore.instance.storage.write('catalog.json', catalog('Kunde B', 'Licht B'));
    ConnectionOptions.instance.mode = ConnectionMode.routing;
    await ConnectionOptions.instance.save();
    await store.switchTo(a.id);
    expect(CatalogStore.instance.catalog.projectName, 'Kunde A');
    expect(ConnectionOptions.instance.mode, ConnectionMode.udp);
    await store.switchTo(b.id);
    expect(CatalogStore.instance.catalog.projectName, 'Kunde B');
    expect(ConnectionOptions.instance.mode, ConnectionMode.routing);

    // Neueste Nutzung zuerst.
    expect(store.list.first.id, b.id);
  });

  test('Gateway: Seriennummer merken, Adresswechsel erkennen, Aufnahmen zuordnen', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await store.load();
    await store.rememberGateway('192.168.1.22', 3671, info: info('00C5:0E2A1B3C'));
    final a = store.active;
    expect(a.gateway?.serial, '00C5:0E2A1B3C');
    expect(a.gateway?.name, 'GIRA X1');
    expect(store.bySerial('00C5:0E2A1B3C')?.id, a.id);
    expect(store.byHost('192.168.1.22', 3671)?.id, a.id);

    // Neue IP: beim Verbinden ist das Gerät noch unbekannt, seine Antwort
    // bringt die Seriennummer – gleiches Gerät, Adresse folgt.
    await store.rememberGateway('192.168.1.40', 3671);
    expect(store.active.gateway?.serial, isNull);
    await store.rememberGateway('192.168.1.40', 3671, info: info('00C5:0E2A1B3C'));
    expect(store.active.gateway?.serial, '00C5:0E2A1B3C');
    expect(store.active.gateway?.host, '192.168.1.40');

    expect(store.forRecording(installation: a.id)?.id, a.id);
    expect(store.forRecording(gateway: 'GIRA X1 · 192.168.1.40')?.id, a.id);
    expect(store.forRecording(gateway: 'Anderes · 10.0.0.1'), isNull);
  });

  test('Löschen entfernt Dateien und Einstellungen, nicht die aktive', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await store.load();
    final b = await store.create('Weg damit');
    final storage = ScopedStorage(AppStorage.instance, 'installations/${b.id}/');
    await storage.write('catalog.json', '{}');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(InstallationStore.scopedKey(b.id, 'gateway_host'), '10.0.0.1');

    await store.delete(store.active.id);
    expect(store.list, hasLength(2));

    await store.delete(b.id);
    expect(store.list, hasLength(1));
    expect(await storage.read('catalog.json'), isNull);
    expect(prefs.getString(InstallationStore.scopedKey(b.id, 'gateway_host')), isNull);
  });

  test('ScopedStorage legt Pfade unter das Präfix', () async {
    final s = ScopedStorage(AppStorage.instance, 'installations/x/');
    await s.write('history/a.ndjson', '1');
    await s.append('history/a.ndjson', '2');
    expect(await AppStorage.instance.read('installations/x/history/a.ndjson'), '12');
    expect((await s.list('history')).single.name, 'a.ndjson');
    await s.delete('history/a.ndjson');
    expect(await s.read('history/a.ndjson'), isNull);
  });

  testWidgets('Verbinden-Bildschirm: Installation als Kachel, Wechsel über ihr Menü im Expertenmodus', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await store.load();
      await store.rename(store.active.id, 'Büro Nord');
      await store.create('Baustelle Süd', gateway: const GatewayRef(host: '10.0.0.9'));
    });
    await ExpertMode.instance.set(false);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const ConnectScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Baustelle Süd'), findsNothing);
    expect(find.text('Demo ansehen'), findsOneWidget);

    await ExpertMode.instance.set(true);
    await tester.pumpAndSettle();
    // Die aktive Installation steht als Kachel über der Verbindung.
    expect(find.text('Büro Nord'), findsOneWidget);
    // Demo auch für Fachleute, Aufnahmen kommen dazu.
    expect(find.text('Demo ansehen'), findsOneWidget);
    expect(find.text('Aufnahmen'), findsOneWidget);
    // Das Menü der Kachel bietet die andere Installation zum Wechseln an.
    await tester.tap(find.text('Wechseln'));
    await tester.pumpAndSettle();
    expect(find.text('Baustelle Süd'), findsOneWidget);
    await tester.tapAt(Offset.zero); // Menü schließen
    await tester.pumpAndSettle();
    // Nach dem Wechsel steht ihr Gateway im Feld.
    await tester.runAsync(() => store.switchTo(store.list.firstWhere((i) => i.name == 'Baustelle Süd').id));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('10.0.0.9'), findsOneWidget);
    await ExpertMode.instance.set(false);
  });

  test('Langzeitverlauf je Installation, auch einer nicht aktiven', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await store.load();
    final a = store.active;
    final b = await store.create('Kunde B');
    await ScopedStorage(AppStorage.instance, 'installations/${b.id}/').write('history/2026-10-12.ndjson', '{}\n');
    await InstallationStore.instance.storage.write('history/2026-10-19.ndjson', '{}\n');

    final history = HistoryStore.instance;
    expect([for (final d in await history.days()) d.date.day], [19]);
    final other = await history.days(installation: b.id);
    expect([for (final d in other) d.date.day], [12]);
    expect(other.single.installation, b.id);
    expect(store.active.id, a.id); // nur angesehen, nicht gewechselt
  });
}
