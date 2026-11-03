import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/export/diagnostics_bundle.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/secure/data_secure.dart';
import 'package:knx_monitor/knx/secure/keyring.dart';
import 'package:knx_monitor/knx/secure/keyring_store.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/annotation.dart';
import 'package:knx_monitor/model/bus_replay.dart';
import 'package:knx_monitor/model/connection_options.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/model/recording.dart';
import 'package:knx_monitor/monitor_model.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/findings_screen.dart';
import 'package:knx_monitor/ui/recordings_screen.dart';
import 'package:knx_monitor/ui/support_package_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final start = DateTime(2026, 10, 21, 14, 0);
  final light = parseGroup('1/2/3')!;
  final heating = parseGroup('3/1/0')!;
  final secured = parseGroup('4/0/1')!;
  final actuator = parseIndividual('1.1.18')!;

  Telegram t(int sec, int ga, List<int> data, {bool small = false}) => Telegram(
    time: start.add(Duration(seconds: sec)),
    source: actuator,
    destination: ga,
    type: TelegramType.write,
    data: Uint8List.fromList(data),
    isSmall: small,
    // Zusatzinfo im cEMI (KNX RF trägt dort die Seriennummer).
    raw: Uint8List.fromList([0x29, 0x08, 0x02, 0x06, 0x00, 0x83, 0x00, 0x1A, 0x2B, 0x3C, 0xBC, 0xE0]),
  );

  final telegrams = [
    t(0, light, [1], small: true),
    t(30, heating, [0x0C, 0x24]),
    t(60, secured, [0xAB, 0xCD]),
    t(600, light, [0], small: true),
  ];

  GroupCatalog catalog() => GroupCatalog(
    {
      light: GroupInfo(address: light, name: 'Licht Küche', path: 'Beleuchtung › Schalten', dpt: const Dpt(1, 1)),
      heating: GroupInfo(
        address: heating,
        name: 'Heizung Bad',
        dpt: const Dpt(9, 1),
        description: 'Fühler an 192.168.1.40',
        links: [GroupLink(device: actuator, object: 4, text: 'Ist-Temperatur')],
      ),
      secured: GroupInfo(address: secured, name: 'Tür Garage', dpt: const Dpt(1, 1)),
    },
    devices: {
      actuator: DeviceInfo(
        address: actuator,
        name: 'Heizungsaktor EG',
        product: 'AKH-0800.03',
        manufacturer: 'MDT',
        location: 'Haus Müller › EG › Bad',
        serial: '0083001A2B3C',
      ),
    },
    projectName: 'Haus Müller',
  );

  const logLines = [
    'SocketException: Connection refused (OS Error, errno = 61), address = 192.168.178.22, port = 3671',
    'mDNS: knx-gateway.fritz.box an fe80::1c2b:3aff:fe4d:5e6f%en0, MAC 00:24:6D:01:02:03',
    'Konto: daniel@example.com, Box https://10.42.0.1:8099/api',
    'Gateway Seriennummer 0083:1A2B3C4D',
  ];

  DiagnosticsPackage build({bool keepNames = true, DateTime? from, DateTime? to}) => buildDiagnosticsPackage(
    telegrams: telegrams,
    catalog: catalog(),
    overrides: {heating: const Dpt(9, 1)},
    secureAddresses: {secured},
    occurred: start.add(const Duration(minutes: 1)),
    from: from,
    to: to,
    problem: 'Licht geht nicht an, Gateway 192.168.1.22 im Ferienhaus Müller',
    expected: 'Licht an',
    keepNames: keepNames,
    technical: {
      'connection': {'kind': 'TCP', 'error': 'Keine Antwort von 192.168.1.22:3671'},
      'gateway': {'name': 'MDT IP Interface', 'medium': 'TP1'},
    },
    log: logLines,
    knownNames: ['Ferienhaus Müller'],
    now: start.add(const Duration(minutes: 20)),
  );

  /// Alle Dateien im ZIP als ein Text.
  String zipText(Uint8List zip) =>
      [for (final f in ZipDecoder().decodeBytes(zip).files) utf8.decode(f.content, allowMalformed: true)].join('\n');

  group('Anonymisierung', () {
    test('keine IP-Adressen, Hosts, MAC, Seriennummern, E-Mail oder privaten Namen', () {
      final text = zipText(build().toZip());
      for (final banned in [
        '192.168.',
        '10.42.0.1',
        'fe80',
        '00:24:6D',
        '0083001A2B3C',
        '0083:1A2B3C4D',
        '001A2B3C',
        'example.com',
        'fritz.box',
        'Haus Müller',
        'Ferienhaus',
      ]) {
        expect(text, isNot(contains(banned)), reason: banned);
      }
      // Was für die Auswertung bleibt.
      expect(text, contains('Licht Küche'));
      expect(text, contains('Heizungsaktor EG'));
      expect(text, contains('MDT IP Interface'));
      expect(text, contains('Connection refused'));
    });

    test('Projekt- und Installationsname werden Platzhalter, Seriennummern fehlen', () {
      final p = build();
      expect(p.catalog.projectName, placeholderProject);
      expect(p.recording.project, placeholderProject);
      expect(p.recording.gateway, isNull);
      expect(p.recording.installation, isNull);
      expect(p.catalog.devices[actuator]!.serial, isNull);
      // Ohne cEMI-Rohdaten (Zusatzinfos können Kennungen tragen).
      expect(p.recording.telegrams.every((t) => t.raw.isEmpty), isTrue);
    });

    test('ohne Namen: Adressen und Produkte statt Namen, Orte und Beschreibungen', () {
      final p = build(keepNames: false);
      final text = zipText(p.toZip());
      for (final name in [
        'Licht Küche',
        'Heizung Bad',
        'Heizungsaktor EG',
        'Beleuchtung',
        'Ist-Temperatur',
        'EG › Bad',
      ]) {
        expect(text, isNot(contains(name)), reason: name);
      }
      expect(p.catalog[light]!.name, '1/2/3');
      expect(p.catalog.devices[actuator]!.name, 'AKH-0800.03');
      expect(p.catalog[heating]!.dpt, const Dpt(9, 1));
      expect(p.namesIncluded, isFalse);
    });

    test('Data Secure nur mit Zeit und Adressen, ohne Inhalt', () {
      final p = build();
      expect(p.recording.telegrams.where((t) => t.destination == secured), isEmpty);
      expect(p.secureTelegrams.single.destination, secured);
      expect(p.secureTelegrams.single.source, actuator);
      final recording = utf8.decode(ZipDecoder().decodeBytes(p.toZip()).findFile('recording.json')!.content);
      expect(recording.toLowerCase(), isNot(contains('abcd')));
    });

    test('Technik enthält keine Keyring-Schlüssel oder Passwörter', () async {
      SharedPreferences.setMockInitialValues({});
      PackageInfo.setMockInitialValues(
        appName: 'KNX Monitor',
        packageName: 'knx_monitor',
        version: '1.5.1',
        buildNumber: '6',
        buildSignature: '',
      );
      final key = Uint8List.fromList(List.generate(16, (i) => 0xA0 + i));
      final keys = KeyringStore.instance;
      keys.dataSecure = DataSecure(Keyring(project: 'Haus Müller', groupKeys: {secured: key}));
      keys.project = 'Haus Müller';
      final options = ConnectionOptions.instance
        ..mode = ConnectionMode.secure
        ..secureUserPassword = 'Tunnel-Passwort-1'
        ..secureDeviceAuthentication = 'Geraete-Code-2';
      addTearDown(() {
        keys.dataSecure = null;
        keys.project = null;
        options
          ..mode = ConnectionMode.udp
          ..secureUserPassword = ''
          ..secureDeviceAuthentication = '';
      });

      final technical = await collectTechnical();
      expect(secureGroupAddresses(), {secured});
      final p = buildDiagnosticsPackage(
        telegrams: telegrams,
        catalog: catalog(),
        secureAddresses: secureGroupAddresses(),
        occurred: start,
        technical: technical,
        knownNames: [?keys.project],
      );
      final text = zipText(p.toZip());
      final keyHex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(text.toLowerCase(), isNot(contains(keyHex)));
      expect(text, isNot(contains(base64.encode(key))));
      expect(text, isNot(contains('Tunnel-Passwort-1')));
      expect(text, isNot(contains('Geraete-Code-2')));
      expect(text, isNot(contains('Haus Müller')));
      final manifest = jsonDecode(
        utf8.decode(ZipDecoder().decodeBytes(p.toZip()).findFile('diagnostics.json')!.content),
      );
      final tech = (manifest as Map)['technical'] as Map;
      expect(tech['app'], containsPair('version', '1.5.1'));
      expect(tech['connection'], containsPair('kind', 'IP Secure'));
      expect(tech['secure'], containsPair('groupKeyCount', 1));
    });

    test('Scrubber lässt KNX-Adressen und Uhrzeiten stehen', () {
      final scrub = Scrubber();
      expect(scrub('1.1.18 an 1/2/3 um 14:02:33.123'), '1.1.18 an 1/2/3 um 14:02:33.123');
      expect(scrub('2026-10-21T14:02:33.123456 Fehler'), '2026-10-21T14:02:33.123456 Fehler');
      expect(scrub('Gateway 192.168.1.22:3671'), 'Gateway <ip>');
    });
  });

  group('Screenshots und Filter', () {
    final bytes = Uint8List.fromList([0xFF, 0xD8, 9]);

    DiagnosticsPackage withShots({required bool include}) => buildDiagnosticsPackage(
      telegrams: telegrams,
      catalog: catalog(),
      occurred: start,
      annotations: [
        Annotation(id: 'a', time: start, note: 'dunkel', shots: ['s1']),
      ],
      shots: {'s1': bytes, 's2': bytes},
      packageShots: ['s2'],
      includeShots: include,
      now: start,
    );

    test('ohne Zustimmung kein Bild im Paket, auch keine Verweise', () {
      final p = withShots(include: false);
      expect(p.shots, isEmpty);
      expect(p.packageShots, isEmpty);
      expect(p.recording.annotations.single.shots, isEmpty);
      expect(p.recording.annotations.single.note, 'dunkel');
      expect(p.manifest.containsKey('shots'), isFalse);
      final names = ZipDecoder().decodeBytes(p.toZip()).files.map((f) => f.name);
      expect(names.where((n) => n.startsWith('shots/')), isEmpty);
    });

    test('mit Zustimmung sind die Bilder drin', () {
      final p = withShots(include: true);
      expect(p.shots.keys.toSet(), {'s1', 's2'});
      expect(p.recording.annotations.single.shots, ['s1']);
    });

    test('IP-Adressen und Kennungen fehlen in allen Textdateien', () {
      final p = buildDiagnosticsPackage(
        telegrams: telegrams,
        catalog: catalog(),
        occurred: start,
        problem: 'Gateway 192.168.1.22 und fe80::1%en0, Mail anna@example.com, Host knx.fritz.box',
        technical: {
          'connection': {'error': 'Keine Antwort von 10.0.0.5:3671'},
        },
        log: ['verbunden mit 2001:db8:0:0:0:0:0:1', 'MAC 00:0e:8c:12:34:56', 'https://10.42.0.1:8099/api'],
        annotations: [Annotation(id: 'a', time: start, note: 'Kommentar 172.16.0.9')],
        now: start,
      );
      final all = p.files.values.join('\n');
      for (final secret in [
        '192.168.1.22',
        'fe80::1',
        'anna@example.com',
        'knx.fritz.box',
        '10.0.0.5',
        '2001:db8',
        '00:0e:8c:12:34:56',
        '10.42.0.1',
        '172.16.0.9',
      ]) {
        expect(all, isNot(contains(secret)), reason: secret);
      }
    });

    test('bekannte Namen gehen, frei getippte Personennamen bleiben: darum kein „ohne persönliche Daten“', () {
      final p = buildDiagnosticsPackage(
        telegrams: const [],
        catalog: GroupCatalog.empty,
        occurred: start,
        problem: 'Herr Schmidt von Elektro Meier sagt, es geht nicht',
        // Betriebsname und Mitglieder aus Pro Team (Team.privateNames).
        knownNames: ['Elektro Meier', 'Anna Beispiel'],
        log: ['Anna Beispiel hat gesendet'],
        now: start,
      );
      expect(p.problem, isNot(contains('Elektro Meier')));
      expect(p.log.single, isNot(contains('Anna Beispiel')));
      expect(p.problem, contains('Herr Schmidt'));
    });
  });

  group('Export → Import', () {
    test('Paket öffnet sich mit Projekt und abspielbarer Aufnahme', () {
      final exported = build();
      final zip = exported.toZip();
      expect(DiagnosticsPackage.looksLikeZip(zip), isTrue);
      final back = DiagnosticsPackage.fromZip(zip);

      expect(back.problem, startsWith('Licht geht nicht an'));
      expect(back.expected, 'Licht an');
      expect(back.occurred, exported.occurred);
      expect(back.namesIncluded, isTrue);
      expect(back.catalog.length, 3);
      expect(back.catalog[light]!.name, 'Licht Küche');
      expect(back.catalog[heating]!.links.single.device, actuator);
      expect(back.catalog.devices[actuator]!.name, 'Heizungsaktor EG');
      expect(back.overrides, {heating: const Dpt(9, 1)});
      expect(back.secureTelegrams.single.time, start.add(const Duration(minutes: 1)));
      expect(back.log, hasLength(logLines.length));
      expect(back.technical['gateway'], containsPair('name', 'MDT IP Interface'));

      final r = back.recording;
      expect(r.telegrams, hasLength(3));
      expect(r.telegrams[1].data, [0x0C, 0x24]);
      expect(r.telegrams.first.isSmall, isTrue);
      expect(r.started, start);
      expect(r.ended, start.add(const Duration(minutes: 10)));

      // Wiedergabe in der App: der Player baut den Stand bis zur Position auf.
      final log = RecordingLog(r);
      final player = RecordingPlayer(log)..seek(const Duration(minutes: 1));
      expect(log.log, hasLength(2));
      player.seek(r.duration);
      expect(log.log, hasLength(3));
      expect(BusReplay.writesOf(r.telegrams), hasLength(3));
      player.dispose();
      log.dispose();
    });

    test('Zeitraum um den Fehler begrenzt die Aufzeichnung', () {
      final p = build(from: start, to: start.add(const Duration(minutes: 2)));
      expect(p.recording.telegrams, hasLength(2));
      expect(p.secureTelegrams, hasLength(1));
      expect(p.recording.started, start);
      expect(p.recording.ended, start.add(const Duration(minutes: 2)));
    });

    test('fremde oder neuere Dateien werden abgelehnt', () {
      expect(() => DiagnosticsPackage.fromZip(Uint8List.fromList(utf8.encode('kein zip'))), throwsFormatException);
      Uint8List zipWith(Map<String, Object?> manifest) {
        final bytes = utf8.encode(jsonEncode(manifest));
        return Uint8List.fromList(
          ZipEncoder().encode(Archive()..addFile(ArchiveFile('diagnostics.json', bytes.length, bytes))),
        );
      }

      expect(() => DiagnosticsPackage.fromZip(zipWith({'format': 'etwas'})), throwsFormatException);
      expect(
        () =>
            DiagnosticsPackage.fromZip(zipWith({'format': diagnosticsFormat, 'version': diagnosticsFormatVersion + 1})),
        throwsFormatException,
      );
      expect(
        () => DiagnosticsPackage.fromZip(zipWith({'format': diagnosticsFormat, 'version': 1})),
        throwsFormatException,
      );
    });
  });

  testWidgets('Import in der App: neue Installation mit Projekt, Aufnahme im Player', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(tester.view.reset);
    final dir = await tester.runAsync(() => Directory.systemTemp.createTemp('knx_diag'));
    addTearDown(() => dir!.delete(recursive: true));
    AppStorage.instance = IoStorage(dir!);
    final installations = InstallationStore.instance..debugReset();
    await tester.runAsync(installations.load);
    final before = installations.active.id;
    final zip = build().toZip();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => openSupportPackage(context, zip), child: const Text('öffnen')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('öffnen'));
    // Der Import schreibt echte Dateien. Unter Last (volle Suite parallel)
    // dauert das länger als eine Sekunde, darum eine Frist in echter Zeit
    // statt einer festen Zahl von Runden.
    final waited = Stopwatch()..start();
    while (find.byType(FindingsScreen).evaluate().isEmpty && waited.elapsed < const Duration(seconds: 15)) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 1));

    // Erst der Befund, darunter die Aufnahme mit Player.
    expect(find.byType(FindingsScreen), findsOneWidget);
    expect(find.byType(RecordingScreen, skipOffstage: false), findsOneWidget);
    expect(installations.active.id, isNot(before));
    expect(installations.active.name, startsWith('Diagnose'));
    expect(CatalogStore.instance.catalog[light]!.name, 'Licht Küche');
    expect(CatalogStore.instance.overrides, {heating: const Dpt(9, 1)});
    final saved = RecordingStore.instance.summaries.single;
    expect(saved.installation, installations.active.id);
    expect(saved.count, 3);
    expect(saved.note, contains('Licht geht nicht an'));
    expect(saved.diagnostics, isTrue);
    installations.debugReset();
  });

  testWidgets('Export-Bildschirm zeigt Inhalt und Namen-Schalter', (tester) async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'KNX Monitor',
      packageName: 'knx_monitor',
      version: '1.5.1',
      buildNumber: '6',
      buildSignature: '',
    );
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = await tester.runAsync(() => Directory.systemTemp.createTemp('knx_diag'));
    addTearDown(() => dir!.delete(recursive: true));
    AppStorage.instance = IoStorage(dir!);
    InstallationStore.instance.debugReset();
    await tester.runAsync(InstallationStore.instance.load);
    await tester.runAsync(() => CatalogStore.instance.adopt(catalog(), name: 'test.knxproj'));
    final log = TelegramLog()..addAll(telegrams);
    // Keyring mit Schlüssel für die gesicherte Adresse.
    KeyringStore.instance.dataSecure = DataSecure(Keyring(project: 'P', groupKeys: {secured: Uint8List(16)}));
    addTearDown(() => KeyringStore.instance.dataSecure = null);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SupportPackageScreen(log: log, error: 'Verbindung verloren'),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.text('Verbindung verloren'), findsOneWidget);
    expect(find.textContaining('Laufende Sitzung'), findsOneWidget);
    expect(find.textContaining('„Licht Küche“'), findsOneWidget);
    expect(find.text('Namen von Gruppenadressen und Geräten: enthalten'), findsOneWidget);
    // Ganze Aufzeichnung: drei normale, ein Data-Secure-Telegramm.
    await tester.tap(find.text('Alles'));
    await tester.pump();
    expect(find.textContaining('Busaufzeichnung: 3 Telegramme'), findsOneWidget);
    expect(find.textContaining('Data Secure: 1 Telegramme'), findsOneWidget);

    await tester.tap(find.text('Namen mitsenden'));
    await tester.pump();
    expect(find.text('Namen von Gruppenadressen und Geräten: entfernt'), findsOneWidget);
    // Der Inhalt sagt offen, was nicht gefiltert wird.
    expect(find.textContaining('Nicht gefiltert:'), findsOneWidget);
    // Ohne Screenshots kein Schalter dazu.
    expect(find.text('Screenshots mitsenden'), findsNothing);
    // Testplattform Android: Teilen-Menü.
    expect(find.text('Paket teilen'), findsOneWidget);
    await tester.runAsync(CatalogStore.instance.clear);
    InstallationStore.instance.debugReset();
    log.dispose();
  });

  test('Monitor behält für den Export die ganze Sitzung, nicht nur die angezeigten 5000', () {
    final tunnel = KnxTunnel('test');
    final model = MonitorModel(tunnel);
    for (var i = 0; i < 6000; i++) {
      model.add(t(i, light, [i & 1], small: true));
    }
    expect(model.log, hasLength(5000));
    expect(model.session, hasLength(6000));
    expect(model.session.first.time, start);
    model.dispose();
    tunnel.dispose();
  });

  /// Pumpt, bis [finder] etwas findet. Der Bildschirm liest echte Dateien;
  /// unter Last (volle Suite parallel) dauert das, darum eine Frist in echter
  /// Zeit statt einer festen Zahl von Runden.
  Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
    final waited = Stopwatch()..start();
    while (finder.evaluate().isEmpty && waited.elapsed < const Duration(seconds: 15)) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  Future<void> pumpScreen(WidgetTester tester, Widget screen, {required Finder until}) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: screen));
    await pumpUntil(tester, until);
  }

  Future<void> setUpStorage(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'KNX Monitor',
      packageName: 'knx_monitor',
      version: '1.5.1',
      buildNumber: '6',
      buildSignature: '',
    );
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = await tester.runAsync(() => Directory.systemTemp.createTemp('knx_diag'));
    addTearDown(() => dir!.delete(recursive: true));
    AppStorage.instance = IoStorage(dir!);
    InstallationStore.instance.debugReset();
    addTearDown(InstallationStore.instance.debugReset);
    await tester.runAsync(InstallationStore.instance.load);
  }

  testWidgets('Screenshot am Kommentar: Schalter steht auf aus, Hinweis und Inhalt sagen es', (tester) async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'KNX Monitor',
      packageName: 'knx_monitor',
      version: '1.5.1',
      buildNumber: '6',
      buildSignature: '',
    );
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = await tester.runAsync(() => Directory.systemTemp.createTemp('knx_diag'));
    addTearDown(() => dir!.delete(recursive: true));
    AppStorage.instance = IoStorage(dir!);
    InstallationStore.instance.debugReset();
    await tester.runAsync(InstallationStore.instance.load);
    await tester.runAsync(AnnotationStore.instance.load);
    final now = DateTime.now();
    await tester.runAsync(() => AnnotationStore.instance.add(Annotation(id: 'a', time: now, note: 'x', shots: ['s1'])));
    addTearDown(() => AnnotationStore.instance.debugReset());
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const SupportPackageScreen()));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    final toggle = find.widgetWithText(SwitchListTile, 'Screenshots mitsenden');
    expect(toggle, findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.textContaining('Bilder werden nicht gefiltert'), findsOneWidget);
    expect(find.text('Screenshots: 1 vorhanden, nicht enthalten'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pump();
    expect(find.text('Screenshots: 1 vorhanden, nicht enthalten'), findsNothing);
    expect(find.textContaining('1 Screenshot'), findsOneWidget);
  });

  testWidgets('Export-Bildschirm nimmt die ganze Sitzung', (tester) async {
    await setUpStorage(tester);
    final session = [
      for (var i = 0; i < 6000; i++) t(i, light, [i & 1], small: true),
    ];
    final log = TelegramLog(maxEntries: 5000)..addAll(session);
    final source = find.text('Laufende Sitzung · 6000 Telegramme');
    await pumpScreen(
      tester,
      SupportPackageScreen(log: log, session: session),
      until: source,
    );
    expect(source, findsOneWidget);
    await tester.tap(find.text('Alles'));
    await tester.pump();
    expect(find.textContaining('Busaufzeichnung: 6000 Telegramme'), findsOneWidget);
    log.dispose();
  });

  testWidgets('Ohne Sitzung und Aufnahme: Tag aus dem Langzeitverlauf als Quelle', (tester) async {
    await setUpStorage(tester);
    final lines = [for (final x in telegrams) jsonEncode(x.toJson())].join('\n');
    await tester.runAsync(() => InstallationStore.instance.storage.write('history/2026-10-21.ndjson', '$lines\n'));
    final source = find.text('Langzeitverlauf 21.10.2026');
    await pumpScreen(tester, const SupportPackageScreen(), until: source);
    expect(source, findsOneWidget);
    await tester.tap(find.text('Alles'));
    final all = find.textContaining('Busaufzeichnung: 4 Telegramme');
    await pumpUntil(tester, all);
    expect(all, findsOneWidget);
  });

  testWidgets('Ohne Sitzung: jüngerer Verlaufstag schlägt ältere Aufnahme', (tester) async {
    await setUpStorage(tester);
    final lines = [for (final x in telegrams) jsonEncode(x.toJson())].join('\n');
    await tester.runAsync(() async {
      await InstallationStore.instance.storage.write('history/2026-10-21.ndjson', '$lines\n');
      final old = DateTime(2026, 10, 1, 9);
      await RecordingStore.instance.save(
        Recording(
          id: 'alt',
          name: 'Alte Aufnahme',
          started: old,
          ended: old.add(const Duration(minutes: 5)),
          telegrams: telegrams,
        ),
      );
    });
    final source = find.text('Langzeitverlauf 21.10.2026');
    await pumpScreen(tester, const SupportPackageScreen(), until: source);
    expect(source, findsOneWidget);
  });
}
