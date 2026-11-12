import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizont/horizont.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/edge_fade.dart';
import 'package:knx_monitor/ui/log_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The overview slides under the activity box with a soft edge, but only once it has scrolled:
/// at the top the first heading stays sharp.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('soft edge under the activity box only after scrolling', (tester) async {
    CatalogStore.instance.catalog = demoCatalog();
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var now = DateTime(2026, 10, 14, 21, 50);
    DemoTunnel.clock = () => now = now.add(const Duration(milliseconds: 900));
    final demo = DemoTunnel();
    final log = TelegramLog()..addAll(demo.simulate());
    demo.dispose();
    DemoTunnel.clock = DateTime.now;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: LogView(data: log, title: const Kennung('Demo-Haus'), exportTitle: 'Demo'),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(TopEdgeFade), findsNothing, reason: 'nothing under the box yet');

    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -300));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(TopEdgeFade), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, 600));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(TopEdgeFade), findsNothing, reason: 'back at the top');
    expect(tester.takeException(), isNull);
  });
}
