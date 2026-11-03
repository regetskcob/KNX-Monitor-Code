import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/theme/palette.dart';

// Die PDF-Farben sind Kopien der Palette – dieser Test hält sie synchron.
void main() {
  test('PDF-Farben entsprechen der App-Palette', () {
    final pdf = RegExp(r'PdfColor\.fromInt\(0x([0-9A-F]{8})\); // Palette\.(\w+)')
        .allMatches(File('lib/export/pdf_export.dart').readAsStringSync());
    final palette = {'ink': Palette.ink, 'muted': Palette.muted, 'line': Palette.line, 'zebra': Palette.zebra};
    expect(pdf.length, palette.length);
    for (final m in pdf) {
      expect(int.parse(m[1]!, radix: 16), palette[m[2]]!.toARGB32(), reason: 'Palette.${m[2]}');
    }
  });
}
