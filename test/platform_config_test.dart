import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Einstellungen außerhalb von Dart, die kein Unit-Test sonst erreicht.
void main() {
  group('Android: Sicherung und Schlüssel', () {
    test('kein Ausweg aus dem Gerät: weder Cloud noch Gerätewechsel', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:fullBackupContent="false"'));
      expect(manifest, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
      final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml').readAsStringSync();
      for (final section in ['cloud-backup', 'device-transfer']) {
        final body = RegExp('<$section>(.*?)</$section>', dotAll: true).firstMatch(rules)![1]!;
        for (final domain in ['root', 'file', 'database', 'sharedpref', 'external']) {
          expect(body, contains('<exclude domain="$domain"'), reason: '$section/$domain');
        }
      }
    });

    test('jeder Schlüsselbund-Zugriff mit resetOnError: false', () {
      final found = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final text = f.readAsStringSync();
        for (final m in RegExp(r'FlutterSecureStorage\(([^;]*?)\);', dotAll: true).allMatches(text)) {
          found.add(f.path);
          expect(m[1], contains('AndroidOptions(resetOnError: false)'), reason: f.path);
        }
      }
      expect(found, hasLength(greaterThanOrEqualTo(5)));
    });

    test('App-Sperre: FLAG_SECURE über den Kanal', () {
      final activity = File('android/app/src/main/kotlin/de/regetskcob/knxmonitor/MainActivity.kt').readAsStringSync();
      expect(activity, contains('"secureScreen"'));
      expect(activity, contains('FLAG_SECURE'));
    });
  });

  test('Windows: angepasstes local_auth_windows baut mit Visual Studio 2026', () {
    final plugin = File('third_party/local_auth_windows/windows/local_auth_plugin.cpp').readAsStringSync();
    final cmake = File('third_party/local_auth_windows/windows/CMakeLists.txt').readAsStringSync();
    expect(plugin, contains('co_return consent_result;'));
    expect(cmake, isNot(contains('/await')));
    expect(File('pubspec.yaml').readAsStringSync(), contains('path: third_party/local_auth_windows'));
  });

  test('Android: Zurück-Geste mit Vorschau', () {
    expect(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      contains('enableOnBackInvokedCallback="true"'),
    );
  });
}
