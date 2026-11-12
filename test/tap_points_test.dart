import 'package:flutter_test/flutter_test.dart';

import 'dart:typed_data';

import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/tap_points.dart';

void main() {
  group('TapSilence', () {
    test('a connected tap point that hears nothing counts as silent once the others delivered enough', () {
      final s = TapSilence()..connected(1);
      var changed = false;
      for (var i = 0; i < TapSilence.threshold; i++) {
        expect(s.silent(1), isFalse);
        changed = s.heard(0);
      }
      expect(changed, isTrue, reason: 'the last frame makes it silent');
      expect(s.silent(1), isTrue);
      // One frame at the tap point ends it.
      expect(s.heard(1), isTrue);
      expect(s.silent(1), isFalse);
    });

    test('a tap point that hears telegrams is never silent; after disconnecting it is not judged', () {
      final s = TapSilence()
        ..connected(1)
        ..connected(2);
      for (var i = 0; i < 50; i++) {
        s
          ..heard(0)
          ..heard(1);
      }
      expect(s.silent(1), isFalse);
      expect(s.silent(2), isTrue);
      s.disconnected(2);
      expect(s.silent(2), isFalse);
    });

    test('counting starts afresh on reconnect', () {
      final s = TapSilence()..connected(1);
      for (var i = 0; i < TapSilence.threshold; i++) {
        s.heard(0);
      }
      expect(s.silent(1), isTrue);
      s.connected(1);
      expect(s.silent(1), isFalse);
    });
  });

  group('TapWindowMeter', () {
    final t0 = DateTime(2026, 11, 9, 12);
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

    test('three late pairs widen the late tap point to 1.5 × the largest lag', () {
      var window = const Duration(milliseconds: 100);
      final m = TapWindowMeter(current: (_) => window, auto: {0, 1});
      expect(m.released(tg(0, 0)), isNull);
      expect(m.released(tg(1, 150)), isNull);
      expect(m.released(tg(0, 5000)), isNull);
      expect(m.released(tg(1, 5180)), isNull);
      expect(m.released(tg(0, 10000)), isNull);
      final grown = m.released(tg(1, 10160));
      expect(grown, (1, const Duration(milliseconds: 270)));
      window = grown!.$2;
      // A few smaller lags afterwards change nothing.
      for (var i = 0; i < 3; i++) {
        m.released(tg(0, 20000 + i * 5000));
        expect(m.released(tg(1, 20120 + i * 5000)), isNull);
      }
    });

    test('merged telegrams, the same tap point, long gaps and hand-set windows change nothing', () {
      final m = TapWindowMeter(current: (_) => const Duration(milliseconds: 100), auto: {0});
      for (var i = 0; i < 5; i++) {
        final at = i * 5000;
        expect(m.released(tg(0, at, sightings: [const Sighting(1, Duration(milliseconds: 3), 5)])), isNull);
        expect(m.released(tg(0, at + 1000)), isNull); // cyclic at one tap point
        expect(m.released(tg(1, at + 1150)), isNull); // tap point 1 has its own window
        expect(m.released(tg(0, at + 4000)), isNull);
        expect(m.released(tg(1, at + 4000 + 2500)), isNull); // too far apart: a new telegram
      }
    });

    test('merged telegrams measure the lag and widen ahead of time, before one misses the window', () {
      var window = const Duration(milliseconds: 100);
      final m = TapWindowMeter(current: (_) => window, auto: {0, 1});
      Sighting at(int ms) => Sighting(1, Duration(milliseconds: ms), 5);
      expect(m.lagOf(1), isNull);
      // Around 40 ms across a coupler (measured on 10 Nov): 1.5 × 51 fits into 100 ms.
      for (final ms in [35, 42, 51, 40]) {
        expect(m.released(tg(0, ms * 100, sightings: [at(ms)])), isNull);
      }
      expect(m.lagOf(1), const Duration(milliseconds: 51));
      // Over VPN the lag grows: 80 ms still merges, but leaves no reserve.
      final grown = m.released(tg(0, 9000, sightings: [at(80)]));
      expect(grown, (1, const Duration(milliseconds: 120)));
      window = grown!.$2;
      expect(m.released(tg(0, 9500, sightings: [at(78)])), isNull, reason: 'does not repeat itself');
    });

    test('a window set by hand wins: neither it nor its partner is widened', () {
      // Tap point 1 has a hand-set window, so only 0 may be adjusted.
      final m = TapWindowMeter(current: (_) => const Duration(milliseconds: 100), auto: {0});
      for (var i = 0; i < 6; i++) {
        expect(m.released(tg(0, i * 1000, sightings: [const Sighting(1, Duration(milliseconds: 90), 5)])), isNull);
        // Tap point 0 lags behind 1, which is set by hand.
        expect(m.released(tg(1, i * 1000 + 300, value: 0)), isNull);
        expect(m.released(tg(0, i * 1000 + 480, value: 0)), isNull);
      }
      // The lag is still measured for the display.
      expect(m.lagOf(1), const Duration(milliseconds: 90));
    });

    test('keeps a bounded number of offsets', () {
      final m = TapWindowMeter(current: (_) => const Duration(seconds: 2), auto: {0, 1});
      m.released(tg(0, 0, sightings: [const Sighting(1, Duration(milliseconds: 900), 5)]));
      for (var i = 1; i <= TapWindowMeter.kept; i++) {
        m.released(tg(0, i * 10, sightings: [const Sighting(1, Duration(milliseconds: 5), 5)]));
      }
      expect(m.lagOf(1), const Duration(milliseconds: 5), reason: 'the old outlier has left');
    });
  });

  group('TapBacklog', () {
    test('a merger whose clock went back cannot grow without limit', () {
      // Entries wait for a tap point that never delivers; "now" lies before them, so no window ends.
      final merger = TapMerger(taps: 2);
      final backlog = TapBacklog();
      final t0 = DateTime(2026, 11, 10, 12);
      var out = 0;
      for (var i = 0; i < 5000; i++) {
        final t = Telegram(
          time: t0.subtract(Duration(milliseconds: i)),
          source: 0x1105,
          destination: i,
          type: TelegramType.write,
          data: Uint8List.fromList([1]),
          isSmall: true,
        );
        final ready = merger.add(0, t);
        out += ready.length;
        if (backlog.note(fed: 1, left: TapBacklog.leaving(ready), pending: merger.pending)) {
          out += merger.flushAll().length;
        }
      }
      expect(out, greaterThanOrEqualTo(5000 - TapBacklog.max - 1));
    });
  });

  group('TapGaps', () {
    final t0 = DateTime(2026, 11, 10, 12);
    DateTime at(int s) => t0.add(Duration(seconds: s));
    TapStatus p(int i, {bool up = true, bool paused = false}) => TapStatus(
      index: i,
      name: 'T$i',
      label: '1.${i + 1}',
      state: up ? TunnelState.connected : TunnelState.disconnected,
      paused: paused,
    );

    test('a telegram missing during a gap is not "filtered"; before and after it is', () {
      final g = TapGaps();
      g.update([p(0), p(1)], at(0));
      expect(g.state(1, at(5)), TapSeen.listening);
      g.update([p(0), p(1, up: false)], at(10));
      expect(g.state(1, at(20)), TapSeen.away);
      expect(g.all.single.to, isNull);
      g.update([p(0), p(1)], at(30));
      expect(g.state(1, at(20)), TapSeen.away);
      expect(g.state(1, at(40)), TapSeen.listening);
      expect(g.state(0, at(20)), TapSeen.listening);
      // Right at the edges the merge window and the reconnect blur things: still the gap.
      expect(g.state(1, at(9).add(const Duration(milliseconds: 500))), TapSeen.away);
      expect(g.state(1, at(31).subtract(const Duration(microseconds: 1))), TapSeen.away);
      // The end is exclusive, as the gap lines in the list draw it.
      expect(g.state(1, at(31)), TapSeen.listening);
      expect(g.state(1, at(32)), TapSeen.listening);
      // Before the monitor opened nothing is known.
      expect(g.state(1, at(-60)), TapSeen.unknown);
      expect(g.all.single.to, at(30));
    });

    test('paused is told apart, a tap point that never connected is a gap from the start', () {
      final g = TapGaps();
      g.update([p(0), p(1, up: false), p(2, up: false, paused: true)], at(0));
      expect(g.state(1, at(3)), TapSeen.away);
      expect(g.state(2, at(3)), TapSeen.paused);
    });

    test('seen at one tap point only does not count while every other one was away', () {
      final g = TapGaps();
      g.update([p(0), p(1), p(2)], at(0));
      expect(g.othersListening([0], at(5)), isTrue);
      g.update([p(0), p(1, up: false), p(2)], at(10));
      expect(g.othersListening([0], at(15)), isTrue, reason: 'tap point 2 still listens');
      g.update([p(0), p(1, up: false), p(2, up: false)], at(20));
      expect(g.othersListening([0], at(25)), isFalse);
    });

    test('a single tap point tracks nothing, and the list of gaps stays bounded', () {
      final g = TapGaps();
      g.update([p(0)], at(0));
      expect(g.since, isNull);
      expect(g.state(0, at(1)), TapSeen.unknown);
      for (var i = 0; i < 2 * TapGaps.kept + 10; i++) {
        g.update([p(0), p(1, up: i.isEven)], at(i));
      }
      expect(g.all.length, lessThanOrEqualTo(TapGaps.kept + 1));
      g.update(const [], at(9999));
      expect(g.all, isEmpty);
    });

    test('the filter "at one tap point only" follows the gaps', () {
      tapLabels.value = ['1.1', '1.2'];
      addTearDown(() {
        tapLabels.value = const [];
        tapGaps.update(const [], DateTime.now());
      });
      Telegram one(DateTime time) => Telegram(
        time: time,
        source: 0x1105,
        destination: 0x0A03,
        type: TelegramType.write,
        data: Uint8List.fromList([1]),
        isSmall: true,
      );
      tapGaps.update([p(0), p(1)], at(0));
      expect(seenAtOneTapOnly(one(at(5))), isTrue);
      tapGaps.update([p(0), p(1, up: false)], at(10));
      expect(seenAtOneTapOnly(one(at(15))), isFalse, reason: 'nowhere else to be seen');
      tapGaps.update([p(0), p(1)], at(20));
      expect(seenAtOneTapOnly(one(at(25))), isTrue);
    });
  });

  group('TapLoad', () {
    test('counts per tap point: a forwarded telegram loads every line it reached', () {
      final t0 = DateTime(2026, 11, 10, 12);
      Telegram tg(int s, {int tap = 0, List<Sighting> seen = const [], bool repeated = false}) => Telegram(
        time: t0.add(Duration(seconds: s)),
        source: 0x1105,
        destination: 0x0A03,
        type: TelegramType.write,
        data: Uint8List.fromList([1]),
        isSmall: true,
        repeated: repeated,
        tap: tap,
        sightings: seen,
      );
      const there = [Sighting(1, Duration(milliseconds: 40), 5)];
      final log = [
        tg(-120, seen: there), // older than the span
        tg(10, seen: there),
        tg(20),
        tg(30, tap: 1, repeated: true),
        tg(40, seen: there),
      ];
      final loads = TapLoad.of(log, 2, now: t0.add(const Duration(seconds: 60)));
      expect(loads[0].telegrams, 3);
      expect(loads[1].telegrams, 3);
      expect(loads[0].repeats, 0);
      expect(loads[1].repeats, 1);
      expect(loads[0].perMinute, 3);
      expect(loads[0].percent, closeTo(3 * (50 + 13 * 9 + 28) / 9600 / 60 * 100, 0.001));
      expect(TapLoad.of(const [], 2, now: t0).every((l) => l.telegrams == 0 && l.percent == 0), isTrue);
    });
  });

  group('TapPoint', () {
    test('the same connection counts once: interface and port, or the multicast group', () {
      const a = TapPoint(name: 'A', host: '192.168.1.20');
      expect(a.sameConnection(const TapPoint(name: 'B', host: '192.168.1.20', mode: TapMode.tcp)), isTrue);
      expect(a.sameConnection(const TapPoint(name: 'B', host: '192.168.1.20', port: 3672)), isFalse);
      expect(a.sameConnection(const TapPoint(name: 'B', host: '192.168.1.21')), isFalse);
      const r = TapPoint(name: 'R', host: '', mode: TapMode.routing);
      expect(r.sameConnection(const TapPoint(name: 'R2', host: '224.0.23.12', mode: TapMode.routing)), isTrue);
      expect(r.sameConnection(const TapPoint(name: 'R3', host: '224.0.23.13', mode: TapMode.routing)), isFalse);
      expect(r.sameConnection(a), isFalse);
    });

    test('stored entries are validated: host, port, tunnel address, name length', () {
      expect(TapPoint.fromJson({'mode': 'udp', 'host': '10.0.0.2; rm -rf'}), isNull);
      expect(TapPoint.fromJson({'mode': 'udp', 'host': 'a b'}), isNull);
      final t = TapPoint.fromJson({
        'mode': 'tcp',
        'host': 'knx.example.org',
        'port': 99999,
        'tunnelAddress': -4,
        'name': 'x' * 300,
        'windowMs': 999999,
      })!;
      expect(t.port, 3671);
      expect(t.tunnelAddress, isNull);
      expect(t.name.length, 80);
      expect(t.window, const Duration(seconds: 5));
      expect(lineOfTapLabel('1.2'), 0x12);
      expect(lineOfTapLabel('Routing'), isNull);
      expect(lineOfTapLabel('16.1'), isNull);
    });
  });

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
