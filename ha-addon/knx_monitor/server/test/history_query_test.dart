import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

void main() {
  late Directory data;
  late Recorder recorder;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  setUp(() {
    data = Directory.systemTemp.createTempSync('history_query');
    Directory('${data.path}/history').createSync();
    recorder = Recorder(data);
  });
  tearDown(() => data.deleteSync(recursive: true));

  Map<String, Object?> line(DateTime t, int d, String x, {int y = 2, bool small = false}) => {
    't': t.microsecondsSinceEpoch,
    's': 4402,
    'd': d,
    'y': y,
    'x': x,
    if (small) 'm': true,
  };

  void write(List<Map<String, Object?>> lines) {
    for (final l in lines) {
      final day = Recorder.dayName(DateTime.fromMicrosecondsSinceEpoch(l['t']! as int));
      File('${data.path}/history/$day.ndjson').writeAsStringSync('${jsonEncode(l)}\n', mode: FileMode.append);
    }
  }

  test('only the asked addresses, the value before the period first, no reads', () async {
    final from = today.subtract(const Duration(days: 2));
    write([
      line(from.subtract(const Duration(hours: 5)), 100, '00', small: true),
      line(from.subtract(const Duration(hours: 1)), 100, '01', small: true), // value at the edge
      line(from.add(const Duration(hours: 1)), 100, '00', small: true),
      line(from.add(const Duration(hours: 2)), 100, '', y: 0), // read
      line(from.add(const Duration(hours: 3)), 200, '0C1A'), // other address
    ]);
    final result = await historyTelegrams(recorder, {100: (1, 1)}, from, now);
    expect(result.keys, [100]);
    expect(result[100]!.map((l) => l['x']), ['01', '00']);
  });

  test('the value at the edge also comes from days further back', () async {
    final from = today.subtract(const Duration(days: 1));
    write([
      line(today.subtract(const Duration(days: 5)), 300, '01', small: true), // last value, five days back
      line(today.subtract(const Duration(days: 6)), 300, '00', small: true),
      line(from.add(const Duration(hours: 2)), 300, '00', small: true),
    ]);
    final result = await historyTelegrams(recorder, {300: (1, 1)}, from, now);
    expect(result[300]!.map((l) => l['x']), ['01', '00']);
  });

  test('thinning keeps changes and peaks', () {
    final start = today.microsecondsSinceEpoch;
    final hour = const Duration(hours: 1).inMicroseconds;
    // A switch: long runs of the same value with few changes.
    final switching = [
      for (var i = 0; i < 1000; i++)
        line(DateTime.fromMicrosecondsSinceEpoch(start + i * 1000000), 1, i < 600 ? '00' : '01'),
    ];
    final thinned = thinLines(switching, (1, 1), start, start + hour, 100);
    expect(thinned.map((l) => l['x']).toSet(), {'00', '01'});
    expect(thinned.length, lessThanOrEqualTo(6));
    final change = thinned.indexWhere((l) => l['x'] == '01');
    expect(thinned[change]['t'], start + 600 * 1000000, reason: 'the change stays at its time');

    // A measured value (DPT 9) with one spike among noise.
    String dpt9(double v) => hexOf(encodeDpt9(v)!);
    final noisy = [
      for (var i = 0; i < 5000; i++)
        line(DateTime.fromMicrosecondsSinceEpoch(start + i * 700000), 2, dpt9(i == 2500 ? 99 : 20 + (i % 7) / 10)),
    ];
    final few = thinLines(noisy, (9, 1), start, start + hour, 400);
    expect(few.length, lessThanOrEqualTo(400));
    expect(few.any((l) => l['x'] == dpt9(99)), isTrue, reason: 'the peak stays');
    expect(few.first, noisy.first);
    expect(few.last, noisy.last);
  });

  test('a longer period with the same data is thinned the same', () {
    final start = today.microsecondsSinceEpoch;
    String dpt9(double v) => hexOf(encodeDpt9(v)!);
    final week = [
      for (var i = 0; i < 20000; i++)
        line(DateTime.fromMicrosecondsSinceEpoch(start + i * 30000000), 2, dpt9(20 + (i % 13) / 10)),
    ];
    final end = start + 20000 * 30000000;
    final seven = thinLines(week, (9, 1), end - const Duration(days: 7).inMicroseconds, end, 4000);
    final thirty = thinLines(week, (9, 1), end - const Duration(days: 30).inMicroseconds, end, 4000);
    expect(thirty.length, seven.length);
  });

  test('parameters', () {
    String? error;
    final q = historyQuery({'a': '100:1.1,200', 'from': '0', 'to': '1000'})!;
    expect(q.addresses, {100: (1, 1), 200: null});
    expect(historyQuery({'a': 'x', 'from': '0', 'to': '1'}, onError: (e) => error = e), isNull);
    expect(error, contains('Adresse'));
    expect(historyQuery({'a': '1', 'from': '0', 'to': '${const Duration(days: 40).inMilliseconds}'}), isNull);
    expect(historyQuery({'from': '0', 'to': '1'}), isNull);
  });

  test('packed days are cached per address and read again after a rewrite', () async {
    final day = today.subtract(const Duration(days: 3));
    final name = Recorder.dayName(day);
    void pack(List<Map<String, Object?>> lines) {
      final text = lines.map(jsonEncode).join('\n');
      File('${data.path}/history/$name.ndjson.gz').writeAsBytesSync(gzip.encode(utf8.encode('$text\n')));
    }

    pack([
      line(day.add(const Duration(hours: 1)), 100, '01', small: true),
      line(day.add(const Duration(hours: 2)), 200, '0C1A'),
    ]);
    final cache = DayLinesCache();
    expect((await cache.lines(recorder, name, {100}))![100], hasLength(1));
    // Another address of the same day is read on demand, the first stays.
    final both = (await cache.lines(recorder, name, {100, 200}))!;
    expect([both[100]!.length, both[200]!.length], [1, 1]);
    // Concurrent requests share one read and see the same lines.
    final results = await Future.wait([
      for (var i = 0; i < 5; i++) cache.lines(recorder, name, {100, 200}),
    ]);
    expect(results.map((r) => r![200]!.length), everyElement(1));
    // Rewritten (e.g. a correction): the stamp changes, the day is read anew.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    pack([
      line(day.add(const Duration(hours: 1)), 100, '01', small: true),
      line(day.add(const Duration(hours: 3)), 100, '00', small: true),
      line(day.add(const Duration(hours: 4)), 100, '01', small: true),
    ]);
    expect((await cache.lines(recorder, name, {100}))![100], hasLength(3));
    // An open day is never cached.
    write([line(today.add(const Duration(minutes: 1)), 100, '01', small: true)]);
    final open = Recorder.dayName(today);
    expect((await cache.lines(recorder, open, {100}))![100], hasLength(1));
    write([line(today.add(const Duration(minutes: 2)), 100, '00', small: true)]);
    expect((await cache.lines(recorder, open, {100}))![100], hasLength(2));
  });

  test('statistics of packed days are counted once and again after a rewrite', () async {
    final day = today.subtract(const Duration(days: 2));
    final name = Recorder.dayName(day);
    void pack(int n) {
      final text = [for (var i = 0; i < n; i++) jsonEncode(line(day.add(Duration(minutes: i)), 100, '01', small: true))]
          .join('\n');
      File('${data.path}/history/$name.ndjson.gz').writeAsBytesSync(gzip.encode(utf8.encode('$text\n')));
    }

    pack(3);
    final runs = await Future.wait([for (var i = 0; i < 3; i++) recorder.stats(5)]);
    expect(runs.map((r) => (r['perDay']! as Map)[name]), everyElement(3));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    pack(5);
    final again = await recorder.stats(5);
    expect((again['perDay']! as Map)[name], 5);
    expect(again['total'], 5);
    expect((again['groups']! as List).first, [100, 5]);
  });
}
