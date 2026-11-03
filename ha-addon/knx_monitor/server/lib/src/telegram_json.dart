import 'dart:typed_data';

import 'knxip.dart';

/// Group telegram from a cEMI frame as a JSON line – exactly in the format of
/// the app's `Telegram.toJson()`, so the app reads the history directly.
/// `null` for anything but group telegrams (L_Data.ind/.con, read/response/write).
Map<String, Object?>? telegramJson(Uint8List c, DateTime time) {
  if (c.length < 2) return null;
  final code = c[0];
  if (code != 0x29 && code != 0x2E) return null;
  final i = 2 + c[1];
  if (c.length < i + 9) return null;
  final ctrl1 = c[i];
  final ctrl2 = c[i + 1];
  if (ctrl2 & 0x80 == 0) return null;
  final npdu = c[i + 6];
  final apci = ((c[i + 7] & 0x03) << 8) | c[i + 8];
  final type = switch (apci & 0x3C0) {
    0x000 => 0, // TelegramType.read
    0x040 => 1, // response
    0x080 => 2, // write
    _ => null,
  };
  if (type == null) return null;
  final small = npdu <= 1;
  final data = small ? [c[i + 8] & 0x3F] : c.sublist(i + 9, (i + 8 + npdu).clamp(i + 9, c.length));
  final priority = (ctrl1 >> 2) & 0x03;
  final hop = (ctrl2 >> 4) & 0x07;
  return {
    't': time.microsecondsSinceEpoch,
    's': (c[i + 2] << 8) | c[i + 3],
    'd': (c[i + 4] << 8) | c[i + 5],
    'y': type,
    'x': hexOf(data),
    if (small) 'm': true,
    if (code == 0x2E) 'o': true,
    if (priority != 3) 'p': priority,
    if (code == 0x29 && ctrl1 & 0x20 == 0) 'rp': true,
    if (hop != 6) 'h': hop,
    if (code == 0x2E && ctrl1 & 0x01 != 0) 'ce': true,
    'r': hexOf(c),
  };
}
