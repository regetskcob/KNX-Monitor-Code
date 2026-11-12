/// Backup of a whole Busclear Box, Docker container or add-on (all installations with history,
/// project, settings, watchers, inspection log, home plan and bus view files) and the way back.
/// Format and decisions: docs/backup-format.md, section "Box backup".
///
/// - The backup is a plain zip, written while it is sent ([writeBoxBackup], [ZipStream]):
///   packed history days go in as they are.
/// - KNX Secure keyring, IP Secure passwords and the credentials of notifications and data export
///   only go in encrypted, in `secrets.json`, with a password chosen when backing up
///   ([sealSecrets]). Without a password they stay out.
/// - Never in it: the box password (hash), paired devices, the TLS key, the tokens of the
///   Busclear integration and the MCP server, crash records. A stolen backup opens no box.
/// - Restoring unpacks into a staging folder first and checks everything ([unpackBoxBackup]);
///   only then, after a confirmation, the current state is set aside under `restore-previous/`
///   and the restored one takes its place ([BoxBackupService]).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

import 'atomic_file.dart';
import 'box_access.dart' show TooManyAttemptsException;
import 'files.dart';
import 'free_space.dart';
import 'http.dart';
import 'installations.dart';
import 'zip_stream.dart';

/// Format constants and limits of the box backup.
abstract final class BoxBackup {
  static const format = 'busclear-box-backup';
  static const version = 1;
  static const secretsFormat = 'busclear-box-secrets';
  static const secretsVersion = 1;

  /// Additional authenticated data of `secrets.json`: `<format>/<version>`. The server uses its own
  /// constant and does not read `cipher.aad` from the file.
  static final secretsAad = Uint8List.fromList(utf8.encode('$secretsFormat/$secretsVersion'));

  /// Like the app's full backup (`FullBackup.minPassword`).
  static const minPassword = 12;
  static const maxPassword = 1024;

  /// PBKDF2 rounds when sealing, as in the app's full backup. Lower only in tests.
  static int iterations = 600000;

  /// Rounds accepted from a file: a foreign file must neither force a weak derivation nor keep
  /// the Pi busy for minutes.
  static int minIterations = 100000;
  static const maxIterations = 2000000;

  /// Without Zip64 an archive and every entry stay below 4 GiB (zip_stream.dart).
  static int maxBytes = 0xFFFFFFFF;
  static int maxEntryBytes = 0xFFFFFFFF;

  /// Entries of a zip without Zip64.
  static const maxEntries = 0xFFFF;

  /// `manifest.json`, `installations.json`, `secrets.json`.
  static int maxJsonBytes = 4 * 1024 * 1024;
  static const maxInstallations = 1000;

  /// Free space that has to remain after unpacking (the recorder stops at 256 MiB as well).
  static int reserveBytes = 256 * 1024 * 1024;
}

/// A backup that cannot be read or restored; [message] is shown to the user (German, like the
/// server's other answers).
class BoxBackupException implements Exception {
  const BoxBackupException(this.message, {this.problem = 'invalid', this.status = HttpStatus.badRequest});
  final String message;

  /// Stable reason for the app (`invalid`, `newer`, `tooLarge`, `space`).
  final String problem;
  final int status;
  @override
  String toString() => message;
}

/// Server files of an installation that the backup carries besides the app's ([knownAppFiles]).
const _serverFiles = {
  'server.json',
  'history',
  'status',
  'reports',
  'cycle_watch.json',
  'charts',
  'availability.json',
  'diagnostics.json',
};

/// Only in the encrypted part (`secrets.json`): the keyring and the credentials of data export
/// and notifications. Compared in lower case (case-insensitive data folders, files.dart).
const _secretFiles = {'secure_keys.json', 'export.json', 'report_settings.json', 'secure_sequence.json'};

/// Company data and the sync state stay out, as in the app's full backup (`FullBackup._isTeam`):
/// they belong to the company account, not to this box.
bool _companyData(String top) => top == 'team' || top.startsWith('team_') || top == 'cloud_sync';

/// Key in `secrets.json` for the IP Secure credentials from `server.json` (`secure`).
const _busSecure = 'server.secure';

/// Fields of `secure` in `server.json` that are passwords (BusConfig.toJson).
const _busPasswords = {'userPassword', 'deviceAuthentication'};

final _segment = RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9._-]{0,254}$');
final _setAside = RegExp(r'\.(tmp|bak|prev|corrupt-\d+)$');
const _maxDepth = 8;

/// Whether a backup carries the file [relative] (`/`-separated) of an installation folder, when
/// writing as when restoring: a known file or folder of the app or the server, plain path
/// segments, nothing secret, no temporary or set-aside copies (`server.json.bak` holds the
/// IP Secure passwords).
bool backupCarries(String relative) {
  final parts = relative.split('/');
  if (parts.length > _maxDepth || parts.any((p) => !_segment.hasMatch(p))) return false;
  final top = parts.first;
  if (!knownAppFiles.contains(top) && !_serverFiles.contains(top)) return false;
  if (_companyData(top)) return false;
  for (final p in parts) {
    final lower = p.toLowerCase();
    if (_secretFiles.any((s) => lower == s || lower.startsWith('$s.'))) return false;
  }
  return !_setAside.hasMatch(parts.last.toLowerCase());
}

// --- Directory of installations ----------------------------------------------------------------

typedef _Index = ({String box, String active, List<Map<String, Object?>> list});

/// `installations.json`, read defensively: valid, unique ids only.
_Index _parseIndex(Object? j) {
  final list = <Map<String, Object?>>[];
  var active = '';
  var box = '';
  if (j is Map) {
    final ids = <String>{};
    for (final e in j['list'] is List ? j['list'] as List : const []) {
      if (e is! Map || list.length >= BoxBackup.maxInstallations) continue;
      try {
        final i = Installation.fromJson(e.cast<String, Object?>());
        if (!Installations.validId.hasMatch(i.id) || !ids.add(i.id)) continue;
        list.add(i.toJson());
      } on Object {
        // Skipped like Installations.open does.
      }
    }
    if (j['active'] case final String a) active = a;
    if (j['box'] case final String b when isKey(b)) box = b;
  }
  if (!list.any((i) => i['id'] == active)) active = list.isEmpty ? '' : list.first['id']! as String;
  return (box: box, active: active, list: list);
}

Future<_Index> _readIndex(Directory root) async {
  for (final name in ['installations.json', 'installations.json.bak']) {
    try {
      final index = _parseIndex(jsonDecode(await File('${root.path}/$name').readAsString()));
      if (index.list.isNotEmpty) return index;
    } on Object {
      // Missing or unreadable: try the backup copy, like Installations.open.
    }
  }
  return (box: '', active: '', list: const <Map<String, Object?>>[]);
}

Future<Map<String, Object?>?> _jsonObject(File file) async {
  try {
    if (!await file.exists()) return null;
    final j = jsonDecode(await file.readAsString());
    return j is Map ? j.cast<String, Object?>() : null;
  } on Object {
    return null;
  }
}

/// [server] (`server.json`) without the IP Secure passwords.
Map<String, Object?> _withoutPasswords(Map<String, Object?> server) {
  final secure = server['secure'];
  if (secure is! Map) return server;
  return {
    ...server,
    'secure': {
      for (final MapEntry(:key, :value) in secure.entries)
        if (!_busPasswords.contains(key)) '$key': value,
    },
  };
}

bool _hasBusPasswords(Object? secure) =>
    secure is Map && _busPasswords.any((k) => secure[k] is String && (secure[k] as String).isNotEmpty);

// --- Secrets -------------------------------------------------------------------------------------

