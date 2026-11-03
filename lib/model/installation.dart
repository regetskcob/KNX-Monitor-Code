import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../catalog_store.dart';
import '../knx/gateway_info.dart';
import '../knx/secure/keyring_store.dart';
import '../l10n/locale_controller.dart';
import '../platform/addon.dart';
import '../platform/file_cipher.dart';
import '../platform/storage.dart';
import 'annotation.dart';
import 'betrieb_mode.dart';
import 'export_history.dart';
import 'commissioning.dart';
import 'connection_options.dart';
import 'customer.dart';
import 'handover.dart';
import 'health.dart';
import 'history_store.dart';
import 'home_plan/home_plan_store.dart';
import 'pinned_sections.dart';
import 'site_photos.dart';

/// Gateway of an installation: the most recently used address, plus what the
/// device reveals about itself (the serial number identifies it even after an
/// IP change).
@immutable
class GatewayRef {
  const GatewayRef({required this.host, this.port = 3671, this.serial, this.mac, this.name});

  final String host;
  final int port;
  final String? serial;
  final String? mac;

  /// Device name from the DESCRIPTION_RESPONSE, e.g. "GIRA X1".
  final String? name;

  /// "192.168.1.22" or "192.168.1.22:3672".
  String get address => port == 3671 ? host : '$host:$port';

  Map<String, Object?> toJson() => {'host': host, 'port': port, 'serial': ?serial, 'mac': ?mac, 'name': ?name};

  factory GatewayRef.fromJson(Map<String, Object?> j) => GatewayRef(
    host: j['host']! as String,
    port: j['port'] as int? ?? 3671,
    serial: j['serial'] as String?,
    mac: j['mac'] as String?,
    name: j['name'] as String?,
  );
}

/// An installation (customer, site, home): its own gateway, ETS project,
/// keyring, health, commissioning, long-term history and settings.
@immutable
class Installation {
  const Installation({required this.id, required this.name, required this.created, this.gateway, this.lastUsed});

  final String id;
  final String name;
  final GatewayRef? gateway;
  final DateTime created;
  final DateTime? lastUsed;

  Installation copyWith({String? name, GatewayRef? gateway, DateTime? lastUsed}) => Installation(
    id: id,
    name: name ?? this.name,
    created: created,
    gateway: gateway ?? this.gateway,
    lastUsed: lastUsed ?? this.lastUsed,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'created': created.millisecondsSinceEpoch,
    'gateway': ?gateway?.toJson(),
    'lastUsed': ?lastUsed?.millisecondsSinceEpoch,
  };

  factory Installation.fromJson(Map<String, Object?> j) => Installation(
    id: j['id']! as String,
    name: j['name'] as String? ?? '',
    created: DateTime.fromMillisecondsSinceEpoch(j['created'] as int? ?? 0),
    gateway: j['gateway'] == null ? null : GatewayRef.fromJson((j['gateway']! as Map).cast<String, Object?>()),
    lastUsed: j['lastUsed'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['lastUsed']! as int),
  );
}

/// The installations and which one is currently active.
///
/// Natively, each installation's files live under `installations/<id>/`
/// ([storage]) and its settings under `inst:<id>:…` ([key]). In the Home
/// Assistant add-on (browser) there is exactly one: the server manages files
/// and switching itself, the app stays in the data folder root.
class InstallationStore extends ChangeNotifier {
  InstallationStore._();

  static final instance = InstallationStore._();

  static const _path = 'installations.json';

  /// Storage format. `version` stays 1 so older versions can read it; if it
  /// contains more than this app knows, the app touches nothing and says so (see [tooNew]).
  static const storageFormat = 2;

  /// The data comes from a newer app (store rollback). Then everything stays as it
  /// is: no new index, no stores, only the message.
  bool tooNew = false;
  static const _activeKey = 'installation_active';

  /// Name when none can be derived (add-on, empty migration).
  static const defaultName = 'Installation';

