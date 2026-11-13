import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/teach_in_screen.dart';
import 'package:knx_monitor/ui/figure_box.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'window.dart';

/// Tunnel, dessen Telegramme der Test selbst einspeist.
class _FakeTunnel extends KnxTunnel {
  _FakeTunnel() : super('test');

  // Not closed on purpose: lives as long as the fake.
  // ignore: close_sinks
  final controller = StreamController<Telegram>.broadcast();

  @override
  Stream<Telegram> get telegrams => controller.stream;
}

final _t0 = DateTime(2020);

Telegram _press(int ms, String dest, {String source = '1.1.30'}) => Telegram(
  time: _t0.add(Duration(milliseconds: ms)),
  source: parseIndividual(source)!,
  destination: parseGroup(dest)!,
  type: TelegramType.write,
  data: Uint8List.fromList([1]),
  isSmall: true,
);

/// Messwert (2 Byte), wie ihn ein Temperaturfühler von selbst sendet.
Telegram _value(int ms, String dest, {String source = '1.1.50'}) => Telegram(
  time: _t0.add(Duration(milliseconds: ms)),
  source: parseIndividual(source)!,
  destination: parseGroup(dest)!,
  type: TelegramType.write,
  data: Uint8List.fromList([0x0C, 0x33]),
  isSmall: false,
);

