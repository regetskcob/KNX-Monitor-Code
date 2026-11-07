import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/box_screens.dart';

Future<void> pumpLocalized(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('de'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('shows temperature, under-voltage and what happened since power-on', (tester) async {
    await pumpLocalized(
      tester,
      const BoxHealthSection({
        'temp': 58.4,
        'maxTemp': 81.2,
        'throttled': ['underVoltage'],
        'throttledBefore': ['underVoltage', 'softTempLimit'],
      }),
    );
    expect(find.text('SoC 58,4 °C, höchstens 81,2 °C seit dem Start'), findsOneWidget);
    expect(find.textContaining('Unterspannung: Das Netzteil'), findsOneWidget);
    expect(find.text('Seit dem Einschalten: Unterspannung, Temperaturgrenze erreicht'), findsOneWidget);
    expect(find.textContaining('Keine Unterspannung'), findsNothing);
  });

  testWidgets('all fine', (tester) async {
    await pumpLocalized(tester, const BoxHealthSection({'temp': 45.0, 'throttled': [], 'throttledBefore': []}));
    expect(find.text('Keine Unterspannung, keine Drosselung'), findsOneWidget);
  });

  testWidgets('throttling from under-voltage alone is not called heat', (tester) async {
    await pumpLocalized(
      tester,
      const BoxHealthSection({
        'temp': 58.0,
        'throttled': ['underVoltage', 'throttled'],
        'throttledBefore': ['underVoltage'],
        'throttledSince': 'serverStart',
      }),
    );
    expect(find.textContaining('Unterspannung: Das Netzteil'), findsOneWidget);
    expect(find.textContaining('wegen Hitze'), findsNothing);
    expect(find.text('Seit dem Serverstart: Unterspannung'), findsOneWidget);
  });
}
