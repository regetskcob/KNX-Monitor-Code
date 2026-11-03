import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/export/pdf_export.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/acceptance.dart';
import 'package:knx_monitor/model/annotation.dart';
import 'package:knx_monitor/model/health.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/model/recording.dart';
import 'package:knx_monitor/model/service_report.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/service_report_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

ServiceReport _report({Signature signature = Signature.empty, List<ServiceLine> health = const []}) => ServiceReport(
  created: DateTime(2026, 10, 30, 14),
  project: 'Haus Muster',
  customer: 'Familie Muster',
  site: 'Hauptstraße 1',
  technician: 'D. Elektro',
  language: 'de',
  occasion: 'Licht geht nachts an',
  observed: 'Bewegungsmelder sendet',
  done: 'Melder eingestellt',
  recommendation: 'In vier Wochen prüfen',
  recordingName: 'Besuch',
  recordingStart: DateTime(2026, 10, 30, 13),
  recordingEnd: DateTime(2026, 10, 30, 13, 40),
  telegrams: 123,
  comments: [
    ServiceComment(time: DateTime(2026, 10, 30, 13, 5), note: 'Jetzt ging es an', shots: const ['abc', 'fehlt']),
  ],
  findings: const [ServiceLine(ServiceLevel.watch, 'Viele Wiederholungen')],
  health: health,
  healthTime: DateTime(2026, 10, 30, 12),
  signer: 'Max Muster',
  signature: signature,
);

