import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../model/installation.dart';
import '../../platform/addon.dart';
import '../../model/box_keyring_consent.dart';
import '../../model/box_share.dart';
import '../../platform/storage.dart';

import 'package:knx/secure.dart';

import 'keyring.dart';

/// Loaded ETS keyring (KNX Secure): keys for Data Secure and credentials of the secure tunnels.
///
/// Only what is needed is stored, decrypted. In the apps it lives in the system keychain (Keychain,
/// Android Keystore, Windows DPAPI, Linux libsecret), not as a file. In the add-on it remains the
/// file `secure_keys.json` in the data folder: the server reads it to record secured telegrams.
class KeyringStore extends ChangeNotifier {
  KeyringStore._();

  static final instance = KeyringStore._();
  static const _path = 'secure_keys.json';
  static const _vaultKey = 'knx_keyring';

  /// One keychain entry per installation.
  static String _vaultKeyFor(String id) => '$_vaultKey:$id';
  String get _key => _vaultKeyFor(InstallationStore.instance.active.id);

  /// "this_device": do not sync via iCloud Keychain or migrate to other devices in backups. macOS
  /// without the Data Protection keychain, which would otherwise need a keychain access group
  /// entitlement.
  static const _vault = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      usesDataProtectionKeychain: false,
    ),
  );

  String? project;
  List<KeyringTunnel> tunnels = const [];
  Map<int, String> deviceAuthentication = const {};
  DataSecure? dataSecure;

  bool get loaded => dataSecure != null || tunnels.isNotEmpty;
  int get groupKeyCount => dataSecure?.groupKeys.length ?? 0;

  /// Data Secure telegrams without a matching key (since start).
  final withoutKey = ValueNotifier<int>(0);

  /// Data Secure telegrams with an invalid MAC/sequence number (since start).
  final rejected = ValueNotifier<int>(0);

  /// Highest Data Secure sequence number seen per sender, per installation (encrypted storage like
  /// the other files). Without it, a restart would accept older recorded telegrams as valid again.
  static const sequencePath = 'secure_sequence.json';

  /// Counters change with every secured telegram: written at most this often.
  @visibleForTesting
  static Duration sequenceDelay = const Duration(seconds: 2);

  Timer? _sequenceTimer;
  Future<void> Function()? _pendingSequence;

  /// Load the keyring of the (just switched) active installation.
  Future<void> reload() async {
    // Counters still waiting belong to the previous installation.
    await flushSequences();
    _reset();
    withoutKey.value = 0;
    rejected.value = 0;
    await load();
    notifyListeners();
  }

  void _reset() {
    project = null;
    tunnels = const [];
    deviceAuthentication = const {};
    dataSecure = null;
  }

  /// Migration: the previous (single) keyring belongs to installation [id].
  static Future<void> moveToInstallation(String id) async {
    if (kIsWeb) return;
    try {
      // Also adopt a plain-text file from older versions.
      final text = await _vault.read(key: _vaultKey) ?? await AppStorage.instance.read(_path);
      if (text == null) return;
      await _vault.write(key: _vaultKeyFor(id), value: text);
      await _vault.delete(key: _vaultKey);
      await AppStorage.instance.delete(_path);
    } on Object catch (e) {
      debugPrint('Keyring nicht umgezogen: $e');
    }
  }

  static Future<void> deleteForInstallation(String id) async {
    if (kIsWeb) return;
    try {
      await _vault.delete(key: _vaultKeyFor(id));
    } on Object catch (e) {
      debugPrint('Keyring nicht gelöscht: $e');
    }
  }

  Future<void> load() async {
    try {
      final text = await _readStored();
      if (text == null) return;
      _apply(jsonDecode(text) as Map<String, Object?>, seen: await _storedSequences());
      notifyListeners();
    } on Object {
      // Unreadable: treat as not loaded.
    }
  }

  /// [seen]: counters stored from earlier runs; the higher one of keyring and [seen] counts.
  void _apply(Map<String, Object?> j, {Map<int, int> seen = const {}}) {
    final keyring = Keyring.fromJson(j);
    project = keyring.project;
    dataSecure = keyring.groupKeys.isEmpty
        ? null
        : (DataSecure(
            groupKeys: keyring.groupKeys,
            sequenceNumbers: {
              for (final MapEntry(:key, :value) in keyring.sequenceNumbers.entries) key: max(value, seen[key] ?? value),
            },
          )..onSequence = _sequenceChanged);
    tunnels = [
      for (final t in (j['tunnels'] as List? ?? const []).cast<Map<String, Object?>>())
        KeyringTunnel(
          address: t['address']! as int,
          host: t['host'] as int?,
          userId: t['userId'] as int?,
          password: t['password'] as String?,
        ),
    ];
    deviceAuthentication = {
      for (final MapEntry(:key, :value) in ((j['deviceAuthentication'] as Map?) ?? const {}).entries)
        int.parse('$key'): '$value',
    };
  }

  /// Imports a `.knxkeys` file. Throws [KeyringException] for a wrong password or a broken file.
  Future<void> import(String text, String password) async {
    final keyring = kIsWeb ? Keyring.parse(text, password) : await compute(_parse, (text, password));
    final json = {
      ...keyring.toJson(),
      'tunnels': [
        for (final t in keyring.tunnels)
          {'address': t.address, 'host': t.host, 'userId': t.userId, 'password': t.password},
      ],
      'deviceAuthentication': {
        for (final MapEntry(:key, :value) in keyring.deviceAuthentication.entries) '$key': value,
      },
    };
    await _writeStored(jsonEncode(json));
    await shareWithBox();
    _apply(json, seen: await _seenSoFar());
    withoutKey.value = 0;
    rejected.value = 0;
    notifyListeners();
  }

  /// All keyrings of this device for the full backup.
  static Future<Map<String, String>> readAllStored() async {
    if (kIsWeb) return const {};
    // One by one per installation: readAll fails on a Mac without the Data Protection keychain
    // (-50).
    final out = <String, String>{};
    for (final i in InstallationStore.instance.list) {
      final key = _vaultKeyFor(i.id);
      final value = await _vault.read(key: key);
      if (value != null) out[key] = value;
    }
    return out;
  }

  /// For "delete everything": keyrings of all installations of this device.
  static Future<void> deleteAllStored() async {
    if (kIsWeb) return;
    for (final i in InstallationStore.instance.list) {
      await _vault.delete(key: _vaultKeyFor(i.id));
    }
  }

  static Future<void> writeAllStored(Map<String, String> rings) async {
    if (kIsWeb) return;
    for (final e in rings.entries) {
      if (e.key.startsWith('$_vaultKey:')) await _vault.write(key: e.key, value: e.value);
    }
  }

  /// Stored state for a handover package (natively from the keychain); `null` without a keyring.
  Future<Map<String, Object?>?> exportStored() async {
    final text = await _readStored();
    return text == null ? null : (jsonDecode(text) as Map).cast<String, Object?>();
  }

  /// Adopts the state from a handover package into the active installation.
  Future<void> adoptStored(Map<String, Object?> json) async {
    _apply(json, seen: await _seenSoFar());
    await _writeStored(jsonEncode(json));
    await shareWithBox();
    withoutKey.value = 0;
    rejected.value = 0;
    notifyListeners();
  }

  static Keyring _parse((String, String) args) => Keyring.parse(args.$1, args.$2);

  Future<void> clear() async {
    if (kIsWeb) {
      await AppStorage.instance.delete(_path);
    } else {
      await _vault.delete(key: _key);
      _sequenceTimer?.cancel();
      _sequenceTimer = null;
      _pendingSequence = null;
      await InstallationStore.instance.storage.delete(sequencePath);
    }
    _reset();
    notifyListeners();
  }

  /// Via the KNX box: put the keyring there too so it records secured telegrams in readable form
  /// (the same file as in the add-on).
  Future<void> shareWithBox() async {
    if (kIsWeb || Addon.box == null) return;
    final text = await _readStored();
    final box = Addon.box!;
    if (text == null || !await BoxProjectConsent.allowed(box) || !await BoxKeyringConsent.allowed(box)) return;
    try {
      await Addon.putFile(_path, utf8.encode(text));
      await BoxShare.remember(InstallationStore.instance.active.id, _path, text);
    } on Object catch (e) {
      debugPrint('Box: $e');
    }
  }

  /// Syncs the keyring ([BoxShare]); `true` if the box has a different version and it was therefore
  /// kept.
  Future<bool> syncWithBox() async {
    if (kIsWeb || Addon.box == null) return false;
    final box = Addon.box!;
    if (!await BoxProjectConsent.allowed(box)) return false;
    final local = await _readStored();
    if (local != null && !await BoxKeyringConsent.allowed(box)) return false;
    final outcome = await BoxShare.sync(
      InstallationStore.instance.active.id,
      _path,
      local: local,
      readBox: () => Addon.getFile(_path),
      writeBox: (bytes) => Addon.putFile(_path, bytes),
    );
    return outcome == BoxShareOutcome.boxDiffers;
  }

  Future<String?> _readStored() async {
    // Web: the file in the data folder (the server reads it). Native: the keychain;
    // [moveToInstallation] migrates older entries.
    if (kIsWeb) return AppStorage.instance.read(_path);
    return _vault.read(key: _key);
  }

  Future<void> _writeStored(String text) async {
    if (kIsWeb) return AppStorage.instance.write(_path, text);
    try {
      await _vault.write(key: _key, value: text);
    } on Object catch (e) {
      // No keychain (e.g. Linux without Secret Service): keep it in memory for this session only
      // instead of falling back to plain text.
      debugPrint('Keyring nicht dauerhaft gespeichert: $e');
    }
  }

  /// Counters known now: in memory, otherwise stored.
  Future<Map<int, int>> _seenSoFar() async => dataSecure?.lastSequences ?? await _storedSequences();

  Future<Map<int, int>> _storedSequences() async {
    // In the add-on the server keeps its own counters.
    if (kIsWeb) return const {};
    final stored = await readStored(
      InstallationStore.instance.storage,
      sequencePath,
      (text) => (jsonDecode(text) as Map)['sequence'] as Map? ?? const {},
    );
    return {
      for (final MapEntry(:key, :value) in (stored ?? const {}).entries)
        if ((int.tryParse('$key'), value) case (final int sender, final int seq)) sender: seq,
    };
  }

  /// A received telegram advanced a counter: store it shortly after, together with any that follow.
  void _sequenceChanged() {
    final ds = dataSecure;
    if (kIsWeb || ds == null) return;
    // The installation of now, even if the timer only fires after a switch.
    final storage = InstallationStore.instance.storage;
    _pendingSequence = () => storage.write(
      sequencePath,
      jsonEncode({
        'version': 1,
        'sequence': {for (final MapEntry(:key, :value) in ds.lastSequences.entries) '$key': value},
      }),
    );
    _sequenceTimer ??= Timer(sequenceDelay, () => unawaited(flushSequences()));
  }

  /// Writes waiting counters right away (before switching installations, in tests).
  Future<void> flushSequences() async {
    _sequenceTimer?.cancel();
    _sequenceTimer = null;
    final write = _pendingSequence;
    _pendingSequence = null;
    if (write == null) return;
    try {
      await write();
    } on Object catch (e) {
      debugPrint('Data Secure: Zähler nicht gespeichert: $e');
      // Keep it and try again, unless newer counters are already waiting: a
      // lost write would let a recorded telegram count as new after a restart.
      _pendingSequence ??= write;
      _sequenceTimer ??= Timer(sequenceDelay, () => unawaited(flushSequences()));
    }
  }

  /// Credentials for a secure tunnel (matching the tunnel address, or the first one).
  KeyringTunnel? tunnelFor({int? address}) =>
      tunnels.where((t) => t.userId != null && (address == null || t.address == address)).firstOrNull;
}
