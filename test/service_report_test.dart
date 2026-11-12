import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/export/pdf_export.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/acceptance.dart';
import 'package:knx_monitor/model/annotation.dart';
import 'package:knx_monitor/model/customer.dart';
import 'package:knx_monitor/model/health.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/model/recording.dart';
import 'package:knx_monitor/model/service_report.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/customers_screen.dart';
import 'package:knx_monitor/ui/fault_reply_screen.dart';
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

/// A report exactly as the app wrote it before kinds, checklist and comparison existed.
const _oldReport =
    '{"format":"knx-monitor-service-report","version":1,"created":1793365200000,"project":"Haus Muster",'
    '"customer":"Familie Muster","site":"Hauptstraße 1","technician":"D. Elektro","language":"de",'
    '"occasion":"Licht geht nachts an","observed":"","done":"","recommendation":"","recordingName":null,'
    '"recordingStart":null,"recordingEnd":null,"telegrams":0,"comments":[],'
    '"findings":[{"l":"watch","t":"Viele Wiederholungen"}],"health":[],"healthTime":null,"signer":"",'
    '"signature":[],"gateway":null}';
const _oldReportChecksum = 'cd0cb12489e2da3f99ea86982c2b69f94d665a21d2d3a3caa785e212d9ea22dd';

/// Maintenance report; [health] `null` = no health check, [recording] whether a recording was included.
ServiceReport _maintenance({
  required DateTime created,
  String language = 'de',
  List<ServiceLine>? health,
  bool recording = false,
  List<ServiceLine> findings = const [],
  List<ServiceCheck>? checklist,
  ServiceReport? previous,
}) => ServiceReport(
  created: created,
  customer: 'Familie Muster',
  site: 'Hauptstraße 1',
  technician: 'D. Elektro',
  language: language,
  occasion: 'Jährliche Wartung',
  observed: '',
  done: '',
  recommendation: '',
  recordingStart: recording ? created.subtract(const Duration(hours: 1)) : null,
  recordingEnd: recording ? created : null,
  findings: findings,
  health: health ?? const [],
  healthTime: health == null ? null : created,
  kind: ServiceKind.maintenance,
  checklist: checklist ?? maintenanceChecklist(language, previous: previous),
  previous: previous == null ? null : ServiceBaseline.of(previous),
);

