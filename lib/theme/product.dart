import 'package:flutter/widgets.dart';
import 'package:horizont/horizont.dart';

/// Busclear as a product on Horizont: the accent "Bus" and the glyph.
///
/// Since Horizont 0.16.0 these decisions live here, not in Horizont. The
/// values mirror `tool/horizont/horizont.product.json` (the form Horizont's
/// web layer and tools read); `test/product_test.dart` holds the two together and
/// checks the colours against Horizont's contrast rules. Change a colour in
/// both files.
const busclear = HorizontProduct(
  id: 'knx',
  displayName: 'Busclear',
  accentName: 'Bus',
  light: HzAccent(
    accent: Color(0xFF437F18),
    onAccent: Color(0xFFFFFFFF),
    accentTint: Color(0xFFE8F2DC),
    accentText: Color(0xFF3E7516),
  ),
  dark: HzAccent(
    accent: Color(0xFF9BD45E),
    onAccent: Color(0xFF12200A),
    accentTint: Color(0xFF1D2913),
    accentText: Color(0xFFA8DC6E),
  ),
  softLight: HzSoftColors(bg: Color(0xFFF6F8F2)),
  softDark: HzSoftColors(
    bg: Color(0xFF171A15),
    surface: Color(0xFF22261F),
    line: Color(0xFF343A2F),
    lineStrong: Color(0xFF6C7266),
    accentTint: Color(0xFF2A3622),
    accentText: Color(0xFFBCDC9F),
  ),
  mark: HorizontGlyph(_terminal),
);

// The bus terminal sitting in the bus cable. Drawn in a box of 100 by 100 with the
// horizon at 66.7; `HorizontMark` strokes it 7 wide with square caps. The
// source is `tool/horizont/mark/glyph.svg`.
Path _terminal() => Path()
  // The bus cable, interrupted by the terminal.
  ..moveTo(4, 66.7)
  ..lineTo(35, 66.7)
  ..moveTo(65, 66.7)
  ..lineTo(96, 66.7)
  // The terminal and the seam between its red and grey half.
  ..moveTo(35, 40)
  ..lineTo(65, 40)
  ..lineTo(65, 74)
  ..lineTo(35, 74)
  ..close()
  ..moveTo(50, 40)
  ..lineTo(50, 74);
