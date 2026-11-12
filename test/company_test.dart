import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:knx_monitor/export/pdf_export.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/company.dart';
import 'package:knx_monitor/model/plan.dart';
import 'package:knx_monitor/model/plan_source.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/company_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _png(int width, int height, {bool transparent = false}) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(200, 30, 30, transparent ? 0 : 255));
  return img.encodePng(image);
}

const _company = Company(
  name: 'Elektro Muster GmbH',
  address: 'Hauptstraße 1\n12345 Musterstadt',
  phone: '0123 456',
  email: 'info@example.org',
  website: 'example.org',
  vatId: 'DE123',
  registration: 'Handwerksrolle Musterstadt',
  technician: 'D. Elektro',
);

class _Store extends PlanSource {
  _Store(this.tier);
  final Tier tier;
  @override
  bool get purchasable => true;
  @override
  Future<Tier> current() async => tier;
  @override
  Future<List<PlanOffer>> offers() async => const [];
  @override
  Future<Tier> buy(PlanOffer offer) async => tier;
  @override
  Future<Tier> restore() async => tier;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Logo', () {
    test('kleines PNG bleibt in der Größe, wird RGBA', () {
      final out = img.decodePng(normalizeLogoImage(_png(120, 40)))!;
      expect((out.width, out.height), (120, 40));
      expect(out.numChannels, 4);
    });

    test('sehr breit und sehr hoch: passt in den Rahmen', () {
      final wide = img.decodePng(normalizeLogoImage(_png(6000, 40)))!;
      expect(wide.width, lessThanOrEqualTo(logoMaxWidth));
      expect(wide.height, greaterThanOrEqualTo(1));
      final tall = img.decodePng(normalizeLogoImage(_png(40, 3000)))!;
      expect(tall.height, lessThanOrEqualTo(logoMaxHeight));
      expect(tall.width, greaterThanOrEqualTo(1));
    });

    test('Transparenz bleibt erhalten', () {
      final out = img.decodePng(normalizeLogoImage(_png(50, 50, transparent: true)))!;
      expect(out.getPixel(10, 10).a, 0);
    });

    test('JPEG wird PNG', () {
      final jpeg = img.encodeJpg(img.Image(width: 300, height: 100));
      final out = normalizeLogoImage(jpeg);
      expect(img.PngDecoder().isValidFile(out), isTrue);
    });

    test('kaputte und leere Daten: FormatException', () {
      expect(() => normalizeLogoImage(Uint8List.fromList([1, 2, 3])), throwsFormatException);
      expect(() => normalizeLogoImage(Uint8List(0)), throwsFormatException);
      expect(() => normalizeLogoImage(Uint8List(logoMaxBytes + 1)), throwsFormatException);
    });

    test('SVG entsteht als PDF, kaputtes SVG wird abgelehnt', () async {
      const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 40"><rect width="300" height="40"/></svg>';
      final pdf = await svgLogoAsPdf(svg);
      expect(utf8.decode(pdf.sublist(0, 5)), '%PDF-');
      // Ohne viewBox, sehr breit: darf nicht scheitern.
      await svgLogoAsPdf('<svg xmlns="http://www.w3.org/2000/svg" width="9000" height="10"><circle r="3"/></svg>');
      await expectLater(svgLogoAsPdf('<svg><kaputt'), throwsFormatException);
      await expectLater(
        normalizeLogo(utf8.encode('kein svg'), 'logo.svg', raster: (_) async => _png(1, 1)),
        throwsFormatException,
      );
    });

