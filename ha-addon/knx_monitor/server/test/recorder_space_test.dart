import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

/// Freier Platz, `fsync`-Takt und Aufräumen bei voller Platte.
void main() {
  late Directory data;
  late Directory history;
  late int free;
  late DateTime now;
  late List<String> synced;

  Map<String, Object?> line() => {
    't': DateTime.now().microsecondsSinceEpoch,
    's': 0x1105,
    'd': 0x0A03,
    'y': 2,
    'x': '01',
    'r': '00',
  };

  Recorder recorder({int minFree = 1000}) => Recorder(
    data,
    minFreeBytes: minFree,
    freeSpace: (_) async => free,
    syncFile: (f) async => synced.add(f.uri.pathSegments.last),
    clock: () => now,
  );

  String day(int back) {
    final n = DateTime.now();
    return Recorder.dayName(DateTime(n.year, n.month, n.day - back));
  }

  setUp(() async {
    data = await Directory.systemTemp.createTemp('recorder_space');
    history = Directory('${data.path}/history');
    await history.create();
    free = 1 << 40;
    now = DateTime(2026, 10, 31, 12);
    synced = [];
  });

  tearDown(() => data.delete(recursive: true));

  group('fsync', () {
    test('nicht bei jedem Schreiben, aber im Takt und beim Beenden', () async {
      final r = recorder();
      await r.start();
      r.add(line());
      await r.flush();
      expect(r.written, 1);
      expect(synced, isEmpty, reason: 'alle 5 s auf die SD-Karte hieße der Verschleiß, den das abstellt');

      now = now.add(const Duration(seconds: 10));
      r.add(line());
      await r.flush();
      expect(synced, isEmpty);

      now = now.add(const Duration(seconds: 21));
      r.add(line());
      await r.flush();
      expect(synced, ['${day(0)}.ndjson']);

      synced.clear();
      r.add(line());
      await r.flush(durable: true);
      expect(synced, ['${day(0)}.ndjson'], reason: 'Beim Beenden gehört alles fest auf die Platte');
    });

    test('ohne Änderung kein fsync', () async {
      final r = recorder();
      await r.start();
      now = now.add(const Duration(minutes: 5));
      await r.flush(durable: true);
      expect(synced, isEmpty);
    });

    test('echtes fsync schreibt die Datei und lässt sie unverändert', () async {
      final r = Recorder(data, freeSpace: (_) async => null);
      await r.start();
      r.add(line());
      await r.flush(durable: true);
      expect(await File('${history.path}/${day(0)}.ndjson').readAsLines(), hasLength(1));
    });

    test('Standard bleibt: 5 s sammeln, 30 s bis fest', () {
      final r = Recorder(data);
      expect(r.flushInterval, const Duration(seconds: 5));
      expect(r.syncInterval, const Duration(seconds: 30));
    });
  });

  group('Platz', () {
    test('wird es eng, fallen die ältesten Tage, heute bleibt', () async {
      for (final back in [0, 1, 2, 3]) {
        await File('${history.path}/${day(back)}.ndjson').writeAsString('x\n');
      }
      final r = Recorder(
        data,
        retentionDays: 30,
        minFreeBytes: 1000,
        clock: () => now,
        // Jede gelöschte Datei schafft 800 Bytes.
        freeSpace: (_) async => 100 + 800 * (4 - history.listSync().whereType<File>().length),
        syncFile: (_) async {},
      );
      await r.start();
      r.add(line());
      await r.flush();
      final left = history.listSync().map((e) => e.uri.pathSegments.last).toSet();
      expect(left, contains(startsWith(day(0))), reason: 'heute bleibt');
      expect(left, isNot(contains(startsWith(day(3)))), reason: 'ältester zuerst');
      expect(r.lowSpace, isFalse);
      expect(r.written, 1);
    });

    test('reicht das nicht: Schreiben hält an, wird gemeldet und läuft wieder an', () async {
      final r = recorder();
      await r.start();
      free = 10;
      now = now.add(const Duration(minutes: 2));
      r.add(line());
      await r.flush();
      expect(r.lowSpace, isTrue);
      expect(r.written, 0);
      expect(r.droppedLowSpace, 1);
      expect(await File('${history.path}/${day(0)}.ndjson').exists(), isFalse);
      final usage = await r.usage();
      expect(usage['lowSpace'], isTrue);
      expect(usage['droppedLowSpace'], 1);
      expect(usage['free'], 10);

      // Knapp über der Grenze: bleibt aus, sonst flattert es.
      free = 1200;
      now = now.add(const Duration(minutes: 2));
      r.add(line());
      await r.flush();
      expect(r.lowSpace, isTrue);

      free = 2000;
      now = now.add(const Duration(minutes: 2));
      r.add(line());
      await r.flush();
      expect(r.lowSpace, isFalse);
      expect(r.written, 1);
      expect((await r.usage())['droppedLowSpace'], 2);
    });

    test('misst höchstens einmal pro Minute', () async {
      var calls = 0;
      final r = Recorder(
        data,
        minFreeBytes: 1000,
        clock: () => now,
        syncFile: (_) async {},
        freeSpace: (_) async {
          calls++;
          return free;
        },
      );
      await r.start();
      final before = calls;
      for (var i = 0; i < 5; i++) {
        r.add(line());
        await r.flush();
      }
      expect(calls, before);
      now = now.add(const Duration(minutes: 1));
      r.add(line());
      await r.flush();
      expect(calls, before + 1);
    });

    test('nicht messbar: schreibt wie bisher', () async {
      final r = Recorder(data, freeSpace: (_) async => null, clock: () => now);
      await r.start();
      r.add(line());
      await r.flush();
      expect(r.written, 1);
      expect(r.lowSpace, isFalse);
    });

    test('Schreibfehler werden gezählt, nicht verschluckt', () async {
      final r = recorder();
      await r.start();
      // Ordner statt Datei: FileSystemException beim Schreiben, wie bei voller Platte.
      await Directory('${history.path}/${day(0)}.ndjson').create();
      r.add(line());
      await r.flush();
      expect(r.droppedLowSpace, 1);
      expect(r.lowSpace, isTrue);
    });

    test('freeBytes misst diese Platte', () async {
      final measured = await freeBytes(data.path);
      expect(measured, isNotNull);
      final df = await Process.run('df', ['-Pk', data.path]);
      final kb = int.parse((df.stdout as String).trim().split('\n').last.trim().split(RegExp(r'\s+'))[3]);
      // Andere Prozesse schreiben mit; 5 % reichen als Spielraum.
      expect((measured! / 1024 - kb).abs(), lessThan(kb * 0.05 + 1024 * 1024));
    });

    test('freeBytes: unbekannter Pfad ist kein Absturz', () async {
      expect(await freeBytes('/gibt/es/nicht'), isNull);
    });
  });
}
