import 'package:flutter/foundation.dart';

import 'storage_io.dart' if (dart.library.js_interop) 'storage_web.dart' as impl;

/// Encrypt existing files in the background (native).
Future<void> encryptExistingFiles() => impl.encryptExistingFiles();

/// All app files for the backup (native).
Future<List<String>> allStoredPaths() => impl.allStoredPaths();

/// What lies next to the actual data: previous and damaged versions, and files whose key is
/// missing.
Future<StorageExtras> storageExtras() => impl.storageExtras();

/// Permanently delete the files without a key.
Future<void> deleteQuarantinedFiles() => impl.deleteQuarantinedFiles();

/// Deletes the copies of [path] a store moved aside as unreadable (`.corrupt-…`), e.g. when an
/// installation is deleted. Natively only; in the browser the server keeps the files.
Future<void> deleteCorruptCopies(AppStorage storage, String path) => impl.deleteCorruptCopies(storage, path);

typedef StorageExtras = ({int previousBytes, int corruptBytes, int quarantinedFiles, int quarantinedBytes});

const StorageExtras noStorageExtras = (previousBytes: 0, corruptBytes: 0, quarantinedFiles: 0, quarantinedBytes: 0);

/// A stored file.
typedef StoredFile = ({String name, int size});

/// File storage of the app (catalog, recordings, long-term history).
///
/// Natively the app directory; in the browser (Home Assistant add-on) the add-on's data folder via
/// its HTTP interface. Paths are relative, e.g. "recordings/abc.json".
abstract class AppStorage {
  static AppStorage instance = impl.createStorage();

  Future<String?> read(String path);
  Future<void> write(String path, String text);
  Future<void> append(String path, String text);

  /// Files in [dir] (not recursive).
  Future<List<StoredFile>> list(String dir);
  Future<void> delete(String path);
}

/// Returns [path] if it stays inside the storage folder; throws [ArgumentError] otherwise.
///
/// Paths are relative with "/" as separator. Refused: absolute paths, drive letters, backslashes
/// (a separator on Windows), NUL and any ".." segment. Every backend checks this before joining, so
/// a foreign name (installation id from a box, file name from a backup) can never reach files
/// outside the app's data folder.
String confinedPath(String path) {
  if (path.startsWith('/') ||
      path.contains(r'\') ||
      path.contains('\u0000') ||
      RegExp(r'^[A-Za-z]:').hasMatch(path) ||
      path.split('/').contains('..')) {
    throw ArgumentError.value(path, 'path', 'leaves the storage folder');
  }
  return path;
}

/// Storage in a subfolder of [base], e.g. "installations/abc/" – each installation has its own
/// files under the same relative paths.
class ScopedStorage implements AppStorage {
  ScopedStorage(this.base, this.prefix);

  final AppStorage base;

  /// With a trailing "/".
  final String prefix;

  /// Checked here as well: [base] may be a backend that does not check itself.
  String _join(String path) => confinedPath('$prefix$path');

  @override
  Future<String?> read(String path) => Future.sync(() => base.read(_join(path)));

  @override
  Future<void> write(String path, String text) => Future.sync(() => base.write(_join(path), text));

  @override
  Future<void> append(String path, String text) => Future.sync(() => base.append(_join(path), text));

  @override
  Future<List<StoredFile>> list(String dir) => Future.sync(() => base.list(_join(dir)));

  @override
  Future<void> delete(String path) => Future.sync(() => base.delete(_join(path)));
}

/// Moves readable but unintelligible content of [path] aside before the store continues with an
/// empty state and replaces it on the next save.
Future<void> keepCorrupt(AppStorage storage, String path, String text) async {
  try {
    await storage.write('$path.corrupt-${DateTime.now().millisecondsSinceEpoch}', text);
  } on Object catch (e) {
    debugPrint('$path nicht beiseitegelegt: $e');
  }
}

/// Reads and parses a store's file. `null` if it does not exist or is not readable; the store then
/// continues empty without losing data: unintelligible content then lies next to it as
/// `.corrupt-…`, and a file that could not be read at all is protected by the storage itself (see
/// `IoStorage.write`).
Future<T?> readStored<T>(AppStorage storage, String path, T Function(String text) parse) async {
  String? text;
  try {
    text = await storage.read(path);
    return text == null ? null : parse(text);
  } on Object catch (e) {
    debugPrint('$path nicht lesbar: $e');
    if (text != null) await keepCorrupt(storage, path, text);
    return null;
  }
}
