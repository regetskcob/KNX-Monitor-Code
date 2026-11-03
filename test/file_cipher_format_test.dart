import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/secure/package_crypto.dart';
import 'package:knx_monitor/platform/crypto_worker.dart';
import 'package:knx_monitor/platform/file_cipher.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:pointycastle/export.dart';

/// Das Format auf der Platte darf sich nie ändern, und ein Release darf den
/// Entschlüsseler nie verlieren: Sonst sieht die App nach einem Update nur Müll
/// und legt eine leere Liste an. Siehe „Rolling back“ in der Release-Anleitung.
void main() {
  final key = Uint8List.fromList(List.generate(32, (i) => i));
  final nonce = Uint8List.fromList(List.generate(12, (i) => 200 + i));

  // Festgeschrieben: eine echte Datei, wie 1.9.1 sie mit pointycastle schrieb.
  const fixture = 'KNXENC1\nyMnKy8zNzs/Q0dLTUx0Sr+einwAVSWyeLyjSqqepQ2gwh++cItf3KWFQiA==\n';

  test('Datei aus 1.9.1 bleibt lesbar', () {
    expect(decryptFile(key, fixture), 'Bestand aus 1.9');
  });

  test('Format und Nonce unverändert', () {
    expect(encryptedHeader, 'KNXENC1\n');
    expect('$encryptedHeader${encryptRecord(key, 'Bestand aus 1.9', nonce: nonce)}', fixture);
  });

  test('schnelles AES-GCM und pointycastle lesen sich gegenseitig', () {
    final aad = Uint8List.fromList([1, 2, 3]);
    for (final size in [0, 1, 15, 16, 17, 4096, 100003]) {
      final data = Uint8List.fromList(List.generate(size, (i) => i * 7));
      final sealed = aesGcm(encrypt: true, key: key, nonce: nonce, aad: aad, data: data);
      expect(sealed.length, size + 16);
      final pc = GCMBlockCipher(AESEngine())..init(false, AEADParameters(KeyParameter(key), 128, nonce, aad));
      expect(pc.process(sealed), data);
      final other = GCMBlockCipher(AESEngine())..init(true, AEADParameters(KeyParameter(key), 128, nonce, aad));
      expect(aesGcm(encrypt: false, key: key, nonce: nonce, aad: aad, data: other.process(data)), data);
    }
  });

  test('veränderter Inhalt fliegt auf', () {
    final sealed = aesGcm(encrypt: true, key: key, nonce: nonce, aad: Uint8List(0), data: utf8.encode('x'));
    sealed[0] ^= 1;
    expect(() => aesGcm(encrypt: false, key: key, nonce: nonce, aad: Uint8List(0), data: sealed), throwsA(anything));
  });

  group('Worker', () {
    test('rechnet im eigenen Isolate und bleibt nach Fehlern nutzbar', () async {
      final worker = CryptoWorker();
      final text = await worker.run(encryptFileJob, (key: key, text: 'hallo'));
      expect(await worker.run(decryptFileJob, (key: key, content: text)), 'hallo');
      await expectLater(worker.run(_boom, 1), throwsA(isA<String>()));
      expect(await worker.run(_double, 21), 42);
      worker.stop();
      expect(await worker.run(_double, 2), 4, reason: 'startet nach dem Beenden neu');
      worker.stop();
    });

    test('hält die Reihenfolge', () async {
      final worker = CryptoWorker();
      final all = await Future.wait([for (var i = 0; i < 50; i++) worker.run(_double, i)]);
      expect(all, [for (var i = 0; i < 50; i++) i * 2]);
      worker.stop();
    });
  });

  test('IoStorage liest eine Datei aus 1.9.1', () async {
    final dir = await Directory.systemTemp.createTemp('format');
    addTearDown(() => dir.delete(recursive: true));
    await File('${dir.path}/a.json').writeAsString(fixture);
    expect(await IoStorage(dir, _Key(key)).read('a.json'), 'Bestand aus 1.9');
  });
}

int _double(int x) => x * 2;
int _boom(int _) => throw StateError('kaputt');

class _Key implements FileKeySource {
  _Key(this.key);
  final Uint8List key;
  @override
  Future<Uint8List?> load(Future<void> Function() onCreated) async => key;
}
