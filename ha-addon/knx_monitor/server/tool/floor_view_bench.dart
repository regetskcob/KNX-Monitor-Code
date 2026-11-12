// Load test of the history scan behind the bus view on the floor plan (issue #7,
// `FloorViewService._seed`): on the first request it reads up to seven days of history.
//
//   dart run tool/floor_view_bench.dart                 # 7 days × 100,000 telegrams, JIT
//   dart compile exe tool/floor_view_bench.dart -o /tmp/fvb && /tmp/fvb   # AOT, as on the box
//   dart run tool/floor_view_bench.dart --per-day 400000 --addresses 600
//
// It writes a synthetic history in the box's layout (finished days packed as `.ndjson.gz`, today
// as plain `.ndjson`, lines as the recorder writes them, raw frame included), then measures in a
// fresh process: how long the scan takes until the answer no longer says `loading`, the peak
// resident memory above the start, the longest stall of the event loop (a timer every 5 ms) and
// whether telegrams fed meanwhile (50 per second, as `observe` and the recorder get them) are
// taken in on time. Results and thresholds: docs/performance.md. Exits with 1 if a threshold
// is exceeded.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:knx_monitor_server/bus.dart';

/// What one run measured.
class FloorViewBench {
  FloorViewBench({
    required this.lines,
    required this.scan,
    required this.rssBase,
    required this.rssPeak,
    required this.maxStall,
    required this.p99Stall,
    required this.fed,
    required this.lateFeeds,
    required this.maxRequest,
    required this.found,
  });

  /// History lines on disk.
  final int lines;

  /// First request until the answer no longer says `loading`.
  final Duration scan;

  /// Resident memory before the scan and the most seen during it, in bytes.
  final int rssBase;
  final int rssPeak;

  /// Longest and 99th-percentile lateness of a 5 ms timer during the scan: how long the event
  /// loop (bus, WebSocket, HTTP) had to wait.
  final Duration maxStall;
  final Duration p99Stall;

  /// Telegrams fed during the scan, and those taken in more than 100 ms late.
  final int fed;
  final int lateFeeds;

  /// Slowest answer to `GET /api/floor-view` during the scan.
  final Duration maxRequest;

  /// Addresses on the plan the scan found a time for.
  final int found;

  int get rssExtra => max(0, rssPeak - rssBase);

  Map<String, Object?> toJson() => {
    'lines': lines,
    'scanMs': scan.inMilliseconds,
    'rssBase': rssBase,
    'rssPeak': rssPeak,
    'maxStallUs': maxStall.inMicroseconds,
    'p99StallUs': p99Stall.inMicroseconds,
    'fed': fed,
    'lateFeeds': lateFeeds,
    'maxRequestUs': maxRequest.inMicroseconds,
    'found': found,
  };

  factory FloorViewBench.fromJson(Map<String, Object?> j) => FloorViewBench(
    lines: j['lines']! as int,
    scan: Duration(milliseconds: j['scanMs']! as int),
    rssBase: j['rssBase']! as int,
    rssPeak: j['rssPeak']! as int,
    maxStall: Duration(microseconds: j['maxStallUs']! as int),
    p99Stall: Duration(microseconds: j['p99StallUs']! as int),
    fed: j['fed']! as int,
    lateFeeds: j['lateFeeds']! as int,
    maxRequest: Duration(microseconds: j['maxRequestUs']! as int),
    found: j['found']! as int,
  );

  @override
  String toString() {
    String ms(Duration d) => (d.inMicroseconds / 1000).toStringAsFixed(1);
    String mb(int b) => (b / 1024 / 1024).toStringAsFixed(1);
    return '$lines lines | scan ${ms(scan)} ms | RSS +${mb(rssExtra)} MB (peak ${mb(rssPeak)} MB) | '
        'event loop max ${ms(maxStall)} ms, p99 ${ms(p99Stall)} ms | fed $fed, late $lateFeeds | '
        'slowest request ${ms(maxRequest)} ms | found $found';
  }
}

/// Group addresses on the synthetic plan: [count] of the 2,000 addresses in the history, spread.
List<int> planAddresses(int count) => [for (var i = 0; i < count; i++) 0x0800 + (i * 7) % 2000];

