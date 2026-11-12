import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/floor_view.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/common.dart' show BarTitle;
import 'package:knx_monitor/ui/floor_view_screen.dart';
import 'package:knx_monitor/ui/group_address_picker.dart';

import 'memory_storage.dart';

Telegram _t(int ga, DateTime time, {TelegramType type = TelegramType.write}) =>
    Telegram(time: time, source: 0x110A, destination: ga, type: type, data: Uint8List.fromList([1]), isSmall: true);

Widget _app(Widget home) => MaterialApp(
  theme: AppTheme.light(),
  locale: const Locale('de'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

void main() {
  final t0 = DateTime(2026, 11, 10, 9);

  group('Format', () {
    test('round trip', () {
      final view = demoFloorView(german: true);
      final back = FloorView.fromJson(jsonDecode(jsonEncode(view.toJson())));
      expect(jsonEncode(back.toJson()), jsonEncode(view.toJson()));
      expect(back.source, FloorView.sourceOwn);
    });

    test('foreign, damaged and newer files', () {
      expect(() => FloorView.fromJson('text'), throwsFormatException);
      expect(() => FloorView.fromJson({'format': 'something else', 'version': 1}), throwsFormatException);
      expect(() => FloorView.fromJson({'format': floorViewFormat}), throwsFormatException);
      expect(
        () => FloorView.fromJson({'format': floorViewFormat, 'version': floorViewFormatVersion + 1}),
        throwsA(isA<FloorViewTooNew>()),
      );
    });

    test('wrong types become defaults, lists and texts are cut, image paths are confined', () {
      final view = FloorView.fromJson({
        'format': floorViewFormat,
        'version': 1,
        'source': 'whatever',
        'floors': [
          'not a floor',
          {
            'id': 'f1',
            'name': '<img src=x onerror=alert(1)>\u0000${'n' * 300}',
            'aspect': 'wide',
            'image': '../../secure_keys.json',
            'rooms': 'none',
            'points': [
              {
                'id': 'p1',
                'name': 7,
                'x': 9,
                'y': double.nan,
                'kind': 'laser',
                'addresses': ['x', -1, 70000, 2305, null],
              },
              for (var i = 0; i < floorViewMaxPoints + 50; i++) {'id': 'q$i', 'addresses': List.filled(40, 1)},
            ],
          },
          {'id': 'f2', 'image': 'home_plan_images/f2.jpg.b64', 'aspect': 1e9},
        ],
      });
      expect(view.source, FloorView.sourceOwn);
      expect(view.floors, hasLength(2));
      final floor = view.floors.first;
      expect(floor.name.length, floorViewMaxText);
      expect(floor.name, startsWith('<img'), reason: 'stays plain text');
      expect(floor.aspect, 1.5);
      expect(floor.image, isNull, reason: 'a path outside the image folders is dropped');
      expect(floor.rooms, isEmpty);
      expect(floor.points, hasLength(floorViewMaxPoints));
      final p = floor.points.first;
      expect((p.name, p.x, p.y, p.kind), ('', 1.0, 0.5, FloorPointKind.other));
      expect(p.addresses, [2305]);
      expect(floor.points[1].addresses, hasLength(floorViewMaxAddresses));
      expect(view.floors.last.image, 'home_plan_images/f2.jpg.b64');
      expect(view.floors.last.aspect, 5.0);
    });

    test('image paths: only generated names in the two image folders', () {
      expect(isFloorImagePath('floor_view_images/f1.jpg.b64'), isTrue);
      expect(isFloorImagePath('home_plan_images/f12.jpg.b64'), isTrue);
      for (final bad in [
        'floor_view_images/../secure_keys.json',
        '/etc/passwd',
        'floor_view_images/F1.jpg.b64',
        'floor_view_images/f1.png',
        'site_photos/f1.jpg.b64',
        'floor_view_images/a/b.jpg.b64',
        7,
        null,
      ]) {
        expect(isFloorImagePath(bad), isFalse, reason: '$bad');
      }
    });
  });

  group('Activity', () {
    test('active, heard, not heard yet, unlinked; reads are no sign of life', () {
      final activity = FloorActivity()..since = t0;
      final linked = FloorPoint(id: 'a', name: 'Light', x: 0, y: 0, addresses: [2305, 2306]);
      final lonely = FloorPoint(id: 'b', name: 'Socket', x: 0, y: 0, addresses: [9]);
      final unlinked = FloorPoint(id: 'c', name: 'New', x: 0, y: 0);
      expect(activity.stateOf(linked, t0), PointState.unheard);
      expect(activity.stateOf(unlinked, t0), PointState.unlinked);

      activity.observe(_t(2306, t0, type: TelegramType.read));
      expect(activity.stateOf(linked, t0), PointState.unheard);

      activity.takeLatest({2306: _t(2306, t0)});
      expect(activity.stateOf(linked, t0.add(const Duration(seconds: 2))), PointState.active);
      expect(activity.stateOf(linked, t0.add(const Duration(seconds: 30))), PointState.heard);
      expect(activity.lastOf(linked), t0);
      expect(activity.stateOf(lonely, t0), PointState.unheard);

      // An older time from the server's history never replaces a newer one.
      activity.note(2305, t0.subtract(const Duration(days: 2)));
      expect(activity.lastOf(linked), t0);
    });

    test('silence only stands out after twelve hours of watched time', () {
      final activity = FloorActivity()..since = t0;
      final lonely = FloorPoint(id: 'b', name: 'Socket', x: 0, y: 0, addresses: [9]);
      // Five minutes after opening, a quiet house is no warning.
      expect(activity.stateOf(lonely, t0.add(const Duration(minutes: 5))), PointState.unheard);
      expect(activity.stateOf(lonely, t0.add(const Duration(hours: 11, minutes: 59))), PointState.unheard);
      expect(activity.stateOf(lonely, t0.add(const Duration(hours: 12))), PointState.silent);
      // The server's history reaches back: then the statement holds at once.
      activity.since = t0.subtract(const Duration(days: 3));
      expect(activity.stateOf(lonely, t0), PointState.silent);
      // Without knowing since when, nothing is claimed.
      activity.since = null;
      expect(activity.stateOf(lonely, t0), PointState.unheard);
      // Heard once in the watched time is never "silent".
      activity
        ..since = t0.subtract(const Duration(days: 3))
        ..note(9, t0.subtract(const Duration(days: 2)));
      expect(activity.stateOf(lonely, t0), PointState.heard);
    });
  });

  group('Store', () {
    final store = FloorViewStore.instance;
    late MemoryStorage storage;
    setUp(() {
      storage = MemoryStorage();
      store
        ..debugReset()
        ..storageOverride = storage;
    });

    test('saves, reloads and keeps a newer or damaged file untouched', () async {
      await store.load();
      expect(store.view.isEmpty, isTrue);
      final floor = FloorLevel(id: store.view.newId('f'), name: 'EG');
      store.view.floors.add(floor);
      floor.points.add(FloorPoint(id: store.view.newId('p'), name: 'Licht', x: .3, y: .4, addresses: [2305]));
      await store.save();
      await store.load();
      expect(store.view.floors.single.points.single.addresses, [2305]);

      const newer = '{"format":"busclear-floor-view","version":99,"floors":[]}';
      storage.files[FloorViewStore.path] = newer;
      await store.load();
      expect(store.tooNew, isTrue);
      store.changed();
      await store.save();
      await store.replace(demoFloorView(german: true));
      expect(storage.files[FloorViewStore.path], newer);

      storage.files[FloorViewStore.path] = '{broken';
      await store.load();
      expect(store.tooNew, isFalse);
      expect(store.view.isEmpty, isTrue);
      expect(storage.files.keys.where((k) => k.contains('.corrupt-')), hasLength(1));
    });

    test('replacing the view removes images it no longer uses', () async {
      await store.load();
      final floor = FloorLevel(id: 'f1', name: 'EG');
      store.view.floors.add(floor);
      await store.setImage(floor, Uint8List.fromList([0xFF, 0xD8, 0xFF, 1]), 1.2);
      expect(storage.files.containsKey('floor_view_images/f1.jpg.b64'), isTrue);
      expect(await store.image(floor), [0xFF, 0xD8, 0xFF, 1]);
      await store.replace(demoFloorView(german: false));
      expect(storage.files.keys.where((k) => k.startsWith('floor_view_images/')), isEmpty);
      expect(store.view.floors.single.points, isNotEmpty);
    });
  });

  test('demo floor: linked addresses exist in the demo project, one point stays silent', () {
    final catalog = demoCatalog();
    final view = demoFloorView(german: true);
    final unknown = [
      for (final p in view.points)
        if (p.addresses.any((a) => catalog[a] == null)) p,
    ];
    expect(unknown, hasLength(1), reason: 'exactly the point that shows "silent"');
    expect(view.points.length, greaterThan(10));
  });

  group('Screen', () {
    setUp(() {
      CatalogStore.instance.beginDemo(demoCatalog());
      final store = FloorViewStore.instance
        ..debugReset()
        ..storageOverride = MemoryStorage();
      store.storageOverride!.write(FloorViewStore.path, jsonEncode(demoFloorView(german: true).toJson()));
    });
    tearDown(() => CatalogStore.instance.endDemo());

    for (final size in const [Size(375, 800), Size(1200, 800)]) {
      testWidgets('points light up, silent ones are listed, ${size.width}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final log = TelegramLog();
        await tester.pumpWidget(_app(FloorViewScreen(log: log, clock: tester.binding.clock.now)));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
        // Nothing heard yet: neutral, by label and not only by colour; no warning minutes after opening.
        expect(find.text('Lange still'), findsNothing);
        expect(find.text('Noch nichts gehört'), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('Wohnen Licht, Wohnen, noch nichts gehört')), findsOneWidget);

        log.add(_t(2049, tester.binding.clock.now())); // 1/0/1: kitchen light
        await tester.pump(const Duration(seconds: 1));
        expect(find.bySemanticsLabel(RegExp('Küche Licht, Küche, gerade aktiv')), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('Wohnen Licht, Wohnen, noch nichts gehört')), findsOneWidget);

        await tester.pump(const Duration(seconds: 6));
        expect(find.bySemanticsLabel(RegExp('Küche Licht, Küche, gehört')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }

    testWidgets('tapping a point names it under the plan; the title is not cut off on a phone', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final log = TelegramLog();
      await tester.pumpWidget(_app(FloorViewScreen(log: log, clock: tester.binding.clock.now)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Bus auf dem Grundriss'), findsOneWidget);
      // BarTitle wraps onto two lines instead of cutting the title off ("Bus auf dem Grund…").
      expect(find.ancestor(of: find.text('Bus auf dem Grundriss'), matching: find.byType(BarTitle)), findsOneWidget);
      expect(find.byKey(const ValueKey('floor-detail')), findsNothing);

      log.add(_t(2049, tester.binding.clock.now()));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.bySemanticsLabel(RegExp('Küche Licht, Küche')));
      await tester.pump();
      final detail = find.byKey(const ValueKey('floor-detail'));
      expect(detail, findsOneWidget);
      expect(find.descendant(of: detail, matching: find.text('Küche Licht')), findsOneWidget);
      expect(find.descendant(of: detail, matching: find.textContaining('zuletzt')), findsOneWidget);
      expect(find.descendant(of: detail, matching: find.textContaining('1/0/1')), findsOneWidget);
      // Right under the plan, on screen without scrolling.
      expect(tester.getRect(detail).bottom, lessThan(844));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('edit: drag moves a point, deleting it can be undone, deleting a level asks first', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = FloorViewStore.instance;
      await tester.pumpWidget(_app(FloorViewScreen(log: TelegramLog(), clock: tester.binding.clock.now)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Bearbeiten'));
      await tester.pump();
      final floor = store.view.floors.single;
      final point = floor.points.firstWhere((p) => p.name == 'Wohnen Licht');
      final before = (point.x, point.y);

      await tester.drag(find.bySemanticsLabel(RegExp('Wohnen Licht, Wohnen')), const Offset(60, 40));
      await tester.pump();
      expect(point.x, greaterThan(before.$1));
      expect(point.y, greaterThan(before.$2));

      // Delete in the sheet, then bring it back.
      final count = floor.points.length;
      await tester.tap(find.bySemanticsLabel(RegExp('Wohnen Licht, Wohnen')));
      await tester.pumpAndSettle();
      expect(find.text('Punkt'), findsOneWidget, reason: 'the sheet says what it edits');
      expect(find.text('Fertig'), findsWidgets);
      await tester.tap(find.text('Löschen'));
      await tester.pumpAndSettle();
      expect(floor.points.length, count - 1);
      expect(find.text('Punkt gelöscht'), findsOneWidget);
      await tester.tap(find.text('Rückgängig'));
      await tester.pump();
      expect(floor.points.length, count);
      expect(floor.points.contains(point), isTrue);

      // One tap never deletes a level.
      await tester.tap(find.text('Ebene löschen'));
      await tester.pumpAndSettle();
      expect(store.view.floors, hasLength(1));
      expect(find.text('„Erdgeschoss“ löschen?'), findsOneWidget);
      expect(find.textContaining('${floor.points.length} Punkten'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(store.view.floors, hasLength(1));
      await tester.tap(find.text('Ebene löschen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Löschen'));
      await tester.pumpAndSettle();
      expect(store.view.floors, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('address picker: count, maximum explained, picked on top, discarding asks, built lazily', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final all = demoCatalog().groups.keys.toList()..sort();
      List<int>? result;
      var returned = false;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await pickGroupAddresses(
                  context,
                  title: 'Küche Licht',
                  initial: [all.last],
                  suggested: [all[5]],
                  max: 2,
                );
                returned = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Gruppenadressen'), findsOneWidget, reason: 'short title, not cut off');
      expect(find.text('Küche Licht'), findsOneWidget, reason: 'what the addresses are for');
      expect(find.text('1 von 2 gewählt'), findsOneWidget);
      // Lazily built: far fewer rows than addresses in the project.
      expect(all.length, greaterThan(40));
      expect(tester.widgetList(find.byType(CheckboxListTile)).length, lessThan(all.length ~/ 2));
      // The picked address comes first although it is the last of the project, then the suggestion.
      final tiles = tester.widgetList<CheckboxListTile>(find.byType(CheckboxListTile)).toList();
      expect(tiles[0].key, ValueKey(all.last));
      expect(tiles[0].value, isTrue);
      expect(tiles[1].key, ValueKey(all[5]));

      await tester.tap(find.byKey(ValueKey(all[5])));
      await tester.pump();
      expect(find.textContaining('2 von 2 gewählt'), findsOneWidget);
      expect(find.textContaining('Höchstzahl erreicht'), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile).at(2)).enabled, isFalse);

      // Leaving with a changed selection asks; cancelling stays.
      // The close button of the full-screen dialog, as the system back gesture would.
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.text('Geänderte Auswahl verwerfen?'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(returned, isFalse);
      // The close button of the full-screen dialog, as the system back gesture would.
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verwerfen'));
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(result, isNull);
    });

    testWidgets('empty state offers to add a level; a view from the house plan is not edited here', (tester) async {
      final store = FloorViewStore.instance;
      await store.storageOverride!.delete(FloorViewStore.path);
      await tester.pumpWidget(_app(FloorViewScreen(log: TelegramLog())));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Noch kein Grundriss'), findsOneWidget);
      expect(find.text('Ebene anlegen'), findsOneWidget);

      await tester.runAsync(() => store.replace(demoFloorView(german: true)..source = FloorView.sourceHomePlan));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Bearbeiten'), findsNothing);
      expect(find.textContaining('stammt aus dem Hausplan'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