ServiceReport _reply({String language = 'de'}) => ServiceReport(
  created: DateTime(2026, 11, 11, 9),
  customer: 'Familie Muster',
  site: '',
  technician: 'D. Elektro',
  language: language,
  occasion: 'Das Licht im Flur geht nachts von selbst an.',
  observed: 'Der Melder reagiert auf die Heizung.',
  done: '',
  recommendation: 'Wir stellen ihn am Donnerstag neu ein.',
  kind: ServiceKind.reply,
  reportedAt: DateTime(2026, 11, 9, 20),
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

  group('Wartung', () {
    const silent = ServiceLine(ServiceLevel.fix, 'Wind meldet sich nicht', 'seit 3 Tagen');
    const repeats = ServiceLine(ServiceLevel.watch, 'Viele Wiederholungen');
    const battery = ServiceLine(ServiceLevel.watch, 'Batterie schwach');
    const note = ServiceLine(ServiceLevel.info, 'Nur zur Information');
    final spring = DateTime(2026, 5, 12, 10);
    final autumn = DateTime(2026, 11, 11, 10);

    test('alter Bericht lädt, bleibt Byte für Byte gleich und behält seine Prüfsumme', () {
      final old = ServiceReport.fromJson(jsonDecode(_oldReport) as Map<String, Object?>);
      expect(old.kind, ServiceKind.visit);
      expect(old.checklist, isEmpty);
      expect(old.previous, isNull);
      expect(old.comparison, isNull);
      expect(old.attention, 1);
      expect(jsonEncode(old.toJson()), _oldReport);
      expect(old.checksum, sha256.convert(utf8.encode(_oldReport)).toString());
      expect(old.checksum, _oldReportChecksum);
      // Ein gewöhnlicher neuer Bericht schreibt die neuen Felder ebenfalls nicht.
      for (final key in ['kind', 'checklist', 'previous', 'reportedAt']) {
        expect(_report().toJson().containsKey(key), isFalse, reason: key);
      }
    });

    test('feste Gliederung in der Sprache des Berichts; Vorgänger gibt sie vor', () {
      final de = maintenanceChecklist('de');
      final en = maintenanceChecklist('en');
      expect(de.map((c) => c.key), maintenanceCheckKeys);
      expect(de.first.label, 'Verteiler und Geräte: Sichtprüfung');
      expect(en.first.label, 'Distribution board and devices: visual inspection');
      expect(de.every((c) => c.result == CheckResult.unchecked), isTrue);
      // Gleiche Gliederung wie beim letzten Mal, auch mit einem Punkt, den diese
      // Version nicht kennt; Ergebnisse werden nie übernommen.
      final previous = _maintenance(
        created: spring,
        checklist: const [
          ServiceCheck('backup', 'Projektstand und Sicherung aktuell', CheckResult.attention),
          ServiceCheck('roof', 'Wetterstation gereinigt', CheckResult.ok),
        ],
      );
      final next = maintenanceChecklist('en', previous: previous);
      expect(next.map((c) => c.label), ['Project data and backup up to date', 'Wetterstation gereinigt']);
      expect(next.every((c) => c.result == CheckResult.unchecked), isTrue);
    });

    test('JSON hin und zurück mit Checkliste und Vorgänger', () {
      final first = _maintenance(created: spring, health: const [silent, repeats]);
      final second = _maintenance(created: autumn, health: const [repeats, battery], previous: first);
      final back = ServiceReport.fromJson(jsonDecode(jsonEncode(second.toJson())) as Map<String, Object?>);
      expect(back.checksum, second.checksum);
      expect(back.kind, ServiceKind.maintenance);
      expect(back.checklist.map((c) => c.key), maintenanceCheckKeys);
      expect(back.previous!.created, spring);
      expect(back.previous!.findings, isNull, reason: 'der Vorgänger hatte keine Aufnahme');
      expect(back.previous!.health!.map((l) => l.title), [silent.title, repeats.title]);
      // Eine Art aus einer neueren Version liest sich als gewöhnlicher Bericht.
      expect(ServiceReport.fromJson({'created': 0, 'kind': 'audit'}).kind, ServiceKind.visit);
    });

    test('Vergleich: neu, weg, geblieben; Gesundheitsprüfung damals und heute', () {
      final first = _maintenance(
        created: spring,
        health: const [silent, repeats, note],
        checklist: const [ServiceCheck('visual', 'Sicht', CheckResult.attention), ServiceCheck('old', 'Alt')],
      );
      final second = _maintenance(
        created: autumn,
        health: const [repeats, battery],
        checklist: const [ServiceCheck('visual', 'Sichtprüfung', CheckResult.ok), ServiceCheck('new', 'Neu')],
        previous: first,
      );
      final c = second.comparison!;
      expect(c.previous, spring);
      expect(c.linesCompared, isTrue);
      expect(c.added.map((l) => l.title), [battery.title]);
      expect(c.gone.map((l) => l.title), [silent.title]);
      expect(c.remaining.map((l) => l.title), [repeats.title]);
      expect(c.healthBefore, (fix: 1, watch: 1));
      expect(c.healthNow, (fix: 0, watch: 2));
      // Nur Prüfpunkte, die beide Berichte haben.
      expect(c.checks, [(label: 'Sichtprüfung', before: CheckResult.attention, now: CheckResult.ok)]);
      expect(_maintenance(created: spring).comparison, isNull, reason: 'ohne Vorgänger kein Vergleich');
    });

    test('ehrlich: verglichen wird nur, was beide Berichte enthalten', () {
      // Vorgänger ohne Gesundheitsprüfung: "silent" ist heute nicht "neu".
      final bare = _maintenance(created: spring);
      final c1 = _maintenance(created: autumn, health: const [silent], previous: bare).comparison!;
      expect(c1.linesCompared, isFalse);
      expect([...c1.added, ...c1.gone, ...c1.remaining], isEmpty);
      expect(c1.healthBefore, isNull);
      // Heute ohne Gesundheitsprüfung: die Befunde von damals sind nicht "weg".
      final checked = _maintenance(created: spring, health: const [silent]);
      final c2 = _maintenance(created: autumn, previous: checked).comparison!;
      expect(c2.linesCompared, isFalse);
      expect(c2.gone, isEmpty);
      // Aufnahme nur auf einer Seite: ihre Hinweise bleiben draußen, die Prüfung zählt.
      final recorded = _maintenance(
        created: spring,
        health: const [silent],
        recording: true,
        findings: const [repeats],
      );
      final c3 = _maintenance(created: autumn, health: const [silent], previous: recorded).comparison!;
      expect(c3.linesCompared, isTrue);
      expect(c3.remaining.map((l) => l.title), [silent.title]);
      expect(c3.gone, isEmpty, reason: 'ohne Aufnahme heute ist "Viele Wiederholungen" nicht weg');
      // Andere Sprache: Texte nicht vergleichbar, die Zahlen schon.
      final english = _maintenance(created: autumn, language: 'en', health: const [battery], previous: checked);
      expect(english.comparison!.linesCompared, isFalse);
      expect(english.comparison!.healthBefore, (fix: 1, watch: 0));
      expect(english.comparison!.healthNow, (fix: 0, watch: 1));
    });

    test('auffällige Prüfpunkte zählen zum Ergebnis', () {
      final r = _maintenance(
        created: autumn,
        health: const [repeats],
        checklist: const [
          ServiceCheck('visual', 'Sicht', CheckResult.attention),
          ServiceCheck('supply', 'Netz', CheckResult.ok),
        ],
      );
      expect(r.attention, 2);
    });

    for (final (language, title, intro, added, gone, still, counts, then, nothing, apart) in [
      (
        'de',
        'Seit dem letzten Besuch',
        'Vergleich mit dem Wartungsbericht vom 12.05.2026. Verglichen wird nur, was in beiden Berichten enthalten ist.',
        'Neu',
        'Nicht mehr vorhanden',
        'Weiterhin vorhanden',
        '1 zu beheben, 1 im Auge zu behalten',
        'Damals (12.05.2026)',
        'Bei beiden Besuchen gab es keine Auffälligkeiten.',
        'lassen sich nicht vergleichen',
      ),
      (
        'en',
        'Since the last visit',
        'Compared with the maintenance report of 2026-05-12. Only what both reports contain is compared.',
        'New',
        'No longer present',
        'Still present',
        '1 to fix, 1 to keep an eye on',
        'Then (2026-05-12)',
        'Neither visit showed any findings.',
        'cannot be compared',
      ),
    ]) {
      test('PDF ($language): Abschnitt „Seit dem letzten Besuch“ mit seinen Texten', () async {
        LocaleController.instance.debugSetLocale(Locale(language));
        addTearDown(() => LocaleController.instance.debugSetLocale(const Locale('de')));
        final first = _maintenance(created: spring, language: language, health: const [silent, repeats]);
        final second = _maintenance(
          created: autumn,
          language: language,
          health: const [repeats, battery],
          previous: first,
        );
        final since = serviceSinceLastVisit(second)!;
        expect(since.title, title);
        expect(since.intro, intro);
        expect(since.note, isNull);
        expect(since.groups.map((g) => (g.$1, g.$2.single.title)), [
          (added, battery.title),
          (gone, silent.title),
          (still, repeats.title),
        ]);
        expect(since.health!.then, counts);
        expect(since.thenHead, then);
        expect(since.checks, hasLength(maintenanceCheckKeys.length));
        expect(serviceReportTitle(second), language == 'de' ? 'Wartungsbericht' : 'Maintenance report');
        // Nichts gefunden und nichts vergleichbar sagen es in einem Satz.
        final calm = _maintenance(
          created: autumn,
          language: language,
          health: const [],
          previous: _maintenance(created: spring, language: language, health: const []),
        );
        expect(serviceSinceLastVisit(calm)!.note, nothing);
        final apartReport = _maintenance(
          created: autumn,
          language: language,
          health: const [silent],
          previous: _maintenance(created: spring, language: language),
        );
        expect(serviceSinceLastVisit(apartReport)!.note, contains(apart));
        expect(serviceSinceLastVisit(apartReport)!.health, isNull);
        // Ohne Vorgänger entfällt der Abschnitt; das PDF ist entsprechend kürzer.
        expect(serviceSinceLastVisit(first), isNull);
        final withSection = await buildPdf(ServiceReportPdf(second));
        final without = await buildPdf(
          ServiceReportPdf(_maintenance(created: autumn, language: language, health: const [repeats, battery])),
        );
        expect(utf8.decode(withSection.sublist(0, 5)), '%PDF-');
        expect(withSection.length, greaterThan(without.length));
        expect(utf8.decode((await buildPdfInBackground(ServiceReportPdf(second))).sublist(0, 5)), '%PDF-');
      });
    }
  });

  group('Rückmeldung nach einer Störungsmeldung', () {
    test('JSON hin und zurück; ältere Versionen lesen sie als Bericht mit denselben Texten', () {
      final r = _reply();
      final json = jsonDecode(jsonEncode(r.toJson())) as Map<String, Object?>;
      final back = ServiceReport.fromJson(json);
      expect(back.checksum, r.checksum);
      expect(back.kind, ServiceKind.reply);
      expect(back.reportedAt, DateTime(2026, 11, 9, 20));
      expect(json['occasion'], r.occasion);
      expect(json['recommendation'], r.recommendation);
    });

    for (final (language, title, reported, found, next) in [
      (
        'de',
        'Rückmeldung zu Ihrer Störungsmeldung',
        'Was Sie gemeldet haben',
        'Was wir festgestellt haben',
        'Wie es weitergeht',
      ),
      ('en', 'Status of your fault report', 'What you reported', 'What we found', 'What happens next'),
    ]) {
      test('PDF ($language): drei Abschnitte in einfachen Worten, nichts aus der Aufnahme', () async {
        LocaleController.instance.debugSetLocale(Locale(language));
        addTearDown(() => LocaleController.instance.debugSetLocale(const Locale('de')));
        final r = _reply(language: language);
        expect(serviceReportTitle(r), title);
        final sections = faultReplySections(r);
        expect(sections.map((x) => x.$1), [reported, found, next]);
        expect(sections.first.$2, startsWith(language == 'de' ? 'Gemeldet am 09.11.2026' : 'Reported on 2026-11-09'));
        expect(sections.first.$2, endsWith(r.occasion));
        expect(sections[1].$2, r.observed);
        expect(sections[2].$2, r.recommendation);
        // Leere Teile entfallen.
        expect(
          faultReplySections(ServiceReport.fromJson({'created': 0, 'kind': 'reply', 'observed': 'x'})).map((x) => x.$1),
          [found],
        );
        final pdf = await buildPdf(ServiceReportPdf(r));
        expect(utf8.decode(pdf.sublist(0, 5)), '%PDF-');
        expect(utf8.decode((await buildPdfInBackground(ServiceReportPdf(r))).sublist(0, 5)), '%PDF-');
        // Kurz: kleiner als ein Servicebericht mit Belegen.
        expect(pdf.length, lessThan((await buildPdf(ServiceReportPdf(_report()))).length));
      });
    }
  });

  group('Seiten', () {
    Future<void> prepare(WidgetTester tester, [Future<void> Function()? fill]) async {
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('service_pages');
        AppStorage.instance = IoStorage(dir);
        addTearDown(() => dir.delete(recursive: true));
        InstallationStore.instance.debugReset();
        await InstallationStore.instance.load();
        CustomerStore.instance.debugReset();
        await fill?.call();
      });
    }

    Widget app(Widget home, {double scale = 1}) => MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home,
    );

    void size(WidgetTester tester, Size s) {
      tester.view.physicalSize = s;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    /// Lets the store read from disk (real time, one hop per await) until [until] shows.
    Future<void> settle(WidgetTester tester, Finder until) async {
      for (var i = 0; i < 100 && until.evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
    }

    testWidgets('Wartung: Checkliste erscheint, Anlass vorbelegt, erster Bericht ohne Vergleich', (tester) async {
      await prepare(tester);
      size(tester, const Size(1400, 3000));
      await tester.pumpWidget(app(const ServiceReportScreen()));
      await tester.pump();
      expect(find.text('Bei diesem Besuch geprüft'), findsNothing);
      await tester.tap(find.text('Wartung'));
      await settle(tester, find.textContaining('Erster Wartungsbericht'));
      expect(find.text('Bei diesem Besuch geprüft'), findsOneWidget);
      expect(find.text('Erster Wartungsbericht dieser Anlage: noch kein Vergleich.'), findsOneWidget);
      expect(find.text('Regelmäßige Wartung der Anlage'), findsOneWidget);
      for (final key in maintenanceCheckKeys) {
        expect(find.text(maintenanceChecklist('de').firstWhere((c) => c.key == key).label), findsOneWidget);
      }
      expect(find.text('Auffällig'), findsNWidgets(maintenanceCheckKeys.length));
      // Breit: Prüfpunkt und Auswahl stehen nebeneinander.
      final label = tester.getRect(find.text('Spannungsversorgung der Anlage'));
      final choice = tester.getRect(find.text('Auffällig').at(1));
      expect(choice.left, greaterThan(label.right));
      expect(choice.center.dy, closeTo(label.center.dy, 12));
      // Jede Auswahl ist groß genug zum Tippen.
      final segment = tester.getSize(find.byType(SegmentedButton<CheckResult>).first);
      expect(segment.height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    });

    testWidgets('breites Fenster: Texte links, Belege und Unterschrift rechts', (tester) async {
      await prepare(tester);
      size(tester, const Size(1400, 1200));
      await tester.pumpWidget(app(const ServiceReportScreen(maintenance: true)));
      await tester.pump();
      await settle(tester, find.text('Bei diesem Besuch geprüft'));
      final l = lookupAppLocalizations(const Locale('de'));
      final visit = tester.getRect(find.text(l.srOccasion));
      final evidence = tester.getRect(find.text(l.srIncludes));
      expect(visit.left, lessThan(120));
      expect(evidence.left, greaterThan(700), reason: 'second column, not below the texts');
      expect(evidence.top, lessThan(visit.top + 200));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Wartung mit Vorgänger: gleiche Gliederung, Anlass und Vergleichshinweis', (tester) async {
      await prepare(tester, () async {
        await ServiceReportStore.instance.save(
          _maintenance(
            created: DateTime(2026, 5, 12, 10),
            checklist: const [
              ServiceCheck('backup', 'x', CheckResult.attention),
              ServiceCheck('roof', 'Wetterstation gereinigt'),
            ],
          ),
        );
        // Ein neuerer gewöhnlicher Bericht ist kein Vorgänger.
        await ServiceReportStore.instance.save(_report());
        expect((await ServiceReportStore.instance.lastMaintenance())!.created, DateTime(2026, 5, 12, 10));
      });
      size(tester, const Size(375, 3000));
      await tester.pumpWidget(app(const ServiceReportScreen(maintenance: true)));
      await settle(tester, find.textContaining('Aufbau und Vergleich'));
      expect(find.text('Aufbau und Vergleich: Wartungsbericht vom 12.05.2026.'), findsOneWidget);
      expect(find.text('Jährliche Wartung'), findsOneWidget);
      expect(find.text('Wetterstation gereinigt'), findsOneWidget);
      expect(find.text('Projektstand und Sicherung aktuell'), findsOneWidget);
      expect(find.text('Verteiler und Geräte: Sichtprüfung'), findsNothing);
      // Schmal: Auswahl unter dem Prüfpunkt.
      final label = tester.getRect(find.text('Wetterstation gereinigt'));
      expect(tester.getRect(find.text('Auffällig').last).top, greaterThan(label.bottom));
      expect(tester.takeException(), isNull);
    });

    final fault = Visit(
      id: 'fault:1',
      time: DateTime(2026, 11, 9, 20),
      kind: VisitKind.faultReport,
      text: 'Das Licht im Flur geht nachts von selbst an.',
      ref: 'r1',
    );

    testWidgets('Rückmeldung: Meldung vorbelegt, Knopf erst mit Inhalt; breit zweispaltig', (tester) async {
      await prepare(tester, () async {
        await CustomerStore.instance.saveRecord(
          InstallationStore.instance.active.id,
          const CustomerRecord(customer: 'Familie Muster', site: 'Hauptstraße 1'),
        );
      });
      size(tester, const Size(1200, 900));
      await tester.pumpWidget(app(FaultReplyScreen(report: fault)));
      await tester.pump();
      expect(find.text('Gemeldet am 09.11.2026'), findsOneWidget);
      expect(find.text(fault.text), findsOneWidget);
      expect(find.text('Familie Muster'), findsOneWidget);
      expect(find.text('Hauptstraße 1'), findsNothing, reason: 'keine Adresse in der Rückmeldung');
      final create = find.widgetWithText(FilledButton, 'Rückmeldung erstellen und teilen');
      expect(tester.widget<FilledButton>(create).onPressed, isNull);
      expect(find.text('Schreibe, was festgestellt wurde oder wie es weitergeht.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'z. B. Wir stellen den Melder am Donnerstag neu ein.'),
        'Termin folgt',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(create).onPressed, isNotNull);
      expect(tester.getSize(create).height, greaterThanOrEqualTo(44));
      // Breit: Meldung links, Antwort rechts daneben.
      final reported = tester.getRect(find.text('Was gemeldet wurde'));
      final found = tester.getRect(find.text('Was festgestellt wurde'));
      expect(found.left, greaterThan(reported.left + 300));
      expect(found.top, lessThan(reported.bottom + 40));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Kundenakte: Störungsmeldung führt zur Rückmeldung, die Rückmeldung steht im Verlauf', (tester) async {
      late Installation i;
      await prepare(tester, () async {
        i = InstallationStore.instance.active;
        await CustomerStore.instance.saveVisit(i.id, fault);
        await CustomerStore.instance.note(
          VisitKind.faultReply,
          text: 'Termin folgt',
          ref: '1',
          now: DateTime(2026, 11, 11),
        );
      });
      // Eine Rückmeldung ist keine Wartung und übersteht die Datei.
      final reply = CustomerStore.instance.visits(i.id).first;
      expect(reply.kind, VisitKind.faultReply);
      expect(Visit.fromJson(reply.toJson()).kind, VisitKind.faultReply);
      expect(VisitKind.faultReply.countsAsMaintenance, isFalse);
      size(tester, const Size(900, 2400));
      await tester.pumpWidget(app(CustomerDetailScreen(installation: i)));
      await tester.pump();
      expect(find.textContaining('Termin folgt'), findsOneWidget);
      expect(find.textContaining('Rückmeldung an den Kunden'), findsOneWidget);
      final button = find.byTooltip('Rückmeldung an den Kunden');
      expect(button, findsOneWidget, reason: 'nur an der Störungsmeldung');
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(FaultReplyScreen), findsOneWidget);
      expect(find.text(fault.text), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Rückmeldung schmal: eine Spalte, Antwort unter der Meldung', (tester) async {
      await prepare(tester);
      size(tester, const Size(375, 2000));
      await tester.pumpWidget(app(FaultReplyScreen(report: fault)));
      await tester.pump();
      final reported = tester.getRect(find.text('Was gemeldet wurde'));
      final found = tester.getRect(find.text('Was festgestellt wurde'));
      expect(found.top, greaterThan(reported.bottom));
      expect(found.left, closeTo(reported.left, 1));
      expect(tester.takeException(), isNull);
    });
  });
}
