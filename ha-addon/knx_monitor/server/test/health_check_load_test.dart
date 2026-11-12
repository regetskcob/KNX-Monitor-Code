import 'dart:io';

import 'package:test/test.dart';

import '../tool/floor_view_bench.dart' show writeHistory;
import '../tool/health_check_bench.dart';

/// The server's health check under load (issue #12): two days of a very full bus, yesterday
/// packed, as `dart run tool/health_check_bench.dart` measures it. The thresholds are the
/// Raspberry Pi 4's of the bus view (floor_view_bench.dart); with a factor of 2 instead of 10
/// this still holds on a slow CI machine. Memory is measured by the benchmark only: the test
/// runner shares one process among its suites.
void main() {
  test('two days of 100,000 telegrams: one run in bounded time, the event loop stays free', () async {
    final root = await Directory.systemTemp.createTemp('health_check_load');
    addTearDown(() => root.delete(recursive: true));
    final now = DateTime(2026, 11, 11, 18);
    await writeHistory(root, now: now, days: 2, perDay: 100000);
    await writeProject(root);
    final b = await measureHealth(root, now: now);
    printOnFailure('run ${b.run}, event loop ${b.maxStall}, memory +${b.rssExtra}');
    expect(b.result['telegrams'], 200000);
    expect(b.result['days'], 2);
    // Half of the telegrams have the wrong length for their address: far more pairs of address
    // and sender than a result may carry. The bounds hold and say so.
    expect(b.result['truncated'], isTrue);
    expect(b.result['findings'], hasLength(200));
    expect(b.result['status'], 'faults');
    expect(healthOverLimits(b, factor: 2, memory: false), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
