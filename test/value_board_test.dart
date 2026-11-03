import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/pinned_sections.dart';
import 'package:knx_monitor/ui/object_board.dart';
import 'package:knx_monitor/ui/value_board.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Spalten der Übersicht je Breite', () {
    expect(columnsFor(350, phone: true), 1);
    // Karten bleiben mindestens 240 pt breit.
    expect(columnsFor(794, phone: false), 3); // iPad 11″ hoch
    expect(columnsFor(1154, phone: false), 4); // iPad 11″ quer
    expect(columnsFor(714, phone: false), 2); // quer mit Detailspalte
    expect(columnsFor(1326, phone: false), 5); // iPad 13″ quer: höchstens 5
  });

  test('Spalten der Objekte je Breite', () {
    expect(objectColumnsFor(350, phone: true), 1);
    expect(objectColumnsFor(794, phone: false), 3); // iPad 11″ hoch
    expect(objectColumnsFor(1154, phone: false), 4); // iPad 11″ quer
    expect(objectColumnsFor(600, phone: false), 2);
  });

  Telegram t(String ga) => Telegram(
    time: DateTime(2026),
    source: 0x1101,
    destination: parseGroup(ga)!,
    type: TelegramType.write,
    data: Uint8List.fromList([1]),
    isSmall: false,
  );

  Widget board(List<Telegram> items) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: ValueBoard(items: items, counts: const {}, history: const {}, onTap: (_) {}, onLongPress: (_) {}),
    ),
  );

  testWidgets('während der Bedienung springt nichts, in Ruhe wird einsortiert', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(board([t('1/1/5')]));
    final gesture = await tester.startGesture(const Offset(600, 450));
    // Neue Adressen davor (1/1/1) und neue Hauptgruppe davor (0/0/1).
    await tester.pumpWidget(board([t('0/0/1'), t('1/1/1'), t('1/1/5')]));
    Offset at(String ga) => tester.getTopLeft(find.text(ga));
    // Lesereihenfolge: kleine Sektionen können nebeneinander stehen.
    bool before(String a, String b) => at(a).dy < at(b).dy || (at(a).dy == at(b).dy && at(a).dx < at(b).dx);
    expect(at('1/1/5').dx, lessThan(at('1/1/1').dx)); // hinten angehängt
    expect(before('1/1/5', '0/0/1'), isTrue); // neue Sektion dahinter

    await gesture.up();
    await tester.pump(const Duration(seconds: 2)); // Ruhezeit vorbei
    expect(at('1/1/1').dx, lessThan(at('1/1/5').dx));
    expect(before('0/0/1', '1/1/5'), isTrue);
  });

  test('Angeheftete Sektionen zuerst, in Anheft-Reihenfolge', () async {
    SharedPreferences.setMockInitialValues({});
    final pins = PinnedSections.instance;
    for (final id in [...pins.ids]) {
      await pins.toggle(id);
    }
    await pins.toggle('type:datetime');
    await pins.toggle('main:1');
    expect(pins.order(['main:0', 'main:1', 'main:2', 'type:datetime']), [
      'type:datetime',
      'main:1',
      'main:0',
      'main:2',
    ]);
    // Nicht vorhandene angeheftete Sektionen tauchen nicht auf.
    expect(pins.order(['main:2']), ['main:2']);
    await pins.toggle('type:datetime');
    expect(pins.ids, ['main:1']);
    await pins.toggle('main:1');
  });

  testWidgets('angeheftete Hauptgruppe steht oben', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(board([t('0/0/1'), t('1/1/1')]));
    Offset at(String ga) => tester.getTopLeft(find.text(ga));
    bool before(String a, String b) => at(a).dy < at(b).dy || (at(a).dy == at(b).dy && at(a).dx < at(b).dx);
    expect(before('0/0/1', '1/1/1'), isTrue);

    await PinnedSections.instance.toggle('main:1');
    await tester.pump();
    expect(at('1/1/1').dy, lessThan(at('0/0/1').dy)); // angeheftet: eigenes Band oben
    await PinnedSections.instance.toggle('main:1');
  });

  testWidgets('Pin-Knopf im Sektionskopf heftet an und legt die Sektion aufs Band', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(board([t('0/0/1'), t('1/1/1')]));
    expect(find.byType(PinnedBand), findsNothing);
    expect(find.byTooltip('Oben anheften'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Oben anheften').last);
    await tester.pump();
    expect(PinnedSections.instance.contains('main:1'), isTrue);
    expect(find.byType(PinnedBand), findsOneWidget);
    expect(find.byTooltip('Nicht mehr anheften'), findsOneWidget);
    expect(tester.getTopLeft(find.text('1/1/1')).dy, lessThan(tester.getTopLeft(find.text('0/0/1')).dy));

    await tester.tap(find.byTooltip('Nicht mehr anheften'));
    await tester.pump();
    expect(PinnedSections.instance.contains('main:1'), isFalse);
    expect(find.byType(PinnedBand), findsNothing);
  });

  testWidgets('Favorit steht in eigener Sektion ganz oben', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fav = parseGroup('5/0/1')!;
    await PinnedSections.instance.toggleFavorite(fav);
    await tester.pumpWidget(board([t('0/0/1'), t('5/0/1')]));
    await tester.pump();
    expect(find.text('Favoriten'), findsOneWidget);
    expect(tester.getTopLeft(find.text('5/0/1')).dy, lessThan(tester.getTopLeft(find.text('0/0/1')).dy));
    expect(find.text('5/0/1'), findsOneWidget); // nicht doppelt
    await PinnedSections.instance.toggleFavorite(fav);
  });

  testWidgets('Karte mit langem Titel und langem Gerätenamen läuft nicht über', (tester) async {
    CatalogStore.instance.catalog = GroupCatalog(
      {
        parseGroup('8/4/11')!: GroupInfo(
          address: parseGroup('8/4/11')!,
          name: 'Leistung Wohnzimmer Steckdosen Fensterseite links',
          path: 'Sonstiges › Verbrauch',
          dpt: const Dpt(14, 56),
        ),
      },
      devices: {
        0x1101: const DeviceInfo(address: 0x1101, name: 'AMI-0816.02 Schaltaktor mit Strommessung 8-fach, 8TE, 16/20A'),
      },
    );
    addTearDown(() => CatalogStore.instance.catalog = GroupCatalog.empty);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 230,
              height: 160,
              child: ValueCard(
                telegram: t('8/4/11'),
                count: 12345,
                history: const [10, 20, 15],
                average: 15,
                onTap: () {},
                onLongPress: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('eingeklappter Kopf mit kurzem Wert reicht bis an den rechten Rand', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SectionHeader(
            title: 'Helligkeit',
            icon: null,
            count: 2,
            activity: 0,
            latest: t('1/1/1'),
            collapsed: true,
            onToggle: () {},
            onPin: () {},
          ),
        ),
      ),
    );
    final header = tester.getRect(find.byType(SectionHeader));
    final chevron = tester.getRect(find.byType(AnimatedRotation));
    expect(header.right - chevron.right, lessThan(16));
  });
}