  /// Files of an installation (relative to its folder).
  static const files = [
    'catalog.json',
    'dpt_overrides.json',
    'health.json',
    'commissioning.json',
    'customer.json',
    'visits.json',
    'handover_origin.json',
    'site_photos.json',
    HomePlanStore.path,
  ];

  /// Folders with the installation's documents; deleted along with it (customer data).
  static const _paperDirs = ['protocols', 'service_reports', 'site_photos', HomePlanStore.imageDir];
  static const _historyDir = 'history';

  /// Settings that belong to an installation (global before the migration).
  static const scopedPrefs = [
    'conn_mode',
    'conn_tunnel_address',
    'conn_routing_address',
    'conn_secure_user',
    'gateway_host',
    'gateway_port',
    'gateway_history',
    'catalog_name',
    'catalog_csv',
    'pinned_sections',
    'collapsed_sections_v2',
    'saved_filters',
    'send_recent',
    'chart_last',
  ];

  /// Saved charts per project (`charts:<project>`) move along.
  static const _scopedPrefPrefixes = ['charts:'];

  List<Installation> _list = [];
  String? _activeId;

  /// Most recently used first.
  List<Installation> get list => List.unmodifiable(_list);

  Installation get active =>
      _list.where((i) => i.id == _activeId).firstOrNull ??
      _list.firstOrNull ??
      Installation(id: 'default', name: defaultName, created: DateTime.fromMillisecondsSinceEpoch(0));

  /// Whether switching is possible (not in the add-on).
  bool get switchable => !kIsWeb;

  /// File storage of the active installation.
  AppStorage get storage =>
      kIsWeb ? AppStorage.instance : ScopedStorage(AppStorage.instance, 'installations/${active.id}/');

  /// Settings key of the active installation.
  String key(String k) => kIsWeb ? k : scopedKey(active.id, k);

  static String scopedKey(String id, String k) => 'inst:$id:$k';

