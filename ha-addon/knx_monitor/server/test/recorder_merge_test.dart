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
}
