import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/box_connection.dart';
import 'package:knx_monitor/model/box_keyring_consent.dart';
import 'package:knx_monitor/platform/box_link.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/connect_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('connect_trust');
    AppStorage.instance = IoStorage(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// Echte Dateizugriffe brauchen echte Zeit, die Folgen ein Bild.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const ConnectScreen(),
      ),
    );
    await settle(tester);
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('ohne beiseitegelegte Dateien kein Hinweis', (tester) async {
    await open(tester);
    expect(find.textContaining('sich nicht öffnen'), findsNothing);
  });

  testWidgets('beiseitegelegte Dateien: Hinweis, Wiederherstellen und Löschen', (tester) async {
    File('${dir.path}/nicht-lesbar/a.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('x' * 2048);
    await open(tester);
    expect(find.textContaining('sich nicht öffnen'), findsOneWidget);
    expect(find.textContaining('Eine Datei (2 KB)'), findsOneWidget);
    expect(find.text('Aus Sicherung wiederherstellen'), findsOneWidget);
    await tester.tap(find.text('Dateien löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dateien löschen').last);
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(Directory('${dir.path}/nicht-lesbar').existsSync(), isFalse);
    expect(find.textContaining('sich nicht öffnen'), findsNothing);
  });

  testWidgets('fremder Link: deutliche Warnung mit Adresse, Abbrechen tut nichts', (tester) async {
    await open(tester);
    BoxConnection.instance.incoming.value = BoxLink.parse('knxmonitor://box?url=https://evil.example');
    await tester.pumpAndSettle();
    expect(find.text('Diese Box ist nicht im lokalen Netz'), findsOneWidget);
    expect(find.textContaining('evil.example'), findsOneWidget);
    expect(find.text('Mit KNX-Box verbinden?'), findsNothing);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(find.text('Diese Box ist nicht im lokalen Netz'), findsNothing);
  });

  testWidgets('lokaler Link: keine Warnung, nur die Rückfrage', (tester) async {
    await open(tester);
    BoxConnection.instance.incoming.value = BoxLink.parse('knxmonitor://box?url=http://10.42.0.1/');
    await tester.pumpAndSettle();
    expect(find.text('Diese Box ist nicht im lokalen Netz'), findsNothing);
    expect(find.text('Mit KNX-Box verbinden?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
  });

  testWidgets('Keyring: eigene Frage nennt die Adresse', (tester) async {
    await open(tester);
    final box = BoxLink(url: Uri.parse('http://10.42.0.7/'));
    bool? answer;
    final waiting = BoxKeyringConsent.ask!(box).then((v) => answer = v);
    await tester.pumpAndSettle();
    expect(find.text('Keyring auf diese Box geben?'), findsOneWidget);
    expect(find.textContaining('10.42.0.7'), findsOneWidget);
    await tester.tap(find.text('Nicht geben'));
    await tester.pumpAndSettle();
    await waiting;
    expect(answer, isFalse);
  });
}
