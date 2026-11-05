import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'export/handover_package.dart';
import 'knx/dpt_codec.dart';
import 'knx/group_catalog.dart';
import 'knx/knxproj_parser.dart';
import 'knx/telegram.dart';
import 'l10n/locale_controller.dart';
import 'knx/demo_tunnel.dart';
import 'model/box_keyring_consent.dart';
import 'model/box_share.dart';
import 'model/installation.dart';
import 'model/teach_in.dart';
import 'platform/addon.dart';
import 'platform/pbkdf2.dart';
import 'platform/storage.dart';

/// Asks for the project password. [wrong]: the previous attempt was wrong. `null` = cancelled.
typedef PasswordPrompt = Future<String?> Function({required bool wrong});

/// A step of a running import, for the progress display.
enum ImportPhase {
  /// Reading the file (in the browser, before the picker returns).
  reading,

  /// Open the archive; if unprotected, read it right away.
  opening,

  /// Decrypt and read a protected project.
  decrypting,

  /// Save the catalog.
  saving,
}

/// A handover package or a fault report was picked in the project import.
class PackageFileChosen implements Exception {
  const PackageFileChosen(this.bytes);
  final Uint8List bytes;
}

/// Holds the imported group addresses/devices and stores them locally.
class CatalogStore extends ChangeNotifier {
  CatalogStore._();

  static final instance = CatalogStore._();

  static const _legacyCsvKey = 'catalog_csv';
  static const _nameKey = 'catalog_name';

  GroupCatalog _project = GroupCatalog.empty;
  GroupCatalog _learned = GroupCatalog.empty;
  GroupCatalog _catalog = GroupCatalog.empty;

  /// Project and learned data combined – what all views show.
  GroupCatalog get catalog => _catalog;

  /// Only the imported project (ETS, CSV, diagnostics package).
  GroupCatalog get project => _project;

  /// Addresses and devices learned without an ETS project.
  GroupCatalog get learned => _learned;

  /// Sets the project and with it the address style (3-level, 2-level, free).
  set catalog(GroupCatalog c) {
    _project = c;
    _merge();
  }

  void _merge() {
    _catalog = withNames(mergeLearned(_project, _learned), names);
    groupStyle = _catalog.style;
  }

  ({GroupCatalog project, GroupCatalog learned, Map<int, String> names})? _beforeDemo;
  int _demoDepth = 0;

  /// Demo house: its project only in memory, without its own learned data and name corrections. Data learned in the demo
  /// also stays in memory only. When nested (tour started from the demo), only the outer [endDemo]
  /// counts.
  void beginDemo(GroupCatalog demo) {
    if (_demoDepth++ == 0) {
      _beforeDemo = (project: _project, learned: _learned, names: names);
      _learned = GroupCatalog.empty;
      names = {};
    }
    catalog = demo;
    notifyListeners();
  }

  /// Restore the own project and learned data after the demo.
  void endDemo() {
    if (_demoDepth == 0 || --_demoDepth > 0) return;
    final before = _beforeDemo!;
    _beforeDemo = null;
    _learned = before.learned;
    names = before.names;
    catalog = before.project;
    notifyListeners();
  }

  String? fileName;

  /// Whether an import is running.
  final busy = ValueNotifier(false);

  /// Current step of the import; `null` outside an import and while asking for the password.
  final phase = ValueNotifier<ImportPhase?>(null);

  static const _path = 'catalog.json';
  static const _overridesPath = 'dpt_overrides.json';
  static const _learnedPath = 'learned.json';
  static const _namesPath = 'name_overrides.json';

  /// Files of the active installation.
  AppStorage get _storage => InstallationStore.instance.storage;
  String get _name => InstallationStore.instance.key(_nameKey);
  String get _legacyCsv => InstallationStore.instance.key(_legacyCsvKey);

  /// User-chosen datapoint types per group address – for addresses without a type (or with a wrong
  /// one) in the project. They apply to display, writing and charts and survive a project change.
  Map<int, Dpt> overrides = {};

