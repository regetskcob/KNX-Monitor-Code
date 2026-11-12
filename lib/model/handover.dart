import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import 'keys.dart';
import 'recording.dart';
import 'project_states.dart';

/// Where an installation at the customer's comes from: stored as
/// `handover_origin.json` in the installation's folder; it enables "An die Firma
/// melden" (report to the company).
@immutable
class HandoverOrigin {
  const HandoverOrigin({
    required this.handover,
    required this.origin,
    required this.contact,
    required this.created,
    this.key,
    this.installationName,
  });

  /// ID of the handover package.
  final String handover;

  /// ID of the installation at the electrician's.
  final String origin;

  /// Installation key from the package (docs/keys.md); `null` for older packages.
  final String? key;
  final PackageContact contact;
  final DateTime created;

  /// Name of the installation as the package had it: a later package without a key is matched by
  /// it even after the customer renamed the installation. `null` when stored by an older app.
  final String? installationName;

  Map<String, Object?> toJson() => {
    'handover': handover,
    'origin': origin,
    'key': ?key,
    'contact': contact.toJson(),
    'created': created.millisecondsSinceEpoch,
    'installation': ?installationName,
  };

  factory HandoverOrigin.fromJson(Map<String, Object?> j) => HandoverOrigin(
    handover: j['handover']! as String,
    origin: j['origin'] as String? ?? '',
    key: switch (j['key']) {
      final String k when isKey(k) => k,
      _ => null,
    },
    contact: PackageContact.fromJson((j['contact'] as Map? ?? const {}).cast()),
    created: DateTime.fromMillisecondsSinceEpoch(j['created'] as int? ?? 0),
    installationName: j['installation'] is String ? j['installation']! as String : null,
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
    final installations = InstallationStore.instance;
    origin = await read(installations.active.id);
    // The installation carries the key from its package. If an older app version dropped it
    // from the index, it comes back from here.
    if (origin?.key case final key? when installations.switchable && installations.byKey(key) == null) {
      await installations.setKey(installations.active.id, key);
    }
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
    // A placeholder (add-on on an older server) says nothing about the installation.
    key: active.keyIsPlaceholder ? null : active.key,
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

/// How an opened package relates to the installations on this device.
enum HandoverMatch {
  /// Nothing here belongs to it: it becomes a new installation.
  none,

  /// The only installation is still empty (fresh app), or there is only one (add-on): it goes
  /// there, as announced before the package was opened.
  first,

  /// This very package was opened here before.
  samePackage,

  /// A later package for an installation that came by handover: same installation key, or (for
  /// packages and installations from before keys) same company and same installation.
  followUp,
}

/// Where [applyHandover] would put a package.
@immutable
class HandoverTarget {
  const HandoverTarget(this.match, [this.installation]);

  final HandoverMatch match;

  /// `null` for [HandoverMatch.none].
  final Installation? installation;

  /// The installation holds a project from an earlier package: the user decides whether this
  /// package updates it or becomes an installation of its own. Never replaced without asking.
  bool get asks => match == HandoverMatch.samePackage || match == HandoverMatch.followUp;
}

String _norm(String text) => text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Whether [p] is a later package for the installation [origin] describes.
///
/// 1. Both carry an installation key (docs/keys.md): the key decides, and nothing else.
/// 2. Otherwise (a package or an installation from before keys, or an add-on that only holds a
///    placeholder): the same company, and either the same installation id at the electrician's
///    (only an id that is unique beyond one device, not `default`) or the same installation name
///    as in the earlier package.
bool isFollowUp(HandoverPackage p, HandoverOrigin origin, {required Installation installation}) {
  final key = p.key;
  if (key != null && origin.key != null) return origin.key == key;
  // An installation that kept its key from a package made before the origin stored it.
  if (key != null && installation.key == key) return true;
  final company = _norm(p.contact.name);
  if (company.isEmpty || company != _norm(origin.contact.name)) return false;
  if (isRandomInstallationId(p.origin) && p.origin == origin.origin) return true;
  final name = _norm(p.installationName);
  return name.isNotEmpty && name == _norm(origin.installationName ?? installation.name);
}

/// Where [p] belongs on this device.
///
/// Only an installation that came by handover itself is ever a target: on the electrician's own
/// device the package must never overwrite the installation it was made from.
Future<HandoverTarget> handoverTarget(HandoverPackage p) async {
  final installations = InstallationStore.instance;
  (Installation, HandoverOrigin)? same;
  (Installation, HandoverOrigin)? later;
  for (final i in installations.list) {
    final origin = await HandoverStore.read(i.id);
    if (origin == null) continue;
    if (origin.handover == p.id) {
      same ??= (i, origin);
    } else if (isFollowUp(p, origin, installation: i) && (later == null || origin.created.isAfter(later.$2.created))) {
      // Several (the user set one package up as a new installation): the most recent one.
      later = (i, origin);
    }
  }
  if (same != null) return HandoverTarget(HandoverMatch.samePackage, same.$1);
  if (later != null) return HandoverTarget(HandoverMatch.followUp, later.$1);
  final active = installations.active;
  // Freshly installed: take over the empty first installation. In the add-on
  // there is only the one anyway.
  final empty =
      CatalogStore.instance.catalog.isEmpty &&
      !KeyringStore.instance.loaded &&
      active.gateway == null &&
      active.name == InstallationStore.defaultName;
  return empty || !installations.switchable
      ? HandoverTarget(HandoverMatch.first, active)
      : const HandoverTarget(HandoverMatch.none);
}

/// What a package changes in an installation that is here already: shown before the user decides.
@immutable
class HandoverChanges {
  const HandoverChanges({
    this.groupsAdded = 0,
    this.groupsRemoved = 0,
    this.groupsRenamed = 0,
    this.devicesAdded = 0,
    this.devicesRemoved = 0,
    this.devicesRenamed = 0,
    this.packageHasKeys = false,
    this.installationHasKeys,
  });

  final int groupsAdded;
  final int groupsRemoved;
  final int groupsRenamed;
  final int devicesAdded;
  final int devicesRemoved;
  final int devicesRenamed;

  /// The package brings a keyring: it replaces the one stored here.
  final bool packageHasKeys;

  /// Whether the installation has a keyring now; `null` if that is not known without switching
  /// to it. Without keys in the package the stored ones are removed.
  final bool? installationHasKeys;

  bool get groupsChanged => groupsAdded + groupsRemoved + groupsRenamed > 0;
  bool get devicesChanged => devicesAdded + devicesRemoved + devicesRenamed > 0;
}

const _catalogFile = 'catalog.json';
const _namesFile = 'name_overrides.json';

/// Files of an installation that [applyHandover] rewrites (`CatalogStore`, `KeyringStore`,
/// [HandoverStore]); everything else in its folder is the customer's and stays.
const _handoverFiles = [
  _catalogFile,
  // Adopting the package's project adds a project state; a failed update must not leave it behind,
  // or old recordings would be named by an import that never took effect.
  projectStatesPath,
  'dpt_overrides.json',
  _namesFile,
  KeyringStore.sequencePath,
  HandoverStore.file,
];

/// Compares [p] with what installation [target] holds now. Reads its files, so it also works for
/// one that is not active. Unreadable files count as empty: the question is still asked.
Future<HandoverChanges> handoverChanges(HandoverPackage p, Installation target) async {
  final storage = HandoverStore._storage(target.id);
  var current = GroupCatalog.empty;
  var names = const <int, String>{};
  try {
    if (await storage.read(_catalogFile) case final text?) {
      current = GroupCatalog.fromJson((jsonDecode(text) as Map).cast());
    }
    if (await storage.read(_namesFile) case final text?) {
      names = {
        for (final MapEntry(:key, :value) in (jsonDecode(text) as Map).entries)
          if ((int.tryParse('$key'), value) case (final int address, final String name)) address: name,
      };
    }
  } on Object catch (e) {
    debugPrint('Übergabe: bisheriger Stand nicht lesbar: $e');
  }
  final groups = p.catalog.groups;
  final devices = p.catalog.devices;
  return HandoverChanges(
    groupsAdded: groups.keys.where((a) => !current.groups.containsKey(a)).length,
    groupsRemoved: current.groups.keys.where((a) => !groups.containsKey(a)).length,
    groupsRenamed: groups.values
        .where(
          (g) => current.groups[g.address] != null && (names[g.address] ?? current.groups[g.address]!.name) != g.name,
        )
        .length,
    devicesAdded: devices.keys.where((a) => !current.devices.containsKey(a)).length,
    devicesRemoved: current.devices.keys.where((a) => !devices.containsKey(a)).length,
    devicesRenamed: devices.values
        .where((d) => current.devices[d.address] != null && current.devices[d.address]!.name != d.name)
        .length,
    packageHasKeys: p.hasKeys,
    installationHasKeys: target.id == InstallationStore.instance.active.id ? KeyringStore.instance.loaded : null,
  );
}

/// Called before each step of [applyHandover] with its name; a test lets one fail.
@visibleForTesting
void Function(String step)? debugHandoverStep;

/// State of an installation before a package updates it, to put it back if a step fails.
class _Before {
  _Before(this.installation);

  final Installation installation;
  final files = <String, String?>{};
  String? catalogName;
  Map<String, Object?>? keyring;
  late ConnectionMode mode;
  int? tunnelAddress;
  late int routingAddress;
  late int secureUserId;

  static String get _catalogNameKey => InstallationStore.instance.key('catalog_name');

  /// Call with [installation] active.
  static Future<_Before> take(Installation installation) async {
    final before = _Before(installation);
    final storage = HandoverStore._storage(installation.id);
    for (final f in _handoverFiles) {
      before.files[f] = await storage.read(f);
    }
    before.catalogName = (await SharedPreferences.getInstance()).getString(_catalogNameKey);
    before.keyring = await KeyringStore.instance.exportStored();
    final options = ConnectionOptions.instance;
    before
      ..mode = options.mode
      ..tunnelAddress = options.tunnelAddress
      ..routingAddress = options.routingAddress
      ..secureUserId = options.secureUserId;
    return before;
  }

  /// Puts everything back. One step failing does not keep the others from running.
  Future<void> restore() async {
    Future<void> step(Future<void> Function() run) async {
      try {
        await run();
      } on Object catch (e) {
        debugPrint('Übergabe: Zurücksetzen unvollständig: $e');
      }
    }

    final storage = HandoverStore._storage(installation.id);
    // The keyring first: clearing it removes the counters file, which is written back below.
    await step(() async {
      if (keyring case final keys?) {
        await KeyringStore.instance.adoptStored(keys);
      } else {
        await KeyringStore.instance.clear();
      }
    });
    for (final MapEntry(key: file, value: text) in files.entries) {
      await step(() => text == null ? storage.delete(file) : storage.write(file, text));
    }
    await step(() async {
      final prefs = await SharedPreferences.getInstance();
      final name = catalogName;
      await (name == null ? prefs.remove(_catalogNameKey) : prefs.setString(_catalogNameKey, name));
    });
    await step(() {
      ConnectionOptions.instance
        ..mode = mode
        ..tunnelAddress = tunnelAddress
        ..routingAddress = routingAddress
        ..secureUserId = secureUserId;
      return ConnectionOptions.instance.save();
    });
    await step(() => InstallationStore.instance.restore(installation));
    await step(InstallationStore.reloadStores);
  }
}

/// Imports an opened package: into the installation [handoverTarget] names, otherwise (or with
/// [asNew]) into a new one. Project, gateway, connection type, keys, origin. Only call without an
/// active connection, and for a target that [HandoverTarget.asks] only after the user agreed.
///
/// The customer's own data in an updated installation stays: long-term history, charts, watchers,
/// comments, recordings and settings are not touched. If a step fails, a newly created
/// installation is removed again and an updated one is put back as it was.
Future<Installation> applyHandover(HandoverPackage p, {bool asNew = false}) async {
  final installations = InstallationStore.instance;
  final previous = installations.active.id;
  // The add-on has one installation: nothing can be set up next to it.
  final existing = asNew && installations.switchable ? null : (await handoverTarget(p)).installation;
  // The installation keeps its key here. Not if it is on this device already (the electrician
  // opens their own package, or the user wants a second installation): two installations here
  // never share a key.
  final key = installations.byKey(p.key) == null ? p.key : null;
  final target = existing ?? await installations.create(p.installationName, gateway: p.gateway, key: key);
  _Before? before;
  try {
    if (target.id != previous) await installations.switchTo(target.id);
    if (existing != null) before = await _Before.take(installations.byId(target.id) ?? target);
    debugHandoverStep?.call('catalog');
    await CatalogStore.instance.adopt(
      p.catalog,
      name: '${p.installationName}.$handoverExtension',
      overrides: p.overrides,
      projectNames: p.projectNames,
    );
    debugHandoverStep?.call('keys');
    if (p.keyring case final keys?) {
      await KeyringStore.instance.adoptStored(keys);
    } else if (KeyringStore.instance.loaded) {
      // Newer package without keys or add-on: leave nothing old behind.
      await KeyringStore.instance.clear();
    }
    debugHandoverStep?.call('connection');
    final options = ConnectionOptions.instance;
    final c = p.connection;
    options
      ..mode = ConnectionMode.values.asNameMap()[c['mode']] ?? ConnectionMode.udp
      ..tunnelAddress = c['tunnelAddress'] as int?
      ..routingAddress = c['routingAddress'] as int? ?? options.routingAddress
      ..secureUserId = c['secureUserId'] as int? ?? options.secureUserId;
    await options.save();
    debugHandoverStep?.call('origin');
    await HandoverStore.instance.write(
      target.id,
      HandoverOrigin(
        handover: p.id,
        origin: p.origin,
        contact: p.contact,
        created: p.created,
        key: p.key,
        installationName: p.installationName,
      ),
    );
    debugHandoverStep?.call('index');
    // Last: name and gateway in the index. In the add-on the server manages the installation;
    // its name stays there.
    if (existing != null && installations.switchable) {
      await installations.adopt(target.id, name: p.installationName, gateway: p.gateway);
    }
    return installations.byId(target.id) ?? target;
  } on Object {
    await before?.restore();
    if (installations.byId(previous) != null && installations.active.id != previous) {
      await installations.switchTo(previous);
    }
    if (existing == null) await installations.delete(target.id);
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
    key: origin.key,
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