/// What only goes into the encrypted part, per installation id: `secure_keys.json`,
/// `export.json`, `report_settings.json` (as JSON objects) and the `secure` part of `server.json`
/// with the IP Secure passwords.
Future<Map<String, Map<String, Object?>>> collectSecrets(Directory root) async {
  final out = <String, Map<String, Object?>>{};
  for (final i in (await _readIndex(root)).list) {
    final id = i['id']! as String;
    final dir = '${root.path}/installations/$id';
    final entry = <String, Object?>{
      for (final name in _secretFiles)
        if (await _jsonObject(File('$dir/$name')) case final value?) name: value,
    };
    final secure = (await _jsonObject(File('$dir/server.json')))?['secure'];
    if (_hasBusPasswords(secure)) entry[_busSecure] = secure;
    if (entry.isNotEmpty) out[id] = entry;
  }
  return out;
}

/// Kinds of secrets in [secrets], for the hint what a backup without a password leaves out:
/// `keyring`, `ipSecure`, `dataExport`, `report`.
List<String> secretKinds(Map<String, Map<String, Object?>> secrets) {
  const names = {
    'secure_keys.json': 'keyring',
    _busSecure: 'ipSecure',
    'export.json': 'dataExport',
    'report_settings.json': 'report',
  };
  return [
    for (final MapEntry(:key, :value) in names.entries)
      if (secrets.values.any((s) => s.containsKey(key))) value,
  ];
}

Uint8List _randomBytes(int n, Random random) => Uint8List.fromList(List.generate(n, (_) => random.nextInt(256)));

/// PBKDF2-HMAC-SHA256 with a 32-byte result. With package:crypto, not pointycastle: compiled it
/// is more than three times as fast, measured on the Pi 4 at 600,000 rounds 10 s instead of 35 s.
Uint8List pbkdf2Sha256(List<int> password, List<int> salt, int rounds) {
  final hmac = crypto.Hmac(crypto.sha256, password);
  var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final out = Uint8List.fromList(u);
  for (var i = 1; i < rounds; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < out.length; j++) {
      out[j] ^= u[j];
    }
  }
  return out;
}

Uint8List _gcm(bool encrypt, Uint8List key, Uint8List nonce, Uint8List data) => (GCMBlockCipher(
  AESEngine(),
)..init(encrypt, AEADParameters(KeyParameter(key), 128, nonce, BoxBackup.secretsAad))).process(data);

/// A key derivation is running: up to 2,000,000 PBKDF2 rounds keep a Pi core busy for half a minute,
/// so only one runs at a time and another request gets `429`.
var _deriving = false;

Future<Uint8List> _derive(String password, Uint8List salt, int rounds) async {
  if (_deriving) {
    throw const BoxBackupException(
      'Die Box berechnet gerade schon einen Schlüssel, bitte gleich noch einmal versuchen.',
      problem: 'busy',
      status: HttpStatus.tooManyRequests,
    );
  }
  _deriving = true;
  try {
    return await Isolate.run(() => pbkdf2Sha256(utf8.encode(password), salt, rounds));
  } finally {
    _deriving = false;
  }
}

/// Key for `secrets.json`, derived from the password once (PBKDF2-HMAC-SHA256, [BoxBackup.iterations]
/// rounds, as in the app's full backup). It is kept in memory for a prepared download instead of the
/// password, and seals the secrets at the end of the zip, when the digests of all entries are known.
class SecretsKey {
  SecretsKey._(this.rounds, this.salt, this._key, this._random);

  final int rounds;
  final Uint8List salt;
  final Uint8List _key;
  final Random _random;

  /// Derives the key in an isolate (several seconds on a Pi); one derivation at a time.
  static Future<SecretsKey> derive(String password, {Random? random}) async {
    final r = random ?? Random.secure();
    final salt = _randomBytes(16, r);
    final rounds = BoxBackup.iterations;
    return SecretsKey._(rounds, salt, await _derive(password, salt, rounds), r);
  }

  /// The content of `secrets.json` for [plain] (JSON), with a fresh nonce.
  Map<String, Object?> seal(Object? plain) {
    final nonce = _randomBytes(12, _random);
    final sealed = _gcm(true, _key, nonce, Uint8List.fromList(utf8.encode(jsonEncode(plain))));
    return {
      'format': BoxBackup.secretsFormat,
      'version': BoxBackup.secretsVersion,
      'kdf': {'name': 'PBKDF2-HMAC-SHA256', 'iterations': rounds, 'salt': base64Encode(salt)},
      'cipher': {'name': 'AES-256-GCM', 'nonce': base64Encode(nonce), 'aad': utf8.decode(BoxBackup.secretsAad)},
      'data': base64Encode(sealed),
    };
  }
}

/// Encrypts [secrets] (and the [integrity] list, see [writeBoxBackup]) with [password]: the
/// content of `secrets.json`.
Future<Map<String, Object?>> sealSecrets(
  Map<String, Map<String, Object?>> secrets,
  String password, {
  List<Object?>? integrity,
  Random? random,
}) async =>
    (await SecretsKey.derive(password, random: random)).seal({'installations': secrets, 'integrity': ?integrity});

typedef _Sealed = ({int rounds, Uint8List salt, Uint8List nonce, Uint8List data});

/// The fields of a `secrets.json`, checked; throws [BoxBackupException] if it is none.
_Sealed _sealedOf(Object? envelope) {
  const broken = BoxBackupException('Der verschlüsselte Teil der Sicherung ist beschädigt.');
  if (envelope is! Map || envelope['format'] != BoxBackup.secretsFormat) throw broken;
  if (envelope['version'] is! int || (envelope['version']! as int) > BoxBackup.secretsVersion) {
    throw const BoxBackupException('Die Sicherung stammt von einer neueren Version.', problem: 'newer');
  }
  final kdf = envelope['kdf'];
  final cipher = envelope['cipher'];
  if (kdf is! Map || cipher is! Map) throw broken;
  final rounds = kdf['iterations'];
  if (rounds is! int || rounds < BoxBackup.minIterations || rounds > BoxBackup.maxIterations) throw broken;
  try {
    final salt = base64Decode(kdf['salt']! as String);
    final nonce = base64Decode(cipher['nonce']! as String);
    final data = base64Decode(envelope['data']! as String);
    if (salt.length < 8 || nonce.length != 12 || data.length < 16) throw broken;
    return (rounds: rounds, salt: salt, nonce: nonce, data: data);
  } on BoxBackupException {
    rethrow;
  } on Object {
    throw broken;
  }
}

/// What [openSecrets] found: the secrets per installation and the list of all entries with their
/// digests that the plain part must match (`null` in a part without one, which a restore refuses).
typedef OpenedSecrets = ({Map<String, Map<String, Object?>> installations, List<Object?>? integrity});

/// Decrypts `secrets.json` ([envelope]) with [password]; `null` if the password is wrong or the
/// part was modified (the GCM tag tells both apart from nothing). Only installations in [ids]
/// and only the known kinds, each a JSON object; anything else is dropped.
Future<OpenedSecrets?> openSecrets(Object? envelope, String password, Set<String> ids) async {
  final sealed = _sealedOf(envelope);
  final key = await _derive(password, sealed.salt, sealed.rounds);
  final Uint8List plain;
  try {
    plain = _gcm(false, key, sealed.nonce, sealed.data);
  } on Object {
    return null;
  }
  final Object? j;
  try {
    j = jsonDecode(utf8.decode(plain));
  } on Object {
    throw const BoxBackupException('Der verschlüsselte Teil der Sicherung ist beschädigt.');
  }
  final out = <String, Map<String, Object?>>{};
  final installations = j is Map ? j['installations'] : null;
  for (final MapEntry(:key, :value)
      in installations is Map ? installations.entries : const <MapEntry<Object?, Object?>>[]) {
    if (key is! String || !ids.contains(key) || value is! Map) continue;
    final entry = <String, Object?>{
      for (final name in [..._secretFiles, _busSecure])
        if (value[name] case final Map<dynamic, dynamic> v) name: v.cast<String, Object?>(),
    };
    if (entry.isNotEmpty) out[key] = entry;
  }
  final integrity = j is Map && j['integrity'] is List ? j['integrity'] as List<Object?> : null;
  return (installations: out, integrity: integrity);
}

