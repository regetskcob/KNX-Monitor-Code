import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/theme/app_theme.dart';

/// Ein Mac-Fenster bzw. Tablet im Querformat und ein Telefon, in logischen Punkten.
const wideWindow = Size(1400, 900);
const phoneWindow = Size(375, 812);

/// Zeigt [home] in einem Fenster der Größe [size] mit Schriftfaktor [textScale]. Ein Überlauf
/// lässt den Test wie üblich scheitern.
Future<void> pumpWindow(WidgetTester tester, Widget home, Size size, {double textScale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      // Je Fenster ein neuer Baum: kein Zustand wandert von einer Größe zur nächsten.
      key: ValueKey('$size-$textScale'),
      theme: AppTheme.light(),
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    ),
  );
  await tester.pump();
}

/// Linke Kanten aller Treffer von [finder], gerundet und ohne Doppelte: die Spalten, in denen sie stehen.
Set<int> columnsOf(WidgetTester tester, Finder finder) => {
  for (final e in finder.evaluate()) tester.getTopLeft(find.byElementPredicate((x) => x == e)).dx.round(),
};
