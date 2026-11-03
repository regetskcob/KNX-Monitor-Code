@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/plan.dart';
import 'package:knx_monitor/model/plan_source.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/plan_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Prüfungs-Screenshots der Bezahlseite für App Store Connect (je Produkt einer,
// iPhone 6,9″ = 1320 × 2868) nach store/ios/review/ (nicht im Repo).
// Nur auf Wunsch:
//   STORE_SHOTS=1 flutter test --tags golden --update-goldens test/review_shots_test.dart
// Preise wie in store/iap.md; bei neuen Preisen hier anpassen.

const _prices = {
  'de': (plusYear: '24,99 €', plusOnce: '79,00 €', proYear: '149,00 €', proMonth: '14,99 €'),
  'en': (plusYear: '€24.99', plusOnce: '€79.00', proYear: '€149.00', proMonth: '€14.99'),
};

class _Store extends PlanSource {
  _Store(this.lang);

  final String lang;

  @override
  bool get purchasable => true;

  @override
  Future<Tier> current() async => Tier.free;

  @override
  Future<List<PlanOffer>> offers() async {
    final p = _prices[lang]!;
    return [
      PlanOffer(id: 'plus_yearly', tier: Tier.plus, price: p.plusYear, period: OfferPeriod.yearly),
      PlanOffer(id: 'plus_lifetime', tier: Tier.plus, price: p.plusOnce, period: OfferPeriod.lifetime),
      PlanOffer(id: 'pro_yearly', tier: Tier.pro, price: p.proYear, period: OfferPeriod.yearly, trialDays: 14),
      PlanOffer(id: 'pro_monthly', tier: Tier.pro, price: p.proMonth, period: OfferPeriod.monthly),
    ];
  }

  @override
  Future<Tier> buy(PlanOffer offer) async => offer.tier;

  @override
  Future<Tier> restore() async => Tier.free;
}

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
  final skip = Platform.environment['STORE_SHOTS'] == null ? 'nur mit STORE_SHOTS=1' : null;
  setUpAll(_loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => LocaleController.instance.debugSetLocale(const Locale('de')));

  for (final lang in _prices.keys) {
    // Plus- und Pro-Produkte zeigen dieselbe Seite: beide Stufen mit allen Preisen.
    testWidgets('review_plan_$lang', skip: skip != null, (tester) async {
      LocaleController.instance.debugSetLocale(Locale(lang));
      await Plan.instance.load(using: _Store(lang));
      await Plan.instance.refreshing;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      const size = Size(440, 956);
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: size, devicePixelRatio: 3, padding: EdgeInsets.only(top: 62, bottom: 34)),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            locale: Locale(lang),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const PlanScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('../store/ios/review/plan_$lang.png'));
      // Zweites Bild für die Plus-Produkte: bis zu den Plus-Preisen gescrollt.
      await tester.dragUntilVisible(
        find.textContaining(lang == 'de' ? 'einmalig' : 'one-time'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.pump(const Duration(seconds: 1));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('../store/ios/review/plan_plus_$lang.png'));
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
