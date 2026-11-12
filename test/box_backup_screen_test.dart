import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/platform/addon.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/box_backup_screen.dart';

/// Box und Dateien ohne Netz: merkt sich, was der Bildschirm schickt.
class _FakeClient extends BoxBackupClient {
  _FakeClient({
    this.readOnly = false,
    this.secrets = true,
    this.failApply,
    this.plain = false,
    this.missing = false,
    this.serverName = 'busclear-box-sicherung.zip',
  });

  final bool readOnly;
  final bool secrets;
  final AddonException? failApply;
  final bool plain;
  final bool missing;
  final String serverName;
  final prepared = <({String? password, String? previous})>[];
  final downloaded = <String>[];
  final paths = <String>[];
  final delivered = <String>[];
  final applied = <({String stage, String? password, bool withoutSecrets, String? current})>[];
  Completer<void>? holdDownload;
  bool? stoppedByCancel;

  @override
  Future<Map<String, Object?>> status() async {
    if (missing) throw const AddonException('Box: HTTP 404', status: 404);
    return {
      'readOnly': readOnly,
      'needsCurrent': true,
      'minPassword': 12,
      'previous': [
        {
          'name': '20261110-120000',
          'created': '2026-11-10T12:00:00Z',
          'installations': ['Alt'],
        },
      ],
    };
  }

  @override
  bool get plainNetwork => plain;

  @override
  String? get boxLabel => 'Garage/../Box 1';

  @override
  Future<Map<String, Object?>> prepare({String? password, String? previous}) async {
    prepared.add((password: password, previous: previous));
    return {
      'ticket': 't1',
      // A hostile box: the app must not use this name.
      'fileName': serverName,
      'bytes': 2 * 1024 * 1024 * 1024,
      'secrets': password != null,
      'withheld': password == null ? ['keyring'] : <String>[],
    };
  }

  @override
  Future<String> temporaryPath(String fileName) async {
    paths.add(fileName);
    return '${Directory.systemTemp.path}/$fileName';
  }

  @override
  Future<void> download(
    String ticket,
    String path, {
    void Function(int bytes)? onProgress,
    bool Function()? cancelled,
  }) async {
    downloaded.add(ticket);
    onProgress?.call(1536 * 1024 * 1024);
    if (holdDownload case final hold?) {
      await hold.future;
      stoppedByCancel = cancelled?.call();
      if (stoppedByCancel ?? false) throw const AddonException('x', problem: 'cancelled');
    }
  }

  @override
  Future<String?> deliver(File file, String name, {Rect? origin}) async {
    delivered.add(name);
    return '';
  }

  @override
  Future<Map<String, Object?>?> pickAndUpload({void Function()? onStart, void Function(int bytes)? onProgress}) async {
    onStart?.call();
    return {
      'stage': 's1',
      'created': '2026-11-09T08:00:00Z',
      'box': {'name': 'Garage'},
      'installations': [
        {'id': 'default', 'name': 'Musterhaus'},
        {'id': 'b', 'name': 'Baustelle'},
      ],
      'secrets': secrets,
      'files': 12,
      'bytes': 4096,
    };
  }

  @override
  Future<Map<String, Object?>> apply({
    required String stage,
    String? password,
    bool withoutSecrets = false,
    String? current,
  }) async {
    applied.add((stage: stage, password: password, withoutSecrets: withoutSecrets, current: current));
    if (failApply case final e?) throw e;
    return {
      'installations': 2,
      'secrets': password != null,
      'secretsSkipped': secrets && password == null,
      'previous': '20261111-120000',
    };
  }
}

