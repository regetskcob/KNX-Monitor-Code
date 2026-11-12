import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/export/telegram_files.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/recording.dart';
import 'package:knx_monitor/model/recording_import.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/catalog_actions.dart';
import 'package:knx_monitor/ui/details_sheet.dart';
import 'package:knx_monitor/ui/project_states_screen.dart';
import 'package:knx_monitor/ui/recordings_screen.dart';
import 'package:knx_monitor/ui/telegram_row.dart' show formatDate;
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_storage.dart';

// The new parts of issue #5 on the smallest phone at text size 2.0 (375 × 667 pt, real fonts)
// and on a wide window: nothing overflows, and the actions do what they say.

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

GroupCatalog _project(Map<int, (String, Dpt?)> groups, {String? name}) => GroupCatalog({
  for (final MapEntry(:key, :value) in groups.entries)
    key: GroupInfo(address: key, name: value.$1, dpt: value.$2, path: 'Beleuchtung › Erdgeschoss'),
}, projectName: name);

final _old = _project({
  0x0801: ('Licht Küche Arbeitsfläche schalten', const Dpt(1, 1)),
  0x0802: ('Licht Flur', const Dpt(1, 1)),
  0x0803: ('Rollladen Wohnzimmer Süd', null),
}, name: 'Einfamilienhaus Mustermann 2024');
final _new = _project({
  0x0801: ('Temperatur Küche Istwert', const Dpt(9, 1)),
  0x0802: ('Licht Flur', const Dpt(1, 1)),
  0x0804: ('Präsenzmelder Hauswirtschaftsraum', const Dpt(1, 1)),
}, name: 'Einfamilienhaus Mustermann 2026');

Telegram _telegram(DateTime time, {int destination = 0x0801}) => Telegram(
  time: time,
  source: 0x1101,
  destination: destination,
  type: TelegramType.write,
  data: Uint8List.fromList([1]),
  isSmall: true,
);

