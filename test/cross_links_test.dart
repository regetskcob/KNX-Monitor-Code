import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/theme/tokens.dart';
import 'package:knx_monitor/ui/details_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Querwege aus den Details: Absender → Geräteblatt, Adresse → Karte.
void main() {
  final t = Telegram(
    time: DateTime(2026, 10, 20, 20),
    source: 0x1132, // 1.1.50
    destination: 0x1000, // 2/0/0
    type: TelegramType.write,
    data: Uint8List.fromList([0x0C, 0x24]),
    isSmall: false,
  );

  Future<void> pump(WidgetTester tester, {ValueChanged<int>? device, ValueChanged<int>? map}) async {
    SharedPreferences.setMockInitialValues({});
    CatalogStore.instance.catalog = GroupCatalog.empty;
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TelegramDetails(telegram: t, tunnel: null, history: [t], onOpenDevice: device, onOpenMap: map),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Absender öffnet das Geräteblatt, Kartenknopf die Karte', (tester) async {
    int? device;
    int? map;
    await pump(tester, device: (a) => device = a, map: (a) => map = a);

    // Der Absender in „Telegramm“ ist der antippbare Wert (mit Pfeil).
    await tester.tap(find.descendant(of: find.byType(InkWell), matching: find.text('1.1.50')).last);
    expect(device, 0x1132);

    await tester.tap(find.byTooltip(s.commonMore));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.mapTitle));
    expect(map, 0x1000);
  });

  testWidgets('Ohne Querwege kein Kartenknopf und kein Filter', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip(s.commonMore));
    await tester.pumpAndSettle();
    expect(find.text(s.mapTitle), findsNothing);
    expect(find.text(s.detailsFilter), findsNothing);
  });

  // Detailspalte am iPad: alle Aktionen auf einer Zeile, Kommentieren dann nur
  // als Zeichen. Mit den echten Schriften, die Testschrift ist viel breiter.
  setUpAll(() async {
    const fonts = {
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
  });
  for (final width in [Widths.inspector, 600.0]) {
    testWidgets('Aktionen bei Breite $width auf einer Zeile', (tester) async {
      SharedPreferences.setMockInitialValues({});
      CatalogStore.instance.catalog = GroupCatalog.empty;
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tunnel = DemoTunnel();
      addTearDown(tunnel.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: TelegramDetails(telegram: t, tunnel: tunnel, history: [t], onFilter: (_) {}, onOpenMap: (_) {}),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final actions = [find.text(s.detailsComment), find.text(s.detailsRemember), find.text(s.detailsFilter)];
      final tops = {for (final f in actions) tester.getCenter(f.first).dy.round()};
      expect(tops, hasLength(1), reason: 'Aktionen brechen um');
    });
  }

  testWidgets('Offenes Blatt übernimmt neue Telegramme der Adresse (auch selbst geschriebene)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    CatalogStore.instance.catalog = GroupCatalog.empty;
    final log = TelegramLog()..add(t);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDetailsSheet(context, t, tunnel: null, history: [t], log: log),
            child: const Text('öffnen'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('öffnen'));
    await tester.pumpAndSettle();
    final written = Telegram(
      time: t.time.add(const Duration(seconds: 5)),
      source: 0x11FF,
      destination: t.destination,
      type: TelegramType.write,
      data: Uint8List.fromList([0x0C, 0x30]),
      isSmall: false,
      outgoing: true,
    );
    // Fremde Adresse: kein Neuaufbau nötig, aber auch kein Fehler.
    log.add(
      Telegram(
        time: t.time,
        source: 0x1132,
        destination: 0x1001,
        type: TelegramType.write,
        data: Uint8List.fromList([1]),
        isSmall: true,
      ),
    );
    log.add(written);
    await tester.pump();
    final details = tester.widget<TelegramDetails>(find.byType(TelegramDetails));
    expect(details.telegram, same(written));
    expect(details.history, hasLength(2));
  });
}
