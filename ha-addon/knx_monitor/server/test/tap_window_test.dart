import 'dart:typed_data';

import 'package:knx/knx.dart';
import 'package:knx_monitor_server/src/tap_window.dart';
import 'package:test/test.dart';

// The same cases as test/tap_points_test.dart in the app.
void main() {
  group('TapWindowMeter limits', () {
    final t0 = DateTime(2026, 11, 10, 12);
    Telegram tg(int tap, int ms, {int value = 1, List<Sighting> sightings = const []}) => Telegram(
      time: t0.add(Duration(milliseconds: ms)),
      source: 0x1105,
      destination: 0x0A03,
      type: TelegramType.write,
      data: Uint8List.fromList([value]),
      isSmall: true,
      tap: tap,
      sightings: sightings,
    );

    test('amplifier: unsecured telegrams repeated 1.3 s later at a second tap point widen nothing', () {
      var window = TapWindowMeter.floor;
      final m = TapWindowMeter(current: (_) => window, auto: {0, 1});
      for (var i = 0; i < 8; i++) {
        expect(m.released(tg(0, i * 10000, value: i)), isNull);
        final change = m.released(tg(1, i * 10000 + 1300, value: i));
        expect(change, isNull, reason: 'pair $i');
        if (change != null) window = change.$2;
      }
      expect(window, TapWindowMeter.floor);
    });

    test('a measured window is capped at one second', () {
      final m = TapWindowMeter(current: (_) => TapWindowMeter.floor, auto: {0, 1});
      (int, Duration)? change;
      for (var i = 0; i < 3; i++) {
        m.released(tg(0, i * 10000, value: i));
        change = m.released(tg(1, i * 10000 + 900, value: i));
      }
      expect(change, (1, TapWindowMeter.max));
      expect(TapWindowMeter.max, const Duration(seconds: 1));
    });

    test('a widened window comes back down after a calm stretch, and a late copy restarts the count', () {
      var window = const Duration(milliseconds: 900);
      final m = TapWindowMeter(current: (_) => window, auto: {0, 1});
      const near = [Sighting(1, Duration(milliseconds: 40), 5)];
      (int, Duration)? change;
      for (var i = 0; i < TapWindowMeter.kept - 1; i++) {
        change = m.released(tg(0, i * 1000, sightings: near));
        expect(change, isNull, reason: 'telegram $i');
      }
      // One copy that came too late: the calm stretch starts again.
      m.released(tg(0, 500000, value: 0));
      m.released(tg(1, 500950, value: 0));
      for (var i = 0; i < TapWindowMeter.kept - 1; i++) {
        expect(m.released(tg(0, 600000 + i * 1000, sightings: near)), isNull, reason: 'after the late copy, $i');
      }
      change = m.released(tg(0, 700000, sightings: near));
      expect(change, (1, TapWindowMeter.floor));
      window = change!.$2;
      expect(m.released(tg(0, 701000, sightings: near)), isNull);
    });

    test('a window set by hand is not narrowed either', () {
      final m = TapWindowMeter(current: (_) => const Duration(seconds: 5), auto: {0});
      for (var i = 0; i < 3 * TapWindowMeter.kept; i++) {
        expect(m.released(tg(0, i * 1000, sightings: const [Sighting(1, Duration(milliseconds: 40), 5)])), isNull);
      }
    });
  });

  group('TapBacklog counts what is inside the merger', () {
    test('three tap points, steady merged traffic that never drains: no forced release in 20,000 telegrams', () {
      final merger = TapMerger(taps: 3);
      final backlog = TapBacklog();
      final t0 = DateTime(2026, 11, 10, 12);
      Telegram tg(int i) => Telegram(
        time: t0.add(Duration(milliseconds: i * 40)),
        source: 0x1105,
        destination: i & 0x7FFF,
        type: TelegramType.write,
        data: Uint8List.fromList([1]),
        isSmall: true,
      );
      var forced = 0, out = 0, merged = 0;
      void feed(int tap, Telegram t) {
        final ready = merger.add(tap, t);
        out += ready.length;
        merged += ready.where((r) => r.sightings.length == 2).length;
        if (backlog.note(fed: 1, left: TapBacklog.leaving(ready), pending: merger.pending)) {
          forced++;
          out += merger.flushAll().length;
        }
      }

      // 25 telegrams a second; the third tap point reports two telegrams late, so two or three
      // entries are open at any time and the merger never drains.
      for (var i = 0; i < 20000; i++) {
        feed(0, tg(i));
        feed(1, tg(i));
        if (i >= 2) feed(2, tg(i - 2));
        expect(merger.pending, isTrue);
      }
      expect(forced, 0);
      expect(merged, out);
      expect(out, 20000 - 2);
    });

    test('still releases everything once more than the limit is really held back', () {
      final b = TapBacklog();
      for (var i = 0; i < TapBacklog.max; i++) {
        expect(b.note(fed: 1, left: 0, pending: true), isFalse);
      }
      expect(b.note(fed: 1, left: 0, pending: true), isTrue);
      expect(b.note(fed: 1, left: 0, pending: true), isFalse);
    });
  });
}
