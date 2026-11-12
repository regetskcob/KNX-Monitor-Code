import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/export/telegram_files.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/recording.dart';
import 'package:knx_monitor/model/tap_points.dart';
import 'package:knx_monitor/monitor_model.dart';
import 'package:knx_monitor/theme/app_icons.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/details_sheet.dart';
import 'package:knx_monitor/ui/live_list.dart';
import 'package:knx_monitor/ui/telegram_row.dart';

/// A recording keeps its tap points (issue #8): labels, names and gaps, so opened later it shows
/// chips, the path and the gaps as live did.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime(2026, 11, 11, 9);
  DateTime at(int s) => t0.add(Duration(seconds: s));
  TapStatus p(int i, {bool up = true, bool paused = false}) => TapStatus(
    index: i,
    name: i == 0 ? 'Gira X1' : 'MDT IP-Interface',
    label: '1.${i + 1}',
    state: up ? TunnelState.connected : TunnelState.disconnected,
    paused: paused,
  );
  Telegram tg(DateTime time, {int tap = 0, List<Sighting> seen = const []}) => Telegram(
    time: time,
    source: 0x1105,
    destination: 0x0A03,
    type: TelegramType.write,
    data: Uint8List.fromList([1]),
    isSmall: true,
    tap: tap,
    sightings: seen,
  );

  /// Live gaps: 1.2 away from 10 s to 30 s, paused from 50 s, still paused at the end (60 s).
  TapGaps liveGaps() => TapGaps()
    ..update([p(0), p(1)], at(0))
    ..update([p(0), p(1, up: false)], at(10))
    ..update([p(0), p(1)], at(30))
    ..update([p(0), p(1, up: false, paused: true)], at(50));

  Recording recording(TapRecord? taps) => Recording(
    id: 'r',
    name: 'Zwei Linien',
    started: at(0),
    ended: at(60),
    telegrams: [
      tg(at(5), seen: const [Sighting(1, Duration(milliseconds: 40), 5)]),
      tg(at(20)),
      tg(at(40)),
    ],
    taps: taps,
  );

  Recording roundTrip(Recording r) => Recording.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, Object?>);

  tearDown(() {
    tapLabels.value = const [];
    tapGaps.update(const [], DateTime.now());
  });

  group('TapRecord', () {
    test('round trip: labels, names and gaps come back, an open gap ends with the recording', () {
      final taps = TapRecord.capture(['1.1', '1.2'], [p(0), p(1)], liveGaps(), from: at(0), to: at(60))!;
      final back = roundTrip(recording(taps)).taps!;
      expect(back.labels, ['1.1', '1.2']);
      expect(back.names, ['Gira X1', 'MDT IP-Interface']);
      expect(back.gaps.since, at(0));
      final gaps = back.gaps.all;
      expect(gaps, hasLength(2));
      expect((gaps[0].tap, gaps[0].from, gaps[0].to, gaps[0].paused), (1, at(10), at(30), false));
      expect((gaps[1].from, gaps[1].to, gaps[1].paused), (at(50), at(60), true));
      expect(back.gaps.state(1, at(20)), TapSeen.away);
      expect(back.gaps.state(1, at(40)), TapSeen.listening);
      expect(back.gaps.state(1, at(55)), TapSeen.paused);
      // Before tracking began nothing is known, as live.
      expect(back.gaps.state(1, at(-30)), TapSeen.unknown);
    });

    test('only the gaps that touch the recording go along', () {
      final taps = TapRecord.capture(['1.1', '1.2'], [p(0), p(1)], liveGaps(), from: at(35), to: at(45))!;
      expect(taps.gaps.all, isEmpty);
      expect(taps.gaps.state(1, at(40)), TapSeen.listening);
    });

    test('a single tap point saves nothing: the file stays as before', () {
      expect(TapRecord.capture(['1.1'], [p(0)], TapGaps(), from: at(0), to: at(60)), isNull);
      expect(recording(null).toJson().containsKey('taps'), isFalse);
    });

    test('names fall back to the label where the status does not know the tap point', () {
      final taps = TapRecord.capture(['1.1', '1.2'], [p(0)], TapGaps(), from: at(0), to: at(60))!;
      expect(taps.names, ['Gira X1', '1.2']);
      // Nothing tracked (single tap point live until now): no gaps, the labels still go along.
      expect(roundTrip(recording(taps)).taps!.gaps.all, isEmpty);
    });

    test('an older file without tap points stays readable and unchanged', () {
      final old = {
        'v': 1,
        'id': 'alt',
        'name': 'Aufnahme von früher',
        'started': at(0).microsecondsSinceEpoch,
        'ended': at(60).microsecondsSinceEpoch,
        'telegrams': [tg(at(5), tap: 1).toJson()],
      };
      final r = Recording.fromJson(old);
      expect(r.taps, isNull);
      expect(r.telegrams.single.tap, 1);
      expect(r.toJson()['taps'], isNull);
      expect(r.toJson()['v'], 1, reason: 'older versions read the file as before');
    });

    test('broken or foreign tap data is dropped, the recording still opens', () {
      for (final bad in <Object?>[
        'x',
        {'labels': 'x'},
        {
          'labels': <String>['1.1'],
        },
        {'labels': List.filled(TapPoint.max + 1, 'x')},
      ]) {
        final json = recording(null).toJson()..['taps'] = bad;
        expect(Recording.fromJson(json).taps, isNull, reason: '$bad');
      }
      // Gaps of a different number of tap points, a gap ending before it starts, a tap point out of
      // range, a time DateTime cannot hold, control characters and overlong names.
      final json = recording(null).toJson()
        ..['taps'] = {
          'labels': ['1.1', '1.2\n'],
          'names': ['A' * 200],
          'gaps': {
            'since': at(0).microsecondsSinceEpoch,
            'n': 2,
            'gaps': [
              [1, at(20).microsecondsSinceEpoch, at(10).microsecondsSinceEpoch],
              [7, at(10).microsecondsSinceEpoch, at(20).microsecondsSinceEpoch],
              [0, 9000000000000000000, 9000000000000000001],
              [1, at(10).microsecondsSinceEpoch, at(20).microsecondsSinceEpoch],
            ],
          },
        };
      final taps = Recording.fromJson(json).taps!;
      expect(taps.labels, ['1.1', '1.2 ']);
      expect(taps.names.first, hasLength(80));
      expect(taps.names.last, '1.2 ');
      expect(taps.gaps.all.single.from, at(10));
      final three = recording(null).toJson()
        ..['taps'] = {
          'labels': ['1.1', '1.2', '1.3'],
          'gaps': {'since': 0, 'n': 2, 'gaps': <Object?>[]},
        };
      expect(Recording.fromJson(three).taps!.gaps.since, isNull);
      final far = recording(null).toJson()
        ..['taps'] = {
          'labels': ['1.1', '1.2'],
          'gaps': {'since': 9000000000000000000, 'n': 2, 'gaps': <Object?>[]},
        };
      expect(Recording.fromJson(far).taps!.gaps.since, isNull);
    });

    test('an edited copy keeps the tap points', () {
      final taps = TapRecord.capture(['1.1', '1.2'], [p(0), p(1)], liveGaps(), from: at(0), to: at(60))!;
      expect(recording(taps).copyWith(name: 'Kopie').taps, same(taps));
    });
  });

  test('stopping a recording in the monitor saves its tap points and the open gap', () async {
    final tunnel = KnxTunnel('test');
    final model = MonitorModel(tunnel);
    addTearDown(model.dispose);
    model.startRecording();
    tunnel.tapPoints.value = [p(0), p(1, up: false)];
    tapLabels.value = const ['1.1', '1.2'];
    final r = roundTrip(model.stopRecording(name: 'x')!);
    expect(r.taps!.labels, ['1.1', '1.2']);
    expect(r.taps!.names, ['Gira X1', 'MDT IP-Interface']);
    final gap = r.taps!.gaps.all.single;
    expect((gap.tap, gap.paused), (1, false));
    expect(gap.to, isNotNull, reason: 'closed at the end of the recording');
    tunnel.tapPoints.value = const [];
  });

  group('TapScope', () {
    test('an opened recording answers with its own tap points, closing it restores live', () {
      tapLabels.value = const [];
      final taps = TapRecord.fromJson(
        TapRecord.capture(['1.1', '1.2'], [p(0), p(1)], liveGaps(), from: at(0), to: at(60))!.toJson(),
      );
      // Live: a single tap point, nothing marked.
      expect(TapScope.labels, isEmpty);
      expect(seenAtOneTapOnly(tg(at(40))), isFalse);
      TapScope.open(taps);
      expect(TapScope.labels, ['1.1', '1.2']);
      expect(TapScope.described(1), '1.2 · MDT IP-Interface');
      // At 40 s 1.2 listened: seen at 1.1 only. At 20 s 1.2 was away: says nothing.
      expect(seenAtOneTapOnly(tg(at(40))), isTrue);
      expect(seenAtOneTapOnly(tg(at(20))), isFalse);
      TapScope.close(taps);
      expect(TapScope.labels, isEmpty);
      expect(TapScope.described(1), '2');
      // A recording without tap points changes nothing.
      TapScope.open(null);
      expect(TapScope.labels, isEmpty);
    });

    test('CSV of an opened recording names its tap points instead of numbers', () {
      final taps = TapRecord.capture(['1.1', '1.2'], [p(0), p(1)], liveGaps(), from: at(0), to: at(60));
      TapScope.open(taps);
      addTearDown(() => TapScope.close(taps));
      final csv = buildCsv([
        tg(at(5), tap: 1, seen: const [Sighting(0, Duration(milliseconds: 40), 5)]),
      ]);
      expect(csv, contains('1.2|1.1+40.0/5'));
    });
  });

  group('gap lines', () {
    test('starts and ends of unreachable gaps, between the right telegrams', () {
      final marks = gapMarks(liveGaps().all);
      // The paused span is named in the strip only.
      expect(marks.map((m) => (m.time, m.start)), [(at(10), true), (at(30), false)]);
      expect(marksBetween(marks, at(5), at(20)).single.start, isTrue);
      expect(marksBetween(marks, at(20), at(40)).single.start, isFalse);
      expect(marksBetween(marks, at(5), at(40)), hasLength(2));
      expect(marksBetween(marks, at(40), null), isEmpty);
      expect(marksBetween(marks, at(0), at(10)), hasLength(1));
      expect(marksBetween(const [], at(0), null), isEmpty);
    });

    test('the edges: the line sits where the mark "not reachable" begins and ends, the end exclusive', () {
      final gaps = liveGaps();
      final marks = gapMarks(gaps.all);
      // [time] is what the line says, [at] where it sits (with the slack of the gap).
      expect(marks.map((m) => (m.time, m.at)), [(at(10), at(9)), (at(30), at(31))]);
      bool away(DateTime t) => gaps.state(1, t) == TapSeen.away;
      // Each telegram is marked "not reachable" exactly when it lies between the two lines, i.e.
      // when the start line sits below it (at or before it) and the end line above it (after it).
      for (final t in [
        at(8),
        at(9),
        at(10),
        at(30),
        at(31).subtract(const Duration(microseconds: 1)),
        at(31),
        at(32),
      ]) {
        final below = marksBetween(marks, at(0), t);
        final inside = below.any((m) => m.start) && !below.any((m) => !m.start);
        expect(inside, away(t), reason: '$t');
      }
      // Right at the end of the gap: still marked, and the end line is above it in the list.
      expect(away(at(30)), isTrue);
      expect(marksBetween(marks, at(20), at(30)), isEmpty, reason: 'the end line is above the telegram at 30 s');
      expect(away(at(31)), isFalse);
      expect(marksBetween(marks, at(20), at(31)).single.start, isFalse, reason: 'and below the one at 31 s');
    });

    Widget app(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

    testWidgets('an opened recording shows chips, the gap lines and the path as live', (tester) async {
      tester.view.physicalSize = const Size(500, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final r = roundTrip(
        recording(TapRecord.capture(['1.1', '1.2'], [p(0), p(1)], liveGaps(), from: at(0), to: at(60))),
      );
      TapScope.open(r.taps);
      addTearDown(() => TapScope.close(r.taps));
      await tester.pumpWidget(
        app(
          LiveList(
            items: r.telegrams,
            live: false,
            onTap: (_) {},
            onLongPress: (_) {},
            isFresh: (_) => false,
            issuesOf: (_) => const [],
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(TapChips), findsNWidgets(3));
      expect(find.text('1.2 (MDT IP-Interface) nicht erreichbar · 09:00:10'), findsOneWidget);
      expect(find.text('1.2 (MDT IP-Interface) wieder erreichbar · 09:00:30'), findsOneWidget);
      // Newest on top: the end of the gap above the telegram of 20 s, its start below it.
      final end = tester.getTopLeft(find.textContaining('wieder erreichbar')).dy;
      final start = tester.getTopLeft(find.textContaining('nicht erreichbar ·')).dy;
      expect(end, lessThan(start));
      // The row of 20 s carries the mark "not reachable at that time".
      expect(find.byTooltip('Zu dieser Zeit nicht erreichbar: 1.2'), findsOneWidget);

      await tester.pumpWidget(app(TelegramDetails(telegram: r.telegrams[1], tunnel: null, history: r.telegrams)));
      await tester.pumpAndSettle();
      expect(find.text('1.2 · MDT IP-INTERFACE'), findsOneWidget);
      expect(find.text('nicht erreichbar zu dieser Zeit · keine Aussage, ob gefiltert'), findsOneWidget);
    });

    testWidgets('live: "Messpunkt 1.2", and a telegram right at the end of a gap lies inside the lines', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(500, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tapLabels.value = const ['1.1', '1.2'];
      tapGaps
        ..update([p(0), p(1)], at(0))
        ..update([p(0), p(1, up: false)], at(10))
        ..update([p(0), p(1)], at(30));
      await tester.pumpWidget(
        app(
          LiveList(
            items: [tg(at(20)), tg(at(30)), tg(at(40))],
            live: false,
            onTap: (_) {},
            onLongPress: (_) {},
            isFresh: (_) => false,
            issuesOf: (_) => const [],
          ),
        ),
      );
      final back = find.text('Messpunkt 1.2 wieder erreichbar · 09:00:30');
      expect(back, findsOneWidget);
      expect(find.byIcon(AppIcons.tapBack), findsOneWidget);
      // Rows of 20 s and 30 s carry the mark; newest on top, so both lie below the line.
      final marked = find.byTooltip('Zu dieser Zeit nicht erreichbar: 1.2');
      expect(marked, findsNWidgets(2));
      final line = tester.getTopLeft(back).dy;
      for (final e in marked.evaluate()) {
        expect(tester.getTopLeft(find.byWidget(e.widget)).dy, greaterThan(line));
      }
      // Readable like other notes: body size, not the small print.
      expect(tester.widget<Text>(back).style!.fontSize, greaterThanOrEqualTo(14));
    });

    testWidgets('without tap points no gap lines and no chips', (tester) async {
      tapGaps
        ..update([p(0), p(1)], at(0))
        ..update([p(0), p(1, up: false)], at(10));
      // Gaps tracked, but the labels say a single tap point: nothing shows.
      tapLabels.value = const ['1.1'];
      await tester.pumpWidget(
        app(
          LiveList(
            items: [tg(at(5)), tg(at(20))],
            live: false,
            onTap: (_) {},
            onLongPress: (_) {},
            isFresh: (_) => false,
            issuesOf: (_) => const [],
          ),
        ),
      );
      expect(find.textContaining('nicht erreichbar'), findsNothing);
      expect(find.byType(TapChips), findsNothing);
    });
  });
}
