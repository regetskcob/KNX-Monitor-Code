import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../export/customer_file.dart';
import '../export/handover_package.dart';
import '../platform/storage.dart';
import 'company.dart';
import 'customer.dart';
import 'handover.dart' show packageKey;
import 'installation.dart';
import 'site_photos.dart';

// Folders of the documents in an installation's folder (`AcceptanceStore`, `ServiceReportStore`,
// `SitePhotoStore`). Read and written as stored, so a document arrives byte for byte.
const _protocolsDir = 'protocols';
const _reportsDir = 'service_reports';
const _photosDir = SitePhotoStore.dir;
const _photosList = SitePhotoStore.path;

String _photoFile(String id) => '$_photosDir/$id.jpg.b64';

Future<Map<String, Map<String, Object?>>> _documents(AppStorage storage, String dir) async {
  final out = <String, Map<String, Object?>>{};
  for (final f in await storage.list(dir)) {
    if (!isCustomerDocumentName(f.name)) continue;
    try {
      final text = await storage.read('$dir/${f.name}');
      if (text != null) out[f.name] = (jsonDecode(text) as Map).cast();
    } on Object catch (e) {
      debugPrint('Kundenakte: ${f.name} nicht lesbar: $e');
    }
  }
  return out;
}

Future<List<SitePhoto>> _photoList(AppStorage storage) async {
  try {
    final text = await storage.read(_photosList);
    if (text == null) return [];
    return [
      for (final j in jsonDecode(text) as List)
        if (j is Map) ?_photo(j),
    ];
  } on Object catch (e) {
    debugPrint('Kundenakte: Fotoliste nicht lesbar: $e');
    return [];
  }
}

SitePhoto? _photo(Map<Object?, Object?> j) {
  try {
    final photo = SitePhoto.fromJson(j);
    return SitePhotoStore.validId(photo.id) ? photo : null;
  } on Object {
    return null;
  }
}

/// How many photos the installations [ids] have, for the switch before the export.
Future<int> customerPhotoCount(Iterable<String> ids) async {
  var n = 0;
  for (final id in ids) {
    n += (await _photoList(CustomerStore.storageOf(id))).length;
  }
  return n;
}

/// Installations whose customer file has anything to export: a record, visits, a protocol, a
/// service report or a photo. A file can consist of documents alone (a protocol without a record).
Future<List<Installation>> customerExportScope() async {
  final withRecord = {
    for (final e in CustomerStore.instance.entries)
      if (!e.record.isEmpty || e.visits.isNotEmpty) e.installation.id,
  };
  final out = <Installation>[];
  for (final i in InstallationStore.instance.list) {
    if (withRecord.contains(i.id)) {
      out.add(i);
      continue;
    }
    final storage = CustomerStore.storageOf(i.id);
    try {
      final hasDocument =
          (await storage.list(_protocolsDir)).any((f) => isCustomerDocumentName(f.name)) ||
          (await storage.list(_reportsDir)).any((f) => isCustomerDocumentName(f.name));
      if (hasDocument || (await _photoList(storage)).isNotEmpty) out.add(i);
    } on Object catch (e) {
      debugPrint('Kundenakte: Ordner von ${i.id} nicht lesbar: $e');
    }
  }
  return out;
}

/// The customer file of installation [i] as it is stored now.
Future<CustomerFileEntry> customerFileEntry(Installation i, {bool includePhotos = false}) async {
  final store = CustomerStore.instance;
  final storage = CustomerStore.storageOf(i.id);
  final photos = <CustomerFilePhoto>[];
  if (includePhotos) {
    for (final p in await _photoList(storage)) {
      final jpeg = await storage.read(_photoFile(p.id));
      if (jpeg != null) photos.add(CustomerFilePhoto(id: p.id, caption: p.caption, at: p.at, jpegBase64: jpeg));
    }
  }
  return CustomerFileEntry(
    // A placeholder (add-on on an older server) says nothing about the installation.
    key: i.keyIsPlaceholder ? null : i.key,
    name: i.name,
    record: store.record(i.id),
    visits: store.visits(i.id),
    protocols: await _documents(storage, _protocolsDir),
    serviceReports: await _documents(storage, _reportsDir),
    photos: photos,
  );
}

