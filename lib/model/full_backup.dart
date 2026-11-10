import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../knx/secure/keyring_store.dart';
import '../knx/secure/package_crypto.dart';
import '../platform/safe_zip.dart';
import '../platform/storage.dart';

/// Wrong password, damaged or foreign file.
class BackupException implements Exception {
  const BackupException(this.message, {this.bytes = 0});
  final String message;

  /// For `tooLarge`: size of the data; for `partial`: files already written
  /// (the app has to restart, see [FullBackup.restore]).
  final int bytes;
  @override
  String toString() => message;
}

/// Backs up everything the app has on this device into a file with its own
/// password: installations, projects, keyrings, customer records, comments,
/// recordings, history, settings. For every tier: the data belongs to the customer.
///
/// The format is described in `docs/backup-format.md` so it stays readable even
/// without the app. Not included: sign-in, app lock and everything from the
/// company; that comes back with sign-in or a new approval. History on a box
/// stays on the box.
class FullBackup {
  FullBackup({AppStorage? storage, Future<List<String>> Function()? paths, BackupKeyrings? keyrings})
    : _storage = storage ?? AppStorage.instance,
      _paths = paths ?? allStoredPaths,
      _keyrings = keyrings ?? const _StoreKeyrings();

  final AppStorage _storage;
  final Future<List<String>> Function() _paths;
  final BackupKeyrings _keyrings;

  static const format = 'knx-monitor-backup';
  static const version = 1;
  static const fileName = 'knx-monitor-sicherung.knxbackup';
  static const minPassword = 12;
  @visibleForTesting
  static int iterations = 600000;
  static final _aad = utf8.encode('$format/$version');

  /// Limits for the rounds from the file: a foreign file should neither cripple
  /// the device nor dictate a derivation that is too weak.
  static const maxIterations = 2000000;
  @visibleForTesting
  static int minIterations = 1000;

  /// Maximum unpacked size of a backup (see also [maxBytes]).
  @visibleForTesting
  static int maxRestoreBytes = 512 * 1024 * 1024;

  /// Settings around purchase and unlocking, also with a prefix (`flutter.`,
  /// `inst:<id>:`); RevenueCat identifiers as well.
  static final _purchase = RegExp(r'(^|[.:_])(plan_|rc_|revenuecat|purchase|entitlement)', caseSensitive: false);

  /// Stays on the device: sign-in, lock, device ID, purchase state, keyring and
  /// project consent for a box. A file must not set any of these: otherwise it would grant Pro
  /// permanently or release the keyring to a foreign box.
  @visibleForTesting
  static bool keepsOut(String key) =>
      key.startsWith('app_lock_') ||
      key.startsWith('flutter.app_lock_') ||
      key.contains('auth-token') ||
      key.contains('account_') ||
      key.contains('device_id') ||
      // Which box an installation was connected with (`InstallationStore.acceptBoxClaim`).
      key.endsWith(':box_bound') ||
      key.startsWith('cloud_sync_') ||
      key.startsWith('flutter.cloud_sync_') ||
      key.contains('box_keyring_') ||
      key.contains('box_project_') ||
      _purchase.hasMatch(key) ||
      key.startsWith('backup_') ||
      key.startsWith('flutter.backup_');

