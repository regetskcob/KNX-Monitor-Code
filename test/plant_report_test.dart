import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/export/pdf_export.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/customer.dart';
import 'package:knx_monitor/model/plan.dart';
import 'package:knx_monitor/model/plant_report.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/plan_screen.dart' show featureName;
import 'package:knx_monitor/ui/common.dart';
import 'package:knx_monitor/ui/figure_box.dart';
import 'package:knx_monitor/ui/plant_report_screen.dart';

import 'window.dart';

final _from = DateTime(2026, 10);
final _to = DateTime(2026, 11);

PlantReport _report({bool partial = false, List<Map<String, Object?>>? findings}) => PlantReport({
  'version': 1,
  'id': '2026-10',
  'period': 'monthly',
  'from': _from.millisecondsSinceEpoch,
  'to': _to.millisecondsSinceEpoch,
  'generated': _to.millisecondsSinceEpoch,
  if (partial) 'partial': true,
  'coverage': {'days': 28, 'total': 31},
  'availability': {
    'ratio': 0.982,
    'outages': [
      {
        'from': DateTime(2026, 10, 3).millisecondsSinceEpoch,
        'to': DateTime(2026, 10, 4).millisecondsSinceEpoch,
        'kind': 'offline',
      },
    ],
    'restarts': const <Object?>[],
  },
  'traffic': {
    'total': 12345,
    'avgPerDay': 440,
    'peakDay': '2026-10-05',
    'peakDayCount': 900,
    'topSenders': [
      {'address': 0x1105, 'label': '1.1.5', 'count': 8000},
    ],
  },
  'load': {
    'average': 0.012,
    'peak': 0.08,
    'lines': [
      {'line': '1.1', 'average': 0.012, 'peak': 0.08},
    ],
  },
  'repeats': [
    {'address': 0x1106, 'label': '1.1.6', 'count': 100, 'repeats': 9, 'rate': 0.09},
  ],
  'safety': [
    {'address': 0x0801, 'label': '1/0/1', 'name': 'Rauchmelder Flur', 'kind': 'alarm', 'state': 'ok'},
  ],
  'findings':
      findings ??
      [
        {
          'key': 'deviceSilent:4357',
          'kind': 'deviceSilent',
          'level': 'warning',
          'status': 'new',
          'label': '1.1.5',
          'since': DateTime(2026, 10, 9).millisecondsSinceEpoch,
        },
      ],
  'resolved': [
    {'key': 'repeats:7', 'kind': 'repeats', 'level': 'warning', 'label': '1.1.7', 'rate': 0.06},
  ],
  'maintenanceDue': DateTime(2026, 12).millisecondsSinceEpoch,
});

class _FakeClient extends PlantReportClient {
  _FakeClient(this.settings);
  Map<String, Object?> settings;
  final changes = <Map<String, Object?>>[];
  int tests = 0;

  @override
  Future<PlantReportOverview> overview() async =>
      PlantReportOverview({'settings': settings, 'reports': const <Object?>[]});

  @override
  Future<PlantReportOverview> configure(Map<String, Object?> c) async {
    changes.add(c);
    settings = {...settings, ...c};
    return overview();
  }

