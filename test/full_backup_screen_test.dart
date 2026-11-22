import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizont/horizont.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/ui/full_backup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_storage.dart';
import 'window.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'backup_last_at': '2026-11-02T10:00:00Z'});
    AppStorage.instance = MemoryStorage();
  });

  testWidgets('Übersicht: Stand des Geräts, Inhalt und beide Aufgaben, kein Passwortfeld', (tester) async {
    await pumpWindow(tester, const FullBackupScreen(), wideWindow);
    await tester.pumpAndSettle();
    expect(find.text('Auf diesem Gerät'), findsOneWidget);
    expect(find.text('Inhalt'), findsOneWidget);
    expect(find.text('02.11.2026'), findsOneWidget);
    expect(find.textContaining('Nicht enthalten'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    // Both tasks stand side by side and do not stretch across the page.
    for (final label in ['Sicherung erstellen', 'Sicherung einspielen']) {
      final button = find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>());
      expect(tester.getSize(button).width, lessThan(wideWindow.width / 3));
    }
  });

  Finder wizardButton() => find.descendant(of: find.byType(HorizontWizard), matching: find.bySubtype<FilledButton>());

  for (final (name, window) in [('Dialog', wideWindow), ('Telefon', phoneWindow)]) {
    testWidgets('Erstellen als Wizard ($name): Inhalt, dann Passwort mit Etiketten und Prüfung', (tester) async {
      await pumpWindow(tester, const FullBackupScreen(), window);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sicherung erstellen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sicherung erstellen'));
      await tester.pumpAndSettle();
      expect(find.byType(HorizontWizard), findsOneWidget);
      expect(find.textContaining('Nicht enthalten'), findsWidgets);

      await tester.tap(wizardButton());
      await tester.pumpAndSettle();
      // Every field has its label above it, not just as a placeholder.
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      for (final (i, label) in ['Passwort der Sicherung', 'Passwort wiederholen'].indexed) {
        expect(tester.getTopLeft(find.text(label).last).dy, lessThan(tester.getTopLeft(fields.at(i)).dy));
      }
      // Empty fields: the last step cannot run.
      expect(tester.widget<FilledButton>(wizardButton()).onPressed, isNull);
      await tester.enterText(fields.at(0), 'geheim');
      await tester.enterText(fields.at(1), 'geheim');
      await tester.pump();
      await tester.tap(wizardButton());
      await tester.pumpAndSettle();
      expect(find.text('Mindestens 12 Zeichen.'), findsOneWidget);
      expect(find.byType(HorizontWizard), findsOneWidget, reason: 'bleibt offen, bis die Sicherung liegt');
    });
  }

  testWidgets('Einspielen als Wizard: ohne Datei geht es nicht weiter', (tester) async {
    await pumpWindow(tester, const FullBackupScreen(), phoneWindow);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sicherung einspielen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sicherung einspielen'));
    await tester.pumpAndSettle();
    expect(find.text('Datei wählen'), findsOneWidget);
    expect(tester.widget<FilledButton>(wizardButton()).onPressed, isNull);
  });

  testWidgets('Telefon mit doppelter Schrift: Kennzahlen untereinander, kein Überlauf', (tester) async {
    await pumpWindow(tester, const FullBackupScreen(), phoneWindow, textScale: 2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.dragUntilVisible(find.text('02.11.2026'), find.byType(ListView), const Offset(0, -200));
    expect(
      tester.getTopLeft(find.text('02.11.2026')).dy,
      greaterThan(tester.getTopLeft(find.text('Letzte Sicherung')).dy),
    );
    expect(tester.takeException(), isNull);
  });
}
