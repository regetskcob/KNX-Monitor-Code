import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../knx/group_catalog.dart';
import '../knx/secure/package_crypto.dart';
import '../model/installation.dart';
import '../model/keys.dart';
import '../platform/safe_zip.dart';
import 'diagnostics_bundle.dart';

/// File extension of the handover package and the fault report.
const handoverExtension = 'knxhandover';
const faultReportExtension = 'knxreport';

const handoverFormat = 'knx-monitor-handover';
const handoverFormatVersion = 1;
const faultReportFormat = 'knx-monitor-fault-report';
const faultReportFormatVersion = 1;

/// Largest file that is opened and largest unpacked content of an entry: a foreign file must not
/// fill up memory.
const packageMaxBytes = 512 * 1024 * 1024;
const packageMaxEntry = 256 * 1024 * 1024;

/// Why a file cannot be opened.
enum PackageProblem {
  /// Not a Busclear package, or damaged.
  corrupt,

  /// From a newer app version.
  newer,

  /// The password is missing or wrong (or the file was modified).
  wrongPassword,

  /// Unpacks to more than the app accepts.
  tooLarge,
}

class PackageException implements Exception {
  const PackageException(this.problem);
  final PackageProblem problem;

  @override
  String toString() => 'PackageException($problem)';
}

/// What a file is, without reading all of it.
enum PackageKind {
  handover,
  faultReport,

  /// The electrician's own customer files for a second device (`lib/export/customer_file.dart`).
  customerFile,
}

/// Head of a customer file; here so [packageKindOf] can tell the three apart.
const customerFileHeadName = 'customers.json';

/// Own contact details in a package: what the customer sees.
@immutable
class PackageContact {
  const PackageContact({this.name = '', this.address = '', this.phone = '', this.email = '', this.website = ''});

  final String name;
  final String address;
  final String phone;
  final String email;
  final String website;

  static const _maxLength = 400;

  Map<String, Object?> toJson() => {
    'name': name,
    if (address.isNotEmpty) 'address': address,
    if (phone.isNotEmpty) 'phone': phone,
    if (email.isNotEmpty) 'email': email,
    if (website.isNotEmpty) 'website': website,
  };

  /// Texts from foreign files: limited to a reasonable length.
  factory PackageContact.fromJson(Map<String, Object?> j) {
    String text(String key) {
      final v = j[key];
      if (v is! String) return '';
      return v.length > _maxLength ? v.substring(0, _maxLength) : v;
    }

    return PackageContact(
      name: text('name'),
      address: text('address'),
      phone: text('phone'),
      email: text('email'),
      website: text('website'),
    );
  }
}

/// The readable header of a handover package: enough for the question "Open?". For an encrypted
/// package it is part of the authenticated data.
@immutable
class HandoverManifest {
  const HandoverManifest({
    required this.id,
    required this.created,
    required this.installationName,
    required this.contact,
    required this.encrypted,
    required this.hasKeys,
    required this.groups,
    required this.devices,
  });

  final String id;
  final DateTime created;
  final String installationName;
  final PackageContact contact;
  final bool encrypted;
  final bool hasKeys;
  final int groups;
  final int devices;
}

/// Content of the handover package: names and structure, gateway, optionally keys. Deliberately not
/// the whole ETS project and no customer data.
@immutable
class HandoverPackage {
  const HandoverPackage({
    required this.id,
    required this.created,
    required this.installationName,
    required this.contact,
    required this.origin,
    required this.catalog,
    this.key,
    this.overrides = const {},
    this.projectNames = const {},
    this.gateway,
    this.connection = const {},
    this.keyring,
  });

  /// Identifier of this package; opening the same package twice replaces the installation.
  final String id;
  final DateTime created;
  final String installationName;
  final PackageContact contact;

  /// ID of the installation at the electrician: a fault report uses it to find its way back.
  final String origin;

  /// Installation key (docs/keys.md): the installation keeps it at the customer's, so electrician
  /// and customer mean the same one. `null` in packages from before keys existed.
  final String? key;
  final GroupCatalog catalog;
  final Map<int, Dpt> overrides;

  /// Project names of addresses whose name was corrected in the app; [catalog] has the corrected
  /// ones (`CatalogStore.projectNames`).
  final Map<int, String> projectNames;
  final GatewayRef? gateway;

