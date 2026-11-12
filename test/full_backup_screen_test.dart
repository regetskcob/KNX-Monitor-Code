import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/ui/figure_box.dart';
import 'package:knx_monitor/ui/full_backup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_storage.dart';
import 'window.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'backup_last_at': '2026-11-02T10:00:00Z'});
    AppStorage.instance = MemoryStorage();
  });

  testWidgets('1400 pt: Datei mit Passwort und beiden Knöpfen links, Stand und Inhalt rechts daneben', (tester) async {
    await pumpWindow(tester, const FullBackupScreen(), wideWindow);
    await tester.pumpAndSettle();
    expect(columnsOf(tester, find.byType(SectionHead)), hasLength(2));
    final file = tester.getTopLeft(find.text('Sicherungsdatei'));
    final device = tester.getTopLeft(find.text('Auf diesem Gerät'));
    expect(device.dx, greaterThan(wideWindow.width / 2));
    expect(device.dy, file.dy, reason: 'beide Spalten beginnen oben');
    expect(tester.getTopLeft(find.text('Inhalt')).dx, device.dx);
    expect(find.text('02.11.2026'), findsOneWidget);
    // Every field has its label above it, not just as a placeholder.
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    for (final (i, label) in ['Passwort der Sicherung', 'Passwort wiederholen'].indexed) {
      expect(tester.getTopLeft(find.text(label)).dy, lessThan(tester.getTopLeft(fields.at(i)).dy));
      expect(tester.widget<TextField>(fields.at(i)).decoration?.hintText, isNull);
    }
    // Create and restore both stand in the card on the left and do not stretch across the column.
    for (final label in ['Sicherung erstellen', 'Sicherung einspielen']) {
      final button = find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>());
      expect(tester.getTopRight(button).dx, lessThan(wideWindow.width / 2));
      expect(tester.getSize(button).width, lessThan(wideWindow.width / 3));
    }
    // What otherwise hides behind the info symbol fills the right column.
    expect(find.textContaining('Nicht enthalten'), findsOneWidget);

    await tester.tap(find.text('Sicherung erstellen'));
    await tester.pump();
    expect(find.text('Mindestens 12 Zeichen.'), findsOneWidget);
  });

  testWidgets('Telefon: eine Liste wie bisher', (tester) async {
    await pumpWindow(tester, const FullBackupScreen(), phoneWindow);
    await tester.pumpAndSettle();
    expect(find.byType(SectionHead), findsNothing);
    expect(find.textContaining('Nicht enthalten'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Sicherung einspielen')).dy,
      greaterThan(tester.getTopLeft(find.text('Sicherung erstellen')).dy),
    );
    expect(find.text('02.11.2026'), findsOneWidget);
    // Jedes Passwortfeld trägt sein Etikett über dem Feld, auch während der Eingabe.
    await tester.enterText(find.byType(TextField).first, 'geheim');
    await tester.pump();
    expect(find.text('Passwort der Sicherung'), findsOneWidget);
    expect(find.text('Passwort wiederholen'), findsOneWidget);
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
