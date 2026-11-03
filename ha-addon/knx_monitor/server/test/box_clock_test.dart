import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/box.dart';
import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

/// Monotonzähler zum Weiterdrehen.
class FakeWatch implements Stopwatch {
  int micros = 0;
  @override
  int get elapsedMicroseconds => micros;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late Directory data;
  late DateTime system;
  late FakeWatch watch;

  setUp(() async {
    data = await Directory.systemTemp.createTemp('box_clock');
    system = DateTime(2026, 10, 19, 12); // Systemuhr der Box (falsch oder richtig)
    watch = FakeWatch();
  });

  tearDown(() => data.delete(recursive: true));

  BoxClock clockWith(ClockSource start) => BoxClock(
    requestFile: File('${data.path}/time-request.json'),
    probe: () async => start,
    system: () => system,
    monotonic: watch,
  );

  int? requested() {
    final f = File('${data.path}/time-request.json');
    if (!f.existsSync()) return null;
    return (jsonDecode(f.readAsStringSync()) as Map)['epochMs'] as int;
  }

  group('Entscheidung', () {
    test('unsichere Uhr: sofort stellen, Wunsch an den Host', () async {
      final clock = clockWith(ClockSource.none);
      await clock.init();
      final real = DateTime(2026, 10, 19, 14, 30);
      expect(await clock.offer(real, ClockSource.client), 'set');
      expect(requested(), real.millisecondsSinceEpoch);
      expect(clock.source, ClockSource.client);
    });

    test('sichere Uhr, kleine Abweichung: nichts tun', () async {
      final clock = clockWith(ClockSource.ntp);
      await clock.init();
      expect(await clock.offer(system.add(const Duration(seconds: 1)), ClockSource.client), 'ok');
      expect(requested(), isNull);
    });

    test('vertrauenswürdigere Quelle stellt kleine Sprünge selbst', () async {
      final clock = clockWith(ClockSource.rtc);
      await clock.init();
      expect(await clock.offer(system.add(const Duration(minutes: 3)), ClockSource.client), 'set');
    });

    test('große Abweichung oder schwächere Quelle: melden, erst auf Nachfrage stellen', () async {
      final clock = clockWith(ClockSource.ntp);
      await clock.init();
      final later = system.add(const Duration(hours: 1));
      expect(await clock.offer(later, ClockSource.client), 'differs');
      expect(clock.status()['offsets'], {'client': const Duration(hours: 1).inMilliseconds});
      expect(requested(), isNull);
      expect(await clock.offer(later, ClockSource.client, force: true), 'set');
      expect(requested(), later.millisecondsSinceEpoch);
    });

    test('KNX-Zeitgeber überstimmt das iPhone nicht', () async {
      final clock = clockWith(ClockSource.none);
      await clock.init();
      await clock.offer(system, ClockSource.client);
      expect(await clock.offer(system.add(const Duration(minutes: 5)), ClockSource.knx), 'differs');
    });

    test('ohne Host (Add-on): unsupported', () async {
      final clock = BoxClock(probe: () async => ClockSource.none, system: () => system, monotonic: watch);
      await clock.init();
      expect(await clock.offer(system, ClockSource.client), 'unsupported');
    });
  });

  test('bis der Host stellt, rechnet now() die Korrektur drauf', () async {
    final clock = clockWith(ClockSource.none);
    await clock.init();
    final real = DateTime(2026, 10, 19, 14);
    await clock.offer(real, ClockSource.client);
    watch.micros += 500000;
    expect(clock.now(), real.add(const Duration(milliseconds: 500)));
    system = real.add(const Duration(milliseconds: 600)); // chrony hat gestellt
    expect(clock.now(), system);
  });