  /// Connection type, tunnel address, routing source (no passwords).
  final Map<String, Object?> connection;

  /// Keyring as in the [KeyringStore] (only with password protection).
  final Map<String, Object?>? keyring;

  bool get hasKeys => keyring != null;

  static const _manifestName = 'handover.json';
  static const _plainName = 'payload.json';
  static const _sealedName = 'payload.enc';

  Map<String, Object?> _manifest({Uint8List? salt, Uint8List? nonce}) => {
    'format': handoverFormat,
    'version': handoverFormatVersion,
    'id': id,
    'created': created.toIso8601String(),
    'installation': installationName,
    'contact': contact.toJson(),
    'encrypted': salt != null,
    'hasKeys': hasKeys,
    'contents': {'groups': catalog.length, 'devices': catalog.devices.length},
    if (salt != null && nonce != null) ...{
      'kdf': {'name': 'PBKDF2-HMAC-SHA256', 'iterations': packageKdfIterations, 'salt': base64Encode(salt)},
      'cipher': {'name': 'AES-256-GCM', 'nonce': base64Encode(nonce)},
    },
  };

  Map<String, Object?> _payload() => {
    'origin': origin,
    'key': ?key,
    'catalog': catalog.toJson(),
    'overrides': {
      for (final MapEntry(:key, :value) in overrides.entries) '$key': [value.main, value.sub],
    },
    if (projectNames.isNotEmpty)
      'projectNames': {for (final MapEntry(:key, :value) in projectNames.entries) '$key': value},
    'gateway': ?gateway?.toJson(),
    'connection': connection,
    'keyring': ?keyring,
  };

