import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Speichert die Screenshots des Rundgangs unter build/tour/.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final file = File('build/tour/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    return true;
  },
);
