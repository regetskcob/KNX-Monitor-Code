import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

// Sprang die Uhr der Box, gibt es für einen Tag schon eine .gz und eine neue
// Datei. Packen darf den früheren Teil nicht ersetzen.
void main() {
  test('Packen führt einen schon gepackten Tag mit der neuen Datei zusammen', () async {
    final day = DateTime.now().subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
    final data = Directory.systemTemp.createTempSync('merge');
    addTearDown(() => data.deleteSync(recursive: true));
    final dir = Directory('${data.path}/history')..createSync();
    File('${dir.path}/$day.ndjson.gz').writeAsBytesSync(gzip.encode(utf8.encode('{"a":1}\n')));
    File('${dir.path}/$day.ndjson').writeAsStringSync('{"b":2}\n');
    final recorder = Recorder(data);
    final before = await (await recorder.dayLines(day))!.toList();
    expect(before, ['{"a":1}', '{"b":2}'], reason: 'auch vor dem Packen beide Teile');
    await recorder.start();
    final after = await (await recorder.dayLines(day))!.toList();
    await recorder.flush();
    expect(after, ['{"a":1}', '{"b":2}']);
    expect(File('${dir.path}/$day.ndjson').existsSync(), isFalse);
  });

  group('power cut during packing', () {
    late String day;
    late Directory dir;
    late Directory data;

    setUp(() {
      day = DateTime.now().subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
      data = Directory.systemTemp.createTempSync('merge');
      dir = Directory('${data.path}/history')..createSync();
    });
    tearDown(() => data.deleteSync(recursive: true));

    Future<List<String>> after() async {
      final recorder = Recorder(data);
      await recorder.start();
      await recorder.flush();
      expect(dir.listSync().map((e) => e.uri.pathSegments.last).toList(), ['$day.ndjson.gz']);
      return (await recorder.dayLines(day))!.toList();
    }

    List<int> packed(String text) => gzip.encode(utf8.encode(text));

    test('before the original was set aside: packed again from the original', () async {
      File('${dir.path}/$day.ndjson').writeAsStringSync('{"a":1}\n');
      File('${dir.path}/$day.ndjson.gz.tmp').writeAsBytesSync(packed('{"a"'));
      expect(await after(), ['{"a":1}']);
    });

    test('after the original was set aside: the packed file becomes the day', () async {
      File('${dir.path}/$day.ndjson.done').writeAsStringSync('{"b":2}\n');
      File('${dir.path}/$day.ndjson.gz.tmp').writeAsBytesSync(packed('{"a":1}\n{"b":2}\n'));
      expect(await after(), ['{"a":1}', '{"b":2}']);
    });

    test('after the rename: the leftover original is only deleted', () async {
      File('${dir.path}/$day.ndjson.done').writeAsStringSync('{"b":2}\n');
      File('${dir.path}/$day.ndjson.gz').writeAsBytesSync(packed('{"a":1}\n{"b":2}\n'));
      expect(await after(), ['{"a":1}', '{"b":2}']);
    });

    test('a new file equal to the end of the packed day is still merged', () async {
      File('${dir.path}/$day.ndjson.gz').writeAsBytesSync(packed('{"a":1}\n'));
      File('${dir.path}/$day.ndjson').writeAsStringSync('{"a":1}\n');
      expect(await after(), ['{"a":1}', '{"a":1}']);
    });
  });
}