  /// The file. With keys, [password] is mandatory so they never sit in plain text on a USB stick or
  /// in an e-mail.
  Uint8List toFile({String? password}) {
    if (hasKeys && (password == null || password.isEmpty)) {
      throw ArgumentError('Schlüssel nur mit Passwort');
    }
    final payload = utf8.encode(jsonEncode(_payload()));
    final archive = Archive();
    void add(String name, List<int> bytes) => archive.addFile(ArchiveFile(name, bytes.length, bytes));
    if (password == null || password.isEmpty) {
      add(_manifestName, utf8.encode(jsonEncode(_manifest())));
      add(_plainName, payload);
    } else {
      // The header is fixed before encryption and includes salt and nonce: draw them first, build
      // the header, then encrypt with the header as AAD.
      final salt = randomBytes(16);
      final nonce = randomBytes(12);
      final manifest = utf8.encode(jsonEncode(_manifest(salt: salt, nonce: nonce)));
      final compressed = Uint8List.fromList(const GZipEncoder().encode(payload));
      final key = deriveKey(password, salt, packageKdfIterations);
      final cipher = aesGcm(encrypt: true, key: key, nonce: nonce, aad: Uint8List.fromList(manifest), data: compressed);
      add(_manifestName, manifest);
      add(_sealedName, cipher);
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// Reads only the header. Throws [PackageException].
  static HandoverManifest readManifest(Uint8List bytes) {
    final (:map, raw: _) = _head(openPackageArchive(bytes));
    try {
      return _parseManifest(map);
    } on Object {
      throw const PackageException(PackageProblem.corrupt);
    }
  }

  static HandoverManifest _parseManifest(Map<String, Object?> m) {
    final contents = (m['contents'] as Map?) ?? const {};
    return HandoverManifest(
      id: m['id']! as String,
      created: DateTime.parse(m['created']! as String),
      installationName: m['installation'] as String? ?? '',
      contact: PackageContact.fromJson((m['contact'] as Map? ?? const {}).cast()),
      encrypted: m['encrypted'] == true,
      hasKeys: m['hasKeys'] == true,
      groups: contents['groups'] as int? ?? 0,
      devices: contents['devices'] as int? ?? 0,
    );
  }

  /// Opens the package. [key] comes from [keyFor] (a separate step, because derivation takes time
  /// and can use Web Crypto in the browser). Throws [PackageException].
  static HandoverPackage open(Uint8List bytes, {Uint8List? key}) {
    final archive = openPackageArchive(bytes);
    final (:map, :raw) = _head(archive);
    try {
      final manifest = _parseManifest(map);
      final Map<String, Object?> payload;
      if (manifest.encrypted) {
        if (key == null) throw const PackageException(PackageProblem.wrongPassword);
        final (salt: _, :nonce, iterations: _) = _sealParams(map);
        final sealed = packageEntry(archive, _sealedName);
        if (sealed == null) throw const PackageException(PackageProblem.corrupt);
        final plain = unseal(sealed, key: key, nonce: nonce, aad: raw);
        final json = utf8.decode(const GZipDecoder().decodeBytes(plain, maxOutputSize: packageMaxEntry));
        payload = (jsonDecode(json) as Map).cast();
      } else {
        final plain = packageEntry(archive, _plainName);
        if (plain == null) throw const PackageException(PackageProblem.corrupt);
        payload = (jsonDecode(utf8.decode(plain)) as Map).cast();
      }
      return HandoverPackage(
        id: manifest.id,
        created: manifest.created,
        installationName: manifest.installationName,
        contact: manifest.contact,
        origin: payload['origin'] as String? ?? '',
        key: switch (payload['key']) {
          final String k when isKey(k) => k,
          _ => null,
        },
        catalog: GroupCatalog.fromJson((payload['catalog']! as Map).cast()),
        overrides: {
          for (final MapEntry(:key, :value) in ((payload['overrides'] as Map?) ?? const {}).entries)
            int.parse(key as String): Dpt((value as List)[0] as int, value[1] as int?),
        },
        projectNames: {
          for (final MapEntry(:key, :value) in ((payload['projectNames'] as Map?) ?? const {}).entries)
            int.parse(key as String): value as String,
        },
        gateway: payload['gateway'] == null ? null : GatewayRef.fromJson((payload['gateway']! as Map).cast()),
        connection: ((payload['connection'] as Map?) ?? const {}).cast(),
        keyring: (payload['keyring'] as Map?)?.cast(),
      );
    } on PackageException {
      rethrow;
    } on PackageDecryptException {
      throw const PackageException(PackageProblem.wrongPassword);
    } on Object catch (e) {
      debugPrint('Übergabepaket beschädigt: $e');
      throw const PackageException(PackageProblem.corrupt);
    }
  }

  static ({Uint8List salt, Uint8List nonce, int iterations}) _sealParams(Map<String, Object?> m) {
    final kdf = (m['kdf']! as Map).cast<String, Object?>();
    final cipher = (m['cipher']! as Map).cast<String, Object?>();
    final iterations = kdf['iterations']! as int;
    if (kdf['name'] != 'PBKDF2-HMAC-SHA256' ||
        cipher['name'] != 'AES-256-GCM' ||
        iterations < 1 ||
        iterations > packageKdfMaxIterations) {
      throw const PackageException(PackageProblem.corrupt);
    }
    return (
      salt: base64Decode(kdf['salt']! as String),
      nonce: base64Decode(cipher['nonce']! as String),
      iterations: iterations,
    );
  }

  /// Key parameters of a package, without decrypting it.
  static ({Uint8List salt, int iterations}) keyParams(Uint8List bytes) {
    try {
      final (:map, raw: _) = _head(openPackageArchive(bytes));
      final (:salt, nonce: _, :iterations) = _sealParams(map);
      return (salt: salt, iterations: iterations);
    } on PackageException {
      rethrow;
    } on Object {
      throw const PackageException(PackageProblem.corrupt);
    }
  }

  static ({Map<String, Object?> map, Uint8List raw}) _head(Archive archive) {
    final raw = packageEntry(archive, _manifestName);
    if (raw == null) throw const PackageException(PackageProblem.corrupt);
    final Map<String, Object?> map;
    try {
      map = (jsonDecode(utf8.decode(raw)) as Map).cast();
    } on Object {
      throw const PackageException(PackageProblem.corrupt);
    }
    if (map['format'] != handoverFormat) throw const PackageException(PackageProblem.corrupt);
    if ((map['version'] as int? ?? 0) > handoverFormatVersion) throw const PackageException(PackageProblem.newer);
    return (map: map, raw: raw);
  }
}

/// The ZIP of a package file within the limits ([packageMaxBytes], `decodeZipLimited`). Throws
/// [PackageException].
Archive openPackageArchive(Uint8List bytes) {
  if (bytes.length > packageMaxBytes) throw const PackageException(PackageProblem.corrupt);
  try {
    return decodeZipLimited(bytes);
  } on ZipLimitException {
    throw const PackageException(PackageProblem.tooLarge);
  } on Object {
    throw const PackageException(PackageProblem.corrupt);
  }
}

/// Content of one entry, `null` if it is missing. Throws [PackageException] above
/// [packageMaxEntry].
Uint8List? packageEntry(Archive archive, String name) {
  final file = archive.findFile(name);
  if (file == null) return null;
  if (file.size > packageMaxEntry) throw const PackageException(PackageProblem.corrupt);
  try {
    return Uint8List.fromList(file.content);
  } on Object {
    throw const PackageException(PackageProblem.corrupt);
  }
}

/// Type of the file, without a password; `null` if it is not one of our packages. Never throws:
/// used to route a picked file to the right place.
PackageKind? packageKindOf(Uint8List bytes) {
  if (!DiagnosticsPackage.looksLikeZip(bytes)) return null;
  try {
    final archive = openPackageArchive(bytes);
    if (archive.findFile('handover.json') != null) return PackageKind.handover;
    if (archive.findFile(customerFileHeadName) != null) return PackageKind.customerFile;
    if (archive.findFile(FaultReport.fileName) != null) return PackageKind.faultReport;
  } on Object catch (e) {
    debugPrint('Keine Paketdatei: $e');
  }
  return null;
}

/// Catalog for the customer: names, structure and associations, without serial numbers and
/// descriptions.
GroupCatalog handoverCatalog(GroupCatalog c) => GroupCatalog(
  {
    for (final g in c.groups.values)
      g.address: GroupInfo(address: g.address, name: g.name, path: g.path, dpt: g.dpt, links: g.links),
  },
  devices: {
    for (final d in c.devices.values)
      d.address: DeviceInfo(
        address: d.address,
        name: d.name,
        product: d.product,
        manufacturer: d.manufacturer,
        location: d.location,
        tunnelOf: d.tunnelOf,
        neverProgrammed: d.neverProgrammed,
        pendingDownload: d.pendingDownload,
        rf: d.rf,
      ),
  },
  projectName: c.projectName,
  manufacturers: c.manufacturers,
  style: c.style,
  externalSenders: c.externalSenders,
);

/// Fault report from the customer: a diagnostics package (without keys, Data Secure contents only
/// as metadata) plus the reference to the installation at the electrician.
@immutable
class FaultReport {
  const FaultReport({
    required this.id,
    required this.created,
    required this.origin,
    required this.installationName,
    required this.package,
    this.handover = '',
    this.key,
  });

  static const fileName = 'fault_report.json';

  final String id;
  final DateTime created;

  /// ID of the installation at the electrician (from the handover package).
  final String origin;

  /// ID of the handover package.
  final String handover;

  /// Installation key (docs/keys.md): finds the installation also on a device where it has
  /// another id than [origin] (a colleague's, a restored one).
  final String? key;
  final String installationName;
  final DiagnosticsPackage package;

  Uint8List toFile() => package.toZip(
    extra: {
      fileName: jsonEncode({
        'format': faultReportFormat,
        'version': faultReportFormatVersion,
        'id': id,
        'created': created.toIso8601String(),
        'origin': origin,
        'handover': handover,
        'key': ?key,
        'installation': installationName,
      }),
    },
  );

  /// Throws [PackageException].
  factory FaultReport.fromFile(Uint8List bytes) {
    final archive = openPackageArchive(bytes);
    final raw = packageEntry(archive, fileName);
    if (raw == null) throw const PackageException(PackageProblem.corrupt);
    try {
      final m = (jsonDecode(utf8.decode(raw)) as Map).cast<String, Object?>();
      if (m['format'] != faultReportFormat) throw const PackageException(PackageProblem.corrupt);
      if ((m['version'] as int? ?? 0) > faultReportFormatVersion) {
        throw const PackageException(PackageProblem.newer);
      }
      return FaultReport(
        id: m['id']! as String,
        created: DateTime.parse(m['created']! as String),
        origin: m['origin'] as String? ?? '',
        handover: m['handover'] as String? ?? '',
        key: switch (m['key']) {
          final String k when isKey(k) => k,
          _ => null,
        },
        installationName: m['installation'] as String? ?? '',
        package: DiagnosticsPackage.fromZip(bytes),
      );
    } on PackageException {
      rethrow;
    } on Object catch (e) {
      debugPrint('Störungsmeldung beschädigt: $e');
      throw const PackageException(PackageProblem.corrupt);
    }
  }
}
