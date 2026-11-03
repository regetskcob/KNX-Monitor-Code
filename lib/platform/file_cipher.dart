import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../knx/secure/package_crypto.dart' show aesGcm;

/// Header line of encrypted files. After it, one Base64 line of nonce and AES-256-GCM per write, so
/// appending works without rewriting and a truncated last entry does not take the others with it.
const encryptedHeader = 'KNXENC1\n';

/// The file belongs to a key that is currently unavailable. Never replaced by empty data.
class StorageLockedException implements Exception {
  const StorageLockedException(this.path);
  final String path;
  @override
  String toString() => 'Datei ohne Schlüssel nicht lesbar: $path';
}

/// The content could not be decrypted with the available key.
class StorageCorruptException implements Exception {
  const StorageCorruptException(this.path);
  final String path;
  @override
  String toString() => 'Verschlüsselte Datei beschädigt: $path';
}

bool isEncrypted(String content) => content.startsWith(encryptedHeader);

final _noAad = Uint8List(0);

/// One line for [text]; [nonce] only for tests.
String encryptRecord(Uint8List key, String text, {Uint8List? nonce}) {
  final r = Random.secure();
  final iv = nonce ?? Uint8List.fromList(List.generate(12, (_) => r.nextInt(256)));
  final sealed = aesGcm(encrypt: true, key: key, nonce: iv, aad: _noAad, data: utf8.encode(text));
  final bytes = Uint8List(iv.length + sealed.length)
    ..setAll(0, iv)
    ..setAll(iv.length, sealed);
  return '${base64Encode(bytes)}\n';
}

String? _decryptRecord(Uint8List key, String line) {
  try {
    final bytes = base64Decode(line);
    if (bytes.length < 12 + 16) return null;
    final plain = aesGcm(
      encrypt: false,
      key: key,
      nonce: Uint8List.sublistView(bytes, 0, 12),
      aad: _noAad,
      data: Uint8List.sublistView(bytes, 12),
    );
    return utf8.decode(plain);
  } on Object {
    return null;
  }
}

/// Whole file. `null` if not a single entry was readable although there are some; individual broken
/// entries (truncated append) are dropped.
String? decryptFile(Uint8List key, String content) {
  final out = StringBuffer();
  var total = 0;
  var good = 0;
  for (final line in const LineSplitter().convert(content.substring(encryptedHeader.length))) {
    if (line.isEmpty) continue;
    total++;
    final text = _decryptRecord(key, line);
    if (text == null) continue;
    good++;
    out.write(text);
  }
  return total > 0 && good == 0 ? null : out.toString();
}

/// For the background isolate: encryption never runs on the UI thread.
String? decryptFileJob(({Uint8List key, String content}) a) => decryptFile(a.key, a.content);
String encryptFileJob(({Uint8List key, String text}) a) => '$encryptedHeader${encryptRecord(a.key, a.text)}';
String encryptRecordJob(({Uint8List key, String text}) a) => encryptRecord(a.key, a.text);

/// UTF-8 of large files; `null` if the bytes are not valid UTF-8.
String? decodeTextJob(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}
