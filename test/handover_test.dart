import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/export/diagnostics_bundle.dart';
import 'package:knx_monitor/export/handover_package.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/secure/keyring_store.dart';
import 'package:knx_monitor/knx/secure/package_crypto.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/annotation.dart';
import 'package:knx_monitor/model/company.dart';
import 'package:knx_monitor/model/connection_options.dart';
import 'package:knx_monitor/model/customer.dart';
import 'package:knx_monitor/model/handover.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/model/plan.dart';
import 'package:knx_monitor/model/recording.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/handover_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _hex(String s) =>
    Uint8List.fromList([for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
String _toHex(List<int> b) => b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();

const _secretKey = 'MTIzNDU2Nzg5MDEyMzQ1Ng=='; // 16 Byte, base64

final _catalog = GroupCatalog(
  {0x0801: const GroupInfo(address: 0x0801, name: 'Licht Küche', path: 'EG › Küche', dpt: Dpt(1, 1))},
  devices: {
    0x1101: const DeviceInfo(
      address: 0x1101,
      name: 'Aktor',
      location: 'Keller',
      serial: '0083AABBCCDD',
      description: 'interne Notiz',
    ),
  },
  projectName: 'Haus Muster',
);

HandoverPackage _package({Map<String, Object?>? keyring}) => HandoverPackage(
  id: 'paket1',
  created: DateTime(2026, 10, 30, 12),
  installationName: 'Haus Muster',
  contact: const PackageContact(name: 'Elektro Muster', phone: '0123', email: 'a@b.de'),
  origin: 'abc123',
  catalog: handoverCatalog(_catalog),
  overrides: const {0x0801: Dpt(1, 2)},
  gateway: const GatewayRef(host: '192.168.1.22', port: 3671, name: 'GIRA X1'),
  connection: const {'mode': 'secure', 'tunnelAddress': 0x11F1, 'secureUserId': 3},
  keyring: keyring,
);

const _keyring = <String, Object?>{
  'project': 'Haus Muster',
  'groupKeys': {'2049': _secretKey},
  'sequence': {'4353': 5},
  'tunnels': [
    {'address': 0x11F1, 'host': 0x11FF, 'userId': 3, 'password': 'TunnelGeheim'},
  ],
};

/// Schneller als die echten Runden: Das Format nimmt sie aus dem Kopf.
Future<HandoverPackage> _open(Uint8List file, String password) => openHandover(file, password: password);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Kryptografie gegen veröffentlichte Testvektoren', () {
    test('AES-256-GCM: NIST-Testfall 16', () {
      final key = _hex('feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308');
      final nonce = _hex('cafebabefacedbaddecaf888');
      final aad = _hex('feedfacedeadbeeffeedfacedeadbeefabaddad2');
      final plain = _hex(
        'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39',
      );
      const cipher =
          '522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662';
      const tag = '76fc6ece0f4e1768cddf8853bb2d551b';
      final out = aesGcm(encrypt: true, key: key, nonce: nonce, aad: aad, data: plain);
      expect(_toHex(out), '$cipher$tag');
      expect(unseal(out, key: key, nonce: nonce, aad: aad), plain);
    });

    test('PBKDF2-HMAC-SHA256: RFC 7914', () {
      final out = pbkdf2(utf8.encode('passwd'), utf8.encode('salt'), 1, 64);
      expect(
        _toHex(out),
        '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc'
        '49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783',
      );
    });

    test('verändertes Byte, falscher Schlüssel, andere AAD: abgelehnt', () {
      final key = randomBytes(32);
      final nonce = randomBytes(12);
      final aad = utf8.encode('kopf');
      final out = aesGcm(encrypt: true, key: key, nonce: nonce, aad: aad, data: utf8.encode('inhalt'));
      final changed = Uint8List.fromList(out)..[0] ^= 1;
      expect(() => unseal(changed, key: key, nonce: nonce, aad: aad), throwsA(isA<PackageDecryptException>()));
      expect(() => unseal(out, key: randomBytes(32), nonce: nonce, aad: aad), throwsA(isA<PackageDecryptException>()));
      expect(() => unseal(out, key: key, nonce: nonce, aad: utf8.encode('x')), throwsA(isA<PackageDecryptException>()));
    });

    test('Passwort: lang genug, Eingabe ohne Trennzeichen und klein', () {
      final a = generatePackagePassword();
      expect(a.length, 29);
      expect(generatePackagePassword(), isNot(a));
      expect(normalizePackagePassword(a.toLowerCase().replaceAll('-', ' ')), normalizePackagePassword(a));
      expect(RegExp(r'[01OILS25Z]').hasMatch(a.replaceAll('-', '')), isFalse);
    });
  });

  group('Paket', () {
    test('Round-Trip ohne Passwort', () async {
      final file = _package().toFile();
      expect(packageKindOf(file), PackageKind.handover);
      final m = HandoverPackage.readManifest(file);
      expect(m.encrypted, isFalse);
      expect(m.contact.name, 'Elektro Muster');
      expect(m.groups, 1);
      final back = await openHandover(file);
      expect(back.catalog[0x0801]?.name, 'Licht Küche');
      expect(back.catalog[0x0801]?.path, 'EG › Küche');
      expect(back.catalog.devices[0x1101]?.name, 'Aktor');
      expect(back.overrides[0x0801]?.sub, 2);
      expect(back.gateway?.host, '192.168.1.22');
      expect(back.connection['secureUserId'], 3);
      expect(back.origin, 'abc123');
      expect(back.keyring, isNull);
    });

    test('Kein ganzes ETS-Projekt: ohne Seriennummern und Beschreibungen', () {
      final c = handoverCatalog(_catalog);
      expect(c.devices[0x1101]?.serial, isNull);
      expect(c.devices[0x1101]?.description, isNull);
      expect(c.devices[0x1101]?.location, 'Keller');
    });

    test('Mit Schlüsseln: ohne Passwort verweigert', () {
      expect(() => _package(keyring: _keyring).toFile(), throwsArgumentError);
      expect(() => _package(keyring: _keyring).toFile(password: ''), throwsArgumentError);
    });

    test('Round-Trip mit Schlüsseln; nichts davon im Klartext', () async {
      final password = generatePackagePassword();
      final file = _package(keyring: _keyring).toFile(password: password);
      final m = HandoverPackage.readManifest(file);
      expect(m.encrypted, isTrue);
      expect(m.hasKeys, isTrue);
      final zip = ZipDecoder().decodeBytes(file);
      expect(zip.findFile('payload.json'), isNull);
      final raw = latin1.decode(zip.findFile('payload.enc')!.content) + latin1.decode(file);
      for (final secret in ['TunnelGeheim', _secretKey, 'Licht', '192.168']) {
        expect(raw, isNot(contains(secret)), reason: secret);
      }
      final back = await _open(file, password.toLowerCase());
      expect(back.keyring?['tunnels'], isNotEmpty);
      expect((back.keyring?['groupKeys'] as Map)['2049'], _secretKey);
      expect(back.catalog[0x0801]?.name, 'Licht Küche');
    });

    test('Falsches oder fehlendes Passwort', () async {
      final file = _package(keyring: _keyring).toFile(password: generatePackagePassword());
      Matcher wrong = throwsA(
        isA<PackageException>().having((e) => e.problem, 'problem', PackageProblem.wrongPassword),
      );
      await expectLater(_open(file, 'FALSCH'), wrong);
      await expectLater(openHandover(file), wrong);
      expect(() => HandoverPackage.open(file), wrong);
    });

    test('Geänderter Kopf im verschlüsselten Paket fällt auf', () async {
      final password = generatePackagePassword();
      final zip = ZipDecoder().decodeBytes(_package(keyring: _keyring).toFile(password: password));
      final head = (jsonDecode(utf8.decode(zip.findFile('handover.json')!.content)) as Map).cast<String, Object?>();
      head['contact'] = {'name': 'Falsche Firma'};
      final forged = Archive();
      final bytes = utf8.encode(jsonEncode(head));
      forged.addFile(ArchiveFile('handover.json', bytes.length, bytes));
      final enc = zip.findFile('payload.enc')!.content;
      forged.addFile(ArchiveFile('payload.enc', enc.length, enc));
      await expectLater(
        _open(Uint8List.fromList(ZipEncoder().encode(forged)), password),
        throwsA(isA<PackageException>().having((e) => e.problem, 'problem', PackageProblem.wrongPassword)),
      );
    });

    test('Korrupte Dateien: Fehler statt Absturz', () async {
      Matcher corrupt = throwsA(isA<PackageException>().having((e) => e.problem, 'problem', PackageProblem.corrupt));
      final good = _package().toFile();
      // Abgeschnitten, Müll, leer, ZIP ohne Inhalt, Fremdformat, kaputtes JSON.
      for (final bad in <Uint8List>[
        Uint8List.fromList(good.sublist(0, good.length ~/ 2)),
        Uint8List.fromList(List.generate(500, (i) => i % 251)),
        Uint8List(0),
        _zip({}),
        _zip({'handover.json': '{"format":"anderes"}'}),
        _zip({'handover.json': '{kaputt'}),
        _zip({'handover.json': '[1,2]'}),
        _zip({
          'handover.json': jsonEncode({'format': handoverFormat, 'version': 1}),
        }),
      ]) {
        expect(() => HandoverPackage.readManifest(bad), corrupt);
      }
      // Kopf in Ordnung, Inhalt fehlt oder ist Unsinn.
      final head = utf8.decode(ZipDecoder().decodeBytes(good).findFile('handover.json')!.content);
      expect(() => HandoverPackage.open(_zip({'handover.json': head})), corrupt);
      expect(() => HandoverPackage.open(_zip({'handover.json': head, 'payload.json': '{"catalog":3}'})), corrupt);
      // Unsinnige Rundenzahl (Gerät soll nicht ewig rechnen).
      final zip = ZipDecoder().decodeBytes(_package(keyring: _keyring).toFile(password: 'X'));
      final m = (jsonDecode(utf8.decode(zip.findFile('handover.json')!.content)) as Map).cast<String, Object?>();
      (m['kdf']! as Map)['iterations'] = packageKdfMaxIterations + 1;
      expect(() => HandoverPackage.keyParams(_zip({'handover.json': jsonEncode(m), 'payload.enc': 'x'})), corrupt);
    });

    test('Paket aus einer neueren Version wird benannt', () {
      final file = _zip({
        'handover.json': jsonEncode({'format': handoverFormat, 'version': 99}),
      });
      expect(
        () => HandoverPackage.readManifest(file),
        throwsA(isA<PackageException>().having((e) => e.problem, 'problem', PackageProblem.newer)),
      );
    });

    test('Dateiart: nie eine Ausnahme', () {
      expect(packageKindOf(Uint8List(0)), isNull);
      expect(packageKindOf(Uint8List.fromList([0x50, 0x4B, 3, 4, 9, 9])), isNull);
      expect(packageKindOf(_zip({'x.txt': 'y'})), isNull);
    });
  });

  group('Einspielen und Melden', () {
    late Directory dir;
    final installs = InstallationStore.instance;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('handover');
      AppStorage.instance = IoStorage(dir);
      installs.debugReset();
      CustomerStore.instance.debugReset();
      CompanyStore.instance.debugReset();
      CatalogStore.instance.catalog = GroupCatalog.empty;
      await installs.load();
      await InstallationStore.reloadStores();
    });

    tearDown(() async {
      CatalogStore.instance.catalog = GroupCatalog.empty;
      HandoverStore.instance.origin = null;
      await dir.delete(recursive: true);
    });

    test('Frische App: übernimmt die leere Anlage, alles eingerichtet', () async {
      final firstId = installs.active.id;
      final p = await openHandover(
        _package(keyring: _keyring).toFile(password: 'ABC'),
        password: 'ABC',
      );
      final i = await applyHandover(p);
      expect(i.id, firstId);
      expect(installs.list.length, 1);
      expect(i.name, 'Haus Muster');
      expect(i.gateway?.host, '192.168.1.22');
      expect(CatalogStore.instance.catalog[0x0801]?.name, 'Licht Küche');
      expect(KeyringStore.instance.groupKeyCount, 1);
      expect(KeyringStore.instance.tunnels.single.password, 'TunnelGeheim');
      expect(ConnectionOptions.instance.mode, ConnectionMode.secure);
      expect(HandoverStore.instance.origin?.contact.name, 'Elektro Muster');
      // Nach einem Neustart noch da.
      HandoverStore.instance.origin = null;
      await HandoverStore.instance.load();
      expect(HandoverStore.instance.origin?.origin, 'abc123');
    });

    test('Vorhandene Anlage bleibt; zweites Öffnen legt nichts doppelt an', () async {
      final mine = installs.active.id;
      await CatalogStore.instance.adopt(_catalog, name: 'eigen.csv');
      final p = await openHandover(_package().toFile());
      final i = await applyHandover(p);
      expect(i.id, isNot(mine));
      expect(installs.list.length, 2);
      await installs.switchTo(mine);
      final again = await applyHandover(p);
      expect(again.id, i.id);
      expect(installs.list.length, 2);
    });

    test('Korrigierte Namen kommen als Korrektur an, nicht als Projektname', () async {
      final store = CatalogStore.instance;
      await store.adopt(_catalog, name: 'eigen.csv');
      await store.setName(0x0801, 'Licht Küche Insel');
      final p = await openHandover((await buildHandover(includeKeys: false)).toFile());
      expect(p.catalog[0x0801]?.name, 'Licht Küche Insel');
      expect(p.projectNames, {0x0801: 'Licht Küche'});
      await applyHandover(p);
      expect(store.project[0x0801]?.name, 'Licht Küche');
      expect(store.names, {0x0801: 'Licht Küche Insel'});
      expect(store.catalog[0x0801]?.name, 'Licht Küche Insel');
      // Älteres Paket ohne Projektnamen: keine Korrekturen übrig.
      await store.adopt(_catalog, name: 'alt.knxhandover', projectNames: const {});
      expect(store.names, isEmpty);
    });

    test('Kaputte Herkunft-Datei: keine Meldung, kein Absturz', () async {
      await installs.storage.write(HandoverStore.file, '{kaputt');
      await HandoverStore.instance.load();
      expect(HandoverStore.instance.origin, isNull);
    });

    test('Kundendaten und Besuche sind nicht im Paket', () async {
      await CatalogStore.instance.adopt(_catalog, name: 'x.csv');
      await CustomerStore.instance.saveRecord(
        installs.active.id,
        const CustomerRecord(customer: 'Familie Geheim', phone: '0171-999'),
      );
      await CompanyStore.instance.save(const Company(name: 'Elektro Muster', phone: '0123'));
      final p = await buildHandover(includeKeys: false);
      expect(p.contact.name, 'Elektro Muster');
      expect(p.origin, installs.active.id);
      final text = latin1.decode(ZipDecoder().decodeBytes(p.toFile()).findFile('payload.json')!.content);
      expect(text, isNot(contains('Geheim')));
      expect(
        latin1.decode(ZipDecoder().decodeBytes(p.toFile()).findFile('handover.json')!.content),
        isNot(contains('Geheim')),
      );
    });

    Telegram tg(int ga, DateTime t) => Telegram(
      time: t,
      source: 0x1101,
      destination: ga,
      type: TelegramType.write,
      data: Uint8List.fromList([0x41]),
      isSmall: true,
    );

    FaultReport report({Set<int> secure = const {}}) {
      final since = DateTime(2026, 10, 30, 10);
      return buildFaultReport(
        origin: HandoverOrigin(
          handover: 'paket1',
          origin: installs.active.id,
          contact: const PackageContact(name: 'Elektro Muster'),
          created: since,
        ),
        installationName: 'Bei Muster',
        telegrams: [
          tg(0x0801, since.add(const Duration(minutes: 1))),
          tg(0x0802, since.add(const Duration(minutes: 2))),
        ],
        catalog: _catalog,
        since: since,
        problem: 'Licht geht nicht aus',
        annotations: [
          Annotation(id: 'a1', time: since.add(const Duration(minutes: 1)), note: 'Jetzt', shots: ['s1']),
        ],
        shots: {
          's1': Uint8List.fromList([1, 2, 3]),
        },
        secureAddresses: secure,
        includeShots: true,
        now: since.add(const Duration(minutes: 5)),
      );
    }

    test('Meldung: Round-Trip, enthält keine Schlüssel, Secure nur Metadaten', () {
      final file = report(secure: {0x0802}).toFile();
      expect(packageKindOf(file), PackageKind.faultReport);
      final back = FaultReport.fromFile(file);
      expect(back.origin, installs.active.id);
      expect(back.package.problem, 'Licht geht nicht aus');
      expect(back.package.catalog[0x0801]?.name, 'Licht Küche');
      expect(back.package.recording.telegrams.single.destination, 0x0801);
      expect(back.package.secureTelegrams.single.destination, 0x0802);
      final zip = ZipDecoder().decodeBytes(file);
      final all = [for (final f in zip.files) latin1.decode(f.content)].join();
      expect(all, isNot(contains(_secretKey)));
      expect(all, isNot(contains('groupKeys')));
    });

    test('Beim Elektriker: im Verlauf der richtigen Anlage, nicht doppelt', () async {
      final other = await installs.create('Andere');
      final r = FaultReport.fromFile(report().toFile());
      final id = await receiveFaultReport(r, installs.active.id);
      final visits = CustomerStore.instance.visits(installs.active.id);
      expect(visits.single.kind, VisitKind.faultReport);
      expect(visits.single.text, 'Licht geht nicht aus');
      expect(visits.single.ref, id);
      expect(CustomerStore.instance.visits(other.id), isEmpty);
      final recording = await RecordingStore.instance.open(id);
      expect(recording.installation, installs.active.id);
      expect(recording.annotations.single.note, 'Jetzt');
      expect(await ShotStore.instance.read(recording.annotations.single.shots.single), isNotNull);
      // Nochmal öffnen: dieselbe Aufnahme, kein zweiter Eintrag.
      expect(await receiveFaultReport(r, installs.active.id), id);
      expect(CustomerStore.instance.visits(installs.active.id).length, 1);
    });

    test('Beschädigte Meldung', () {
      expect(() => FaultReport.fromFile(Uint8List(5)), throwsA(isA<PackageException>()));
      expect(
        () => FaultReport.fromFile(_zip({FaultReport.fileName: '{"format":"$faultReportFormat","version":1}'})),
        throwsA(isA<PackageException>()),
      );
      expect(
        () => FaultReport.fromFile(_zip({FaultReport.fileName: '{"format":"$faultReportFormat","version":9}'})),
        throwsA(isA<PackageException>().having((e) => e.problem, 'problem', PackageProblem.newer)),
      );
    });

    group('Datenschutz der Meldung', () {
      FaultReport build({bool? includeShots, bool keepNames = true}) {
        final since = DateTime(2026, 10, 30, 10);
        final annotations = [
          Annotation(id: 'a1', time: since.add(const Duration(minutes: 1)), note: 'Jetzt', shots: ['s1']),
        ];
        final origin = HandoverOrigin(
          handover: 'p',
          origin: 'o',
          contact: const PackageContact(name: 'Elektro Muster'),
          created: since,
        );
        final shots = {
          's1': Uint8List.fromList([1, 2, 3]),
        };
        final telegrams = [tg(0x0801, since.add(const Duration(minutes: 1)))];
        return includeShots == null
            ? buildFaultReport(
                origin: origin,
                installationName: 'Bei Muster',
                telegrams: telegrams,
                catalog: _catalog,
                since: since,
                problem: 'x',
                annotations: annotations,
                shots: shots,
                keepNames: keepNames,
                now: since.add(const Duration(minutes: 5)),
              )
            : buildFaultReport(
                origin: origin,
                installationName: 'Bei Muster',
                telegrams: telegrams,
                catalog: _catalog,
                since: since,
                problem: 'x',
                annotations: annotations,
                shots: shots,
                includeShots: includeShots,
                keepNames: keepNames,
                now: since.add(const Duration(minutes: 5)),
              );
      }

      test('Screenshots nur auf ausdrücklichen Wunsch', () {
        expect(build().package.shots, isEmpty, reason: 'Vorgabe: ohne');
        expect(build().package.recording.annotations.single.shots, isEmpty);
        expect(build(includeShots: true).package.shots, isNotEmpty);
      });

      test('Namen lassen sich wie im Diagnosepaket ersetzen', () {
        expect(build().package.namesIncluded, isTrue);
        final without = build(keepNames: false).package;
        expect(without.namesIncluded, isFalse);
        final original = _catalog.groups.values.map((g) => g.name).where((n) => n.isNotEmpty).toList();
        expect(original, isNotEmpty);
        for (final name in original) {
          expect(without.catalog.groups.values.map((g) => g.name), isNot(contains(name)));
        }
      });
    });

    test('Diagnosepaket bleibt als solches lesbar (Zusatzdatei stört nicht)', () {
      final file = report().toFile();
      expect(DiagnosticsPackage.fromZip(file).problem, 'Licht geht nicht aus');
    });
  });

  test('Stufen: erstellen Pro, empfangen Plus', () {
    expect(Feature.handover.tier, Tier.pro);
    expect(Feature.handoverReceive.tier, Tier.plus);
    expect(Feature.customerRecords.tier, Tier.pro);
  });

  group('Oberfläche', () {
    Widget app(Widget home) => MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: home,
    );

    setUp(() {
      CompanyStore.instance.debugReset();
      CatalogStore.instance.catalog = GroupCatalog.empty;
    });

    testWidgets('Ohne Firma: Hinweis, Erstellen gesperrt', (tester) async {
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(const HandoverScreen()));
      await tester.pump();
      expect(find.textContaining('Trage zuerst deine Firma ein'), findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(of: find.text('Paket erstellen und teilen'), matching: find.bySubtype<ButtonStyleButton>()),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Passwortschutz zeigt QR-Code und Passwort', (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      CompanyStore.instance.company = const Company(name: 'Elektro Muster');
      CatalogStore.instance.catalog = _catalog;
      addTearDown(() => CatalogStore.instance.catalog = GroupCatalog.empty);
      await tester.pumpWidget(app(const HandoverScreen()));
      await tester.pump();
      expect(find.byType(PasswordQr), findsNothing);
      await tester.tap(find.text('Mit Passwort schützen'));
      await tester.pump();
      expect(find.byType(PasswordQr), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Kontakt in der Karte der Anlage', (tester) async {
      await tester.pumpWidget(
        app(
          Scaffold(
            body: HandoverOriginTile(
              origin: HandoverOrigin(
                handover: 'p',
                origin: 'o',
                contact: const PackageContact(name: 'Elektro Muster', phone: '0123', address: 'Weg 1'),
                created: DateTime(2026),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Eingerichtet von Elektro Muster'), findsOneWidget);
      expect(find.text('0123'), findsOneWidget);
    });
  });
}

Uint8List _zip(Map<String, String> files) {
  final a = Archive();
  for (final MapEntry(:key, :value) in files.entries) {
    final b = utf8.encode(value);
    a.addFile(ArchiveFile(key, b.length, b));
  }
  return Uint8List.fromList(ZipEncoder().encode(a));
}
