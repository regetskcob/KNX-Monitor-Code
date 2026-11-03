@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/device_art.dart';
import 'package:knx_monitor/model/expert_mode.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/actuator_view.dart';
import 'package:knx_monitor/ui/device_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Bilder für Instagram (store/social/): der Schaltaktor 1.1.10 des
// Demo-Hauses, wie die App ihn zeichnet. Die Kanäle schalten nacheinander
// ein, jedes Bild bei 30 fps landet in build/social/actuator/, dazu das
// Gerätefenster auf dem Telefon. Nur auf Wunsch:
//   SOCIAL_SHOTS=1 flutter test --tags golden --update-goldens test/social_shots_test.dart

const _out = '../build/social';
const _fps = 30;

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

final _actuator = parseIndividual('1.1.10')!;

Telegram _status(int room, bool on, DateTime time) => Telegram(
  time: time,
  source: _actuator,
  destination: parseGroup('1/1/$room')!,
  type: TelegramType.write,
  data: Uint8List.fromList([on ? 1 : 0]),
  isSmall: true,
);

/// Demo-Verkehr mit fester Uhr, danach alle Kanäle des Aktors aus.
TelegramLog _log() {
  var now = DateTime(2026, 10, 14, 21, 50);
  DemoTunnel.clock = () => now = now.add(const Duration(milliseconds: 900));
  final tunnel = DemoTunnel();
  final out = tunnel.simulate();
  tunnel.dispose();
  DemoTunnel.clock = DateTime.now;
  final end = out.last.time;
  return TelegramLog()
    ..addAll(out)
    ..addAll([for (var r = 0; r < 8; r++) _status(r, false, end.add(Duration(seconds: r + 1)))]);
}

void main() {
  final skip = Platform.environment['SOCIAL_SHOTS'] == null ? 'nur mit SOCIAL_SHOTS=1' : null;
  setUpAll(_loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<TelegramLog> pumpApp(
    WidgetTester tester,
    Size size,
    double ratio,
    Widget Function(TelegramLog) home, {
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = size * ratio;
    tester.view.devicePixelRatio = ratio;
    addTearDown(tester.view.reset);
    ExpertMode.instance.value = true;
    addTearDown(() => ExpertMode.instance.value = false);
    CatalogStore.instance.catalog = demoCatalog();
    final log = _log();
    await tester.runAsync(() => DeviceArtCatalog.instance.load());
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size, devicePixelRatio: ratio, padding: padding, viewPadding: padding),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(body: home(log)),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pump(const Duration(seconds: 2));
    return log;
  }

  testWidgets('actuator', skip: skip != null, (tester) async {
    final log = await pumpApp(
      tester,
      const Size(520, 476),
      2,
      (log) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ActuatorView(address: _actuator, log: log),
        ),
      ),
    );
    var frame = 0;
    var time = log.log.last.time;
    Future<void> hold(Duration d) async {
      for (var i = 0; i < d.inMilliseconds * _fps ~/ 1000; i++) {
        await tester.pump(const Duration(milliseconds: 1000 ~/ _fps));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('$_out/actuator/${(frame++).toString().padLeft(3, '0')}.png'),
        );
      }
    }

    await hold(const Duration(milliseconds: 400));
    for (var r = 0; r < 8; r++) {
      time = time.add(const Duration(seconds: 1));
      log.add(_status(r, true, time));
      await hold(const Duration(milliseconds: 450));
    }
    await hold(const Duration(milliseconds: 600));
    debugDefaultTargetPlatformOverride = null;
  });

  // Breit genug für die Kanal-Karten mit Führungslinien neben der Grafik.
  testWidgets('actuator links', skip: skip != null, (tester) async {
    final log = await pumpApp(
      tester,
      const Size(860, 720),
      3,
      (log) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ActuatorView(address: _actuator, log: log),
        ),
      ),
    );
    var time = log.log.last.time;
    // Taster schaltet, der Aktor meldet zurück: Karte und Zeile stimmen überein.
    for (final r in [0, 1, 3, 4, 6]) {
      time = time.add(const Duration(seconds: 1));
      log.add(
        Telegram(
          time: time,
          source: parseIndividual('1.1.${30 + r}')!,
          destination: parseGroup('1/0/$r')!,
          type: TelegramType.write,
          data: Uint8List.fromList([1]),
          isSmall: true,
        ),
      );
      log.add(_status(r, true, time.add(const Duration(milliseconds: 80))));
    }
    await tester.pump(const Duration(seconds: 2));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_out/actuator-links.png'));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('device sheet', skip: skip != null, (tester) async {
    final log = await pumpApp(
      tester,
      const Size(430, 932),
      3,
      (log) => SafeArea(
        child: DeviceTraffic(address: _actuator, log: log, hops: 6, onMap: () {}, onFilter: () {}),
      ),
      // Statusleiste und Home-Balken eines iPhones mit Dynamic Island.
      padding: const EdgeInsets.only(top: 62, bottom: 34),
    );
    var time = log.log.last.time;
    for (final r in [0, 1, 2, 3, 4]) {
      time = time.add(const Duration(seconds: 1));
      log.add(_status(r, true, time));
    }
    await tester.pump(const Duration(seconds: 2));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_out/device-phone.png'));
    debugDefaultTargetPlatformOverride = null;
  });
}