  /// Whether a path from a foreign file may go into storage. Only relative, without
  /// backward steps, without the plugins' settings file (Windows, Linux).
  @visibleForTesting
  static bool safePath(String path) {
    if (path.isEmpty || path.contains(r'\') || path.contains('\u0000')) return false;
    if (path.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(path)) return false;
    final parts = path.split('/');
    if (parts.any((p) => p.isEmpty || p == '.' || p == '..')) return false;
    return parts.last != 'shared_preferences.json' && parts.first != 'nicht-lesbar';
  }

  /// Company data does not belong in an individual employee's file: it would
  /// outlive their departure. The device ID must also be created anew, otherwise
  /// a new device would never get a key. The same goes for the sync state.
  static bool _isTeam(String path) =>
      path == 'team' || path.startsWith('team/') || path.startsWith('team_') || path.startsWith('cloud_sync/');

  /// Up to this size the backup safely fits in memory: the file is built in one
  /// piece, and at peak several times the data is held there at once. Beyond
  /// that, a clear error is better than a crash or a silently incomplete
  /// backup.
  static int maxBytes = 256 * 1024 * 1024;

  /// Size of the files to back up on disk.
  Future<int> estimateBytes() async {
    final byDir = <String, Set<String>>{};
    for (final path in await _paths()) {
      if (_isTeam(path)) continue;
      final cut = path.lastIndexOf('/');
      (byDir[cut < 0 ? '' : path.substring(0, cut)] ??= {}).add(path.substring(cut + 1));
    }
    var total = 0;
    for (final MapEntry(key: dir, value: names) in byDir.entries) {
      for (final f in await _storage.list(dir)) {
        if (names.contains(f.name)) total += f.size;
      }
    }
    return total;
  }

  Future<Uint8List> create(String password) async {
    final estimate = await estimateBytes();
    if (estimate > maxBytes) throw BackupException('tooLarge', bytes: estimate);
    final files = <String, String>{};
    for (final path in await _paths()) {
      if (_isTeam(path)) continue;
      final text = await _storage.read(path);
      if (text != null) files['files/$path'] = text;
    }
    final prefs = await SharedPreferences.getInstance();
    final prefsJson = jsonEncode({
      for (final k in prefs.getKeys())
        if (!keepsOut(k)) k: prefs.get(k),
    });
    // Packing, derivation, sealing and base64 all in the background.
    return compute(_pack, (
      files: files,
      prefs: prefsJson,
      keyrings: jsonEncode(await _keyrings.read()),
      password: password,
      salt: randomBytes(16),
      nonce: randomBytes(12),
      rounds: iterations,
    ));
  }

  /// Returns the number of files. Restart afterwards: the stores hold the old state
  /// in memory. Existing files with the same path are replaced (the previous
  /// version remains as `.prev`), others remain.
  Future<int> restore(Uint8List file, String password) async {
    final _Unpacked unpacked;
    try {
      unpacked = await compute(_unpack, (
        file: file,
        password: password,
        minRounds: minIterations,
        maxBytes: maxRestoreBytes,
      ));
    } on BackupException {
      rethrow;
    } on Object catch (e) {
      debugPrint('Sicherung: $e');
      throw const BackupException('open');
    }
    // Check all paths first: a foreign file writes nothing at all, or only what is allowed.
    for (final path in unpacked.files.keys) {
      if (!safePath(path)) throw const BackupException('open');
    }
    // Settings and keyrings are parsed before anything is written: a broken
    // backup must not leave half the files restored and the rest old.
    final Map<String, Object?> prefsMap;
    final Map<String, String>? rings;
    try {
      prefsMap = unpacked.prefs == null ? const {} : jsonDecode(unpacked.prefs!) as Map<String, Object?>;
      for (final value in prefsMap.values) {
        if (value is List && value.any((e) => e is! String)) throw const FormatException('prefs list');
      }
      rings = unpacked.keyrings == null ? null : (jsonDecode(unpacked.keyrings!) as Map).cast<String, String>();
      // cast is lazy: touch every value now.
      rings?.values.toList();
    } on Object catch (e) {
      debugPrint('Sicherung: $e');
      throw const BackupException('open');
    }
    var count = 0;
    try {
      for (final MapEntry(key: path, value: text) in unpacked.files.entries) {
        // Company data stays out, as when creating.
        if (_isTeam(path)) continue;
        await _storage.write(path, text);
        count++;
      }
      await _restorePrefs(prefsMap);
      if (rings != null) await _keyrings.write(rings);
    } on Object catch (e) {
      // Some files are already new: the app must restart instead of saving its
      // old in-memory state over them.
      debugPrint('Sicherung teilweise zurückgespielt ($count Dateien): $e');
      throw BackupException('partial', bytes: count);
    }
    return count;
  }

  Future<void> _restorePrefs(Map<String, Object?> values) async {
    if (values.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    for (final MapEntry(:key, :value) in values.entries) {
      if (keepsOut(key)) continue;
      switch (value) {
        case final bool v:
          await prefs.setBool(key, v);
        case final int v:
          await prefs.setInt(key, v);
        case final double v:
          await prefs.setDouble(key, v);
        case final String v:
          await prefs.setString(key, v);
        case final List<Object?> v:
          await prefs.setStringList(key, v.cast<String>());
      }
    }
  }
}

/// Reminds about backing up without ever getting in the way: only for users who
/// have something to lose (customer records or several installations), and only
/// after [interval] without a backup. Dismissing counts as a new deadline. For
/// users who never backed up, the time counts from when the app first notices,
/// so the first customer record does not trigger a reminder right away.
class BackupReminder {
  BackupReminder._();

  static const interval = Duration(days: 30);
  static const _lastKey = 'backup_last_at';
  static const _sinceKey = 'backup_reminder_since';
  static const _dismissedKey = 'backup_reminder_dismissed_at';

  static bool isDue({
    required bool hasData,
    required DateTime now,
    DateTime? last,
    DateTime? since,
    DateTime? dismissed,
  }) {
    if (!hasData) return false;
    final from = [?last, ?since, ?dismissed];
    if (from.isEmpty) return false;
    final latest = from.reduce((a, b) => a.isAfter(b) ? a : b);
    return now.difference(latest) >= interval;
  }

  static DateTime? _read(SharedPreferences prefs, String key) => DateTime.tryParse(prefs.getString(key) ?? '');

  static Future<DateTime?> lastBackup() async => _read(await SharedPreferences.getInstance(), _lastKey);

  /// The backup is in a file. Not part of the backup itself ([FullBackup._keepsOut]):
  /// a restored file is not a new backup on this device.
  static Future<void> markDone({DateTime? now}) async =>
      (await SharedPreferences.getInstance()).setString(_lastKey, (now ?? DateTime.now()).toUtc().toIso8601String());

  static Future<void> dismiss({DateTime? now}) async => (await SharedPreferences.getInstance()).setString(
    _dismissedKey,
    (now ?? DateTime.now()).toUtc().toIso8601String(),
  );

  /// Whether the reminder is due. Remembers on the first call since when there has
  /// been something to back up.
  static Future<bool> check({required bool hasCustomerRecords, required int installations, DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final hasData = hasCustomerRecords || installations > 1;
    final at = now ?? DateTime.now();
    var since = _read(prefs, _sinceKey);
    if (hasData && since == null) {
      since = at;
      await prefs.setString(_sinceKey, at.toUtc().toIso8601String());
    }
    return isDue(
      hasData: hasData,
      now: at,
      last: _read(prefs, _lastKey),
      since: since,
      dismissed: _read(prefs, _dismissedKey),
    );
  }
}

/// Keyrings live in the keychain, not in files.
abstract interface class BackupKeyrings {
  Future<Map<String, String>> read();
  Future<void> write(Map<String, String> rings);
}

class _StoreKeyrings implements BackupKeyrings {
  const _StoreKeyrings();
  @override
  Future<Map<String, String>> read() => KeyringStore.readAllStored();
  @override
  Future<void> write(Map<String, String> rings) => KeyringStore.writeAllStored(rings);
}

Uint8List _pack(
  ({
    Map<String, String> files,
    String prefs,
    String keyrings,
    String password,
    Uint8List salt,
    Uint8List nonce,
    int rounds,
  })
  a,
) {
  final archive = Archive();
  void add(String name, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  a.files.forEach(add);
  add('prefs.json', a.prefs);
  add('keyrings.json', a.keyrings);
  add(
    'manifest.json',
    jsonEncode({'format': FullBackup.format, 'version': FullBackup.version, 'files': a.files.length}),
  );
  final plain = Uint8List.fromList(ZipEncoder().encode(archive));
  final key = pbkdf2(utf8.encode(a.password), a.salt, a.rounds, 32);
  final sealed = aesGcm(encrypt: true, key: key, nonce: a.nonce, aad: Uint8List.fromList(FullBackup._aad), data: plain);
  return utf8.encode(
    jsonEncode({
      'format': FullBackup.format,
      'version': FullBackup.version,
      'kdf': {'name': 'PBKDF2-HMAC-SHA256', 'iterations': a.rounds, 'salt': base64Encode(a.salt)},
      'cipher': {'name': 'AES-256-GCM', 'nonce': base64Encode(a.nonce), 'aad': utf8.decode(FullBackup._aad)},
      'data': base64Encode(sealed),
    }),
  );
}

typedef _Unpacked = ({Map<String, String> files, String? prefs, String? keyrings});

_Unpacked _unpack(({Uint8List file, String password, int minRounds, int maxBytes}) a) {
  final j = jsonDecode(utf8.decode(a.file)) as Map<String, Object?>;
  if (j['format'] != FullBackup.format) throw const BackupException('format');
  if ((j['version']! as int) > FullBackup.version) throw const BackupException('newer');
  final kdf = (j['kdf']! as Map).cast<String, Object?>();
  final cipher = (j['cipher']! as Map).cast<String, Object?>();
  final rounds = kdf['iterations']! as int;
  if (rounds < a.minRounds || rounds > FullBackup.maxIterations) throw const BackupException('open');
  final key = pbkdf2(utf8.encode(a.password), base64Decode(kdf['salt']! as String), rounds, 32);
  final plain = aesGcm(
    encrypt: false,
    key: key,
    nonce: base64Decode(cipher['nonce']! as String),
    aad: Uint8List.fromList(FullBackup._aad),
    data: base64Decode(j['data']! as String),
  );
  final archive = decodeZipLimited(
    plain,
    limits: ZipLimits(maxTotalBytes: a.maxBytes, maxFileBytes: a.maxBytes, maxEntries: 200000),
  );
  String text(ArchiveFile f) => utf8.decode(f.content);
  final prefs = archive.findFile('prefs.json');
  final rings = archive.findFile('keyrings.json');
  return (
    files: {
      for (final f in archive.files)
        if (f.isFile && f.name.startsWith('files/')) f.name.substring('files/'.length): text(f),
    },
    prefs: prefs == null ? null : text(prefs),
    keyrings: rings == null ? null : text(rings),
  );
}
