import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/plan.dart';
import 'package:knx_monitor/model/plan_source.dart';
import 'package:knx_monitor/platform/license_plan.dart';
import 'package:knx_monitor/theme/app_icons.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/plan_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'window.dart';

class _Store extends PlanSource {
  _Store({this.list = const [], this.failing = false, this.awaiting = false});

  final List<PlanOffer> list;
  final bool failing;
  final bool awaiting;

  @override
  bool get purchasable => true;

  @override
  Future<Tier> current() async => Tier.free;

  @override
  Future<List<PlanOffer>> offers() async => failing ? throw StateError('offline') : list;

  @override
  Future<Tier> buy(PlanOffer offer) async => awaiting ? throw const PlanAwaitingApproval() : offer.tier;

  @override
  Future<Tier> restore() async => Tier.free;
}

const _pro = PlanOffer(id: 'pro_yearly', tier: Tier.pro, price: '99,00 €', period: OfferPeriod.yearly);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => Plan.clock = DateTime.now);

  Future<double> top(WidgetTester tester, Tier tier) async => tester.getTopLeft(find.text(tierName(tier)).first).dy;

  Future<void> open(WidgetTester tester, PlanScreen screen) async {
    tester.view.physicalSize = const Size(393, 2400) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: screen,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('Gesperrtes Plus-Werkzeug: Plus zuerst, Pro darunter', (tester) async {
    await open(tester, const PlanScreen(reason: '„Home Assistant“ gehört zu Plus.'));
    expect(await top(tester, Tier.plus), lessThan(await top(tester, Tier.pro)));
  });

  testWidgets('Aus dem Menü: Pro zuerst', (tester) async {
    await open(tester, const PlanScreen());
    expect(await top(tester, Tier.pro), lessThan(await top(tester, Tier.plus)));
  });
  group('Keine Angebote', () {
    Future<void> load(PlanSource source) async {
      await Plan.instance.load(using: source);
      await Plan.instance.refreshing;
    }

    testWidgets('Windows ohne Kaufseite: „noch nicht verfügbar“', (tester) async {
      await tester.runAsync(() => load(_Store()));
      await open(tester, const PlanScreen());
      expect(find.textContaining('noch nicht verfügbar'), findsOneWidget);
    });

    testWidgets('Build ohne Kaufweg: ebenso', (tester) async {
      await tester.runAsync(() => load(const NoPlanSource()));
      await open(tester, const PlanScreen());
      expect(find.textContaining('noch nicht verfügbar'), findsOneWidget);
    });

    testWidgets('Störung bleibt „nicht erreichbar“', (tester) async {
      await tester.runAsync(() => load(_Store(failing: true)));
      await open(tester, const PlanScreen());
      expect(find.textContaining('nicht erreichbar'), findsOneWidget);
      expect(find.textContaining('noch nicht verfügbar'), findsNothing);
    });

    testWidgets('Bewusst frei: kein Hinweis', (tester) async {
      await tester.runAsync(() => load(const OpenPlanSource()));
      await open(tester, const PlanScreen());
      expect(find.textContaining('noch nicht verfügbar'), findsNothing);
    });
  });

  testWidgets('Übergangszeit: Kaufknöpfe sichtbar, Hinweis mit Enddatum', (tester) async {
    Plan.clock = () => DateTime(2027, 3, 1);
    SharedPreferences.setMockInitialValues({'plan_tier': 'pro', 'plan_paid_tier': 'pro'});
    await tester.runAsync(() async {
      await Plan.instance.load(using: _Store(list: const [_pro]));
      await Plan.instance.refreshing;
    });
    expect(Plan.instance.value, Tier.pro);
    await open(tester, const PlanScreen());
    expect(find.textContaining('Bisher war alles frei'), findsOneWidget);
    expect(find.textContaining('31.03.'), findsOneWidget);
    expect(find.text('99,00 € pro Jahr'), findsOneWidget);
  });

  testWidgets('Kauf wartet auf Freigabe: eigene Meldung statt Fehler', (tester) async {
    await tester.runAsync(() async {
      await Plan.instance.load(using: _Store(list: const [_pro], awaiting: true));
      await Plan.instance.refreshing;
    });
    await open(tester, const PlanScreen());
    await tester.tap(find.text('99,00 € pro Jahr'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('wartet noch auf Freigabe'), findsWidgets);
    expect(find.textContaining('fehlgeschlagen'), findsNothing);
  });

  group('Einmalige Meldung beim Start', () {
    Future<void> gate(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const PlanNoticeGate(child: Scaffold()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Am Anfang und am Ende je einmal', (tester) async {
      var now = DateTime(2027, 3, 1);
      Plan.clock = () => now;
      SharedPreferences.setMockInitialValues({'plan_tier': 'pro'});
      Future<void> start() => tester.runAsync(() async {
        await Plan.instance.load(using: _Store());
        await Plan.instance.refreshing;
      });
      await start();
      await gate(tester);
      expect(find.textContaining('Bisher war alles frei'), findsOneWidget);
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));

      await start();
      await gate(tester);
      expect(find.textContaining('Bisher war alles frei'), findsNothing);

      now = now.add(Plan.openTransition);
      await start();
      await tester.pumpAndSettle();
      expect(find.textContaining('Übergangszeit ist vorbei'), findsOneWidget);
    });
  });

  group('Lizenz (Windows ohne Konto)', () {
    Future<void> openWithLicense(WidgetTester tester) async {
      Plan.instance.source = LicensePlanSource(publicKey: 'kein-schluessel', fetch: (_) => Future.error('offline'));
      addTearDown(() => Plan.instance.source = const OpenPlanSource());
      await open(tester, const PlanScreen());
    }

    testWidgets('Eingabe statt Wiederherstellen', (tester) async {
      await openWithLicense(tester);
      expect(find.text('Lizenz eingeben'), findsOneWidget);
      expect(find.text('Käufe wiederherstellen'), findsNothing);
    });

    testWidgets('Falsche Lizenz: klare Meldung, Abbrechen passiert nichts', (tester) async {
      await openWithLicense(tester);
      await tester.tap(find.text('Lizenz eingeben'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      await tester.tap(find.text('Lizenz eingeben'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'KNX1.falsch.falsch');
      await tester.tap(find.text('Freischalten'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Diese Lizenz stimmt nicht'), findsOneWidget);
    });
  });

  group('Breite', () {
    const offers = [_pro, PlanOffer(id: 'plus_yearly', tier: Tier.plus, price: '19,00 €', period: OfferPeriod.yearly)];

    testWidgets('breites Fenster: Stufen nebeneinander, Punkte in Spalten, Kaufknöpfe auf einer Höhe', (tester) async {
      await tester.runAsync(() async {
        await Plan.instance.load(using: _Store(list: offers));
        await Plan.instance.refreshing;
      });
      await pumpWindow(tester, const PlanScreen(), wideWindow);
      await tester.pump(const Duration(seconds: 1));
      final pro = tester.getTopLeft(find.text('Pro'));
      final plus = tester.getTopLeft(find.text('Plus'));
      expect(plus.dy, pro.dy);
      expect(plus.dx, greaterThan(wideWindow.width / 2));
      // Punkte spaltenweise: der letzte Pro-Punkt steht rechts neben dem ersten, nicht 20 Zeilen tiefer.
      final first = tester.getTopLeft(find.text('Diagnose'));
      final last = tester.getTopLeft(find.text('Dazu alles aus Plus'));
      expect(last.dx, greaterThan(first.dx));
      expect(last.dx, lessThan(plus.dx));
      // Gleich hohe Karten: die Knöpfe beider Stufen enden auf einer Linie.
      expect(
        tester.getBottomLeft(find.text('19,00 € pro Jahr')).dy,
        tester.getBottomLeft(find.text('99,00 € pro Jahr')).dy,
      );
      await pumpWindow(tester, const PlanScreen(), wideWindow, textScale: 2);
      await tester.pump(const Duration(seconds: 1));
      // Nur Pro: eine Karte über die Breite.
      await pumpWindow(tester, const PlanScreen(reason: 'Anlass', need: Tier.pro), wideWindow);
      await tester.pump(const Duration(seconds: 1));
      expect(columnsOf(tester, find.byIcon(AppIcons.success)), hasLength(3));
    });

    testWidgets('Telefon und schmales Fenster: Stufen untereinander, Punkte in einer Spalte', (tester) async {
      await tester.runAsync(() async {
        await Plan.instance.load(using: _Store(list: offers));
        await Plan.instance.refreshing;
      });
      for (final (size, scale) in [(phoneWindow, 1.0), (phoneWindow, 2.0), (const Size(800, 1000), 1.0)]) {
        await pumpWindow(tester, const PlanScreen(), size, textScale: scale);
        await tester.pump(const Duration(seconds: 1));
        expect(columnsOf(tester, find.byIcon(AppIcons.success)), hasLength(1), reason: '$size, Schrift $scale');
      }
    });
  });
}
