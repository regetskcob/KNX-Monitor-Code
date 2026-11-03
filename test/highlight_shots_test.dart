@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizont/horizont.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/device_art.dart';
import 'package:knx_monitor/model/expert_mode.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/charts_screen.dart';
import 'package:knx_monitor/ui/log_view.dart';
import 'package:knx_monitor/ui/topology_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Große Bilder für die Highlights der Landingpage (Mac, 1440 × 900 @2x, dunkel)
// aus dem Demo-Haus nach site/static/images/highlights/. Nur auf Wunsch:
//   HIGHLIGHT_SHOTS=1 flutter test --tags golden --update-goldens test/highlight_shots_test.dart

const _out = '../site/static/images/highlights';

Future<void> _loadFonts() async {
  const fonts = {
    'Literata': ['Literata-Light.ttf', 'Literata-SemiBold.ttf'],
    'MonaSans': ['MonaSans-Regular.ttf', 'MonaSans-Medium.ttf', 'MonaSans-SemiBold.ttf'],
    'MonaspaceArgon': ['MonaspaceArgon-Regular.otf', 'MonaspaceArgon-SemiBold.otf'],
    'MaterialSymbolsSharp': ['MaterialSymbolsSharp-300.ttf'],
  };
  for (final entry in fonts.entries) {
    final loader = FontLoader('packages/horizont/${entry.key}');
    for (final file in entry.value) {
      loader.addFont(rootBundle.load('packages/horizont/fonts/$file'));
    }
    await loader.load();
  }
}

/// Demo-Verkehr mit fester Uhr und ein paar Schaltvorgängen mehr, damit
/// Diagramme und Geräte-LEDs etwas zeigen.
List<Telegram> _traffic() {
  var now = DateTime(2026, 10, 14, 21, 50);
  DemoTunnel.clock = () => now = now.add(const Duration(milliseconds: 900));
  final tunnel = DemoTunnel();
  final out = tunnel.simulate();
  tunnel.dispose();
  DemoTunnel.clock = DateTime.now;
  final start = out.first.time;
  final toggles = [
    for (final (i, (ga, on)) in [
      ('1/1/1', 1), ('1/1/2', 1), ('1/1/1', 0), ('4/0/3', 1), ('1/1/3', 1), //
      ('1/1/2', 0), ('1/1/1', 1), ('4/0/3', 0), ('1/1/4', 1), ('1/1/3', 0),
    ].indexed)
      Telegram(
        time: start.add(Duration(seconds: 22 * (i + 1))),
        source: 0x1110,
        destination: parseGroup(ga)!,
        type: TelegramType.write,
        data: Uint8List.fromList([on]),
        isSmall: true,
      ),
  ];
  return [...out, ...toggles]..sort((a, b) => a.time.compareTo(b.time));
}

void main() {
  final skip = Platform.environment['HIGHLIGHT_SHOTS'] == null ? 'nur mit HIGHLIGHT_SHOTS=1' : null;
  setUpAll(_loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> shoot(WidgetTester tester, String name, Widget Function(TelegramLog log) home) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    const size = Size(1440, 900);
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    ExpertMode.instance.value = true;
    addTearDown(() => ExpertMode.instance.value = false);
    CatalogStore.instance.catalog = demoCatalog();
    final log = TelegramLog()..addAll(_traffic());
    await tester.runAsync(() => DeviceArtCatalog.instance.load());
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: size, devicePixelRatio: 2),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(),
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: home(log),
        ),
      ),
    );
    // Grafiken laden, „frische“ Werte abklingen lassen.
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pump(const Duration(seconds: 2));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_out/$name.png'));
    debugDefaultTargetPlatformOverride = null;
  }

  testWidgets('overview', skip: skip != null, (tester) async {
    await shoot(
      tester,
      'overview',
      (log) => LogView(data: log, title: const Kennung('Demo-Haus'), exportTitle: 'Demo'),
    );
  });

  testWidgets('topology', skip: skip != null, (tester) async {
    await shoot(tester, 'topology', (log) => TopologyScreen(log: log, onFilter: (_) {}));
  });

  testWidgets('charts', skip: skip != null, (tester) async {
    await shoot(
      tester,
      'charts',
      (log) => ChartsScreen(
        log: log,
        initial: [
          for (final a in ['2/0/1', '2/0/2', '2/0/4', '1/1/1', '1/1/2', '1/1/3', '1/1/4', '4/0/3']) parseGroup(a)!,
        ],
      ),
    );
  });
}
