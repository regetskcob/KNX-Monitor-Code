import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/export/customer_file.dart';
import 'package:knx_monitor/export/diagnostics_bundle.dart';
import 'package:knx_monitor/export/handover_package.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/company.dart';
import 'package:knx_monitor/model/customer.dart';
import 'package:knx_monitor/model/customer_transfer.dart';
import 'package:knx_monitor/model/handover.dart';
import 'package:knx_monitor/model/incoming_file.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/model/plan.dart';
import 'package:knx_monitor/model/site_photos.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/customer_transfer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The electrician's own customer files for a second own device: one password-protected file,
// matched by installation key, merged without duplicates, a question where the record differs.
// And the other direction of the same rule: none of it ever reaches a package for the customer.

const _password = 'ABCD-EFGH';

final _jpeg = base64Encode([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4]);

const _record = CustomerRecord(
  customer: 'Familie Geheim',
  site: 'Geheimweg 7\n12345 Ort',
  phone: '0171-999',
  notes: 'Verteiler im Keller',
  maintenanceMonths: 12,
);

Visit _visit(String id, {String text = '', VisitKind kind = VisitKind.manual}) => Visit(
  id: id,
  time: DateTime(2026, 11, 1).add(Duration(hours: id.hashCode % 200)),
  kind: kind,
  text: text,
);

Future<CustomerFile> _reopen(CustomerFile file) async =>
    openCustomerFile(file.toFile(password: _password), password: _password);

Uint8List _zip(Map<String, List<int>> files) {
  final a = Archive();
  for (final MapEntry(:key, :value) in files.entries) {
    a.addFile(ArchiveFile(key, value.length, value));
  }
  return Uint8List.fromList(ZipEncoder().encode(a));
}

