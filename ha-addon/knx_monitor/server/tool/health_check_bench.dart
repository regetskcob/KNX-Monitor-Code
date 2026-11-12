// Load test of the server's health check (issue #12, `ServerHealthCheck.run`): it reads the
// history of today and yesterday in a separate isolate.
//
//   dart run tool/health_check_bench.dart                    # 2 days × 100,000 telegrams, JIT
//   dart run tool/health_check_bench.dart --per-day 400000
//
// It writes a synthetic history in the box's layout (yesterday packed, today plain, see
// floor_view_bench.dart) and a project with a datapoint type for each of its 2,000 addresses,
// some of them wrong on purpose, then measures one run: how long it takes, the longest stall
// of the event loop (a timer every 5 ms) and the peak resident memory above the start. Exits
// with 1 if a threshold of floor_view_bench.dart is exceeded.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:knx_monitor_server/bus.dart';

import 'floor_view_bench.dart' show extraRssLimit, piFactor, piScan, piStall, writeHistory;

/// What one run measured.
typedef HealthBench = ({Duration run, Duration maxStall, int rssExtra, Map<String, Object?> result});

/// A project for the addresses of [writeHistory]: switches, temperatures, percentages and some
/// without a type. The history sends 1 bit or 2 bytes at random, so many lengths are wrong.
Future<void> writeProject(Directory root) => File('${root.path}/catalog.json').writeAsString(
  jsonEncode({
    'groups': [
      for (var i = 0; i < 2000; i++)
        {
          'a': 0x0800 + i,
          'n': 'Adresse $i',
          if (i % 4 != 3)
            'd': switch (i % 4) {
              0 => [1, 1],
              1 => [9, 1],
              _ => [5, 1],
            },
        },
    ],
    'devices': [
      for (var i = 0; i < 250; i++) {'a': 0x1100 + i, 'n': 'Gerät $i'},
    ],
  }),
);

/// One run of the health check over the history in [root], measured.
Future<HealthBench> measureHealth(Directory root, {required DateTime now}) async {
  final bus = BusService(root, describe: (_, _) async => null);
  await bus.start();
  final cycles = CycleWatch(() => bus, clock: () => now);
  // As on a running server: the hourly "stopped sending" check has read the history already;
  // the health check takes its result.
  await cycles.check();
  final check = ServerHealthCheck(() => bus, enabled: true, cycles: cycles, clock: () => now);
  final rssBase = ProcessInfo.currentRss;
  var rssPeak = rssBase;
  var maxStall = 0;
  const tick = Duration(milliseconds: 5);
  var last = Stopwatch()..start();
  final timer = Timer.periodic(tick, (_) {
    maxStall = max(maxStall, last.elapsedMicroseconds - tick.inMicroseconds);
    last = Stopwatch()..start();
    rssPeak = max(rssPeak, ProcessInfo.currentRss);
  });
  final watch = Stopwatch()..start();
  final result = await check.run();
  watch.stop();
  timer.cancel();
  await bus.shutdown();
  return (
    run: watch.elapsed,
    maxStall: Duration(microseconds: maxStall),
    rssExtra: max(0, rssPeak - rssBase),
    result: result,
  );
}

/// Thresholds of the Raspberry Pi 4 (floor_view_bench.dart) that [b] exceeds when the machine
/// is [factor] times faster.
List<String> healthOverLimits(HealthBench b, {int factor = piFactor, bool memory = true}) => [
  if (b.run * factor > piScan) 'run ${b.run.inMilliseconds} ms × $factor > ${piScan.inSeconds} s',
  if (b.maxStall * factor > piStall)
    'event loop ${b.maxStall.inMilliseconds} ms × $factor > ${piStall.inMilliseconds} ms',
  if (memory && b.rssExtra > extraRssLimit)
    'memory +${b.rssExtra ~/ 1024 ~/ 1024} MB > ${extraRssLimit ~/ 1024 ~/ 1024} MB',
];

Future<void> main(List<String> args) async {
  final i = args.indexOf('--per-day');
  final perDay = i >= 0 && i + 1 < args.length ? int.parse(args[i + 1]) : 100000;
  final now = DateTime(2026, 11, 11, 18);
  final root = await Directory.systemTemp.createTemp('health_check_bench');
  try {
    await writeHistory(root, now: now, days: 2, perDay: perDay);
    await writeProject(root);
    final b = await measureHealth(root, now: now);
    final over = healthOverLimits(b);
    stdout.writeln(
      '${b.result['telegrams']} telegrams, ${(b.result['counts']! as Map)['total']} findings: '
      'run ${b.run.inMilliseconds} ms, event loop ${b.maxStall.inMilliseconds} ms, '
      'memory +${b.rssExtra ~/ 1024 ~/ 1024} MB${over.isEmpty ? '' : ' | OVER: ${over.join('; ')}'}',
    );
    if (over.isNotEmpty) exitCode = 1;
  } finally {
    await root.delete(recursive: true);
  }
}