  Future<void> load() async {
    if (kIsWeb) {
      _list = [active];
      notifyListeners();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final root = AppStorage.instance;
    final text = await _readIndex(_path);
    if (_isNewer(text) || _isNewer(await _readIndex(_backupPath))) {
      debugPrint('Installationen: neueres Format, nichts angefasst');
      tooNew = true;
      _list = [];
      notifyListeners();
      return;
    }
    _list = text == null ? [] : _parse(text);
    if (_list.isEmpty) {
      // Index unreadable: do not simply overwrite it. Use the backup from the last
      // save first; the broken file stays for investigation.
      final backup = await _readIndex(_backupPath);
      _list = backup == null ? [] : _parse(backup);
      if (text != null) await keepCorrupt(root, _path, text);
      if (_list.isEmpty) _list = await _recover(prefs);
      if (_list.isNotEmpty) {
        debugPrint('Installationen: wiederhergestellt');
        await _save();
      } else {
        await _migrate(prefs);
      }
    }
    _activeId = prefs.getString(_activeKey);
    if (!_list.any((i) => i.id == _activeId)) _activeId = _list.first.id;
    _sort();
    notifyListeners();
  }

  static bool _isNewer(String? text) {
    if (text == null) return false;
    try {
      final j = jsonDecode(text) as Map<String, Object?>;
      return (j['format'] as int? ?? 0) > storageFormat;
    } on Object {
      return false;
    }
  }

  /// Damaged counts as missing; without a key, however, loading aborts, otherwise
  /// a new list would be created next to the installations that still exist.
  static Future<String?> _readIndex(String path) async {
    try {
      return await AppStorage.instance.read(path);
    } on StorageCorruptException catch (e) {
      debugPrint('Installationen: $e');
      return null;
    }
  }

  /// Index and backup are gone, but the installations' folders are there: rebuild
  /// from them, otherwise they would be unreachable. The installation's name is
  /// only in the index; the project or customer record comes closest.
  static Future<List<Installation>> _recover(SharedPreferences prefs) async {
    final ids = {
      for (final path in await allStoredPaths())
        if (RegExp(r'^installations/([^/]+)/').firstMatch(path) case final m?) m[1]!,
    };
    return [for (final id in ids.toList()..sort()) await _recovered(id, prefs)];
  }

  static Future<Installation> _recovered(String id, SharedPreferences prefs) async {
    final storage = ScopedStorage(AppStorage.instance, 'installations/$id/');
    final name = await _projectName(storage) ?? await _customerName(storage) ?? s.installationRecovered;
    final host = prefs.getString(scopedKey(id, 'gateway_host'));
    return Installation(
      id: id,
      name: name,
      created: DateTime.now(),
      gateway: host == null || host.isEmpty
          ? null
          : GatewayRef(host: host, port: prefs.getInt(scopedKey(id, 'gateway_port')) ?? 3671),
    );
  }

  static Future<String?> _customerName(AppStorage storage) async {
    try {
      final text = await storage.read('customer.json');
      if (text == null) return null;
      final name = CustomerRecord.fromJson((jsonDecode(text) as Map).cast()).customer.trim();
      return name.isEmpty ? null : name;
    } on Object {
      return null;
    }
  }

  /// Loads with a deadline so a slow device does not block startup. If the list
  /// only arrives afterwards, the stores of the then active installation (project,
  /// keyring, history …) are reloaded as soon as the first load of the stores
  /// ([storesLoaded]) is done – otherwise the app would remain "without a
  /// project" until restart. [load] and [reload] are for tests.
  Future<void> loadWithin(
    Duration timeout, {
    required Future<void> storesLoaded,
    Future<void> Function()? load,
    Future<void> Function()? reload,
  }) async {
    final loading = (load ?? this.load)();
    try {
      await loading.timeout(timeout);
      return;
    } on TimeoutException {
      debugPrint('Start: Installationen nach ${timeout.inSeconds} s noch nicht geladen – Projekt folgt');
    } on Object catch (e, st) {
      debugPrint('Start: Installationen nicht geladen: $e\n$st');
      return;
    }
    unawaited(() async {
      try {
        await loading;
        // Only once the first load is done, otherwise it would overtake the reload.
        await storesLoaded.catchError((Object _) {});
        await (reload ?? reloadStores)();
        notifyListeners();
        debugPrint('Start: Installationen nachgeladen');
      } on Object catch (e, st) {
        debugPrint('Start: Installationen nicht nachgeladen: $e\n$st');
      }
    }());
  }

  /// First start with installations: everything so far becomes the first one.
  Future<void> _migrate(SharedPreferences prefs) async {
    final id = newId();
    final root = AppStorage.instance;
    final target = ScopedStorage(root, 'installations/$id/');
    for (final f in files) {
      final text = await root.read(f);
      if (text == null) continue;
      await target.write(f, text);
      await root.delete(f);
    }
    for (final f in await root.list(_historyDir)) {
      final path = '$_historyDir/${f.name}';
      final text = await root.read(path);
      if (text != null) await target.write(path, text);
      await root.delete(path);
    }
    await KeyringStore.moveToInstallation(id);
    for (final k in prefs.getKeys().toList()) {
      if (!scopedPrefs.contains(k) && !_scopedPrefPrefixes.any(k.startsWith)) continue;
      final v = prefs.get(k);
      final nk = scopedKey(id, k);
      switch (v) {
        case String():
          await prefs.setString(nk, v);
        case int():
          await prefs.setInt(nk, v);
        case bool():
          await prefs.setBool(nk, v);
        case double():
          await prefs.setDouble(nk, v);
        case List():
          await prefs.setStringList(nk, v.cast<String>());
      }
      await prefs.remove(k);
    }
    final host = prefs.getString(scopedKey(id, 'gateway_host'));
    final port = prefs.getInt(scopedKey(id, 'gateway_port')) ?? 3671;
    _list = [
      Installation(
        id: id,
        name: await _projectName(target) ?? defaultName,
        created: DateTime.now(),
        gateway: host == null || host.isEmpty ? null : GatewayRef(host: host, port: port),
      ),
    ];
    await prefs.setString(_activeKey, id);
    await _save();
  }

  static Future<String?> _projectName(AppStorage storage) async {
    try {
      final text = await storage.read('catalog.json');
      if (text == null) return null;
      final name = (jsonDecode(text) as Map<String, Object?>)['project'] as String?;
      return name == null || name.trim().isEmpty ? null : name.trim();
    } on Object {
      return null;
    }
  }

  static String newId() {
    final r = Random.secure();
    return List.generate(12, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  void _sort() => _list.sort((a, b) => (b.lastUsed ?? b.created).compareTo(a.lastUsed ?? a.created));

  /// Read entries one by one: a broken one (or one from a newer version) does not
  /// take the others down with it.
  static List<Installation> _parse(String text) {
    final Object? list;
    try {
      list = (jsonDecode(text) as Map<String, Object?>)['list'];
    } on Object catch (e) {
      debugPrint('Installationen nicht lesbar: $e');
      return [];
    }
    return [for (final j in list is List ? list : const []) ?_entry(j)];
  }

  static Installation? _entry(Object? j) {
    try {
      return Installation.fromJson((j! as Map).cast<String, Object?>());
    } on Object catch (e) {
      debugPrint('Installation übersprungen: $e');
      return null;
    }
  }

  static const _backupPath = '$_path.bak';

  Future<void> _save() async {
    if (tooNew) return;
    final root = AppStorage.instance;
    // Keep the last readable state as a backup.
    final previous = await _readIndex(_path);
    if (previous != null && _parse(previous).isNotEmpty) await root.write(_backupPath, previous);
    await root.write(
      _path,
      jsonEncode({
        'version': 1,
        'format': storageFormat,
        'list': [for (final i in _list) i.toJson()],
      }),
    );
  }

  Installation? byId(String? id) => _list.where((i) => i.id == id).firstOrNull;

  /// Installation with this gateway (serial number).
  Installation? bySerial(String serial) =>
      serial.isEmpty ? null : _list.where((i) => i.gateway?.serial == serial).firstOrNull;

  /// Installation whose gateway last ran at this address.
  Installation? byHost(String host, int port) =>
      _list.where((i) => i.gateway?.host == host && i.gateway?.port == port).firstOrNull;

  /// Which installation a recording belongs to: the stored ID, otherwise (older
  /// recordings) via the gateway address in the display text
  /// ("Gira X1 · 192.168.1.22") or the project name.
  Installation? forRecording({String? installation, String? gateway, String? project}) {
    if (installation != null) return byId(installation);
    final host = gateway?.split(' · ').last.trim();
    return _list.where((i) => host != null && i.gateway?.host == host).firstOrNull ??
        _list.where((i) => project != null && i.name == project).firstOrNull;
  }

  /// Creates an empty installation (does not become active).
  Future<Installation> create(String name, {GatewayRef? gateway, String? id}) async {
    final i = Installation(id: id ?? newId(), name: name.trim(), created: DateTime.now(), gateway: gateway);
    _list.add(i);
    _sort();
    await _save();
    notifyListeners();
    return i;
  }

  /// Renames – via the KNX box also there, if it manages the installation.
  Future<void> rename(String id, String name) async {
    await _update(id, (i) => i.copyWith(name: name.trim()));
    if (Addon.box == null || !boxList.containsKey(id)) return;
    try {
      await Addon.renameInstallation(id, name.trim());
      boxList = {...boxList, id: name.trim()};
    } on AddonException catch (e) {
      debugPrint('Box: $e');
    }
  }

  /// Takes over name and gateway (handover package into an existing installation).
  Future<void> adopt(String id, {required String name, GatewayRef? gateway}) =>
      _update(id, (i) => i.copyWith(name: name.trim().isEmpty ? i.name : name.trim(), gateway: gateway));

  /// Whether the paired box manages this installation (box mode).
  bool onBox(String id) => Addon.box != null && boxList.containsKey(id);

  Future<void> _update(String id, Installation Function(Installation) change) async {
    final index = _list.indexWhere((i) => i.id == id);
    if (index < 0) return;
    _list[index] = change(_list[index]);
    await _save();
    notifyListeners();
  }

  /// Remembers the connected gateway (address and, once known, what it reveals
  /// about itself) in the active installation.
  Future<void> rememberGateway(String host, int port, {GatewayInfo? info}) {
    // If the device already belongs to another installation, do not assign it
    // twice – the UI offers to switch.
    final elsewhere = info != null && ownerElsewhere(info) != null;
    return _rememberGateway(host, port, elsewhere ? null : info);
  }

  /// Installation the connected device belongs to by serial number, if it is not
  /// the active one.
  Installation? ownerElsewhere(GatewayInfo info) {
    final owner = bySerial(info.serial);
    return owner == null || owner.id == active.id ? null : owner;
  }

  Future<void> _rememberGateway(String host, int port, GatewayInfo? info) => _update(active.id, (i) {
    final old = i.gateway;
    // Same device (serial number) or same address: supplement, otherwise replace.
    final same = old != null && (old.host == host && old.port == port || info != null && old.serial == info.serial);
    return i.copyWith(
      lastUsed: DateTime.now(),
      gateway: GatewayRef(
        host: host,
        port: port,
        serial: info?.serial ?? (same ? old.serial : null),
        mac: info?.mac ?? (same ? old.mac : null),
        name: info == null || info.name.trim().isEmpty ? (same ? old.name : null) : info.name.trim(),
      ),
    );
  });

  /// Deletes a (non-active) installation with its files, settings and its
  /// keyring. Recordings remain.
  Future<void> delete(String id) async {
    if (id == active.id || byId(id) == null) return;
    // Via the box: delete there with its history (the box refuses its active one).
    if (onBox(id) && id != boxActive) {
      await Addon.deleteInstallation(id);
      boxList = {...boxList}..remove(id);
    }
    final storage = ScopedStorage(AppStorage.instance, 'installations/$id/');
    for (final f in files) {
      await storage.delete(f);
    }
    if (Betrieb.enabled) {
      // GaPlanStore, SiteNotes and SiteSurveyStore of the company edition.
      for (final f in const ['ga_plan.json', 'site_notes.json', 'site_survey.json']) {
        await storage.delete(f);
      }
    }
    for (final f in await storage.list(_historyDir)) {
      await storage.delete('$_historyDir/${f.name}');
    }
    for (final dir in _paperDirs) {
      for (final f in await storage.list(dir)) {
        await storage.delete('$dir/${f.name}');
      }
    }
    await KeyringStore.deleteForInstallation(id);
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().where((k) => k.startsWith('inst:$id:')).toList()) {
      await prefs.remove(k);
    }
    _list.removeWhere((i) => i.id == id);
    await _save();
    notifyListeners();
  }

  // --- KNX box ---------------------------------------------------------------------

  /// Box mode: installation the box is currently recording into.
  String? boxActive;

  /// Installations on the box (id → name).
  Map<String, String> boxList = const {};

  /// Reads the box's installations. [adopt]: take over those that do not exist
  /// here yet (same id, with ETS project) – empty ones only if the box is currently
  /// recording into them.
  Future<void> syncBox({bool adopt = true}) async {
    if (Addon.box == null) {
      boxActive = null;
      boxList = const {};
      notifyListeners();
      return;
    }
    try {
      final j = await Addon.installations();
      boxActive = j['active'] as String?;
      boxList = {
        for (final e in (j['list'] as List? ?? const []).cast<Map<Object?, Object?>>())
          e['id']! as String: e['name'] as String? ?? '',
      };
      if (adopt) {
        for (final MapEntry(key: id, value: name) in boxList.entries) {
          if (byId(id) != null) continue;
          final project = await Addon.getInstallationFile(id, 'catalog.json');
          if (project == null && id != boxActive) continue;
          final target = ScopedStorage(AppStorage.instance, 'installations/$id/');
          if (project != null) await target.write('catalog.json', utf8.decode(project));
          final overrides = await Addon.getInstallationFile(id, 'dpt_overrides.json');
          if (overrides != null) await target.write('dpt_overrides.json', utf8.decode(overrides));
          await create(name.isEmpty ? defaultName : name, id: id);
        }
      }
    } on Object catch (e) {
      // Older box without installations, or unreachable.
      debugPrint('Installationen der Box: $e');
      boxActive = null;
      boxList = const {};
    }
    notifyListeners();
  }

  /// The box moves: from now on it records into [id], and the app switches along.
  /// Creates it on the box with the same id, then passes along the project, custom
  /// types, keyring and (if known) the bus connection.
  Future<void> useOnBox(String id) async {
    await switchTo(id);
    if (Addon.box == null) return;
    final i = active;
    try {
      if (!boxList.containsKey(id)) await Addon.createInstallation(id, i.name);
      if (boxActive != id) await Addon.activateInstallation(id);
      await CatalogStore.instance.shareWithBox();
      await KeyringStore.instance.shareWithBox();
      if (i.gateway case final g?) {
        await Addon.configure(await ConnectionOptions.instance.toAddonAsked(host: g.host, port: g.port));
      }
      await syncBox(adopt: false);
    } on Object catch (e) {
      // Box dead: the installation has been switched locally and stays usable.
      debugPrint('Installationen: Box nicht erreichbar: $e');
    }
  }

  /// The box is back: hand over project and keyring if they changed here while it
  /// was gone. Only if it is currently recording into this installation, otherwise
  /// the storage points to another one. `true` if the box has a different state
  /// that we do not replace without asking.
  Future<bool> shareChangesWithBox() async {
    if (Addon.box == null || (boxActive != null && boxActive != active.id)) return false;
    try {
      final project = await CatalogStore.instance.syncWithBox();
      final keyring = await KeyringStore.instance.syncWithBox();
      return project || keyring;
    } on Object catch (e) {
      debugPrint('Box: nicht abgeglichen: $e');
      return false;
    }
  }

  /// Switches the active installation and loads everything that belongs to it.
  /// Only call while disconnected: connection type and credentials change too.
  Future<void> switchTo(String id) async {
    if (!switchable || id == active.id || byId(id) == null) return;
    await HistoryStore.instance.flush(); // Buffered data still belongs to the previous one
    _activeId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeKey, id);
    await _update(id, (i) => i.copyWith(lastUsed: DateTime.now()));
    _sort();
    await reloadStores();
    notifyListeners();
  }

  /// Reloads all stores attached to the active installation.
  static Future<void> reloadStores() => Future.wait([
    CatalogStore.instance.reload(),
    KeyringStore.instance.reload(),
    HealthCheck.instance.reload(),
    Commissioning.instance.reload(),
    ConnectionOptions.instance.load(),
    PinnedSections.instance.reload(),
    CollapsedSections.instance.reload(),
    HistoryStore.instance.load(),
    AnnotationStore.instance.load(),
    ExportHistory.instance.load(),
    CustomerStore.instance.load(),
    HandoverStore.instance.load(),
    SitePhotoStore.instance.load(),
    HomePlanStore.instance.load(),
  ]);

  @visibleForTesting
  void debugReset() {
    tooNew = false;
    _list = [];
    _activeId = null;
  }
}
