import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'crypto_worker.dart';
import 'file_cipher.dart';
import 'storage.dart';

AppStorage createStorage() => IoStorage(null, KeychainFileKey());

/// See [IoStorage.encryptExisting].
Future<void> encryptExistingFiles() async {
  final storage = AppStorage.instance;
  if (storage is IoStorage) await storage.encryptExisting();
}

/// See [IoStorage.allPaths].
Future<List<String>> allStoredPaths() async {
  final storage = AppStorage.instance;
  return storage is IoStorage ? storage.allPaths() : const [];
}

/// See [IoStorage.extras].
Future<StorageExtras> storageExtras() async {
  final storage = AppStorage.instance;
  return storage is IoStorage ? storage.extras() : noStorageExtras;
}

/// See [IoStorage.deleteQuarantined].
Future<void> deleteQuarantinedFiles() async {
  final storage = AppStorage.instance;
  if (storage is IoStorage) await storage.deleteQuarantined();
}

Future<void> deleteCorruptCopies(AppStorage storage, String path) async {
  var base = storage;
  var full = path;
  while (base is ScopedStorage) {
    full = '${base.prefix}$full';
    base = base.base;
  }
  if (base is IoStorage) await base.deleteCorruptCopies(full);
}

/// Where the key of the files comes from.
abstract interface class FileKeySource {
  /// Existing key, or `null` if the keychain is currently unavailable. [onCreated] runs before a
  /// new key is used for the first time.
  Future<Uint8List?> load(Future<void> Function() onCreated);
}

/// Key in the keychain. Deliberately without "this_device": it comes along with an encrypted device
/// backup, otherwise the files would be lost afterwards.
///
/// [read] and [write] only for tests.
class KeychainFileKey implements FileKeySource {
  KeychainFileKey({
    Future<String?> Function(String key)? read,
    Future<void> Function(String key, String value)? write,
    this.recheck = const Duration(milliseconds: 200),
  }) : _read = read ?? ((key) => _vault.read(key: key)),
       _write = write ?? ((key, value) => _vault.write(key: key, value: value));

  static const _name = 'knx_file_key';

  /// `resetOnError: false`: if decryption fails (Android Keystore after a device change), the entry
  /// would otherwise not be left alone but everything would be deleted.
  static const _vault = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock, usesDataProtectionKeychain: false),
  );

  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;

  /// Wait time before the second look, before the key counts as missing.
  final Duration recheck;

  /// A new key moves all files aside ([onCreated]). That may only happen if the old one is really
  /// missing: if reading throws, everything stays as it is.
  @override
  Future<Uint8List?> load(Future<void> Function() onCreated) async {
    try {
      var stored = await _read(_name);
      if (stored != null) return base64Decode(stored);
      await Future<void>.delayed(recheck);
      stored = await _read(_name);
      if (stored != null) return base64Decode(stored);
      final r = Random.secure();
      final key = Uint8List.fromList(List.generate(32, (_) => r.nextInt(256)));
      await _write(_name, base64Encode(key));
      // Only use what can also be read back.
      if (await _read(_name) != base64Encode(key)) return null;
      await onCreated();
      return key;
    } on Object catch (e) {
      debugPrint('Ablage: Schlüsselbund nicht nutzbar, Dateien bleiben unverschlüsselt: $e');
      return null;
    }
  }
}

/// Storage in the app directory (or in [root], e.g. for tests).
///
/// Encrypted with [keySource]: protects files when someone removes the storage medium or uses
/// another user account. Without a keychain (Linux without libsecret) it stays unencrypted as
/// before; anything already encrypted is then never overwritten.
class IoStorage implements AppStorage {
  IoStorage([this.root, this.keySource]);

  final Directory? root;
  final FileKeySource? keySource;

  /// From this size on, UTF-8 is no longer decoded on the UI thread.
  static const _bigFile = 256 * 1024;

  /// Previous version next to the file; see [write].
  static const prevSuffix = '.prev';

  /// Version moved aside: `<file>.corrupt-<time>`.
  static const corruptInfix = '.corrupt-';

  /// Larger files keep no previous version, otherwise they take up double the space.
  @visibleForTesting
  static int maxPrevBytes = 16 * 1024 * 1024;

  /// How long versions moved aside are kept; the newest per file always stays.
  static const corruptKeep = Duration(days: 30);

  CryptoWorker get _worker => CryptoWorker.instance;

  Future<Uint8List?>? _key;

  Future<Directory> get _base async => root ?? await getApplicationSupportDirectory();

