import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../catalog_store.dart';
import '../export/diagnostics_bundle.dart';
import '../export/handover_package.dart';
import '../knx/group_catalog.dart';
import '../knx/secure/keyring_store.dart';
import '../knx/secure/package_crypto.dart';
import '../knx/telegram.dart';
import '../platform/pbkdf2.dart';
import '../platform/storage.dart';
import 'annotation.dart';
import 'company.dart';
import 'connection_options.dart';
import 'customer.dart';
import 'installation.dart';
import 'recording.dart';

/// Where an installation at the customer's comes from: stored as
/// `handover_origin.json` in the installation's folder; it enables "An die Firma
/// melden" (report to the company).
@immutable
class HandoverOrigin {
  const HandoverOrigin({required this.handover, required this.origin, required this.contact, required this.created});

  /// ID of the handover package.
  final String handover;

  /// ID of the installation at the electrician's.
  final String origin;
  final PackageContact contact;
  final DateTime created;

  Map<String, Object?> toJson() => {
    'handover': handover,
    'origin': origin,
    'contact': contact.toJson(),
    'created': created.millisecondsSinceEpoch,
  };

  factory HandoverOrigin.fromJson(Map<String, Object?> j) => HandoverOrigin(
    handover: j['handover']! as String,
    origin: j['origin'] as String? ?? '',
    contact: PackageContact.fromJson((j['contact'] as Map? ?? const {}).cast()),
    created: DateTime.fromMillisecondsSinceEpoch(j['created'] as int? ?? 0),
  );
}

/// Origin of the active installation (at the customer's).
class HandoverStore extends ChangeNotifier {
  HandoverStore._();

  static final instance = HandoverStore._();

  static const file = 'handover_origin.json';

  HandoverOrigin? origin;

  static AppStorage _storage(String id) =>
      kIsWeb ? AppStorage.instance : ScopedStorage(AppStorage.instance, 'installations/$id/');

  /// A broken file just means: no origin.
  static Future<HandoverOrigin?> read(String id) async {
    try {
      final text = await _storage(id).read(file);
      return text == null ? null : HandoverOrigin.fromJson((jsonDecode(text) as Map).cast());
    } on Object catch (e) {
      debugPrint('Herkunft nicht lesbar: $e');
      return null;
    }
  }

  Future<void> load() async {
    origin = await read(InstallationStore.instance.active.id);
    notifyListeners();
  }

  Future<void> write(String id, HandoverOrigin value) async {
    await _storage(id).write(file, jsonEncode(value.toJson()));
    if (id == InstallationStore.instance.active.id) {
      origin = value;
      notifyListeners();
    }
  }
}

/// Our own contact from the company details.
PackageContact companyContact(Company c) =>
    PackageContact(name: c.name, address: c.address, phone: c.phone, email: c.email, website: c.website);

/// Assembles the package of the active installation. Customer data stays out.
Future<HandoverPackage> buildHandover({required bool includeKeys, DateTime? now}) async {
  final installations = InstallationStore.instance;
  final active = installations.active;
  final catalog = CatalogStore.instance;
  final options = ConnectionOptions.instance;
  final time = now ?? DateTime.now();
  return HandoverPackage(
    id: time.microsecondsSinceEpoch.toRadixString(36),
    created: time,
    installationName: active.name,
    contact: companyContact(CompanyStore.instance.company),
    origin: active.id,
    catalog: handoverCatalog(catalog.catalog),
    overrides: Map.of(catalog.overrides),
    projectNames: catalog.projectNames,
    gateway: active.gateway,
    connection: {
      'mode': options.mode.name,
      'tunnelAddress': ?options.tunnelAddress,
      'routingAddress': options.routingAddress,
      'secureUserId': options.secureUserId,
    },
    keyring: includeKeys ? await KeyringStore.instance.exportStored() : null,
  );
}

