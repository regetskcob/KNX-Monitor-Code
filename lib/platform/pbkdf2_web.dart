import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<List<int>?> nativePbkdf2Sha256(List<int> password, List<int> salt, int iterations, int bytes) async {
  // crypto.subtle only exists in secure contexts (HTTPS, localhost).
  if (!web.window.isSecureContext) return null;
  try {
    final subtle = web.window.crypto.subtle;
    final key = await subtle
        .importKey('raw', Uint8List.fromList(password).toJS, 'PBKDF2'.toJS, false, ['deriveBits'.toJS].toJS)
        .toDart;
    final params = JSObject()
      ..setProperty('name'.toJS, 'PBKDF2'.toJS)
      ..setProperty('hash'.toJS, 'SHA-256'.toJS)
      ..setProperty('salt'.toJS, Uint8List.fromList(salt).toJS)
      ..setProperty('iterations'.toJS, iterations.toJS);
    final bits = await subtle.deriveBits(params, key, bytes * 8).toDart;
    return bits.toDart.asUint8List();
  } on Object {
    return null;
  }
}
