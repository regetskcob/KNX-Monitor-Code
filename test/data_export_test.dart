import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/data_export.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/data_export_screen.dart';

class _FakeClient extends DataExportClient {
  _FakeClient(this.settings, {this.generated, this.mqtt, this.health});
  Map<String, Object?> settings;
  final String? generated;
  final Map<String, Object?>? mqtt;
  final Map<String, Object?>? health;
  final saved = <Map<String, Object?>>[];

  @override
  Future<DataExportState> load() async =>
      DataExportState({'settings': settings, 'mqttTelegrams': ?mqtt, 'healthCheck': ?health});

  @override
  Future<DataExportState> save(Map<String, Object?> changes) async {
    saved.add(changes);
    settings = {...settings, ...changes};
    return DataExportState({'settings': settings, 'generatedToken': ?generated});
  }

  final mqttSaved = <Map<String, Object?>>[];
  Map<String, Object?>? mqttNow;

  @override
  Future<DataExportState> saveMqtt(Map<String, Object?> changes) async {
    mqttSaved.add(changes);
    mqttNow = changes['reset'] == true
        ? {...?mqtt, 'source': 'default'}
        : {...?mqtt, ...changes, 'source': 'app', 'connected': true, 'seq': 0};
    return DataExportState({'settings': settings, 'mqttTelegrams': mqttNow});
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

  testWidgets('health check of the server (#12): one line, also without MQTT; nothing on older servers', (
    tester,
  ) async {
    tall(tester);
    await tester.pumpWidget(app(DataExportScreen(client: _FakeClient(const {}))));
    await tester.pumpAndSettle();
    final section = find.text('Home Assistant');
    expect(section, findsNothing);
    expect(find.textContaining('Gesundheitsprüfung'), findsNothing);

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final at = DateTime(yesterday.year, yesterday.month, yesterday.day, 3, 5);
    String two(int n) => n.toString().padLeft(2, '0');
    for (final (health, text) in [
      (const <String, Object?>{'enabled': false}, 'Gesundheitsprüfung am Server aus. Einschalten:'),
      (const <String, Object?>{'enabled': true, 'status': null, 'time': null}, 'noch kein Lauf'),
      (
        <String, Object?>{
          'enabled': true,
          'status': 'faults',
          'time': at.toUtc().toIso8601String(),
          'counts': {'total': 3, 'errors': 1},
        },
        'Letzter Lauf ${two(at.day)}.${two(at.month)}. 03:05: 3 Befunde.',
      ),
      (
        <String, Object?>{
          'enabled': true,
          'status': 'ok',
          'time': at.toUtc().toIso8601String(),
          'counts': {'total': 0},
        },
        'keine Befunde',
      ),
    ]) {
      await tester.pumpWidget(
        app(
          DataExportScreen(
            key: UniqueKey(),
            client: _FakeClient(const {}, health: health),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(section, findsOneWidget, reason: '$health');
      expect(find.textContaining(text), findsOneWidget, reason: '$health');
      expect(find.textContaining('Gesundheitsprüfung'), findsOneWidget, reason: 'one line only');
      expect(tester.takeException(), isNull);
    }
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

  testWidgets('MQTT telegram stream: no section without broker, reasons for left-out secure telegrams', (tester) async {
    tall(tester);
    await tester.pumpWidget(app(DataExportScreen(client: _FakeClient(const {}))));
    await tester.pumpAndSettle();
    expect(find.text('MQTT: jedes Telegramm (Vorschau)'), findsNothing);

    await tester.pumpWidget(
      app(
        DataExportScreen(
          key: const ValueKey('off'),
          client: _FakeClient(const {}, mqtt: {'enabled': false}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('MQTT_TELEGRAMS=true'), findsOneWidget);

    await tester.pumpWidget(
      app(
        DataExportScreen(
          key: const ValueKey('on'),
          client: _FakeClient(
            const {},
            mqtt: {'enabled': true, 'connected': true, 'sent': 120, 'dropped': 0, 'secureSkipped': 7, 'undecrypted': 3},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('120 gesendet'), findsOneWidget);
    expect(find.textContaining('7 KNX-Secure-Telegramme nicht gesendet. Sie gehen nur mit der Option'), findsOneWidget);
    expect(
      find.textContaining('3 KNX-Secure-Telegramme nicht gesendet, weil der Server sie nicht entschlüsseln'),
      findsOneWidget,
    );
    expect(find.textContaining('Gruppenadressen:'), findsNothing, reason: 'older server without seq');

    await tester.pumpWidget(
      app(
        DataExportScreen(
          key: const ValueKey('raw'),
          client: _FakeClient(
            const {},
            mqtt: {'enabled': true, 'connected': true, 'rawOnly': true, 'raw': true, 'filter': '1/#,3/2/#', 'seq': 42},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nur Rohdaten · Gruppenadressen: 1/#,3/2/# · letzte Nr. (seq) 42'), findsOneWidget);
    expect(find.textContaining('knx_monitor/value/'), findsNothing, reason: 'keep last value is off');

    await tester.pumpWidget(
      app(
        DataExportScreen(
          key: const ValueKey('retain'),
          client: _FakeClient(
            const {},
            mqtt: {'enabled': true, 'connected': true, 'retainValues': true, 'valuesSent': 12, 'seq': 42},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Letzter Wert je Adresse unter knx_monitor/value/… mit retain, 12 Werte gesendet.'),
      findsOneWidget,
    );
  });

  testWidgets('InfluxDB: Hinweis, wenn das Token über http:// ginge; nicht bei https:// oder ohne Token', (
    tester,
  ) async {
    tall(tester);
    const hint = 'geht das Token unverschlüsselt';
    final client = _FakeClient(const {'influx': true, 'influxUrl': 'http://192.168.1.10:8086'});
    await tester.pumpWidget(app(DataExportScreen(client: client)));
    await tester.pumpAndSettle();
    expect(find.textContaining(hint), findsNothing, reason: 'kein Token');
    await tester.enterText(find.byType(TextField).at(4), 'tk');
    await tester.pump();
    expect(find.textContaining(hint), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'https://influx.example:8086');
    await tester.pump();
    expect(find.textContaining(hint), findsNothing, reason: 'https');

    // A token stored on the server counts as well.
    final stored = _FakeClient(const {'influx': true, 'influxUrl': 'HTTP://10.0.0.5:8086', 'hasInfluxToken': true});
    await tester.pumpWidget(app(DataExportScreen(key: UniqueKey(), client: stored)));
    await tester.pumpAndSettle();
    expect(find.textContaining(hint), findsOneWidget);
  });

  group('breites Fenster', () {
    const mqtt = {
      'enabled': true,
      'configurable': true,
      'source': 'app',
      'connected': true,
      'discovery': true,
      'seq': 1,
    };
    const settings = {'prometheus': true, 'influx': true, 'influxUrl': 'http://192.168.1.10:8086'};

    Future<void> pump(WidgetTester tester, Size size, {Map<String, Object?>? mqtt}) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(DataExportScreen(client: _FakeClient(settings, mqtt: mqtt))));
      await tester.pumpAndSettle();
    }

    double left(WidgetTester tester, String text) => tester.getTopLeft(find.text(text)).dx;
    double top(WidgetTester tester, String text) => tester.getTopLeft(find.text(text)).dy;

    testWidgets('1400 pt: drei Kartenspalten, jede beginnt oben', (tester) async {
      await pump(tester, const Size(1400, 900), mqtt: mqtt);
      expect(left(tester, 'Zähler und Werte'), lessThan(100));
      expect(left(tester, 'MQTT: jedes Telegramm (Vorschau)'), inInclusiveRange(400, 700));
      expect(left(tester, 'Grafana-Vorlage'), greaterThan(900));
      for (final head in ['MQTT: jedes Telegramm (Vorschau)', 'Grafana-Vorlage', 'Home Assistant']) {
        expect(top(tester, head), lessThan(450), reason: head);
      }
      expect(top(tester, 'Grafana-Vorlage'), top(tester, 'Zähler und Werte'));
      expect(top(tester, 'MQTT: jedes Telegramm (Vorschau)'), top(tester, 'Zähler und Werte'));
      // The fields keep their order: port, then InfluxDB, then the MQTT filter.
      expect(tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text, '9464');
      expect(tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text, 'http://192.168.1.10:8086');
      expect(tester.takeException(), isNull);
    });

    testWidgets('1000 pt: zwei Spalten, MQTT rechts oben, Grafana unter den Zählern', (tester) async {
      await pump(tester, const Size(1000, 3000), mqtt: mqtt);
      expect(left(tester, 'MQTT: jedes Telegramm (Vorschau)'), greaterThan(500));
      expect(top(tester, 'MQTT: jedes Telegramm (Vorschau)'), top(tester, 'Zähler und Werte'));
      expect(left(tester, 'Grafana-Vorlage'), lessThan(100));
      expect(top(tester, 'Grafana-Vorlage'), greaterThan(top(tester, 'Speichern')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ohne MQTT: Grafana füllt die rechte Spalte', (tester) async {
      await pump(tester, const Size(1400, 900));
      expect(left(tester, 'Grafana-Vorlage'), greaterThan(700));
      expect(top(tester, 'Grafana-Vorlage'), top(tester, 'Zähler und Werte'));
    });

    testWidgets('Telefon: eine Spalte in der gewohnten Reihenfolge', (tester) async {
      await pump(tester, const Size(375, 5000), mqtt: mqtt);
      final order = [
        'Zähler und Werte',
        'Speichern',
        'Grafana-Vorlage',
        'MQTT: jedes Telegramm (Vorschau)',
        'Home Assistant',
      ];
      for (final text in order) {
        expect(left(tester, text), lessThan(100), reason: text);
      }
      final tops = [for (final text in order) top(tester, text)];
      expect(tops, [...tops]..sort());
      expect(tester.takeException(), isNull);
    });
  });

  group('MQTT-Telegrammstrom in der App einstellen (#11)', () {
    const off = {'enabled': false, 'configurable': true, 'source': 'default', 'connected': true, 'discovery': true};

    testWidgets('Einschalten fragt nach, übernimmt Filter und Schalter, zurück zur Vorgabe', (tester) async {
      tall(tester);
      final client = _FakeClient(const {}, mqtt: off);
      await tester.pumpWidget(app(DataExportScreen(client: client)));
      await tester.pumpAndSettle();
      // Aus: kein Hinweis auf Add-on-Optionen mehr, sondern der Schalter.
      expect(find.textContaining('MQTT_TELEGRAMS=true'), findsNothing);
      expect(find.text('Nur diese Gruppenadressen'), findsNothing);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'MQTT übernehmen')).onPressed, isNull);

      await tester.tap(find.text('Jedes Telegramm an MQTT'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Jeder, der den Broker lesen kann'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(find.text('Nur diese Gruppenadressen'), findsNothing, reason: 'abgebrochen: bleibt aus');

      await tester.tap(find.text('Jedes Telegramm an MQTT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Einschalten'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '1/#,3/2/#,4/1/7'), ' 1/# ');
      await tester.tap(find.text('Letzten Wert je Adresse behalten'));
      await tester.pumpAndSettle();
      expect(find.text('Geändert, noch nicht übernommen.'), findsOneWidget);
      expect(client.mqttSaved, isEmpty);

      await tester.tap(find.text('MQTT übernehmen'));
      await tester.pumpAndSettle();
      expect(client.mqttSaved.single, {
        'enabled': true,
        'raw': false,
        'rawOnly': false,
        'retainValues': true,
        'repeats': false,
        'secure': false,
        'filter': '1/#',
      });
      expect(client.saved, isEmpty, reason: 'die übrigen Einstellungen der Seite gehen nicht mit');
      expect(find.textContaining('In der App eingestellt'), findsOneWidget);

      await tester.tap(find.text('Zurück zur Vorgabe'));
      await tester.pumpAndSettle();
      expect(client.mqttSaved.last, {'reset': true});
      expect(find.text('Zurück zur Vorgabe'), findsNothing);
    });

    testWidgets('KNX-Secure-Telegramme nur nach Rückfrage; „Nur Rohdaten“ erst mit Rohdaten', (tester) async {
      tall(tester);
      final client = _FakeClient(const {}, mqtt: {...off, 'enabled': true, 'seq': 3});
      await tester.pumpWidget(app(DataExportScreen(client: client)));
      await tester.pumpAndSettle();
      expect(find.text('Nur Rohdaten'), findsNothing);
      await tester.tap(find.text('Rohdaten mitsenden'));
      await tester.pumpAndSettle();
      expect(find.text('Nur Rohdaten'), findsOneWidget);

      await tester.tap(find.text('Auch KNX-Secure-Telegramme'));
      await tester.pumpAndSettle();
      expect(find.text('KNX-Secure-Telegramme im Klartext senden?'), findsOneWidget);
      await tester.tap(find.text('Einschalten'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MQTT übernehmen'));
      await tester.pumpAndSettle();
      expect(client.mqttSaved.single, containsPair('secure', true));
      expect(client.mqttSaved.single, containsPair('raw', true));
    });

    testWidgets('Secure schon in den Optionen an: Einschalten fragt eigens danach, Nein lässt sie draußen', (
      tester,
    ) async {
      tall(tester);
      final client = _FakeClient(const {}, mqtt: {...off, 'secure': true});
      await tester.pumpWidget(app(DataExportScreen(client: client)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jedes Telegramm an MQTT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Einschalten'));
      await tester.pumpAndSettle();
      expect(find.text('KNX-Secure-Telegramme im Klartext senden?'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MQTT übernehmen'));
      await tester.pumpAndSettle();
      expect(client.mqttSaved.single, allOf(containsPair('enabled', true), containsPair('secure', false)));
    });

    testWidgets('Telefon mit doppelter Schriftgröße: nichts läuft über', (tester) async {
      tester.view
        ..physicalSize = const Size(375, 5000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final mqtt = {...off, 'enabled': true, 'raw': true, 'source': 'app', 'seq': 1, 'filter': '1/#,3/2/#,4/1/7'};
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: DataExportScreen(client: _FakeClient(const {}, mqtt: mqtt)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Wiederholungen mitsenden'));
      // In cards the page is longer than the test window: let the scroll position settle.
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wiederholungen mitsenden'));
      await tester.pumpAndSettle();
      expect(find.text('Geändert, noch nicht übernommen.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('älterer Server: nur der Stand, keine Schalter', (tester) async {
      tall(tester);
      await tester.pumpWidget(app(DataExportScreen(client: _FakeClient(const {}, mqtt: const {'enabled': false}))));
      await tester.pumpAndSettle();
      expect(find.text('Jedes Telegramm an MQTT'), findsNothing);
      expect(find.textContaining('MQTT_TELEGRAMS=true'), findsOneWidget);
      expect(find.text('Home Assistant'), findsNothing);
    });

    testWidgets('pausiert über Home Assistant; Zeile zu Integration und MQTT-Gerät (#12)', (tester) async {
      tall(tester);
      for (final (extra, text) in [
        (const {'paused': true}, 'MQTT-Gerät „Busclear“ aktiv'),
        (const {'integration': true, 'discovery': false}, 'Busclear Integration eingerichtet'),
        (const {'discovery': false}, 'MQTT_DISCOVERY=false'),
        (const {'connected': false}, 'MQTT-Broker nicht verbunden.'),
      ]) {
        final mqtt = {...off, 'enabled': true, 'seq': 1, ...extra};
        await tester.pumpWidget(
          app(
            DataExportScreen(
              key: UniqueKey(),
              client: _FakeClient(const {}, mqtt: mqtt),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining(text), findsOneWidget, reason: '$extra');
        expect(
          find.textContaining('Pausiert über den Schalter'),
          extra['paused'] == true ? findsOneWidget : findsNothing,
        );
      }
    });
  });
}
