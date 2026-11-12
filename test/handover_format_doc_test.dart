import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx/knx.dart' show GroupStyle;
import 'package:knx_monitor/export/customer_file.dart';
import 'package:knx_monitor/export/handover_package.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/secure/package_crypto.dart';
import 'package:knx_monitor/model/customer.dart';
import 'package:knx_monitor/model/handover.dart';
import 'package:knx_monitor/model/incoming_file.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/model/site_photos.dart';
import 'package:knx_monitor/platform/safe_zip.dart';

// Keeps docs/handover-format.md honest: every field the code writes into a handover package, a
// fault report or a customer file is named there, the numbers are the code's, and the Python
// example really opens a protected package.

const _key = '0b6a1c1e-7d0e-4f6e-9a55-3f2a9c01be77';
const _password = 'ABCD-EFGH-JKMN';

/// Maps whose keys are data (addresses, file names), not field names.
const _dataKeyed = {'overrides', 'projectNames', 'manufacturers', 'groupKeys', 'sequence', 'deviceAuthentication'};

/// Documents inside a customer file are stored as the app wrote them and described elsewhere.
const _opaque = {'protocols', 'serviceReports'};

/// Field names in [json], recursively.
Set<String> _fields(Object? json) {
  final out = <String>{};
  void walk(Object? v) {
    if (v is List) {
      v.forEach(walk);
    } else if (v is Map) {
      for (final MapEntry(:key, :value) in v.entries) {
        out.add(key as String);
        if (_opaque.contains(key)) continue;
        if (_dataKeyed.contains(key)) {
          (value as Map).values.forEach(walk);
        } else {
          walk(value);
        }
      }
    }
  }

  walk(json);
  return out;
}

Map<String, Object?> _json(Archive zip, String name) =>
    (jsonDecode(utf8.decode(zip.findFile(name)!.content)) as Map).cast<String, Object?>();

HandoverPackage _handover() => HandoverPackage(
  id: 'paket1',
  created: DateTime(2026, 11, 10, 14, 3),
  installationName: 'Haus-Muster',
  contact: const PackageContact(
    name: 'Elektro Muster',
    address: 'Weg 1',
    phone: '0123',
    email: 'a@example.com',
    website: 'example.com',
  ),
  origin: '3f2a9c01be77',
  key: _key,
  // Through the same reduction as a real package, from a catalog that uses every field.
  catalog: handoverCatalog(
    GroupCatalog(
      {
        0x0801: const GroupInfo(
          address: 0x0801,
          name: 'Licht Küche Insel',
          path: 'EG › Küche',
          dpt: Dpt(1, 1),
          description: 'intern',
          links: [
            GroupLink(
              device: 0x1101,
              object: 3,
              text: 'Schalten',
              sends: true,
              flags: ComFlags(write: true, transmit: true),
              ref: 'O-3_R-1',
            ),
          ],
        ),
      },
      devices: {
        0x1101: const DeviceInfo(
          address: 0x1101,
          name: 'Aktor',
          product: 'Schaltaktor 8-fach',
          manufacturer: 'Hersteller',
          location: 'Keller',
          description: 'intern',
          serial: '0083AABBCCDD',
          neverProgrammed: true,
          pendingDownload: [DownloadPart.address],
          rf: true,
        ),
        0x1102: const DeviceInfo(address: 0x1102, name: 'Aktor · Tunnel 1', tunnelOf: 0x1101),
      },
      projectName: 'Haus Muster',
      manufacturers: const {131: 'Hersteller'},
      style: GroupStyle.twoLevel,
      externalSenders: const {0x1201},
    ),
  ),
  overrides: const {0x0801: Dpt(1, 2)},
  projectNames: const {0x0801: 'Licht Küche'},
  gateway: const GatewayRef(host: '192.168.1.22', serial: '00AB', mac: '00:11', name: 'GIRA X1'),
  connection: const {'mode': 'secure', 'tunnelAddress': 0x11F1, 'routingAddress': 0x00FE, 'secureUserId': 3},
  keyring: const {
    'project': 'Haus Muster',
    'groupKeys': {'2049': 'MTIzNDU2Nzg5MDEyMzQ1Ng=='},
    'sequence': {'4353': 5},
    'tunnels': [
      {'address': 0x11F1, 'host': 0x11FF, 'userId': 3, 'password': 'TunnelGeheim'},
    ],
    'deviceAuthentication': {'4353': 'code'},
  },
);

