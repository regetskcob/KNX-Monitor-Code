import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/chart_templates.dart';
import 'package:knx_monitor/model/template_gallery.dart';
import 'package:knx_monitor/model/template_rules.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/template_gallery_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_storage.dart';

/// Liest die echten Dateien, optional mit Ersatz für einzelne Pfade.
class _FileBundle extends CachingAssetBundle {
  _FileBundle([this.overrides = const {}]);

  final Map<String, String> overrides;

  @override
  Future<ByteData> load(String key) async {
    if (overrides[key] case final text?) return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
    final file = File(key);
    if (!file.existsSync()) throw FlutterError('fehlt: $key');
    return ByteData.sublistView(file.readAsBytesSync());
  }
}

GroupInfo _g(String address, String name, {String? path, Dpt? dpt}) =>
    GroupInfo(address: parseGroup(address)!, name: name, path: path, dpt: dpt);

void main() {
  test('Jede Datei steht im Index, ist gültig und zweisprachig', () async {
    final files = Directory(galleryAssets).listSync().whereType<File>().map((f) => f.uri.pathSegments.last).toSet();
    final index = (jsonDecode(File('$galleryAssets/index.json').readAsStringSync()) as List).cast<String>();
    expect(index.toSet(), files.difference({'index.json'}), reason: 'Index und Ordner stimmen überein');

    final gallery = await loadTemplateGallery(bundle: _FileBundle());
    expect(gallery.length, index.length, reason: 'alle lesbar');
    expect(gallery.map((t) => t.id).toSet().length, gallery.length);
    for (final t in gallery) {
      for (final language in ['de', 'en']) {
        expect(t.titles[language], isNotEmpty, reason: '${t.id} $language');
        expect(t.descriptions[language], isNotEmpty, reason: '${t.id} $language');
      }
      expect(t.tags, isNotEmpty);
      for (final series in t.rule.series) {
        // Rollen statt Adressen: nur bekannte Rollen oder Kennzahlen.
        if (series.role case final role?) expect(chartRoleNames, contains(role), reason: t.id);
        expect(series.role != null || series.metric != null, isTrue);
      }
      expect(jsonEncode(t.rule.toJson()), isNot(matches(RegExp(r'\d+/\d+/\d+'))), reason: 'keine Adressen');
    }
  });

  test('Kaputte oder fehlende Dateien fallen weg, nichts stürzt ab', () async {
    final bundle = _FileBundle({
      '$galleryAssets/index.json': '["energie.json","kaputt.json","fehlt_wirklich.json","fremd.json"]',
      '$galleryAssets/kaputt.json': '{nein',
      '$galleryAssets/fremd.json': '{"format":"anders"}',
    });
    expect((await loadTemplateGallery(bundle: bundle)).map((t) => t.id), ['energie']);
    expect(await loadTemplateGallery(bundle: _FileBundle({'$galleryAssets/index.json': 'kaputt'})), isEmpty);
  });

  test('Suche in Titel, Beschreibung und Stichwörtern, je Sprache', () async {
    final gallery = await loadTemplateGallery(bundle: _FileBundle());
    List<String> find(String q, String lang) => [
      for (final t in gallery)
        if (t.matches(q, lang)) t.id,
    ];
    expect(find('', 'de'), hasLength(gallery.length));
    expect(find('RAUMKLIMA', 'de'), ['raumklima']);
    expect(find('room climate', 'en'), ['raumklima']);
    expect(find('jalousie', 'de'), ['beschattung']);
    expect(find('gibtsnicht', 'de'), isEmpty);
  });

  test('Anwenden auf ein Projekt über die vorhandene Logik', () async {
    final gallery = await loadTemplateGallery(bundle: _FileBundle());
    final climate = gallery.firstWhere((t) => t.id == 'raumklima');
    final groups = {
      for (final g in [
        _g('3/0/0', 'Temperatur Ist EG Küche', dpt: const Dpt(9, 1)),
        _g('3/1/0', 'Sollwert EG Küche', dpt: const Dpt(9, 1)),
      ])
        g.address: g,
    };
    final out = applyRule(climate.ruleIn('de'), groups, const {}, dptOf: (a) => groups[a]?.dpt);
    expect(out, hasLength(1));
    expect(out.single.ids, [parseGroup('3/0/0'), parseGroup('3/1/0')]);
    final bus = gallery.firstWhere((t) => t.id == 'busgesundheit');
    expect(applyRule(bus.ruleIn('de'), const {}, const {}, dptOf: (_) => null).single.ids, [-1, -2]);
  });

  test('Die Galerie kennt kein Netz', () {
    for (final file in ['lib/model/template_gallery.dart', 'lib/ui/template_gallery_screen.dart']) {
      final source = File(file).readAsStringSync();
      for (final banned in ['package:http', 'dart:io', 'supabase', 'https://', 'http://']) {
        expect(source.contains(banned), isFalse, reason: '$file: $banned');
      }
    }
  });

  testWidgets('Suchen und übernehmen legt die Vorlage in die Bibliothek', (tester) async {
    SharedPreferences.setMockInitialValues({});
    AppStorage.instance = MemoryStorage();
    CustomTemplates.instance.reset();
    await CatalogStore.instance.reload();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: TemplateGalleryScreen(bundle: _FileBundle()),
      ),
    );
    for (var i = 0; i < 20 && find.byType(TextField).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.enterText(find.byType(TextField), 'wetterstation');
    await tester.pump();
    expect(find.textContaining('Findet in diesem Projekt'), findsOneWidget);
    await tester.tap(find.text('Übernehmen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(CustomTemplates.instance.rules.map((r) => r.name), ['Wetterstation']);
    expect(find.text('Übernommen'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
