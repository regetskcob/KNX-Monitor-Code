import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/secure/secure_tap_cache.dart';

void main() {
  test('gesichertes Telegramm am zweiten Messpunkt: Entschlüsselung des ersten, nur kurz', () {
    var now = DateTime(2026, 11, 9, 12);
    final cache = SecureTapCache(now: () => now);
    List<int> frame(int ctrl2) => [
      0x29,
      0x00,
      0xBC,
      ctrl2,
      0x11,
      0x05,
      0x09,
      0x01,
      0x05,
      0x03,
      0xF1,
      0xAA,
      0xBB,
      0xCC,
      0xDD,
    ];
    cache.remember(frame(0xE0), Uint8List.fromList([0x29, 0x00, 0xBC, 0xE0, 0x11, 0x05, 0x09, 0x01, 0x01, 0x00, 0x81]));
    expect(cache.seen(frame(0xD0)), [0x29, 0x00, 0xBC, 0xD0, 0x11, 0x05, 0x09, 0x01, 0x01, 0x00, 0x81]);
    expect(cache.seen(frame(0xD0)..[14] = 0x00), isNull);
    now = now.add(const Duration(seconds: 4));
    expect(cache.seen(frame(0xD0)), isNull);
  });
}