/// Assembles the customer files of [installations] (default: all that have one). Installations
/// without a record, a visit or a document are left out when all are exported.
Future<CustomerFile> buildCustomerFile({
  Iterable<Installation>? installations,
  bool includePhotos = false,
  DateTime? now,
}) async {
  final time = now ?? DateTime.now();
  final entries = <CustomerFileEntry>[];
  for (final i in installations ?? InstallationStore.instance.list) {
    final entry = await customerFileEntry(i, includePhotos: includePhotos);
    final empty = entry.record.isEmpty && entry.visits.isEmpty && entry.documents == 0 && entry.photos.isEmpty;
    if (installations == null && empty) continue;
    entries.add(entry);
  }
  return CustomerFile(
    id: time.microsecondsSinceEpoch.toRadixString(36),
    created: time,
    company: CompanyStore.instance.company.name,
    entries: entries,
  );
}

/// [CustomerFile.toFile] off the UI thread, where isolates exist.
Future<Uint8List> customerFileToBytes(CustomerFile file, {required String password}) =>
    kIsWeb ? Future.sync(() => file.toFile(password: password)) : compute(_fileTask, (file, password));

Uint8List _fileTask((CustomerFile, String) a) => a.$1.toFile(password: a.$2);

/// Opens a customer file with its password. Throws [PackageException].
Future<CustomerFile> openCustomerFile(Uint8List bytes, {required String password}) async {
  CustomerFile.readManifest(bytes);
  if (password.isEmpty) throw const PackageException(PackageProblem.wrongPassword);
  final params = CustomerFile.keyParams(bytes);
  final key = await packageKey(password, params.salt, params.iterations);
  return CustomerFile.open(bytes, key: key);
}

/// What taking over one installation's customer file would do.
@immutable
class CustomerImportItem {
  const CustomerImportItem({
    required this.entry,
    required this.installation,
    required this.recordDiffers,
    required this.newVisits,
    required this.newDocuments,
    required this.newPhotos,
  });

  final CustomerFileEntry entry;

  /// The installation on this device with the entry's key; `null` if there is none.
  final Installation? installation;

  /// Both devices hold a record and the two are not the same: the user decides which one counts.
  /// An empty record here takes the file's without a question.
  final bool recordDiffers;
  final int newVisits;
  final int newDocuments;
  final int newPhotos;

  /// Nothing in the file that this device does not have.
  bool get upToDate =>
      installation != null && !recordDiffers && !takesRecord && newVisits + newDocuments + newPhotos == 0;

  /// The record here is empty and the file has one.
  bool get takesRecord =>
      installation != null && !entry.record.isEmpty && CustomerStore.instance.record(installation!.id).isEmpty;
}

bool _sameRecord(CustomerRecord a, CustomerRecord b) => jsonEncode(a.toJson()) == jsonEncode(b.toJson());

/// Matches the entries of [file] to the installations here, by installation key (docs/keys.md)
/// and by nothing else: a name can be the same for two customers.
Future<List<CustomerImportItem>> planCustomerImport(CustomerFile file) async {
  final installations = InstallationStore.instance;
  final store = CustomerStore.instance;
  final items = <CustomerImportItem>[];
  final seen = <String>{};
  for (final entry in file.entries) {
    final target = installations.byKey(entry.key);
    // The same installation twice in one file: only the first one counts.
    if (target != null && !seen.add(target.id)) continue;
    if (target == null) {
      items.add(
        CustomerImportItem(
          entry: entry,
          installation: null,
          recordDiffers: false,
          newVisits: entry.visits.length,
          newDocuments: entry.documents,
          newPhotos: entry.photos.length,
        ),
      );
      continue;
    }
    final storage = CustomerStore.storageOf(target.id);
    final local = store.record(target.id);
    final visits = {for (final v in store.visits(target.id)) v.id};
    final protocols = {for (final f in await storage.list(_protocolsDir)) f.name};
    final reports = {for (final f in await storage.list(_reportsDir)) f.name};
    final photos = {for (final p in await _photoList(storage)) p.id};
    items.add(
      CustomerImportItem(
        entry: entry,
        installation: target,
        recordDiffers: !local.isEmpty && !entry.record.isEmpty && !_sameRecord(local, entry.record),
        newVisits: {for (final v in entry.visits) v.id}.difference(visits).length,
        newDocuments:
            entry.protocols.keys.where((n) => !protocols.contains(n)).length +
            entry.serviceReports.keys.where((n) => !reports.contains(n)).length,
        newPhotos: {for (final p in entry.photos) p.id}.difference(photos).length,
      ),
    );
  }
  return items;
}