/// Derivation in a background isolate, in the browser via Web Crypto (otherwise
/// pure Dart): the derivation is deliberately noticeably slow.
Future<Uint8List> packageKey(String password, Uint8List salt, int iterations) async {
  if (kIsWeb) {
    final native = await nativePbkdf2Sha256(passwordBytes(password), salt, iterations, 32);
    if (native != null) return Uint8List.fromList(native);
    return deriveKey(password, salt, iterations);
  }
  return compute(_deriveTask, (password, salt, iterations));
}

Uint8List _deriveTask((String, Uint8List, int) a) => deriveKey(a.$1, a.$2, a.$3);

/// [HandoverPackage.toFile] off the UI thread, where isolates exist.
Future<Uint8List> packageToFile(HandoverPackage p, {String? password}) =>
    kIsWeb ? Future.value(p.toFile(password: password)) : compute(_fileTask, (p, password));

Uint8List _fileTask((HandoverPackage, String?) a) => a.$1.toFile(password: a.$2);

/// Opens a package with the password. Throws [PackageException].
Future<HandoverPackage> openHandover(Uint8List bytes, {String? password}) async {
  final manifest = HandoverPackage.readManifest(bytes);
  if (!manifest.encrypted) return HandoverPackage.open(bytes);
  if (password == null || password.isEmpty) throw const PackageException(PackageProblem.wrongPassword);
  final params = HandoverPackage.keyParams(bytes);
  final key = await packageKey(password, params.salt, params.iterations);
  return HandoverPackage.open(bytes, key: key);
}

/// Whether importing this package needs a new installation (for the tier
/// limit). Not if it already exists or the active one is still empty.
Future<bool> handoverNeedsNewInstallation(String handoverId) async => await _targetFor(handoverId) == null;

Future<Installation?> _targetFor(String handoverId) async {
  final installations = InstallationStore.instance;
  for (final i in installations.list) {
    if ((await HandoverStore.read(i.id))?.handover == handoverId) return i;
  }
  final active = installations.active;
  // Freshly installed: take over the empty first installation. In the add-on
  // there is only the one anyway.
  final empty =
      CatalogStore.instance.catalog.isEmpty &&
      !KeyringStore.instance.loaded &&
      active.gateway == null &&
      active.name == InstallationStore.defaultName;
  return empty || !installations.switchable ? active : null;
}

/// Imports an opened package: new installation (or the same one if this package
/// was opened before), project, gateway, connection type, keys, origin. Only
/// call without an active connection. If a step fails, the newly created
/// installation is removed again.
Future<Installation> applyHandover(HandoverPackage p) async {
  final installations = InstallationStore.instance;
  final previous = installations.active.id;
  final existing = await _targetFor(p.id);
  final target = existing ?? await installations.create(p.installationName, gateway: p.gateway);
  try {
    if (target.id != previous) await installations.switchTo(target.id);
    // In the add-on the server manages the installation; its name stays there.
    if (existing != null && installations.switchable) {
      await installations.adopt(target.id, name: p.installationName, gateway: p.gateway);
    }
    await CatalogStore.instance.adopt(
      p.catalog,
      name: '${p.installationName}.$handoverExtension',
      overrides: p.overrides,
      projectNames: p.projectNames,
    );
    if (p.keyring case final keys?) {
      await KeyringStore.instance.adoptStored(keys);
    } else if (KeyringStore.instance.loaded) {
      // Newer package without keys or add-on: leave nothing old behind.
      await KeyringStore.instance.clear();
    }
    final options = ConnectionOptions.instance;
    final c = p.connection;
    options
      ..mode = ConnectionMode.values.asNameMap()[c['mode']] ?? ConnectionMode.udp
      ..tunnelAddress = c['tunnelAddress'] as int?
      ..routingAddress = c['routingAddress'] as int? ?? options.routingAddress
      ..secureUserId = c['secureUserId'] as int? ?? options.secureUserId;
    await options.save();
    await HandoverStore.instance.write(
      target.id,
      HandoverOrigin(handover: p.id, origin: p.origin, contact: p.contact, created: p.created),
    );
    return installations.byId(target.id) ?? target;
  } on Object {
    if (existing == null && installations.byId(previous) != null) {
      await installations.switchTo(previous);
      await installations.delete(target.id);
    }
    rethrow;
  }
}

