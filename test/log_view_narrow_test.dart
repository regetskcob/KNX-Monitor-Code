import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizont/horizont.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/theme/palette.dart';
import 'package:knx_monitor/ui/log_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Mac-Fenster auf 400 pt gezogen: Zeiger, aber so schmal wie ein Telefon.
  for (final width in const [400.0, 700.0]) {
    testWidgets('Mac-Fenster $width pt: Kopfzeile läuft nicht über, Menü erreichbar', (tester) async {
      CatalogStore.instance.catalog = demoCatalog();
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tunnel = KnxTunnel('192.0.2.1');
      addTearDown(tunnel.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: LogView(
            data: TelegramLog(),
            tunnel: tunnel,
            title: const Kennung('Gira X1 · verbunden'),
            exportTitle: 'Test',
            actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.fiber_manual_record))],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      final context = tester.element(find.byType(LogView));
      expect(context.hzTheme.density, HorizontDensity.pointer);
      if (width < 840) {
        // Wie am Telefon: Menü „⋯“ oben, Ansichten als Reiter unten, „Schreiben“ neben dem Filter, früher kein ausgeschriebenes „Schreiben“.
        expect(find.byTooltip('Menü'), findsOneWidget);
        expect(find.text('Live'), findsWidgets);
        expect(find.widgetWithText(FilledButton, 'Schreiben'), findsOneWidget);
      } else {
        expect(find.byKey(const ValueKey('viewSwitch')), findsOneWidget);
      }
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