/// Writes [days] days of [perDay] telegrams each up to [now] into `root/history`, as on the box,
/// and a plan `floor_view.json` with [addresses] addresses (12 per point, as the app's limit).
Future<int> writeHistory(
  Directory root, {
  required DateTime now,
  int days = 7,
  int perDay = 100000,
  int addresses = 200,
  int seed = 7,
}) async {
  final history = Directory('${root.path}/history')..createSync(recursive: true);
  final random = Random(seed);
  var total = 0;
  for (var back = 0; back < days; back++) {
    final day = DateTime(now.year, now.month, now.day - back);
    final name = Recorder.dayName(day);
    final packed = back > 0;
    final file = File('${history.path}/$name.ndjson${packed ? '.gz' : ''}');
    final sink = file.openWrite();
    // Spread over the day; today only up to [now].
    final end = back == 0 ? now : day.add(const Duration(days: 1));
    final span = end.difference(day).inMicroseconds;
    final buffer = StringBuffer();
    final chunk = <int>[];
    Future<void> flush() async {
      final bytes = utf8.encode(buffer.toString());
      buffer.clear();
      if (packed) {
        chunk.addAll(bytes);
      } else {
        sink.add(bytes);
      }
    }

    for (var i = 0; i < perDay; i++) {
      final t = day.microsecondsSinceEpoch + span * i ~/ perDay;
      // 2,000 addresses, a few of them much busier (cyclic sensors), as on a real bus.
      final d = 0x0800 + (random.nextDouble() < 0.3 ? random.nextInt(40) : random.nextInt(2000));
      final s = 0x1100 + random.nextInt(250);
      final type = random.nextInt(10) == 0 ? 0 : 2;
      final small = random.nextBool();
      final x = small ? '0${random.nextInt(2)}' : '0c${random.nextInt(256).toRadixString(16).padLeft(2, '0')}';
      final raw =
          '2900bce0${s.toRadixString(16).padLeft(4, '0')}${d.toRadixString(16).padLeft(4, '0')}0${small ? 1 : 3}00${small ? '8$x' : '80$x'}';
      buffer.writeln(jsonEncode({'t': t, 's': s, 'd': d, 'y': type, 'x': x, if (small) 'm': true, 'r': raw}));
      if (i % 5000 == 4999) await flush();
    }
    await flush();
    if (packed) sink.add(gzip.encode(chunk));
    await sink.close();
    total += perDay;
  }
  final plan = planAddresses(addresses);
  await File('${root.path}/${FloorViewService.fileName}').writeAsString(
    jsonEncode({
      'format': FloorViewService.format,
      'version': 1,
      'floors': [
        {
          'id': 'f1',
          'name': 'EG',
          'points': [
            for (var p = 0; p * 12 < plan.length; p++)
              {
                'id': 'p$p',
                'name': 'Punkt $p',
                'x': 0.5,
                'y': 0.5,
                'addresses': plan.sublist(p * 12, min(plan.length, p * 12 + 12)),
              },
          ],
        },
      ],
    }),
  );
  return total;
}

/// Runs the scan once against the history in [root] and measures it (see the top of the file).
Future<FloorViewBench> measure(Directory root, {required DateTime now, required int lines}) async {
  final recorder = Recorder(root, clock: () => now);
  final service = FloorViewService(now: () => now);
  final rssBase = ProcessInfo.currentRss;
  var rssPeak = rssBase;
  final stalls = <int>[];
  var fed = 0, late = 0;
  var maxRequest = Duration.zero;
  const tick = Duration(milliseconds: 5);
  var last = Stopwatch()..start();
  // The bus meanwhile: 50 telegrams per second, each where the server puts it.
  final feedClock = Stopwatch()..start();
  var nextFeed = 0;
  final timer = Timer.periodic(tick, (_) {
    final elapsed = last.elapsedMicroseconds;
    last = Stopwatch()..start();
    stalls.add(max(0, elapsed - tick.inMicroseconds));
    rssPeak = max(rssPeak, ProcessInfo.currentRss);
    while (feedClock.elapsedMilliseconds >= nextFeed) {
      if (feedClock.elapsedMilliseconds - nextFeed > 100) late++;
      final line = {'t': now.microsecondsSinceEpoch, 's': 0x1105, 'd': 0x0900 + fed % 50, 'y': 2, 'x': '01', 'm': true};
      recorder.add(line);
      service.observe(line, root: root.path);
      fed++;
      nextFeed += 20;
    }
  });
  final scan = Stopwatch()..start();
  Map<String, Object?> answer;
  do {
    final request = Stopwatch()..start();
    answer = await service.describe(root, recorder);
    if (request.elapsed > maxRequest) maxRequest = request.elapsed;
    // As the card polls, but often enough to see the end.
    if (answer['loading'] == true) await Future<void>.delayed(const Duration(milliseconds: 20));
  } while (answer['loading'] == true);
  scan.stop();
  timer.cancel();
  await recorder.flush();
  stalls.sort();
  return FloorViewBench(
    lines: lines,
    scan: scan.elapsed,
    rssBase: rssBase,
    rssPeak: rssPeak,
    maxStall: Duration(microseconds: stalls.isEmpty ? 0 : stalls.last),
    p99Stall: Duration(
      microseconds: stalls.isEmpty ? 0 : stalls[(stalls.length * 0.99).floor().clamp(0, stalls.length - 1)],
    ),
    fed: fed,
    lateFeeds: late,
    maxRequest: maxRequest,
    found: (answer['last']! as Map).length,
  );
}

