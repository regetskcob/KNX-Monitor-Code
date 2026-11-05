import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx/secure.dart';
import 'package:knx_monitor/knx/secure/keyring.dart';
import 'package:knx_monitor/knx/secure/keyring_store.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';

/// Keyring-Dateien und Beispiele aus den Tests von xknx (MIT). Data Secure selbst testet
/// packages/knx (test/data_secure_test.dart); hier geht es um den Keyring der App.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test('Schlüssel aus dem Keyring entschlüsseln, auch über secure_keys.json beim Add-on-Server', () {
    final cemi = fromHex('29003ce0400904001103f110002446cfef4ac085e7092ab062b44d');
    final direct = DataSecure(groupKeys: secureTest.groupKeys, sequenceNumbers: secureTest.sequenceNumbers);
    final (result, plain) = direct.receive(cemi);
    expect(result, SecureResult.decrypted);
    expect(Telegram.fromCemi(plain)!.data, [116, 41, 41]);

    // Die App schreibt Keyring.toJson als secure_keys.json, der Server liest es mit DataSecure.fromJson.
    final json = jsonDecode(jsonEncode(secureTest.toJson())) as Map<String, Object?>;
    final (serverResult, serverPlain) = DataSecure.fromJson(json).receive(cemi);
    expect(serverResult, SecureResult.decrypted);
    expect(serverPlain, plain);
  });

  test('Zähler überstehen einen Neustart: ein mitgeschnittenes Telegramm gilt danach nicht wieder', () async {
    final dir = await Directory.systemTemp.createTemp('data_secure_seq');
    addTearDown(() => dir.delete(recursive: true));
    AppStorage.instance = IoStorage(dir);
    InstallationStore.instance.debugReset();
    final id = InstallationStore.instance.active.id;
    FlutterSecureStorage.setMockInitialValues({'knx_keyring:$id': jsonEncode(secureTest.toJson())});
    final store = KeyringStore.instance;
    final cemi = fromHex('29003ce0400904001103f110002446cfef4ac085e7092ab062b44d');

    await store.reload();
    expect(store.dataSecure!.receive(cemi).$1, SecureResult.decrypted);
    expect(store.dataSecure!.receive(cemi).$1, SecureResult.invalid, reason: 'Wiederholung im selben Lauf');
    await store.flushSequences();
    final stored = await AppStorage.instance.read('installations/$id/${KeyringStore.sequencePath}');
    expect(stored, contains('${0x4009}'));

    await store.reload(); // wie ein Neustart
    expect(store.dataSecure!.receive(cemi).$1, SecureResult.invalid, reason: 'älteres Telegramm nach dem Neustart');

    await store.clear();
    expect(await AppStorage.instance.read('installations/$id/${KeyringStore.sequencePath}'), isNull);
  });
}
