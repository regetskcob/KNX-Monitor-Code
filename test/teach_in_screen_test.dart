import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/teach_in_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tunnel, dessen Telegramme der Test selbst einspeist.
class _FakeTunnel extends KnxTunnel {
  _FakeTunnel() : super('test');

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

void main() {
  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('knx_teach_screen');
    AppStorage.instance = IoStorage(dir);
    await CatalogStore.instance.reload();
  });

  tearDown(() async => dir.delete(recursive: true));

  Future<_FakeTunnel> open(WidgetTester tester, {Duration warmUp = Duration.zero}) async {
    final tunnel = _FakeTunnel();
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
}
