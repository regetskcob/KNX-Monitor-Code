import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/bus_metrics.dart';

void main() {
  final t0 = DateTime(2026, 10, 27, 12);
  Telegram at(int seconds, {int source = 0x1105, bool repeated = false}) => Telegram(
    time: t0.add(Duration(seconds: seconds)),
    source: source,
    destination: 0x0A01,
    type: TelegramType.write,
    data: Uint8List.fromList([1]),
    isSmall: true,
    repeated: repeated,
  );

  test('Ids: Gruppenadressen sind keine Kennzahl, Linien kommen zurück', () {
    expect(BusMetric.of(0x0A01), isNull);
    expect(BusMetric.of(-1), BusMetric.telegrams);
    expect(BusMetric.of(-2), BusMetric.repeats);
    final line = BusMetric.line(0x11);
    expect(BusMetric.of(line.id)!.line, 0x11);
    expect(BusMetric.lineLabel(0x11), '1.1');
    expect(BusMetric.of(-3), BusMetric.load);
    expect(BusMetric.load.key, 'load');
    expect(BusMetric.load.unit, '%');
    expect(BusMetric.repeats.unit, '/min');
    expect(BusMetric.of(-4), isNull);
  });

  test('je Minute: gesamt, wiederholt, je Linie; leere Minuten zählen 0', () {
    final log = [at(1), at(2, repeated: true), at(3, source: 0x1201), at(150)];
    final now = t0.add(const Duration(minutes: 3));
    List<double> values(BusMetric m) => [for (final (_, v) in m.rates(log, now: now)) v];
    expect(values(BusMetric.telegrams), [3, 0, 1, 0]);
    expect(values(BusMetric.repeats), [1, 0, 0, 0]);
    expect(values(BusMetric.line(0x11)), [2, 0, 1, 0]);
  });

  test('höchstens so viele Spalten wie erlaubt, auch bei glatten Grenzen', () {
    for (final minutes in [399, 400, 401, 799, 800, 1440]) {
      final log = [at(0), at(minutes * 60)];
      final rates = BusMetric.telegrams.rates(log, now: t0.add(Duration(minutes: minutes)));
      expect(rates.length, lessThanOrEqualTo(400), reason: '$minutes min');
    }
  });

  test('Buslast: Belegungszeit der Leitung in Prozent, wie auf dem Server', () {
    // Small telegrams (1 bit): (50 + 13 × 9 + 28) bits at 9600 bit/s = 20.3 ms each.
    final log = [for (var i = 0; i < 30; i++) at(i * 2), at(119)];
    final rates = BusMetric.load.rates(log, now: t0.add(const Duration(minutes: 2)));
    expect(rates.first.$2, closeTo(30 * 195 / 9600 / 60 * 100, 0.001));
    expect(rates.first.$2, closeTo(1.016, 0.01));
  });
}
