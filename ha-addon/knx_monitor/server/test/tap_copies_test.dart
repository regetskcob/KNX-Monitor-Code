import 'dart:io';

import 'package:test/test.dart';

/// The server keeps copies of two classes of the app's `lib/model/tap_points.dart` (it cannot
/// import Flutter code). The same logic must decide in the app and on the add-on, or the list
/// shows a silent tap point or a widened window in one place only.
String _classBody(String source, String name) {
  final start = source.indexOf('class $name {');
  expect(start, isNonNegative, reason: '$name not found');
  final end = source.indexOf('\n}\n', start);
  return source.substring(start, end).replaceAll(RegExp(r'\s+'), ' ');
}

void main() {
  final app = File('../../../lib/model/tap_points.dart').readAsStringSync();
  for (final (name, file) in [
    ('TapSilence', 'lib/src/tap_silence.dart'),
    ('TapWindowMeter', 'lib/src/tap_window.dart'),
  ]) {
    test('$name is the same in app and server', () {
      expect(_classBody(File(file).readAsStringSync(), name), _classBody(app, name));
    });
  }
}