/// Builds the fault report: no keys, Data Secure content only as time and
/// addresses, the customer's texts unchanged except for network addresses.
/// Screenshots only on request ([includeShots]); without [keepNames], names are
/// replaced as in the diagnostic package.
FaultReport buildFaultReport({
  required HandoverOrigin origin,
  required String installationName,
  required List<Telegram> telegrams,
  required GroupCatalog catalog,
  required DateTime since,
  required String problem,
  Map<String, Object?> technical = const {},
  List<String> log = const [],
  List<Annotation> annotations = const [],
  Map<String, Uint8List> shots = const {},
  Map<int, Dpt> overrides = const {},
  Set<int> secureAddresses = const {},
  bool keepNames = true,
  Iterable<String> knownNames = const [],
  bool includeShots = false,
  DateTime? now,
}) {
  final time = now ?? DateTime.now();
  return FaultReport(
    id: time.microsecondsSinceEpoch.toRadixString(36),
    created: time,
    origin: origin.origin,
    handover: origin.handover,
    installationName: installationName,
    package: buildDiagnosticsPackage(
      telegrams: telegrams,
      catalog: catalog,
      occurred: annotations.lastOrNull?.time ?? time,
      overrides: overrides,
      from: since,
      to: time,
      problem: problem,
      secureAddresses: secureAddresses,
      technical: technical,
      log: log,
      annotations: annotations,
      shots: shots,
      includeShots: includeShots,
      keepNames: keepNames,
      knownNames: knownNames,
      now: time,
    ),
  );
}

/// Stores an incoming report in installation [installationId]: a recording with
/// comments and screenshots, plus an entry in the history. Opening the same
/// report twice creates no duplicates. Returns the ID of the recording.
Future<String> receiveFaultReport(FaultReport report, String installationId) async {
  final customers = CustomerStore.instance;
  final key = 'fault:${report.id}';
  for (final v in customers.visits(installationId)) {
    if (v.id == key && v.ref != null) return v.ref!;
  }
  final package = report.package;
  // Screenshots under new IDs, as when opening a diagnostic package.
  final ids = <String, String>{};
  for (final (i, MapEntry(key: id, value: jpeg)) in package.shots.entries.indexed) {
    ids[id] = await ShotStore.instance.put(jpeg, id: '${Annotation.newId()}${i.toRadixString(36)}', checkQuota: false);
  }
  List<String> remap(List<String> shots) => [for (final id in shots) ?ids[id]];
  final p = package.recording;
  // Never the ID from the file: it ends up in a file path.
  final recordingId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  await RecordingStore.instance.save(
    Recording(
      id: recordingId,
      name: report.installationName.isEmpty ? p.name : '${report.installationName} · ${p.name}',
      note: package.problem.isEmpty ? null : package.problem,
      started: p.started,
      ended: p.ended,
      installation: installationId,
      telegrams: p.telegrams,
      annotations: [for (final a in p.annotations) a.copyWith(shots: remap(a.shots))],
      diagnostics: {
        'created': package.created.toIso8601String(),
        'occurred': package.occurred.toIso8601String(),
        'problem': package.problem,
        'expected': ?package.expected,
        'namesIncluded': package.namesIncluded,
        'technical': package.technical,
        'log': package.log,
        'shots': remap(package.packageShots),
        'secureTelegrams': package.secureTelegrams.length,
      },
    ),
  );
  await customers.saveVisit(
    installationId,
    Visit(id: key, time: report.created, kind: VisitKind.faultReport, text: package.problem, ref: recordingId),
  );
  return recordingId;
}