void main() {
  final store = CatalogStore.instance;
  setUpAll(_loadFonts);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppStorage.instance = MemoryStorage();
    await store.reload();
    CatalogStore.now = () => DateTime(2026, 3, 10, 9, 30);
    await store.adopt(_old, name: 'Mustermann-alt.knxproj');
    CatalogStore.now = () => DateTime(2026, 9, 14, 16);
    await store.adopt(_new, name: 'Mustermann-Umbau-Herbst.knxproj');
    CatalogStore.now = () => DateTime(2026, 11, 11);
  });

  tearDown(() {
    CatalogStore.now = DateTime.now;
    LocaleController.instance.debugSetLocale(const Locale('de'));
    debugDefaultTargetPlatformOverride = null;
  });

  /// Pumps [home] and returns the layout errors (overflow) of its first frames.
  Future<List<String>> pump(
    WidgetTester tester,
    Widget home, {
    Size size = const Size(375, 667),
    double scale = 2,
    Locale locale = const Locale('de'),
  }) async {
    LocaleController.instance.debugSetLocale(locale);
    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split('\n').first);
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
    // Back before any expect: a failing expect under a foreign handler stalls the test run.
    // Whatever overflows after this (pages opened by a tap) fails the test the usual way.
    FlutterError.onError = previous;
    return errors;
  }

  for (final locale in const [Locale('de'), Locale('en')]) {
    testWidgets('states list on a phone at text size 2.0 (${locale.languageCode})', (tester) async {
      final errors = await pump(tester, const ProjectStatesScreen(), locale: locale);
      final l = lookupAppLocalizations(locale);
      final since = l.projectStateSince(formatDate(DateTime(2026, 9, 14)));
      expect(find.text(l.projectStateCurrent), findsOneWidget);
      expect(find.text(since), findsOneWidget);
      expect(find.textContaining(l.projectStateRenamed(1)), findsOneWidget);
      expect(find.textContaining(l.projectStateRetyped(1)), findsOneWidget);
      // Tap targets of the two actions.
      for (final button in tester.widgetList<TextButton>(find.byType(TextButton))) {
        expect(tester.getSize(find.byWidget(button)).height, greaterThanOrEqualTo(44));
      }
      // The changes on their own page.
      await tester.tap(find.text(since));
      await tester.pumpAndSettle();
      expect(find.text(l.projectStateAddedTitle), findsOneWidget);
      expect(find.textContaining('Präsenzmelder Hauswirtschaftsraum'), findsOneWidget);
      expect(find.textContaining('← Licht Küche Arbeitsfläche schalten'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('DPT 1.001 → DPT 9.001'), 200);
      expect(find.text(l.projectStateRetypedTitle), findsOneWidget);
      // Back in the list: the oldest state further down.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(l.projectStateFromStart), 200);
      expect(find.text(l.projectStateFirst), findsOneWidget);
      expect(errors, isEmpty);
    });
  }

  testWidgets('wide window: list and changes side by side', (tester) async {
    final errors = await pump(tester, const ProjectStatesScreen(), size: const Size(1400, 900), scale: 1);
    final l = lookupAppLocalizations(const Locale('de'));
    // The newest state is selected: its changes are there without a tap.
    expect(find.text(l.projectStateRemovedTitle), findsOneWidget);
    expect(find.textContaining('Rollladen Wohnzimmer Süd'), findsOneWidget);
    expect(find.text(l.projectStateFromStart), findsOneWidget);
    final list = tester.getTopLeft(find.text(l.projectStateFromStart)).dx;
    final detail = tester.getTopLeft(find.text(l.projectStateRemovedTitle)).dx;
    expect(detail, greaterThan(list + 400), reason: 'the changes have their own column');
    expect(errors, isEmpty);
  });

  testWidgets('date corrected through the picker, state removed after confirmation', (tester) async {
    final errors = await pump(tester, const ProjectStatesScreen(), scale: 1);
    final l = lookupAppLocalizations(const Locale('de'));
    // The oldest state has no date to set: one button for the two states.
    expect(find.text(l.projectStateSetDate), findsOneWidget);
    await tester.tap(find.text(l.projectStateSetDate));
    await tester.pumpAndSettle();
    expect(find.text(l.projectStateDateHelp), findsOneWidget);
    await tester.tap(find.text('3'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(store.projectStates.last.from, DateTime(2026, 9, 3));
    expect(find.text(l.projectStateSince('03.09.2026')), findsOneWidget);

    await tester.ensureVisible(find.text(l.projectStateRemove).first);
    await tester.tap(find.text(l.projectStateRemove).first);
    await tester.pumpAndSettle();
    expect(find.text(l.projectStateRemoveCurrent), findsOneWidget);
    await tester.tap(find.text(l.commonCancel));
    await tester.pumpAndSettle();
    expect(store.projectStates, hasLength(2));
    await tester.tap(find.text(l.projectStateRemove).first);
    await tester.pumpAndSettle();
    // Title and action of the dialog carry the words; the action comes last.
    await tester.tap(find.text(l.projectStateRemove).last);
    await tester.pumpAndSettle();
    expect(store.projectStates, hasLength(1));
    expect(store.project.projectName, 'Einfamilienhaus Mustermann 2024');
    // One state: nothing to remove, no date.
    expect(find.text(l.projectStateRemove), findsNothing);
    expect(find.text(l.projectStateSetDate), findsNothing);
    expect(errors, isEmpty);
  });

  test('days a state may begin on', () {
    final now = DateTime(2026, 11, 11, 15);
    expect(projectStateDays((after: null, before: null), now), (first: DateTime(2000), last: DateTime(2026, 11, 11)));
    expect(projectStateDays((after: DateTime(2026, 3, 10, 9, 30), before: DateTime(2026, 9, 14, 16)), now), (
      first: DateTime(2026, 3, 11),
      last: DateTime(2026, 9, 14),
    ));
    // The next state begins at midnight: the day before is the last one.
    expect(
      projectStateDays((after: DateTime(2026, 3, 10), before: DateTime(2026, 9, 14)), now)!.last,
      DateTime(2026, 9, 13),
    );
    // Two imports on the same day leave no day between them.
    expect(projectStateDays((after: DateTime(2026, 9, 14, 8), before: DateTime(2026, 9, 14, 16)), now), isNull);
    expect(projectStateDays((after: DateTime(2026, 11, 11, 8), before: null), now), isNull);
  });

  testWidgets('row in the project sheet opens the states (text size 2.0)', (tester) async {
    final errors = await pump(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(onPressed: () => showProjectSheet(context), child: const Text('Projekt')),
          ),
        ),
      ),
    );
    final l = lookupAppLocalizations(const Locale('de'));
    await tester.tap(find.text('Projekt'));
    await tester.pumpAndSettle();
    final row = find.text(l.projectStatesRow(2));
    await tester.ensureVisible(row);
    expect(
      tester.getSize(find.ancestor(of: row, matching: find.byType(InkWell)).first).height,
      greaterThanOrEqualTo(44),
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(ProjectStatesScreen), findsOneWidget);
    expect(errors, isEmpty);
  });

  testWidgets('without a project the sheet has no states row', (tester) async {
    await store.clear();
    await pump(tester, const Scaffold(body: ProjectStatesRow()), scale: 1);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('an old telegram says quietly which state names it', (tester) async {
    final l = lookupAppLocalizations(const Locale('de'));
    final errors = await pump(
      tester,
      Scaffold(
        body: Column(
          children: [
            PastStateNote(telegram: _telegram(DateTime(2026, 5))),
            PastStateNote(telegram: _telegram(DateTime(2026, 5), destination: 0x0803)),
            PastStateNote(telegram: _telegram(DateTime(2026, 5), destination: 0x0802)),
            PastStateNote(telegram: _telegram(DateTime(2026, 10))),
          ],
        ),
      ),
    );
    final note = l.projectStateNote('14.09.2026');
    // Renamed since: today's name next to it. Gone since. Unchanged: only the state.
    expect(find.text('$note ${l.projectStateNoteToday('Temperatur Küche Istwert')}'), findsOneWidget);
    expect(find.text('$note ${l.projectStateNoteGone}'), findsOneWidget);
    expect(find.text(note), findsOneWidget);
    // A telegram of the current state: nothing.
    expect(find.textContaining(note), findsNWidgets(3));
    expect(errors, isEmpty);
  });

  testWidgets('a recording says where it comes from; an ordinary one says nothing', (tester) async {
    final l = lookupAppLocalizations(const Locale('de'));
    Recording recording(DateTime at, {ImportOrigin? imported}) => Recording(
      id: 'r${at.microsecondsSinceEpoch}',
      name: 'Aufnahme',
      started: at,
      ended: at.add(const Duration(minutes: 5)),
      telegrams: [_telegram(at)],
      imported: imported,
    );
    final errors = await pump(
      tester,
      Scaffold(
        body: Column(
          children: [
            RecordingOriginNote(
              recording: recording(
                DateTime(2026, 5),
                imported: ImportOrigin(
                  file: 'Gruppenmonitor-Mustermann-Mai.xml',
                  format: 'etsXml',
                  at: DateTime(2026, 11, 11),
                ),
              ),
            ),
            RecordingOriginNote(recording: recording(DateTime(2026, 10))),
          ],
        ),
      ),
    );
    expect(find.textContaining(l.recImportedFrom('Gruppenmonitor-Mustermann-Mai.xml')), findsOneWidget);
    expect(find.textContaining(l.recImportFormatEtsXml), findsOneWidget);
    expect(find.textContaining(l.projectStateRecordingNote('14.09.2026')), findsOneWidget);
    expect(find.byType(Text), findsOneWidget, reason: 'the recording of today has no note');
    expect(errors, isEmpty);
  });

  for (final locale in const [Locale('de'), Locale('en')]) {
    testWidgets('import preview at text size 2.0 (${locale.languageCode})', (tester) async {
      final l = lookupAppLocalizations(locale);
      final found = RecordingImport(
        format: RecordingFormat.etsXml,
        fileName: 'Gruppenmonitor-Mustermann-Inbetriebnahme-Mai.xml',
        telegrams: [_telegram(DateTime(2026, 5, 3, 8)), _telegram(DateTime(2026, 5, 4, 17, 30))],
        skipped: {TelegramSkip.frame: 1204, TelegramSkip.noData: 3, TelegramSkip.time: 2, TelegramSkip.line: 1},
      );
      String? result = 'unset';
      final errors = await pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showAdaptiveDialog<String>(
                context: context,
                builder: (_) => RecordingImportDialog(found: found),
              ),
              child: const Text('open'),
            ),
          ),
        ),
        locale: locale,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(l.recImportFormatEtsXml), findsOneWidget);
      expect(find.text('Gruppenmonitor-Mustermann-Inbetriebnahme-Mai.xml'), findsOneWidget);
      expect(find.textContaining(formatDate(DateTime(2026, 5, 3))), findsOneWidget);
      expect(find.textContaining(l.recImportSkipFrame(1204)), findsOneWidget);
      expect(find.text(formatInt(1210)), findsOneWidget);
      // Older than the current project state: said before importing.
      expect(find.text(l.recImportState(formatDate(DateTime(2026, 9, 14)))), findsOneWidget);
      final confirm = find.text(l.recImportConfirm);
      expect(
        tester.getSize(find.ancestor(of: confirm, matching: find.bySubtype<ButtonStyleButton>())).height,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(result, 'Gruppenmonitor-Mustermann-Inbetriebnahme-Mai');
      expect(errors, isEmpty);
    });
  }

  testWidgets('import preview cancelled saves nothing', (tester) async {
    final l = lookupAppLocalizations(const Locale('de'));
    final found = RecordingImport(
      format: RecordingFormat.csv,
      fileName: 'a.csv',
      telegrams: [_telegram(DateTime(2026, 10))],
      skipped: const {},
    );
    String? result = 'unset';
    await pump(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showAdaptiveDialog<String>(
              context: context,
              builder: (_) => RecordingImportDialog(found: found),
            ),
            child: const Text('open'),
          ),
        ),
      ),
      scale: 1,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(l.recImportSkippedNone), findsOneWidget);
    expect(find.textContaining(l.recImportState('14.09.2026')), findsNothing);
    await tester.tap(find.text(l.commonCancel));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  test('every import error has its sentence', () {
    LocaleController.instance.debugSetLocale(const Locale('de'));
    final texts = {
      for (final e in RecordingImportError.values)
        recordingImportError(RecordingImportException(e, limit: 100, detail: 'Zeile 3')),
    };
    expect(texts, hasLength(RecordingImportError.values.length));
    expect(texts.every((t) => t.trim().isNotEmpty), isTrue);
  });
}