  /// Datapoint type of a group address: user-chosen, otherwise from the project.
  Dpt? dptOf(int address) => overrides[address] ?? catalog[address]?.dpt;

  Future<void> setDpt(int address, Dpt? dpt) async {
    if (dpt == null) {
      overrides.remove(address);
    } else {
      overrides[address] = dpt;
    }
    final text = jsonEncode({
      for (final MapEntry(:key, :value) in overrides.entries) '$key': [value.main, value.sub],
    });
    await _storage.write(_overridesPath, text);
    _shareWithBox(_overridesPath, text);
    notifyListeners();
  }

  Future<void> _loadOverrides() async {
    overrides =
        await readStored(
          _storage,
          _overridesPath,
          (text) => {
            for (final MapEntry(:key, :value) in (jsonDecode(text) as Map<String, Object?>).entries)
              int.parse(key): Dpt((value! as List)[0] as int, (value as List)[1] as int?),
          },
        ) ??
        {};
  }

  /// Corrected names per group address of the project, e.g. typos – shown everywhere instead of the
  /// project name and returned to the ETS with the group address import. Survive a project change;
  /// once the project has the same name, the correction no longer shows up as a task.
  Map<int, String> names = {};

  /// Corrects the name of a project address; `null` or the project name reverts to the project.
  Future<void> setName(int address, String? name) => setNames({address: name});

  /// Corrects several names at once (`null` = revert to the project), saved once.
  Future<void> setNames(Map<int, String?> changes) async {
    for (final MapEntry(key: address, value: name) in changes.entries) {
      final trimmed = name?.trim();
      if (trimmed == null || trimmed.isEmpty || trimmed == _project[address]?.name) {
        names.remove(address);
      } else {
        names[address] = trimmed;
      }
    }
    _merge();
    notifyListeners();
    // Demo: persist nothing.
    if (_beforeDemo != null || DemoTunnel.active) return;
    await _storage.write(_namesPath, jsonEncode({for (final MapEntry(:key, :value) in names.entries) '$key': value}));
  }

  Future<void> _loadNames() async {
    names =
        await readStored(
          _storage,
          _namesPath,
          (text) => {
            for (final MapEntry(:key, :value) in (jsonDecode(text) as Map<String, Object?>).entries)
              int.parse(key): value! as String,
          },
        ) ??
        {};
  }

  /// Load the project of the (just switched) active installation.
  Future<void> reload() async {
    _learned = GroupCatalog.empty;
    catalog = GroupCatalog.empty;
    fileName = null;
    overrides = {};
    names = {};
    await load();
  }

  Future<void> load() async {
    await _loadOverrides();
    await _loadNames();
    await _loadLearned();
    final prefs = await SharedPreferences.getInstance();
    fileName = prefs.getString(_name);
    String? json;
    try {
      json = await _storage.read(_path);
      if (json != null) {
        catalog = GroupCatalog.fromJson(jsonDecode(json) as Map<String, Object?>);
      } else if (prefs.getString(_legacyCsv) case final csv?) {
        // Migration from version 1 (CSV in the settings).
        catalog = GroupCatalog.parseCsv(csv);
        await _save(catalog, fileName ?? 'Gruppenadressen.csv');
        await prefs.remove(_legacyCsv);
      }
    } on Object catch (e) {
      debugPrint('Katalog nicht lesbar: $e');
      if (json != null) await keepCorrupt(_storage, _path, json);
      catalog = GroupCatalog.empty;
    }
    notifyListeners();
  }

  Future<void> _loadLearned() async {
    _learned =
        await readStored(
          _storage,
          _learnedPath,
          (text) => GroupCatalog.fromJson(jsonDecode(text) as Map<String, Object?>),
        ) ??
        GroupCatalog.empty;
    _merge();
  }