  @override
  Future<String?> sendTest() async {
    tests++;
    return 'http401';
  }
}

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('de'),
  home: child,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('liest Zahlen und Befunde aus dem Bericht', () {
    final r = _report();
    expect(r.availability, 0.982);
    expect(r.coveredDays, 28);
    expect(r.attention, 1);
    expect(r.outages, hasLength(1));
    expect(r.lastDay.day, 31);
  });

  test('alle Befundarten haben einen Text', () {
    for (final kind in [
      'deviceSilent',
      'cyclicSilent',
      'stuck',
      'repeats',
      'busLoad',
      'outages',
      'restarts',
      'alarmActive',
      'faultActive',
      'batteryLow',
    ]) {
      final text = plantFindingText({'kind': kind, 'label': '1.1.5', 'rate': 0.1, 'count': 2, 'since': 0});
      expect(text, isNotEmpty, reason: kind);
    }
    expect(plantFindingStatus('new'), isNotNull);
    expect(plantFindingStatus('first'), isNull);
  });

  test('PDF entsteht mit und ohne Kundendaten', () async {
    final pdf = await buildPdf(
      PlantReportPdf(
        _report(),
        customer: 'Familie Muster',
        site: 'Hauptstr. 1\nKalkar',
        project: 'Haus',
        nextMaintenance: DateTime(2026, 12),
      ),
    );
    expect(pdf.length, greaterThan(1000));
    expect(await buildPdf(PlantReportPdf(_report(partial: true, findings: const []))), isNotEmpty);
  });

  test('Bericht-PDF hat den Bericht als Besuchsart, ohne Wartung neu anzusetzen', () {
    expect(VisitKind.report.countsAsMaintenance, isFalse);
    final v = Visit(id: '1', time: DateTime(2026), kind: VisitKind.report);
    expect(Visit.fromJson(v.toJson()).kind, VisitKind.report);
  });

  test('Stufe: Pro, mit Namen auf der Bezahlseite', () {
    expect(Feature.plantReport.tier, Tier.pro);
    expect(featureName(Feature.plantReport), isNotEmpty);
  });

  testWidgets('Standard aus: Schalter aus, kein Mitteilungsziel, kein Testknopf', (tester) async {
    final client = _FakeClient({'enabled': false, 'notifyKind': 'off'});
    await tester.pumpWidget(_app(PlantReportScreen(client: client)));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);
    expect(find.text('Test senden'), findsNothing);
    expect(find.text('Zugangstoken'), findsNothing);
  });

  testWidgets('Test meldet den Grund, das Token steht nicht im Feld', (tester) async {
    final client = _FakeClient({
      'enabled': true,
      'notifyKind': 'webhook',
      'notifyUrl': 'https://example.org/hook',
      'hasNotifyToken': true,
    });
    tester.view
      ..physicalSize = const Size(1200, 3000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(PlantReportScreen(client: client)));
    await tester.pumpAndSettle();
    expect(find.text('Gespeichert; leer lassen, um es zu behalten'), findsOneWidget);
    await tester.ensureVisible(find.text('Test senden'));
    await tester.tap(find.text('Test senden'));
    await tester.pumpAndSettle();
    expect(client.tests, 1);
    expect(find.textContaining('HTTP 401'), findsWidgets);
    expect(client.changes.single.containsKey('notifyToken'), isFalse, reason: 'leer heißt unverändert');
  });

  testWidgets('Bericht zeigt Ergebnis, Vergleich und Stand der Melder', (tester) async {
    await tester.pumpWidget(_app(PlantReportDetailScreen(report: _report())));
    await tester.pumpAndSettle();
    expect(find.text('1 Punkt braucht Aufmerksamkeit.'), findsOneWidget);
    expect(find.textContaining('antwortet nicht mehr seit'), findsOneWidget);
    expect(find.text('neu'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('behoben'), 200);
    expect(find.text('behoben'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('in Ordnung'), 200);
    expect(find.text('in Ordnung'), findsOneWidget);
  });

  testWidgets('Bericht im breiten Fenster: Befunde links, Kennzahlen des Busses rechts daneben', (tester) async {
    await pumpWindow(tester, PlantReportDetailScreen(report: _report()), wideWindow);
    await tester.pumpAndSettle();
    final findings = tester.getTopLeft(find.text('Befunde'));
    final outages = tester.getTopLeft(find.text('Ausfälle'));
    expect(findings.dx, lessThan(wideWindow.width / 2));
    expect(outages.dx, greaterThan(wideWindow.width / 2));
    expect(outages.dy, findings.dy);
    expect(find.byType(SectionCard), findsWidgets);
    await pumpWindow(tester, PlantReportDetailScreen(report: _report()), phoneWindow, textScale: 2);
    await tester.pumpAndSettle();
    expect(find.byType(SectionCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('Breite', () {
    final settings = {'enabled': true, 'notifyKind': 'ntfy', 'notifyUrl': 'https://ntfy.sh', 'notifyTopic': 'haus'};

    testWidgets('1400 pt: Einstellungen, Wartung und Mitteilungen links, Berichte rechts daneben', (tester) async {
      await pumpWindow(tester, PlantReportScreen(client: _FakeClient(settings)), wideWindow);
      await tester.pumpAndSettle();
      expect(columnsOf(tester, find.byType(SectionHead)), hasLength(2));
      final left = tester.getTopLeft(find.text('Einstellungen'));
      final right = tester.getTopLeft(find.text('Berichte'));
      expect(right.dx, greaterThan(wideWindow.width / 2));
      expect(right.dy, left.dy, reason: 'beide Spalten beginnen oben');
      for (final head in ['Wartung', 'Mitteilungen']) {
        expect(tester.getTopLeft(find.text(head)).dx, left.dx);
      }
      // Every field keeps its label.
      for (final label in ['Zeitraum', 'Ziel', 'Adresse', 'Topic', 'Zugangstoken']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Zwischenstand erstellen'), findsOneWidget);
    });

    testWidgets('Telefon: eine Liste wie bisher, auch bei doppelter Schrift ohne Überlauf', (tester) async {
      for (final scale in [1.0, 2.0]) {
        await pumpWindow(tester, PlantReportScreen(client: _FakeClient(settings)), phoneWindow, textScale: scale);
        await tester.pumpAndSettle();
        expect(find.byType(SectionHead), findsNothing);
        expect(find.byType(ListView), findsOneWidget);
        expect(find.text('Einstellungen'), findsNothing);
      }
    });
  });
}
