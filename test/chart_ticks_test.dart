import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/ui/history_chart.dart';

void main() {
  test('runde Y-Marken', () {
    expect(niceTicks(20.4, 22.7), [21.0, 22.0]);
    expect(niceTicks(20.4, 22.7, count: 5), [20.5, 21.0, 21.5, 22.0, 22.5]);
    expect(niceTicks(0, 100), [0.0, 50.0, 100.0]);
    expect(niceTicks(46.2, 47.4), [46.5, 47.0]);
    expect(niceTicks(5, 5), [5.0]);
  });

  test('Zeitmarken auf runden Uhrzeiten', () {
    final short = timeTicks(DateTime(2026, 10, 21, 21, 50, 26), DateTime(2026, 10, 21, 21, 54, 56), 10);
    expect(short.step, const Duration(seconds: 30));
    expect(short.ticks.first, DateTime(2026, 10, 21, 21, 50, 30));
    expect(formatTick(short.ticks.first, short.step), '21:50:30');

    final day = timeTicks(DateTime(2026, 10, 26, 17, 12), DateTime(2026, 10, 27, 17, 12), 5);
    expect(day.step, const Duration(hours: 6));
    expect(day.ticks.first, DateTime(2026, 10, 26, 18));
    expect(formatTick(day.ticks.first, day.step), '18:00');
  });

  test('über die Zeitumstellung: Tage auf Mitternacht', () {
    final week = timeTicks(DateTime(2026, 10, 20, 17), DateTime(2026, 10, 27, 17), 8);
    expect(week.step, const Duration(days: 1));
    expect(week.ticks, [for (var d = 21; d <= 27; d++) DateTime(2026, 10, d)]);
  });
}
