import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/expert_mode.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/connect_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Connect page in landscape (iPad, Android tablet, Mac): toggling expert mode keeps the two
/// columns, so the switch stays in its column instead of jumping into a single one.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocaleController.instance.debugSetLocale(const Locale('de'));
  });
  tearDown(() => ExpertMode.instance.set(false));

  for (final size in const [Size(1180, 820), Size(1366, 1024)]) {
    testWidgets('Expertenmodus umschalten: Schalter bleibt in seiner Spalte ($size)', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await ExpertMode.instance.set(true);
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
      final toggle = find.byType(Switch);
      final before = tester.getRect(toggle);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(ExpertMode.instance.value, isFalse);
      final after = tester.getRect(toggle);
      // Same column (right edge), and the page no longer re-centres. The shortcuts above the
      // switch differ with expert mode, so it may move by one row of buttons: in the public
      // build (no home planner) their number of rows changes, here it does not.
      expect(after.right, before.right);
      expect(after.left, greaterThan(size.width / 2));
      expect((after.top - before.top).abs(), lessThanOrEqualTo(56));

      // And back on.
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.getRect(toggle).right, before.right);
    });
  }
}
