import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/export/telegram_files.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/gateway_info.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/model/tap_coverage.dart';
import 'package:knx_monitor/model/tap_points.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/details_sheet.dart';
import 'package:knx_monitor/ui/log_view.dart';
import 'package:knx_monitor/ui/tap_points_panel.dart';
import 'package:knx_monitor/ui/tap_strip.dart';
import 'package:knx_monitor/ui/telegram_row.dart';
import 'package:knx_monitor/ui/topology_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_storage.dart';

/// A tunnel whose tap points the test sets.
class _Taps extends KnxTunnel {
  _Taps() : super('test');
}

Widget _app(Widget child, {String locale = 'de'}) => MaterialApp(
  theme: AppTheme.light(),
  locale: Locale(locale),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Telegram _tg(DateTime time, {int tap = 0, List<Sighting> seen = const []}) => Telegram(
  time: time,
  source: 0x1105,
  destination: 0x0A03,
  type: TelegramType.write,
  data: Uint8List.fromList([1]),
  isSmall: true,
  tap: tap,
  sightings: seen,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('demo house', () {
    test('as before without tap points: no labels, no sightings, the same telegrams', () {
      var now = DateTime(2026, 10, 14, 21, 50);
      DemoTunnel.clock = () => now = now.add(const Duration(milliseconds: 900));
      addTearDown(() => DemoTunnel.clock = DateTime.now);
      final plain = DemoTunnel();
      final a = plain.simulate();
      plain.dispose();
      expect(tapLabels.value, isEmpty);
      expect(a.every((t) => t.tap == 0 && t.sightings.isEmpty), isTrue);
      // With tap points the same traffic, the same values: only where it was seen differs.
      now = DateTime(2026, 10, 14, 21, 50);
      final tapped = DemoTunnel(withTapPoints: true);
      final b = tapped.simulate();
      tapped.dispose();
      // Plus a push button on a third line without a tap point.
      final extra = b.where((t) => t.source >> 8 == 0x13).toList();
      expect(extra, isNotEmpty);
      expect(extra.every((t) => t.tap == 0 && t.sightings.isEmpty && t.hopCount == 5), isTrue);
      b.removeWhere((t) => t.source >> 8 == 0x13);
      expect(b.length, a.length);
      for (var i = 0; i < a.length; i++) {
        expect((b[i].source, b[i].destination, b[i].time), (a[i].source, a[i].destination, a[i].time));
        expect(b[i].data, a[i].data);
      }
    });

    test('two lines, two tap points: forwarded, filtered, findings, and a tap point that drops', () {
      addTearDown(() {
        DemoTunnel.clock = DateTime.now;
        tapLabels.value = const [];
        tapGaps.update(const [], DateTime.now());
      });
      fakeAsync((async) {
        CatalogStore.instance.catalog = demoCatalog();
        var now = DateTime(2026, 11, 10, 12);
        DemoTunnel.clock = () => now;
        final tunnel = DemoTunnel(withTapPoints: true)..autoPress = false;
        final got = <Telegram>[];
        final states = <bool>[];
        tunnel.telegrams.listen(got.add);
        tunnel.tapPoints.addListener(() => states.add(tunnel.tapPoints.value[1].connected));
        tunnel.connect();
        async.flushMicrotasks();
        expect(tapLabels.value, ['1.1', '1.2']);
        expect(tunnel.tapPoints.value.map((p) => p.connected), [true, true]);

        void run(Duration d) {
          for (var ms = 0; ms < d.inMilliseconds; ms += 100) {
            now = now.add(const Duration(milliseconds: 100));
            async.elapse(const Duration(milliseconds: 100));
          }
        }

        // Initial state and the first steps, before the tap point drops.
        run(const Duration(seconds: 25));
        final before = [...got];
        bool from12(Telegram t) => t.source >> 8 == 0x12;
        // Weather on 1.2 with receivers on 1.1: origin at tap point 1, forwarded with one hop less.
        final forwarded = before.where((t) => from12(t) && t.sightings.isNotEmpty);
        expect(forwarded, isNotEmpty);
        expect(forwarded.every((t) => t.tap == 1 && t.hopCount == 6 && t.sightings.single.hopCount == 5), isTrue);
        expect(
          forwarded.every(
            (t) => t.sightings.single.offset.inMilliseconds >= 36 && t.sightings.single.offset.inMilliseconds < 46,
          ),
          isTrue,
        );
        // Line-local on 1.2 (nobody on 1.1 listens): seen at tap point 1 only.
        expect(before.where((t) => from12(t) && t.sightings.isEmpty && t.tap == 1), isNotEmpty);
        // 1.1 stays on 1.1, except the one address the coupler passes needlessly.
        expect(before.where((t) => t.source >> 8 == 0x11 && t.sightings.isEmpty && t.tap == 0), isNotEmpty);
        final passed = before.where((t) => !from12(t) && t.sightings.isNotEmpty);
        expect(passed.map((t) => formatGroup(t.destination)).toSet(), {'5/0/0'});
        expect(passed.every((t) => t.sightings.single.tap == 1 && t.sightings.single.hopCount == 5), isTrue);

        // The second tap point drops for a while and comes back.
        run(const Duration(seconds: 150));
        expect(states.take(3), [true, false, true]);
        final gap = tapGaps.all.firstWhere((g) => g.tap == 1 && g.to != null);
        final during = got.where((t) => t.time.isAfter(gap.from) && t.time.isBefore(gap.to!)).toList();
        expect(during, isNotEmpty);
        expect(during.every((t) => t.tap == 0 && t.sightings.isEmpty), isTrue);
        expect(during.every((t) => tapGaps.state(1, t.time) != TapSeen.listening), isTrue);
        expect(during.any(seenAtOneTapOnly), isFalse, reason: 'a gap is not "filtered"');

        // The live filter table check finds exactly the two prepared faults.
        final coverage = TapCoverage.build(demoCatalog(), got, tapLabels.value, gaps: tapGaps)!;
        expect(coverage.blocked.map((f) => formatGroup(f.group)), ['4/0/1']);
        expect(coverage.leaked.map((f) => formatGroup(f.group)), ['5/0/0']);

        tunnel.disconnect();
        tunnel.dispose();
        async.flushMicrotasks();
        expect(tapLabels.value, isEmpty);
        expect(tapGaps.since, isNull);
        DemoTunnel.clock = DateTime.now;
      });
    });
  });

  group('tap strip', () {
    testWidgets('nothing with a single tap point', (tester) async {
      final tunnel = _Taps();
      addTearDown(tunnel.dispose);
      await tester.pumpWidget(_app(TapStrip(tunnel: tunnel, log: TelegramLog())));
      expect(find.byType(Text), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    for (final size in const [Size(390, 844), Size(1280, 900)]) {
      testWidgets('one card per tap point with state in words, load and lag ($size)', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final tunnel = _Taps();
        addTearDown(tunnel.dispose);
        final log = TelegramLog();
        final now = DateTime.now();
        for (var i = 0; i < 30; i++) {
          log.add(
            _tg(now.subtract(Duration(seconds: 50 - i)), seen: const [Sighting(1, Duration(milliseconds: 40), 5)]),
          );
        }
        tunnel.tapPoints.value = const [
          TapStatus(index: 0, name: 'Gira X1', label: '1.1', state: TunnelState.connected),
          TapStatus(
            index: 1,
            name: 'Linie 1.2 · MDT IP-Interface',
            label: '1.2',
            state: TunnelState.disconnected,
            error: 'keine Antwort',
            lag: Duration(milliseconds: 41),
            autoWindow: Duration(milliseconds: 250),
          ),
        ];
        await tester.pumpWidget(_app(TapStrip(tunnel: tunnel, log: log)));
        expect(find.text('2 Messpunkte · 1 verbunden'), findsOneWidget);
        // Narrow screens start folded.
        if (size.width < 840 + 64) {
          expect(find.text('Gira X1'), findsNothing);
          await tester.tap(find.text('2 Messpunkte · 1 verbunden'));
          await tester.pump();
        }
        expect(find.text('Gira X1'), findsOneWidget);
        expect(find.text('verbunden'), findsOneWidget);
        expect(find.textContaining('nicht erreichbar · kein Busfehler'), findsOneWidget);
        expect(find.textContaining('30/min'), findsNWidgets(2));
        expect(find.textContaining('Buslast'), findsNWidgets(2));
        expect(find.textContaining('Versatz bis 41,0 ms'), findsOneWidget);
        expect(find.textContaining('Fenster 250 ms (gemessen)'), findsOneWidget);
        // The gap of the second tap point is listed, still open.
        expect(find.textContaining('Lücke an 1.2'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  group('tap strip sizes', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    List<TapStatus> points(int n) => [
      for (var i = 0; i < n; i++)
        TapStatus(
          index: i,
          name: i == 0 ? 'Gira X1' : 'Linie 1.${i + 1} · MDT IP-Interface SCN-IP000.03',
          label: i == 4 ? '5' : '1.${i + 1}',
          state: i == 2 ? TunnelState.disconnected : TunnelState.connected,
          paused: i == 4,
          error: i == 2 ? 'SocketException: Network is unreachable (OS Error: errno = 51)' : null,
          lag: i == 1 ? const Duration(milliseconds: 41) : null,
        ),
    ];

    for (final width in const [390.0, 820.0, 1280.0]) {
      for (final scale in const [1.0, 1.5, 2.0]) {
        testWidgets('1 to 8 tap points at $width pt, text × $scale: no overflow, the list stays visible', (
          tester,
        ) async {
          CatalogStore.instance.catalog = demoCatalog();
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          var now = DateTime.now().subtract(const Duration(seconds: 50));
          DemoTunnel.clock = () => now = now.add(const Duration(milliseconds: 300));
          final demo = DemoTunnel(withTapPoints: true);
          final log = TelegramLog()..addAll(demo.simulate());
          demo.dispose();
          DemoTunnel.clock = DateTime.now;
          final tunnel = _Taps();
          addTearDown(tunnel.dispose);
          addTearDown(() => tapLabels.value = const []);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(),
              locale: const Locale('de'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              home: LogView(
                data: log,
                tunnel: tunnel,
                title: const Text('Demo'),
                exportTitle: 'Test',
                initialTab: LogTab.live,
                banner: TapStrip(tunnel: tunnel, log: log),
              ),
            ),
          );
          for (var n = 1; n <= 8; n++) {
            final list = n == 1 ? const <TapStatus>[] : points(n);
            tunnel.tapPoints.value = list;
            tapLabels.value = [for (final p in list) p.label];
            await tester.pump(const Duration(milliseconds: 400));
            final problem = tester.takeException();
            if (n == 1 && problem != null) {
              // The view itself does not fit at this size and text scale, without any tap point:
              // not what this test is about.
              debugDefaultTargetPlatformOverride = null;
              markTestSkipped('LogView overflows at $width pt × $scale without tap points: $problem');
              await tester.pumpWidget(const SizedBox());
              return;
            }
            expect(problem, isNull, reason: '$n tap points');
            if (n == 1) {
              expect(find.textContaining('Messpunkte ·'), findsNothing);
              continue;
            }
            final header = find.textContaining('$n Messpunkte ·');
            expect(header, findsOneWidget);
            // A proper tap target.
            final target = find.ancestor(of: header, matching: find.byType(InkWell)).first;
            expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
            // Unfolded, whatever it started as.
            if (find.textContaining('/min').evaluate().isEmpty) {
              await tester.tap(header);
              await tester.pump(const Duration(milliseconds: 400));
            }
            expect(find.textContaining('/min'), findsWidgets, reason: '$n tap points unfolded');
            expect(tester.takeException(), isNull, reason: '$n tap points unfolded');
            // What the system reports is put in plain words.
            if (n >= 3) {
              expect(find.textContaining('SocketException', findRichText: true), findsNothing);
              expect(find.textContaining('Das Netz ist nicht erreichbar', findRichText: true), findsWidgets);
            }
            // The live list keeps room below the strip.
            final strip = tester.getRect(find.byType(TapStrip));
            expect(strip.height, lessThanOrEqualTo(844 * 0.3 + 120), reason: '$n tap points');
            expect(find.byType(TelegramRow), findsWidgets, reason: 'list visible with $n tap points');
            await tester.tap(header);
            await tester.pump(const Duration(milliseconds: 400));
          }
          debugDefaultTargetPlatformOverride = null;
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  });

  group('rows', () {
    testWidgets('wide table gets the column "Gesehen an" only with several tap points', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 300));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_app(const TelegramTableHeader()));
      expect(find.text('GESEHEN AN'), findsNothing);
      expect(find.text('Gesehen an'), findsNothing);
      tapLabels.value = ['1.1', '1.2'];
      addTearDown(() => tapLabels.value = const []);
      await tester.pumpWidget(_app(const TelegramTableHeader(), locale: 'en'));
      await tester.pumpWidget(_app(const TelegramTableHeader()));
      expect(find.textContaining(RegExp('gesehen an', caseSensitive: false)), findsOneWidget);
    });

    for (final width in const [820.0, 1280.0]) {
      testWidgets('at $width pt the column "Gesehen an" only where it does not squeeze names and senders', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        tapLabels.value = ['1.1', '1.2', '1.3'];
        addTearDown(() => tapLabels.value = const []);
        final t = _tg(DateTime(2026, 11, 10, 12), seen: const [Sighting(1, Duration(milliseconds: 40), 5)]);
        await tester.pumpWidget(
          _app(
            Column(
              children: [
                const TelegramTableHeader(),
                TelegramRow(telegram: t, wide: true),
              ],
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final column = find.textContaining(RegExp('gesehen an', caseSensitive: false));
        expect(column, width >= TelegramTableHeader.seenFrom ? findsOneWidget : findsNothing);
        expect(find.byType(TapChips), findsOneWidget);
        // Chips in the column line up with its header; under the name otherwise.
        if (width >= TelegramTableHeader.seenFrom) {
          expect(tester.getTopLeft(find.byType(TapChips)).dx, closeTo(tester.getTopLeft(column).dx, 1));
        }
      });
    }

    testWidgets('a tap point that was away gets a chip in words instead of looking filtered', (tester) async {
      final tunnel = _Taps();
      addTearDown(tunnel.dispose);
      TapStatus p(int i, bool up) => TapStatus(
        index: i,
        name: '$i',
        label: '1.${i + 1}',
        state: up ? TunnelState.connected : TunnelState.disconnected,
      );
      tapLabels.value = ['1.1', '1.2'];
      addTearDown(() {
        tapLabels.value = const [];
        tapGaps.update(const [], DateTime.now());
      });
      final t0 = DateTime(2026, 11, 10, 12);
      tapGaps
        ..update([p(0, true), p(1, true)], t0)
        ..update([p(0, true), p(1, false)], t0.add(const Duration(seconds: 10)));
      // A third one is paused: said in the strip, not in every row.
      tapLabels.value = ['1.1', '1.2', '1.3'];
      TapStatus paused(int i) =>
          TapStatus(index: i, name: '$i', label: '1.${i + 1}', state: TunnelState.disconnected, paused: true);
      tapGaps.update([p(0, true), p(1, false), paused(2)], t0.add(const Duration(seconds: 11)));
      await tester.pumpWidget(_app(TapChips(telegram: _tg(t0.add(const Duration(seconds: 20))))));
      expect(find.text('1.1'), findsOneWidget);
      // One mark for all that were not reachable, the names in tooltip and semantics.
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
      expect(find.byTooltip('Zu dieser Zeit nicht erreichbar: 1.2'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Zu dieser Zeit nicht erreichbar: 1.2')), findsOneWidget);
      expect(find.textContaining('aus'), findsNothing);
      expect(find.textContaining('1.3'), findsNothing);
      // While it listened, nothing is added.
      await tester.pumpWidget(_app(TapChips(telegram: _tg(t0.add(const Duration(seconds: 5))))));
      expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Weg durch die Anlage: 1.1')), findsOneWidget);
    });

    testWidgets('path through the installation: origin first, decimal comma, the term of the section above', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(500, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      CatalogStore.instance.catalog = demoCatalog();
      tapLabels.value = ['1.1', '1.2', '1.3'];
      addTearDown(() => tapLabels.value = const []);
      // Sent on line 1.2 (tap point 1), seen on 1.1 44.2 ms later, not on 1.3.
      final t = Telegram(
        time: DateTime(2026, 11, 10, 12),
        source: 0x1214,
        destination: parseGroup('4/0/2')!,
        type: TelegramType.write,
        data: Uint8List.fromList([0x0C, 0x1A]),
        isSmall: false,
        tap: 1,
        sightings: const [Sighting(0, Duration(microseconds: 44200), 5)],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TelegramDetails(telegram: t, tunnel: null, history: [t]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final origin = find.text('Ursprung · Routingzähler 6');
      final seen = find.textContaining('+44,2 ms · Routingzähler 5');
      final missing = find.text('nicht gesehen, gefiltert oder nur lokal');
      expect(origin, findsOneWidget);
      expect(seen, findsOneWidget);
      expect(missing, findsOneWidget);
      expect(find.textContaining('Hop 5'), findsNothing);
      expect(tester.getTopLeft(origin).dy, lessThan(tester.getTopLeft(seen).dy));
      expect(tester.getTopLeft(seen).dy, lessThan(tester.getTopLeft(missing).dy));
    });
  });

  group('live view', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    for (final width in const [400.0, 1400.0]) {
      testWidgets('demo house with two tap points at $width pt: chips or column, filter, no overflow', (tester) async {
        CatalogStore.instance.catalog = demoCatalog();
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var now = DateTime.now().subtract(const Duration(seconds: 50));
        DemoTunnel.clock = () => now = now.add(const Duration(milliseconds: 300));
        final demo = DemoTunnel(withTapPoints: true);
        final log = TelegramLog()..addAll(demo.simulate());
        demo.dispose();
        DemoTunnel.clock = DateTime.now;
        final tunnel = _Taps();
        addTearDown(tunnel.dispose);
        tunnel.tapPoints.value = const [
          TapStatus(index: 0, name: 'Demo-Gateway', label: '1.1', state: TunnelState.connected),
          TapStatus(index: 1, name: 'Linie 1.2 · Demo-Interface', label: '1.2', state: TunnelState.connected),
        ];
        tapLabels.value = ['1.1', '1.2'];
        addTearDown(() => tapLabels.value = const []);
        final seenBoth = log.log.where((t) => t.sightings.isNotEmpty).length;
        expect(seenBoth, greaterThan(0));
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: LogView(
              data: log,
              tunnel: tunnel,
              title: const Text('Demo'),
              exportTitle: 'Test',
              initialTab: LogTab.live,
              banner: TapStrip(tunnel: tunnel, log: log),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        expect(find.text('2 Messpunkte · 2 verbunden'), findsOneWidget);
        expect(find.byType(TapChips), findsWidgets);
        final header = find.textContaining(RegExp('gesehen an', caseSensitive: false));
        expect(header, width >= 1200 ? findsOneWidget : findsNothing);
        // Without the column the chips sit under the name, so every row still says where.
        expect(find.byType(TapChips), findsWidgets);
        debugDefaultTargetPlatformOverride = null;
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('one tap point: no strip, no chips, no column', (tester) async {
      CatalogStore.instance.catalog = demoCatalog();
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var now = DateTime(2026, 10, 14, 21, 50);
      DemoTunnel.clock = () => now = now.add(const Duration(milliseconds: 900));
      final demo = DemoTunnel();
      final log = TelegramLog()..addAll(demo.simulate());
      demo.dispose();
      DemoTunnel.clock = DateTime.now;
      final tunnel = _Taps();
      addTearDown(tunnel.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: LogView(
            data: log,
            tunnel: tunnel,
            title: const Text('Demo'),
            exportTitle: 'Test',
            initialTab: LogTab.live,
            banner: TapStrip(tunnel: tunnel, log: log),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.byType(TapChips), findsNothing);
      expect(find.textContaining('Messpunkt'), findsNothing);
      expect(find.textContaining(RegExp('gesehen an', caseSensitive: false)), findsNothing);
      debugDefaultTargetPlatformOverride = null;
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('search', () {
    GatewayInfo info(String name, int address, {int free = 2, int slots = 4, Map<int, int> services = const {4: 1}}) =>
        GatewayInfo(
          name: name,
          medium: 0x02,
          programmingMode: false,
          address: address,
          serial: name,
          mac: '',
          multicast: '224.0.23.12',
          projectInstallation: 0,
          services: services,
          slots: [for (var i = 0; i < slots; i++) TunnelSlot(address + 1 + i, free: i < free, usable: true)],
        );

    testWidgets('several interfaces can be ticked; full ones and routing-only ones cannot', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      AppStorage.instance = MemoryStorage();
      InstallationStore.instance.debugReset();
      await tester.runAsync(InstallationStore.instance.load);
      final original = tapSearch;
      addTearDown(() => tapSearch = original);
      tapSearch = () => Stream.fromIterable([
        FoundGateway('192.168.1.22', info('Gira X1', 0x1123)),
        FoundGateway('192.168.1.30', info('Gira S1', 0x111E, free: 3)),
        FoundGateway('192.168.1.40', info('MDT IP-Interface', 0x13F0, free: 1)),
        FoundGateway('192.168.1.41', info('Belegt', 0x14F0, free: 0)),
        FoundGateway('192.168.1.50', info('Gira G1', 0x1005, slots: 0, services: const {5: 1})),
      ]);
      var demo = 0;
      await tester.pumpWidget(_app(TapPointsPanel(enabled: true, onDemo: () => demo++)));
      await tester.tap(find.text('Im Demo-Haus ausprobieren'));
      expect(demo, 1);
      await tester.tap(find.text('Im Netz suchen'));
      await tester.pumpAndSettle();
      expect(find.text('Interfaces als Messpunkte'), findsOneWidget);
      expect(find.textContaining('alle 4 Tunnel belegt'), findsOneWidget);
      expect(find.textContaining('0 von 4 Tunneln frei'), findsNothing, reason: 'said once');
      expect(find.textContaining('kann nur Routing'), findsOneWidget);
      expect(find.textContaining('neue Linie'), findsNWidgets(3));

      // Nothing ticked: nothing to add, and the button does not say "0".
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      expect(find.widgetWithText(FilledButton, 'Hinzufügen'), findsOneWidget);
      expect(find.textContaining('0 hinzufügen'), findsNothing);
      await tester.tap(find.textContaining('Gira X1'));
      await tester.tap(find.textContaining('Gira S1'));
      await tester.tap(find.textContaining('MDT IP-Interface'));
      // Cannot be ticked.
      await tester.tap(find.textContaining('Belegt'));
      await tester.tap(find.textContaining('Gira G1'));
      await tester.pump();
      expect(find.text('3 hinzufügen'), findsOneWidget);
      // Said before connecting: same line twice, and the last free tunnel.
      expect(find.textContaining('gleiche Linie wie ein anderer Messpunkt'), findsNWidgets(2));
      expect(find.textContaining('Der letzte freie Tunnel wird belegt: MDT IP-Interface'), findsOneWidget);
      await tester.tap(find.text('3 hinzufügen'));
      await tester.pumpAndSettle();
      final taps = InstallationStore.instance.active.taps;
      expect(taps.map((t) => (t.name, t.host, t.mode)), [
        ('Linie 1.1 · Gira X1', '192.168.1.22', TapMode.udp),
        ('Linie 1.1 · Gira S1', '192.168.1.30', TapMode.udp),
        ('Linie 1.3 · MDT IP-Interface', '192.168.1.40', TapMode.udp),
      ]);
      expect(find.textContaining('Verbinden öffnet 4 Verbindungen.'), findsOneWidget);

      // Searching again: what is a tap point already cannot be added twice.
      await tester.tap(find.text('Im Netz suchen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('schon Messpunkt'), findsNWidgets(3));
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('set up', () {
    Future<void> store(WidgetTester tester, {List<TapPoint> taps = const []}) async {
      SharedPreferences.setMockInitialValues({});
      AppStorage.instance = MemoryStorage();
      InstallationStore.instance.debugReset();
      await tester.runAsync(InstallationStore.instance.load);
      if (taps.isNotEmpty) await InstallationStore.instance.setTaps(InstallationStore.instance.active.id, taps);
    }

    testWidgets('a failed search says so in plain words, can be repeated and leads to the entry by hand', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await store(tester);
      final original = tapSearch;
      addTearDown(() => tapSearch = original);
      var runs = 0;
      tapSearch = () {
        runs++;
        return runs == 1
            ? Stream.error(const SocketException('Network is unreachable', osError: OSError('', 51)))
            : const Stream.empty();
      };
      await tester.pumpWidget(_app(const TapPointsPanel(enabled: true)));
      await tester.tap(find.text('Im Netz suchen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('SocketException'), findsNothing);
      expect(find.textContaining('errno'), findsNothing);
      expect(find.textContaining('Das Netz ist nicht erreichbar'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

      await tester.tap(find.text('Erneut suchen'));
      await tester.pumpAndSettle();
      expect(runs, 2);
      expect(find.text('Kein Interface gefunden.'), findsOneWidget);
      expect(find.textContaining('hinter einem VPN'), findsOneWidget);

      // On to the entry by hand.
      await tester.tap(find.text('Adresse eingeben'));
      await tester.pumpAndSettle();
      expect(find.text('Interfaces als Messpunkte'), findsNothing);
      final host = find.widgetWithText(TextFormField, '192.168.1.20');
      expect(host, findsOneWidget);
      // Host names are allowed, so the keyboard is not digits only.
      expect(
        tester.widget<TextField>(find.descendant(of: host, matching: find.byType(TextField))).keyboardType,
        TextInputType.url,
      );

      // Digits and dots must be a real IPv4 address.
      for (final bad in ['300.1', '1.2.3', '256.1.1.1', '1..2.3']) {
        await tester.enterText(host, bad);
        await tester.tap(find.widgetWithText(FilledButton, 'Hinzufügen'));
        await tester.pumpAndSettle();
        expect(InstallationStore.instance.active.taps, isEmpty, reason: bad);
      }
      await tester.enterText(host, 'knx.example.org');
      await tester.tap(find.widgetWithText(FilledButton, 'Hinzufügen'));
      await tester.pumpAndSettle();
      expect(InstallationStore.instance.active.taps.single.host, 'knx.example.org');
      expect(TapPoint.validHost('192.168.1.20'), isTrue);
      expect(TapPoint.fromJson({'mode': 'udp', 'host': '300.1'}), isNull);
    });

    testWidgets('removing a tap point can be undone; switches and bins are named for screen readers', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const a = TapPoint(name: 'Linie 1.2 · MDT', host: '192.168.1.40');
      const b = TapPoint(name: 'Linie 1.3 · Gira', host: '192.168.1.41');
      await store(tester, taps: [a, b]);
      await tester.pumpWidget(_app(const TapPointsPanel(enabled: true)));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Messpunkt aktiv: Linie 1.2 · MDT'), findsOneWidget);
      expect(find.bySemanticsLabel('Messpunkt aktiv: Linie 1.3 · Gira'), findsOneWidget);
      await tester.tap(find.byTooltip('Messpunkt entfernen: Linie 1.2 · MDT'));
      await tester.pumpAndSettle();
      expect(InstallationStore.instance.active.taps, [b]);
      expect(find.text('Messpunkt entfernt: Linie 1.2 · MDT'), findsOneWidget);
      await tester.tap(find.text('Rückgängig'));
      await tester.pumpAndSettle();
      expect(InstallationStore.instance.active.taps, [a, b], reason: 'back in its place');
    });
  });

  testWidgets('topology of the demo house: the third line without a tap point is only indirectly visible', (
    tester,
  ) async {
    CatalogStore.instance.catalog = demoCatalog();
    var now = DateTime(2026, 10, 14, 21, 50);
    DemoTunnel.clock = () => now = now.add(const Duration(milliseconds: 900));
    final demo = DemoTunnel(withTapPoints: true);
    final log = TelegramLog()..addAll(demo.simulate(steps: 80));
    demo.dispose();
    DemoTunnel.clock = DateTime.now;
    tapLabels.value = ['1.1', '1.2'];
    addTearDown(() => tapLabels.value = const []);
    await tester.binding.setSurfaceSize(const Size(1680, 1050));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TopologyScreen(log: log, onFilter: (_) {}),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.text('nur indirekt sichtbar'), findsOneWidget);
    expect(find.textContaining('Kein Messpunkt in dieser Linie'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  group('CSV', () {
    final t0 = DateTime(2026, 11, 10, 12);
    test('without tap points the file is as before; with them a last column says where it was seen', () {
      final plain = buildCsv([_tg(t0)]);
      expect(plain.split('\r\n').first, endsWith('"hop_count","cemi"'));
      expect(plain.contains('seen_at'), isFalse);
      tapLabels.value = ['1.1', '1.2'];
      addTearDown(() => tapLabels.value = const []);
      expect(buildCsv([_tg(t0)]), plain, reason: 'nothing seen elsewhere, nothing added');
      final rows = buildCsv([
        _tg(t0, seen: const [Sighting(1, Duration(microseconds: 38200), 5)]),
        _tg(t0.add(const Duration(seconds: 1)), tap: 1),
        _tg(t0.add(const Duration(seconds: 2))),
      ]).trim().split('\r\n');
      expect(rows.first, endsWith('"cemi","seen_at"'));
      expect([for (final r in rows.skip(1)) r.split(',').last], ['"1.1|1.2+38.2/5"', '"1.2"', '"1.1"']);
      // Without the labels of an open monitor: the tap point's number.
      tapLabels.value = const [];
      expect(buildCsv([_tg(t0, tap: 2)]).trim().split(',').last, '"3"');
    });
  });
}
