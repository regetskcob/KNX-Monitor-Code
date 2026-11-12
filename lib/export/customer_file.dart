import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../knx/secure/package_crypto.dart';
import '../model/customer.dart';
import '../model/keys.dart';
import 'handover_package.dart';

/// File extension, format id and version of the customer file (docs/handover-format.md).
const customerFileExtension = 'knxcustomers';
const customerFileFormat = 'knx-monitor-customer-file';
const customerFileFormatVersion = 1;

/// Longest text taken from a file for one field of a record or a visit.
const customerFileMaxText = 20000;

final _documentName = RegExp(r'^[0-9A-Za-z_-]{1,40}\.json$');

/// Ids that end up in file paths: photos, recordings.
final _photoId = RegExp(r'^[0-9a-z]{1,32}$');

/// Whether [name] may name a protocol or service report from a file: it becomes a file name in
/// the installation's folder.
bool isCustomerDocumentName(String name) => _documentName.hasMatch(name);

/// A photo of the installation's photo documentation inside a customer file.
@immutable
class CustomerFilePhoto {
  const CustomerFilePhoto({required this.id, required this.caption, required this.at, required this.jpegBase64});

  final String id;
  final String caption;
  final DateTime at;

  /// The JPEG, base64 as it is stored.
  final String jpegBase64;

  Map<String, Object?> toJson() => {
    'id': id,
    'caption': caption,
    'at': at.toUtc().toIso8601String(),
    'jpeg': jpegBase64,
  };
}

/// The customer file of one installation.
@immutable
class CustomerFileEntry {
  const CustomerFileEntry({
    required this.key,
    required this.name,
    this.record = CustomerRecord.empty,
    this.visits = const [],
    this.protocols = const {},
    this.serviceReports = const {},
    this.photos = const [],
  });

  /// Installation key (docs/keys.md): what the second device finds the installation by. `null`
  /// if the installation only has a placeholder (add-on on an older server).
  final String? key;

  /// Name of the installation on the exporting device, for the list before taking over.
  final String name;
  final CustomerRecord record;
  final List<Visit> visits;

  /// Acceptance protocols and service reports: file name (`<timestamp>.json`, the document's id)
  /// to content as stored.
  final Map<String, Map<String, Object?>> protocols;
  final Map<String, Map<String, Object?>> serviceReports;
  final List<CustomerFilePhoto> photos;

  int get documents => protocols.length + serviceReports.length;

  Map<String, Object?> toJson() => {
    'key': ?key,
    'name': name,
    'record': record.toJson(),
    'visits': [for (final v in visits) v.toJson()],
    if (protocols.isNotEmpty) 'protocols': protocols,
    if (serviceReports.isNotEmpty) 'serviceReports': serviceReports,
    if (photos.isNotEmpty) 'photos': [for (final p in photos) p.toJson()],
  };