  /// Adopts learned addresses and devices (replaces equal addresses).
  Future<void> learn(Iterable<GroupInfo> groups, {Iterable<DeviceInfo> devices = const []}) async {
    _learned = GroupCatalog(
      {..._learned.groups, for (final g in groups) g.address: g},
      devices: {..._learned.devices, for (final d in devices) d.address: d},
    );
    await _saveLearned();
  }

  /// Forgets a learned group address.
  Future<void> forget(int address) async {
    _learned = GroupCatalog({..._learned.groups}..remove(address), devices: _learned.devices);
    await _saveLearned();
  }

  /// Forgets everything learned (the project stays).
  Future<void> clearLearned() async {
    _learned = GroupCatalog.empty;
    await _saveLearned();
  }

  Future<void> _saveLearned() async {
    _merge();
    notifyListeners();
    // Demo: persist nothing.
    if (_beforeDemo != null || DemoTunnel.active) return;
    final text = jsonEncode(_learned.toJson());
    // Lives in the installation's storage: natively on the device, in the add-on (browser) in the
    // data folder of the user's own Home Assistant – never in a cloud. Server features (alarms,
    // timers) only read the project.
    await _storage.write(_learnedPath, text);
  }

  /// Opens the file picker and imports a .knxproj or ETS CSV. Returns `false` when cancelled;
  /// throws [FormatException] for an invalid file.
  Future<bool> pickAndImport({required PasswordPrompt askPassword}) async {
    // FileType.any: iOS does not know .knxproj as a file type and would grey it out.
    final file = await FilePicker.pickFile(
      type: FileType.any,
      // In the browser the picker reads the whole file before it returns.
      onFileLoading: (status) {
        if (status == FilePickerStatus.picking) phase.value = ImportPhase.reading;
      },
    );
    if (file == null) {
      phase.value = null;
      return false;
    }
    busy.value = true;
    try {
      return await _import(file.name, await file.readAsBytes(), askPassword);
    } finally {
      busy.value = false;
      phase.value = null;
    }
  }

  /// In the browser the import runs on the UI thread and blocks it: let a frame be drawn first so
  /// the new step is visible.
  static Future<void> _paint() async {
    if (kIsWeb) await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  Future<bool> _import(String name, Uint8List bytes, PasswordPrompt askPassword) async {
    GroupCatalog? parsed;
    if (name.toLowerCase().endsWith('.knxproj')) {
      String? password;
      String? ets6;
      while (parsed == null) {
        phase.value = password == null ? ImportPhase.opening : ImportPhase.decrypting;
        await _paint();
        try {
          final pw = password;
          final key = ets6;
          final locale = LocaleController.instance.locale;
          GroupCatalog parse() {
            // Error messages in the background isolate in the chosen language.
            LocaleController.instance.debugSetLocale(locale);
            return parseKnxproj(
              bytes,
              password: pw,
              ets6Password: key,
              language: locale.languageCode == 'en' ? 'en-US' : 'de-DE',
            );
          }

          // There are no isolates in the browser.
          parsed = kIsWeb ? parse() : await Isolate.run(parse);
        } on KnxprojPasswordException catch (e) {
          phase.value = null;
          password = await askPassword(wrong: e.wrong);
          if (password == null) return false;
          // ETS6 key derivation in the browser via Web Crypto instead of Dart.
          if (kIsWeb && password.isNotEmpty) {
            phase.value = ImportPhase.decrypting;
            final derived = await nativePbkdf2Sha256(ets6KeyInput(password), utf8.encode(ets6Salt), ets6Iterations, 32);
            ets6 = derived == null ? null : base64.encode(derived);
          }
        }
      }
    } else if (RegExp(r'\.(csv|txt)$', caseSensitive: false).hasMatch(name)) {
      parsed = GroupCatalog.parseCsv(GroupCatalog.decodeBytes(bytes));
    } else if (packageKindOf(bytes) != null) {
      // A package from the electrician instead of a project: does not belong here, but the customer
      // should not have to search.
      throw PackageFileChosen(bytes);
    } else {
      throw FormatException(s.catalogPickFile);
    }

    phase.value = ImportPhase.saving;
    await _paint();
    catalog = parsed;
    await _save(parsed, name);
    notifyListeners();
    return true;
  }

  /// Adopts a finished project (e.g. from a diagnostics package) including user-chosen datapoint
  /// types into the active installation.
  Future<void> adopt(GroupCatalog c, {required String name, Map<int, Dpt> overrides = const {}}) async {
    catalog = c;
    await _save(c, name);
    this.overrides = Map.of(overrides);
    final text = jsonEncode({
      for (final MapEntry(:key, :value) in this.overrides.entries) '$key': [value.main, value.sub],
    });
    await _storage.write(_overridesPath, text);
    _shareWithBox(_overridesPath, text);
    notifyListeners();
  }

  Future<void> _save(GroupCatalog c, String name) async {
    fileName = name;
    final text = jsonEncode(c.toJson());
    await _storage.write(_path, text);
    _shareWithBox(_path, text);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_name, name);
  }

