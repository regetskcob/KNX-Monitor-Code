import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/secure/data_secure.dart';
import 'package:knx_monitor/knx/secure/keyring.dart';
import 'package:knx_monitor/knx/secure/knx_crypto.dart';
import 'package:knx_monitor/knx/telegram.dart';

/// Keyring-Dateien und Beispiele aus den Tests von xknx (MIT).
void main() {
  late Keyring secureTest;
  setUpAll(() => secureTest = Keyring.parse(File('test/resources/SecureTest.knxkeys').readAsStringSync(), 'test'));

  test('Keyring: Tunnelpasswörter, Geräte-Code, Signatur', () {
    final k = Keyring.parse(File('test/resources/testcase.knxkeys').readAsStringSync(), 'password');
    expect(k.tunnels.map((t) => (t.address, t.password)), [
      (0x1001, 'user1'),
      (0x100B, 'user2'),
      (0x100C, 'user3'),
      (0x100D, 'user4'),
    ]);
    expect(k.tunnels.first.userId, 3);
    expect(k.deviceAuthentication[0x1000], 'authenticationcode');
    expect(k.backboneKey, fromHex('cf89fd0f18f4889783c7ef44ee1f5e14'));
    expect(
      () => Keyring.parse(File('test/resources/testcase.knxkeys').readAsStringSync(), 'falsch'),
      throwsA(isA<KeyringException>().having((e) => e.wrongPassword, 'wrongPassword', isTrue)),
    );
  });

  test('Keyring: Data-Secure-Schlüssel und Absender', () {
    expect(secureTest.groupKeys.keys, unorderedEquals([1024, 1027, 1028, 1029]));
    expect(secureTest.sequenceNumbers.keys, containsAll([0x4000, 0x4001, 0x4009, 0x5000, 0x5001]));
    expect(secureTest.tunnelFor(address: 0x5001)?.userId, 2);
  });

  test('entschlüsselt eine Gruppenantwort (A+C)', () {
    final ds = DataSecure(secureTest);
    final cemi = fromHex('29003ce0400904001103f110002446cfef4ac085e7092ab062b44d');
    final (result, plain) = ds.receive(cemi);
    expect(result, SecureResult.decrypted);
    final t = Telegram.fromCemi(plain)!;
    expect(t.type, TelegramType.response);
    expect(t.source, 0x4009);
    expect(t.destination, 0x0400);
    expect(t.data, [116, 41, 41]);
    // gleiche Sequenznummer noch einmal → verworfen
    expect(ds.receive(cemi).$1, SecureResult.invalid);
  });

  test('unbekannter Schlüssel und verfälschte MAC', () {
    final ds = DataSecure(secureTest);
    final noKey = fromHex('29003ce0400904011103f110002446cfef4ac085e7092ab062b44d');
    expect(ds.receive(noKey).$1, SecureResult.noKey);
    final tampered = fromHex('29003ce0400904001103f110002446cfef4ac085e7092ab062b44e');
    expect(ds.receive(tampered).$1, SecureResult.invalid);
  });

  test('verschlüsselt eigenes Lesen und Schreiben wie xknx', () {
    var ds = DataSecure(secureTest, sequenceStart: 160170101607);
    final read = buildGroupRequest(0x0400, TelegramType.read);
    expect(ds.send(read, source: 0x5001), fromHex('1100bce0500104000e03f11000254ae1cb67cd184afe5744'));

    ds = DataSecure(secureTest, sequenceStart: 160170101607);
    final write = buildGroupRequest(0x0400, TelegramType.write, data: [255, 0, 5]);
    final secured = ds.send(write, source: 0x5001);
    expect(secured, fromHex('11003ce0500104001103f11000254ae1cb67cd98e577b519be47bb'));

    // Und zurück: das eigene Telegramm lässt sich wieder entschlüsseln.
    final receiver = DataSecure(secureTest);
    final incoming = Uint8List.fromList(secured)..[0] = 0x29;
    final (result, plain) = receiver.receive(incoming);
    expect(result, SecureResult.decrypted);
    expect(Telegram.fromCemi(plain)!.data, [255, 0, 5]);
  });

  test('normale Telegramme bleiben unverändert', () {
    final ds = DataSecure(secureTest);
    final plain = fromHex('2900bce011050a03010081');
    expect(ds.receive(plain).$1, SecureResult.plain);
    final req = buildGroupRequest(0x0A03, TelegramType.write, small: 1);
    expect(ds.send(req, source: 0x5001), req);
  });
}
