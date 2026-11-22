import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

// What a full disk, a broken file or a power cut must not do: stop the server
// at start, keep the cleanup from running, swallow telegrams or double them.
void main() {
  late Directory data;
  late Directory history;

  setUp(() {
    data = Directory.systemTemp.createTempSync('robust');
    history = Directory('${data.path}/history')..createSync();
  });
  tearDown(() => data.deleteSync(recursive: true));

  List<String> names() => [for (final f in history.listSync()) f.uri.pathSegments.last]..sort();
  String day(int back) => Recorder.dayName(DateTime.now().subtract(Duration(days: back)));
  File file(String name, [String text = '{"t":1}\n']) => File('${history.path}/$name')..writeAsStringSync(text);
  Map<String, Object?> line(DateTime t, [int d = 1]) => {'t': t.microsecondsSinceEpoch, 'd': d};

  group('start with a day that cannot be packed', () {
    test('a broken .gz next to the plain file: start completes, the rest is still cleaned up', () async {
      file('${day(2)}.ndjson');
      File('${history.path}/${day(2)}.ndjson.gz').writeAsBytesSync([1, 2, 3, 4]);
      file('${day(1)}.ndjson');
      file('${day(30)}.ndjson');
      final recorder = Recorder(data);
      await recorder.start();
      // The broken day stays as it is, nothing half-written is left behind.
      expect(names(), contains('${day(2)}.ndjson'));
      expect(names().where((n) => n.endsWith('.tmp')), isEmpty);
      // The day after it was packed, the expired one is gone.
      expect(names(), contains('${day(1)}.ndjson.gz'));
      expect(names(), isNot(contains('${day(30)}.ndjson')));
      expect(names(), isNot(contains('${day(30)}.ndjson.gz')));
    });

    test('a history folder that cannot be created does not throw', () async {
      history.deleteSync(recursive: true);
      File('${data.path}/history').writeAsStringSync('not a folder');
      await Recorder(data).start();
    });

    test('the hourly run goes on after a failed day too', () async {
      final recorder = Recorder(data);
      await recorder.start();
      file('${day(2)}.ndjson');
      File('${history.path}/${day(2)}.ndjson.gz').writeAsBytesSync([1, 2, 3, 4]);
      file('${day(30)}.ndjson');
      await recorder.maintain();
      expect(names(), isNot(contains('${day(30)}.ndjson')));
      expect(names(), isNot(contains('${day(30)}.ndjson.gz')));
    });
  });

  group('retention nobody confirmed', () {
    test('keepExpired: nothing goes by age, the size limit still applies', () async {
      file('${day(30)}.ndjson');
      var keep = true;
      final recorder = Recorder(data)..keepExpired = (() => keep);
      await recorder.start();
      expect(names(), ['${day(30)}.ndjson.gz']);
      keep = false;
      await recorder.maintain();
      expect(names(), isEmpty);
    });

    test('keepExpired: "off" deletes nothing either', () async {
      file('${day(1)}.ndjson');
      final recorder = Recorder(data, retentionDays: 0)..keepExpired = (() => true);
      await recorder.start();
      expect(names(), isNotEmpty);
    });
  });

  test('a last line without line break does not swallow the first new telegram', () async {
    final now = DateTime.now();
    final today = file('${Recorder.dayName(now)}.ndjson', '{"t":1,"d":7}\n{"t":2,"d"');
    final recorder = Recorder(data);
    await recorder.start();
    recorder
      ..add(line(now, 8))
      ..add(line(now, 9));
    await recorder.flush();
    recorder.add(line(now, 10));
    await recorder.flush();
    final lines = today.readAsLinesSync();
    expect(lines, hasLength(5));
    expect(lines[1], '{"t":2,"d"');
    expect([for (final l in lines.skip(2)) (jsonDecode(l) as Map)['d']], [8, 9, 10]);
  });

  test('the buffer limit counts what waits in the write queue too', () async {
    final recorder = Recorder(data);
    await recorder.start();
    final now = DateTime.now();
    // The first flush is queued behind a slow cleanup; its lines are not on disk yet.
    for (var i = 0; i < Recorder.maxBuffered; i++) {
      recorder.add(line(now));
    }
    final writing = recorder.flush();
    recorder.add(line(now));
    expect(recorder.dropped, 1);
    await writing;
    recorder.add(line(now));
    expect(recorder.dropped, 1);
    await recorder.flush();
    expect(recorder.written, Recorder.maxBuffered + 1);
    expect(recorder.lastFlush, isNotNull);
    expect(recorder.lastWriteFailed, isFalse);
  });

  group('lines without time are converted', () {
    Future<Recorder> unsynced(int lines) async {
      var known = false;
      final recorder = Recorder(data)
        ..timeKnown = (() => known)
        ..monoMicros = (() => 1000000);
      await recorder.start();
      for (var i = 0; i < lines; i++) {
        recorder.add({'t': 1, 'd': i});
      }
      await recorder.flush();
      known = true;
      return recorder;
    }

    test('into the daily files, after a truncated last line too', () async {
      final now = DateTime.now();
      final today = file('${Recorder.dayName(now)}.ndjson', '{"t":1,"d":99}\n{"t":2');
      final recorder = await unsynced(3);
      await recorder.retime(now, 1000000);
      expect(names(), ['${Recorder.dayName(now)}.ndjson']);
      final lines = today.readAsLinesSync();
      expect(lines, hasLength(5));
      expect([for (final l in lines.skip(2)) (jsonDecode(l) as Map)['d']], [0, 1, 2]);
      expect(lines.skip(2).every((l) => !l.contains('mono')), isTrue);
    });

    test('power cut while a part was being appended: cut back and appended once', () async {
      final today = Recorder.dayName(DateTime.now());
      final before = '{"t":1,"d":99}\n';
      final part = '{"t":5,"d":1}\n{"t":6,"d":2}\n';
      // The daily file already got half of the part.
      file('$today.ndjson', '$before{"t":5,"d":1}\n{"t":6');
      file('$today.ndjson.retime-${before.length}', part);
      file('unsynced-100.ndjson.retimed', 'old');
      await Recorder(data).start();
      expect(names(), ['$today.ndjson']);
      expect(File('${history.path}/$today.ndjson').readAsStringSync(), '$before$part');
    });

    test('power cut after the source was set aside: remaining parts are appended', () async {
      final today = Recorder.dayName(DateTime.now());
      file('$today.ndjson.retime-tmp', '{"t":5,"d":1}\n');
      file('unsynced-100.ndjson.retimed', 'old');
      await Recorder(data).start();
      expect(names(), ['$today.ndjson']);
      expect(File('${history.path}/$today.ndjson').readAsStringSync(), '{"t":5,"d":1}\n');
    });

    test('power cut before that: incomplete parts go, the source stays as a section without time', () async {
      final today = Recorder.dayName(DateTime.now());
      file('$today.ndjson.retime-tmp', '{"t":5,"d":1}\n');
      file('unsynced-100.ndjson', '{"t":1,"mono":5}\n');
      await Recorder(data).start();
      expect(names().single, matches(RegExp(r'^unsynced-100-\d+\.ndjson$')));
    });
  });

  test('a write queue that hangs is reported as stalled, a full disk is not', () async {
    var now = DateTime(2026, 11, 16, 12);
    final never = Completer<void>();
    final recorder = Recorder(data, clock: () => now, syncFile: (_) => never.future);
    await recorder.start();
    expect(recorder.stalled, isFalse);
    recorder.add(line(now));
    unawaited(recorder.flush(durable: true));
    recorder.add(line(now));
    unawaited(recorder.flush());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(recorder.stalled, isFalse, reason: 'packing a large day takes minutes');
    now = now.add(Recorder.stallAfter + const Duration(minutes: 1));
    expect(recorder.stalled, isTrue);

    final full = Recorder(Directory('${data.path}/full')..createSync(), clock: () => now, freeSpace: (_) async => 0);
    await full.start();
    full.add(line(now));
    await full.flush();
    now = now.add(Recorder.stallAfter + const Duration(minutes: 1));
    expect(full.lowSpace, isTrue);
    expect(full.stalled, isFalse);
  });
}
