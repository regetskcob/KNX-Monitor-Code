import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/secure/package_crypto.dart';
import 'package:knx_monitor/platform/file_cipher.dart';
import 'package:pointycastle/export.dart';

/// Vergleich der AES-GCM-Umsetzungen. Von Hand laufen lassen, `skip` dafür
/// kurz entfernen: Die Testumgebung ist JIT; im Release-Build (AOT) sind beide
/// schneller, das Verhältnis bleibt.
void main() {
  test('AES-GCM: MB/s', () {
    final key = Uint8List(32);
    final nonce = Uint8List(12);
    final aad = Uint8List(0);
    double rate(int bytes, void Function() run) {
      final w = Stopwatch()..start();
      run();
      return bytes / 1048576 / (w.elapsedMicroseconds / 1e6);
    }

    final small = Uint8List(2 * 1024 * 1024);
    final big = Uint8List(16 * 1024 * 1024);
    final slow = rate(small.length, () {
      (GCMBlockCipher(AESEngine())..init(true, AEADParameters(KeyParameter(key), 128, nonce, aad))).process(small);
    });
    final fast = rate(big.length, () => aesGcm(encrypt: true, key: key, nonce: nonce, aad: aad, data: big));
    final line = List.filled(10, '{"t":1,"a":"1/2/3","v":"01"}\n').join();
    final lines = rate(utf8.encode(line).length * 2000, () {
      final sb = StringBuffer();
      for (var i = 0; i < 2000; i++) {
        sb.write(encryptRecord(key, line));
      }
      decryptFile(key, '$encryptedHeader$sb');
    });
    // ignore: avoid_print
    print(
      'pointycastle ${slow.toStringAsFixed(1)} MB/s, aesGcm ${fast.toStringAsFixed(1)} MB/s, '
      'Zeilen hin und zurück ${lines.toStringAsFixed(1)} MB/s',
    );
  }, skip: 'Messung, von Hand');
}