CustomerFile _customers() => CustomerFile(
  id: 'akten1',
  created: DateTime(2026, 11, 12),
  company: 'Elektro Muster',
  entries: [
    CustomerFileEntry(
      key: _key,
      name: 'Haus Muster',
      record: CustomerRecord(
        customer: 'Familie Muster',
        site: 'Weg 1',
        contact: 'Frau Muster',
        phone: '0171',
        email: 'm@example.com',
        notes: 'Keller',
        orderNumber: 'K-1',
        maintenanceMonths: 12,
        maintenanceSince: DateTime(2026),
      ),
      visits: [
        Visit(
          id: 'v1',
          time: DateTime(2026, 11, 1),
          kind: VisitKind.faultReport,
          text: 'x',
          minutes: 45,
          ref: 'k3x9f0',
        ),
      ],
      protocols: const {
        '1794300100000.json': {'inside': 1},
      },
      serviceReports: const {
        '1794300200000.json': {'inside': 1},
      },
      photos: [CustomerFilePhoto(id: 'k3xa10', caption: 'Verteiler', at: DateTime(2026, 11, 10), jpegBase64: '/9j/')],
    ),
  ],
);

void main() {
  final doc = File('docs/handover-format.md').readAsStringSync();

  void expectDocumented(Set<String> fields, String where) {
    expect(fields, isNotEmpty);
    for (final field in fields) {
      expect(doc, contains('`$field`'), reason: '$where: Feld „$field“ fehlt in docs/handover-format.md');
    }
  }

  test('Übergabepaket: jedes geschriebene Feld von Kopf und Inhalt steht im Dokument', () {
    final package = _handover();
    final plain = ZipDecoder().decodeBytes(
      HandoverPackage(
        id: package.id,
        created: package.created,
        installationName: package.installationName,
        contact: package.contact,
        origin: package.origin,
        key: package.key,
        catalog: package.catalog,
        overrides: package.overrides,
        projectNames: package.projectNames,
        gateway: package.gateway,
        connection: package.connection,
      ).toFile(),
    );
    final sealed = ZipDecoder().decodeBytes(package.toFile(password: _password));
    expect(plain.files.map((f) => f.name).toSet(), {'handover.json', 'payload.json'});
    expect(sealed.files.map((f) => f.name).toSet(), {'handover.json', 'payload.enc'});
    for (final name in ['handover.json', 'payload.json', 'payload.enc']) {
      expect(doc, contains('`$name`'));
    }
    expectDocumented({..._fields(_json(plain, 'handover.json')), ..._fields(_json(sealed, 'handover.json'))}, 'Kopf');
    final payload = _fields(_json(plain, 'payload.json'));
    // The catalog in the test uses every optional field the reduction keeps.
    expect(payload, containsAll(['l', 'f', 'r', 'tu', 'np', 'pd', 'rf', 'xs', 'style', 'serial', 'mac']));
    expect(payload, isNot(contains('sn')), reason: 'Seriennummern der Geräte sind nie im Paket');
    expectDocumented(payload, 'Inhalt');
    expectDocumented(_fields(package.keyring), 'Schlüsselbund');
  });

  test('Störungsmeldung und Herkunft: jedes Feld steht im Dokument', () {
    final report = buildFaultReport(
      origin: HandoverOrigin(
        handover: 'paket1',
        origin: '3f2a9c01be77',
        key: _key,
        contact: const PackageContact(name: 'Elektro Muster'),
        created: DateTime(2026, 11, 10),
        installationName: 'Haus Muster',
      ),
      installationName: 'Haus Muster',
      telegrams: const [],
      catalog: GroupCatalog.empty,
      since: DateTime(2026, 11, 12, 8),
      problem: 'Licht',
      now: DateTime(2026, 11, 12, 9),
    );
    final zip = ZipDecoder().decodeBytes(report.toFile());
    expect(doc, contains('`${FaultReport.fileName}`'));
    expectDocumented(_fields(_json(zip, FaultReport.fileName)), 'Störungsmeldung');
    final origin = HandoverOrigin(
      handover: 'paket1',
      origin: '3f2a9c01be77',
      key: _key,
      contact: const PackageContact(name: 'Elektro Muster'),
      created: DateTime(2026, 11, 10),
      installationName: 'Haus Muster',
    ).toJson();
    expect(doc, contains('`${HandoverStore.file}`'));
    for (final field in origin.keys) {
      expect(doc, contains('`$field`'), reason: 'Herkunft: $field');
    }
  });

  test('Kundenakten: jedes geschriebene Feld von Kopf und Inhalt steht im Dokument', () async {
    final file = _customers();
    final zip = ZipDecoder().decodeBytes(file.toFile(password: _password));
    expect(zip.files.map((f) => f.name).toSet(), {customerFileHeadName, 'payload.enc'});
    expect(doc, contains('`$customerFileHeadName`'));
    expectDocumented(_fields(_json(zip, customerFileHeadName)), 'Kopf');
    // The content as it is written, before encryption.
    final content = {
      'installations': [for (final e in file.entries) e.toJson()],
    };
    final fields = _fields(content);
    expect(fields, containsAll(['record', 'visits', 'protocols', 'serviceReports', 'photos', 'jpeg', 'r', 'm']));
    expectDocumented(fields, 'Inhalt');
    for (final kind in VisitKind.values) {
      expect(doc, contains('`${kind.name}`'), reason: 'Besuchsart ${kind.name}');
    }
  });

  test('Kennungen, Endungen und Grenzen im Dokument sind die des Codes', () {
    String mib(int bytes) => '${bytes ~/ (1024 * 1024)} MiB';
    String thousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');
    for (final text in [
      '`$handoverFormat`',
      '`$faultReportFormat`',
      '`$customerFileFormat`',
      '`.$handoverExtension`',
      '`.$faultReportExtension`',
      '`.$customerFileExtension`',
      '"version": $handoverFormatVersion',
      '"version": $faultReportFormatVersion',
      '"version": $customerFileFormatVersion',
      '"iterations": $packageKdfIterations',
      thousands(packageKdfIterations),
      thousands(packageKdfMaxIterations),
      mib(packageMaxBytes),
      mib(packageMaxEntry),
      mib(incomingMaxBytes),
      '${defaultZipLimits.maxTotalBytes ~/ (1024 * 1024 * 1024)} GiB',
      thousands(defaultZipLimits.maxEntries),
      '${thousands(customerFileMaxText)} characters',
      '${sitePhotoQuotaBytes ~/ (1024 * 1024)} MB',
      'PBKDF2-HMAC-SHA256',
      'AES-256-GCM',
    ]) {
      expect(doc, contains(text), reason: text);
    }
    // The alphabet of generated passwords, as the document quotes it.
    final password = generatePackagePassword().replaceAll('-', '');
    final alphabet = RegExp(r'24 characters out of\s+`([^`]+)`').firstMatch(doc)![1]!;
    expect(password.length, 24);
    expect(password.split('').every(alphabet.contains), isTrue);
    expect(File('docs/README.md').readAsStringSync(), contains('(handover-format.md)'));
  });

  test('Python-Beispiel aus dem Dokument öffnet ein geschütztes Paket und eine Kundenakten-Datei', () async {
    final example = RegExp(r'```python\n(.*?)```', dotAll: true).firstMatch(doc)![1]!;
    final probe = await Process.run('python3', [
      '-c',
      'import cryptography',
    ]).onError((_, _) => ProcessResult(0, 1, '', 'python3 fehlt'));
    if (probe.exitCode != 0) {
      markTestSkipped('python3 mit dem Paket „cryptography“ ist hier nicht installiert');
      return;
    }
    final dir = await Directory.systemTemp.createTemp('handover_doc');
    addTearDown(() => dir.delete(recursive: true));
    await File('${dir.path}/Haus-Muster.knxhandover').writeAsBytes(_handover().toFile(password: _password));
    // The password as someone would type it: lower case, with spaces.
    Future<ProcessResult> run(String code, String password) async {
      await File('${dir.path}/example.py').writeAsString(code);
      return Process.run('python3', [
        '-c',
        'import getpass\ngetpass.getpass = lambda prompt="": ${jsonEncode(password)}\nexec(open("example.py").read())',
      ], workingDirectory: dir.path);
    }

    final ok = await run(example, 'abcd efgh jkmn');
    expect(ok.exitCode, 0, reason: '${ok.stderr}');
    expect(ok.stdout, contains('Haus-Muster 1 group addresses'));
    final wrong = await run(example, 'FALSCH');
    expect(wrong.exitCode, isNot(0));
    expect(wrong.stderr, contains('InvalidTag'));

    // "The same code opens customer files: the head is customers.json there."
    await File('${dir.path}/akten.knxcustomers').writeAsBytes(_customers().toFile(password: _password));
    final customers = example
        .replaceAll('Haus-Muster.knxhandover', 'akten.knxcustomers')
        .replaceAll('handover.json', customerFileHeadName)
        .replaceAll(RegExp(r'print\(.*\)'), 'print(payload["installations"][0]["record"]["customer"])');
    final opened = await run(customers, _password);
    expect(opened.exitCode, 0, reason: '${opened.stderr}');
    expect(opened.stdout, contains('Familie Muster'));
  });
}