Telegram _t(DateTime time) => Telegram(
  time: time,
  source: 0x1101,
  destination: 0x0801,
  type: TelegramType.write,
  data: Uint8List.fromList([1]),
  isSmall: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('JSON hin und zurück, Prüfsumme bleibt gleich', () {
    final r = _report(
      signature: const Signature([
        [Offset(0.1, 0.1), Offset(0.5, 0.5)],
      ]),
      health: const [ServiceLine(ServiceLevel.fix, 'Titel', 'Detail')],
    );
    final back = ServiceReport.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, Object?>);
    expect(back.checksum, r.checksum);
    expect(back.health.single.level, ServiceLevel.fix);
    expect(back.comments.single.shots, ['abc', 'fehlt']);
    expect(back.attention, 2);
  });

  test('ältere Berichte mit fehlenden Feldern bleiben lesbar', () {
    final r = ServiceReport.fromJson({'created': 0});
    expect(r.language, 'de');
    expect(r.signature.isEmpty, isTrue);
    expect(r.findings, isEmpty);
  });

  test('Kommentare: aus Aufnahme und Zeitraum, ohne Doppelte und leere', () {
    final start = DateTime(2026, 10, 30, 13);
    final inner = Annotation(id: 'a', time: start.add(const Duration(minutes: 1)), note: 'Aufnahme');
    final recording = Recording(
      id: 'r',
      name: 'x',
      started: start,
      ended: start.add(const Duration(hours: 1)),
      telegrams: const [],
      annotations: [inner],
    );
    final outside = Annotation(id: 'b', time: start.subtract(const Duration(hours: 1)), note: 'davor');
    final during = Annotation(id: 'c', time: start.add(const Duration(minutes: 2)), note: 'Anlage');
    final empty = Annotation(id: 'd', time: start.add(const Duration(minutes: 3)));
    final list = collectServiceComments(recording, [inner, outside, during, empty]);
    expect(list.map((c) => c.note), ['Aufnahme', 'Anlage']);
    // Ohne Aufnahme: die letzten 24 Stunden.
    final day = collectServiceComments(null, [outside, during], now: start.add(const Duration(hours: 2)));
    expect(day.length, 2);
  });

  test('Hinweise ordnen sich für Laien ein; Support-Infos bleiben draußen', () {
    final start = DateTime(2026, 10, 30, 13);
    final recording = Recording(
      id: 'r',
      name: 'x',
      started: start,
      ended: start,
      telegrams: const [],
      diagnostics: const {
        'technical': {
          'connection': {'state': 'connected', 'error': 'Zeitüberschreitung'},
          'app': {'mode': 'debug'},
        },
      },
    );
    CatalogStore.instance.catalog = GroupCatalog({0x0801: const GroupInfo(address: 0x0801, name: 'Wind')});
    addTearDown(() => CatalogStore.instance.catalog = GroupCatalog.empty);
    final run = HealthRun(start, [HealthFinding(FindingKind.alwaysSilent, 0x0801)], asked: 1, answered: 0);
    final e = buildServiceEvidence(recording, run);
    expect(e.findings.single.level, ServiceLevel.fix);
    expect(e.findings.single.title, isNot(contains('debug')));
    expect(e.health.single.title, contains('Wind'));
    expect(buildServiceEvidence(null, null).health, isEmpty);
  });

  test('Hinweise in der Sprache des Berichts, unabhängig von der App', () async {
    final start = DateTime(2026, 10, 30, 13);
    final recording = Recording(
      id: 'r',
      name: 'x',
      started: start,
      ended: start,
      telegrams: [for (var i = 0; i < 50; i++) _t(start)],
    );
    final de = await collectServiceEvidence(language: 'de', recording: recording);
    final en = await collectServiceEvidence(language: 'en', recording: recording);
    expect(de.findings.single.title, isNot(en.findings.single.title));
  });

  test('PDF entsteht: mit Bild, fehlendem Bild, Unterschrift, im Hintergrund', () async {
    final jpeg = img.encodeJpg(img.Image(width: 40, height: 30));
    final job = ServiceReportPdf(
      _report(
        signature: const Signature([
          [Offset(0.1, 0.1), Offset(0.5, 0.5)],
        ]),
      ),
      shots: {'abc': jpeg},
    );
    final pdf = await buildPdf(job);
    expect(utf8.decode(pdf.sublist(0, 5)), '%PDF-');
    expect(utf8.decode((await buildPdfInBackground(job)).sublist(0, 5)), '%PDF-');
    // Kaputtes Bild und leere Angaben: trotzdem ein PDF.
    final minimal = await buildPdf(
      ServiceReportPdf(ServiceReport.fromJson({'created': 0}), shots: {'x': Uint8List(3)}),
    );
    expect(utf8.decode(minimal.sublist(0, 5)), '%PDF-');
  });

  group('Ablage', () {
    late Directory dir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('service');
      AppStorage.instance = IoStorage(dir);
      InstallationStore.instance.debugReset();
      await InstallationStore.instance.load();
    });

    tearDown(() async {
      DemoTunnel.active = false;
      await dir.delete(recursive: true);
    });

    test('speichern, neueste zuerst, kaputte Datei überspringen', () async {
      final store = ServiceReportStore.instance;
      await store.save(_report());
      await store.save(ServiceReport.fromJson({'created': DateTime(2027).millisecondsSinceEpoch, 'customer': 'Neu'}));
      await InstallationStore.instance.storage.write('${ServiceReportStore.dir}/kaputt.json', '{');
      final list = await store.list();
      expect(list.length, 2);
      expect(list.first.customer, 'Neu');
    });

    test('Demo-Haus schreibt nichts in die echte Anlage', () async {
      DemoTunnel.active = true;
      await ServiceReportStore.instance.save(_report());
      expect(await InstallationStore.instance.storage.list(ServiceReportStore.dir), isEmpty);
      expect((await ServiceReportStore.instance.list()).length, 1);
    });
  });

  testWidgets('Seite zeigt die vier Felder und erstellt ohne Unterschrift', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('service_screen');
      AppStorage.instance = IoStorage(dir);
      addTearDown(() => dir.delete(recursive: true));
      InstallationStore.instance.debugReset();
      await InstallationStore.instance.load();
    });
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const ServiceReportScreen(),
      ),
    );
    await tester.pump();
    expect(find.text('Anlass des Besuchs'), findsOneWidget);
    expect(find.text('Was wir getan haben'), findsOneWidget);
    expect(find.text('Bericht erstellen und teilen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
