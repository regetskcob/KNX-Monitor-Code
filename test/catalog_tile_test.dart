import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/catalog_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The hint "no group addresses" above the overview, as a new user without a project sees it.
/// On a 440 pt phone (iPhone Pro Max) its buttons stood beside the text and squeezed it to one
/// letter per line, which pushed the whole overview off the screen.
/// The real fonts: the test font is far wider, and this is about what fits.
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CatalogStore.instance.catalog = GroupCatalog.empty;
  });
  tearDown(() => LocaleController.instance.debugSetLocale(const Locale('de')));

  for (final language in ['de', 'en']) {
    for (final width in [320.0, 375.0, 440.0, 520.0, 700.0, 1100.0]) {
      testWidgets('Hinweis ohne Projekt, $language, $width pt: Text bleibt lesbar', (tester) async {
        await tester.runAsync(_loadFonts);
        LocaleController.instance.debugSetLocale(Locale(language));
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            locale: Locale(language),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [CatalogTile(onDismiss: () {}, onTeachIn: () {})],
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        // The title keeps at least a third of the tile and the tile stays a card, not a column.
        expect(tester.getSize(find.text(s.catalogNone)).width, greaterThan(100));
        expect(tester.getSize(find.byType(CatalogTile)).height, lessThan(320));
      });
    }
  }
}