Future<void> _loadFonts() async {
  const fonts = {
    'Literata': ['Literata-Light.ttf', 'Literata-SemiBold.ttf'],
    'MonaSans': ['MonaSans-Regular.ttf', 'MonaSans-Medium.ttf', 'MonaSans-SemiBold.ttf'],
    'MonaspaceArgon': ['MonaspaceArgon-Regular.otf', 'MonaspaceArgon-SemiBold.otf'],
    'MaterialSymbolsSharp': ['MaterialSymbolsSharp-300.ttf'],
  };
  for (final entry in fonts.entries) {
    final loader = FontLoader('packages/horizont/${entry.key}');
    for (final file in entry.value) {
      loader.addFont(rootBundle.load('packages/horizont/fonts/$file'));
    }
    await loader.load();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final installs = InstallationStore.instance;
  final store = CustomerStore.instance;
  final dirs = <Directory>[];

  /// A fresh device: empty storage, one empty installation.
  Future<void> device() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('customer_transfer');
    dirs.add(dir);
    AppStorage.instance = IoStorage(dir);
    installs.debugReset();
    store.debugReset();
    SitePhotoStore.instance.debugReset();
    CompanyStore.instance.debugReset();
    CatalogStore.instance.catalog = GroupCatalog.empty;
    await installs.load();
    await InstallationStore.reloadStores();
  }

  AppStorage folder(String id) => CustomerStore.storageOf(id);

  /// First device: one installation with everything a customer file can hold. Returns its key.
  Future<String> fill({bool photo = true}) async {
    final i = installs.active;
    await installs.rename(i.id, 'Haus Geheim');
    await store.saveRecord(i.id, _record);
    await store.saveVisit(i.id, _visit('v1', text: 'Taster getauscht'));
    await store.saveVisit(i.id, _visit('v2', kind: VisitKind.acceptance));
    await folder(i.id).write('protocols/1794300100000.json', '{"created":1794300100000,"note":"Abnahme"}');
    await folder(i.id).write('service_reports/1794300200000.json', '{"created":1794300200000,"work":"Service"}');
    if (photo) {
      await folder(i.id).write('site_photos/k3xa10.jpg.b64', _jpeg);
      await folder(i.id).write(
        'site_photos.json',
        jsonEncode([SitePhoto(id: 'k3xa10', caption: 'Verteiler', at: DateTime(2026, 11, 10)).toJson()]),
      );
    }
    await CompanyStore.instance.save(const Company(name: 'Elektro Muster'));
    return i.key;
  }

  setUp(device);

  tearDown(() async {
    CatalogStore.instance.catalog = GroupCatalog.empty;
    for (final d in dirs) {
      if (d.existsSync()) await d.delete(recursive: true);
    }
    dirs.clear();
  });

  group('Datei', () {
    test('Round-Trip: Akte, Besuche, Protokolle, Serviceberichte, Fotos', () async {
      final key = await fill();
      final file = await buildCustomerFile(includePhotos: true, now: DateTime(2026, 11, 12));
      final bytes = file.toFile(password: _password);
      expect(packageKindOf(bytes), PackageKind.customerFile);
      final head = CustomerFile.readManifest(bytes);
      expect(head.company, 'Elektro Muster');
      expect((head.installations, head.visits, head.documents, head.photos), (1, 2, 2, 1));
      // Kleinschreibung und Trennzeichen im Passwort sind egal, wie beim Übergabepaket.
      final back = await openCustomerFile(bytes, password: 'abcd efgh');
      final e = back.entries.single;
      expect(e.key, key);
      expect(e.name, 'Haus Geheim');
      expect(jsonEncode(e.record.toJson()), jsonEncode(_record.toJson()));
      expect(e.visits.map((v) => v.id).toSet(), {'v1', 'v2'});
      expect(e.visits.firstWhere((v) => v.id == 'v1').text, 'Taster getauscht');
      expect(e.protocols['1794300100000.json']?['note'], 'Abnahme');
      expect(e.serviceReports['1794300200000.json']?['work'], 'Service');
      expect(e.photos.single.caption, 'Verteiler');
      expect(e.photos.single.jpegBase64, _jpeg);
    });

    test('Fotos nur auf Wunsch; alle Akten ohne die leeren Anlagen', () async {
      await fill();
      await installs.create('Leer');
      final file = await buildCustomerFile();
      expect(file.entries.single.photos, isEmpty);
      expect(file.entries.single.name, 'Haus Geheim');
      // Einzeln gewählt geht auch eine leere mit.
      final one = await buildCustomerFile(installations: [installs.list.firstWhere((i) => i.name == 'Leer')]);
      expect(one.entries.single.record.isEmpty, isTrue);
    });

    test('„Alle Akten“ nimmt auch eine Anlage mit, die nur ein Dokument hat', () async {
      await fill();
      await installs.create('Leer');
      final only = await installs.create('Nur Protokoll');
      await CustomerStore.storageOf(only.id).write('protocols/20261111-101500.json', '{"customer":"X"}');
      final scope = await customerExportScope();
      expect(scope.map((i) => i.name), containsAll(['Haus Geheim', 'Nur Protokoll']));
      expect(scope.map((i) => i.name), isNot(contains('Leer')));
    });

    test('nie ohne Passwort; nichts von den Kundendaten im Klartext', () async {
      await fill();
      final file = await buildCustomerFile(includePhotos: true);
      expect(() => file.toFile(password: ''), throwsArgumentError);
      final bytes = file.toFile(password: _password);
      final zip = ZipDecoder().decodeBytes(bytes);
      expect(zip.files.map((f) => f.name).toSet(), {'customers.json', 'payload.enc'});
      final raw = [latin1.decode(bytes), for (final f in zip.files) latin1.decode(f.content)].join();
      for (final secret in ['Geheim', '0171', 'Taster', 'Verteiler', 'Abnahme']) {
        expect(raw, isNot(contains(secret)), reason: secret);
      }
    });

    test('falsches Passwort, geänderter Kopf, geänderter Inhalt: dieselbe Meldung', () async {
      await fill();
      final bytes = (await buildCustomerFile()).toFile(password: _password);
      Matcher wrong = throwsA(
        isA<PackageException>().having((e) => e.problem, 'problem', PackageProblem.wrongPassword),
      );
      await expectLater(openCustomerFile(bytes, password: 'FALSCH'), wrong);
      await expectLater(openCustomerFile(bytes, password: ''), wrong);
      final zip = ZipDecoder().decodeBytes(bytes);
      final headBytes = zip.findFile('customers.json')!.content;
      final enc = zip.findFile('payload.enc')!.content;
      final head = (jsonDecode(utf8.decode(headBytes)) as Map).cast<String, Object?>()..['company'] = 'Andere Firma';
      await expectLater(
        openCustomerFile(
          _zip({'customers.json': utf8.encode(jsonEncode(head)), 'payload.enc': enc}),
          password: _password,
        ),
        wrong,
      );
      final changed = Uint8List.fromList(enc)..[enc.length ~/ 2] ^= 1;
      await expectLater(
        openCustomerFile(_zip({'customers.json': headBytes, 'payload.enc': changed}), password: _password),
        wrong,
      );
    });

    test('beschädigt, fremd, aus einer neueren Version', () async {
      await fill();
      final bytes = (await buildCustomerFile()).toFile(password: _password);
      Matcher problem(PackageProblem p) => throwsA(isA<PackageException>().having((e) => e.problem, 'problem', p));
      final head = (jsonDecode(utf8.decode(ZipDecoder().decodeBytes(bytes).findFile('customers.json')!.content)) as Map)
          .cast<String, Object?>();
      List<int> json(Object? v) => utf8.encode(jsonEncode(v));
      for (final bad in <Uint8List>[
        Uint8List.fromList(bytes.sublist(0, bytes.length ~/ 2)),
        Uint8List(0),
        _zip({'customers.json': utf8.encode('{kaputt')}),
        _zip({
          'customers.json': json({'format': 'anderes', 'version': 1}),
        }),
        _zip({
          'customers.json': json({'format': customerFileFormat, 'version': 1}),
        }),
      ]) {
        expect(() => CustomerFile.readManifest(bad), problem(PackageProblem.corrupt));
      }
      expect(
        () => CustomerFile.readManifest(
          _zip({
            'customers.json': json({'format': customerFileFormat, 'version': 2}),
          }),
        ),
        problem(PackageProblem.newer),
      );
      // Kopf in Ordnung, Inhalt fehlt; unbekanntes Verfahren; unsinnige Rundenzahl.
      await expectLater(
        openCustomerFile(_zip({'customers.json': json(head)}), password: _password),
        problem(PackageProblem.corrupt),
      );
      final otherCipher = {
        ...head,
        'cipher': {'name': 'AES-128-CBC', 'nonce': ''},
      };
      expect(
        () => CustomerFile.keyParams(_zip({'customers.json': json(otherCipher)})),
        problem(PackageProblem.corrupt),
      );
      final slow = {
        ...head,
        'kdf': {...head['kdf']! as Map, 'iterations': 5000001},
      };
      expect(() => CustomerFile.keyParams(_zip({'customers.json': json(slow)})), problem(PackageProblem.corrupt));
    });

    test('Fremde Datei: unbrauchbare Namen, IDs und Verweise werden verworfen', () {
      final e = CustomerFileEntry.fromJson({
        'key': 'kein-schluessel',
        'name': 'x' * (customerFileMaxText + 5),
        'record': {'customer': 7, 'phone': '0123', 'maintenanceMonths': 'zwölf'},
        'visits': [
          {'id': 'ok', 't': 1794300000000, 'k': 'manual', 'r': '../../etc/passwd'},
          {'t': 1794300000000, 'k': 'manual'},
          'kein Besuch',
          {'id': 'neu', 't': 1794300000000, 'k': 'kommtNoch', 'r': 'k3x9f0'},
        ],
        'protocols': {
          '../x.json': <String, Object?>{},
          'a/b.json': <String, Object?>{},
          'gut_1.json': {'a': 1},
          'kein.txt': <String, Object?>{},
          'liste.json': <Object?>[],
        },
        'photos': [
          {'id': '../x', 'at': '2026-11-10T13:02:11.000Z', 'jpeg': 'AA=='},
          {'id': 'k3xa10', 'at': 'gestern', 'jpeg': 'AA=='},
          {'id': 'k3xa11', 'at': '2026-11-10T13:02:11.000Z', 'jpeg': 'AA=='},
        ],
      });
      expect(e.key, isNull);
      expect(e.name.length, customerFileMaxText);
      expect(e.record.customer, '');
      expect(e.record.phone, '0123');
      expect(e.record.maintenanceMonths, isNull);
      expect(e.visits.map((v) => v.id), ['ok', 'neu']);
      expect(e.visits.first.ref, isNull, reason: 'ein Verweis landet in einem Dateipfad');
      expect(e.visits.last.ref, 'k3x9f0');
      expect(e.visits.last.kind, VisitKind.manual);
      expect(e.protocols.keys, ['gut_1.json']);
      expect(e.photos.single.id, 'k3xa11');
    });
  });

  group('Zweites Gerät', () {
    /// Builds the file on the first device, then starts a second one that knows the installation.
    Future<(CustomerFile, Installation)> second({bool known = true, bool photo = true}) async {
      final key = await fill(photo: photo);
      final file = await _reopen(await buildCustomerFile(includePhotos: true));
      await device();
      final target = known ? await installs.create('Haus Geheim (Tablet)', key: key) : installs.active;
      return (file, target);
    }

    test('über den Anlagenschlüssel zugeordnet, alles übernommen', () async {
      final (file, target) = await second();
      final items = await planCustomerImport(file);
      final item = items.single;
      expect(item.installation?.id, target.id);
      expect(item.recordDiffers, isFalse);
      expect(item.takesRecord, isTrue);
      expect((item.newVisits, item.newDocuments, item.newPhotos), (2, 2, 1));
      final result = await applyCustomerImport(items);
      expect((result.installations, result.records, result.visits, result.documents, result.photos), (1, 1, 2, 2, 1));
      expect(store.record(target.id).customer, 'Familie Geheim');
      expect(store.visits(target.id).length, 2);
      expect(await folder(target.id).read('protocols/1794300100000.json'), contains('Abnahme'));
      expect(await folder(target.id).read('service_reports/1794300200000.json'), contains('Service'));
      expect(await folder(target.id).read('site_photos/k3xa10.jpg.b64'), _jpeg);
      expect(jsonDecode((await folder(target.id).read('site_photos.json'))!), hasLength(1));
      // Nach einem Neustart noch da.
      store.debugReset();
      await store.load();
      expect(store.record(target.id).phone, '0171-999');
      expect(store.visits(target.id).map((v) => v.id).toSet(), {'v1', 'v2'});
      // Die andere Anlage hat nichts abbekommen.
      final other = installs.list.firstWhere((i) => i.id != target.id);
      expect(store.record(other.id).isEmpty, isTrue);
      expect(store.visits(other.id), isEmpty);
    });

    test('dieselbe Datei noch einmal: nichts doppelt', () async {
      final (file, target) = await second();
      await applyCustomerImport(await planCustomerImport(file));
      final again = await planCustomerImport(file);
      expect(again.single.upToDate, isTrue);
      final result = await applyCustomerImport(again);
      expect((result.records, result.visits, result.documents, result.photos), (0, 0, 0, 0));
      expect(store.visits(target.id).length, 2);
      expect((await folder(target.id).list('protocols')).length, 1);
      expect((await folder(target.id).list('site_photos')).length, 1);
      expect(jsonDecode((await folder(target.id).read('site_photos.json'))!), hasLength(1));
    });

    test('beide Geräte haben Einträge: zusammengeführt, gleiche ID nur einmal, hiesige bleiben', () async {
      final (file, target) = await second();
      await store.saveVisit(target.id, _visit('v1', text: 'hier anders notiert'));
      await store.saveVisit(target.id, _visit('v9', text: 'nur auf dem Tablet'));
      await folder(target.id).write('protocols/1794300100000.json', '{"note":"hiesige Fassung"}');
      await folder(target.id).write('protocols/1794399900000.json', '{"note":"nur hier"}');
      final item = (await planCustomerImport(file)).single;
      expect((item.newVisits, item.newDocuments), (1, 1));
      await applyCustomerImport([item]);
      final visits = store.visits(target.id);
      expect(visits.map((v) => v.id).toSet(), {'v1', 'v2', 'v9'});
      expect(visits.firstWhere((v) => v.id == 'v1').text, 'hier anders notiert');
      expect(await folder(target.id).read('protocols/1794300100000.json'), contains('hiesige Fassung'));
      expect((await folder(target.id).list('protocols')).length, 2);
      expect((await folder(target.id).list('service_reports')).length, 1);
    });

    test('abweichende Kundendaten: ohne Antwort bleiben die hiesigen, mit Antwort die aus der Datei', () async {
      final (file, target) = await second();
      const mine = CustomerRecord(customer: 'Familie Geheim', phone: '0171-000', notes: 'Tablet-Notiz');
      await store.saveRecord(target.id, mine);
      final item = (await planCustomerImport(file)).single;
      expect(item.recordDiffers, isTrue);
      expect(item.takesRecord, isFalse);
      var result = await applyCustomerImport([item]);
      expect(result.records, 0);
      expect(store.record(target.id).phone, '0171-000');
      expect(store.visits(target.id).length, 2, reason: 'der Rest kommt trotzdem an');
      result = await applyCustomerImport(await planCustomerImport(file), takeRecordFor: {target.id});
      expect(result.records, 1);
      expect(store.record(target.id).phone, '0171-999');
      // Gleiche Daten sind kein Unterschied.
      expect((await planCustomerImport(file)).single.recordDiffers, isFalse);
    });

    test('Anlage nicht auf dem Gerät: übersprungen, auf Wunsch leer angelegt', () async {
      final (file, _) = await second(known: false);
      final items = await planCustomerImport(file);
      expect(items.single.installation, isNull);
      var result = await applyCustomerImport(items);
      expect(result.installations, 0);
      expect(installs.list.length, 1);
      expect(store.hasRecords, isFalse);
      result = await applyCustomerImport(items, createMissing: true);
      expect((result.installations, result.created, result.visits), (1, 1, 2));
      final created = installs.byKey(file.entries.single.key)!;
      expect(created.name, 'Haus Geheim');
      expect(store.record(created.id).customer, 'Familie Geheim');
      // Beim nächsten Öffnen ist sie da und auf dem Stand.
      expect((await planCustomerImport(file)).single.upToDate, isTrue);
    });

    test('gleicher Name genügt nicht: nur der Schlüssel ordnet zu', () async {
      await fill();
      final file = await _reopen(await buildCustomerFile());
      await device();
      await installs.create('Haus Geheim');
      expect((await planCustomerImport(file)).single.installation, isNull);
    });

    test('kein Bild oder Fotodokumentation voll: Foto übersprungen und gezählt', () async {
      final (file, target) = await second();
      final entry = file.entries.single;
      final hostile = CustomerFileEntry(
        key: entry.key,
        name: entry.name,
        photos: [
          entry.photos.single,
          CustomerFilePhoto(
            id: 'k3xa11',
            caption: '',
            at: DateTime(2026),
            jpegBase64: base64Encode(utf8.encode('<svg/>')),
          ),
          CustomerFilePhoto(id: 'k3xa12', caption: '', at: DateTime(2026), jpegBase64: 'kein base64 !!'),
        ],
      );
      final items = await planCustomerImport(CustomerFile(id: 'x', created: DateTime(2026), entries: [hostile]));
      final result = await applyCustomerImport(items);
      expect((result.photos, result.photosSkipped), (1, 2));
      expect((await folder(target.id).list('site_photos')).map((f) => f.name), ['k3xa10.jpg.b64']);
    });

    test('aktive Anlage: die Fotodokumentation zeigt die neuen Fotos sofort', () async {
      final (file, target) = await second();
      await installs.switchTo(target.id);
      await SitePhotoStore.instance.load();
      expect(SitePhotoStore.instance.photos, isEmpty);
      await applyCustomerImport(await planCustomerImport(file));
      expect(SitePhotoStore.instance.photos.single.caption, 'Verteiler');
    });
  });

  group('Nie für den Kunden', () {
    test('Übergabepaket, Störungsmeldung und Diagnosepaket enthalten nichts aus der Akte', () async {
      final key = await fill();
      final file = await _reopen(await buildCustomerFile(includePhotos: true));
      await device();
      // The installation's own name is part of a handover package; the customer's is not.
      final target = await installs.create('Anlage 7', key: key);
      await installs.switchTo(target.id);
      await applyCustomerImport(await planCustomerImport(file));
      await CatalogStore.instance.adopt(
        GroupCatalog({0x0801: const GroupInfo(address: 0x0801, name: 'Licht Küche')}, projectName: 'Projekt'),
        name: 'x.csv',
      );
      await CompanyStore.instance.save(const Company(name: 'Elektro Muster'));
      const secrets = ['Geheim', '0171-999', 'Taster getauscht', 'Abnahme', 'Verteiler im Keller'];
      String text(Uint8List zip) =>
          [for (final f in ZipDecoder().decodeBytes(zip).files) latin1.decode(f.content)].join();

      final handover = text((await buildHandover(includeKeys: false)).toFile());
      final since = DateTime(2026, 11, 12, 10);
      final telegram = Telegram(
        time: since.add(const Duration(minutes: 1)),
        source: 0x1101,
        destination: 0x0801,
        type: TelegramType.write,
        data: Uint8List.fromList([0x41]),
        isSmall: true,
      );
      // The customer's own words pass through the scrubber, which knows the record's texts.
      final report = text(
        buildFaultReport(
          origin: HandoverOrigin(
            handover: 'p',
            origin: 'o',
            contact: const PackageContact(name: 'Elektro Muster'),
            created: since,
          ),
          installationName: 'Anlage',
          telegrams: [telegram],
          catalog: CatalogStore.instance.catalog,
          since: since,
          problem: 'Bei Familie Geheim, Geheimweg 7, 0171-999 geht das Licht nicht',
          knownNames: store.privateNames,
          now: since.add(const Duration(minutes: 5)),
        ).toFile(),
      );
      final diagnostics = text(
        buildDiagnosticsPackage(
          telegrams: [telegram],
          catalog: CatalogStore.instance.catalog,
          occurred: since,
          from: since,
          to: since.add(const Duration(minutes: 5)),
          problem: 'Familie Geheim ruft unter 0171-999 an',
          knownNames: store.privateNames,
          now: since.add(const Duration(minutes: 5)),
        ).toZip(),
      );
      for (final secret in secrets) {
        expect(handover, isNot(contains(secret)), reason: 'Übergabe: $secret');
      }
      for (final secret in ['Familie Geheim', 'Geheimweg', '0171-999']) {
        expect(report, isNot(contains(secret)), reason: 'Meldung: $secret');
        expect(diagnostics, isNot(contains(secret)), reason: 'Diagnose: $secret');
      }
      for (final name in ['customers.json', 'customer.json', 'visits.json', 'protocols', 'service_reports']) {
        expect(handover + report + diagnostics, isNot(contains(name)), reason: name);
      }
    });

    test('eine Kundenakten-Datei ist kein Übergabepaket und keine Meldung, und umgekehrt', () async {
      await fill();
      final customers = (await buildCustomerFile()).toFile(password: _password);
      Matcher corrupt = throwsA(isA<PackageException>().having((e) => e.problem, 'problem', PackageProblem.corrupt));
      expect(() => HandoverPackage.readManifest(customers), corrupt);
      expect(() => FaultReport.fromFile(customers), corrupt);
      await CatalogStore.instance.adopt(
        GroupCatalog({0x0801: const GroupInfo(address: 0x0801, name: 'Licht')}, projectName: 'P'),
        name: 'x.csv',
      );
      final handover = (await buildHandover(includeKeys: false)).toFile();
      expect(packageKindOf(handover), PackageKind.handover);
      expect(() => CustomerFile.readManifest(handover), corrupt);
    });

    test('Stufe und Dateiendung', () {
      expect(Feature.customerRecords.tier, Tier.pro);
      expect(packagePathFromArgs(const ['/tmp/a.knxcustomers']), '/tmp/a.knxcustomers');
      expect(customerFileExtension, 'knxcustomers');
    });

    test('auf allen Plattformen angemeldet wie das Übergabepaket; Android liest sie nur per content://', () {
      for (final plist in ['ios/Runner/Info.plist', 'macos/Runner/Info.plist']) {
        final text = File(plist).readAsStringSync();
        expect(text, contains('<string>$customerFileExtension</string>'), reason: plist);
        expect('de.regetskcob.knx-monitor.customers'.allMatches(text).length, 2, reason: plist);
      }
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(r'\\.knxcustomers"'.allMatches(manifest).length, 6, reason: 'both filters, three depths');
      expect(manifest, contains('application/vnd.knx-monitor.customers'));
      final activity = File('android/app/src/main/kotlin/de/regetskcob/knxmonitor/MainActivity.kt').readAsStringSync();
      expect(activity, isNot(contains(customerFileExtension)), reason: 'kein file://-Weg für Kundendaten');
    });
  });

  group('Oberfläche', () {
    Widget app(Widget home, {double scale = 1}) => MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home,
    );

    void phone(WidgetTester tester, {double height = 2400}) {
      tester.view.physicalSize = Size(375, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('Übernehmen: zeigt Neues, fragt bei abweichenden Kundendaten, führt zusammen', (tester) async {
      late List<CustomerImportItem> items;
      late CustomerFile file;
      late Installation target;
      await tester.runAsync(() async {
        final key = await fill();
        file = await _reopen(await buildCustomerFile());
        await device();
        target = await installs.create('Haus Geheim', key: key);
        await store.saveRecord(target.id, const CustomerRecord(customer: 'Familie Geheim', phone: '0171-000'));
        items = await planCustomerImport(file);
      });
      phone(tester);
      await tester.pumpWidget(app(CustomerImportScreen(file: file, items: items)));
      await tester.pump();
      expect(find.textContaining('Datei von Elektro Muster'), findsOneWidget);
      expect(find.text('Neu: Besuche 2, Dokumente 2, Fotos 0'), findsOneWidget);
      expect(find.text('Kundendaten weichen ab'), findsOneWidget);
      // Die abweichenden Felder beim Namen.
      expect(find.textContaining('Aus der Datei übernehmen: Anschrift der Anlage, Telefon'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('Übernehmen'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      expect(store.record(target.id).phone, '0171-999');
      expect(store.visits(target.id).length, 2);
    });

    testWidgets('Übernehmen: fehlende Anlage wird genannt und nur auf Wunsch angelegt', (tester) async {
      late List<CustomerImportItem> items;
      late CustomerFile file;
      await tester.runAsync(() async {
        await fill();
        file = await _reopen(await buildCustomerFile());
        await device();
        items = await planCustomerImport(file);
      });
      phone(tester);
      await tester.pumpWidget(app(CustomerImportScreen(file: file, items: items)));
      await tester.pump();
      expect(find.text('Nicht auf diesem Gerät'), findsOneWidget);
      expect(find.text('Familie Geheim'), findsOneWidget);
      expect(find.textContaining('Hole sie zuerst auf dieses Gerät'), findsOneWidget);
      // Ohne den Schalter wird nichts angelegt.
      await tester.tap(find.text('Als leere Anlagen anlegen'));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('Übernehmen'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      expect(installs.byKey(file.entries.single.key)?.name, 'Haus Geheim');
    });

    testWidgets('Export: Passwort als QR-Code, Fotos als Schalter, Hinweis „nur eigene Geräte“', (tester) async {
      late Installation i;
      await tester.runAsync(() async {
        await fill();
        i = installs.active;
      });
      phone(tester);
      // Counting the photos reads files: the screen starts in real time.
      await tester.runAsync(() async {
        await tester.pumpWidget(app(CustomerExportScreen(installation: i)));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      expect(find.text('Familie Geheim'), findsOneWidget);
      expect(find.text('Fotos mitnehmen'), findsOneWidget);
      expect(find.textContaining('Nur für deine eigenen Geräte'), findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(of: find.text('Datei erstellen und teilen'), matching: find.bySubtype<ButtonStyleButton>()),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('1400 pt: Export mit Inhalt links und Passwort rechts, Übernehmen mit Rückfragen rechts', (
      tester,
    ) async {
      late List<CustomerImportItem> items;
      late CustomerFile file;
      late Installation first;
      await tester.runAsync(() async {
        final key = await fill();
        first = installs.active;
        file = await _reopen(await buildCustomerFile());
        await device();
        final target = await installs.create('Haus Geheim', key: key);
        await store.saveRecord(target.id, const CustomerRecord(customer: 'Familie Geheim', phone: '0171-000'));
        items = await planCustomerImport(file);
      });
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Offset at(String text) => tester.getTopLeft(find.text(text));

      await tester.pumpWidget(app(CustomerExportScreen(installation: first)));
      await tester.pump();
      expect(at('Inhalt').dx, lessThan(100));
      expect(at('Passwort').dx, greaterThan(700));
      expect(at('Passwort').dy, at('Inhalt').dy);
      expect(at('Passwort').dy, lessThan(200));
      expect(at('Datei erstellen und teilen').dx, greaterThan(700));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(app(CustomerImportScreen(file: file, items: items)));
      await tester.pump();
      expect(at('Auf diesem Gerät').dx, lessThan(100));
      expect(at('Kundendaten weichen ab').dx, greaterThan(700));
      expect(at('Kundendaten weichen ab').dy, at('Auf diesem Gerät').dy);
      expect(at('Kundendaten weichen ab').dy, lessThan(200));
      expect(at('Übernehmen').dx, greaterThan(700));
      expect(tester.takeException(), isNull);

      // Nothing to decide: one column, the button below the list.
      await tester.pumpWidget(
        app(
          CustomerImportScreen(
            key: UniqueKey(),
            file: file,
            items: [
              for (final i in items)
                CustomerImportItem(
                  entry: i.entry,
                  installation: i.installation,
                  recordDiffers: false,
                  newVisits: i.newVisits,
                  newDocuments: i.newDocuments,
                  newPhotos: i.newPhotos,
                ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Kundendaten weichen ab'), findsNothing);
      expect(at('Übernehmen').dy, greaterThan(at('Auf diesem Gerät').dy));
      expect(tester.getCenter(find.text('Übernehmen')).dx, closeTo(700, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('375 pt breit, Textgröße 2.0: Export und Übernehmen ohne Überlauf', (tester) async {
      late List<CustomerImportItem> items;
      late CustomerFile file;
      late Installation first;
      await tester.runAsync(() async {
        await _loadFonts();
        final key = await fill();
        first = installs.active;
        file = await _reopen(await buildCustomerFile());
        await device();
        final target = await installs.create('Haus Geheim', key: key);
        await store.saveRecord(target.id, const CustomerRecord(customer: 'Familie Geheim', phone: '0171-000'));
        items = [
          ...await planCustomerImport(file),
          CustomerImportItem(
            entry: const CustomerFileEntry(key: null, name: 'Mehrfamilienhaus Beispielstraße Hinterhaus'),
            installation: null,
            recordDiffers: false,
            newVisits: 0,
            newDocuments: 0,
            newPhotos: 0,
          ),
        ];
      });
      phone(tester, height: 667);
      await tester.pumpWidget(app(CustomerImportScreen(file: file, items: items), scale: 2));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.dragUntilVisible(find.text('Übernehmen'), find.byType(ListView), const Offset(0, -300));
      expect(tester.takeException(), isNull);
      expect(
        tester
            .getSize(find.ancestor(of: find.text('Übernehmen'), matching: find.bySubtype<ButtonStyleButton>()))
            .height,
        greaterThanOrEqualTo(44),
      );
      await tester.pumpWidget(app(CustomerExportScreen(installation: first), scale: 2));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.dragUntilVisible(
        find.text('Datei erstellen und teilen'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
