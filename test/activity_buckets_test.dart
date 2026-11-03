import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/ui/heatmap.dart';

void main() {
  test('Aktivität bleibt über Wochen in zeitlicher Reihenfolge', () {
    final start = DateTime(2026, 10, 1, 12);
    final times = [start, for (var i = 0; i < 3; i++) start.add(const Duration(days: 20))];
    final bars = activityBuckets(times, 16);
    expect(bars.first, 1);
    expect(bars.last, 3);
    expect(activityBuckets(const [], 16), isEmpty);
  });
}
