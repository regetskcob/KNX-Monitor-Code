import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/export/diagnostics_bundle.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/annotation.dart';
import 'package:knx_monitor/model/findings.dart';
import 'package:knx_monitor/model/recording.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/annotations.dart';
import 'package:knx_monitor/ui/recording_timeline.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final t0 = DateTime(2026, 10, 22, 21, 40);
  final light = parseGroup('1/1/3')!;
  final status = parseGroup('1/4/3')!;
  final button = parseIndividual('1.1.30')!;
  final actuator = parseIndividual('1.1.10')!;

  Telegram tg(int sec, int src, int ga, int value, {TelegramType type = TelegramType.write}) => Telegram(
    time: t0.add(Duration(seconds: sec)),
    source: src,
    destination: ga,
    type: type,
    data: Uint8List.fromList([value]),
    isSmall: true,
  );

  final telegrams = [
    tg(6, button, light, 1),
    tg(6, actuator, status, 1, type: TelegramType.response),
    tg(38, button, light, 1),
  ];

  late Directory dir;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('knx_notes');
    AppStorage.instance = IoStorage(dir);
    AnnotationStore.instance
      ..debugReset()
      ..storage = () => AppStorage.instance;
  });
  tearDown(() => dir.delete(recursive: true));

  group('Annotation', () {
    test('JSON mit Telegramm-Bezug samt Rohwert und Diagramm-Bezug', () {
      final a = Annotation(
        id: 'a',
        time: telegrams[2].time,
        note: 'Drittes Mal: Licht bleibt aus',
        telegram: TelegramRef.of(telegrams[2]),
        shots: ['s1'],
      );
      final back = Annotation.fromJson(a.toJson());
      expect(back.note, a.note);
      expect(back.telegram!.destination, light);
      expect(back.telegram!.toTelegram().data, [1]);
      expect(back.telegram!.toTelegram().isSmall, isTrue);
      expect(back.shots, ['s1']);
      final c = Annotation(
        id: 'c',
        time: t0,
        chart: ChartRef(groups: [light, status], from: t0, to: t0.add(const Duration(minutes: 1))),
      );
      expect(Annotation.fromJson(c.toJson()).chart!.groups, [light, status]);
    });

    test('Aufnahme speichert Kommentare und Befunddaten', () {
      final r = Recording(
        id: 'r',
        name: 'Test',
        started: t0,
        ended: t0.add(const Duration(minutes: 1)),
        telegrams: telegrams,
        annotations: [Annotation(id: 'a', time: t0, note: 'x')],
        diagnostics: {'problem': 'Licht'},
      );
      final back = Recording.fromJson(r.toJson());
      expect(back.annotations.single.note, 'x');
      expect(back.diagnostics!['problem'], 'Licht');
    });
  });

  group('Screenshots', () {
    test('verkleinert auf 1920 an der langen Kante, als JPEG', () {
      final big = img.Image(width: 3000, height: 2000);
      img.fill(big, color: img.ColorRgb8(200, 30, 30));
      final out = compressShot(Uint8List.fromList(img.encodePng(big)));
      expect(out.sublist(0, 2), [0xFF, 0xD8]);
      final decoded = img.decodeJpg(out)!;
      expect(decoded.width, shotMaxEdge);
      expect(decoded.height, 1280);
    });

    test('kein Bild: FormatException', () {
      expect(() => compressShot(Uint8List.fromList([1, 2, 3])), throwsFormatException);
    });

    test('Ablage: speichern, lesen, löschen', () async {
      final id = await ShotStore.instance.put(Uint8List.fromList([0xFF, 0xD8, 1]));
      expect(await ShotStore.instance.read(id), [0xFF, 0xD8, 1]);
      await ShotStore.instance.delete(id);
      expect(await ShotStore.instance.read(id), isNull);
    });
  });

  group('AnnotationStore', () {
    test('Hinzufügen, Fähnchen am Telegramm, Bereich, Ändern und Löschen räumt Bilder weg', () async {
      final store = AnnotationStore.instance;
      final shot = await ShotStore.instance.put(Uint8List.fromList([0xFF, 0xD8]));
      final a = Annotation(id: 'a', time: telegrams[2].time, telegram: TelegramRef.of(telegrams[2]), shots: [shot]);
      await store.add(a);
      expect(store.hasTelegram(telegrams[2].time, button, light), isTrue);
      expect(store.hasTelegram(telegrams[0].time, button, light), isFalse);
      expect(store.inRange(t0, t0.add(const Duration(seconds: 10))), isEmpty);
      expect(store.inRange(t0, null), hasLength(1));

      await store.replace(a.copyWith(note: 'neu', shots: []));
      expect(store.all.single.note, 'neu');
      expect(await ShotStore.instance.read(shot), isNull);

      // Neu geladen: aus der Datei.
      store.debugReset();
      await store.load();
      expect(store.all.single.note, 'neu');
      await store.remove(store.all.single);
      expect(store.all, isEmpty);
    });
  });

  group('Diagnosepaket mit Kommentaren', () {
    final catalog = GroupCatalog({light: const GroupInfo(address: 0, name: 'Licht Küche')});

    test('Zeitraum, ältere Kommentare, Screenshots, Namen bereinigt – und zurück', () {
      final inside = Annotation(
        id: 'in',
        time: telegrams[2].time,
        note: 'Licht Küche bleibt aus',
        telegram: TelegramRef.of(telegrams[2]),
        shots: ['s1'],
      );
      final older = Annotation(id: 'old', time: t0.subtract(const Duration(days: 3)), note: 'komisch');
      final outside = Annotation(id: 'out', time: t0.subtract(const Duration(days: 2)), note: 'nicht dabei');
      final package = buildDiagnosticsPackage(
        telegrams: telegrams,
        catalog: catalog,
        occurred: telegrams[2].time,
        from: t0,
        to: t0.add(const Duration(minutes: 1)),
        keepNames: false,
        annotations: [inside, outside],
        olderAnnotations: [older],
        shots: {
          's1': Uint8List.fromList([0xFF, 0xD8, 9]),
          's2': Uint8List.fromList([0xFF]),
        },
        packageShots: ['s2'],
      );
      expect(package.recording.annotations.map((a) => a.id), ['old', 'in']);
      // Ohne Namen auch ohne Raumnamen im freien Text.
      expect(package.recording.annotations.last.note, isNot(contains('Licht Küche')));
      expect(package.shots.keys.toSet(), {'s1', 's2'});
      expect(package.manifest['shots'], ['s2']);

      final back = DiagnosticsPackage.fromZip(package.toZip());
      expect(back.recording.annotations.map((a) => a.id), ['old', 'in']);
      expect(back.shots['s1'], [0xFF, 0xD8, 9]);
      expect(back.packageShots, ['s2']);
    });
  });

  group('Sicherheit des Pakets', () {
    test('Screenshot-IDs mit Pfadteilen werden weder gespeichert noch importiert', () async {
      expect(ShotStore.validId('mh8x2k1a0'), isTrue);
      expect(ShotStore.validId('../../outside'), isFalse);
      expect(ShotStore.validId('a/b'), isFalse);
      expect(() => ShotStore.instance.put(Uint8List.fromList([1]), id: '../x'), throwsArgumentError);
      expect(await ShotStore.instance.read('../x'), isNull);

      final ok = buildDiagnosticsPackage(
        telegrams: telegrams,
        catalog: GroupCatalog.empty,
        occurred: telegrams.last.time,
        from: t0,
        keepNames: true,
      ).toZip();
      // Paket nachträglich um einen bösartigen Eintrag ergänzen.
      final archive = ZipDecoder().decodeBytes(ok)..addFile(ArchiveFile('shots/../../outside.jpg', 1, [1]));
      final back = DiagnosticsPackage.fromZip(Uint8List.fromList(ZipEncoder().encode(archive)));
      expect(back.shots, isEmpty);
    });

    test('Kommentar an einem Secure-Telegramm verrät dessen Wert nicht', () {
      final a = Annotation(id: 'a', time: telegrams[0].time, note: 'x', telegram: TelegramRef.of(telegrams[0]));
      final package = buildDiagnosticsPackage(
        telegrams: telegrams,
        catalog: GroupCatalog.empty,
        occurred: telegrams.last.time,
        from: t0,
        keepNames: true,
        secureAddresses: {light},
        annotations: [a],
      );
      final ref = package.recording.annotations.single.telegram!;
      expect(ref.destination, light);
      expect(ref.data, isEmpty);
      expect(jsonEncode(package.recording.toJson()), isNot(contains('"data":[1]')));
    });
  });

  test('Gerätekommentare enthalten Diagramme mit seinen Adressen', () async {
    await AnnotationStore.instance.add(
      Annotation(
        id: 'c',
        time: t0,
        note: 'Diagramm',
        chart: ChartRef(groups: [status], from: t0, to: t0),
      ),
    );
    expect(AnnotationScope.forDevice(actuator, {status}).map((a) => a.id), ['c']);
    expect(AnnotationScope.forDevice(actuator, {light}), isEmpty);
  });

  group('Befund', () {
    Recording withDiagnostics(Map<String, Object?> technical, {List<String> log = const []}) => Recording(
      id: 'r',
      name: 'Diagnose',
      started: t0,
      ended: t0.add(const Duration(minutes: 1)),
      telegrams: telegrams,
      diagnostics: {'technical': technical, 'log': log},
    );

    test('Hinweise nach Schwere, Versionen und Technik', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('de'));
      expect(l10n, isNotNull);
      final r = withDiagnostics(
        {
          'app': {'version': '1.7.1', 'mode': 'release'},
          'connection': {'state': 'disconnected', 'error': 'Keine freien Tunnel'},
          'secure': {'telegramsWithoutKey': 4, 'telegramsRejected': 0},
          'traffic': {'telegrams': 100, 'repeated': 12, 'unansweredReads': 2},
        },
        log: ['ok', 'Fehler: Zeitüberschreitung'],
      );
      final f = findingsOf(r, currentVersion: '1.7.3');
      expect(f.first.level, FindingLevel.critical);
      expect(f.first.text, contains('Keine freien Tunnel'));
      expect(f.where((x) => x.level == FindingLevel.warning), hasLength(3));
      expect(f.where((x) => x.level == FindingLevel.info), hasLength(2));
      expect(compareVersions('1.7.10', '1.7.2'), greaterThan(0));
      expect(compareVersions('1.7.2+8', '1.7.2'), 0);
      expect(technicalFacts(r.diagnostics!['technical']! as Map<String, Object?>), isNotEmpty);
    });
  });

  testWidgets('Zeitleiste zeigt Telegramme, Tippen öffnet den Kommentar', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    CatalogStore.instance.catalog = GroupCatalog({light: const GroupInfo(address: 0, name: 'Licht Küche')});
    final r = Recording(
      id: 'r',
      name: 'Licht Küche',
      started: t0,
      ended: t0.add(const Duration(seconds: 60)),
      telegrams: telegrams,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: RecordingTimelineScreen(recording: r),
      ),
    );
    await tester.pump();
    expect(find.text('Licht Küche'), findsWidgets);
    expect(find.text(formatGroup(status)), findsOneWidget);
    // Zeitleiste füllt 1400 − 190 px für 60 s: 20 px je Sekunde.
    final view = tester.getTopLeft(find.byType(TimelineView));
    await tester.tapAt(view + Offset(190 + 38 * 20.0, 28 + 17));
    await tester.pumpAndSettle();
    expect(find.text('Kommentar'), findsOneWidget);
  });

  test('chart values survive saving; older files without them still load', () {
    final ref = ChartRef(
      groups: const [2561],
      from: DateTime(2026, 11, 4, 9),
      to: DateTime(2026, 11, 4, 12),
      values: const [ChartValue(group: 2561, name: 'Wind', now: '3,9 m/s', before: '1,8 m/s')],
    );
    final back = ChartRef.fromJson(ref.toJson());
    expect(back.values.single.now, '3,9 m/s');
    expect(back.values.single.before, '1,8 m/s');
    final old = ChartRef.fromJson({
      'groups': [1],
      'from': 0,
      'to': 1,
    });
    expect(old.values, isEmpty);
    expect(
      ChartRef(groups: const [1], from: DateTime(2026), to: DateTime(2026)).toJson().containsKey('values'),
      isFalse,
    );
  });
}
