import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/coupler_filter.dart';
import 'package:knx_monitor/model/ets_tasks.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/project_check_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_storage.dart';

final _ga = parseGroup('1/0/1')!;
final _other = parseGroup('1/0/2')!;
final _t0 = DateTime(2026, 10, 30, 8);

int _pa(String s) => parseIndividual(s)!;

const _send = ComFlags(transmit: true);
const _hear = ComFlags(write: true);

GroupInfo _group(int address, {required String from, required List<String> to}) => GroupInfo(
  address: address,
  name: 'Licht',
  links: [
    GroupLink(device: _pa(from), sends: true, flags: _send),
    for (final d in to) GroupLink(device: _pa(d), flags: _hear),
  ],
);

GroupCatalog _catalog(List<GroupInfo> groups) => GroupCatalog(
  {for (final g in groups) g.address: g},
  devices: {
    for (final g in groups)
      for (final l in g.links) l.device: DeviceInfo(address: l.device, name: 'G'),
  },
);

Telegram _t(int ga, String source, int minutes, {int hop = 6, bool outgoing = false, TelegramType? type}) => Telegram(
  time: _t0.add(Duration(minutes: minutes)),
  source: _pa(source),
  destination: ga,
  type: type ?? TelegramType.write,
  data: Uint8List.fromList([1]),
  isSmall: true,
  hopCount: hop,
  outgoing: outgoing,
);

FilterObservation _point(String name, String line, List<Telegram> telegrams, {int minutes = 30}) => FilterObservation(
  name: name,
  line: _pa('$line.0') >> 8,
  from: _t0,
  to: _t0.add(Duration(minutes: minutes)),
  telegrams: telegrams,
);