  /// Via the KNX box: put the project there too so it knows names and types (alarms, timers,
  /// browser on the box Wi-Fi). Native only; in the browser [AppStorage] lives on the server
  /// anyway.
  void _shareWithBox(String path, String text) {
    final installations = InstallationStore.instance;
    final id = installations.active.id;
    // If it is currently recording elsewhere, it ended up in that installation.
    if (Addon.box == null || (installations.boxActive != null && installations.boxActive != id)) return;
    final box = Addon.box!;
    // If it fails, [syncWithBox] catches up as soon as the box is back.
    unawaited(() async {
      try {
        // Paired via a link from outside and not confirmed yet: nothing goes there.
        if (!await BoxProjectConsent.allowed(box)) return;
        await Addon.putFile(path, utf8.encode(text));
        await BoxShare.remember(id, path, text);
      } on Object catch (e) {
        debugPrint('Box: $e');
      }
    }());
  }

  /// Puts the project and user-chosen types on the box (after setup, when it has none yet).
  Future<void> shareWithBox() async {
    final box = Addon.box;
    if (box == null || !await BoxProjectConsent.allowed(box)) return;
    for (final path in [_path, _overridesPath]) {
      final text = await _storage.read(path);
      if (text != null && Addon.box != null) {
        await Addon.putFile(path, utf8.encode(text));
        await BoxShare.remember(InstallationStore.instance.active.id, path, text);
      }
    }
  }

  /// Syncs the project and user-chosen types ([BoxShare]); `true` if the box has a different
  /// version of either and it was therefore kept.
  Future<bool> syncWithBox() async {
    final box = Addon.box;
    if (box == null || !await BoxProjectConsent.allowed(box)) return false;
    var differs = false;
    for (final path in [_path, _overridesPath]) {
      final outcome = await BoxShare.sync(
        InstallationStore.instance.active.id,
        path,
        local: await _storage.read(path),
        readBox: () => Addon.getFile(path),
        writeBox: (bytes) => Addon.putFile(path, bytes),
      );
      differs = differs || outcome == BoxShareOutcome.boxDiffers;
    }
    return differs;
  }

  Future<void> clear() async {
    catalog = GroupCatalog.empty;
    fileName = null;
    await _storage.delete(_path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_name);
    await prefs.remove(_legacyCsv);
    notifyListeners();
  }

  GroupInfo? info(int address) => catalog[address];

  DeviceInfo? device(int address) => catalog.devices[address];

  /// Display name: name from the catalog or the group address.
  String title(Telegram t) => catalog[t.destination]?.name ?? t.destinationText;

  /// Source: „1.1.18 Heizungsaktor“ (heating actuator) or just the address.
  String sender(Telegram t) {
    final d = device(t.source);
    return d == null ? t.sourceText : '${t.sourceText} ${d.name}';
  }

  /// Value, decoded with the DPT from the catalog, otherwise heuristically.
  String value(Telegram t) {
    final dpt = dptOf(t.destination);
    return (dpt == null ? null : decodeDpt(dpt, t)) ?? t.valueText;
  }
}
