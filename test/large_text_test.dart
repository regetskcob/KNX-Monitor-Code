import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizont/horizont.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/expert_mode.dart';
import 'package:knx_monitor/monitor_model.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/commissioning_screen.dart';
import 'package:knx_monitor/ui/connect_screen.dart';
import 'package:knx_monitor/ui/inventory_view.dart';
import 'package:knx_monitor/ui/log_view.dart';
import 'package:knx_monitor/ui/sound_ack_screen.dart';
import 'package:knx_monitor/ui/teach_in_screen.dart';
import 'package:knx_monitor/ui/weekly_report_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Große Schrift auf dem kleinsten Telefon (iPhone 13 mini, 375 × 667 pt,
// Textgröße 2.0) mit den echten Schriften: kein Überlauf und kein Wort, das
// mitten im Wort auf die nächste Zeile bricht.

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

List<Telegram> _demoTraffic() {
  var now = DateTime(2026, 10, 14, 21, 50);
  DemoTunnel.clock = () => now = now.add(const Duration(milliseconds: 900));
  final tunnel = DemoTunnel();
  final out = tunnel.simulate();
  tunnel.dispose();
  DemoTunnel.clock = DateTime.now;
  return out;
}

/// Tunnel, dessen Telegramme der Test selbst einspeist.
class _FakeTunnel extends KnxTunnel {
  _FakeTunnel() : super('test');

  final controller = StreamController<Telegram>.broadcast();

  @override
  Stream<Telegram> get telegrams => controller.stream;
}

Telegram _write(int ms, String dest, String source, List<int> data, {bool small = true}) => Telegram(
  time: DateTime(2020).add(Duration(milliseconds: ms)),
  source: parseIndividual(source)!,
  destination: parseGroup(dest)!,
  type: TelegramType.write,
  data: Uint8List.fromList(data),
  isSmall: small,
);

final _letter = RegExp(r'\p{L}', unicode: true);

/// Texte, die mitten im Wort umbrechen (Wort passt nicht in die Breite).
List<String> _brokenWords(WidgetTester tester) {
  final out = <String>[];
  for (final element in find.byType(RichText).evaluate()) {
    final p = element.renderObject;
    if (p is! RenderParagraph || !p.hasSize || !p.attached) continue;
    final text = p.text.toPlainText();
    for (var o = 1; o < text.length; o++) {
      if (!_letter.hasMatch(text[o - 1]) || !_letter.hasMatch(text[o])) continue;
      final before = p.getBoxesForSelection(TextSelection(baseOffset: o - 1, extentOffset: o));
      final after = p.getBoxesForSelection(TextSelection(baseOffset: o, extentOffset: o + 1));
      if (before.isNotEmpty && after.isNotEmpty && after.first.top > before.first.top + 1) {
        out.add('„$text“ bei ${text.substring(0, o)}|');
        break;
      }
    }
  }
  return out;
}

void main() {
  setUpAll(_loadFonts);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LocaleController.instance.debugSetLocale(const Locale('en'));
  });
  tearDown(() => LocaleController.instance.debugSetLocale(const Locale('de')));

  Future<List<String>> shoot(WidgetTester tester, Widget home, {Future<void> Function()? then}) async {
    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (d) {
      // Meldung plus Fundstelle im Code („The relevant error-causing widget was“).
      final where = RegExp(r'lib/[\w/]+\.dart:\d+').firstMatch(d.toString())?.group(0);
      errors.add('${d.exceptionAsString().split('\n').first}${where == null ? '' : ' ($where)'}');
    };
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(375, 667) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: home,
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await then?.call();
    await tester.pump(const Duration(milliseconds: 500));
    final broken = _brokenWords(tester);
    FlutterError.onError = previous;
    debugDefaultTargetPlatformOverride = null;
    return [...errors, ...broken];
  }

  for (final tab in [LogTab.overview, LogTab.live]) {
    testWidgets('Monitor ${tab.name}: Kennzahlenleiste', (tester) async {
      CatalogStore.instance.catalog = demoCatalog();
      // Live wie am Gateway: mit Rate „Ø Tel./min“ in der Leiste.
      final tunnel = _FakeTunnel();
      final log = MonitorModel(tunnel)..addAll(_demoTraffic());
      final problems = await shoot(
        tester,
        LogView(data: log, title: const Kennung('Demo house'), exportTitle: 'Demo', initialTab: tab),
      );
      await tester.pumpWidget(const SizedBox());
      log.dispose();
      await tunnel.controller.close();
      expect(problems, isEmpty);
    });
  }

  for (final expert in [false, true]) {
    testWidgets('Verbinden (Experte: $expert)', (tester) async {
      await ExpertMode.instance.set(expert);
      addTearDown(() => ExpertMode.instance.set(false));
      expect(await shoot(tester, const ConnectScreen()), isEmpty);
    });
  }

  testWidgets('Geräteinventar: „Start inventory“', (tester) async {
    CatalogStore.instance.catalog = demoCatalog();
    final tunnel = _FakeTunnel();
    addTearDown(tunnel.controller.close);
    final problems = await shoot(
      tester,
      Scaffold(
        body: ListView(children: [InventoryCard(tunnel: tunnel)]),
      ),
    );
    expect(problems, isEmpty);
  });

  testWidgets('Anlernen: gefangenes Ereignis', (tester) async {
    CatalogStore.instance.catalog = demoCatalog();
    final tunnel = _FakeTunnel();
    final problems = await shoot(
      tester,
      TeachInScreen(tunnel: tunnel, warmUp: Duration.zero),
      then: () async {
        tunnel.controller
          ..add(_write(0, '1/0/0', '1.1.30', [1]))
          ..add(_write(150, '1/1/0', '1.1.10', [1]))
          ..add(_write(300, '2/2/7', '1.1.13', [40], small: false))
          ..add(_write(20000, '1/0/9', '1.1.31', [1]));
        await tester.pump();
      },
    );
    await tester.pumpWidget(const SizedBox());
    await tunnel.controller.close();
    expect(problems, isEmpty);
  });

  testWidgets('Ampel der Woche', (tester) async {
    expect(
      await shoot(
        tester,
        Scaffold(
          body: SingleChildScrollView(child: HealthLightCard(onOpenHealth: () {})),
        ),
      ),
      isEmpty,
    );
  });

  testWidgets('Klangquittung: Ziel-Auswahl', (tester) async {
    CatalogStore.instance.catalog = demoCatalog();
    expect(await shoot(tester, const SoundAckScreen()), isEmpty);
  });

  testWidgets('Inbetriebnahme', (tester) async {
    CatalogStore.instance.catalog = demoCatalog();
    final tunnel = _FakeTunnel();
    final problems = await shoot(tester, CommissioningScreen(tunnel: tunnel));
    await tester.pumpWidget(const SizedBox());
    await tunnel.controller.close();
    expect(problems, isEmpty);
  });
}
