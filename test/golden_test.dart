@Tags(['golden'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/ui/actuator_view.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/expert_mode.dart';
import 'package:knx_monitor/model/plan.dart';
import 'package:knx_monitor/model/plan_source.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/model/saved_charts.dart';
import 'package:knx_monitor/ui/charts_overview.dart';
import 'package:knx_monitor/ui/value_board.dart';
import 'package:knx_monitor/ui/charts_screen.dart';
import 'package:knx_monitor/ui/connect_screen.dart';
import 'package:knx_monitor/ui/project_check_screen.dart';
import 'package:knx_monitor/ui/log_view.dart';
import 'package:knx_monitor/ui/plan_screen.dart';
import 'package:knx_monitor/ui/flush_input_view.dart';
import 'package:knx_monitor/ui/presence_view.dart';
import 'package:knx_monitor/ui/push_button_view.dart';
import 'package:knx_monitor/ui/weather_view.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/model/push_buttons.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart' show ConnectProblem;
import 'package:knx_monitor/model/connect_help.dart';
import 'package:knx_monitor/model/connection_options.dart' show ConnectionMode;
import 'package:knx_monitor/model/health.dart';
import 'package:knx_monitor/model/weekly_report.dart' show ListeningLog;
import 'package:knx_monitor/ui/weekly_report_screen.dart';
import 'package:horizont/horizont.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Goldens des Horizont-Redesigns: Demo-Haus mit fester Uhr, hell und dunkel,
// Textgröße 1.0 und 2.0, je Formfaktor. Sie rendern mit den gebündelten
// Schriften und unterscheiden sich zwischen macOS und Linux; die CI lässt sie
// aus (--exclude-tags golden). Neu erzeugen:
//   flutter test --tags golden --update-goldens test/golden_test.dart

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

/// Demo-Verkehr mit fester Uhr: Anfangszustand aller Adressen plus einige
/// Schritte laufender Verkehr, ohne Timer.
List<Telegram> _demoTraffic() {
  // Fester Tag in der Vergangenheit: nichts gilt im Bild als „frisch“.
  var now = DateTime(2026, 10, 14, 21, 50);
  DemoTunnel.clock = () => now = now.add(const Duration(milliseconds: 900));
  final tunnel = DemoTunnel();
  final out = tunnel.simulate();
  tunnel.dispose();
  DemoTunnel.clock = DateTime.now;
  return out;
}

/// Store mit den vier Angeboten, Stufe Free.
class _FreeStore extends PlanSource {
  @override
  bool get purchasable => true;

  @override
  Future<Tier> current() async => Tier.free;

  @override
  Future<List<PlanOffer>> offers() async => const [
    PlanOffer(id: 'plus_yearly', tier: Tier.plus, price: '24,99 €', period: OfferPeriod.yearly),
    PlanOffer(id: 'plus_lifetime', tier: Tier.plus, price: '79,00 €', period: OfferPeriod.lifetime),
    PlanOffer(id: 'pro_yearly', tier: Tier.pro, price: '149,00 €', period: OfferPeriod.yearly, trialDays: 14),
    PlanOffer(id: 'pro_monthly', tier: Tier.pro, price: '14,99 €', period: OfferPeriod.monthly),
  ];

  @override
  Future<Tier> buy(PlanOffer offer) async => offer.tier;

  @override
  Future<Tier> restore() async => Tier.free;
}

/// Formfaktoren nach Horizont: Telefon, iPad quer, Mac mit Zeiger.
const _devices = {
  'phone': (Size(393, 852), TargetPlatform.iOS),
  'ipad': (Size(1180, 820), TargetPlatform.iOS),
  'mac': (Size(1440, 900), TargetPlatform.macOS),
};

void main() {
  setUpAll(_loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget home, {
    required String device,
    required Brightness brightness,
    double scale = 1,
    Future<void> Function(WidgetTester)? before,
    double? height,
    double? width,
  }) async {
    var (size, platform) = _devices[device]!;
    if (height != null) size = Size(size.width, height);
    if (width != null) size = Size(width, size.height);
    debugDefaultTargetPlatformOverride = platform;
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final theme = brightness == Brightness.light ? AppTheme.light() : AppTheme.dark();
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size, devicePixelRatio: 2, textScaler: TextScaler.linear(scale)),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: home,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await before?.call(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
    debugDefaultTargetPlatformOverride = null;
  }

  // Grüne Box in voller Breite, Details und Live als Spalten darunter.
  testWidgets('split_mac_light', (tester) async {
    CatalogStore.instance.catalog = demoCatalog();
    final log = TelegramLog()..addAll(_demoTraffic());
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await shoot(
      tester,
      'split_mac_light',
      LogView(data: log, title: const Kennung('Demo-Haus · Aufnahme'), exportTitle: 'Demo'),
      device: 'mac',
      brightness: Brightness.light,
      width: 2000,
      before: (tester) async {
        await tester.tap(find.byType(ValueCard).at(1));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
      },
    );
  });

  for (final brightness in Brightness.values) {
    for (final device in _devices.keys) {
      for (final scale in [1.0, if (device == 'phone') 2.0]) {
        for (final tab in LogTab.values) {
          final name = '${tab.name}_${device}_${brightness.name}_${scale.toStringAsFixed(0)}x';
          testWidgets(name, (tester) async {
            CatalogStore.instance.catalog = demoCatalog();
            final log = TelegramLog()..addAll(_demoTraffic());
            // „Frisch“ eingetroffene Werte blinken; für das Bild abklingen lassen.
            await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
            await shoot(
              tester,
              name,
              LogView(data: log, title: const Kennung('Demo-Haus · Aufnahme'), exportTitle: 'Demo', initialTab: tab),
              device: device,
              brightness: brightness,
              scale: scale,
            );
          });
        }
      }
      testWidgets('connect_${device}_${brightness.name}', (tester) async {
        await shoot(
          tester,
          'connect_${device}_${brightness.name}',
          const ConnectScreen(),
          device: device,
          brightness: brightness,
        );
      });
    }
  }

  // Taster: Glastaster (WZ) und Rahmen 55 (SZ), maßstäblich. Gerade gedrückt:
  // T3/4 am Rahmen (Ab); am Glastaster leuchtet T1 dauerhaft (Licht an).
  for (final brightness in Brightness.values) {
    testWidgets('buttons_phone_${brightness.name}', (tester) async {
      CatalogStore.instance.catalog = demoCatalog();
      final log = TelegramLog()..addAll(_demoTraffic());
      final glass = pushButtonOf(parseIndividual('1.1.30')!, demoCatalog())!;
      final frame = pushButtonOf(parseIndividual('1.1.33')!, demoCatalog())!;
      Telegram write(String from, String ga, int value) => Telegram(
        time: DateTime(2026, 10, 14, 21, 52, 7),
        source: parseIndividual(from)!,
        destination: parseGroup(ga)!,
        type: TelegramType.write,
        data: Uint8List.fromList([value]),
        isSmall: true,
      );
      log.add(write('1.1.10', '1/1/0', 1));
      await shoot(
        tester,
        'buttons_phone_${brightness.name}',
        Builder(
          builder: (context) => MediaQuery(
            // Ohne Bewegung: Tastendruck ohne Einblenden, unabhängig von der Uhr.
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Scaffold(
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    PushButtonView(button: glass, log: log),
                    const SizedBox(height: 32),
                    PushButtonView(button: frame, log: log),
                  ],
                ),
              ),
            ),
          ),
        ),
        device: 'phone',
        brightness: brightness,
        before: (tester) async {
          log.add(write('1.1.33', '3/1/3', 1));
          await tester.pump();
        },
      );
    });
  }

  // Aktoren ohne Herstellergrafik in der neutralen Optik „A“: Dimm-,
  // Jalousie- und Heizungsaktor des Demo-Hauses, Namen in den Feldern.
  for (final brightness in Brightness.values) {
    testWidgets('actuators_generic_ipad_${brightness.name}', (tester) async {
      CatalogStore.instance.catalog = demoCatalog();
      final log = TelegramLog()..addAll(_demoTraffic());
      await shoot(
        tester,
        'actuators_generic_ipad_${brightness.name}',
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Scaffold(
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final pa in ['1.1.11', '1.1.12', '1.1.13']) ...[
                      ActuatorView(address: parseIndividual(pa)!, log: log),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        device: 'ipad',
        brightness: brightness,
      );
    });
  }

  // Sensoren und Eingänge: Tasterinterface, Präsenz- und Bewegungsmelder,
  // Wetterstation – nachgebaut nach einer echten Anlage.
  for (final brightness in Brightness.values) {
    testWidgets('sensors_phone_${brightness.name}', (tester) async {
      final pa = parseIndividual;
      final input = pa('1.1.121')!, ceiling = pa('1.1.60')!, wall = pa('1.1.112')!, weather = pa('1.2.20')!;
      final groups = <int, GroupInfo>{};
      void ga(String a, String name, Dpt dpt, int device, {String? text, bool sends = true}) {
        final g = parseGroup(a)!;
        final links = [...?groups[g]?.links, GroupLink(device: device, text: text, sends: sends)];
        groups[g] = GroupInfo(address: g, name: name, dpt: dpt, links: links);
      }

      for (final (i, (ch, name)) in [
        ('A', 'OG EL F01 Gekippt'),
        ('B', 'OG EL F01 Geöffnet'),
        ('C', 'OG EL F02 Gekippt'),
        ('D', 'OG EL F02 Geöffnet'),
        ('E', 'OG K1 F01 Geöffnet'),
        ('F', 'OG K1 F01 Gekippt'),
        ('G', 'OG K2 F01 Geöffnet'),
        ('H', 'OG K2 F01 Gekippt'),
      ].indexed) {
        ga('4/1/${20 + i}', name, const Dpt(1, 19), input, text: 'Eingang $ch:');
      }
      ga('8/2/0', 'EG FL Helligkeit', const Dpt(9, 4), ceiling);
      ga('8/3/0', 'EG FL Präsenz', const Dpt(1, 18), ceiling);
      ga('1/1/3', 'EG FL Licht Schalten', const Dpt(1, 1), ceiling);
      ga('8/0/3', 'Tag / Nacht', const Dpt(1, 2), ceiling);
      ga('1/1/75', 'Außenleuchte Garage Schalten', const Dpt(1, 1), wall);
      ga('8/1/3', 'Außenhelligkeit', const Dpt(9, 4), weather);
      ga('8/1/3', 'Außenhelligkeit', const Dpt(9, 4), wall, sends: false);
      ga('8/1/4', 'Außenhelligkeit NW (vorne)', const Dpt(9, 4), weather);
      ga('8/1/6', 'Außenhelligkeit SW (links)', const Dpt(9, 4), weather);
      ga('8/1/5', 'Außenhelligkeit NO (rechts)', const Dpt(9, 4), weather);
      ga('8/1/2', 'Außentemperatur', const Dpt(9, 1), weather);
      ga('8/1/1', 'Windgeschwindigkeit (m/s)', const Dpt(9, 5), weather);
      ga('8/1/0', 'Regen', const Dpt(1, 1), weather);
      ga('8/1/8', 'Elevation', const Dpt(14, 7), weather);
      ga('8/1/9', 'Azimut', const Dpt(14, 7), weather);
      CatalogStore.instance.catalog = GroupCatalog(
        groups,
        devices: {
          input: DeviceInfo(address: input, name: 'UP-Fensterkontakt EL', product: 'Tasterinterface 8-fach, UP'),
          ceiling: DeviceInfo(address: ceiling, name: 'Präsenzmelder FL', product: 'Präsenzmelder 360°'),
          wall: DeviceInfo(address: wall, name: 'Bewegungsmelder Garage', product: 'Bewegungsmelder außen 300°'),
          weather: DeviceInfo(address: weather, name: 'Wetterstation', product: 'Wetterstation'),
        },
      );
      final time = DateTime(2026, 10, 14, 14, 5);
      Telegram small(String ga, int v, int from) => Telegram(
        time: time,
        source: from,
        destination: parseGroup(ga)!,
        type: TelegramType.write,
        data: Uint8List.fromList([v]),
        isSmall: true,
      );
      Telegram nine(String ga, double v, int from) => Telegram(
        time: time,
        source: from,
        destination: parseGroup(ga)!,
        type: TelegramType.write,
        data: Uint8List.fromList(encodeDpt9(v)!),
        isSmall: false,
      );
      Telegram float(String ga, double v, int from) => Telegram(
        time: time,
        source: from,
        destination: parseGroup(ga)!,
        type: TelegramType.write,
        data: (ByteData(4)..setFloat32(0, v)).buffer.asUint8List(),
        isSmall: false,
      );
      final log = TelegramLog()
        ..addAll([
          small('4/1/20', 1, input),
          small('4/1/21', 0, input),
          small('4/1/22', 0, input),
          small('4/1/23', 1, input),
          small('4/1/24', 0, input),
          small('4/1/25', 1, input),
          small('4/1/26', 0, input),
          small('4/1/27', 0, input),
          nine('8/2/0', 312, ceiling),
          small('8/3/0', 1, ceiling),
          small('1/1/3', 1, ceiling),
          small('8/0/3', 0, ceiling),
          small('1/1/75', 1, wall),
          nine('8/1/3', 24800, weather),
          nine('8/1/4', 8200, weather),
          nine('8/1/6', 23000, weather),
          nine('8/1/5', 1500, weather),
          nine('8/1/2', 12.4, weather),
          nine('8/1/1', 3.2, weather),
          small('8/1/0', 1, weather),
          float('8/1/8', 28, weather),
          float('8/1/9', 210, weather),
        ]);
      await shoot(
        tester,
        'sensors_phone_${brightness.name}',
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Scaffold(
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final view in [
                      FlushInputView(address: input, log: log),
                      PresenceView(address: ceiling, log: log),
                      PresenceView(address: wall, log: log, wall: true),
                      WeatherView(address: weather, log: log),
                    ]) ...[view, const SizedBox(height: 32)],
                  ],
                ),
              ),
            ),
          ),
        ),
        device: 'phone',
        // Lange Seite: alle Zeichnungen untereinander.
        height: 2600,
        brightness: brightness,
      );
    });
  }

  // Diagramme: Zahlen in einem Feld je Einheit, Schaltwerte als eigene Zeilen.
  testWidgets('charts_mac_dark', (tester) async {
    CatalogStore.instance.catalog = demoCatalog();
    final traffic = _demoTraffic();
    // Ein paar Schaltvorgänge, damit die Zeilen Bänder zeigen.
    final start = traffic.first.time;
    final toggles = [
      for (final (i, (ga, on)) in [
        ('1/1/1', 1),
        ('1/1/2', 1),
        ('1/1/1', 0),
        ('4/0/3', 1),
        ('1/1/3', 1),
        ('1/1/2', 0),
        ('1/1/1', 1),
        ('4/0/3', 0),
      ].indexed)
        Telegram(
          time: start.add(Duration(seconds: 25 * (i + 1))),
          source: 0x1110,
          destination: parseGroup(ga)!,
          type: TelegramType.write,
          data: Uint8List.fromList([on]),
          isSmall: true,
        ),
    ];
    final log = TelegramLog()..addAll([...traffic, ...toggles]..sort((a, b) => a.time.compareTo(b.time)));
    await shoot(
      tester,
      'charts_mac_dark',
      ChartsScreen(
        log: log,
        initial: [
          for (final a in ['2/0/1', '2/0/2', '1/1/1', '1/1/2', '1/1/3', '4/0/3']) parseGroup(a)!,
        ],
      ),
      device: 'mac',
      brightness: Brightness.dark,
    );
  });

  // Diagramm-Bibliothek: ein eigenes Diagramm, darunter die Vorlagen je Rezept.
  testWidgets('chart_library_mac_light', (tester) async {
    CatalogStore.instance.catalog = demoCatalog();
    final log = TelegramLog()..addAll(_demoTraffic());
    SavedCharts.instance.reset();
    await SavedCharts.instance.useScope('Demo-Haus');
    // Wie „Übernehmen“: die erste Vorlage als eigenes Diagramm.
    final first = templateLibrary(log).firstWhere((t) => t.recipeName == s.chartRecipeClimate);
    await SavedCharts.instance.put(first.name, first.addresses);
    await shoot(
      tester,
      'chart_library_mac_light',
      ChartsOverview(log: log),
      device: 'mac',
      height: 1600,
      brightness: Brightness.light,
    );
  });

  // Einsteiger: Hilfe beim Verbinden (Tunnel belegt, IP Secure, nichts gefunden).
  testWidgets('connect_help_phone_light', (tester) async {
    await shoot(
      tester,
      'connect_help_phone_light',
      Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final p in [ConnectProblem.noFreeTunnel, ConnectProblem.secureAuth])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ConnectHelpCard(
                  help: connectHelp(p, mode: ConnectionMode.udp, port: 3671)!,
                  onAction: (_) {},
                ),
              ),
            ConnectHelpCard(help: noGatewayHelp(), onAction: (_) {}),
          ],
        ),
      ),
      device: 'phone',
      brightness: Brightness.light,
      height: 1400,
    );
  });

  // Einsteiger: Wochenbericht mit offenem und erledigtem Befund.
  testWidgets('weekly_report_phone_light', (tester) async {
    CatalogStore.instance.catalog = demoCatalog();
    final health = HealthCheck.instance..debugReset();
    addTearDown(health.debugReset);
    final now = DateTime(2026, 10, 29, 18);
    ListeningLog.instance.debugReset();
    health.runs.addAll([
      HealthRun(now, [HealthFinding(FindingKind.newSilent, parseGroup('2/3/3')!)], asked: 32, answered: 31),
      HealthRun(
        now.subtract(const Duration(days: 2)),
        [HealthFinding(FindingKind.stuck, parseGroup('2/0/1')!)],
        asked: 32,
        answered: 32,
      ),
    ]);
    await shoot(
      tester,
      'weekly_report_phone_light',
      WeeklyReportScreen(onOpenHealth: () {}, at: now),
      device: 'phone',
      brightness: Brightness.light,
    );
  });

  // Projekt-Abgleich ab Tablet zweispaltig.
  testWidgets('project_check_ipad_dark', (tester) async {
    CatalogStore.instance.catalog = demoCatalog();
    final log = TelegramLog()..addAll(_demoTraffic());
    await shoot(
      tester,
      'project_check_ipad_dark',
      ProjectCheckScreen(log: log, onFilter: (_) {}),
      device: 'ipad',
      brightness: Brightness.dark,
    );
  });

  // Bezahlmodell: Bezahlseite und Menü mit gesperrten Werkzeugen (Free).
  for (final brightness in Brightness.values) {
    testWidgets('plan_phone_${brightness.name}', (tester) async {
      await Plan.instance.load(using: _FreeStore());
      await Plan.instance.refreshing;
      await shoot(
        tester,
        'plan_phone_${brightness.name}',
        const PlanScreen(reason: '„Diagnose“ gehört zu Pro.', need: Tier.pro),
        device: 'phone',
        brightness: brightness,
      );
    });
  }

  // Aus dem Menü, ohne Anlass: Pro oben, Plus darunter.
  testWidgets('plan_all_phone_light', (tester) async {
    await Plan.instance.load(using: _FreeStore());
    await Plan.instance.refreshing;
    await shoot(tester, 'plan_all_phone_light', const PlanScreen(), device: 'phone', brightness: Brightness.light);
  });

  testWidgets('menu_free_phone_light', (tester) async {
    await Plan.instance.load(using: _FreeStore());
    await Plan.instance.refreshing;
    ExpertMode.instance.value = true;
    addTearDown(() => ExpertMode.instance.value = false);
    CatalogStore.instance.catalog = demoCatalog();
    final log = TelegramLog()..addAll(_demoTraffic());
    final (size, platform) = _devices['phone']!;
    debugDefaultTargetPlatformOverride = platform;
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
        home: LogView(data: log, title: const Kennung('Demo-Haus'), exportTitle: 'Demo'),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byTooltip('Menü'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/menu_free_phone_light.png'));
    debugDefaultTargetPlatformOverride = null;
  });
}