void main() {
  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('knx_teach_screen');
    AppStorage.instance = IoStorage(dir);
    await CatalogStore.instance.reload();
  });

  tearDown(() async => dir.delete(recursive: true));

  /// [tall]: hohes Fenster, damit Karte und Listen zugleich aufgebaut sind.
  Future<_FakeTunnel> open(WidgetTester tester, {Duration warmUp = Duration.zero, bool tall = false}) async {
    final tunnel = _FakeTunnel();
    if (tall) {
      tester.view
        ..physicalSize = const Size(800, 3000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: TeachInScreen(tunnel: tunnel, warmUp: warmUp),
      ),
    );
    return tunnel;
  }

  /// Zeile der Liste „Offen“ (Adresse und Wert in einem Text).
  Finder openRow(String address) => find.textContaining('$address ', findRichText: true);

  /// „Anlernen“ antippen und das Speichern (echte Dateien) abwarten.
  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Anlernen'));
    // Mehrere Schreibvorgänge nacheinander (Angelerntes, Typ, Namen): jeder Schritt braucht echte Zeit.
    for (var i = 0; i < 100 && find.textContaining('Angelernt: ').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('Angelernt: '), findsOneWidget);
  }

  Future<void> close(WidgetTester tester, _FakeTunnel tunnel) async {
    await tester.pumpWidget(const SizedBox());
    await tunnel.controller.close();
  }

  testWidgets('Ereignis bleibt 10 s stehen; benannt ersetzt es kein neues mehr', (tester) async {
    final tunnel = await open(tester);
    // Ein Ereignis schließt, sobald das nächste Telegramm nach dem Fenster kommt.
    tunnel.controller
      ..add(_press(0, '1/0/0'))
      ..add(_press(5000, '2/2/7', source: '1.1.13'))
      ..add(_press(9000, '1/0/1', source: '1.1.31'));
    await tester.pump();
    expect(find.text('1/0/0'), findsOneWidget, reason: 'nach 5 s noch nicht ersetzt');
    expect(find.textContaining('1/0/0 nicht mehr fangen'), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse, reason: 'kein Autofokus, keine Tastatur');

    // Unberührt und älter als 10 s: das neuere ersetzt es.
    tunnel.controller
      ..add(_press(12000, '1/0/2', source: '1.1.32'))
      ..add(_press(14000, '1/0/3', source: '1.1.33'));
    await tester.pump();
    expect(find.text('1/0/2'), findsOneWidget);
    expect(find.text('1/0/0'), findsNothing);

    // Raum eintippen zählt als Benennen: das gefangene bleibt stehen.
    await tester.enterText(find.widgetWithText(TextField, 'Raum'), 'Wohnzimmer');
    await tester.pump();
    tunnel.controller
      ..add(_press(40000, '1/0/5', source: '1.1.34'))
      ..add(_press(60000, '1/0/6', source: '1.1.35'));
    await tester.pump();
    expect(find.text('1/0/2'), findsOneWidget);
    expect(find.text('1/0/5'), findsNothing);
    await close(tester, tunnel);
  });

  testWidgets('Gleichzeitiger fremder Verkehr: „Auch gesehen“, nicht angehakt', (tester) async {
    final tunnel = await open(tester);
    tunnel.controller
      ..add(_press(0, '1/0/4'))
      ..add(_press(150, '1/1/4', source: '1.1.10'))
      ..add(_press(200, '2/3/7', source: '1.1.13'))
      ..add(_press(5000, '1/0/9', source: '1.1.31'));
    await tester.pump();
    expect(find.text('Rückmeldung'), findsOneWidget);
    expect(find.text('Auch gesehen'), findsOneWidget);
    final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).map((c) => c.value).toList();
    expect(boxes, [true, true, false], reason: 'Befehl, Rückmeldung 1/1/4, 2/3/7 unangehakt');
    await close(tester, tunnel);
  });

  testWidgets('Zu Beginn: ruhig mithören mit Fortschritt, dann „Drück jetzt“', (tester) async {
    var now = DateTime(2026, 10, 29, 18);
    TeachInScreen.clock = () => now;
    addTearDown(() => TeachInScreen.clock = DateTime.now);
    final tunnel = await open(tester, warmUp: const Duration(seconds: 15));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Höre kurz mit'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    now = now.add(const Duration(seconds: 16));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Höre kurz mit'), findsNothing);
    await close(tester, tunnel);
  });

  testWidgets('breites Fenster: Mithören links, „Benannt“ rechts daneben; schmal untereinander', (tester) async {
    final tunnel = _FakeTunnel();
    final screen = TeachInScreen(tunnel: tunnel, warmUp: Duration.zero);
    final card = find.byType(SwitchRow);
    final named = find.widgetWithText(SectionHead, 'Benannt');

    await pumpWindow(tester, screen, wideWindow);
    expect(tester.getTopLeft(card).dx, lessThan(wideWindow.width / 2));
    expect(tester.getTopLeft(named).dx, greaterThan(wideWindow.width / 2));
    expect(tester.getTopLeft(named).dy, lessThan(tester.getBottomLeft(card).dy));

    // Das gefangene Ereignis steht an derselben Stelle.
    tunnel.controller
      ..add(_press(0, '1/0/4'))
      ..add(_press(5000, '1/0/9', source: '1.1.31'));
    await tester.pump();
    expect(tester.getTopLeft(find.text('1/0/4')).dx, lessThan(wideWindow.width / 2));
    expect(tester.getTopLeft(named).dx, greaterThan(wideWindow.width / 2));

    for (final (size, scale) in [(phoneWindow, 1.0), (phoneWindow, 2.0), (const Size(800, 1000), 1.0)]) {
      await pumpWindow(tester, screen, size, textScale: scale);
      await tester.dragUntilVisible(named, find.byType(ListView), const Offset(0, -200));
      expect(tester.getTopLeft(named).dx, lessThan(size.width / 2), reason: '$size, Schrift $scale');
    }
    await pumpWindow(tester, screen, wideWindow, textScale: 2);
    await close(tester, tunnel);
  });

  testWidgets('Offen: gehörte Adresse antippen und ohne Tastendruck benennen', (tester) async {
    final tunnel = await open(tester, tall: true);
    final store = CatalogStore.instance;
    tunnel.controller
      ..add(_value(0, '3/1/1'))
      ..add(_value(1000, '3/1/2'));
    await tester.pump();
    expect(find.textContaining('0 von 2 gehörten Adressen'), findsOneWidget);
    expect(find.text('Drück einen Taster'), findsOneWidget, reason: 'Messwerte fangen nichts');

    await tester.tap(openRow('3/1/1'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Gehört: 3/1/1'), findsOneWidget);
    expect(find.text('Gerät (Absender)'), findsNothing, reason: 'kein Taster, der benannt wird');
    expect(find.textContaining('nicht mehr fangen'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Raum'), 'Wohnzimmer');
    await tester.enterText(find.widgetWithText(TextField, 'Was ist es?'), 'Temperatur');
    await tester.pump();
    await save(tester);

    final g = store.learned[parseGroup('3/1/1')!]!;
    expect((g.name, g.path, g.dpt?.main), ('Temperatur', 'Wohnzimmer', 9));
    expect(store.learned.devices, isEmpty);
    expect(find.textContaining('1 von 2 gehörten Adressen'), findsOneWidget);
    expect(openRow('3/1/2'), findsOneWidget, reason: 'bleibt offen');
    await close(tester, tunnel);
  });

  testWidgets('Offen: Nachbar einer benannten Adresse schlägt „… Status“ und den Raum vor', (tester) async {
    await tester.runAsync(
      () => CatalogStore.instance.learn([GroupInfo(address: parseGroup('1/0/4')!, name: 'Deckenlicht', path: 'Küche')]),
    );
    final tunnel = await open(tester, tall: true);
    tunnel.controller.add(_press(0, '1/1/4', source: '1.1.10'));
    // Kein Ereignis: Status von einem Aktor, der schon in der Aufzeichnung sendete, fängt nichts.
    await tester.pump();
    await tester.tap(openRow('1/1/4'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.widgetWithText(ChoiceChip, 'Deckenlicht Status'), findsOneWidget);
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Raum')).controller!.text, 'Küche');
    await close(tester, tunnel);
  });

  testWidgets('Altes Projekt: anderer Name wird Korrektur, fehlende Adresse steht unter Offen', (tester) async {
    final store = CatalogStore.instance;
    final a = parseGroup('1/0/0')!;
    await tester.runAsync(
      () => store.adopt(
        GroupCatalog({a: GroupInfo(address: a, name: 'Flur Licht', path: 'Beleuchtung', dpt: const Dpt(1, 1))}),
        name: 'alt.knxproj',
      ),
    );
    final tunnel = await open(tester, tall: true);
    tunnel.controller
      ..add(_press(0, '1/0/0'))
      ..add(_value(100, '3/1/7'))
      ..add(_press(5000, '2/2/7', source: '1.1.13'));
    await tester.pump();
    final name = find.widgetWithText(TextField, 'Was ist es?');
    expect(tester.widget<TextField>(name).controller!.text, 'Flur Licht', reason: 'Name aus dem Projekt vorbelegt');
    expect(find.textContaining('älter als die Anlage'), findsOneWidget);
    expect(openRow('3/1/7'), findsOneWidget);

    await tester.enterText(name, 'Garderobe Licht');
    await tester.pump();
    await save(tester);
    expect(store.names[a], 'Garderobe Licht');
    expect(store.info(a)!.name, 'Garderobe Licht', reason: 'gilt trotz Vorrang des Projekts');
    await close(tester, tunnel);
  });

  testWidgets('Altes Projekt: Länge passt nicht zum Typ – offen, Benennen setzt den Typ', (tester) async {
    final store = CatalogStore.instance;
    final a = parseGroup('3/1/1')!;
    await tester.runAsync(
      () => store.adopt(
        GroupCatalog({a: GroupInfo(address: a, name: 'Alt Schalten', dpt: const Dpt(1, 1))}),
        name: 'alt.knxproj',
      ),
    );
    final tunnel = await open(tester, tall: true);
    tunnel.controller.add(_value(0, '3/1/1'));
    await tester.pump();
    expect(find.textContaining('passt nicht zu „Alt Schalten“'), findsOneWidget);
    await tester.tap(openRow('3/1/1'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.widgetWithText(TextField, 'Was ist es?'), 'Temperatur');
    await tester.pump();
    await save(tester);
    expect(store.dptOf(a)?.main, 9);
    expect(store.info(a)!.name, 'Temperatur');
    expect(find.textContaining('passt nicht zu'), findsNothing);
    await close(tester, tunnel);
  });

  testWidgets('Zweite Wippe desselben Tasters: Raum und Gerät stehen schon da', (tester) async {
    final store = CatalogStore.instance;
    await tester.runAsync(
      () => store.learn(
        [GroupInfo(address: parseGroup('1/0/0')!, name: 'Deckenlicht', path: 'Küche')],
        devices: [DeviceInfo(address: parseIndividual('1.1.30')!, name: 'Glastaster Tür', location: 'Küche')],
      ),
    );
    final tunnel = await open(tester, tall: true);
    tunnel.controller
      ..add(_press(0, '1/0/1'))
      ..add(_press(5000, '2/2/7', source: '1.1.13'));
    await tester.pump();
    String text(String label) => tester.widget<TextField>(find.widgetWithText(TextField, label)).controller!.text;
    expect(text('Raum'), 'Küche');
    expect(text('Gerät (Absender)'), 'Glastaster Tür');
    expect(text('Was ist es?'), isEmpty);
    await close(tester, tunnel);
  });
}