    test('SVG wird gerastert und an den Rändern beschnitten', () async {
      final sheet = img.Image(width: 600, height: 200, numChannels: 4);
      img.fill(sheet, color: img.ColorRgba8(255, 255, 255, 255));
      img.fillRect(sheet, x1: 0, y1: 50, x2: 299, y2: 149, color: img.ColorRgba8(0, 0, 0, 255));
      final out = await normalizeLogo(
        utf8.encode('<svg xmlns="http://www.w3.org/2000/svg" width="3" height="1"/>'),
        'LOGO.SVG',
        raster: (_) async => img.encodePng(sheet),
      );
      final logo = img.decodePng(out)!;
      expect(logo.width, lessThan(600));
      expect(logo.height, lessThan(200));
    });
  });

  group('Letterhead', () {
    final telegrams = [
      Telegram(
        time: DateTime(2026, 10, 30),
        source: 0x1101,
        destination: 0x0801,
        type: TelegramType.write,
        data: Uint8List.fromList([1]),
        isSmall: true,
      ),
    ];

    test('ohne Firmennamen kein Briefkopf', () {
      expect(const Company(address: 'x').isSet, isFalse);
      expect(_company.isSet, isTrue);
      expect(_company.contactLine, '0123 456 · info@example.org · example.org');
      expect(_company.letterhead().addressLines, ['Hauptstraße 1', '12345 Musterstadt']);
      expect(_company.letterhead().author, 'Elektro Muster GmbH, D. Elektro');
    });

    test('kaputte Datei: Felder bleiben leer, nichts wirft', () {
      expect(Company.fromJson({'name': 3, 'phone': null, 'x': []}).isSet, isFalse);
    });

    test('Briefkopf steht im PDF, Verfasser in den Metadaten', () async {
      final plain = await buildPdf(TelegramPdf(telegrams));
      final pdf = await buildPdf(TelegramPdf(telegrams), letterhead: _company.letterhead(logo: _png(400, 100)));
      expect(pdf.length, greaterThan(plain.length));
      final text = latin1.decode(pdf);
      expect(text, contains('Elektro Muster'));
      expect(latin1.decode(plain), isNot(contains('Elektro Muster')));
    });

    test('ungewöhnliche Logos: breit, hoch, winzig, kaputt', () async {
      for (final logo in [
        normalizeLogoImage(_png(6000, 40)),
        normalizeLogoImage(_png(40, 3000)),
        normalizeLogoImage(_png(1, 1)),
        normalizeLogoImage(_png(100, 100, transparent: true)),
        Uint8List.fromList([9, 9, 9]),
      ]) {
        final pdf = await buildPdf(TelegramPdf(telegrams), letterhead: _company.letterhead(logo: logo));
        expect(utf8.decode(pdf.sublist(0, 5)), '%PDF-');
      }
    });

    test('lange Telegrammliste: Folgeseiten mit Briefkopf', () async {
      final many = [for (var i = 0; i < 200; i++) telegrams.first];
      final pdf = await buildPdf(TelegramPdf(many), letterhead: _company.letterhead(logo: _png(200, 50)));
      expect(utf8.decode(pdf.sublist(0, 5)), '%PDF-');
    });

    test('der Hintergrund-Isolate bekommt das Logo als Bytes', () async {
      Plan.instance.value = Tier.pro;
      CompanyStore.instance
        ..company = _company
        ..logo = _png(200, 50);
      addTearDown(CompanyStore.instance.debugReset);
      final pdf = await buildPdfInBackground(TelegramPdf(telegrams));
      expect(latin1.decode(pdf), contains('Elektro Muster'));
    });
  });

  group('CompanyStore', () {
    late Directory dir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('company');
      AppStorage.instance = IoStorage(dir);
      CompanyStore.instance.debugReset();
    });

    tearDown(() => dir.delete(recursive: true));

    test('speichern und wieder laden, Logo entfernen', () async {
      final store = CompanyStore.instance;
      await store.save(_company);
      await store.setLogo(_png(10, 10));
      store.debugReset();
      await store.load();
      expect(store.company.name, _company.name);
      expect(store.company.technician, 'D. Elektro');
      expect(store.logo, isNotNull);
      await store.setLogo(null);
      store.debugReset();
      await store.load();
      expect(store.logo, isNull);
    });

    test('kaputte Dateien verhindern den Start nicht', () async {
      await AppStorage.instance.write('company.json', '{kaputt');
      await AppStorage.instance.write('company_logo.png.b64', '%%%');
      await CompanyStore.instance.load();
      expect(CompanyStore.instance.company.isSet, isFalse);
      expect(CompanyStore.instance.logo, isNull);
    });

    test('ohne Pro bleibt das PDF ohne Briefkopf', () async {
      await Plan.instance.load(using: _Store(Tier.plus));
      await Plan.instance.refreshing;
      final store = CompanyStore.instance..company = _company;
      expect(Plan.instance.allows(Feature.letterhead), isFalse);
      expect(store.letterhead, isNull);
      await Plan.instance.load(using: _Store(Tier.pro));
      await Plan.instance.refreshing;
      expect(store.letterhead?.name, _company.name);
    });
  });

  testWidgets('Seite Firma: eintragen, speichern, Vorschau', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late Directory dir;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('company_screen');
      AppStorage.instance = IoStorage(dir);
      addTearDown(() => dir.delete(recursive: true));
    });
    CompanyStore.instance.debugReset();
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const CompanyScreen(),
      ),
    );
    await tester.pump();
    expect(find.text('Ihr Firmenname'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Elektro Test');
    await tester.pump();
    expect(find.text('Elektro Test'), findsWidgets);
    await tester.runAsync(() async {
      await tester.tap(find.text('Speichern'));
      await tester.pump();
      // Wait for the file itself, not a fixed time: under the load of the whole suite the write
      // took longer, and the folder was deleted underneath it.
      for (var i = 0; i < 100 && !File('${dir.path}/company.json').existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(File('${dir.path}/company.json').existsSync(), isTrue);
    expect(CompanyStore.instance.company.name, 'Elektro Test');
    CompanyStore.instance.debugReset();
  });

  group('Seite Firma nach Breite', () {
    Future<void> pump(WidgetTester tester, Size size, {double scale = 1}) async {
      SharedPreferences.setMockInitialValues({});
      CompanyStore.instance
        ..debugReset()
        ..company = _company
        ..logo = _png(280, 96);
      addTearDown(CompanyStore.instance.debugReset);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const CompanyScreen(),
        ),
      );
      await tester.pump();
    }

    testWidgets('1400 pt: Angaben links, Vorschau, Logo und weitere Angaben rechts daneben', (tester) async {
      await pump(tester, const Size(1400, 900));
      final details = tester.getTopLeft(find.text('Angaben'));
      final preview = tester.getTopLeft(find.text('Vorschau des Briefkopfs'));
      expect(details.dx, lessThan(100));
      expect(preview.dx, greaterThan(700));
      expect(preview.dy, details.dy);
      expect(preview.dy, lessThan(200));
      expect(tester.getTopLeft(find.text('Weitere Angaben')).dx, greaterThan(700));
      // Everything fits a window of 900 pt height.
      expect(tester.getBottomLeft(find.text('Techniker auf diesem Gerät')).dy, lessThan(900));
      // Keyboard order: the left column first.
      expect(tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text, _company.name);
      expect(tester.widget<TextField>(find.byType(TextField).at(5)).controller!.text, _company.vatId);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Telefon: eine Spalte, die Vorschau zuerst', (tester) async {
      await pump(tester, const Size(375, 3000));
      final preview = tester.getTopLeft(find.text('Vorschau des Briefkopfs'));
      final details = tester.getTopLeft(find.text('Angaben'));
      expect(preview.dx, details.dx);
      expect(preview.dy, lessThan(details.dy));
      expect(details.dy, lessThan(tester.getTopLeft(find.text('Weitere Angaben')).dy));
    });

    testWidgets('375 pt breit, Textgröße 2.0: kein Überlauf', (tester) async {
      await pump(tester, const Size(375, 667), scale: 2);
      expect(tester.takeException(), isNull);
      await tester.dragUntilVisible(
        find.text('Techniker auf diesem Gerät'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
