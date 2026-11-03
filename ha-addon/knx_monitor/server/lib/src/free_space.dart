import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// Free space in bytes (for normal processes, like `df`) in the file system of
/// [path]; `null` if it cannot be determined.
///
/// Directly via `statvfs`: the add-on image is `FROM scratch` and has no `df`.
Future<int?> freeBytes(String path) async {
  try {
    if (Platform.isLinux || Platform.isMacOS) return _statvfs(path);
  } on Object catch (e) {
    stderr.writeln('Freier Platz: $e');
  }
  return null;
}

typedef _StatvfsNative = Int32 Function(Pointer<Uint8> path, Pointer<Uint8> buffer);
typedef _StatvfsDart = int Function(Pointer<Uint8> path, Pointer<Uint8> buffer);

int? _statvfs(String path) {
  final libc = DynamicLibrary.process();
  final malloc = libc.lookupFunction<Pointer<Uint8> Function(IntPtr), Pointer<Uint8> Function(int)>('malloc');
  final free = libc.lookupFunction<Void Function(Pointer<Uint8>), void Function(Pointer<Uint8>)>('free');
  final statvfs = libc.lookupFunction<_StatvfsNative, _StatvfsDart>('statvfs');
  final name = utf8.encode(path);
  final cPath = malloc(name.length + 1);
  // Larger than any `struct statvfs`.
  final buffer = malloc(512);
  try {
    cPath.asTypedList(name.length + 1)
      ..setAll(0, name)
      ..[name.length] = 0;
    if (statvfs(cPath, buffer) != 0) return null;
    return statvfsFree(ByteData.sublistView(buffer.asTypedList(512)), macOS: Platform.isMacOS);
  } finally {
    free(cPath);
    free(buffer);
  }
}

/// Reads `f_frsize × f_bavail`. 64-bit Linux (amd64, arm64): everything is
/// `unsigned long` from byte 0 (bsize, frsize, blocks, bfree, bavail). macOS:
/// block counters are only 32 bits, directly after frsize.
int statvfsFree(ByteData buffer, {required bool macOS}) {
  final frsize = buffer.getUint64(8, Endian.host);
  final available = macOS ? buffer.getUint32(24, Endian.host) : buffer.getUint64(32, Endian.host);
  return frsize * available;
}
