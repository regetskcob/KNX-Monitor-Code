import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/expert_mode.dart';
import 'package:knx_monitor/model/plain_text.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/cause_chain_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'window.dart';

final _t0 = DateTime(2026, 10, 29, 20);

Telegram _t(int ms, String source, String ga) => Telegram(
  time: _t0.add(Duration(milliseconds: ms)),
  source: parseIndividual(source)!,
  destination: parseGroup(ga)!,
  type: TelegramType.write,
  data: Uint8List.fromList([1]),
  isSmall: true,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final command = _t(0, '1.1.60', '1/1/1');
  final feedback = _t(120, '1.1.10', '1/4/1');
  final log = [command, feedback];

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: CauseChainView(telegram: command, log: log),
      ),
    ),
  );

  testWidgets('ohne Expertenmodus spricht die Kette wie die Live-Liste', (tester) async {
    await ExpertMode.instance.set(false);
    await pump(tester);
    expect(find.text(telegramSentence(command)), findsOneWidget);
    expect(find.text(telegramSentence(feedback)), findsOneWidget);
    // Ohne Projekt nur Zeitnähe: nicht „gleichzeitig“ nennen, der Abstand steht daneben.
    expect(find.text('Zeitnah, ohne Bezug'), findsOneWidget);
    expect(find.text('+120 ms'), findsOneWidget);
  });

  testWidgets('im Expertenmodus Adresse, Wert und Absender', (tester) async {
    await ExpertMode.instance.set(true);
    addTearDown(() => ExpertMode.instance.set(false));
    await pump(tester);
    expect(find.text(telegramSentence(command)), findsNothing);
    expect(find.textContaining('1/1/1'), findsWidgets);
  });

  group('Reaktionszeiten', () {
    late TelegramLog demo;
    setUp(() {
      CatalogStore.instance.catalog = demoCatalog();
      var now = DateTime(2026, 11, 10, 18, 30);
      DemoTunnel.clock = () => now = now.add(const Duration(milliseconds: 900));
      final tunnel = DemoTunnel();
      demo = TelegramLog()..addAll(tunnel.simulate(steps: 400));
      tunnel.dispose();
      DemoTunnel.clock = DateTime.now;
    });
    tearDown(() {
      demo.dispose();
      CatalogStore.instance.catalog = GroupCatalog.empty;
    });

    // Jede Zeile nennt Befehl → Rückmeldung.
    final rows = find.textContaining(' → ');

    testWidgets('breites Fenster: die Rangliste läuft in drei Spalten bis in die rechte Hälfte', (tester) async {
      await pumpWindow(tester, ReactionTimesScreen(log: demo), wideWindow);
      final columns = columnsOf(tester, rows).toList()..sort();
      expect(columns, hasLength(3));
      expect(columns.last, greaterThan(wideWindow.width / 2));
      // Spaltenweise: die erste Spalte ist gefüllt, bevor die zweite beginnt.
      final first = tester.getTopLeft(rows.at(0));
      final second = tester.getTopLeft(rows.at(1));
      expect(second.dx, first.dx);
      expect(second.dy, greaterThan(first.dy));
    });

    testWidgets('Telefon: eine Spalte, auch bei doppelter Schrift ohne Überlauf', (tester) async {
      for (final scale in [1.0, 2.0]) {
        await pumpWindow(tester, ReactionTimesScreen(log: demo), phoneWindow, textScale: scale);
        expect(columnsOf(tester, rows), hasLength(1), reason: 'Schrift $scale');
      }
      // Dazwischen (Tablet hochkant) mit großer Schrift: keine Spalte wird zu schmal.
      await pumpWindow(tester, ReactionTimesScreen(log: demo), const Size(800, 1000), textScale: 2);
    });
  });
}
