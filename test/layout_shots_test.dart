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
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/box_setup.dart';
import 'package:knx_monitor/model/expert_mode.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/platform/box_link.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/box_screens.dart';
import 'package:knx_monitor/ui/log_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Layout auf großen Bildschirmen (z. B. 34″ 21:9, 3440 × 1440 bei Faktor 1),
// mit Demo-Haus, nach build/layout/ (nicht im Repo). Nur auf Wunsch:
//   LAYOUT_SHOTS=1 flutter test --tags golden --update-goldens test/layout_shots_test.dart

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

void main() {
  final skip = Platform.environment['LAYOUT_SHOTS'] == null;
  setUpAll(_loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Logische Größe, Pixelfaktor, Plattform (Touch oder Zeiger).
  const sizes = {
    'ultrawide': (Size(3440, 1340), 1.0, TargetPlatform.macOS),
    'qhd': (Size(2560, 1340), 1.0, TargetPlatform.macOS),
    'notebook16_web': (Size(1728, 970), 2.0, TargetPlatform.macOS),
    'ipad13_quer': (Size(1376, 1032), 2.0, TargetPlatform.iOS),
  };
  for (final MapEntry(key: name, value: (size, dpr, platform)) in sizes.entries) {
    for (final tab in [LogTab.overview, LogTab.live]) {
      testWidgets('layout_${name}_${tab.name}', skip: skip, (tester) async {
        CatalogStore.instance.catalog = demoCatalog();
        ExpertMode.instance.value = true;
        addTearDown(() => ExpertMode.instance.value = false);
        var now = DateTime(2026, 10, 14, 21, 50);
        DemoTunnel.clock = () => now = now.add(const Duration(milliseconds: 900));
        final tunnel = DemoTunnel();
        final log = TelegramLog()..addAll(tunnel.simulate());
        tunnel.dispose();
        DemoTunnel.clock = DateTime.now;
        await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
        debugDefaultTargetPlatformOverride = platform;
        tester.view.physicalSize = size * dpr;
        tester.view.devicePixelRatio = dpr;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark(),
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: LogView(data: log, title: const Kennung('Demo-Haus'), exportTitle: 'Demo', initialTab: tab),
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('../build/layout/${name}_${tab.name}.png'));
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }

  // Mac App Store: MacBook (1440 × 900 bei Faktor 2), hell, je Sprache, mit
  // Demo-Haus, nach store/raw/mac/<sprache>/ (tool/store_graphics.py):
  //   STORE_MAC=1 flutter test --tags golden --update-goldens test/layout_shots_test.dart
  final skipMac = Platform.environment['STORE_MAC'] == null;
  for (final lang in LocaleController.supported) {
    for (final tab in LogTab.values) {
      testWidgets('store_mac_${lang}_${tab.name}', skip: skipMac, (tester) async {
        LocaleController.instance.debugSetLocale(Locale(lang));
        addTearDown(() => LocaleController.instance.debugSetLocale(const Locale('de')));
        CatalogStore.instance.catalog = demoCatalog();
        var now = DateTime(2026, 10, 14, 21, 50);
        DemoTunnel.clock = () => now = now.add(const Duration(milliseconds: 900));
        final tunnel = DemoTunnel();
        final log = TelegramLog()..addAll(tunnel.simulate());
        tunnel.dispose();
        DemoTunnel.clock = DateTime.now;
        // „Frisch“ eingetroffene Werte blinken; für das Bild abklingen lassen.
        await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        tester.view.physicalSize = const Size(1440, 900) * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            locale: Locale(lang),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: LogView(
              data: log,
              title: Kennung(lang == 'de' ? 'Demo-Haus' : 'Demo house'),
              exportTitle: 'Demo',
              initialTab: tab,
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('../store/raw/mac/$lang/${tab.name}.png'));
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }

  // Box-Seite (site/, 03 Einrichten): die Einrichtung der KNX-Box auf dem
  // iPhone, alle Schritte abgehakt, je Sprache nach site/assets/images/:
  //   BOX_SHOTS=1 flutter test --tags golden --update-goldens test/layout_shots_test.dart
  final skipBox = Platform.environment['BOX_SHOTS'] == null;
  for (final lang in LocaleController.supported) {
    testWidgets('box_setup_$lang', skip: skipBox, (tester) async {
      LocaleController.instance.debugSetLocale(Locale(lang));
      addTearDown(() => LocaleController.instance.debugSetLocale(const Locale('de')));
      final link = BoxLink(url: Uri.parse('http://knx-box.local'), name: 'KNX-Box-4F2A', ssid: 'KNX-Box-4F2A');
      final setup = BoxSetup(link, deviceName: 'iPhone')
        ..timeResult = 'set'
        ..gateway = '192.168.1.10';
      setup.states.updateAll((_, _) => BoxStepState.done);
      addTearDown(setup.dispose);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      const size = Size(393, 852);
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          // Insel oben, Leiste unten wie am iPhone.
          data: const MediaQueryData(size: size, devicePixelRatio: 3, padding: EdgeInsets.only(top: 59, bottom: 34)),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            locale: Locale(lang),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: BoxSetupScreen(link: link, deviceName: 'iPhone', setup: setup),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('../site/assets/images/box-setup-$lang.png'));
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
