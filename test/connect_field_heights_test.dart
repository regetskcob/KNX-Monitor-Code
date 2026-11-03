import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/expert_mode.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/connect_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Gateway und Port stehen nebeneinander und müssen gleich hoch sein, auch bei
// kleinerer oder größerer Systemschrift: Der Suchknopf hält das Gateway-Feld
// mindestens auf Bedienhöhe, das Portfeld bekommt dieselbe Untergrenze.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (name, size, platform, scale) in [
    ('iPad', const Size(1180, 820), TargetPlatform.iOS, 1.0),
    ('iPad kleine Schrift', const Size(1180, 820), TargetPlatform.iOS, 0.85),
    ('iPad große Schrift', const Size(1180, 820), TargetPlatform.iOS, 1.5),
    ('iPhone kleine Schrift', const Size(393, 852), TargetPlatform.iOS, 0.85),
    ('Mac kleine Schrift', const Size(1440, 900), TargetPlatform.macOS, 0.85),
  ]) {
    testWidgets('Gateway und Port gleich hoch: $name', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await ExpertMode.instance.set(true);
      addTearDown(() => ExpertMode.instance.set(false));
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: size, devicePixelRatio: 2, textScaler: TextScaler.linear(scale)),
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const ConnectScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      double height(String label) => tester
          .getSize(
            find.descendant(
              of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
              matching: find.byType(InputDecorator),
            ),
          )
          .height;
      expect(height('Port'), height('Gateway'));
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('Expertenmodus: „Demo ansehen“ bleibt, „Aufnahmen“ kommt dazu', (tester) async {
    tester.view.physicalSize = const Size(393, 852) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    for (final expert in [false, true]) {
      await ExpertMode.instance.set(expert);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: ConnectScreen(key: ValueKey(expert)),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Demo ansehen', skipOffstage: false), findsOneWidget, reason: 'Experte: $expert');
      expect(find.text('Aufnahmen', skipOffstage: false), expert ? findsOneWidget : findsNothing);
    }
    await ExpertMode.instance.set(false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Schmales Telefon (360 dp): „Einführung“ nicht abgeschnitten', (tester) async {
    // Mit den echten Schriften: Die Testschrift ist viel breiter.
    await tester.runAsync(() async {
      for (final file in ['MonaSans-Regular.ttf', 'MonaSans-Medium.ttf', 'MonaSans-SemiBold.ttf']) {
        await (FontLoader(
          'packages/horizont/MonaSans',
        )..addFont(rootBundle.load('packages/horizont/fonts/$file'))).load();
      }
    });
    tester.view.physicalSize = const Size(360, 780) * 2;
    tester.view.devicePixelRatio = 2;
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
    await tester.pump(const Duration(seconds: 2));
    final label = find.textContaining('Einführung', skipOffstage: false);
    expect(label, findsOneWidget);
    expect(tester.renderObject<RenderParagraph>(label).didExceedMaxLines, isFalse);
  });
}
