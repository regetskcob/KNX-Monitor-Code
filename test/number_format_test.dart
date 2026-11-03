import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/dpt_codec.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';

Telegram _float32(double v) {
  final data = (ByteData(4)..setFloat32(0, v)).buffer.asUint8List();
  return Telegram(
    time: DateTime(2026),
    source: 0x1101,
    destination: 0x0801,
    type: TelegramType.write,
    isSmall: false,
    data: Uint8List.fromList(data),
  );
}

void main() {
  final controller = LocaleController.instance;
  tearDown(() => controller.debugSetLocale(const Locale('de')));

  test('Tausendertrennzeichen je Sprache', () {
    controller.debugSetLocale(const Locale('de'));
    expect(localizeDecimal('14612.48'), '14.612,48');
    expect(localizeDecimal('-1234567'), '-1.234.567');
    expect(localizeDecimal('999.5'), '999,5');
    expect(formatInt(1524), '1.524');
    controller.debugSetLocale(const Locale('en'));
    expect(localizeDecimal('14612.48'), '14,612.48');
    expect(formatInt(1524), '1,524');
  });

  test('Leistung und Energie ab 1000 eine Stufe höher', () {
    controller.debugSetLocale(const Locale('de'));
    expect(decodeDpt(const Dpt(14, 56), _float32(1250)), '1,25 kW');
    expect(decodeDpt(const Dpt(14, 56), _float32(980)), '980 W');
    expect(formatWithUnit(15300, ' Wh'), '15,3 kWh');
    expect(formatWithUnit(15300, ' kWh'), '15.300 kWh');
  });
}
