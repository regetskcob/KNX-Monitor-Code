import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/plan.dart';
import 'package:knx_monitor/model/tour.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/tour_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Einführung: Kapitel je Stufe, ohne Kaufweg alles; jede Karte rendert am
// Telefon und am Tablet. Bilder zur Sichtkontrolle nach build/tour-shots/:
//   TOUR_SHOTS=1 flutter test test/tour_test.dart
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
  final shots = Platform.environment['TOUR_SHOTS'] != null;
  // Mit den echten Schriften: Die Ersatzschrift der Tests ist breiter.
  setUpAll(_loadFonts);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TourProgress.instance.reset();
  });

  group('Kapitel nach Stufe', () {
    test('ohne Kaufweg (Add-on, Linux): alle drei, keine Karte für mehr', () {
      final steps = tourSteps(Tier.free, purchasable: false);
      expect({for (final st in steps) ?st.chapter}, TourChapter.values.toSet());
      expect(steps.where((st) => st.more), isEmpty);
      expect(steps.last.ready, isTrue);
    });

    test('Store, Free: nur Grundlagen, dann was Plus und Pro bringen', () {
      final steps = tourSteps(Tier.free, purchasable: true);
      expect({for (final st in steps) ?st.chapter}, {TourChapter.basics});
      expect(steps.where((st) => st.more), hasLength(1));
    });

    test('Store, Plus: Grundlagen und Auswertung; Pro: alles ohne Karte für mehr', () {
      expect(
        {for (final st in tourSteps(Tier.plus, purchasable: true)) ?st.chapter},
        {TourChapter.basics, TourChapter.analysis},
      );
      final pro = tourSteps(Tier.pro, purchasable: true);
      expect({for (final st in pro) ?st.chapter}, TourChapter.values.toSet());
      expect(pro.where((st) => st.more), isEmpty);
    });

    test('nach einem Upgrade beginnt sie beim neuen Kapitel und merkt sich Gesehenes', () async {
      final progress = TourProgress.instance;
      await progress.markSeen(TourChapter.basics);
      final steps = tourSteps(Tier.plus, purchasable: true);
      expect(steps[tourStart(steps, progress)].chapter, TourChapter.analysis);
      expect(progress.unseen(Tier.plus, purchasable: true), [TourChapter.analysis]);
      // Ganz gesehen: wieder von vorn.
      await progress.markSeen(TourChapter.analysis);
      expect(tourStart(steps, progress), 0);
      // Gespeichert.
      progress.reset();
      await progress.load();
      expect(progress.seen(TourChapter.analysis), isTrue);
    });
  });

  for (final (name, size) in [('phone', Size(393, 852)), ('ipad', Size(1180, 820))]) {
    testWidgets('alle Karten rendern ($name)', (tester) async {
      final own = CatalogStore.instance.catalog = GroupCatalog.empty;
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final steps = tourSteps(Tier.pro, purchasable: false);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: TourScreen(steps: steps),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      // Während der Einführung das Demo-Haus.
      expect(CatalogStore.instance.catalog.groups, isNotEmpty);
      for (var i = 0; i < steps.length; i++) {
        if (shots) {
          await expectLater(
            find.byType(TourScreen),
            matchesGoldenFile('../build/tour-shots/${name}_${(i + 1).toString().padLeft(2, '0')}.png'),
          );
        }
        if (i + 1 < steps.length) {
          await tester.tap(find.widgetWithText(FilledButton, s.tourNext));
          // Das Blättern ist animiert: ein Frame startet, der nächste endet.
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
        }
      }
      expect(find.text(s.tourOpenDemo), findsOneWidget);
      // Alle Kapitel gesehen.
      expect(TourProgress.instance.unseen(Tier.pro, purchasable: false), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      // Das eigene Projekt ist zurück.
      expect(identical(CatalogStore.instance.catalog, own), isTrue);
    });
  }
}
