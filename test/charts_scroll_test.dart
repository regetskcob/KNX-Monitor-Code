import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/charts_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vollbild-Diagramm mit langer Reihe: breiter als das Fenster, öffnet am
// neuesten Ende, Zeilennamen bleiben beim Scrollen stehen, und das
// Fadenkreuz trifft nach dem Scrollen die Zeit unter dem Finger.
void main() {
  final start = DateTime(2026, 10, 24, 8);
  const count = 300;
  // 300 Schaltwechsel im Abstand von 10 s – rund 4200 px bei 14 px je Wert.
  final log = TelegramLog()
    ..addAll([
      for (var i = 0; i < count; i++)
        Telegram(
          time: start.add(Duration(seconds: 10 * i)),
          source: 0x1110,
          destination: parseGroup('1/1/1')!,
          type: TelegramType.write,
          data: Uint8List.fromList([i.isEven ? 1 : 0]),
          isSmall: true,
        ),
    ]);
  const span = 10 * (count - 1);

  Future<void> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    CatalogStore.instance.catalog = demoCatalog();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ChartsScreen(log: log, initial: [parseGroup('1/1/1')!]),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder plots() => find.byWidgetPredicate((w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal);

  ScrollPosition position(WidgetTester tester) =>
      tester.state<ScrollableState>(find.descendant(of: plots(), matching: find.byType(Scrollable))).position;

  /// Sekunden seit Beginn am Fadenkreuz, aus dem Kommentar-Knopf
  /// („Kommentar bei 08:41:20 …“).
  int? cursor(WidgetTester tester) {
    for (final tip in tester.widgetList<Tooltip>(find.byType(Tooltip))) {
      final m = RegExp(r'Kommentar bei (\d\d):(\d\d):(\d\d)').firstMatch(tip.message ?? '');
      if (m != null) {
        final t = DateTime(start.year, start.month, start.day, int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
        return t.difference(start).inSeconds;
      }
    }
    return null;
  }

  testWidgets('Lange Reihe scrollt und öffnet am neuesten Ende', (tester) async {
    await pump(tester);
    expect(plots(), findsOneWidget);
    expect(position(tester).maxScrollExtent, greaterThan(1000));
    // reverse: 0 heißt, das rechte (neueste) Ende ist zu sehen.
    expect(position(tester).pixels, 0);
  });

  testWidgets('Zeilenname bleibt beim Scrollen stehen', (tester) async {
    await pump(tester);
    final name = find.text(CatalogStore.instance.info(parseGroup('1/1/1')!)!.name).first;
    final before = tester.getTopLeft(name);
    await tester.drag(plots(), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(position(tester).pixels, greaterThan(0));
    expect(tester.getTopLeft(name), before);
  });

  testWidgets('Tippen nach dem Scrollen trifft die Zeit unter dem Finger', (tester) async {
    await pump(tester);
    final box = tester.getRect(plots());
    final spot = Offset(box.left + 20, box.top + 40);
    // Am neuesten Ende: links im Fenster liegt schon die zweite Hälfte.
    await tester.tapAt(spot);
    await tester.pump();
    expect(cursor(tester), greaterThan(span * 0.5));

    // Ganz zurück zum Anfang: dieselbe Stelle zeigt jetzt den Beginn.
    position(tester).jumpTo(position(tester).maxScrollExtent);
    await tester.pump();
    await tester.tapAt(spot);
    await tester.pump();
    expect(cursor(tester), lessThan(span * 0.05));
  });
}