  Future<Uint8List?> _keyNow() => _key ??= keySource == null ? Future.value() : keySource!.load(_quarantine);

  Future<File> _file(String path) async {
    final file = File(await _resolve(path));
    await file.parent.create(recursive: true);
    return file;
  }

  /// Absolute path of [path] below the base folder. Throws [ArgumentError] for a path that would
  /// leave it ([confinedPath]); the normalised comparison afterwards guards the join itself.
  Future<String> _resolve(String path) async {
    confinedPath(path);
    final base = await _base;
    final joined = '${base.path}/$path';
    final windows = Platform.isWindows;
    final root = Uri.directory(base.path, windows: windows).normalizePath().path;
    final target = Uri.file(joined, windows: windows).normalizePath().path;
    if (!target.startsWith(root)) throw ArgumentError.value(path, 'path', 'leaves the storage folder');
    return joined;
  }

  /// Files that could not be read last time; see [write].
  final _damaged = <String>{};

  @override
  Future<String?> read(String path) async {
    // First: a new key moves old files aside.
    final key = await _keyNow();
    final f = await _file(path);
    final prev = File('${f.path}$prevSuffix');
    if (!await f.exists()) {
      // Aborted between the two renames in [write]; [delete] removes both.
      if (!await prev.exists()) return null;
      debugPrint('Ablage: $path fehlt, vorige Fassung genommen');
      return await _readPrev(prev, key, path) ?? (throw StorageCorruptException(path));
    }
    String? text;
    try {
      final content = await _readText(f);
      if (!isEncrypted(content)) {
        _damaged.remove(path);
        return content;
      }
      if (key == null) throw StorageLockedException(path);
      text = await _open(key, content);
    } on FileSystemException catch (e) {
      debugPrint('Ablage: $path nicht lesbar: $e');
    }
    if (text != null) {
      _damaged.remove(path);
      return text;
    }
    _damaged.add(path);
    // Damaged: better the previous version than nothing at all.
    final older = await _readPrev(prev, key, path);
    if (older != null) {
      debugPrint('Ablage: $path beschädigt, vorige Fassung genommen');
      return older;
    }
    throw StorageCorruptException(path);
  }

  Future<String?> _readPrev(File prev, Uint8List? key, String path) async {
    if (!await prev.exists()) return null;
    final String older;
    try {
      older = await _readText(prev);
    } on FileSystemException {
      return null;
    }
    if (!isEncrypted(older)) return older;
    if (key == null) throw StorageLockedException(path);
    return _open(key, older);
  }

  /// Like `readAsString`, but large files without UTF-8 decoding on the UI thread.
  Future<String> _readText(File f) async {
    if (await f.length() <= _bigFile) return f.readAsString();
    final text = await _worker.run(decodeTextJob, await f.readAsBytes());
    return text ?? (throw FileSystemException('Kein gültiges UTF-8', f.path));
  }

  Future<String?> _open(Uint8List key, String content) => _worker.run(decryptFileJob, (key: key, content: content));

  Future<String> _seal(Uint8List key, String text) => _worker.run(encryptFileJob, (key: key, text: text));

  /// One after another per file: otherwise encrypting old data could overwrite a write from a split
  /// second earlier with the old content.
  final _busy = <String, Future<void>>{};

  Future<T> _oneAtATime<T>(String path, Future<T> Function() work) async {
    final before = _busy[path] ?? Future<void>.value();
    final done = before.catchError((Object _) {}).then((_) => work());
    final settled = done.then<void>((_) {}, onError: (Object _) {});
    _busy[path] = settled;
    unawaited(
      settled.then((_) {
        if (identical(_busy[path], settled)) _busy.remove(path);
      }),
    );
    return done;
  }

  @override
  Future<void> write(String path, String text) async {
    final file = await _file(path);
    return _oneAtATime(file.path, () => _write(file, path, text));
  }

