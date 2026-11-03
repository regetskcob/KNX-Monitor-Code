import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/plan.dart';
import 'package:knx_monitor/model/plan_source.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/plan_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Store-Ersatz: beginnt bei [tier], Kauf setzt die Stufe des Angebots.
class _FakeStore extends PlanSource {
  _FakeStore(this.tier);

  Tier tier;
  void Function(Tier)? listener;
  bool? beta = false;
  bool definite = false;

  @override
  Future<bool?> get betaUnlock async => beta;

  @override
  bool get lastAnswerDefinite => definite;

  static const offer = PlanOffer(id: 'pro_yearly', tier: Tier.pro, price: '99,00 €', period: OfferPeriod.yearly);

  @override
  bool get purchasable => true;

  @override
  Future<Tier> current() async => tier;

  @override
  Future<List<PlanOffer>> offers() async => const [offer];

  @override
  Future<Tier> buy(PlanOffer offer) async => tier = offer.tier;

  @override
  Future<Tier> restore() async => tier;

  @override
  set onChange(void Function(Tier tier) listener) => this.listener = listener;
}

void main() {
  final plan = Plan.instance;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Ohne Kaufweg ist alles frei', () async {
    await plan.load(using: const OpenPlanSource());
    await plan.refreshing;
    expect(plan.value, Tier.pro);
    expect(plan.purchasable, isFalse);
    expect(Feature.values.every(plan.allows), isTrue);
  });

  test('Add-on und Linux: alles frei, aber nur eine Anlage', () async {
    await plan.load(using: const OpenPlanSource(maxInstallations: 1));
    await plan.refreshing;
    expect(plan.value, Tier.pro);
    expect(plan.allows(Feature.acceptance), isTrue);
    expect(plan.allows(Feature.faultHunt), isTrue);
    expect(plan.maxInstallations, 1);
    expect(plan.installationsCapped, isTrue);

    await plan.load(using: const OpenPlanSource());
    await plan.refreshing;
    expect(plan.maxInstallations, greaterThan(3));
    expect(plan.installationsCapped, isFalse);
  });

  test('Projekt-Abgleich gehört zu Plus', () {
    expect(Feature.projectCheck.tier, Tier.plus);
  });

  test('Stufen und Grenzen', () async {
    final store = _FakeStore(Tier.free);
    await plan.load(using: store);
    await plan.refreshing;
    expect(plan.allows(Feature.charts), isFalse);
    expect(plan.maxInstallations, 1);
    expect(plan.maxRecordings, 1);
    expect(plan.maxHistoryDays, 0);
    expect(plan.liveWindow, const Duration(minutes: 60));

    store.listener!(Tier.plus);
    await pumpEventQueue();
    expect(plan.allows(Feature.charts), isTrue);
    expect(plan.allows(Feature.diagnostics), isFalse);
    expect(plan.maxInstallations, 3);
    expect(plan.maxHistoryDays, greaterThan(365));
    expect(plan.liveWindow, isNull);

    await plan.buy(_FakeStore.offer);
    expect(plan.allows(Feature.diagnostics), isTrue);
  });

  test('Schonfrist: bezahlte Stufe bleibt eine Woche, wenn der Store plötzlich weniger meldet', () async {
    var now = DateTime(2026, 11, 1);
    Plan.clock = () => now;
    addTearDown(() => Plan.clock = DateTime.now);
    final store = _FakeStore(Tier.pro);
    await plan.load(using: store);
    await plan.refreshing;
    expect(plan.value, Tier.pro);

    // Store meldet Free (Konto gewechselt, Verlängerung nicht angekommen).
    now = now.add(const Duration(days: 3));
    store.listener!(Tier.free);
    await pumpEventQueue();
    expect(plan.value, Tier.pro);

    // Neustart innerhalb der Frist: weiter Pro.
    store.tier = Tier.free;
    await plan.load(using: store);
    await plan.refreshing;
    expect(plan.value, Tier.pro);

    // Nach Ablauf der Frist gilt der Store.
    now = now.add(Plan.paidGrace);
    store.listener!(Tier.free);
    await pumpEventQueue();
    expect(plan.value, Tier.free);
  });

  test('Schonfrist gilt nicht bei zurückgedrehter Uhr', () async {
    var now = DateTime(2026, 11, 1);
    Plan.clock = () => now;
    addTearDown(() => Plan.clock = DateTime.now);
    final store = _FakeStore(Tier.pro);
    await plan.load(using: store);
    await plan.refreshing;
    now = DateTime(2026, 1, 1);
    store.listener!(Tier.free);
    await pumpEventQueue();
    expect(plan.value, Tier.free);
  });

  test('Im Demo-Haus ist alles frei, die gekaufte Stufe bleibt', () async {
    await plan.load(using: _FakeStore(Tier.free));
    await plan.refreshing;
    plan.demo = true;
    addTearDown(() => plan.demo = false);
    expect(plan.allows(Feature.diagnostics), isTrue);
    expect(plan.liveWindow, isNull);
    expect(plan.value, Tier.free);
  });

  group('Vom freien Build in die erste Bezahlversion', () {
    var now = DateTime(2027, 3, 1);
    setUp(() {
      now = DateTime(2027, 3, 1);
      Plan.clock = () => now;
    });
    tearDown(() => Plan.clock = DateTime.now);

    Future<void> start(PlanSource source) async {
      await plan.load(using: source);
      await plan.refreshing;
    }

    Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

    final legacy = <String, Object>{
      'plan_tier': 'pro',
      'plan_paid_tier': 'pro',
      'plan_paid_seen': '2027-02-28T10:00:00.000',
    };

    test('Ein Build ohne Kaufweg speichert nichts als bezahlt', () async {
      await start(const OpenPlanSource());
      final p = await prefs();
      expect(plan.value, Tier.pro);
      expect(p.getString('plan_paid_tier'), isNull);
      expect(p.getString('plan_tier'), isNull);
    });

    test('Alte Stufe ohne Kauf fällt weg, 30 Tage Pro mit Hinweis und Enddatum', () async {
      SharedPreferences.setMockInitialValues(legacy);
      await start(_FakeStore(Tier.free));
      final p = await prefs();
      expect(p.getString('plan_paid_tier'), isNull);
      expect(plan.value, Tier.pro);
      expect(plan.bought, Tier.free);
      expect(plan.gifted, isTrue);
      expect(plan.purchasable, isTrue);
      expect(plan.openUntil, now.add(Plan.openTransition));
      expect(plan.notice, PlanNotice.openStarted);
    });

    test('Die Frist zählt ab dem ersten Start und läuft nicht neu an', () async {
      SharedPreferences.setMockInitialValues(legacy);
      await start(_FakeStore(Tier.free));
      final end = plan.openUntil;
      await plan.acknowledgeNotice();
      now = now.add(const Duration(days: 29));
      await start(_FakeStore(Tier.free));
      expect(plan.openUntil, end);
      expect(plan.value, Tier.pro);
      expect(plan.notice, isNull);
    });

    test('Danach Free und einmal eine Meldung', () async {
      SharedPreferences.setMockInitialValues(legacy);
      await start(_FakeStore(Tier.free));
      await plan.acknowledgeNotice();
      now = now.add(Plan.openTransition);
      await start(_FakeStore(Tier.free));
      expect(plan.value, Tier.free);
      expect(plan.openUntil, isNull);
      expect(plan.notice, PlanNotice.openEnded);
      await plan.acknowledgeNotice();
      await start(_FakeStore(Tier.free));
      expect(plan.value, Tier.free);
      expect(plan.notice, isNull);
    });

    test('Auch nach einem neuen freien Build (ohne alte Stufe) gilt die Frist', () async {
      await start(const OpenPlanSource());
      await start(_FakeStore(Tier.free));
      expect(plan.openUntil, now.add(Plan.openTransition));
    });

    test('Wer kauft, behält die Stufe ohne Meldung', () async {
      SharedPreferences.setMockInitialValues(legacy);
      final store = _FakeStore(Tier.free);
      await start(store);
      await plan.acknowledgeNotice();
      await plan.buy(const PlanOffer(id: 'plus_yearly', tier: Tier.plus, price: '', period: OfferPeriod.yearly));
      expect(plan.bought, Tier.plus);
      expect(plan.openUntil, isNull);
      now = now.add(Plan.openTransition);
      await start(store);
      expect(plan.value, Tier.plus);
      expect(plan.notice, isNull);
    });

    test('Neue Nutzer und echte Käufer: keine Übergangszeit', () async {
      await start(_FakeStore(Tier.free));
      expect(plan.value, Tier.free);
      expect(plan.notice, isNull);

      SharedPreferences.setMockInitialValues({...legacy, 'plan_store_confirmed': true});
      await start(_Offline());
      expect(plan.value, Tier.pro);
      expect(plan.bought, Tier.pro);
      expect(plan.openUntil, isNull);
      expect((await prefs()).getString('plan_paid_tier'), 'pro');
    });

    test('In der Beta läuft die Frist noch nicht', () async {
      SharedPreferences.setMockInitialValues(legacy);
      await start(_FakeStore(Tier.free)..beta = true);
      expect(plan.openUntil, isNull);
      expect(plan.notice, isNull);
      now = now.add(const Duration(days: 200));
      await start(_FakeStore(Tier.free));
      expect(plan.openUntil, now.add(Plan.openTransition));
    });

    test('Zurückgedrehte Uhr verlängert die Frist nicht', () async {
      SharedPreferences.setMockInitialValues(legacy);
      await start(_FakeStore(Tier.free));
      now = now.subtract(const Duration(days: 60));
      await start(_FakeStore(Tier.free));
      expect(plan.value, Tier.free);
    });
  });

  group('Beta-Dankeschön', () {
    var now = DateTime(2026, 11, 1);
    setUp(() {
      now = DateTime(2026, 11, 1);
      Plan.clock = () => now;
    });
    tearDown(() => Plan.clock = DateTime.now);

    Future<void> start(bool? beta) async {
      await plan.load(using: _FakeStore(Tier.free)..beta = beta);
      await plan.refreshing;
    }

    test('Fehler bei der Beta-Erkennung startet es nicht', () async {
      SharedPreferences.setMockInitialValues({'plan_beta_tester': true, 'plan_beta_last': true});
      await start(null);
      expect(plan.rewardUntil, isNull);
      // Beim letzten Stand bleiben: weiter Beta.
      expect(plan.beta, isTrue);
      expect(plan.value, Tier.pro);
    });

    test('Bearbeitetes Ende weit in der Zukunft zählt nicht und startet nichts neu', () async {
      SharedPreferences.setMockInitialValues({
        'plan_beta_tester': true,
        'plan_beta_reward_until': now.add(const Duration(days: 91)).toIso8601String(),
      });
      await start(false);
      expect(plan.rewardActive, isFalse);
      expect(plan.value, Tier.free);
      expect(plan.rewardUntil, now.add(const Duration(days: 91)));
    });

    test('Nicht über das feste Ende hinaus', () async {
      now = Plan.rewardHardEnd.subtract(const Duration(days: 10));
      SharedPreferences.setMockInitialValues({'plan_beta_tester': true});
      await start(false);
      expect(plan.rewardUntil, Plan.rewardHardEnd);
      expect(plan.rewardActive, isTrue);

      now = Plan.rewardHardEnd.add(const Duration(days: 1));
      SharedPreferences.setMockInitialValues({
        'plan_beta_tester': true,
        'plan_beta_reward_until': now.add(const Duration(days: 30)).toIso8601String(),
      });
      await start(false);
      expect(plan.rewardActive, isFalse);
    });
  });

  group('Schonfrist bei eindeutiger Antwort', () {
    var now = DateTime(2026, 11, 1);
    setUp(() {
      now = DateTime(2026, 11, 1);
      Plan.clock = () => now;
    });
    tearDown(() => Plan.clock = DateTime.now);

    test('Erstattet: drei Tage ab der ersten Antwort, dann Free', () async {
      final store = _FakeStore(Tier.pro);
      await plan.load(using: store);
      await plan.refreshing;
      now = now.add(const Duration(days: 10));
      store
        ..tier = Tier.free
        ..definite = true;
      store.listener!(Tier.free);
      await pumpEventQueue();
      expect(plan.value, Tier.pro);

      now = now.add(const Duration(days: 2));
      await plan.load(using: store);
      await plan.refreshing;
      expect(plan.value, Tier.pro);

      now = now.add(const Duration(days: 1));
      await plan.load(using: store);
      await plan.refreshing;
      expect(plan.value, Tier.free);
    });

    test('Nicht eindeutig: die 30 Tage bleiben', () async {
      final store = _FakeStore(Tier.pro);
      await plan.load(using: store);
      await plan.refreshing;
      now = now.add(const Duration(days: 29));
      store.listener!(Tier.free);
      await pumpEventQueue();
      expect(plan.value, Tier.pro);
    });

    test('Store nicht erreichbar: die 30 Tage bleiben', () async {
      final store = _FakeStore(Tier.pro);
      await plan.load(using: store);
      await plan.refreshing;
      now = now.add(const Duration(days: 29));
      await plan.load(using: _Offline());
      await plan.refreshing;
      expect(plan.value, Tier.pro);
    });

    test('Erneut bestätigt: Die Frist beginnt wieder von vorn', () async {
      final store = _FakeStore(Tier.pro)..definite = true;
      await plan.load(using: store);
      await plan.refreshing;
      now = now.add(const Duration(days: 1));
      store.listener!(Tier.free);
      await pumpEventQueue();
      store.listener!(Tier.pro);
      await pumpEventQueue();
      now = now.add(const Duration(days: 5));
      store.listener!(Tier.free);
      await pumpEventQueue();
      expect(plan.value, Tier.pro);
    });
  });

  test('Warten auf Freigabe wird gemerkt, bis die Stufe kommt', () async {
    final store = _Pending();
    await plan.load(using: store);
    await plan.refreshing;
    await expectLater(plan.buy(_FakeStore.offer), throwsA(isA<PlanAwaitingApproval>()));
    expect(plan.awaitingApproval, isTrue);
    expect(plan.value, Tier.free);
    store.listener!(Tier.pro);
    await pumpEventQueue();
    expect(plan.awaitingApproval, isFalse);
    expect(plan.value, Tier.pro);
  });

  test('Ohne Kaufweg im Release: Free', () async {
    await plan.load(using: const NoPlanSource());
    await plan.refreshing;
    expect(plan.value, Tier.free);
    expect(plan.purchasable, isFalse);
    expect(plan.free, isFalse);
  });

  test('Live-Log mit Zeitfenster behält nur die letzte Stunde', () {
    final start = DateTime(2026, 10, 14, 12);
    Telegram at(int minute) => Telegram(
      time: start.add(Duration(minutes: minute)),
      source: 0x1101,
      destination: 0x0A03,
      type: TelegramType.write,
      data: Uint8List.fromList([1]),
      isSmall: true,
    );
    final log = TelegramLog(maxEntries: 5000)..maxAge = const Duration(minutes: 60);
    log.addAll([for (var m = 0; m <= 90; m += 10) at(m)]);
    expect(log.log.first.time, start.add(const Duration(minutes: 30)));
    expect(log.log.length, 7);
  });

  test('TestFlight: alles frei, versteckter Schalter, Dankeschön nach dem Start', () async {
    final now = DateTime(2026, 11, 1);
    Plan.clock = () => now;
    addTearDown(() => Plan.clock = DateTime.now);

    await plan.load(using: _FakeStore(Tier.free)..beta = true);
    await plan.refreshing;
    expect(plan.value, Tier.pro);
    expect(plan.purchasable, isFalse);

    await plan.setBetaStore(true);
    expect(plan.value, Tier.free);
    expect(plan.purchasable, isTrue);
    await plan.setBetaStore(false);

    // Dieselbe Installation, jetzt aus dem App Store.
    await plan.load(using: _FakeStore(Tier.free));
    await plan.refreshing;
    expect(plan.value, Tier.pro);
    expect(plan.rewardUntil, now.add(Plan.betaReward));

    Plan.clock = () => now.add(const Duration(days: 91));
    await plan.load(using: _FakeStore(Tier.free));
    await plan.refreshing;
    expect(plan.value, Tier.free);
  });

  test('Letzter Stand gilt sofort, auch wenn der Store nicht antwortet', () async {
    SharedPreferences.setMockInitialValues({'plan_tier': 'plus', 'plan_store_confirmed': true});
    await plan.load(using: _Offline());
    await plan.refreshing;
    expect(plan.value, Tier.plus);
  });

  testWidgets('Gesperrte Funktion öffnet die Bezahlseite, Kauf schaltet frei', (tester) async {
    await plan.load(using: _FakeStore(Tier.free));
    await plan.refreshing;
    // Hoch genug, dass beide Stufen ohne Scrollen passen.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await unlock(context, Feature.diagnostics),
            child: const Text('Diagnose'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Diagnose'));
    await tester.pumpAndSettle();
    expect(find.text('Plus und Pro'), findsOneWidget);
    expect(find.textContaining('gehört zu Pro'), findsOneWidget);

    await tester.tap(find.text('99,00 € pro Jahr'));
    await tester.pumpAndSettle();
    expect(find.text('Danke! Pro ist freigeschaltet.'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}

class _Pending extends _FakeStore {
  _Pending() : super(Tier.free);

  @override
  Future<Tier> buy(PlanOffer offer) => Future.error(const PlanAwaitingApproval());
}

class _Offline extends _FakeStore {
  _Offline() : super(Tier.free);

  @override
  Future<Tier> current() => Future.error(StateError('offline'));
}