void main() {
  Widget app(Widget child, {Locale locale = const Locale('de')}) => MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    home: child,
  );

  void tall(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(1200, 3600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> enter(WidgetTester tester, int index, String text) async {
    await tester.enterText(find.byType(TextField).at(index), text);
    await tester.pump();
  }

  Future<void> pick(WidgetTester tester) async {
    await tester.tap(find.text('Sicherung auswählen …'));
    await tester.pumpAndSettle();
  }

  test('H1: Dateiname kommt von der App, nie von der Box', () {
    final now = DateTime(2026, 11, 11, 9, 5);
    expect(
      boxBackupFileName(box: 'Garage/../Box 1', now: now),
      'busclear-box-sicherung-Garage-Box-1-2026-11-11-0905.zip',
    );
    expect(boxBackupFileName(box: r'..\..\Startup', now: now), 'busclear-box-sicherung-Startup-2026-11-11-0905.zip');
    expect(boxBackupFileName(previous: '20261110-120000', now: now), 'busclear-box-vorher-20261110-120000.zip');
    expect(boxBackupFileName(previous: '../../x', now: now), 'busclear-box-sicherung-2026-11-11-0905.zip');
    expect(boxBackupFileName(box: 'ä' * 200, now: now), 'busclear-box-sicherung-2026-11-11-0905.zip');
  });

  testWidgets('H1: bösartiger Dateiname der Box wird nicht benutzt', (tester) async {
    tall(tester);
    final client = _FakeClient(serverName: '../../AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup/x.cmd');
    await tester.pumpWidget(app(BoxBackupScreen(client: client)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KNX-Secure-Schlüssel und Zugangsdaten einschließen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sicherung erstellen').last);
    await tester.pumpAndSettle();
    expect(client.paths.single, matches(RegExp(r'^busclear-box-sicherung-Garage-Box-1-[0-9-]+\.zip$')));
    expect(client.delivered.single, client.paths.single);
  });

  testWidgets('Sicherung mit Schlüsseln: Passwort prüfen am Feld, dann laden und weitergeben', (tester) async {
    tall(tester);
    final client = _FakeClient();
    await tester.pumpWidget(app(BoxBackupScreen(client: client)));
    await tester.pumpAndSettle();
    await enter(tester, 0, 'kurz');
    await tester.tap(find.text('Sicherung erstellen').last);
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.decoration?.errorText, 'Mindestens 12 Zeichen.');
    expect(client.prepared, isEmpty);

    await enter(tester, 0, 'ein langes passwort');
    await enter(tester, 1, 'ein anderes passwort');
    await tester.tap(find.text('Sicherung erstellen').last);
    await tester.pumpAndSettle();
    expect(find.text('Die Passwörter stimmen nicht überein.'), findsOneWidget);

    await enter(tester, 1, 'ein langes passwort');
    await tester.tap(find.text('Sicherung erstellen').last);
    await tester.pumpAndSettle();
    expect(client.prepared.single.password, 'ein langes passwort');
    expect(client.downloaded, ['t1']);
    expect(find.text('Sicherung gespeichert.'), findsOneWidget);
    // Help says what happens with a forgotten password.
    expect(find.textContaining('Getrennt notieren'), findsOneWidget);
  });

  testWidgets('UX10: Fortschritt mit Ziel in GB, Abbrechen beendet den Download', (tester) async {
    tall(tester);
    final client = _FakeClient()..holdDownload = Completer<void>();
    await tester.pumpWidget(app(BoxBackupScreen(client: client)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KNX-Secure-Schlüssel und Zugangsdaten einschließen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sicherung erstellen').last);
    await tester.pump();
    await tester.pump();
    expect(find.text('Lade 1,50 GB von etwa 2,00 GB …'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, closeTo(0.75, 0.001));
    await tester.tap(find.text('Abbrechen'));
    await tester.pump();
    client.holdDownload!.complete();
    await tester.pumpAndSettle();
    expect(client.stoppedByCancel, isTrue);
    expect(client.delivered, isEmpty);
    expect(find.text('Abgebrochen.'), findsOneWidget);
  });

  testWidgets('N5: unverschlüsselte Verbindung fragt vor Schlüsseln nach', (tester) async {
    tall(tester);
    final client = _FakeClient(plain: true);
    await tester.pumpWidget(app(BoxBackupScreen(client: client)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unverschlüsselte Verbindung'), findsOneWidget);
    await enter(tester, 0, 'ein langes passwort');
    await enter(tester, 1, 'ein langes passwort');
    await tester.tap(find.text('Sicherung erstellen').last);
    await tester.pumpAndSettle();
    expect(find.text('Ohne Verschlüsselung weiter?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(client.prepared, isEmpty);
    await tester.tap(find.text('Sicherung erstellen').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trotzdem'));
    await tester.pumpAndSettle();
    expect(client.prepared.single.password, 'ein langes passwort');
  });

  testWidgets('Sicherung ohne Schlüssel: kein Passwort, Hinweis was fehlt', (tester) async {
    tall(tester);
    final client = _FakeClient();
    await tester.pumpWidget(app(BoxBackupScreen(client: client)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KNX-Secure-Schlüssel und Zugangsdaten einschließen'));
    await tester.pumpAndSettle();
    expect(find.text('Passwort der Sicherung'), findsNothing);
    await tester.tap(find.text('Sicherung erstellen').last);
    await tester.pumpAndSettle();
    expect(client.prepared.single.password, isNull);
    expect(find.textContaining('Ohne Schlüssel gesichert'), findsOneWidget);
  });

  testWidgets('Wiederherstellen mit Passwort: Rückfrage mit Datum und Anzahl, dann mit Box-Passwort', (tester) async {
    tall(tester);
    final client = _FakeClient();
    await tester.pumpWidget(app(BoxBackupScreen(client: client)));
    await tester.pumpAndSettle();
    await pick(tester);
    expect(find.textContaining('2 Anlagen'), findsOneWidget);
    expect(find.text('Box-Passwort (zur Bestätigung)'), findsOneWidget);
    // Fields: create (2), backup password, box password.
    await enter(tester, 2, 'ein langes passwort');
    await enter(tester, 3, 'box-passwort');
    await tester.tap(find.text('Box wiederherstellen'));
    await tester.pumpAndSettle();
    expect(find.text('Box wiederherstellen?'), findsOneWidget);
    expect(find.textContaining('die 2 Anlagen aus der Sicherung vom 09.11.2026'), findsOneWidget);
    expect(client.applied, isEmpty);
    await tester.tap(find.text('Box wiederherstellen').last);
    await tester.pumpAndSettle();
    expect(client.applied.single, (
      stage: 's1',
      password: 'ein langes passwort',
      withoutSecrets: false,
      current: 'box-passwort',
    ));
    expect(find.textContaining('2 Anlagen wiederhergestellt'), findsOneWidget);
    expect(find.textContaining('Schlüssel nicht wiederhergestellt'), findsNothing);
  });

  testWidgets('UX1: Ergebnis steht im Abschnitt Wiederherstellen, nicht oben', (tester) async {
    tall(tester);
    final client = _FakeClient();
    await tester.pumpWidget(app(BoxBackupScreen(client: client)));
    await tester.pumpAndSettle();
    await pick(tester);
    await enter(tester, 2, 'ein langes passwort');
    await enter(tester, 3, 'box-passwort');
    await tester.tap(find.text('Box wiederherstellen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Box wiederherstellen').last);
    await tester.pumpAndSettle();
    final result = tester.getTopLeft(find.textContaining('Anlagen wiederhergestellt')).dy;
    expect(result, greaterThan(tester.getTopLeft(find.textContaining('Ersetzt alle Anlagen dieser Box')).dy));
    expect(result, lessThan(tester.getTopLeft(find.text('Sicherung auswählen …')).dy));
    expect(result, greaterThan(tester.getTopLeft(find.text('Sicherung erstellen').last).dy));
  });

  testWidgets('Wiederherstellen ohne Passwort: nur nach eigener Rückfrage, Schlüssel bleiben weg', (tester) async {
    tall(tester);
    final client = _FakeClient();
    await tester.pumpWidget(app(BoxBackupScreen(client: client)));
    await tester.pumpAndSettle();
    await pick(tester);
    await enter(tester, 3, 'box-passwort');
    await tester.tap(find.text('Box wiederherstellen'));
    await tester.pumpAndSettle();
    expect(find.text('Ohne Schlüssel wiederherstellen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(client.applied, isEmpty);

    await tester.tap(find.text('Box wiederherstellen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ohne Schlüssel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Box wiederherstellen').last);
    await tester.pumpAndSettle();
    expect(client.applied.single, (stage: 's1', password: null, withoutSecrets: true, current: 'box-passwort'));
    expect(find.textContaining('Schlüssel nicht wiederhergestellt'), findsOneWidget);
  });

  testWidgets('falsches Passwort der Sicherung steht am Feld', (tester) async {
    tall(tester);
    final client = _FakeClient(failApply: const AddonException('x', problem: 'backupPassword'));
    await tester.pumpWidget(app(BoxBackupScreen(client: client)));
    await tester.pumpAndSettle();
    await pick(tester);
    await enter(tester, 2, 'falsches passwort');
    await enter(tester, 3, 'box-passwort');
    await tester.tap(find.text('Box wiederherstellen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Box wiederherstellen').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).decoration?.errorText,
      'Das Passwort der Sicherung stimmt nicht.',
    );
    // The upload stays, so the user can try again.
    expect(find.text('Box wiederherstellen'), findsOneWidget);
  });

  testWidgets('UX1: leeres Box-Passwort hat einen eigenen Hinweis', (tester) async {
    tall(tester);
    final client = _FakeClient(secrets: false);
    await tester.pumpWidget(app(BoxBackupScreen(client: client)));
    await tester.pumpAndSettle();
    await pick(tester);
    expect(find.textContaining('Ohne Schlüssel gesichert'), findsOneWidget);
    await tester.tap(find.text('Box wiederherstellen'));
    await tester.pumpAndSettle();
    expect(client.applied, isEmpty);
    expect(find.text('Box-Passwort eingeben.'), findsOneWidget);
    expect(find.text('Box wiederherstellen?'), findsNothing);
  });

  testWidgets('UX7: Serverfehler übersetzt, auch auf Englisch', (tester) async {
    tall(tester);
    LocaleController.instance.debugSetLocale(const Locale('en'));
    addTearDown(() => LocaleController.instance.debugSetLocale(const Locale('de')));
    final client = _FakeClient(failApply: const AddonException('Die Sicherung wurde …', problem: 'tampered'));
    await tester.pumpWidget(app(BoxBackupScreen(client: client), locale: const Locale('en')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose backup …'));
    await tester.pumpAndSettle();
    await enter(tester, 2, 'ein langes passwort');
    await enter(tester, 3, 'box-passwort');
    await tester.tap(find.text('Restore box'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore box').last);
    await tester.pumpAndSettle();
    expect(find.text('The backup was changed after it was made and is not restored.'), findsOneWidget);
  });

  testWidgets('Nur-Lesen: Sichern ja, Wiederherstellen gesperrt', (tester) async {
    tall(tester);
    await tester.pumpWidget(app(BoxBackupScreen(client: _FakeClient(readOnly: true))));
    await tester.pumpAndSettle();
    expect(find.text('Sicherung auswählen …'), findsNothing);
    expect(find.textContaining('Nur-Lesen ist an'), findsOneWidget);
    expect(find.text('Sicherung erstellen'), findsWidgets);
  });

  testWidgets('UX8: ältere Box ohne Sicherung: klarer Hinweis, keine Abschnitte', (tester) async {
    tall(tester);
    await tester.pumpWidget(app(BoxBackupScreen(client: _FakeClient(missing: true))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Diese Box kann noch keine Sicherungen'), findsOneWidget);
    expect(find.text('Frühere Stände'), findsNothing);
    expect(find.text('Sicherung erstellen'), findsNothing);
  });

  testWidgets('frühere Stände: eigener Passwortdialog, Knöpfe auch bei großer Schrift nutzbar', (tester) async {
    tall(tester);
    final client = _FakeClient();
    await tester.pumpWidget(
      app(
        MediaQuery(
          data: const MediaQueryData(size: Size(375, 3600), textScaler: TextScaler.linear(2)),
          child: BoxBackupScreen(client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Alt'), findsOneWidget);
    // The text keeps the width, the buttons sit below it.
    expect(tester.getTopLeft(find.text('Herunterladen')).dy, greaterThan(tester.getTopLeft(find.text('Alt')).dy));
    await tester.tap(find.text('Herunterladen'));
    await tester.pumpAndSettle();
    expect(find.text('Früheren Stand herunterladen'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'ein langes passwort');
    await tester.tap(find.text('Herunterladen').last);
    await tester.pumpAndSettle();
    expect(client.prepared.single, (password: 'ein langes passwort', previous: '20261110-120000'));
    expect(client.paths.single, 'busclear-box-vorher-20261110-120000.zip');
  });
}