/// Thresholds for a Raspberry Pi 4, measured here on a Mac and divided by [piFactor]
/// (docs/performance.md says why).
const piFactor = 10;

/// On the Pi: the scan ends within 30 s (the card shows live data meanwhile), the event loop never
/// waits longer than 250 ms (a tunnel acknowledges within 1 s, the gateway gives up after that),
/// and the scan needs at most 64 MB on top (the add-on shares the Pi with Home Assistant).
const piScan = Duration(seconds: 30);
const piStall = Duration(milliseconds: 250);
const extraRssLimit = 64 * 1024 * 1024;

/// What exceeds the thresholds, empty if nothing. [memory] only counts in a process of its own:
/// the test runner shares one among its suites.
List<String> overLimits(FloorViewBench b, {int factor = piFactor, bool memory = true}) => [
  if (b.scan * factor > piScan) 'scan ${b.scan.inMilliseconds} ms × $factor > ${piScan.inSeconds} s',
  if (b.maxStall * factor > piStall)
    'event loop ${b.maxStall.inMilliseconds} ms × $factor > ${piStall.inMilliseconds} ms',
  if (memory && b.rssExtra > extraRssLimit)
    'memory +${b.rssExtra ~/ 1024 ~/ 1024} MB > ${extraRssLimit ~/ 1024 ~/ 1024} MB',
  if (b.lateFeeds > 0) '${b.lateFeeds} telegrams taken in late',
];

Future<void> main(List<String> args) async {
  String? option(String name) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final now = DateTime(2026, 11, 11, 18);
  final measureDir = option('measure');
  if (measureDir != null) {
    // Child process: only the scan, so generating the history does not count for the memory.
    final b = await measure(Directory(measureDir), now: now, lines: int.parse(option('lines')!));
    stdout.writeln(jsonEncode(b.toJson()));
    return;
  }
  final days = int.parse(option('days') ?? '7');
  final perDay = int.parse(option('per-day') ?? '100000');
  final addresses = int.parse(option('addresses') ?? '200');
  final runs = int.parse(option('runs') ?? '3');
  final root = await Directory.systemTemp.createTemp('floor_view_bench');
  try {
    final generate = Stopwatch()..start();
    final lines = await writeHistory(root, now: now, days: days, perDay: perDay, addresses: addresses);
    var bytes = 0;
    for (final f in Directory('${root.path}/history').listSync().whereType<File>()) {
      bytes += f.lengthSync();
    }
    stdout.writeln(
      'History: $days days × $perDay telegrams, ${(bytes / 1024 / 1024).toStringAsFixed(1)} MB on disk, '
      '$addresses addresses on the plan (written in ${generate.elapsed.inSeconds} s)',
    );
    // A compiled executable runs itself again; `dart run` the script.
    final script = Platform.script.toFilePath();
    final self = script.endsWith('.dart')
        ? [Platform.resolvedExecutable, 'run', script]
        : [Platform.resolvedExecutable];
    var failed = false;
    for (var run = 1; run <= runs; run++) {
      final result = await Process.run(self.first, [...self.skip(1), '--measure', root.path, '--lines', '$lines']);
      if (result.exitCode != 0) {
        stderr.write(result.stderr);
        exitCode = 2;
        return;
      }
      final b = FloorViewBench.fromJson(
        jsonDecode((result.stdout as String).trim().split('\n').last) as Map<String, Object?>,
      );
      final over = overLimits(b);
      stdout.writeln('Run $run: $b${over.isEmpty ? '' : ' | OVER: ${over.join('; ')}'}');
      failed |= over.isNotEmpty;
    }
    stdout.writeln(
      'Thresholds (Pi 4 = Mac × $piFactor): scan ≤ ${piScan.inSeconds} s, event loop ≤ ${piStall.inMilliseconds} ms, '
      'memory ≤ +${extraRssLimit ~/ 1024 ~/ 1024} MB, no telegram late',
    );
    if (failed) exitCode = 1;
  } finally {
    await root.delete(recursive: true);
  }
}