/// What [applyCustomerImport] did.
@immutable
class CustomerImportResult {
  const CustomerImportResult({
    this.installations = 0,
    this.created = 0,
    this.records = 0,
    this.visits = 0,
    this.documents = 0,
    this.photos = 0,
    this.photosSkipped = 0,
  });

  /// Installations whose file was looked at (matched or created).
  final int installations;
  final int created;
  final int records;
  final int visits;
  final int documents;
  final int photos;

  /// Photos that did not fit into the installation's photo limit or were not readable images.
  final int photosSkipped;
}

/// Takes over the customer files of [items] ([planCustomerImport]).
///
/// Merging only ever adds: a visit, protocol, service report or photo whose id is here already
/// stays as it is here and is not added twice, so opening the same file again changes nothing.
/// The record is taken when this device has none; where both have one and they differ, only for
/// the installations in [takeRecordFor] (installation ids here). [createMissing] sets up an empty
/// installation with the entry's key and name for entries that have none here; without it they
/// are skipped. The caller checks the tier limit.
Future<CustomerImportResult> applyCustomerImport(
  List<CustomerImportItem> items, {
  Set<String> takeRecordFor = const {},
  bool createMissing = false,
}) async {
  final installations = InstallationStore.instance;
  final store = CustomerStore.instance;
  var count = 0, created = 0, records = 0, visits = 0, documents = 0, photos = 0, skipped = 0;
  for (final item in items) {
    final entry = item.entry;
    var target = item.installation == null ? null : installations.byId(item.installation!.id);
    if (target == null) {
      if (!createMissing || !installations.switchable) continue;
      target = await installations.create(
        entry.name.trim().isEmpty ? InstallationStore.defaultName : entry.name,
        key: entry.key,
      );
      created++;
    }
    count++;
    final id = target.id;
    final storage = CustomerStore.storageOf(id);
    final local = store.record(id);
    if (!entry.record.isEmpty && !_sameRecord(local, entry.record) && (local.isEmpty || takeRecordFor.contains(id))) {
      await store.saveRecord(id, entry.record);
      records++;
    }
    visits += await store.mergeVisits(id, entry.visits);
    for (final (dir, files) in [(_protocolsDir, entry.protocols), (_reportsDir, entry.serviceReports)]) {
      final known = {for (final f in await storage.list(dir)) f.name};
      for (final MapEntry(key: name, value: content) in files.entries) {
        if (known.contains(name) || !isCustomerDocumentName(name)) continue;
        await storage.write('$dir/$name', jsonEncode(content));
        documents++;
      }
    }
    if (entry.photos.isNotEmpty) {
      final list = await _photoList(storage);
      final known = {for (final p in list) p.id};
      var used = (await storage.list(_photosDir)).fold<int>(0, (n, f) => n + f.size);
      var added = false;
      for (final p in entry.photos) {
        if (known.contains(p.id)) continue;
        if (!SitePhotoStore.validId(p.id) ||
            !_isJpeg(p.jpegBase64) ||
            used + p.jpegBase64.length > sitePhotoQuotaBytes) {
          skipped++;
          continue;
        }
        await storage.write(_photoFile(p.id), p.jpegBase64);
        used += p.jpegBase64.length;
        known.add(p.id);
        list.add(SitePhoto(id: p.id, caption: p.caption, at: p.at));
        photos++;
        added = true;
      }
      // The list last: a photo file without an entry is harmless, an entry without its file is not.
      if (added) await storage.write(_photosList, jsonEncode([for (final p in list) p.toJson()]));
    }
  }
  if (photos > 0) await SitePhotoStore.instance.reload();
  return CustomerImportResult(
    installations: count,
    created: created,
    records: records,
    visits: visits,
    documents: documents,
    photos: photos,
    photosSkipped: skipped,
  );
}

/// Whether [base64] is a JPEG of a size the photo documentation accepts.
bool _isJpeg(String base64) {
  if (base64.length > sitePhotoMaxInput * 4 ~/ 3 + 4) return false;
  try {
    final bytes = base64Decode(base64);
    return bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8;
  } on FormatException {
    return false;
  }
}