  /// From a file: wrong types, unusable names and ids are skipped, long texts cut.
  factory CustomerFileEntry.fromJson(Map<String, Object?> j) {
    String cut(Object? v) =>
        v is! String ? '' : (v.length > customerFileMaxText ? v.substring(0, customerFileMaxText) : v);
    Map<String, Map<String, Object?>> documents(Object? v) => {
      if (v is Map)
        for (final MapEntry(:key, :value) in v.entries)
          if (key is String && isCustomerDocumentName(key) && value is Map) key: value.cast<String, Object?>(),
    };
    final record = j['record'];
    final visits = <Visit>[];
    for (final v in j['visits'] is List ? j['visits']! as List : const <Object?>[]) {
      try {
        final map = (v! as Map).cast<String, Object?>();
        // Without an id a visit would be added again on every opening.
        if (map['id'] is! String) continue;
        final visit = Visit.fromJson(map);
        visits.add(
          Visit(
            id: cut(visit.id),
            time: visit.time,
            kind: visit.kind,
            text: cut(visit.text),
            minutes: visit.minutes,
            // A reference names a recording and so ends up in a file path.
            ref: visit.ref != null && _photoId.hasMatch(visit.ref!) ? visit.ref : null,
          ),
        );
      } on Object catch (e) {
        debugPrint('Kundenakte: Besuch übersprungen: $e');
      }
    }
    final photos = <CustomerFilePhoto>[];
    for (final p in j['photos'] is List ? j['photos']! as List : const <Object?>[]) {
      if (p case {'id': final String id, 'at': final String at, 'jpeg': final String jpeg} when _photoId.hasMatch(id)) {
        final time = DateTime.tryParse(at);
        if (time == null) continue;
        photos.add(CustomerFilePhoto(id: id, caption: cut(p['caption']), at: time.toLocal(), jpegBase64: jpeg));
      }
    }
    return CustomerFileEntry(
      key: switch (j['key']) {
        final String k when isKey(k) => k,
        _ => null,
      },
      name: cut(j['name']),
      record: record is Map
          ? CustomerRecord.fromJson({
              for (final MapEntry(:key, :value) in record.entries)
                if (key is String) key: value is String ? cut(value) : value,
            })
          : CustomerRecord.empty,
      visits: visits,
      protocols: documents(j['protocols']),
      serviceReports: documents(j['serviceReports']),
      photos: photos,
    );
  }
}

/// The readable head of a customer file: enough for the question "Open?". It names no customer.
@immutable
class CustomerFileManifest {
  const CustomerFileManifest({
    required this.id,
    required this.created,
    required this.company,
    required this.installations,
    required this.visits,
    required this.documents,
    required this.photos,
  });

  final String id;
  final DateTime created;

  /// Name of the own company at the time of the export.
  final String company;
  final int installations;
  final int visits;
  final int documents;
  final int photos;
}

/// The electrician's own customer files (record, visits, protocols, service reports, optionally
/// photos) of one or all installations, to take over on a second own device without a cloud.
///
/// Always password-protected, with the encryption of the handover package: a ZIP with the
/// readable head `customers.json` and `payload.enc` (gzip-compressed JSON, AES-256-GCM, key from
/// PBKDF2-HMAC-SHA256, the head as authenticated data). Never part of a handover package, a fault
/// report or a diagnostics package, and those never contain it.
@immutable
class CustomerFile {
  const CustomerFile({required this.id, required this.created, required this.entries, this.company = ''});

  final String id;
  final DateTime created;
  final String company;
  final List<CustomerFileEntry> entries;

  static const _sealedName = 'payload.enc';

  Map<String, Object?> _manifest(Uint8List salt, Uint8List nonce) => {
    'format': customerFileFormat,
    'version': customerFileFormatVersion,
    'id': id,
    'created': created.toIso8601String(),
    'company': company,
    'contents': {
      'installations': entries.length,
      'visits': entries.fold<int>(0, (n, e) => n + e.visits.length),
      'documents': entries.fold<int>(0, (n, e) => n + e.documents),
      'photos': entries.fold<int>(0, (n, e) => n + e.photos.length),
    },
    'kdf': {'name': 'PBKDF2-HMAC-SHA256', 'iterations': packageKdfIterations, 'salt': base64Encode(salt)},
    'cipher': {'name': 'AES-256-GCM', 'nonce': base64Encode(nonce)},
  };

  Map<String, Object?> _payload() => {
    'installations': [for (final e in entries) e.toJson()],
  };

