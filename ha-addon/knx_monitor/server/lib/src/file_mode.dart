/// File modes for the data folder outside Home Assistant.
///
/// In Docker the data folder is a bind mount on the host (`./data:/data`). The
/// container runs as root with umask 022, so the keyring (`secure_keys.json`),
/// IP Secure passwords (`server.json`) and the box access (`access.json`) would
/// land on the host readable for every account. The image is built `FROM
/// scratch` without a `chmod` binary, hence libc through FFI.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

typedef _UmaskC = Uint32 Function(Uint32);
typedef _UmaskDart = int Function(int);
typedef _ChmodC = Int32 Function(Pointer<Uint8>, Uint32);
typedef _ChmodDart = int Function(Pointer<Uint8>, int);
typedef _MallocC = Pointer<Uint8> Function(IntPtr);
typedef _MallocDart = Pointer<Uint8> Function(int);
typedef _FreeC = Void Function(Pointer<Uint8>);
typedef _FreeDart = void Function(Pointer<Uint8>);

/// New files only for the server's own user (umask 077), and [data] itself
/// 0700, which also closes the files written before with 0644. Linux only;
/// errors are logged, the server keeps running.
void restrictDataFolder(Directory data) {
  if (!Platform.isLinux) return;
  try {
    final libc = DynamicLibrary.process();
    libc.lookupFunction<_UmaskC, _UmaskDart>('umask')(0x3F); // 077
    final malloc = libc.lookupFunction<_MallocC, _MallocDart>('malloc');
    final free = libc.lookupFunction<_FreeC, _FreeDart>('free');
    final chmod = libc.lookupFunction<_ChmodC, _ChmodDart>('chmod');
    final path = utf8.encode(data.absolute.path);
    final native = malloc(path.length + 1);
    try {
      native.asTypedList(path.length + 1)
        ..setAll(0, path)
        ..[path.length] = 0;
      if (chmod(native, 0x1C0) != 0) stderr.writeln('chmod ${data.path} fehlgeschlagen'); // 0700
    } finally {
      free(native);
    }
  } on Object catch (e) {
    stderr.writeln('Dateirechte: $e');
  }
}
