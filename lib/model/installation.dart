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
import 'box_keyring_consent.dart';
import 'betrieb_mode.dart';
import 'export_history.dart';
import 'commissioning.dart';
import 'connection_options.dart';
import 'customer.dart';
import 'dali.dart';
import 'dali_log.dart';
import 'handover.dart';
import 'health.dart';
import 'history_store.dart';
import 'floor_view.dart';
import 'home_plan/home_plan_store.dart';
import 'keys.dart';
import 'pinned_sections.dart';
import 'project_states.dart';
import 'site_photos.dart';
import 'tap_points.dart';

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
  Installation({
    required this.id,
    required this.name,
    required this.created,
    String? key,
    this.gateway,
    this.lastUsed,
    this.taps = const [],
  }) : key = key ?? derivedInstallationKey(id);

  /// Name of the folder and part of the settings keys on this device. Local: the same
  /// installation can have another id on another device (handover, box).
  final String id;

  /// Installation key (docs/keys.md): the same UUID wherever this installation is known, at the
  /// electrician's, at the customer's and on a box. It stays when the installation is handed
  /// over or moves to another device, and it never grants access.
  final String key;

  /// The key is only derived from an id that is not unique beyond this device (`default`): the
  /// real one comes from the box that manages the installation, or is generated before the
  /// installation goes anywhere else.
  bool get keyIsPlaceholder => !isRandomInstallationId(id) && key == derivedInstallationKey(id);

  final String name;
  final GatewayRef? gateway;

  static final _validId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  /// Whether [id] may name an installation. It becomes a folder (`installations/<id>/`) and part of
  /// settings keys, so every id from outside – box, restored backup, index file – is checked; one
  /// like "../../x" would otherwise reach files outside the data folder.
  static bool isValidId(String id) => _validId.hasMatch(id);
  final DateTime created;
  final DateTime? lastUsed;

  /// Further tap points besides the normal connection (issue #8). Empty for most installations.
  final List<TapPoint> taps;

  Installation copyWith({String? name, String? key, GatewayRef? gateway, DateTime? lastUsed, List<TapPoint>? taps}) =>
      Installation(
        id: id,
        name: name ?? this.name,
        created: created,
        key: key ?? this.key,
        gateway: gateway ?? this.gateway,
        lastUsed: lastUsed ?? this.lastUsed,
        taps: taps ?? this.taps,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'key': key,
    'name': name,
    'created': created.millisecondsSinceEpoch,
    'gateway': ?gateway?.toJson(),
    'lastUsed': ?lastUsed?.millisecondsSinceEpoch,
    if (taps.isNotEmpty) 'taps': [for (final t in taps) t.toJson()],
  };

  /// Throws [FormatException] for an invalid id ([isValidId]); the index then skips the entry.
  factory Installation.fromJson(Map<String, Object?> j) => Installation(
    id: _checkedId(j['id']! as String),
    // Missing (older version) or not a key: derived from the id.
    key: switch (j['key']) {
      final String k when isKey(k) => k,
      _ => null,
    },
    name: j['name'] as String? ?? '',
    created: DateTime.fromMillisecondsSinceEpoch(j['created'] as int? ?? 0),
    gateway: j['gateway'] == null ? null : GatewayRef.fromJson((j['gateway']! as Map).cast<String, Object?>()),
    lastUsed: j['lastUsed'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['lastUsed']! as int),
    taps: j['taps'] is List
        ? [for (final t in j['taps']! as List) ?TapPoint.fromJson(t)].take(TapPoint.max - 1).toList()
        : const [],
  );

  static String _checkedId(String id) => isValidId(id) ? id : throw FormatException('invalid installation id', id);
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
    projectStatesPath,
    'dpt_overrides.json',
    'name_overrides.json',
    'learned.json',
    'health.json',
    'commissioning.json',
    'customer.json',
    'visits.json',
    'handover_origin.json',
    'site_photos.json',
    DaliStore.path,
    DaliStore.statePath,
    HomePlanStore.path,
    HomePlanStore.exchangePath,
    HomePlanStore.livePath,
    HomePlanStore.previousPath,
    FloorViewStore.path,
    KeyringStore.sequencePath,
  ];

  /// Folders with the installation's documents; deleted along with it (customer data).
  static const _paperDirs = [
    'protocols',
    'service_reports',
    'site_photos',
    DaliTestLog.dir,
    HomePlanStore.imageDir,
    HomePlanStore.previousImageDir,
    FloorViewStore.imageDir,
  ];
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
      // The server manages the one installation; its key comes from there.
      unawaited(_loadServerKey());
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
    // An index that names an installation twice (seen on 12 Nov 2026 in a debug container) broke
    // every list keyed by the id: the first entry stays.
    final seen = <String>{};
    final unique = [
      for (final i in _list)
        if (seen.add(i.id)) i,
    ];
    if (unique.length != _list.length) {
      debugPrint('Installationen: ${_list.length - unique.length} doppelte Einträge entfernt');
      _list = unique;
      await _save();
    }
    _activeId = prefs.getString(_activeKey);
    if (!_list.any((i) => i.id == _activeId)) _activeId = _list.first.id;
    _sort();
    notifyListeners();
  }

  /// Add-on (browser): key of the server's installation and of the add-on itself. Without them
  /// (older server, not reachable yet) the placeholder stays.
  Future<void> _loadServerKey() async {
    try {
      final j = await Addon.installations().timeout(const Duration(seconds: 10));
      if (j['box'] case final String box when isKey(box)) boxKey = box;
      final current = (j['list'] as List? ?? const []).whereType<Map<Object?, Object?>>().where(
        (e) => e['id'] == j['active'],
      );
      if (current.firstOrNull?['key'] case final String key when isKey(key)) {
        _list = [active.copyWith(key: key)];
      }
      notifyListeners();
    } on Object catch (e) {
      debugPrint('Installation: Schlüssel vom Server nicht gelesen: $e');
    }
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
        if (RegExp(r'^installations/([^/]+)/').firstMatch(path) case final m? when Installation.isValidId(m[1]!)) m[1]!,
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

  /// Installation with this key (docs/keys.md): the same one, whatever its id is here.
  Installation? byKey(String? key) => key == null ? null : _list.where((i) => i.key == key).firstOrNull;

  /// Sets the key of installation [id]: from the box that manages it, from the handover package
  /// it came with, or a fresh one in place of a placeholder.
  ///
  /// A key is set once. Only one that was never stored (still the one derived from the id) can
  /// be set, and never to the key of another installation here; anything else is ignored.
  Future<void> setKey(String id, String key) async {
    final current = byId(id);
    if (current == null || !isKey(key) || current.key == key) return;
    if (current.key != derivedInstallationKey(id) || byKey(key) != null) {
      debugPrint('Installation: Schlüssel steht fest, nicht ersetzt');
      return;
    }
    if (kIsWeb) {
      // Add-on: the server keeps the installation; here it only lives in memory.
      _list = [for (final i in _list) i.id == id ? i.copyWith(key: key) : i];
      notifyListeners();
      return;
    }
    await _update(id, (i) => i.copyWith(key: key));
  }

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
  /// Throws [ArgumentError] for an invalid [id] ([Installation.isValidId]).
  ///
  /// [key]: the installation exists elsewhere already (box, handover package) and keeps its key.
  Future<Installation> create(String name, {GatewayRef? gateway, String? id, String? key}) async {
    if (id != null && !Installation.isValidId(id)) throw ArgumentError.value(id, 'id', 'invalid installation id');
    if (id != null && _list.any((i) => i.id == id)) throw ArgumentError.value(id, 'id', 'installation id exists');
    // Two installations here never share a key.
    if (isKey(key) && byKey(key) != null) throw ArgumentError.value(key, 'key', 'installation key exists');
    final i = Installation(
      id: id ?? newId(),
      name: name.trim(),
      created: DateTime.now(),
      gateway: gateway,
      key: isKey(key) ? key : null,
    );
    _list.add(i);
    _sort();
    await _save();
    notifyListeners();
    return i;
  }

  /// Renames – via the Busclear Box also there, if it manages the installation.
  Future<void> rename(String id, String name) async {
    await _update(id, (i) => i.copyWith(name: name.trim()));
    if (Addon.box == null || !boxList.containsKey(id)) return;
    try {
      await Addon.renameInstallation(boxIdOf(id), name.trim());
      boxList = {...boxList, id: name.trim()};
    } on AddonException catch (e) {
      debugPrint('Box: $e');
    }
  }

  /// Takes over name and gateway (handover package into an existing installation).
  Future<void> adopt(String id, {required String name, GatewayRef? gateway}) =>
      _update(id, (i) => i.copyWith(name: name.trim().isEmpty ? i.name : name.trim(), gateway: gateway));

  /// Puts the index entry of an installation back as it was (a handover package that failed
  /// half way).
  Future<void> restore(Installation previous) => _update(previous.id, (_) => previous);

  /// Whether the paired box manages this installation (box mode).
  bool onBox(String id) => Addon.box != null && boxList.containsKey(id);

  Future<void> _update(String id, Installation Function(Installation) change) async {
    final index = _list.indexWhere((i) => i.id == id);
    if (index < 0) return;
    _list[index] = change(_list[index]);
    await _save();
    notifyListeners();
  }

  /// Sets the further tap points of installation [id] (issue #8).
  Future<void> setTaps(String id, List<TapPoint> taps) =>
      _update(id, (i) => i.copyWith(taps: List.unmodifiable(taps.take(TapPoint.max - 1))));

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
      await Addon.deleteInstallation(boxIdOf(id));
      boxList = {...boxList}..remove(id);
    }
    final storage = ScopedStorage(AppStorage.instance, 'installations/$id/');
    for (final f in files) {
      await storage.delete(f);
      // Copies a store moved aside as unreadable are the installation's data too.
      await deleteCorruptCopies(storage, f);
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

  // --- Busclear Box ---------------------------------------------------------------------

  /// Box mode: installation the box is currently recording into (id on this device);
  /// [boxActiveUnconnected] if that one is not connected with any installation here.
  String? boxActive;

  /// [boxActive] while the box records into an installation that is only claimed ([boxClaims]).
  /// It is no installation's id, so nothing here counts as "the one on the box" and nothing is
  /// shared with it.
  static const boxActiveUnconnected = '';

  /// Installations on the box (id on this device → name).
  Map<String, String> boxList = const {};

  /// Key of the paired box or, in the browser, of the add-on (docs/keys.md); `null` for an older
  /// one. It tells boxes apart, also after their address or certificate changed. It is the box's
  /// own claim: what may go to a box is still decided per address and certificate
  /// (`BoxProjectConsent`, `BoxKeyringConsent`).
  String? boxKey;

  /// Id on the box of the installations that have another one here: every box calls its first
  /// installation `default`, so the second box's one cannot keep that id on this device.
  Map<String, String> _boxIds = const {};

  /// Id of installation [id] on the paired box (mostly the same).
  String boxIdOf(String id) => _boxIds[id] ?? id;

  /// Installations here whose key the paired box names for one of its own (id here → id on the
  /// box) without this app ever having connected the two. Nothing is exchanged for them: an
  /// installation key travels in handover packages and fault reports, so a box that merely
  /// knows it must not get the project by it. [acceptBoxClaim] connects them.
  Map<String, String> boxClaims = const {};

  static const _boundKey = 'box_bound';

  /// Whether this app connected installation [id] with the paired box before.
  Future<bool> _boundToBox(String id) async {
    final box = boxKey;
    if (box == null) return false;
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(scopedKey(id, _boundKey)) ?? const []).contains(box);
  }

  Future<void> _bindToBox(String id) async {
    final box = boxKey;
    if (box == null || await _boundToBox(id)) return;
    final prefs = await SharedPreferences.getInstance();
    final key = scopedKey(id, _boundKey);
    await prefs.setStringList(key, [...?prefs.getStringList(key), box]);
  }

  /// The user confirms that installation [id] here is the one the paired box names
  /// ([boxClaims]), e.g. a home owner's box that holds an installation the electrician got back
  /// by other means. From then on the two are matched like any other.
  Future<void> acceptBoxClaim(String id) async {
    if (!boxClaims.containsKey(id)) return;
    await _bindToBox(id);
    await syncBox(adopt: false);
  }

  /// Reads the box's installations. [adopt]: take over those that do not exist
  /// here yet (with ETS project) – empty ones only if the box is currently
  /// recording into them.
  ///
  /// Which installation here is which one there is decided by the installation key; the id only
  /// counts for a box that does not know keys yet.
  Future<void> syncBox({bool adopt = true}) async {
    if (Addon.box == null) {
      boxActive = null;
      boxList = const {};
      boxKey = null;
      _boxIds = const {};
      boxClaims = const {};
      notifyListeners();
      return;
    }
    try {
      final j = await Addon.installations();
      boxKey = switch (j['box']) {
        final String k when isKey(k) => k,
        _ => null,
      };
      final names = <String, String>{};
      final ids = <String, String>{};
      final claims = <String, String>{};
      String? active;
      for (final e in (j['list'] as List? ?? const []).whereType<Map<Object?, Object?>>()) {
        // The box is a device on the network: an id that cannot be a folder name is ignored.
        final boxId = e['id'];
        if (boxId is! String || !Installation.isValidId(boxId)) continue;
        final name = e['name'] as String? ?? '';
        final key = switch (e['key']) {
          final String k when isKey(k) => k,
          _ => null,
        };
        final (local, taken, claimed) = await _localFor(boxId, key);
        if (claimed != null) {
          claims[claimed] = boxId;
          if (boxId == j['active']) active = boxActiveUnconnected;
          continue;
        }
        var id = local?.id;
        if (id == null) {
          // Unknown here. With the id taken by another installation it gets a new one.
          final target = taken ? newId() : boxId;
          if (adopt && await _adoptFromBox(boxId, target, name, key, isActive: boxId == j['active'])) {
            id = target;
          } else if (!taken) {
            id = boxId;
          } else {
            // Not taken over, and its id means another installation here: if the box records
            // into it, no installation here is "the one on the box", so nothing is shared.
            if (boxId == j['active']) active = boxActiveUnconnected;
            continue;
          }
        } else if (key == null && boxKey != null && !local!.keyIsPlaceholder) {
          // Created by an older app: the box learns the key (admin only, otherwise next time).
          try {
            await Addon.setInstallationKey(boxId, local.key);
          } on Object catch (error) {
            debugPrint('Box: Schlüssel der Installation nicht gesetzt: $error');
          }
        }
        names[id] = name;
        if (id != boxId) ids[id] = boxId;
        if (boxId == j['active']) active = id;
      }
      boxActive = active;
      boxList = names;
      _boxIds = ids;
      boxClaims = claims;
    } on Object catch (e) {
      // Older box without installations, or unreachable.
      debugPrint('Installationen der Box: $e');
      boxActive = null;
      boxList = const {};
      _boxIds = const {};
      boxClaims = const {};
    }
    notifyListeners();
  }

  /// The installation here that is the box's [boxId] with [key]; `taken` if there is none but
  /// the id belongs to another installation here; `claimed` (its id) if the box names the key of
  /// an installation here that this app never connected with it ([boxClaims]).
  Future<(Installation?, bool taken, String? claimed)> _localFor(String boxId, String? key) async {
    final same = byId(boxId);
    if (key == null) return (same, false, null);
    if (byKey(key) case final known?) {
      // The key alone connects nothing: same id as before keys existed, or connected by this app.
      if (known.id == boxId || await _boundToBox(known.id)) return (known, false, null);
      return (null, false, known.id);
    }
    if (same == null) return (null, false, null);
    if (isRandomInstallationId(boxId)) {
      // Same random id, another key. A box this app put the installation on never says that
      // (it has the key from here), so the id alone connects nothing either.
      if (await _boundToBox(same.id)) return (same, false, null);
      return (null, false, same.id);
    }
    if (same.keyIsPlaceholder) {
      // Taken over from this box before keys existed: it gets the box's key now.
      await setKey(boxId, key);
      return (byId(boxId), false, null);
    }
    return (null, true, null);
  }

  /// Takes over the box's installation [boxId] as [id] here; `false` if there is nothing to take.
  Future<bool> _adoptFromBox(String boxId, String id, String name, String? key, {required bool isActive}) async {
    final project = await Addon.getInstallationFile(boxId, 'catalog.json');
    if (project == null && !isActive) return false;
    final target = ScopedStorage(AppStorage.instance, 'installations/$id/');
    if (project != null) await target.write('catalog.json', utf8.decode(project));
    for (final file in const ['dpt_overrides.json', 'name_overrides.json', 'learned.json']) {
      final bytes = await Addon.getInstallationFile(boxId, file);
      if (bytes != null) await target.write(file, utf8.decode(bytes));
    }
    await create(name.isEmpty ? defaultName : name, id: id, key: key);
    // It came from this box: under another id here it is still the box's one next time.
    await _bindToBox(id);
    return true;
  }

  /// The box moves: from now on it records into [id], and the app switches along.
  /// Creates it on the box with the same id, then passes along the project, custom
  /// types, keyring and (if known) the bus connection.
  ///
  /// A box paired via a link from outside gets none of this until the user confirmed
  /// ([BoxProjectConsent]); the app then only switches locally.
  Future<void> useOnBox(String id) async {
    await switchTo(id);
    final box = Addon.box;
    if (box == null || !await BoxProjectConsent.allowed(box)) return;
    try {
      if (!boxList.containsKey(id)) {
        // Before it leaves this device, a placeholder becomes a real key.
        if (active.keyIsPlaceholder) await setKey(id, newKey());
        // An id like `default` is taken on every box; a box that knows keys gets a fresh one
        // and is matched by the key afterwards.
        final fresh = boxKey != null && !isRandomInstallationId(id);
        await Addon.createInstallation(fresh ? newId() : id, active.name, key: active.key);
        // Put there by this app: connected, also under another id.
        await _bindToBox(id);
        if (fresh) await syncBox(adopt: false);
      }
      final i = active;
      if (boxActive != id) await Addon.activateInstallation(boxIdOf(id));
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
    DaliStore.instance.reload().then((_) => DaliTestLog.instance.reload()),
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
    FloorViewStore.instance.load(),
  ]);

  @visibleForTesting
  void debugReset() {
    tooNew = false;
    _list = [];
    _activeId = null;
  }
}
