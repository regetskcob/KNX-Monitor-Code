import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Horizont: no raw value outside `lib/theme/` (the check from Horizont's `docs/flutter.md`).
///
/// The code is not there yet: painters of device drawings and a few data styles still carry
/// their own sizes. So this is a ratchet: the count may only go down. Whoever removes raw
/// values lowers [_budget]; whoever needs a new one adds a token in `lib/theme/` instead.
const _budget = 32;

final _raw = RegExp(r'Colors\.(?!transparent)|Color\(0x|BorderRadius\.circular\(|fontSize:');

void main() {
  test('Keine neuen rohen Farben, Radien und Schriftgrößen außerhalb von lib/theme', () {
    final hits = <String>[];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final path = file.path.replaceAll(r'\', '/');
      if (!path.endsWith('.dart') || path.startsWith('lib/theme/') || path.startsWith('lib/l10n/')) continue;
      final lines = file.readAsLinesSync();
      for (final (i, line) in lines.indexed) {
        if (line.trimLeft().startsWith('//')) continue;
        if (_raw.hasMatch(line)) hits.add('$path:${i + 1}: ${line.trim()}');
      }
    }
    expect(
      hits.length,
      lessThanOrEqualTo(_budget),
      reason: 'Raw values outside lib/theme (budget $_budget):\n${hits.join('\n')}',
    );
  });
}
