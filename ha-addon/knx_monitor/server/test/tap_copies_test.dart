import 'dart:io';

import 'package:test/test.dart';

/// The server keeps copies of classes of the app's `lib/model/tap_points.dart` and of the Data
/// Secure exception for tap points (it cannot
/// import Flutter code). The same logic must decide in the app and on the add-on, or the list
/// shows a silent tap point or a widened window in one place only.
String _classBody(String source, String name) {
  final start = source.indexOf('class $name {');
  expect(start, isNonNegative, reason: '$name not found');
  final end = source.indexOf('\n}\n', start);
  return source.substring(start, end).replaceAll(RegExp(r'\s+'), ' ');
}

void main() {
  const model = '../../../lib/model/tap_points.dart';
  for (final (name, file, appFile) in [
    ('TapSilence', 'lib/src/tap_silence.dart', model),
    ('TapWindowMeter', 'lib/src/tap_window.dart', model),
    ('TapBacklog', 'lib/src/tap_window.dart', model),
    // The exception to the replay check must be exactly the same in both places.
    ('SecureTapCache', 'lib/src/secure_taps.dart', '../../../lib/knx/secure/secure_tap_cache.dart'),
    ('_Seen', 'lib/src/secure_taps.dart', '../../../lib/knx/secure/secure_tap_cache.dart'),
  ]) {
    test('$name is the same in app and server', () {
      expect(_classBody(File(file).readAsStringSync(), name), _classBody(File(appFile).readAsStringSync(), name));
    });
  }
}
