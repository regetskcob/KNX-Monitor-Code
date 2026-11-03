import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/model/activity_range.dart';

void main() {
  test('Minutenzähler: letzte Stunde und heute in Viertelstunden', () {
    final c = MinuteCounter();
    final now = DateTime(2026, 10, 15, 9, 30, 20);
    c
      ..add(DateTime(2026, 10, 15, 9, 30, 5))
      ..add(DateTime(2026, 10, 15, 9, 30, 10), alarm: true)
      ..add(DateTime(2026, 10, 15, 9, 0, 0))
      ..add(DateTime(2026, 10, 15, 0, 14, 59))
      ..add(DateTime(2026, 10, 14, 23, 50)); // gestern, nur in „letzte Stunde“ bis 0:50 sichtbar

    final hour = c.hour(now);
    expect(hour, hasLength(60));
    expect(hour.last, 2);
    expect(hour[59 - 30], 1); // 9:00
    expect(c.hour(now, alarms: true).last, 1);

    final today = c.today(now);
    expect(today, hasLength(96));
    expect(today[0], 1); // 0:00–0:15
    expect(today[36], 1); // 9:00–9:15
    expect(today[38], 2); // 9:30–9:45
    expect(today.fold(0, (a, b) => a + b), 4); // gestern zählt nicht

    c.prune(now);
    expect(c.hour(DateTime(2026, 10, 15, 0, 30)).fold(0, (a, b) => a + b), 2); // 23:50 von gestern + 0:14
  });

  test('Ø je Minute nur über die erfasste Zeit', () {
    final c = MinuteCounter();
    final start = DateTime(2026, 10, 15, 9);
    for (var i = 0; i < 30; i++) {
      c.add(start.add(Duration(minutes: i)));
    }
    final now = start.add(const Duration(minutes: 30));
    // Erst seit 9:00 erfasst: 30 Telegramme / 30 min, nicht / 60 min.
    expect(c.perMinute(now, now.subtract(const Duration(hours: 1)), coveredSince: start), closeTo(1, 0.01));
    expect(c.perMinute(now, DateTime(2026, 10, 15), coveredSince: start), closeTo(1, 0.01));
  });
}
