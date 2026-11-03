import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/theme/palette.dart';

/// Die Gerätegrafiken der Webseite tragen dieselben Farben wie die App.
void main() {
  test('teaser.css und Palette nennen dieselben Gerätefarben', () {
    final css = File('teaser/assets/css/teaser.css').readAsStringSync().toUpperCase();
    String hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    for (final (selector, color) in [
      ('.DV-HOUSING { FILL: ', Palette.deviceHousing),
      ('.DV-STEP { FILL: ', Palette.deviceStep),
      ('.DV-FRONT { FILL: ', Palette.deviceFront),
      ('.DV-SLOT { FILL: ', Palette.deviceSlot),
      ('.DV-SCREW { FILL: ', Palette.deviceScrew),
      ('.DV-LED { FILL: ', Palette.deviceLedOff),
    ]) {
      expect(css, contains('$selector${hex(color)}'), reason: selector);
    }
    expect(css, contains('--BH-NIGHT: ${hex(Palette.sceneNightLight)}'));
    expect(css, contains('--BH-GLOW: ${hex(Palette.sceneGlow)}'));
  });
}