/// Whether a backup may list the entry [name] without a SHA-256, with size and CRC-32 only: the
/// history and status files of backups written before every entry got its hash. They cannot
/// redirect the secrets the way a changed `server.json` could; new backups hash them all the same.
bool _mayLackDigest(String name) => RegExp(r'^installations/[^/]+/(history|status)/').hasMatch(name);

String _hex(List<int> bytes) => [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

/// Checks the plain part of [backup] against the [integrity] list from `secrets.json`: the same
/// entries (except `secrets.json`), each with the same size and CRC-32, and the same SHA-256 where
/// the list has one. Throws if anything differs: then the plain part was changed after backing up,
/// for instance `server.json` to send the restored IP Secure passwords to another host.
void verifyIntegrity(UnpackedBoxBackup backup, List<Object?>? integrity) {
  const changed = BoxBackupException(
    'Die Sicherung wurde nach dem Sichern verändert und wird nicht wiederhergestellt.',
    problem: 'tampered',
    status: HttpStatus.unprocessableEntity,
  );
  if (integrity == null || integrity.length != backup.entries.length) throw changed;
  final seen = <String>{};
  for (final item in integrity) {
    if (item is! List || item.length != 4 || item[0] is! String) throw changed;
    final name = item[0]! as String;
    final actual = backup.entries[name];
    if (actual == null || !seen.add(name)) throw changed;
    if (item[1] != actual.size || item[2] != actual.crc) throw changed;
    if (item[3] == null && _mayLackDigest(name)) continue;
    if (item[3] is! String || item[3] != actual.sha256) throw changed;
  }
}

// --- Writing -------------------------------------------------------------------------------------

/// Files of an installation folder the backup carries, sorted, with their size.
Future<List<(String, int)>> _carriedFiles(Directory dir) async {
  final out = <(String, int)>[];
  if (!await dir.exists()) return out;
  await for (final e in dir.list(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final relative = e.path.substring(dir.path.length + 1).replaceAll(r'\', '/');
    if (!backupCarries(relative)) continue;
    try {
      out.add((relative, await e.length()));
    } on FileSystemException {
      // Gone meanwhile (a day being packed).
    }
  }
  out.sort((a, b) => a.$1.compareTo(b.$1));
  return out;
}

/// Writes the backup of [root] (the data folder, or a state set aside under `restore-previous/`)
/// to [emit]: `manifest.json`, `installations.json`, every carried file of every installation
/// and, with a [key] and [secrets] ([collectSecrets]), `secrets.json` as the last entry. That
/// part also holds the integrity list: every entry before it with size, CRC-32 and SHA-256, so the plain part cannot be changed without the password
/// ([verifyIntegrity]). [withheld] names the kinds of secrets left out ([secretKinds]), [box]
/// describes the box (name, key, container) for the manifest. Returns the number of
/// installations and files.
Future<({int installations, int files})> writeBoxBackup(
  Directory root,
  Future<void> Function(List<int> bytes) emit, {
  required String serverVersion,
  SecretsKey? key,
  Map<String, Map<String, Object?>> secrets = const {},
  List<String> withheld = const [],
  Map<String, Object?> box = const {},
  DateTime? now,
}) async {
  final index = await _readIndex(root);
  final time = now ?? DateTime.now();
  final plan = [
    for (final i in index.list)
      (entry: i, files: await _carriedFiles(Directory('${root.path}/installations/${i['id']}'))),
  ];
  final sealing = key != null && secrets.isNotEmpty;
  final zip = ZipStream(emit);
  Future<void> json(String name, Object? value) =>
      zip.add(name, time, (write) => write(jsonEncode(value)), digest: sealing);
  await json('manifest.json', {
    'format': BoxBackup.format,
    'version': BoxBackup.version,
    'created': time.toUtc().toIso8601String(),
    'server': serverVersion,
    // Without the box key: the restored box keeps its own (docs/backup-format.md).
    'box': {...box}..remove('key'),
    'active': index.active,
    'installations': [
      for (final p in plan)
        {
          'id': p.entry['id'],
          'name': p.entry['name'],
          'key': ?p.entry['key'],
          'files': p.files.length,
          'bytes': p.files.fold<int>(0, (sum, f) => sum + f.$2),
        },
    ],
    'secrets': sealing,
    if (withheld.isNotEmpty) 'withheld': withheld,
  });
  await json('installations.json', {'version': 1, 'active': index.active, 'list': index.list});
  var files = 0;
  final written = <String>{};
  for (final p in plan) {
    final dir = '${root.path}/installations/${p.entry['id']}';
    for (final (relative, _) in p.files) {
      var name = 'installations/${p.entry['id']}/$relative';
      var file = File('$dir/$relative');
      if (relative == 'server.json') {
        final server = await _jsonObject(file);
        if (server == null || !written.add(name)) continue;
        await json(name, _withoutPasswords(server));
        files++;
        continue;
      }
      if (!await file.exists()) {
        // The recorder packed the day meanwhile.
        final packed = File('${file.path}.gz');
        if (!relative.endsWith('.ndjson') || !await packed.exists()) continue;
        file = packed;
        name = '$name.gz';
      }
      if (!written.add(name)) continue;
      final DateTime modified;
      try {
        modified = await file.lastModified();
      } on FileSystemException {
        continue;
      }
      await zip.addStream(name, modified, file.openRead(), level: name.endsWith('.gz') ? 0 : 6, digest: sealing);
      files++;
    }
  }
  if (sealing) {
    await json(
      'secrets.json',
      key.seal({
        'installations': secrets,
        'integrity': [
          for (final e in zip.written) [e.name, e.size, e.crc, if (e.sha256 case final h?) _hex(h) else null],
        ],
      }),
    );
  }
  await zip.close();
  return (installations: plan.length, files: files);
}

/// Size of the files a backup of [root] carries, before packing.
Future<int> estimateBoxBackup(Directory root) async {
  var total = 0;
  for (final i in (await _readIndex(root)).list) {
    for (final (_, size) in await _carriedFiles(Directory('${root.path}/installations/${i['id']}'))) {
      total += size;
    }
  }
  return total;
}

// --- Reading -------------------------------------------------------------------------------------

class _ZipEntry {
  _ZipEntry(this.name, this.method, this.crc, this.compressed, this.size, this.offset);
  final String name;
  final int method;
  final int crc;
  final int compressed;
  final int size;
  final int offset;
}

class _Collect implements Sink<List<int>> {
  _Collect(this._into);
  final List<List<int>> _into;
  @override
  void add(List<int> data) => _into.add(data);
  @override
  void close() {}
}

const _damaged = BoxBackupException('Die Datei ist beschädigt oder keine Busclear-Sicherung.');

/// Largest central directory read (65,535 entries with names of up to about 400 characters).
const maxDirectoryBytes = 24 * 1024 * 1024;

/// Central directory of the zip [raf] ([length] bytes): entries, and where the directory starts
/// (no entry's data may reach into it).
Future<(List<_ZipEntry>, int)> _centralDirectory(RandomAccessFile raf, int length) async {
  if (length < 22) throw _damaged;
  final tail = min(length, 22 + 0xFFFF);
  await raf.setPosition(length - tail);
  final buf = await raf.read(tail);
  final end = ByteData.sublistView(buf);
  var at = -1;
  for (var i = buf.length - 22; i >= 0; i--) {
    if (end.getUint32(i, Endian.little) == 0x06054b50 && i + 22 + end.getUint16(i + 20, Endian.little) == buf.length) {
      at = i;
      break;
    }
  }
  if (at < 0) throw _damaged;
  int u16(int o) => end.getUint16(at + o, Endian.little);
  int u32(int o) => end.getUint32(at + o, Endian.little);
  final count = u16(10);
  final size = u32(12);
  final offset = u32(16);
  if (u16(4) != 0 || u16(6) != 0 || u16(8) != count) throw _damaged;
  if (count == 0xFFFF || size == 0xFFFFFFFF || offset == 0xFFFFFFFF) {
    throw const BoxBackupException('Zip64 wird nicht unterstützt (Sicherung über 4 GB).', problem: 'tooLarge');
  }
  final directoryEnd = length - tail + at;
  // A directory larger than [maxDirectoryBytes] or than its entries can need is not read: a
  // foreign file could otherwise make the Pi read a gigabyte into memory.
  if (offset + size > directoryEnd || size > min(maxDirectoryBytes, 64 + count * 512)) throw _damaged;
  await raf.setPosition(offset);
  final cd = await raf.read(size);
  if (cd.length != size) throw _damaged;
  final d = ByteData.sublistView(cd);
  final entries = <_ZipEntry>[];
  var p = 0;
  for (var n = 0; n < count; n++) {
    if (p + 46 > cd.length || d.getUint32(p, Endian.little) != 0x02014b50) throw _damaged;
    final flags = d.getUint16(p + 8, Endian.little);
    final method = d.getUint16(p + 10, Endian.little);
    final nameLength = d.getUint16(p + 28, Endian.little);
    final extra = d.getUint16(p + 30, Endian.little);
    final comment = d.getUint16(p + 32, Endian.little);
    if (p + 46 + nameLength + extra + comment > cd.length) throw _damaged;
    // Encrypted (bit 0) or patched data (bit 5): not from Busclear.
    if (flags & 0x21 != 0 || (method != 0 && method != 8)) throw _damaged;
    final raw = cd.sublist(p + 46, p + 46 + nameLength);
    if (raw.any((b) => b < 0x20 || b > 0x7e)) throw _damaged;
    entries.add(
      _ZipEntry(
        ascii.decode(raw),
        method,
        d.getUint32(p + 16, Endian.little),
        d.getUint32(p + 20, Endian.little),
        d.getUint32(p + 24, Endian.little),
        d.getUint32(p + 42, Endian.little),
      ),
    );
    p += 46 + nameLength + extra + comment;
  }
  return (entries, offset);
}

/// Unpacks [e] from [raf] into [write], checking size and CRC while unpacking: a zip that
/// declares less than it holds (a zip bomb) is stopped at the declared size.
Future<void> _extract(
  RandomAccessFile raf,
  _ZipEntry e,
  int directory,
  Future<void> Function(List<int> chunk) write,
) async {
  await raf.setPosition(e.offset);
  final header = await raf.read(30);
  if (header.length != 30) throw _damaged;
  final h = ByteData.sublistView(header);
  if (h.getUint32(0, Endian.little) != 0x04034b50 || h.getUint16(8, Endian.little) != e.method) throw _damaged;
  final nameLength = h.getUint16(26, Endian.little);
  final extra = h.getUint16(28, Endian.little);
  if (ascii.decode(await raf.read(nameLength), allowInvalid: true) != e.name) throw _damaged;
  final start = e.offset + 30 + nameLength + extra;
  if (start + e.compressed > directory) throw _damaged;
  await raf.setPosition(start);
  final pending = <List<int>>[];
  final inflate = e.method == 8 ? ZLibDecoder(raw: true).startChunkedConversion(_Collect(pending)) : null;
  var crc = 0;
  var size = 0;
  Future<void> drain() async {
    for (final chunk in pending) {
      size += chunk.length;
      if (size > e.size) throw _damaged;
      crc = crc32(chunk, crc);
      await write(chunk);
    }
    pending.clear();
  }

  var left = e.compressed;
  while (left > 0) {
    // Small steps: one step of deflated zeros unpacks to about a thousand times its size.
    final chunk = await raf.read(min(left, 16 * 1024));
    if (chunk.isEmpty) throw _damaged;
    left -= chunk.length;
    if (inflate == null) {
      pending.add(chunk);
    } else {
      inflate.add(chunk);
    }
    await drain();
  }
  inflate?.close();
  await drain();
  if (size != e.size || crc != e.crc) throw _damaged;
}

final _installationEntry = RegExp(r'^installations/([A-Za-z0-9_-]{1,64})/(.+)$');
final _directoryEntry = RegExp(r'^installations/([A-Za-z0-9_-]{1,64}/)?([A-Za-z0-9_-][A-Za-z0-9._-]*/)*$');
const _jsonEntries = {'manifest.json', 'installations.json', 'secrets.json'};

/// What [unpackBoxBackup] found.
class UnpackedBoxBackup {
  UnpackedBoxBackup({
    required this.manifest,
    required this.active,
    required this.list,
    required this.secrets,
    required this.files,
    required this.bytes,
    required this.entries,
  });

  final Map<String, Object?> manifest;
  final String active;

  /// Installations as in `installations.json` (`id`, `name`, `created`, `key`).
  final List<Map<String, Object?>> list;

  /// `secrets.json`, still sealed; `null` without one.
  final Map<String, Object?>? secrets;
  final int files;
  final int bytes;

  /// Every entry except `secrets.json` and folders: size, CRC-32 and the
  /// SHA-256 of the content (hex), for [verifyIntegrity].
  final Map<String, ({int size, int crc, String? sha256})> entries;
}

/// Checks the backup [zip] and unpacks it into [tree] (`installations.json`, `installations/`),
/// which must be empty. Nothing outside [tree] is touched. Throws [BoxBackupException] for:
/// not a zip or damaged, Zip64, encrypted entries, entries outside the known paths
/// ([backupCarries]: no `secure_keys.json`, `access.json`, certificate …), the same name twice,
/// more than [BoxBackup.maxEntries] entries, more than [BoxBackup.maxEntryBytes] per entry or
/// [BoxBackup.maxBytes] in total (checked from the directory, then while unpacking), not enough
/// free space ([free], else asked from the system), a foreign or newer `manifest.json`, no
/// installation, and files of installations missing from `installations.json`.
Future<UnpackedBoxBackup> unpackBoxBackup(File zip, Directory tree, {int? free}) async {
  final raf = await zip.open();
  try {
    final (entries, directory) = await _centralDirectory(raf, await raf.length());
    if (entries.length > BoxBackup.maxEntries) throw _damaged;
    final names = <String>{};
    final files = <(_ZipEntry, String id, String relative)>[];
    final json = <String, _ZipEntry>{};
    var total = 0;
    for (final e in entries) {
      if (!names.add(e.name.toLowerCase())) throw _damaged;
      if (e.size > BoxBackup.maxEntryBytes) {
        throw const BoxBackupException('Eine Datei in der Sicherung ist zu groß.', problem: 'tooLarge');
      }
      total += e.size;
      if (_jsonEntries.contains(e.name)) {
        if (e.size > BoxBackup.maxJsonBytes) throw _damaged;
        json[e.name] = e;
      } else if (_installationEntry.firstMatch(e.name) case final m? when !e.name.endsWith('/')) {
        if (!backupCarries(m[2]!)) {
          throw BoxBackupException(
            'Unbekannte Datei in der Sicherung: ${m[2]!.length > 80 ? m[2]!.substring(0, 80) : m[2]}',
          );
        }
        files.add((e, m[1]!, m[2]!));
      } else if (!(_directoryEntry.hasMatch(e.name) && e.size == 0)) {
        throw BoxBackupException(
          'Unbekannte Datei in der Sicherung: ${e.name.length > 80 ? e.name.substring(0, 80) : e.name}',
        );
      }
    }
    if (total > BoxBackup.maxBytes) {
      throw const BoxBackupException('Die Sicherung ist zu groß.', problem: 'tooLarge');
    }
    final space = free ?? await freeBytes(tree.parent.path);
    if (space != null && total + BoxBackup.reserveBytes > space) {
      throw const BoxBackupException(
        'Nicht genug freier Speicher zum Wiederherstellen.',
        problem: 'space',
        status: HttpStatus.insufficientStorage,
      );
    }

    final digests = <String, ({int size, int crc, String? sha256})>{};
    Future<void> extract(_ZipEntry e, Future<void> Function(List<int> chunk) write) async {
      final sha = e.name != 'secrets.json' ? Sha256Stream() : null;
      await _extract(raf, e, directory, (chunk) async {
        sha?.add(chunk);
        await write(chunk);
      });
      if (sha == null) return;
      digests[e.name] = (size: e.size, crc: e.crc, sha256: _hex(sha.close()));
    }

    Future<Object?> readJson(String name) async {
      final e = json[name];
      if (e == null) return null;
      final builder = BytesBuilder(copy: false);
      await extract(e, (chunk) async => builder.add(chunk));
      try {
        return jsonDecode(utf8.decode(builder.takeBytes()));
      } on Object {
        throw _damaged;
      }
    }

    final manifest = await readJson('manifest.json');
    if (manifest is! Map || manifest['format'] != BoxBackup.format || manifest['version'] is! int) throw _damaged;
    if ((manifest['version']! as int) > BoxBackup.version) {
      throw const BoxBackupException('Die Sicherung stammt von einer neueren Version.', problem: 'newer');
    }
    final index = _parseIndex(await readJson('installations.json'));
    if (index.list.isEmpty) throw const BoxBackupException('Die Sicherung enthält keine Anlage.');
    final ids = {for (final i in index.list) i['id']! as String};
    final secrets = await readJson('secrets.json');
    if (json.containsKey('secrets.json')) _sealedOf(secrets);
    if (files.any((f) => !ids.contains(f.$2))) throw _damaged;

    await tree.create(recursive: true);
    for (final id in ids) {
      await Directory('${tree.path}/installations/$id').create(recursive: true);
    }
    var bytes = 0;
    for (final (e, id, relative) in files) {
      final target = File('${tree.path}/installations/$id/$relative');
      // The names are checked; still, nothing lands outside the tree.
      if (!target.absolute.path.startsWith('${tree.absolute.path}/')) throw _damaged;
      await target.parent.create(recursive: true);
      final out = await target.open(mode: FileMode.writeOnly);
      try {
        await extract(e, (chunk) => out.writeFrom(chunk));
      } finally {
        await out.close();
      }
      if (relative == 'server.json') {
        // IP Secure passwords come only from the encrypted part, never from a plain entry
        // (an older or edited file could carry them).
        final server = await _jsonObject(target);
        if (server == null) throw _damaged;
        await writeAtomic(target, text: jsonEncode(_withoutPasswords(server)));
      }
      bytes += e.size;
    }
    return UnpackedBoxBackup(
      manifest: manifest.cast<String, Object?>(),
      active: index.active,
      list: index.list,
      secrets: secrets is Map ? secrets.cast<String, Object?>() : null,
      files: files.length,
      bytes: bytes,
      entries: digests,
    );
  } on BoxBackupException {
    rethrow;
  } on Object catch (e) {
    stderr.writeln('Sicherung lesen: $e');
    throw _damaged;
  } finally {
    await raf.close();
  }
}

// --- HTTP ----------------------------------------------------------------------------------------

class _Ticket {
  _Ticket(this.root, this.key, this.secrets, this.withheld, this.fileName, this.expires);
  final Directory root;

  /// Derived from the password, `null` without one or without secrets.
  final SecretsKey? key;
  final Map<String, Map<String, Object?>> secrets;
  final List<String> withheld;
  final String fileName;
  final DateTime expires;
}

class _Staged {
  _Staged(this.id, this.backup);
  final String id;
  final UnpackedBoxBackup backup;

  Map<String, Object?> toJson() {
    final m = backup.manifest;
    return {
      'stage': id,
      'created': m['created'],
      'server': m['server'],
      if (m['box'] case final Map<dynamic, dynamic> box) 'box': {'name': ?box['name'], 'container': ?box['container']},
      'active': backup.active,
      'installations': [
        for (final i in backup.list) {'id': i['id'], 'name': i['name']},
      ],
      'secrets': backup.secrets != null,
      if (m['withheld'] case final List<dynamic> w)
        'withheld': [
          for (final k in w)
            if (k is String) k,
        ],
      'files': backup.files,
      'bytes': backup.bytes,
    };
  }
}

/// `/api/backup…`: box backup and restore, admin only (box password, a device paired with it, or
/// Ingress in the add-on). See docs/backup-format.md.
///
/// - `GET /api/backup` → `{readOnly, needsCurrent, minPassword, busy, staged, previous}`
/// - `POST /api/backup` `{password?, previous?}` → `{ticket, fileName, secrets, withheld}`; with a
///   password the secrets are sealed now (several seconds on a Pi), [previous] is the name of a
///   state set aside by a restore.
/// - `GET /api/backup/download?ticket=…` → the zip (`check=1`: only checks the ticket). A ticket
///   holds for 10 minutes and one download.
/// - `POST /api/backup/form` (form fields `password`, `password2`): the zip straight away, for the
///   page `/pair` in the browser.
/// - `PUT /api/backup/restore` (body: the zip) → summary with `stage`; unpacks into
///   `restore-staging/` and checks everything, changes nothing else.
/// - `POST /api/backup/restore/apply` `{stage, password?, withoutSecrets?, current?}` → replaces
///   all installations; the current state moves to `restore-previous/<time>/`.
/// - `DELETE /api/backup/restore`: discards the uploaded backup.
/// - `DELETE /api/backup/previous/<name>`: deletes a state set aside.
///
/// Restoring is refused in read-only mode ([readOnly]). On the box and in Docker
/// [confirmPassword] asks for the current box password, as for locking out all devices.
class BoxBackupService {
  BoxBackupService(
    this.data,
    this.service, {
    required this.serverVersion,
    this.describe,
    this.readOnly = false,
    this.confirmPassword,
    this.onReplaced,
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final Directory data;
  final InstallationService service;
  final String serverVersion;

  /// Box name, container, LAN access for the manifest (informative, nothing is restored from it).
  final Map<String, Object?> Function()? describe;
  final bool readOnly;
  final Future<bool> Function(HttpRequest request, Object? current)? confirmPassword;

  /// After a restore (e.g. clear caches of the old installations).
  final void Function()? onReplaced;
  final DateTime Function() _clock;
  final Random _random;

  static const path = '/api/backup';
  static const formPath = '/api/backup/form';
  static const ticketLifetime = Duration(minutes: 10);
  static const _maxTickets = 4;

  Directory get _staging => Directory('${data.path}/restore-staging');
  Directory get _previous => Directory('${data.path}/restore-previous');
  static final _previousName = RegExp(r'^\d{8}-\d{6}(-\d{1,3})?$');

  final _tickets = <String, _Ticket>{};
  var _downloading = false;
  var _uploading = false;
  var _applying = false;
  _Staged? _staged;

  bool get _busy => _downloading || _uploading || _applying;

  /// While the folders are swapped: the server refuses `/api/files/` and `/api/installations`
  /// meanwhile (server.dart), so nothing writes into a folder that is being moved.
  bool get swapping => _swapping;
  var _swapping = false;

  static const _busyError = BoxBackupException('Es läuft schon eine Sicherung.', problem: 'busy', status: 409);

  /// Journal of a running swap in the data folder: `{"aside": "<name>"}`. If it is there at start,
  /// the box went down in the middle of a restore ([recover]).
  static File journalOf(Directory data) => File('${data.path}/restore-swap.json');

  /// Puts the previous state back if the box went down in the middle of a restore (power cut):
  /// the half restored folders go, the ones set aside return. Runs before the installations are
  /// opened (server.dart); without a journal it does nothing.
  static Future<void> recover(Directory data) async {
    final journal = journalOf(data);
    if (!await journal.exists()) return;
    try {
      final name = (await _jsonObject(journal))?['aside'];
      final aside = Directory('${data.path}/restore-previous/$name');
      if (name is String && _previousName.hasMatch(name) && await aside.exists()) {
        for (final relative in ['installations', 'installations.json', 'installations.json.bak']) {
          final kept = '${aside.path}/$relative';
          final type = await FileSystemEntity.type(kept, followLinks: false);
          if (type == FileSystemEntityType.notFound) continue;
          final live = '${data.path}/$relative';
          final liveType = await FileSystemEntity.type(live, followLinks: false);
          if (liveType == FileSystemEntityType.directory) await Directory(live).delete(recursive: true);
          if (liveType == FileSystemEntityType.file) await File(live).delete();
          type == FileSystemEntityType.directory ? await Directory(kept).rename(live) : await File(kept).rename(live);
        }
        if (await aside.list().isEmpty) await aside.delete();
        stderr.writeln('Sicherung: Wiederherstellen wurde unterbrochen, vorheriger Stand zurückgelegt');
      }
      await journal.delete();
    } on Object catch (e) {
      stderr.writeln('Sicherung: unterbrochenes Wiederherstellen nicht zurückgelegt: $e');
    }
  }

  /// Removes an upload left over from before a restart.
  Future<void> start() async {
    try {
      if (await _staging.exists()) await _staging.delete(recursive: true);
    } on FileSystemException catch (e) {
      stderr.writeln('restore-staging: $e');
    }
  }

  String _token() => base64Url.encode(_randomBytes(24, _random)).replaceAll('=', '');

  Future<void> _fail(HttpResponse response, int status, String problem, String message) async {
    response.statusCode = status;
    await sendJson(response, {'error': message, 'problem': problem});
  }

  /// `true` if [request] was a backup path and has been answered.
  Future<bool> serve(HttpRequest request, {required bool admin}) async {
    final p = request.uri.path;
    if (p != path && !p.startsWith('$path/')) return false;
    final response = request.response;
    if (!admin) {
      response
        ..statusCode = HttpStatus.forbidden
        ..headers.contentType = ContentType.text
        ..write('Nur mit dem Box-Passwort.');
      await response.close();
      return true;
    }
    try {
      switch ((request.method, p)) {
        case ('GET', path):
          await sendJson(response, await status());
        case ('POST', path):
          await _ticket(request);
        case ('GET', '$path/download'):
          await _download(request);
        case ('POST', formPath):
          await _form(request);
        case ('PUT', '$path/restore'):
          await _upload(request);
        case ('DELETE', '$path/restore'):
          if (_busy) throw _busyError;
          await _discard();
          response.statusCode = HttpStatus.noContent;
          await response.close();
        case ('POST', '$path/restore/apply'):
          await _apply(request);
        case ('DELETE', _) when p.startsWith('$path/previous/'):
          await _deletePrevious(response, p.substring('$path/previous/'.length));
        default:
          response.statusCode = HttpStatus.methodNotAllowed;
          await response.close();
      }
    } on BoxBackupException catch (e) {
      await _fail(response, e.status, e.problem, e.message);
    } on TooManyAttemptsException catch (e) {
      response.headers.set(HttpHeaders.retryAfterHeader, '${e.retryAfter.inSeconds + 1}');
      await _fail(response, HttpStatus.tooManyRequests, 'tooMany', 'Zu viele Fehlversuche, bitte warten.');
    }
    return true;
  }

  /// State for the app: whether restoring is possible, the uploaded backup, the states set aside.
  Future<Map<String, Object?>> status() async => {
    'readOnly': readOnly,
    'needsCurrent': confirmPassword != null,
    'minPassword': BoxBackup.minPassword,
    'busy': _busy,
    'staged': _staged?.toJson(),
    'previous': await _listPrevious(),
  };

  Future<List<Map<String, Object?>>> _listPrevious() async {
    if (!await _previous.exists()) return const [];
    final out = <Map<String, Object?>>[];
    await for (final e in _previous.list()) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (e is! Directory || !_previousName.hasMatch(name)) continue;
      final index = await _readIndex(e);
      out.add({
        'name': name,
        'created': (await e.stat()).modified.toUtc().toIso8601String(),
        'installations': [for (final i in index.list) i['name']],
      });
    }
    out.sort((a, b) => (b['name']! as String).compareTo(a['name']! as String));
    return out;
  }

  Future<Map<String, Object?>?> _body(HttpRequest request) async {
    final raw = await readBody(request, 4096);
    if (raw == null) return null;
    try {
      final j = raw.isEmpty ? const <String, Object?>{} : jsonDecode(utf8.decode(raw));
      return j is Map ? j.cast<String, Object?>() : null;
    } on Object {
      return null;
    }
  }

  String _day(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}'
      '-${t.hour.toString().padLeft(2, '0')}${t.minute.toString().padLeft(2, '0')}';

  /// Password from a request: `null` without one, throws if it is too short or too long.
  String? _password(Object? value) {
    if (value == null || value == '') return null;
    if (value is! String || value.length < BoxBackup.minPassword || value.length > BoxBackup.maxPassword) {
      throw BoxBackupException(
        'Das Passwort der Sicherung braucht mindestens ${BoxBackup.minPassword} Zeichen.',
        problem: 'passwordShort',
      );
    }
    return value;
  }

  /// Prepares a download of [root] (derives the key for the secrets from [password]).
  Future<_Ticket> _prepare(Directory root, String? password, String fileName) async {
    if (_applying) throw _busyError;
    if (root.path == data.path) await service.bus.recorder.flush();
    final secrets = await collectSecrets(root);
    final key = password == null || secrets.isEmpty ? null : await SecretsKey.derive(password, random: _random);
    return _Ticket(
      root,
      key,
      key == null ? const {} : secrets,
      password == null ? secretKinds(secrets) : const [],
      fileName,
      _clock().add(ticketLifetime),
    );
  }

  Future<void> _ticket(HttpRequest request) async {
    final body = await _body(request);
    if (body == null) throw const BoxBackupException('Ungültige Anfrage.');
    final password = _password(body['password']);
    var root = data;
    var fileName = 'busclear-box-sicherung-${_day(_clock())}.zip';
    if (body['previous'] case final Object previous) {
      if (previous is! String || !_previousName.hasMatch(previous))
        throw const BoxBackupException('Ungültige Anfrage.');
      root = Directory('${_previous.path}/$previous');
      if (!await root.exists()) {
        throw const BoxBackupException('Diesen früheren Stand gibt es nicht.', status: HttpStatus.notFound);
      }
      fileName = 'busclear-box-vorher-$previous.zip';
    }
    final ticket = await _prepare(root, password, fileName);
    final now = _clock();
    _tickets.removeWhere((_, t) => !t.expires.isAfter(now));
    while (_tickets.length >= _maxTickets) {
      _tickets.remove(_tickets.keys.first);
    }
    final id = _token();
    _tickets[id] = ticket;
    await sendJson(request.response, {
      'ticket': id,
      'fileName': ticket.fileName,
      'secrets': ticket.key != null,
      'withheld': ticket.withheld,
      // Estimate for the progress bar: the files as they are on disk (the zip is somewhat smaller).
      'bytes': await estimateBoxBackup(ticket.root),
    });
  }

  Future<void> _download(HttpRequest request) async {
    final id = request.uri.queryParameters['ticket'] ?? '';
    final ticket = _tickets[id];
    if (ticket == null || !ticket.expires.isAfter(_clock())) {
      _tickets.remove(id);
      throw const BoxBackupException(
        'Der Download ist abgelaufen, bitte die Sicherung neu starten.',
        problem: 'ticket',
        status: HttpStatus.notFound,
      );
    }
    if (_busy) throw const BoxBackupException('Es läuft schon eine Sicherung.', problem: 'busy', status: 429);
    if (request.uri.queryParameters['check'] == '1') {
      request.response.statusCode = HttpStatus.noContent;
      return request.response.close();
    }
    _tickets.remove(id);
    await _stream(request.response, ticket);
  }

  /// The form on `/pair`: errors go back to the page as a notice (BoxAccess.backupNotice), not
  /// as JSON in the browser.
  Future<void> _form(HttpRequest request) async {
    try {
      await _formDownload(request);
    } on BoxBackupException catch (e) {
      request.response
        ..statusCode = HttpStatus.seeOther
        ..headers.set(HttpHeaders.locationHeader, '/pair?backup=${Uri.encodeQueryComponent(e.problem)}');
      await request.response.close();
    }
  }

  Future<void> _formDownload(HttpRequest request) async {
    final raw = await readBody(request, 4096);
    final form = raw == null ? null : Uri.splitQueryString(utf8.decode(raw, allowMalformed: true));
    if (form == null) throw const BoxBackupException('Ungültige Anfrage.');
    final password = form['password'] ?? '';
    if (password.isNotEmpty && password != form['password2']) {
      throw const BoxBackupException('Die beiden Passwörter stimmen nicht überein.', problem: 'mismatch');
    }
    if (_busy) throw const BoxBackupException('Es läuft schon eine Sicherung.', problem: 'busy', status: 429);
    // Reserve the slot before the first await, or two forms could both pass the check.
    _downloading = true;
    final _Ticket ticket;
    try {
      ticket = await _prepare(data, _password(password), 'busclear-box-sicherung-${_day(_clock())}.zip');
    } on Object {
      _downloading = false;
      rethrow;
    }
    await _stream(request.response, ticket);
  }

  Future<void> _stream(HttpResponse response, _Ticket ticket) async {
    _downloading = true;
    try {
      response.headers
        ..contentType = ContentType('application', 'zip')
        ..set(HttpHeaders.cacheControlHeader, 'no-store')
        ..set('Content-Disposition', 'attachment; filename="${ticket.fileName}"');
      // Collect the zip's many small pieces into larger ones before sending.
      final buffer = BytesBuilder(copy: true);
      Future<void> push() async {
        response.add(buffer.takeBytes());
        await response.flush();
      }

      try {
        await writeBoxBackup(
          ticket.root,
          (bytes) async {
            buffer.add(bytes);
            if (buffer.length >= 256 * 1024) await push();
          },
          serverVersion: serverVersion,
          key: ticket.key,
          secrets: ticket.secrets,
          withheld: ticket.withheld,
          box: describe?.call() ?? const {},
          now: _clock(),
        );
        if (buffer.isNotEmpty) await push();
      } on Object catch (e) {
        // Headers are out: cut the connection, so the client sees a broken download, not a
        // quietly incomplete one (the app also checks the zip's end record).
        stderr.writeln('Sicherung: abgebrochen: $e');
        try {
          (await response.detachSocket(writeHeaders: false)).destroy();
          return;
        } on Object {
          // Fall through and close normally.
        }
      }
      await response.close();
    } finally {
      _downloading = false;
    }
  }

  Future<void> _discard() async {
    _staged = null;
    if (await _staging.exists()) await _staging.delete(recursive: true);
  }

  Future<void> _upload(HttpRequest request) async {
    if (readOnly) throw _readOnly;
    if (_busy) throw const BoxBackupException('Es läuft schon eine Sicherung.', problem: 'busy', status: 409);
    if (request.contentLength > BoxBackup.maxBytes) {
      throw const BoxBackupException(
        'Die Sicherung ist zu groß.',
        problem: 'tooLarge',
        status: HttpStatus.requestEntityTooLarge,
      );
    }
    _uploading = true;
    try {
      await _discard();
      await _staging.create(recursive: true);
      final free = await freeBytes(data.path);
      // The zip and what it unpacks to are on the disk at the same time.
      if (free != null && request.contentLength > 0 && 2 * request.contentLength + BoxBackup.reserveBytes > free) {
        throw const BoxBackupException(
          'Nicht genug freier Speicher zum Wiederherstellen.',
          problem: 'space',
          status: HttpStatus.insufficientStorage,
        );
      }
      final zip = File('${_staging.path}/upload.zip');
      final out = await zip.open(mode: FileMode.writeOnly);
      var size = 0;
      var checked = 0;
      try {
        await for (final chunk in request) {
          size += chunk.length;
          if (size > BoxBackup.maxBytes) {
            throw const BoxBackupException(
              'Die Sicherung ist zu groß.',
              problem: 'tooLarge',
              status: HttpStatus.requestEntityTooLarge,
            );
          }
          await out.writeFrom(chunk);
          if (size - checked > 64 * 1024 * 1024) {
            checked = size;
            final left = await freeBytes(data.path);
            if (left != null && left < BoxBackup.reserveBytes) {
              throw const BoxBackupException(
                'Nicht genug freier Speicher zum Wiederherstellen.',
                problem: 'space',
                status: HttpStatus.insufficientStorage,
              );
            }
          }
        }
      } finally {
        await out.close();
      }
      final UnpackedBoxBackup backup;
      try {
        backup = await unpackBoxBackup(zip, Directory('${_staging.path}/tree'));
      } finally {
        if (await zip.exists()) await zip.delete();
      }
      final staged = _Staged(_token(), backup);
      _staged = staged;
      await sendJson(request.response, staged.toJson());
    } on Object {
      _staged = null;
      try {
        if (await _staging.exists()) await _staging.delete(recursive: true);
      } on FileSystemException {
        // Removed on the next start.
      }
      rethrow;
    } finally {
      _uploading = false;
    }
  }

  static const _readOnly = BoxBackupException(
    'Nur-Lesen ist an: Wiederherstellen ist gesperrt.',
    problem: 'readOnly',
    status: HttpStatus.conflict,
  );

  Future<void> _apply(HttpRequest request) async {
    final response = request.response;
    if (readOnly) throw _readOnly;
    final body = await _body(request);
    if (body == null) throw const BoxBackupException('Ungültige Anfrage.');
    final staged = _staged;
    if (staged == null || body['stage'] != staged.id) throw _stageGone;
    if (_busy) throw _busyError;
    // Taken before the first wait: an upload or discard meanwhile would replace the staged backup
    // while its password is being checked.
    _applying = true;
    final String previous;
    final Map<String, Map<String, Object?>>? secrets;
    final backup = staged.backup;
    try {
      if (confirmPassword != null && !await confirmPassword!(request, body['current'])) {
        response
          ..statusCode = HttpStatus.forbidden
          ..headers.contentType = ContentType.text
          ..write('Das aktuelle Passwort stimmt nicht.');
        return await response.close();
      }
      secrets = await _openStaged(backup, body);
      if (!identical(_staged, staged)) throw _stageGone;
      final boxKey = service.installations.boxKey;
      _swapping = true;
      try {
        previous = await service.replaceAll(() => _swap(backup, secrets, boxKey));
      } finally {
        _swapping = false;
      }
      await _discard();
    } finally {
      _applying = false;
    }
    onReplaced?.call();
    stdout.writeln(
      'Sicherung wiederhergestellt: ${backup.list.length} Anlagen, vorheriger Stand in restore-previous/$previous',
    );
    await sendJson(response, {
      'installations': backup.list.length,
      'files': backup.files,
      'secrets': secrets != null,
      'secretsSkipped': backup.secrets != null && secrets == null,
      'previous': previous,
      'active': backup.active,
    });
  }

  static const _stageGone = BoxBackupException(
    'Keine hochgeladene Sicherung, bitte die Datei noch einmal wählen.',
    problem: 'stage',
    status: HttpStatus.conflict,
  );

  /// The secrets of the staged [backup] with the password from [body], checked against the plain
  /// part; `null` when restoring without them (only on explicit `withoutSecrets`).
  Future<Map<String, Map<String, Object?>>?> _openStaged(UnpackedBoxBackup backup, Map<String, Object?> body) async {
    if (backup.secrets == null) return null;
    final password = body['password'];
    if (password is String && password.isNotEmpty) {
      final opened = await openSecrets(backup.secrets, password, {for (final i in backup.list) i['id']! as String});
      if (opened == null) {
        throw const BoxBackupException(
          'Das Passwort der Sicherung stimmt nicht.',
          problem: 'backupPassword',
          status: HttpStatus.unprocessableEntity,
        );
      }
      verifyIntegrity(backup, opened.integrity);
      return opened.installations;
    }
    if (body['withoutSecrets'] == true) return null;
    throw const BoxBackupException(
      'Die Sicherung enthält verschlüsselte Schlüssel: Passwort angeben oder ohne Schlüssel wiederherstellen.',
      problem: 'passwordMissing',
      status: HttpStatus.unprocessableEntity,
    );
  }

  /// Sets the current state aside and puts the unpacked one in its place; returns the name of the
  /// state set aside. On an error the current state is moved back.
  Future<String> _swap(UnpackedBoxBackup backup, Map<String, Map<String, Object?>>? secrets, String boxKey) async {
    final t = _clock();
    String two(int v) => v.toString().padLeft(2, '0');
    final base = '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
    var name = base;
    for (var n = 1; await Directory('${_previous.path}/$name').exists(); n++) {
      name = '$base-$n';
    }
    final aside = Directory('${_previous.path}/$name');
    await aside.create(recursive: true);
    final journal = journalOf(data);
    await writeAtomic(journal, text: jsonEncode({'aside': name}));
    final moved = <(String, String)>[];
    final target = Directory('${data.path}/installations');
    var placed = false;
    try {
      for (final relative in ['installations', 'installations.json', 'installations.json.bak']) {
        final from = '${data.path}/$relative';
        final type = await FileSystemEntity.type(from, followLinks: false);
        if (type == FileSystemEntityType.notFound) continue;
        final to = '${aside.path}/$relative';
        if (type == FileSystemEntityType.directory) {
          await Directory(from).rename(to);
        } else {
          await File(from).rename(to);
        }
        moved.add((from, to));
      }
      await Directory('${_staging.path}/tree/installations').rename(target.path);
      placed = true;
      await writeAtomic(
        File('${data.path}/installations.json'),
        text: jsonEncode({
          'version': 1,
          if (boxKey.isNotEmpty) 'box': boxKey,
          'active': backup.active,
          'list': backup.list,
        }),
      );
      for (final MapEntry(key: id, value: entry) in (secrets ?? const {}).entries) {
        final dir = '${target.path}/$id';
        for (final name in _secretFiles) {
          if (entry[name] case final Object value) await writeAtomic(File('$dir/$name'), text: jsonEncode(value));
        }
        if (entry[_busSecure] case final Object secure) {
          final file = File('$dir/server.json');
          final server = await _jsonObject(file) ?? <String, Object?>{};
          await writeAtomic(file, text: jsonEncode({...server, 'secure': secure}));
        }
      }
      await _keepSequences(aside, target, backup);
      await journal.delete();
      return name;
    } on Object {
      try {
        if (placed) {
          if (await target.exists()) await target.delete(recursive: true);
          final index = File('${data.path}/installations.json');
          if (await index.exists()) await index.delete();
        }
        for (final (from, to) in moved.reversed) {
          await FileSystemEntity.isDirectory(to) ? await Directory(to).rename(from) : await File(to).rename(from);
        }
        if (moved.isEmpty || await aside.list().isEmpty) await aside.delete(recursive: true);
        if (await journal.exists()) await journal.delete();
      } on Object catch (e) {
        stderr.writeln('Sicherung: Zurücklegen fehlgeschlagen, alter Stand in ${aside.path}: $e');
      }
      rethrow;
    }
  }

  /// KNX Data Secure sequence numbers only rise: a restored older state must not let telegrams
  /// through again that the box already saw (files.dart, `secure_sequence.json`). The restored
  /// numbers come only from the encrypted part (a plain `secure_sequence.json` is refused); each
  /// installation then gets the highest of those, of the previous state's `secure_sequence.json`
  /// and of the `sequence` in its keyring, matched by id or installation key.
  Future<void> _keepSequences(Directory aside, Directory target, UnpackedBoxBackup backup) async {
    final before = (await _readIndex(aside)).list;
    for (final i in backup.list) {
      final id = i['id']! as String;
      final match = before.where((b) => b['id'] == id || (i['key'] != null && b['key'] == i['key'])).firstOrNull;
      final file = File('${target.path}/$id/secure_sequence.json');
      final merged = <String, int>{};
      void take(Object? numbers) {
        if (numbers is! Map) return;
        for (final MapEntry(:key, :value) in numbers.entries) {
          if (key is! String || !RegExp(r'^\d{1,5}$').hasMatch(key) || value is! int || value < 0) continue;
          if (value > _maxSequence) continue;
          if (value > (merged[key] ?? -1)) merged[key] = value;
        }
      }

      take(await _jsonObject(file));
      if (match != null) {
        final dir = '${aside.path}/installations/${match['id']}';
        take(await _jsonObject(File('$dir/secure_sequence.json')));
        take((await _jsonObject(File('$dir/secure_keys.json')))?['sequence']);
      } else if (await File('${target.path}/$id/secure_keys.json').exists()) {
        stderr.writeln(
          'Sicherung: $id hat einen Keyring, aber keinen vorigen Stand auf dieser Box; '
          'Folgenummern nur aus der Sicherung',
        );
      }
      if (merged.isNotEmpty) await writeAtomic(file, text: jsonEncode(merged));
    }
  }

  /// KNX Data Secure sequence numbers have 48 bits.
  static const _maxSequence = 0xFFFFFFFFFFFF;

  Future<void> _deletePrevious(HttpResponse response, String name) async {
    if (!_previousName.hasMatch(name)) throw const BoxBackupException('Ungültige Anfrage.');
    final dir = Directory('${_previous.path}/$name');
    if (!await dir.exists())
      throw const BoxBackupException('Diesen früheren Stand gibt es nicht.', status: HttpStatus.notFound);
    if (_busy) throw const BoxBackupException('Es läuft schon eine Sicherung.', problem: 'busy', status: 409);
    await dir.delete(recursive: true);
    response.statusCode = HttpStatus.noContent;
    await response.close();
  }
}
