import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/week_summary.dart';
import 'package:knx_monitor/model/week_summary_prefs.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/week_summary_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answer of `/api/summary` as the server writes it (shortened).
Map<String, Object?> sample({List<Map<String, Object?>>? findings}) => {
  'v': 1,
  'days': 7,
  'telegrams': 193600,
  'per_day_mean': 27657,
  'repeats': 0,
  'load_mean_pct': 0.76,
  'load_max_pct': 14.9,
  'availability_pct': 95.3,
  'state': 'ok',
  'findings':
      findings ??
      [
        {
          'kind': 'clocks',
          'severity': 'info',
          'groups': ['8/0/0', '8/0/1', '8/0/2'],
          'senders': ['1.1.35', '1.1.36'],
          'share': 15.0,
        },
        {
          'kind': 'multi_responders',
          'severity': 'info',
          'count': 3,
          'groups': [
            {
              'group': '5/0/0',
              'name': 'Alarm EG',
              'devices': ['1.1.59', '1.1.110'],
            },
            {'group': '5/0/1', 'name': 'Alarm OG', 'devices': <String>[]},
          ],
        },
        {
          'kind': 'silent',
          'severity': 'info',
          'count': 1,
          'devices': [
            {'address': '1.1.120', 'name': 'Binäreingang'},
          ],
        },
        {
          'kind': 'unknown_senders',
          'severity': 'info',
          'senders': ['15.15.255'],
        },
        {'kind': 'from_a_newer_server', 'severity': 'info'},
      ],
};

void main() {
  setUp(() => LocaleController.instance.debugSetLocale(const Locale('de')));

  test('findings in words; unknown kinds of newer servers are left out', () {
    final w = WeekSummary.fromJson(sample());
    expect(w.findings.map((f) => f.kind), ['clocks', 'multi_responders', 'silent', 'unknown_senders']);
    expect(w.findings.first.text, contains('1.1.35, 1.1.36'));
    expect(w.findings.first.text, contains('15 %'));
    expect(w.findings[1].text, contains('5/0/0 Alarm EG, 5/0/1 Alarm OG'));
    expect(w.findings[1].text, contains('(3 Adressen)'));
    expect(w.findings[2].text, 'Ohne Telegramm: 1.1.120 Binäreingang.');
    expect(w.warn, isFalse);
    expect(w.headline, contains('4 Hinweise'));
  });

  test('a warning turns the headline', () {
    final w = WeekSummary.fromJson(
      sample(
        findings: [
          {'kind': 'disconnected', 'severity': 'warn', 'count': 2, 'minutes': 7},
        ],
      ),
    );
    expect(w.warn, isTrue);
    expect(w.headline, s.weekSumWarn);
    expect(w.findings.single.text, 'Die Busverbindung brach 2-mal ab, zusammen 7 min.');
  });

  Widget app(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('de'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('card: figures, three findings, the rest behind "more"', (tester) async {
    await tester.pumpWidget(app(WeekSummaryCard(load: () async => sample())));
    await tester.pumpAndSettle();
    expect(find.text('Letzte 7 Tage'), findsOneWidget);
    expect(find.text('27.657'), findsOneWidget);
    expect(find.text('95,3 %'), findsOneWidget);
    expect(find.textContaining('Absender nicht im Projekt'), findsNothing);
    await tester.tap(find.text('1 weitere'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Absender nicht im Projekt'), findsOneWidget);
  });

  group('room in the overview', () {
    final prefs = WeekSummaryPrefs.instance;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      prefs.debugReset();
    });
    tearDown(prefs.debugReset);

    testWidgets('collapsed: title and headline stay, figures and findings go', (tester) async {
      await tester.pumpWidget(app(WeekSummaryCard(load: () async => sample())));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Einklappen'));
      await tester.pumpAndSettle();
      expect(find.text('Letzte 7 Tage'), findsOneWidget);
      expect(find.text('27.657'), findsNothing);
      expect(find.text('1 weitere'), findsNothing);
      expect(prefs.collapsed, isTrue);
      await tester.tap(find.byTooltip('Aufklappen'));
      await tester.pumpAndSettle();
      expect(find.text('27.657'), findsOneWidget);
    });

    testWidgets('"not this week" hides it until next Monday', (tester) async {
      prefs.clock = () => DateTime(2026, 11, 10, 15);
      await tester.pumpWidget(app(WeekSummaryCard(load: () async => sample())));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Mehr'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diese Woche nicht mehr anzeigen'));
      await tester.pumpAndSettle();
      expect(find.text('Letzte 7 Tage'), findsNothing);
      expect(prefs.show, isTrue);
      prefs.clock = () => DateTime(2026, 11, 15, 23, 59);
      expect(prefs.visible, isFalse, reason: 'Sunday is still this week');
      prefs.clock = () => DateTime(2026, 11, 16, 0, 1);
      expect(prefs.visible, isTrue, reason: 'Monday brings it back');
    });

    testWidgets('"do not show again" switches it off; the switch brings it back at once', (tester) async {
      await tester.pumpWidget(app(WeekSummaryCard(load: () async => sample())));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Mehr'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nicht mehr anzeigen'));
      await tester.pumpAndSettle();
      expect(find.text('Letzte 7 Tage'), findsNothing);
      expect(prefs.show, isFalse);
      await prefs.hideThisWeek();
      await prefs.setShow(true);
      await tester.pumpAndSettle();
      expect(find.text('Letzte 7 Tage'), findsOneWidget);
    });

    test('a week is named by its Monday', () {
      expect(WeekSummaryPrefs.weekOf(DateTime(2026, 11, 9)), '2026-11-09');
      expect(WeekSummaryPrefs.weekOf(DateTime(2026, 11, 15, 23)), '2026-11-09');
      expect(WeekSummaryPrefs.weekOf(DateTime(2027, 1, 1)), '2026-12-28');
    });
  });

  testWidgets('card stays away when the server has no overview', (tester) async {
    await tester.pumpWidget(app(WeekSummaryCard(load: () async => throw Exception('404'))));
    await tester.pumpAndSettle();
    expect(find.text('Letzte 7 Tage'), findsNothing);
  });
}
