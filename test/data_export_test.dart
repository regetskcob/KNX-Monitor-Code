import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/data_export.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/data_export_screen.dart';

class _FakeClient extends DataExportClient {
  _FakeClient(this.settings, {this.generated});
  Map<String, Object?> settings;
  final String? generated;
  final saved = <Map<String, Object?>>[];

  @override
  Future<DataExportState> load() async => DataExportState({'settings': settings});

  @override
  Future<DataExportState> save(Map<String, Object?> changes) async {
    saved.add(changes);
    settings = {...settings, ...changes};
    return DataExportState({'settings': settings, 'generatedToken': ?generated});
  }
}

void main() {
  Widget app(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('de'),
    home: child,
  );

  void tall(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(1200, 3000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('Standard aus: alle Schalter aus, keine Zielfelder', (tester) async {
    tall(tester);
    await tester.pumpWidget(app(DataExportScreen(client: _FakeClient(const {}))));
    await tester.pumpAndSettle();
    final switches = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile));
    expect(switches.map((x) => x.value), everyElement(isFalse));
    expect(find.text('Adresse'), findsNothing);
    expect(find.text('Verbindung testen'), findsNothing);
  });

  testWidgets('leeres Token wird nicht mitgeschickt, gespeichertes nicht angezeigt', (tester) async {
    tall(tester);
    final client = _FakeClient(const {
      'influx': true,
      'influxUrl': 'http://192.168.1.10:8086',
      'influxOrg': 'o',
      'influxBucket': 'b',
      'hasInfluxToken': true,
    });
    await tester.pumpWidget(app(DataExportScreen(client: client)));
    await tester.pumpAndSettle();
    expect(find.text('Gespeichert; leer lassen, um es zu behalten'), findsOneWidget);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(client.saved.single.containsKey('influxToken'), isFalse);
    expect(client.saved.single['influxUrl'], 'http://192.168.1.10:8086');
  });

  testWidgets('neues Prometheus-Token erscheint genau einmal', (tester) async {
    tall(tester);
    final client = _FakeClient(const {'prometheus': true}, generated: 'neues-token');
    await tester.pumpWidget(app(DataExportScreen(client: client)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('neues-token'), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    expect(find.text('neues-token'), findsNothing);
  });
}
