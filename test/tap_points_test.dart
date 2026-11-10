import 'package:flutter_test/flutter_test.dart';

import 'dart:typed_data';

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
      // Smaller lags afterwards do not narrow it.
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
  });
}
