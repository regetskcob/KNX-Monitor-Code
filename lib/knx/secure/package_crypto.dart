import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as fast;
import 'package:cryptography/dart.dart' as fast;
import 'package:pointycastle/export.dart';

/// Encryption of the handover package: AES-256-GCM (authenticated), key derived from the password
/// via PBKDF2-HMAC-SHA256. Everything from pointycastle, which also computes KNX Secure; verified
/// against the test vectors from NIST SP 800-38D and RFC 7914 (`test/handover_test.dart`).
const packageKdfIterations = 210000;

/// Opening rejects more rounds: a foreign file should not keep the device busy for arbitrarily
/// long.
const packageKdfMaxIterations = 5000000;

const _keyBytes = 32;

/// Characters that cannot be confused (no 0/O, 1/I/L, 5/S, 2/Z).
const _alphabet = '3467ABCDEFGHJKMNPQRTUVWXY89';

/// Wrong password or modified file – indistinguishable with GCM.
class PackageDecryptException implements Exception {
  const PackageDecryptException();
}

/// New random password, e.g. `ABCD-EFGH-…`: 24 characters, a good 110 bits. For typing and as a QR
/// code; people do not choose it themselves so it stays strong enough.
String generatePackagePassword({Random? random}) {
  final r = random ?? Random.secure();
  final chars = List.generate(24, (_) => _alphabet[r.nextInt(_alphabet.length)]);
  return [for (var i = 0; i < 24; i += 4) chars.sublist(i, i + 4).join()].join('-');
}

/// Before derivation: case and separators do not matter.
String normalizePackagePassword(String password) => password.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');

/// Random bytes from the system.
Uint8List randomBytes(int count, {Random? random}) {
  final r = random ?? Random.secure();
  return Uint8List.fromList(List.generate(count, (_) => r.nextInt(256)));
}

/// PBKDF2-HMAC-SHA256.
Uint8List pbkdf2(List<int> password, List<int> salt, int iterations, int length) {
  final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(Uint8List.fromList(salt), iterations, length));
  return kdf.process(Uint8List.fromList(password));
}

/// AES-256-GCM; [aad] is authenticated as well.
Uint8List aesGcm({
  required bool encrypt,
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List aad,
  required Uint8List data,
}) {
  if (_isWeb) {
    final cipher = GCMBlockCipher(AESEngine())..init(encrypt, AEADParameters(KeyParameter(key), 128, nonce, aad));
    return cipher.process(data);
  }
  // The same format as before (tag at the end), but about ten times as fast; cross-checked in
  // test/file_cipher_format_test.dart.
  final gcm = fast.DartAesGcm(secretKeyLength: key.length, nonceLength: nonce.length);
  final secret = fast.SecretKeyData(key);
  if (encrypt) {
    final box = gcm.encryptSync(data, secretKeyData: secret, nonce: nonce, aad: aad);
    final sealed = Uint8List(box.cipherText.length + box.mac.bytes.length);
    sealed.setAll(0, box.cipherText);
    sealed.setAll(box.cipherText.length, box.mac.bytes);
    return sealed;
  }
  if (data.length < _tagBytes) throw ArgumentError('Daten kürzer als der Tag');
  final end = data.length - _tagBytes;
  final open = gcm.decryptSync(
    fast.SecretBox(Uint8List.sublistView(data, 0, end), nonce: nonce, mac: fast.Mac(Uint8List.sublistView(data, end))),
    secretKeyData: secret,
    aad: aad,
  );
  return open is Uint8List ? open : Uint8List.fromList(open);
}

const _tagBytes = 16;

/// In the browser it stays with pointycastle: Dart handles integers differently there.
const _isWeb = bool.fromEnvironment('dart.library.js_interop');

/// Key from the password; separate so the browser can use Web Crypto.
Uint8List deriveKey(String password, Uint8List salt, int iterations) =>
    pbkdf2(normalizePackagePassword(password).codeUnits, salt, iterations, _keyBytes);

/// Inputs of [deriveKey] as bytes (for Web Crypto).
List<int> passwordBytes(String password) => normalizePackagePassword(password).codeUnits;

/// Decrypts; [cipher] carries the 16-byte tag at the end, [key] comes from [deriveKey]. Throws
/// [PackageDecryptException] for a wrong password or a modified file.
Uint8List unseal(Uint8List cipher, {required Uint8List key, required Uint8List nonce, required Uint8List aad}) {
  try {
    return aesGcm(encrypt: false, key: key, nonce: nonce, aad: aad, data: cipher);
  } on Object {
    throw const PackageDecryptException();
  }
}
