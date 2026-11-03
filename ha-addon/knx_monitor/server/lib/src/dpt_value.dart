import 'dart:typed_data';

/// Numeric value of a group telegram, like the app's `numericValue`: [dpt] as
/// (main type, subtype), [data] the payload, [small] a value in the 6 bits of
/// the APCI (1 bit, dimming …). Without a type it guesses: short values as a
/// number, 1 byte as 0…255, 2 bytes as DPT 9. `null` if it is not a number.
double? numericValue((int, int?)? dpt, Uint8List data, {required bool small}) {
  if (data.isEmpty) return null;
  if (small) return dpt == null || dpt.$1 <= 2 ? data[0].toDouble() : null;
  final bd = ByteData.sublistView(data);
  return switch ((dpt?.$1, data.length)) {
    (5, 1) when dpt!.$2 == 1 => data[0] * 100 / 255,
    (5 || 6 || null, 1) => dpt?.$1 == 6 ? bd.getInt8(0).toDouble() : data[0].toDouble(),
    (7, 2) => bd.getUint16(0).toDouble(),
    (8, 2) => bd.getInt16(0).toDouble(),
    (9 || null, 2) => _dpt9(data),
    (12, 4) => bd.getUint32(0).toDouble(),
    (13, 4) => bd.getInt32(0).toDouble(),
    (14, 4) => bd.getFloat32(0),
    _ => null,
  };
}

double _dpt9(List<int> b) {
  var mantissa = ((b[0] & 0x07) << 8) | b[1];
  if (b[0] & 0x80 != 0) mantissa -= 2048;
  final exponent = (b[0] >> 3) & 0x0F;
  return 0.01 * mantissa * (1 << exponent);
}

/// Bytes from the history's hex representation (`x`).
Uint8List hexBytes(String s) =>
    Uint8List.fromList([for (var i = 0; i + 1 < s.length; i += 2) int.tryParse(s.substring(i, i + 2), radix: 16) ?? 0]);