  Future<void> _write(File file, String path, String text) async {
    // Write next to it first, then rename: anyone reading, or if the app is terminated midway, sees
    // the old or the new file, never an empty one. A unique name per call.
    final key = await _keyNow();
    if (key == null && await _startsEncrypted(file)) throw StorageLockedException(path);
    final tmp = File('${file.path}.$pid-${_tmpCounter++}.tmp');
    try {
      await tmp.writeAsString(key == null ? text : await _seal(key, text), flush: true);
      // The previous version is kept: if a store reads a broken file as empty and saves, it would
      // otherwise be gone for good. We do not keep unencrypted old data this way.
      try {
        if (await file.exists()) {
          if (_damaged.remove(path)) {
            // Could not be read: whoever saves now does not know the content. The file stays aside
            // and does not displace a readable previous version.
            await file.rename('${file.path}$corruptInfix${DateTime.now().millisecondsSinceEpoch}');
          } else if (await file.length() > maxPrevBytes) {
            // Too large to keep twice; the rename below replaces it atomically. An older version
            // would otherwise remain as a state from long ago.
            final prev = File('${file.path}$prevSuffix');
            if (await prev.exists()) await prev.delete();
          } else if (key == null || await _startsEncrypted(file)) {
            try {
              await file.rename('${file.path}$prevSuffix');
            } on FileSystemException catch (e) {
              // A parallel write was faster; its version is sufficient.
              debugPrint('Ablage: vorige Fassung nicht behalten: $e');
            }
          }
          // Otherwise the file stays: the rename below replaces it atomically.
        }
      } on PathNotFoundException catch (e) {
        // A parallel write just removed the file; the rename below applies anyway.
        debugPrint('Ablage: vorige Fassung nicht behalten: $e');
      }
      try {
        await tmp.rename(file.path);
      } on FileSystemException {
        // Should Windows ever refuse the replace: better the small window than not saving at all.
        if (!Platform.isWindows || !await file.exists()) rethrow;
        await file.delete();
        await tmp.rename(file.path);
      }
    } on Object {
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
  }

  static var _tmpCounter = 0;

  Future<bool> _startsEncrypted(File file) async {
    if (!await file.exists()) return false;
    final head = await file.openRead(0, encryptedHeader.length).expand((b) => b).toList();
    return String.fromCharCodes(head) == encryptedHeader;
  }

  @override
  Future<void> append(String path, String text) async {
    final file = await _file(path);
    final key = await _keyNow();
    final encrypted = await _startsEncrypted(file);
    if (key == null) {
      if (encrypted) throw StorageLockedException(path);
      await file.writeAsString(text, mode: FileMode.append, flush: true);
      return;
    }
    if (!encrypted && await file.exists()) await _encryptInPlace(file, key);
    final record = await _worker.run(encryptRecordJob, (key: key, text: text));
    final fresh = !await file.exists();
    await file.writeAsString('${fresh ? encryptedHeader : ''}$record', mode: FileMode.append, flush: true);
  }

  Future<void> _encryptInPlace(File file, Uint8List key) async {
    if (!await file.exists()) return;
    final text = await _readText(file);
    // Rewritten before us: that is already encrypted.
    if (isEncrypted(text)) return;
    final sealed = await _seal(key, text);
    final tmp = File('${file.path}.$pid-${_tmpCounter++}.tmp');
    await tmp.writeAsString(sealed, flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<List<StoredFile>> list(String dir) async {
    final d = Directory(await _resolve(dir));
    if (!await d.exists()) return [];
    return [
      await for (final f in d.list())
        // Do not count half-written files, previous versions and versions moved aside.
        if (f is File && !_isSideFile(f.uri.pathSegments.last)) (name: f.uri.pathSegments.last, size: await f.length()),
    ];
  }

  static bool _isSideFile(String name) =>
      name.endsWith('.tmp') || name.endsWith(prevSuffix) || name.contains(corruptInfix);

  /// Deletes the copies of [path] moved aside as unreadable.
  Future<void> deleteCorruptCopies(String path) async {
    final f = File(await _resolve(path));
    final dir = f.parent;
    if (!await dir.exists()) return;
    final prefix = '${f.uri.pathSegments.last}$corruptInfix';
    await for (final e in dir.list()) {
      if (e is File && e.uri.pathSegments.last.startsWith(prefix)) await e.delete();
    }
  }

  @override
  Future<void> delete(String path) async {
    final f = await _file(path);
    if (await f.exists()) await f.delete();
    final prev = File('${f.path}$prevSuffix');
    if (await prev.exists()) await prev.delete();
    _damaged.remove(path);
  }

  /// All files of the app, relative. For the backup.
  Future<List<String>> allPaths() async {
    final base = await _base;
    return [
      await for (final f in base.list(recursive: true))
        if (f is File && _isOurs(f, base)) f.path.substring(base.path.length + 1),
    ];
  }

  /// Only our own text files: on Windows and Linux the same folder also holds the settings, which
  /// the plugin reads itself.
  static bool _isOurs(File f, Directory base) {
    final name = f.uri.pathSegments.last;
    if (name == 'shared_preferences.json' || name.endsWith('.tmp') || name.endsWith(prevSuffix)) return false;
    if (f.path.startsWith('${base.path}/$quarantineDir/')) return false;
    return const ['.json', '.ndjson', '.jsonl', '.bak', '.csv', '.txt', '.log', '.b64'].any(name.endsWith);
  }

  static const quarantineDir = 'nicht-lesbar';

  /// Encrypt existing files in the background; atomically per file. If the app aborts, the next
  /// start continues there: whatever carries the header is done. Between files, pause at least as
  /// long as the last one took so battery and ongoing work do not notice. [pause] only for tests.
  Future<int> encryptExisting({Future<void> Function(Duration)? pause}) async {
    await cleanSideFiles();
    final key = await _keyNow();
    if (key == null) return 0;
    final wait = pause ?? (d) => Future<void>.delayed(d);
    var done = 0;
    final base = await _base;
    for (final path in await allPaths()) {
      final file = File('${base.path}/$path');
      if (!await file.exists() || await _startsEncrypted(file)) continue;
      final watch = Stopwatch()..start();
      try {
        await _oneAtATime(file.path, () => _encryptInPlace(file, key));
        done++;
      } on Object catch (e) {
        debugPrint('Ablage: $path bleibt unverschlüsselt: $e');
      }
      await wait(watch.elapsed + const Duration(milliseconds: 20));
    }
    return done;
  }

  /// Cleans up: versions moved aside older than [corruptKeep], except the newest per file; `.tmp`
  /// files left behind by an abort more than a day ago.
  Future<void> cleanSideFiles({DateTime? now}) async {
    final base = await _base;
    if (!await base.exists()) return;
    final time = now ?? DateTime.now();
    final corrupt = <String, List<(File, DateTime)>>{};
    await for (final f in base.list(recursive: true)) {
      if (f is! File || f.path.startsWith('${base.path}/$quarantineDir/')) continue;
      try {
        final modified = await f.lastModified();
        final cut = f.path.lastIndexOf(corruptInfix);
        if (cut > 0) {
          (corrupt[f.path.substring(0, cut)] ??= []).add((f, modified));
        } else if (f.path.endsWith('.tmp') && time.difference(modified) > const Duration(days: 1)) {
          await f.delete();
        }
      } on FileSystemException catch (e) {
        debugPrint('Ablage: nicht aufgeräumt: $e');
      }
    }
    for (final files in corrupt.values) {
      files.sort((a, b) => b.$2.compareTo(a.$2));
      for (final (f, modified) in files.skip(1)) {
        if (time.difference(modified) <= corruptKeep) continue;
        try {
          await f.delete();
        } on FileSystemException catch (e) {
          debugPrint('Ablage: nicht aufgeräumt: $e');
        }
      }
    }
  }

  /// What lies next to the actual data, for display.
  Future<StorageExtras> extras() async {
    final base = await _base;
    var prev = 0;
    var corrupt = 0;
    var quarantined = 0;
    var quarantinedBytes = 0;
    if (await base.exists()) {
      await for (final f in base.list(recursive: true)) {
        if (f is! File) continue;
        final size = await f.length();
        if (f.path.startsWith('${base.path}/$quarantineDir/')) {
          quarantined++;
          quarantinedBytes += size;
        } else if (f.path.endsWith(prevSuffix)) {
          prev += size;
        } else if (f.uri.pathSegments.last.contains(corruptInfix)) {
          corrupt += size;
        }
      }
    }
    return (
      previousBytes: prev,
      corruptBytes: corrupt,
      quarantinedFiles: quarantined,
      quarantinedBytes: quarantinedBytes,
    );
  }

  /// The user gives up the files moved aside.
  Future<void> deleteQuarantined() async {
    final dir = Directory('${(await _base).path}/$quarantineDir');
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// New key, but encrypted files: the old one is gone (device restored without a keychain backup).
  /// Do not let them be overwritten, but move them aside; with a separate backup the content comes
  /// back.
  Future<void> _quarantine() async {
    final base = await _base;
    final target = '${base.path}/$quarantineDir';
    for (final path in await allPaths()) {
      final file = File('${base.path}/$path');
      if (!await _startsEncrypted(file)) continue;
      final moved = File('$target/$path');
      await moved.parent.create(recursive: true);
      await file.rename(moved.path);
      // The previous version belongs to the same key and is useless without it.
      final prev = File('${file.path}$prevSuffix');
      if (await prev.exists()) await prev.rename('${moved.path}$prevSuffix');
      debugPrint('Ablage: $path ohne Schlüssel beiseitegelegt');
    }
  }
}
