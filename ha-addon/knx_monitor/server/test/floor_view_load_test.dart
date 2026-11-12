import 'dart:io';

import 'package:test/test.dart';

import '../tool/floor_view_bench.dart';

/// The history scan of the bus view under load (issue #7), smaller than the full benchmark
/// (`dart run tool/floor_view_bench.dart`, numbers in docs/performance.md) so it fits into every
/// test run. The thresholds are the Raspberry Pi 4's; with a factor of 2 instead of 10 this still
/// holds on a slow CI machine, and it fails long before the box would notice. Memory is measured
/// by the benchmark only.
void main() {
  test('seven packed days: the scan finds every address, keeps the event loop free, takes in the bus', () async {
    final root = await Directory.systemTemp.createTemp('floor_view_load');
    addTearDown(() => root.delete(recursive: true));
    final now = DateTime(2026, 11, 11, 18);
    final lines = await writeHistory(root, now: now, perDay: 20000, addresses: 120);
    expect(Directory('${root.path}/history').listSync().where((f) => f.path.endsWith('.ndjson.gz')), hasLength(6));
    final b = await measure(root, now: now, lines: lines);
    printOnFailure('$b');
    expect(b.found, 120, reason: 'every address on the plan is on the bus in these days');
    // Memory only in the benchmark's own process: the test runner shares one among its suites.
    expect(overLimits(b, factor: 2, memory: false), isEmpty);
  });
}
