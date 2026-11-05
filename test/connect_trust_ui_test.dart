import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/box_connection.dart';
import 'package:knx_monitor/model/box_keyring_consent.dart';
import 'package:knx_monitor/platform/addon.dart';
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

  testWidgets('lokaler Link: keine Fremd-Warnung, nur die Rückfrage mit Adresse und HTTP-Hinweis', (tester) async {
    await open(tester);
    BoxConnection.instance.incoming.value = BoxLink.parse('knxmonitor://box?url=http://10.42.0.1/&name=Meine%20Box');
    await tester.pumpAndSettle();
    expect(find.text('Diese Box ist nicht im lokalen Netz'), findsNothing);
    expect(find.text('Mit KNX-Box verbinden?'), findsOneWidget);
    // Adresse eigenständig und vor dem Namen, der Name als Angabe des Links.
    expect(find.text('10.42.0.1'), findsOneWidget);
    expect(find.text('Name im Link: Meine Box'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('10.42.0.1')).dy,
      lessThan(tester.getTopLeft(find.text('Name im Link: Meine Box')).dy),
    );
    expect(find.textContaining('Unverschlüsselt (HTTP)'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
  });

  testWidgets('Link mit Fingerabdruck: kein HTTP-Hinweis', (tester) async {
    await open(tester);
    BoxConnection.instance.incoming.value = BoxLink.parse('knxmonitor://box?url=http://10.42.0.1/&fp=${'A' * 43}');
    await tester.pumpAndSettle();
    expect(find.text('Mit KNX-Box verbinden?'), findsOneWidget);
    expect(find.textContaining('Unverschlüsselt (HTTP)'), findsNothing);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
  });

  testWidgets('andere Box gekoppelt: Ersetzen nur nach eigener Frage mit beiden Boxen', (tester) async {
    final before = BoxLink(url: Uri.parse('http://10.42.0.5/'), key: 'alt', name: 'Werkstatt');
    BoxConnection.instance.saved = before;
    addTearDown(() => BoxConnection.instance.saved = null);
    await open(tester);
    BoxConnection.instance.incoming.value = BoxLink.parse('knxmonitor://box?url=http://10.42.0.9/&name=Neu');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verbinden').last);
    await tester.pumpAndSettle();
    expect(find.text('Gekoppelte Box ersetzen?'), findsOneWidget);
    expect(find.textContaining('Werkstatt (10.42.0.5)'), findsOneWidget);
    expect(find.textContaining('Neu (10.42.0.9)'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(BoxConnection.instance.saved, before);
  });

  testWidgets('gleicher Host, anderer Port: auch das ist eine andere Box', (tester) async {
    final before = BoxLink(url: Uri.parse('http://10.42.0.5/'), key: 'alt', name: 'Werkstatt');
    BoxConnection.instance.saved = before;
    addTearDown(() => BoxConnection.instance.saved = null);
    await open(tester);
    BoxConnection.instance.incoming.value = BoxLink.parse('knxmonitor://box?url=http://10.42.0.5:8080/&name=Neu');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verbinden').last);
    await tester.pumpAndSettle();
    expect(find.text('Gekoppelte Box ersetzen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(BoxConnection.instance.saved, before);
  });

  testWidgets('über fremden Link gekoppelte Box: Projekt erst nach eigener Frage', (tester) async {
    final box = BoxLink(url: Uri.parse('http://10.42.0.9/'), key: 'zugang');
    await BoxProjectConsent.markPending(box);
    // Start mit gekoppelter Box: die App will Projekt und Keyring abgleichen.
    BoxConnection.instance.saved = box;
    Addon.box = box;
    addTearDown(() {
      Addon.box = null;
      BoxConnection.instance.saved = null;
    });
    await open(tester);
    await settle(tester);
    expect(find.text('Projekt an diese Box geben?'), findsOneWidget);
    expect(find.textContaining('Die Box 10.42.0.9'), findsOneWidget);
    await tester.tap(find.text('Noch nicht'));
    await tester.pumpAndSettle();
    expect(await BoxProjectConsent.pending(box), isTrue);
  });

  testWidgets('Keyring: eigene Frage nennt die Adresse', (tester) async {
    await open(tester);
    final box = BoxLink(url: Uri.parse('http://10.42.0.7/'));
    bool? answer;
    final waiting = BoxKeyringConsent.ask!(box).then((v) => answer = v);
    await tester.pumpAndSettle();
    expect(find.text('KNX-Secure-Schlüssel auf diese Box geben?'), findsOneWidget);
    expect(find.textContaining('10.42.0.7'), findsOneWidget);
    await tester.tap(find.text('Nicht geben'));
    await tester.pumpAndSettle();
    await waiting;
    expect(answer, isFalse);
  });
}
