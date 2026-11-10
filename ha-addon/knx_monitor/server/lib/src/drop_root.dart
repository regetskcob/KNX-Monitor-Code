/// Docker without root: with `PUID`/`PGID` the server hands the data folder to
/// that user and then gives up root for good (`setgroups`, `setgid`, `setuid`).
///
/// The image is built `FROM scratch` (no `su`, `chown` or `gosu`), hence libc
/// through FFI, as in `file_mode.dart`. Without `PUID` nothing changes: data
/// folders of existing installations belong to root, and the add-on (Home
/// Assistant) and the box set their users themselves.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

typedef _IdC = Uint32 Function();
typedef _IdDart = int Function();
typedef _SetIdC = Int32 Function(Uint32);
typedef _SetIdDart = int Function(int);
typedef _SetGroupsC = Int32 Function(IntPtr, Pointer<Uint32>);
typedef _SetGroupsDart = int Function(int, Pointer<Uint32>);
typedef _ChownC = Int32 Function(Pointer<Uint8>, Uint32, Uint32);
typedef _ChownDart = int Function(Pointer<Uint8>, int, int);
typedef _MallocC = Pointer<Uint8> Function(IntPtr);
typedef _MallocDart = Pointer<Uint8> Function(int);
typedef _FreeC = Void Function(Pointer<Uint8>);
typedef _FreeDart = void Function(Pointer<Uint8>);

/// Thrown when `PUID`/`PGID` are set but the server cannot become that user.
/// The server then refuses to start rather than quietly keep running as root.
class DropRootException implements Exception {
  DropRootException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// User and group from `PUID`/`PGID`, or `null` without `PUID`. `PGID`
/// defaults to `PUID`. Root (0) and values outside 1–65534 are refused.
({int uid, int gid})? requestedUser(Map<String, String> env) {
  final rawUid = env['PUID']?.trim() ?? '';
  if (rawUid.isEmpty) return null;
  final rawGid = env['PGID']?.trim() ?? '';
  final uid = int.tryParse(rawUid);
  final gid = rawGid.isEmpty ? uid : int.tryParse(rawGid);
  bool ok(int? v) => v != null && v >= 1 && v <= 65534;
  if (!ok(uid) || !ok(gid)) {
    throw DropRootException('PUID/PGID: eine Zahl von 1 bis 65534 erwartet (PUID=$rawUid, PGID=$rawGid).');
  }
  return (uid: uid!, gid: gid!);
}

/// Paths [dropRoot] hands over: [data] with everything below it, plus the
/// mount point above it (`/data` for `DATA_DIR=/data/app`) without its other
/// contents. Symbolic links are not followed.
Iterable<String> handOverPaths(Directory data) sync* {
  final parent = data.absolute.parent.path;
  if (parent != '/' && parent != data.absolute.path) yield parent;
  yield data.absolute.path;
  if (!data.existsSync()) return;
  for (final e in data.listSync(recursive: true, followLinks: false)) {
    yield e.path;
  }
}

/// With `PUID` set and running as root on Linux: hands the data folder to
/// that user and switches to it. Returns the new user, or `null` if nothing
/// was asked for. Throws [DropRootException] if the switch does not take
/// (the container lacks `SETUID`/`SETGID`) or the data folder is not writable
/// for the new user afterwards (no `CHOWN`, or a file system that refuses it).
({int uid, int gid})? dropRoot(Map<String, String> env, Directory data) {
  final want = requestedUser(env);
  if (want == null || !Platform.isLinux) return null;
  final libc = DynamicLibrary.process();
  final getuid = libc.lookupFunction<_IdC, _IdDart>('getuid');
  final getgid = libc.lookupFunction<_IdC, _IdDart>('getgid');
  final current = getuid();
  if (current == want.uid) return want;
  if (current != 0) {
    throw DropRootException('PUID=${want.uid} verlangt, der Server läuft aber schon als uid $current.');
  }
  final malloc = libc.lookupFunction<_MallocC, _MallocDart>('malloc');
  final free = libc.lookupFunction<_FreeC, _FreeDart>('free');
  final lchown = libc.lookupFunction<_ChownC, _ChownDart>('lchown');
  var failed = 0;
  String? firstFailure;
  for (final path in handOverPaths(data)) {
    final bytes = utf8.encode(path);
    final native = malloc(bytes.length + 1);
    try {
      native.asTypedList(bytes.length + 1)
        ..setAll(0, bytes)
        ..[bytes.length] = 0;
      if (lchown(native, want.uid, want.gid) != 0) {
        failed++;
        firstFailure ??= path;
      }
    } finally {
      free(native);
    }
  }
  // Some file systems refuse chown even to root (Docker Desktop shares, NFS
  // with root_squash, CIFS). That alone is no reason to stay root: what
  // counts is whether the folder is writable afterwards (checked below).
  if (failed > 0) {
    stderr.writeln(
      'Busclear: $failed Einträge im Datenordner nicht an ${want.uid}:${want.gid} übergeben '
      '(z. B. $firstFailure). Ohne cap_add CHOWN oder auf diesem Dateisystem nicht möglich.',
    );
  }
  final setgroups = libc.lookupFunction<_SetGroupsC, _SetGroupsDart>('setgroups');
  final setgid = libc.lookupFunction<_SetIdC, _SetIdDart>('setgid');
  final setuid = libc.lookupFunction<_SetIdC, _SetIdDart>('setuid');
  // Order matters: groups and gid while still root, the uid last.
  if (setgroups(0, nullptr) != 0 || setgid(want.gid) != 0 || setuid(want.uid) != 0) {
    throw DropRootException(
      'Benutzerwechsel auf ${want.uid}:${want.gid} abgelehnt. Braucht cap_add SETUID und SETGID.',
    );
  }
  // setuid(0) must fail now: root is gone for good, not just for the moment.
  if (getuid() != want.uid || getgid() != want.gid || setuid(0) == 0) {
    throw DropRootException('Benutzerwechsel auf ${want.uid}:${want.gid} nicht vollständig.');
  }
  final probe = File('${data.path}/.write-test');
  try {
    probe.writeAsStringSync('ok', flush: true);
    probe.deleteSync();
  } on FileSystemException catch (e) {
    throw DropRootException(
      'Datenordner ${data.path} für ${want.uid}:${want.gid} nicht beschreibbar (${e.osError?.message ?? e.message}). '
      'PUID/PGID passend zum Besitzer von ./data setzen oder cap_add CHOWN ergänzen.',
    );
  }
  return want;
}
