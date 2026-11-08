import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/app_lock.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/app_lock_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
