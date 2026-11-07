import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

void main() {
  late Directory data;
  late File boot;
  var now = DateTime(2026, 10, 30, 12);

  CrashWatch watch() => CrashWatch(data, version: '1.9.0', now: () => now, bootIdFile: boot, log: (_) {});

  setUp(() async {
    data = await Directory.systemTemp.createTemp('knx_crash');
    boot = File('${data.path}/boot_id')..writeAsStringSync('A\n');
    now = DateTime(2026, 10, 30, 12);
  });
  tearDown(() => data.delete(recursive: true));

  test('erster Start und sauberes Ende: nichts gezählt', () async {
    final first = watch();
    await first.start();
    expect(first.entries, isEmpty);
    expect(first.summary(), isNull);
    await first.cleanExit();
    final next = watch();
    await next.start();
    expect(next.entries, isEmpty);
    await next.cleanExit();
  });

  test('Ende ohne Abmeldung zählt, mit letztem Lebenszeichen und Version', () async {
    await watch().start(); // kein cleanExit: wie ein Absturz
    final seen = await File('${data.path}/running.json').lastModified();
    now = now.add(const Duration(hours: 1));
    final next = watch();
    await next.start();
    final entry = next.entries.single;
    expect(entry['reason'], 'unknown');
    expect(entry['version'], '1.9.0');
    expect(entry['lastSeen'], seen.millisecondsSinceEpoch);
    expect(next.summary()!['count'], 1);
    await next.cleanExit();
  });

  test('anderes Boot-ID heißt: Host neu gestartet (Strom, Reboot)', () async {
    await watch().start();
    boot.writeAsStringSync('B\n');
    final next = watch();
    await next.start();
    expect(next.entries.single['reason'], 'host');
    await next.cleanExit();
  });

  test('unbehandelter Fehler landet als Grund im nächsten Start, nur einmal', () async {
    final first = watch();
    await first.start();
    first.recordError(StateError('kaputt'), StackTrace.current);
    final next = watch();
    await next.start();
    expect(next.entries.single['reason'], 'error');
    expect(next.entries.single['error'], contains('kaputt'));
    expect(
      next.between(now.subtract(const Duration(days: 1)), now.add(const Duration(days: 1))).single.containsKey('error'),
      isFalse,
    );
    // Paired devices without admin rights get no error text.
    expect(next.recent().single['error'], contains('kaputt'));
    expect(next.recent(withError: false).single.containsKey('error'), isFalse);
    expect(next.recent(withError: false).single['reason'], 'error');
    await next.cleanExit();
    final third = watch();
    await third.start();
    expect(third.entries, hasLength(1));
    await third.cleanExit();
  });

  test('zählt nur die letzten 30 Tage, alles liegt im Datenordner', () async {
    await watch().start();
    final next = watch();
    await next.start();
    now = now.add(const Duration(days: 31));
    expect(next.summary(), isNull);
    expect(next.recent(days: 60), hasLength(1));
    final lines = await File('${data.path}/restarts.ndjson').readAsLines();
    expect(jsonDecode(lines.single), containsPair('reason', 'unknown'));
    await next.cleanExit();
  });

  test('Fehler beim Schreiben verhindern den Start nicht', () async {
    await Directory('${data.path}/running.json').create();
    await Directory('${data.path}/restarts.ndjson').create();
    final w = watch();
    await w.start();
    w.recordError('x', null);
    await w.cleanExit();
    expect(w.summary(), isNull);
  });

  test('begrenzt die Liste', () async {
    final keep = CrashWatch(data, keep: 2, now: () => now, bootIdFile: boot, log: (_) {});
    for (var i = 0; i < 5; i++) {
      await File('${data.path}/running.json').writeAsString('{}');
      final w = CrashWatch(data, keep: 2, now: () => now, bootIdFile: boot, log: (_) {});
      await w.start();
    }
    await File('${data.path}/running.json').delete();
    await keep.start();
    expect(keep.entries, hasLength(2));
    await keep.cleanExit();
  });

  test('Uhr gestellt: der Eintrag dieses Starts bekommt die richtige Zeit', () async {
    await watch().start();
    final seen = await File('${data.path}/running.json').lastModified();
    boot.writeAsStringSync('B\n');
    now = DateTime(2026, 10, 26, 11, 31); // Startzeit ohne Batterie-Uhr
    final next = watch();
    await next.start();
    expect(next.entries.single['t'], lessThan(seen.millisecondsSinceEpoch));
    final real = DateTime(2026, 11, 7, 7, 4);
    await next.retime(real);
    final t = next.entries.single['t']! as int;
    expect(real.millisecondsSinceEpoch - t, inInclusiveRange(0, 5000));
    expect(next.entries.single['lastSeen'], seen.millisecondsSinceEpoch);
    final saved = jsonDecode(File('${data.path}/restarts.ndjson').readAsLinesSync().single) as Map;
    expect(saved['t'], t);
    await next.cleanExit();
  });

  test('Uhr gestellt ohne Eintrag dieses Starts: nichts geändert', () async {
    final first = watch();
    await first.start();
    await first.retime(DateTime(2026, 11, 7));
    expect(first.entries, isEmpty);
    expect(File('${data.path}/restarts.ndjson').existsSync(), isFalse);
    await first.cleanExit();
  });

  group('Grund von systemd (last-exit.json)', () {
    Future<Map<String, Object?>> endWith(Map<String, Object?> exit, {bool newBoot = false}) async {
      await watch().start(); // kein cleanExit
      File('${data.path}/last-exit.json').writeAsStringSync(jsonEncode(exit));
      if (newBoot) boot.writeAsStringSync('B\n');
      final next = watch();
      await next.start();
      expect(File('${data.path}/last-exit.json').existsSync(), isFalse);
      await next.cleanExit();
      return next.entries.single;
    }

    test('Speicher voll', () async {
      final e = await endWith({'result': 'oom-kill', 'code': 'killed', 'status': 'KILL'});
      expect(e['reason'], 'oom');
      expect(e['signal'], 'KILL');
    });

    test('Signal mit Name', () async {
      final e = await endWith({'result': 'core-dump', 'code': 'dumped', 'status': 'SEGV'});
      expect(e['reason'], 'signal');
      expect(e['signal'], 'SEGV');
    });

    test('Watchdog', () async {
      expect((await endWith({'result': 'watchdog', 'code': 'killed', 'status': 'ABRT'}))['reason'], 'watchdog');
    });

    test('Exit-Code sagt nichts Neues: Boot-ID entscheidet wie bisher', () async {
      final e = await endWith({'result': 'exit-code', 'code': 'exited', 'status': '1'}, newBoot: true);
      expect(e['reason'], 'host');
      expect(e.containsKey('signal'), isFalse);
    });

    test('eigener Fehlertext geht vor', () async {
      final first = watch();
      await first.start();
      first.recordError(StateError('kaputt'), null);
      File('${data.path}/last-exit.json').writeAsStringSync(jsonEncode({'result': 'exit-code', 'status': '255'}));
      final next = watch();
      await next.start();
      expect(next.entries.single['reason'], 'error');
      await next.cleanExit();
    });

    test('nach sauberem Ende: Datei weg, kein Eintrag, erklärt kein späteres Ende', () async {
      final first = watch();
      await first.start();
      await first.cleanExit();
      File('${data.path}/last-exit.json').writeAsStringSync(jsonEncode({'result': 'signal', 'status': 'TERM'}));
      final second = watch();
      await second.start(); // liest und löscht
      expect(second.entries, isEmpty);
      // jetzt ein Ende ohne systemd-Angabe
      final third = watch();
      await third.start();
      expect(third.entries.single['reason'], 'unknown');
      await third.cleanExit();
    });

    test('kaputte Datei: kein Grund, Start läuft weiter', () async {
      await watch().start();
      File('${data.path}/last-exit.json').writeAsStringSync('{kaputt');
      final next = watch();
      await next.start();
      expect(next.entries.single['reason'], 'unknown');
      expect(File('${data.path}/last-exit.json').existsSync(), isFalse);
      await next.cleanExit();
    });

    test('Signal erscheint in Zusammenfassung und Bericht', () async {
      await endWith({'result': 'signal', 'code': 'killed', 'status': 'KILL'});
      final again = watch();
      await again.start();
      expect((again.summary()!['last']! as Map)['signal'], 'KILL');
      expect(again.between(DateTime(2000), DateTime(2100)).single['signal'], 'KILL');
      await again.cleanExit();
    });
  });
}
