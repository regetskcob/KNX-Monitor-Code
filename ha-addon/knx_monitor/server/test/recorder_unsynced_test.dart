import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

// Box ohne Batterie-Uhr: Dateien ohne Zeit aus einem früheren Start lassen sich
// nicht mehr einordnen. Sie dürfen weder unsichtbar liegen bleiben noch ewig.
void main() {
  late Directory data;
  late Directory history;

  setUp(() {
    data = Directory.systemTemp.createTempSync('unsynced');
    history = Directory('${data.path}/history')..createSync();
  });
  tearDown(() => data.deleteSync(recursive: true));

  List<String> names() => [for (final f in history.listSync()) f.uri.pathSegments.last]..sort();
  File file(String name, [String text = '{"t":1,"mono":5}\n']) =>
      File('${history.path}/$name')..writeAsStringSync(text);

  test('mit Uhr: bekommt den Beginn der Aufbewahrung, Inhalt bleibt, zählt in der Belegung', () async {
    file('unsynced-100.ndjson');
    final recorder = Recorder(data);
    await recorder.start();
    expect(names().single, matches(RegExp(r'^unsynced-100-\d+\.ndjson$')));
    expect(File('${history.path}/${names().single}').readAsStringSync(), contains('"mono":5'));
    final usage = await recorder.usage();
    expect(usage['bytes'], greaterThan(0));
    expect(usage['unsynced'], 1);
  });

  test('ohne Uhr: bleibt unmarkiert, der falsche Startstempel löscht nichts', () async {
    file('unsynced-100.ndjson');
    final recorder = Recorder(data)..timeKnown = (() => false);
    await recorder.start();
    expect(names(), ['unsynced-100.ndjson']);
  });

  test('alter Startstempel wird beim ersten Aufräumen mit Uhr nicht gelöscht', () async {
    file('unsynced-1000.ndjson'); // 1970
    await (Recorder(data, retentionDays: 1)).start();
    expect(names(), hasLength(1));
  });

  test('Aufbewahrung: abgelaufen weg, frisch bleibt', () async {
    final old = DateTime.now().subtract(const Duration(days: 10)).millisecondsSinceEpoch;
    final fresh = DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch;
    file('unsynced-1-$old.ndjson');
    file('unsynced-2-$fresh.ndjson');
    await Recorder(data).start();
    expect(names(), ['unsynced-2-$fresh.ndjson']);
  });

  test('Größenlimit gilt auch ohne Uhr, unmarkierte zuerst', () async {
    final today = Recorder.dayName(DateTime.now());
    file('unsynced-1.ndjson', 'x' * (2 * 1024 * 1024));
    file('$today.ndjson', 'y');
    await (Recorder(data, maxMegabytes: 1)..timeKnown = (() => false)).start();
    expect(names(), ['$today.ndjson']);
  });

  test('Aufzeichnung aus: auch diese Dateien weg', () async {
    file('unsynced-100.ndjson');
    await Recorder(data, retentionDays: 0).start();
    expect(names(), isEmpty);
  });

  test('die Datei des laufenden Starts wird weder markiert noch gelöscht und später umgerechnet', () async {
    var known = false;
    var mono = 1000000;
    final recorder = Recorder(data, flushInterval: Duration.zero, retentionDays: 1)
      ..timeKnown = (() => known)
      ..monoMicros = (() => mono);
    await recorder.start();
    recorder.add({'t': 1, 'd': 1});
    await recorder.flush();
    known = true;
    await recorder.maintain();
    expect(names().single, matches(RegExp(r'^unsynced-\d+\.ndjson$')));
    mono = 2000000;
    final now = DateTime.now();
    await recorder.retime(now, mono);
    final line = jsonDecode(File('${history.path}/${Recorder.dayName(now)}.ndjson').readAsLinesSync().single) as Map;
    expect(line['t'], now.subtract(const Duration(seconds: 1)).microsecondsSinceEpoch);
  });
}
