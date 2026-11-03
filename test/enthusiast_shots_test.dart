@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/device_inventory.dart';
import 'package:knx_monitor/model/plan.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/cause_chain_view.dart';
import 'package:knx_monitor/ui/details_sheet.dart';
import 'package:knx_monitor/ui/forum_sheet.dart';
import 'package:knx_monitor/ui/ha_config_screen.dart';
import 'package:knx_monitor/ui/inventory_view.dart';
import 'package:knx_monitor/ui/security_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Bilder der Enthusiasten-Werkzeuge im Demo-Haus für den PR, nach
// build/enthusiast_shots/ (nicht im Repo). Nur auf Wunsch:
//   ENT_SHOTS=1 flutter test --tags golden --update-goldens test/enthusiast_shots_test.dart

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

final _t0 = DateTime(2026, 10, 29, 19, 42, 10);
int _ga(String s) => parseGroup(s)!;
int _pa(String s) => parseIndividual(s)!;

Telegram _t(int ms, String source, String ga, List<int> data, {bool small = true}) => Telegram(
  time: _t0.add(Duration(milliseconds: ms)),
  source: _pa(source),
  destination: _ga(ga),
  type: TelegramType.write,
  data: Uint8List.fromList(data),
  isSmall: small,
);

/// Abend im Demo-Haus: Licht per Taster, Aktor meldet zurück; dazwischen
/// Messwerte. Reicht für Ursachenkette, Reaktionszeiten und Forenpaket.
List<Telegram> _evening() => [
  _t(-900, '1.2.20', '4/0/0', [0x0C, 0x7D], small: false),
  for (var i = 0; i < 8; i++) ...[
    _t(i * 4000, '1.1.${30 + i}', '1/0/$i', [1]),
    _t(i * 4000 + 140 + i * 35, '1.1.10', '1/1/$i', [1]),
  ],
  _t(1200, '1.1.41', '5/0/0', [0x44, 0x9A, 0xE0, 0x00], small: false),
  // Fremdes Gerät (nicht im Projekt) für den Sicherheits-Check.
  _t(2100, '1.1.44', '1/0/3', [0]),
  _t(2290, '1.1.10', '1/1/3', [0]),
];

void main() {
  final skip = Platform.environment['ENT_SHOTS'] == null ? 'nur mit ENT_SHOTS=1' : null;
  setUpAll(_loadFonts);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CatalogStore.instance.catalog = demoCatalog();
    Plan.instance.demo = true;
  });
  tearDown(() => Plan.instance.demo = false);

  Future<void> shot(WidgetTester tester, String name, Widget home, {Size size = const Size(820, 1180)}) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: home,
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../build/enthusiast_shots/$name.png'));
  }

  testWidgets('ha_config', skip: skip != null, (tester) async {
    await shot(tester, 'ha_config', const HaConfigScreen());
    await tester.dragUntilVisible(find.text('EG KÜ L02'), find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../build/enthusiast_shots/ha_config_list.png'));
  });

  testWidgets('cause_chain', skip: skip != null, (tester) async {
    final log = _evening()..sort((a, b) => a.time.compareTo(b.time));
    final focus = log.firstWhere((t) => t.destination == _ga('1/0/3') && t.source == _pa('1.1.33'));
    await shot(
      tester,
      'cause_chain',
      Scaffold(
        body: TelegramDetails(
          telegram: focus,
          tunnel: null,
          history: [
            for (final t in log)
              if (t.destination == focus.destination) t,
          ],
          around: log,
        ),
      ),
      size: const Size(420, 1400),
    );
  });

  testWidgets('reaction_times', skip: skip != null, (tester) async {
    final log = TelegramLog()..addAll(_evening()..sort((a, b) => a.time.compareTo(b.time)));
    await shot(tester, 'reaction_times', ReactionTimesScreen(log: log), size: const Size(820, 900));
  });

  testWidgets('security', skip: skip != null, (tester) async {
    final log = TelegramLog()..addAll(_evening());
    await shot(
      tester,
      'security',
      SecurityScreen(tunnel: DemoTunnel(), log: log),
      size: const Size(820, 1100),
    );
  });

  testWidgets('inventory', skip: skip != null, (tester) async {
    final tunnel = DemoTunnel();
    final run = DeviceInventory(
      tunnel,
      area: 1,
      line: 1,
      from: 1,
      to: 50,
      catalog: demoCatalog(),
      pause: Duration.zero,
    );
    // Echtzeit: Die Demo-Geräte antworten mit kurzen Verzögerungen wie am Bus.
    await tester.runAsync(run.start);
    await shot(
      tester,
      'inventory',
      Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [InventoryCard(tunnel: tunnel, initial: run)],
        ),
      ),
      size: const Size(820, 2600),
    );
  });

  testWidgets('forum', skip: skip != null, (tester) async {
    final log = _evening()..sort((a, b) => a.time.compareTo(b.time));
    await shot(
      tester,
      'forum',
      Scaffold(
        body: ForumPanel(telegrams: log.take(8).toList(), connection: 'IP Secure'),
      ),
      size: const Size(820, 1500),
    );
  });
}