  group('KNX-Zeitgeber', () {
    // 19.10.2026, Montag 14:30:05, Arbeitstag, Sommerzeit
    List<int> dpt19(int minute, int second) => [126, 10, 19, (1 << 5) | 14, minute, second, 0x41, 0x00];
    Map<String, Object?> line(int group, List<int> bytes, {int type = 2}) => {
      'd': group,
      'y': type,
      'x': [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join(),
    };

    test('DPT 19.001 lesen, als fehlend markierte Felder ablehnen', () {
      expect(parseDateTime19(dpt19(30, 5)), DateTime(2026, 10, 19, 14, 30, 5));
      expect(parseDateTime19([...dpt19(30, 5).take(6), 0x80, 0]), isNull); // Fehler
      expect(parseDateTime19([...dpt19(30, 5).take(6), 0x02, 0]), isNull); // keine Zeit
      expect(parseDateTime19([126, 2, 31, 10, 0, 0, 0, 0]), isNull); // 31.02.
    });

    test('ohne Projekt: erst zwei passende Telegramme derselben Adresse', () async {
      final clock = clockWith(ClockSource.none);
      await clock.init();
      final watchKnx = KnxTimeWatch(clock, dptOf: (_) => null);
      await watchKnx.observe(line(0x0A01, dpt19(30, 5)));
      expect(clock.synced, isFalse);
      watch.micros += 60 * 1000000;
      await watchKnx.observe(line(0x0A01, dpt19(31, 5)));
      expect(clock.source, ClockSource.knx);
      expect(requested(), DateTime(2026, 10, 19, 14, 31, 5).millisecondsSinceEpoch);
    });

    test('ohne Projekt: unpassender Abstand stellt nicht', () async {
      final clock = clockWith(ClockSource.none);
      await clock.init();
      final watchKnx = KnxTimeWatch(clock, dptOf: (_) => null);
      await watchKnx.observe(line(0x0A01, dpt19(30, 5)));
      watch.micros += 10 * 1000000;
      await watchKnx.observe(line(0x0A01, dpt19(45, 0)));
      expect(clock.synced, isFalse);
    });

    test('mit Projekt: DPT 19 sofort, DPT 10 mit 11 zusammen, Leseanfragen nicht', () async {
      final clock = clockWith(ClockSource.none);
      await clock.init();
      final dpts = {0x0A01: 19, 0x0A02: 10, 0x0A03: 11};
      final watchKnx = KnxTimeWatch(clock, dptOf: (g) => dpts[g]);
      expect(watchKnx.timeGroup(dpts.keys), 0x0A01);
      await watchKnx.observe(line(0x0A01, dpt19(30, 5), type: 0));
      expect(clock.synced, isFalse);
      await watchKnx.observe(line(0x0A01, dpt19(30, 5)));
      expect(clock.source, ClockSource.knx);

      final second = clockWith(ClockSource.none);
      await second.init();
      final pair = KnxTimeWatch(second, dptOf: (g) => dpts[g]);
      await pair.observe(line(0x0A02, [(1 << 5) | 8, 15, 0])); // Zeit ohne Datum
      expect(second.synced, isFalse);
      await pair.observe(line(0x0A03, [19, 10, 26]));
      await pair.observe(line(0x0A02, [(1 << 5) | 8, 15, 30]));
      expect(requested(), DateTime(2026, 10, 19, 8, 15, 30).millisecondsSinceEpoch);
    });
  });

  group('Aufzeichnung ohne Zeit', () {
    test('wird beim Stellen in die richtigen Tage umgerechnet', () async {
      var known = false;
      final recorder = Recorder(data, flushInterval: Duration.zero)
        ..timeKnown = (() => known)
        ..monoMicros = (() => watch.micros);
      await recorder.start();
      // Falsche Systemzeit: 1.1.2025, aber 10 s zwischen den Telegrammen.
      recorder.add({'t': DateTime(2025).microsecondsSinceEpoch, 'd': 1, 'y': 2, 'x': '01'});
      watch.micros += 10 * 1000000;
      recorder.add({'t': DateTime(2025).microsecondsSinceEpoch, 'd': 2, 'y': 2, 'x': '01'});
      await recorder.flush();
      final history = Directory('${data.path}/history');
      expect(history.listSync().map((f) => f.uri.pathSegments.last), [startsWith('unsynced-')]);

      // Jetzt (Monotonzähler 20 s) ist es wirklich 19.10.2026 12:00:20.
      watch.micros += 10 * 1000000;
      known = true;
      await recorder.retime(DateTime(2026, 10, 19, 12, 0, 20), watch.micros);
      final day = File('${history.path}/2026-10-19.ndjson');
      final lines = [for (final l in day.readAsLinesSync()) jsonDecode(l) as Map<String, Object?>];
      expect(
        [for (final l in lines) DateTime.fromMicrosecondsSinceEpoch(l['t']! as int)],
        [DateTime(2026, 10, 19, 12), DateTime(2026, 10, 19, 12, 0, 10)],
      );
      expect(lines.every((l) => !l.containsKey('mono')), isTrue);
      expect(history.listSync().where((f) => f.path.contains('unsynced')), isEmpty);
    });

    test('streng: ohne Zeit wird nur gezählt', () async {
      final recorder = Recorder(data, flushInterval: Duration.zero)
        ..timeKnown = (() => false)
        ..holdUntilTime = true;
      await recorder.start();
      recorder.add({'t': 0, 'd': 1, 'y': 2, 'x': '01'});
      await recorder.flush();
      expect(recorder.waiting, 1);
      expect(Directory('${data.path}/history').listSync(), isEmpty);
    });
  });
}
