import 'dart:convert';
import 'dart:typed_data';

import 'package:knx_monitor_server/src/secure/data_secure.dart';
import 'package:knx_monitor_server/src/secure/ip_secure.dart';
import 'package:knx_monitor_server/src/secure/knx_crypto.dart';
import 'package:knx_monitor_server/src/telegram_json.dart';
import 'package:test/test.dart';

/// Die Kopie der Secure-Bausteine im Server gegen dieselben Beispiele wie die
/// App (KNX AN159, xknx).
void main() {
  test('IP-Secure-Handshake (AN159)', () async {
    final session = IpSecureSession(
      userId: 1,
      userPassword: 'secret',
      deviceAuthentication: 'trustme',
      serialNumber: fromHex('00 fa 12 34 56 78'),
      messageTag: fromHex('af fe'),
      keyPair: (
        fromHex('b8 fa bd 62 66 5d 8b 9e 8a 9d 8b 1f 4b ca 42 c8 c2 78 9a 61 10 f5 0e 9d d7 85 b3 ed e8 83 f3 78'),
        fromHex('0a a2 27 b4 fd 7a 32 31 9b a9 96 0a c0 36 ce 0e 5c 45 07 b5 ae 55 16 1f 10 78 b1 dc fb 3c b6 31'),
      ),
    );
    final sent = <List<int>>[];
    final done = session.handshake(sent.add);
    await Future<void>.delayed(Duration.zero);
    session.handle(
      Uint8List.fromList([
        ...fromHex('06 10 09 52 00 38 00 01'),
        ...fromHex('bd f0 99 90 99 23 14 3e f0 a5 de 0b 3b e3 68 7b c5 bd 3c f5 f9 e6 f9 01 69 9c d8 70 ec 1f f8 24'),
        ...fromHex('a9 22 50 5a aa 43 61 63 57 0b d5 49 4c 2d f2 a3'),
      ]),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      sent.last,
      fromHex(
        '06 10 09 50 00 3e 00 01 00 00 00 00 00 00 00 fa 12 34 56 78 af fe'
        '79 15 a4 f3 6e 6e 42 08 d2 8b 4a 20 7d 8f 35 c0 d1 38 c2 6a 7b 5e 71 69'
        '52 db a8 e7 e4 bd 80 bd 7d 86 8a 3a e7 87 49 de',
      ),
    );
    session.handle(
      fromHex(
        '06 10 09 50 00 2e 00 01 00 00 00 00 00 00 00 fa aa aa aa aa af fe'
        '26 15 6d b5 c7 49 88 8f a3 73 c3 e0 b4 bd e4 49 7c 39 5e 4b 1c 2f 46 a1',
      ),
    );
    await done;
    expect(session.established, isTrue);
  });

  test('Data Secure: Aufzeichnung entschlüsselt (Schlüssel wie aus secure_keys.json)', () {
    final ds = DataSecure.fromJson({
      'groupKeys': {'1024': base64.encode(fromHex('dfdf23a59fbb40404091d1c162087e8b'))},
      'sequence': {'${0x4009}': 155806854915},
    });
    final (_, plain) = ds.receive(fromHex('29003ce0400904001103f110002446cfef4ac085e7092ab062b44d'));
    final line = telegramJson(plain, DateTime(2026))!;
    expect(line['y'], 1); // Antwort
    expect(line['x'], '742929');
  });
}
