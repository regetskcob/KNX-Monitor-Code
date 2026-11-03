import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/dpt_codec.dart';
import 'package:knx_monitor/knx/group_catalog.dart';

void main() {
  test('Text (16): auch leer, max. 14 Zeichen', () {
    expect(encodeForDpt(const Dpt(16, 0), '')!.data, List.filled(14, 0));
    expect(encodeForDpt(const Dpt(16, 0), 'Hallo')!.data.take(5), 'Hallo'.codeUnits);
    expect(encodeForDpt(const Dpt(16, 0), 'x' * 15), isNull);
  });

  test('Uhrzeit, Datum, Farbe, HVAC', () {
    expect(encodeForDpt(const Dpt(10, 1), '14:47')!.data, [14, 47, 0]);
    expect(encodeForDpt(const Dpt(10, 1), '25:00'), isNull);
    expect(encodeForDpt(const Dpt(11, 1), '31.12.2024')!.data, [31, 12, 24]);
    expect(encodeForDpt(const Dpt(11, 1), '2024-12-31')!.data, [31, 12, 24]);
    expect(encodeForDpt(const Dpt(232, 600), '#FF8000')!.data, [255, 128, 0]);
    expect(encodeForDpt(const Dpt(232, 600), '1, 2, 3')!.data, [1, 2, 3]);
    expect(encodeForDpt(const Dpt(20, 102), '3')!.data, [3]);
  });

  test('Ganzzahlen 8, 12, 13', () {
    expect(encodeForDpt(const Dpt(8, 1), '-2')!.data, [0xFF, 0xFE]);
    expect(encodeForDpt(const Dpt(12, 1), '65536')!.data, [0, 1, 0, 0]);
    expect(encodeForDpt(const Dpt(13, 1), '-1')!.data, [0xFF, 0xFF, 0xFF, 0xFF]);
    expect(canEncodeDpt(const Dpt(19, 1)), isFalse);
  });
}
