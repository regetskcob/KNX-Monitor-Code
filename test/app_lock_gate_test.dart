import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/app_lock.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/app_lock_screen.dart';
import 'package:knx_monitor/ui/common.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'window.dart';

Widget _app() => MaterialApp(
  theme: AppTheme.light(),
  locale: const Locale('de'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  builder: (context, child) => AppLockGate(child: child!),
  home: const Scaffold(body: TextField(key: Key('geheim'))),
);

void main() {
  testWidgets('gesperrt: Inhalt weg, Passwortfeld und Vergessen-Dialog gehen', (tester) async {
    SharedPreferences.setMockInitialValues({'app_lock_enabled': true, 'app_lock_mode': 'password'});
    FlutterSecureStorage.setMockInitialValues({});
    await AppLock.instance.load();
    addTearDown(() => WidgetsBinding.instance.removeObserver(AppLock.instance));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Busclear ist gesperrt'), findsOneWidget);
    expect(find.byKey(const Key('geheim')), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Passwort vergessen'));
    await tester.pumpAndSettle();
    expect(find.text('Passwort vergessen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(find.text('Busclear ist gesperrt'), findsOneWidget);
  });

  group('Einstellungen der Sperre', () {
    Future<void> lock(Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(prefs);
      FlutterSecureStorage.setMockInitialValues({});
      await AppLock.instance.load();
      addTearDown(() async {
        SharedPreferences.setMockInitialValues({});
        await AppLock.instance.load();
        WidgetsBinding.instance.removeObserver(AppLock.instance);
      });
    }

    const on = {'app_lock_enabled': true, 'app_lock_mode': 'password'};
    const explain = 'Schützt die App, falls das Gerät verloren geht';

    testWidgets('1400 pt: Sperre links, Erklärung und Notfallschlüssel rechts daneben', (tester) async {
      await lock(on);
      await pumpWindow(tester, const AppLockSettingsScreen(), wideWindow);
      await tester.pumpAndSettle();
      final settings = tester.getTopLeft(find.text('Sperren nach'));
      final text = tester.getTopLeft(find.textContaining(explain));
      expect(settings.dx, lessThan(wideWindow.width / 2));
      expect(text.dx, greaterThan(wideWindow.width / 2));
      expect(tester.getTopLeft(find.text('Notfallschlüssel')).dx, text.dx);
      // Little content: two columns of cards.
      expect(columnsOf(tester, find.byType(SectionCard)), hasLength(2));
    });

    testWidgets('1400 pt, noch aus: Einrichten links, Erklärung rechts', (tester) async {
      await lock({});
      await pumpWindow(tester, const AppLockSettingsScreen(), wideWindow);
      // The question for the device lock goes to the platform: it only answers outside the fake clock.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(tester.getTopLeft(find.text('App-Passwort nutzen')).dx, lessThan(wideWindow.width / 2));
      expect(tester.getTopLeft(find.textContaining(explain)).dx, greaterThan(wideWindow.width / 2));
    });

    testWidgets('Telefon: Karten untereinander wie bisher, auch bei doppelter Schrift', (tester) async {
      await lock(on);
      for (final scale in [1.0, 2.0]) {
        await pumpWindow(tester, const AppLockSettingsScreen(), phoneWindow, textScale: scale);
        await tester.pumpAndSettle();
        expect(find.textContaining(explain), findsNothing, reason: 'steht hinter dem Info-Symbol');
        expect(columnsOf(tester, find.byType(SectionCard)), hasLength(1));
        // Doubled text only has to fit; the list builds its lower rows as they scroll in.
        if (scale > 1) continue;
        expect(
          tester.getTopLeft(find.text('Notfallschlüssel')).dy,
          greaterThan(tester.getTopLeft(find.text('Sperren nach')).dy),
        );
      }
    });
  });
}