void main() {
  group('Linie eines Mitschnitts', () {
    test('Eigene Telegramme sind sicher', () {
      expect(observationLine([_t(_ga, '1.2.200', 0, outgoing: true), _t(_ga, '1.1.5', 1)]), _pa('1.2.0') >> 8);
    });

    test('Sonst die klare Mehrheit der direkten Telegramme', () {
      final direct = [
        _t(_ga, '1.1.5', 0),
        _t(_ga, '1.1.6', 1),
        _t(_ga, '1.2.7', 2, hop: 5),
        _t(_ga, '1.2.8', 3, hop: 5),
      ];
      expect(observationLine(direct), _pa('1.1.0') >> 8, reason: 'Über Koppler zählt nicht');
    });

    test('Unklar: kein Beobachtungspunkt', () {
      expect(observationLine([_t(_ga, '1.1.5', 0), _t(_ga, '1.2.5', 1)]), isNull);
      expect(FilterObservation.of('x', const []), isNull);
    });
  });

  group('Aus dem Projekt', () {
    test('Sender und Empfänger auf verschiedenen Linien', () {
      final check = FilterCheck.of(
        _catalog([
          _group(_ga, from: '1.1.5', to: ['1.2.1', '1.1.9']),
          _group(_other, from: '1.1.5', to: ['1.1.9']),
        ]),
      );
      expect(check.crossLine.map((c) => c.group.address), [_ga]);
      expect(check.crossLine.single.open, {_pa('1.2.0') >> 8});
      expect(check.openByLine, {_pa('1.2.0') >> 8: 1});
      expect(check.comparedPoints, 0);
    });

    test('Ohne Flags sagen wir nichts', () {
      final csv = GroupInfo(
        address: _ga,
        name: 'x',
        links: [
          GroupLink(device: _pa('1.1.5'), sends: true),
          GroupLink(device: _pa('1.2.1')),
        ],
      );
      expect(FilterCheck.of(_catalog([csv])).crossLine, isEmpty);
    });

    test('Hauptgruppe 14 und 15 nur bei mehreren Linien', () {
      final high = parseGroup('14/0/1')!;
      final two = FilterCheck.of(
        _catalog([
          _group(high, from: '1.1.5', to: ['1.2.1']),
        ]),
      );
      expect(two.mainGroups.single.address, high);
      final one = FilterCheck.of(
        _catalog([
          _group(high, from: '1.1.5', to: ['1.1.1']),
        ]),
      );
      expect(one.mainGroups, isEmpty);
    });
  });

  group('Aus dem Mitschnitt', () {
    final catalog = _catalog([
      _group(_ga, from: '1.1.5', to: ['1.2.1']),
    ]);
    final onA = [_t(_ga, '1.1.5', 1), _t(_ga, '1.1.5', 2), _t(_ga, '1.1.5', 3)];

    test('Auf einer Linie gesehen, auf der anderen nicht: vermutlich gefiltert', () {
      final check = FilterCheck.of(
        catalog,
        observations: [
          _point('A', '1.1', onA),
          _point('B', '1.2', [_t(_other, '1.2.9', 4)]),
        ],
      );
      final found = check.notForwarded.single;
      expect(found.seenOn, _pa('1.1.0') >> 8);
      expect(found.missingOn, _pa('1.2.0') >> 8);
      expect(found.count, 3);
      expect(check.comparedPoints, 1);
    });

    test('Nur ein Beobachtungspunkt: keine Aussage über „nicht gesehen“', () {
      expect(FilterCheck.of(catalog, observations: [_point('A', '1.1', onA)]).notForwarded, isEmpty);
    });

    test('Zwei Punkte auf derselben Linie vergleichen nichts', () {
      final check = FilterCheck.of(catalog, observations: [_point('A', '1.1', onA), _point('B', '1.1', const [])]);
      expect(check.notForwarded, isEmpty);
      expect(check.comparedPoints, 0);
    });

    test('Keine zeitliche Überschneidung, zu kurz oder zu selten: nichts', () {
      final later = FilterObservation(
        name: 'B',
        line: _pa('1.2.0') >> 8,
        from: _t0.add(const Duration(hours: 2)),
        to: _t0.add(const Duration(hours: 3)),
        telegrams: const [],
      );
      expect(FilterCheck.of(catalog, observations: [_point('A', '1.1', onA), later]).notForwarded, isEmpty);
      final short = [_point('A', '1.1', onA, minutes: 5), _point('B', '1.2', const [])];
      expect(FilterCheck.of(catalog, observations: short).notForwarded, isEmpty);
      final once = [
        _point('A', '1.1', [_t(_ga, '1.1.5', 1)]),
        _point('B', '1.2', const []),
      ];
      expect(FilterCheck.of(catalog, observations: once).notForwarded, isEmpty);
    });

    test('Ohne Empfänger auf der anderen Linie ist „nicht gesehen“ richtig', () {
      final local = _catalog([
        _group(_ga, from: '1.1.5', to: ['1.1.1']),
      ]);
      final check = FilterCheck.of(local, observations: [_point('A', '1.1', onA), _point('B', '1.2', const [])]);
      expect(check.notForwarded, isEmpty);
    });

    test('Auf beiden Linien gesehen: nichts, und der Übergang gilt als belegt', () {
      final check = FilterCheck.of(
        catalog,
        observations: [
          _point('A', '1.1', onA),
          _point('B', '1.2', [_t(_ga, '1.1.5', 1, hop: 5)]),
        ],
      );
      expect(check.notForwarded, isEmpty);
      expect(check.crossLine.single.confirmed, {_pa('1.2.0') >> 8});
      expect(check.crossLine.single.open, isEmpty);
      expect(check.openByLine, isEmpty);
    });

    test('Leseanfragen und eigene Telegramme belegen nichts', () {
      final check = FilterCheck.of(
        catalog,
        observations: [
          _point('A', '1.1', [_t(_ga, '1.1.5', 1, type: TelegramType.read), _t(_ga, '1.1.200', 2, outgoing: true)]),
          _point('B', '1.2', const []),
        ],
      );
      expect(check.notForwarded, isEmpty);
    });
  });

  group('Aufgaben für die ETS', () {
    final catalog = _catalog([
      _group(_ga, from: '1.1.5', to: ['1.2.1']),
    ]);

    test('Übergang als Hinweis je Linie', () {
      final tasks = EtsTasks.of(catalog, const {});
      final task = tasks.project.singleWhere((t) => t.kind == EtsTaskKind.filterCrossLine);
      expect(task.line, _pa('1.2.0') >> 8);
      expect(task.count, 1);
      expect(task.hint, isTrue);
    });

    test('Nicht durchgelassen als Hinweis an der Adresse', () {
      final tasks = EtsTasks.of(
        catalog,
        const {},
        observations: [
          _point('A', '1.1', [_t(_ga, '1.1.5', 1), _t(_ga, '1.1.5', 2)]),
          _point('B', '1.2', const []),
        ],
      );
      final task = tasks.groups.singleWhere((t) => t.kind == EtsTaskKind.filterNotForwarded);
      expect(task.group, _ga);
      expect(task.hint, isTrue);
      expect(task.kind.importable, isFalse);
    });
  });

  testWidgets('Prüfregeln zeigen den Abschnitt mit Vermutung', (tester) async {
    SharedPreferences.setMockInitialValues({});
    AppStorage.instance = MemoryStorage();
    InstallationStore.instance.debugReset();
    final store = CatalogStore.instance
      ..catalog = _catalog([
        _group(_ga, from: '1.1.5', to: ['1.2.1']),
      ]);
    addTearDown(() => store.catalog = GroupCatalog.empty);
    final log = TelegramLog();
    addTearDown(log.dispose);
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: ProjectCheckScreen(log: log, onFilter: (_) {}),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(find.textContaining(RegExp('Filtertabellen', caseSensitive: false)), findsWidgets);
    expect(find.textContaining('vermutlich nur an'), findsOneWidget);
    expect(find.textContaining('nur eine Vermutung', findRichText: true), findsWidgets);
  });

  test('Die Prüfung schreibt und liest keinen Koppler', () {
    for (final file in ['lib/model/coupler_filter.dart', 'lib/ui/filter_observations.dart']) {
      final source = File(file).readAsStringSync();
      for (final banned in ['knx_tunnel', 'KnxTunnel', 'memoryRead', 'memoryWrite', 'propertyWrite', 'knx_device']) {
        expect(source.contains(banned), isFalse, reason: '$file: $banned');
      }
    }
  });

  test('Texte sprechen von Vermutung, nicht von Tatsache', () {
    final de = File('lib/l10n/app_de.arb').readAsStringSync();
    for (final key in ['checkFilterMissingRow', 'checkFilterCrossRow', 'checkFilterConfirmedRow']) {
      expect(RegExp('"$key": "[^"]*[Vv]ermutlich').hasMatch(de), isTrue, reason: key);
    }
    final en = File('lib/l10n/app_en.arb').readAsStringSync();
    expect(RegExp('"checkFilterMissingRow": "[^"]*presumably').hasMatch(en), isTrue);
  });
}