  /// The file. Customer data never leaves in plain text: without a [password] it throws
  /// [ArgumentError]. Throws [PackageException] ([PackageProblem.tooLarge]) if the content is more
  /// than a device would open again.
  Uint8List toFile({required String password}) {
    if (password.isEmpty) throw ArgumentError('Kundenakten nur mit Passwort');
    final payload = utf8.encode(jsonEncode(_payload()));
    if (payload.length > packageMaxEntry) throw const PackageException(PackageProblem.tooLarge);
    final salt = randomBytes(16);
    final nonce = randomBytes(12);
    final manifest = utf8.encode(jsonEncode(_manifest(salt, nonce)));
    final compressed = Uint8List.fromList(const GZipEncoder().encode(payload));
    final key = deriveKey(password, salt, packageKdfIterations);
    final cipher = aesGcm(encrypt: true, key: key, nonce: nonce, aad: Uint8List.fromList(manifest), data: compressed);
    final archive = Archive()
      ..addFile(ArchiveFile(customerFileHeadName, manifest.length, manifest))
      ..addFile(ArchiveFile(_sealedName, cipher.length, cipher));
    final file = Uint8List.fromList(ZipEncoder().encode(archive));
    if (file.length > packageMaxBytes) throw const PackageException(PackageProblem.tooLarge);
    return file;
  }

  /// Reads only the head. Throws [PackageException].
  static CustomerFileManifest readManifest(Uint8List bytes) {
    final (:map, raw: _) = _head(openPackageArchive(bytes));
    try {
      return _parseManifest(map);
    } on Object {
      throw const PackageException(PackageProblem.corrupt);
    }
  }

  static CustomerFileManifest _parseManifest(Map<String, Object?> m) {
    final contents = (m['contents'] as Map?) ?? const {};
    final company = m['company'] as String? ?? '';
    return CustomerFileManifest(
      id: m['id']! as String,
      created: DateTime.parse(m['created']! as String),
      company: company.length > 400 ? company.substring(0, 400) : company,
      installations: contents['installations'] as int? ?? 0,
      visits: contents['visits'] as int? ?? 0,
      documents: contents['documents'] as int? ?? 0,
      photos: contents['photos'] as int? ?? 0,
    );
  }

  /// Key parameters of a file, without decrypting it. Throws [PackageException].
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

  /// Opens the file with the [key] derived from the password ([keyParams]). Throws
  /// [PackageException]: a wrong password and a modified file (head included) are the same error.
  static CustomerFile open(Uint8List bytes, {required Uint8List key}) {
    final archive = openPackageArchive(bytes);
    final (:map, :raw) = _head(archive);
    try {
      final manifest = _parseManifest(map);
      final (salt: _, :nonce, iterations: _) = _sealParams(map);
      final sealed = packageEntry(archive, _sealedName);
      if (sealed == null) throw const PackageException(PackageProblem.corrupt);
      final plain = unseal(sealed, key: key, nonce: nonce, aad: raw);
      final json = utf8.decode(const GZipDecoder().decodeBytes(plain, maxOutputSize: packageMaxEntry));
      final payload = (jsonDecode(json) as Map).cast<String, Object?>();
      return CustomerFile(
        id: manifest.id,
        created: manifest.created,
        company: manifest.company,
        entries: [for (final e in payload['installations']! as List) CustomerFileEntry.fromJson((e as Map).cast())],
      );
    } on PackageException {
      rethrow;
    } on PackageDecryptException {
      throw const PackageException(PackageProblem.wrongPassword);
    } on Object catch (e) {
      debugPrint('Kundenakten-Datei beschädigt: $e');
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

  static ({Map<String, Object?> map, Uint8List raw}) _head(Archive archive) {
    final raw = packageEntry(archive, customerFileHeadName);
    if (raw == null) throw const PackageException(PackageProblem.corrupt);
    final Map<String, Object?> map;
    try {
      map = (jsonDecode(utf8.decode(raw)) as Map).cast();
    } on Object {
      throw const PackageException(PackageProblem.corrupt);
    }
    if (map['format'] != customerFileFormat) throw const PackageException(PackageProblem.corrupt);
    if ((map['version'] as int? ?? 0) > customerFileFormatVersion) throw const PackageException(PackageProblem.newer);
    return (map: map, raw: raw);
  }
}
