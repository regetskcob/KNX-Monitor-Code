import 'dart:typed_data';

import 'package:knx/knx.dart';

/// Numeric value of a group telegram (`dptNumericValue` of package:knx, the same the app's charts use)
/// with the datapoint type as (main type, subtype), the way the server keeps it. [data] the payload,
/// [small] a value in the 6 bits of the APCI (1 bit, dimming …). `null` if it is not a number.
double? numericValue((int, int?)? dpt, List<int> data, {required bool small}) =>
    dptNumericValue(dpt == null ? null : Dpt(dpt.$1, dpt.$2), data, small: small);

/// Bytes from the history's hex representation (`x`).
Uint8List hexBytes(String s) =>
    Uint8List.fromList([for (var i = 0; i + 1 < s.length; i += 2) int.tryParse(s.substring(i, i + 2), radix: 16) ?? 0]);
