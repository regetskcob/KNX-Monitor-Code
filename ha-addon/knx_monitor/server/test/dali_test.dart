// DALI on the server: the decoding is the app's (same file, same fixture), watchers know the
// check kind `bits`, faults count per luminaire, and the emergency lighting log is only appended.
import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

List<int> bytes(String hex) => [
  for (var i = 0; i + 1 < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
];

/// A decoded value as the fixture writes it down (the app's test has the same function).
Map<String, Object?>? describe(int dpt, List<int> d) {
  if (dpt == 237 || dpt == 238) {
    final r = decodeDaliReport(dpt, d);
    return r == null ? null : {'address': r.address, 'group': r.isGroup, 'faults': r.faults, 'read': r.readRequest};
  }
  if (dpt == 244) {
    final v = decodeConverterStatus(d);
    return v == null
        ? null
        : {
            'mode': v.mode.name,
            'switch': v.hardwiredSwitch,
            'inhibit': v.hardwiredInhibit,
            'fp': v.functionTestPending.name,
            'dp': v.durationTestPending.name,
            'pp': v.partialDurationTestPending.name,
            'failure': v.failure.name,
          };
  }
  final v = decodeConverterTestResult(d);
  return v == null
      ? null
      : {
          'function': v.function.name,
          'duration': v.duration.name,
          'partial': v.partial.name,
          'sf': v.functionStart.name,
          'sd': v.durationStart.name,
          'sp': v.partialStart.name,
          'minutes': v.durationMinutes,
          'charge': v.partialCharge,
        };
}

void main() {
  const gateway = 0x1128; // 1.1.40
  const diag = 0x0C14; // 1/4/20
  const status = 0x2910; // 5/1/16
  const result = 0x2A10; // 5/2/16
  const lampBit = 0x0F00; // 1/7/0
  final t0 = DateTime(2026, 11, 10, 2, 15, 3);

  Map<String, Object?> line(
    int ga,
    String hex, {
    bool small = false,
    int type = 2,
    DateTime? at,
    int source = gateway,
  }) => {'t': (at ?? t0).microsecondsSinceEpoch, 's': source, 'd': ga, 'y': type, 'x': hex, if (small) 'm': true};

  test('the server copy of the codec is the app file', () {
    expect(File('lib/src/dali.dart').readAsStringSync(), File('../../../lib/knx/dali.dart').readAsStringSync());
  });

  test('fixtures decode exactly as in the app', () {
    final fixture =
        jsonDecode(File('../../../test/fixtures/dali/codec.json').readAsStringSync()) as Map<String, Object?>;
    for (final f in (fixture['values']! as List).cast<Map<String, Object?>>()) {
      expect(describe(f['dpt']! as int, bytes(f['x']! as String)), f['v'], reason: 'DPT ${f['dpt']} ${f['x']}');
    }
    for (final f in (fixture['bits']! as List).cast<Map<String, Object?>>()) {
      expect(bitsCheckMatches((f['check']! as Map).cast(), bytes(f['x']! as String)), f['match'], reason: '$f');
    }
  });

  test('the status announces the check kind and DALI', () {
    expect(BusService.features, containsAll(['bitsCheck', 'dali']));
  });

  group('watcher check kind bits', () {
    late Directory data;
    final sent = <(String, String, String)>[];
    late WatchRuleSet set;

    setUp(() async {
      data = await Directory.systemTemp.createTemp('knx_dali_watch');
      sent.clear();
      set = WatchRuleSet(
        data,
        notify: ({required id, required title, required message}) async => sent.add((id, title, message)),
      );
    });
    tearDown(() => data.delete(recursive: true));

    Future<void> rules(List<Map<String, Object?>> list) =>
        File('${data.path}/watch_rules.json').writeAsString(jsonEncode({'rules': list}));

    test('any fault flag, one luminaire only, never a query or a wrong length', () async {
      await rules([
        {
          'id': 'all',
          'address': diag,
          'label': 'DALI-Fehler · Gateway 1.1.40',
          'value': 'bits',
          'check': {
            'bits': {'bytes': 2, 'mask': 0x0700, 'zero': 0x80},
          },
        },
        {
          'id': 'one',
          'address': diag,
          'label': 'DALI-Fehler · EVG 12',
          'check': {
            'bits': {'bytes': 2, 'mask': 0x0700, 'zero': 0x80, 'addr': 12, 'addrMask': 0x7F},
          },
        },
        // Unreadable checks never fire, and do not switch off the others.
        {
          'id': 'broken',
          'address': diag,
          'check': {
            'bits': {'mask': 'x'},
          },
        },
        {
          'id': 'worse',
          'address': diag,
          'check': {'bits': 'x'},
        },
      ]);
      expect(await set.check(line(diag, '000C')), isEmpty);
      expect(await set.check(line(diag, '018C')), isEmpty);
      expect(await set.check(line(diag, '01', small: true)), isEmpty);
      expect(await set.check(line(diag, '010C00')), isEmpty);
      expect(await set.check(line(diag, '010D')), ['all']);
      expect(await set.check(line(diag, '010C', at: t0.add(const Duration(seconds: 10)))), ['all', 'one']);
      expect(sent.map((s) => s.$2), ['Wächter: DALI-Fehler · Gateway 1.1.40', 'Wächter: DALI-Fehler · EVG 12']);
      expect((await set.rules()).map((r) => r.id), ['all', 'one']);
    });
  });

  group('FaultDebouncer', () {
    final t0 = DateTime(2026, 11, 10, 2);
    DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

    test('flickering never settles: nothing; a state that holds counts once', () {
      final d = FaultDebouncer();
      for (var i = 0; i < 20; i++) {
        d.report('a', gateway, i.isEven ? 1 : 0, at(i));
      }
      expect(d.take(at(25)), isEmpty);
      expect(d.take(at(60)), isEmpty, reason: 'ended on 0, as it was announced');
      d.report('a', gateway, 1, at(61));
      expect(d.nextDue, at(91));
      expect(d.take(at(80)), isEmpty);
      final n = d.take(at(91)).single;
      expect((n.before, n.after, n.notify, n.event), (0, 1, true, true));
      expect(d.take(at(200)), isEmpty);
    });

    test('back to normal only for a notified fault; fault again within the throttle: event, no notification', () {
      final d = FaultDebouncer(settle: Duration.zero);
      d.report('a', gateway, 1, at(0));
      expect(d.take(at(0)).single.notify, isTrue);
      d.report('a', gateway, 0, at(1));
      expect(d.take(at(1)).single.notify, isTrue);
      d.report('a', gateway, 1, at(2));
      final again = d.take(at(2)).single;
      expect((again.notify, again.event), (false, true));
      d.report('a', gateway, 0, at(3));
      expect(d.take(at(3)).single.notify, isFalse);
    });

    test('64 luminaires at once: five notifications and one summary per gateway, events capped', () {
      final d = FaultDebouncer(settle: Duration.zero);
      for (var a = 0; a < 64; a++) {
        d.report('$gateway:$a', gateway, 1, at(0));
      }
      final notices = d.take(at(0));
      expect(notices.where((n) => n.notify && n.count == 0).length, 5);
      expect(notices.where((n) => n.count > 0).single.count, 59);
      expect(notices.where((n) => n.event).length, 60);
    });

    test('keys are bounded', () {
      final d = FaultDebouncer(settle: Duration.zero, maxKeys: 100);
      for (var a = 0; a < 1000; a++) {
        d.report('k$a', a, 1, at(0));
        d.take(at(0));
      }
      expect(d.length, 100);
    });
  });

  group('DaliWatch', () {
    late Directory data;
    final sent = <(String, String, String)>[];
    final changes = <DaliFaultChange>[];
    late DaliWatch watch;
    var timeKnown = true;

    final dpts = <int, (int, int?)>{diag: (237, 600), status: (244, 600), result: (245, 600), lampBit: (1, 5)};

    setUp(() async {
      data = await Directory.systemTemp.createTemp('knx_dali');
      sent.clear();
      changes.clear();
      timeKnown = true;
      watch = DaliWatch(
        data,
        dptOf: (g) => dpts[g],
        formatGroup: (g) => '${(g >> 11) & 0x1F}/${(g >> 8) & 7}/${g & 0xFF}',
        notify: ({required id, required title, required message}) async => sent.add((id, title, message)),
        onChange: changes.add,
        timeKnown: () => timeKnown,
        debouncer: FaultDebouncer(settle: Duration.zero),
      );
    });
    tearDown(() async {
      watch.dispose();
      await data.delete(recursive: true);
    });

    /// A telegram, then what settled at its time.
    Future<void> check(Map<String, Object?> l, {bool secure = false}) async {
      await watch.check(l, secure: secure);
      await watch.flush(DateTime.fromMicrosecondsSinceEpoch(l['t']! as int));
    }

    Future<void> model([Map<String, Object?>? json]) => File('${data.path}/dali.json').writeAsString(
      jsonEncode(
        json ??
            {
              'v': 1,
              'gateways': [
                {'a': gateway, 'pn': 'DALI-Gateway'},
              ],
              'gear': [
                {'gw': gateway, 'a': 12, 'n': 'Flur EG Leuchte 2', 'r': 'Flur EG'},
                {'gw': gateway, 'a': 16, 'emd': true, 'st': status, 'res': result},
              ],
              'groups': [
                {'gw': gateway, 'g': 3, 'n': 'Büro 2.15'},
              ],
              'objects': {
                '$diag': {'gw': gateway, 'r': 'diagnostic'},
                '$lampBit': {'gw': gateway, 'r': 'lampFault', 'i': 0},
                '$status': {'gw': gateway, 'r': 'emergencyStatus', 'i': 16},
                '$result': {'gw': gateway, 'r': 'emergencyResult', 'i': 16},
              },
            },
      ),
    );

    Future<List<Map<String, Object?>>> log() async {
      final file = File('${data.path}/dali_tests/2026.ndjson');
      if (!await file.exists()) return const [];
      return [
        for (final l in const LineSplitter().convert(await file.readAsString())) jsonDecode(l) as Map<String, Object?>,
      ];
    }

    test('per luminaire: into the fault, back; named from dali.json; reads and queries change nothing', () async {
      await model();
      await check(line(diag, '000C'));
      await check(line(diag, '010C', at: t0.add(const Duration(minutes: 1))));
      await check(line(diag, '010D', at: t0.add(const Duration(minutes: 1))));
      await check(line(diag, '008E', at: t0.add(const Duration(minutes: 1)))); // query
      await check(line(diag, '010C', type: 0)); // read request
      expect(sent.map((s) => s.$2), ['Lampenfehler: Flur EG Leuchte 2', 'Lampenfehler: EVG 13']);
      expect(sent.first.$1, 'knx_dali_${gateway}_12');
      expect(sent.first.$3, 'EVG 12 · Flur EG · Gateway 1.1.40 · 02:16:03');
      expect(watch.openCount, 2);
      await check(line(diag, '000C', at: t0.add(const Duration(minutes: 2))));
      expect(sent.last.$2, 'Wieder in Ordnung: Flur EG Leuchte 2');
      expect(changes.where((c) => c.address == 12).map((c) => c.faults), [1, 0]);
      expect(
        (changes.first.gateway, changes.first.groupAddress, changes.first.name),
        ('1.1.40', '1/4/20', 'Flur EG Leuchte 2'),
      );
    });

    test('groups, English, notifications off, 1-bit fault objects only from the gateway', () async {
      await model();
      watch.language = 'en';
      await check(line(diag, '0243'));
      expect(sent.single.$2, 'ECG failure: G3 Büro 2.15');
      expect(sent.single.$3, startsWith('Group 3 · Gateway 1.1.40'));
      watch.enabled = false;
      await check(line(lampBit, '01', small: true, source: 0x7777));
      expect(changes.length, 1);
      await check(line(lampBit, '01', small: true));
      expect(sent.length, 1);
      expect(changes.last.faults, DaliFault.lamp);
      expect(changes.last.name, 'ECG 0');
    });

    test('with dali.json only its gateways count; without it at most 16 senders', () async {
      await model();
      await check(line(diag, '010C', source: 0x7777));
      expect(sent, isEmpty);
      await File('${data.path}/dali.json').delete();
      for (var pa = 0x2000; pa < 0x2000 + 40; pa++) {
        await check(line(diag, '010C', source: pa));
      }
      expect(watch.openCount, DaliWatch.maxUnknownGateways);
    });

    test('broken dali.json: still per luminaire, named by address', () async {
      await File('${data.path}/dali.json').writeAsString('{"gear": "viele", "objects": [1, 2]');
      await check(line(diag, '030C'));
      expect(sent.single.$2, 'EVG-Fehler, Lampenfehler: EVG 12');
      await model({
        'gear': 7,
        'gateways': 'x',
        'objects': {
          'x': 1,
          '70000': <String, Object?>{},
          '$diag': {'gw': 'a'},
        },
      });
      await check(line(diag, '010E', at: t0.add(const Duration(seconds: 2))));
      expect(sent.length, 2);
    });

    test('other datapoint types and other addresses are none of its business', () async {
      dpts[0x0A03] = (238, 1);
      await check(line(0x0A03, '8C'));
      await check(line(0x0B00, '010C'));
      expect(sent, isEmpty);
      expect(changes, isEmpty);
    });

    test('flickering 64 luminaires at 1 Hz for 5 minutes: bounded notifications and events', () async {
      final calm = DaliWatch(
        data,
        dptOf: (g) => dpts[g],
        formatGroup: (g) => '$g',
        notify: ({required id, required title, required message}) async => sent.add((id, title, message)),
        onChange: changes.add,
      );
      await model();
      for (var s = 0; s < 300; s++) {
        for (var a = 0; a < 64; a++) {
          await calm.check(
            line(diag, '0${s.isEven ? 1 : 0}${a.toRadixString(16).padLeft(2, '0')}', at: t0.add(Duration(seconds: s))),
          );
        }
        await calm.flush(t0.add(Duration(seconds: s)));
      }
      calm.dispose();
      expect(sent, isEmpty, reason: 'nothing ever held for 30 s');
      expect(changes, isEmpty);
    });

    group('emergency log', () {
      test('one line per new result, append only, with sender; a pending test that ended counts', () async {
        await model();
        await check(line(result, '110050005CFF'));
        await check(line(result, '110050005CFF', at: t0.add(const Duration(hours: 1))));
        var lines = await log();
        expect(lines.length, 2);
        expect(lines.first, {
          't': t0.millisecondsSinceEpoch,
          'ga': result,
          'gw': gateway,
          'a': 16,
          'k': 'function',
          'r': 'passed',
          's': 'automatic',
          'x': '110050005CFF',
          'first': true,
          'src': gateway,
        });
        // A week later: function test pending, then no longer pending; the same bytes are a new test.
        final week = t0.add(const Duration(days: 7));
        await check(line(status, '1095', at: week));
        await check(line(status, '1055', at: week.add(const Duration(minutes: 2))));
        await check(line(result, '110050005CFF', at: week.add(const Duration(minutes: 2))));
        // The duration test fails.
        await check(line(result, '130050005CFF', at: week.add(const Duration(days: 1))));
        await check(line(result, '610050005CFF', at: week.add(const Duration(days: 2))));
        await check(line(result, '1300', at: week.add(const Duration(days: 2))));
        lines = await log();
        expect(lines.skip(2).map((l) => l['k']), ['function', 'duration']);
        expect(lines.last['r'], 'failed');
        expect(sent.last.$2, 'Notlichttest durchgefallen: Notlicht 16');
        expect(changes.last.test, isTrue);

        // After a restart the log tells what is known: the same bytes add nothing.
        final again = DaliWatch(
          data,
          dptOf: (g) => dpts[g],
          formatGroup: (g) => '$g',
          notify: ({required id, required title, required message}) async {},
        );
        await again.check(line(result, '130050005CFF', at: week.add(const Duration(days: 3))));
        again.dispose();
        expect((await log()).length, 4);
      });

      test('a forged result from another sender is marked foreign and notifies nothing', () async {
        await model();
        await check(line(result, '130050005CFF'));
        sent.clear();
        await check(line(result, '111050005CFF', source: 0x7777, at: t0.add(const Duration(hours: 2))));
        final count = (await log()).length;
        expect(count, 5, reason: 'two real entries, three forged ones');
        final forged = (await log()).last;
        expect((forged['gw'], forged['src'], forged['fx'], forged['r']), (gateway, 0x7777, true, 'passed'));
        expect(sent, isEmpty);
        // A forged status "running, then normal" does not make the next unchanged result a new test.
        await check(line(status, '7055', source: 0x7777, at: t0.add(const Duration(hours: 3))));
        await check(line(status, '1055', source: 0x7777, at: t0.add(const Duration(hours: 3))));
        await check(line(result, '130050005CFF', at: t0.add(const Duration(hours: 4))));
        expect((await log()).length, count);
      });

      test('Data Secure is noted', () async {
        await model();
        await check(line(result, '110050005CFF'), secure: true);
        expect((await log()).first['sec'], isTrue);
      });

      test('alternating values: at most one entry per kind and hour, the rest only counted', () async {
        await model();
        for (var i = 0; i < 2000; i++) {
          await watch.check(
            line(result, i.isEven ? '110050005CFF' : '330050005CFF', at: t0.add(Duration(milliseconds: 500 * i))),
          );
        }
        // 2000 telegrams in 17 minutes: the first two entries, then nothing for an hour.
        expect((await log()).length, 2);
        expect(watch.suppressedResults, greaterThan(1000));
      });

      test('a full year: one overflow line, one notification, nothing more; a huge file is read in part', () async {
        await model();
        final file = File('${data.path}/dali_tests/2026.ndjson');
        await file.parent.create(recursive: true);
        await file.writeAsString('${'x' * (emergencyLogMaxBytes - 100)}\n');
        await check(line(result, '110050005CFF'));
        await check(line(result, '130050005CFF', at: t0.add(const Duration(days: 1))));
        final tail = (await file.readAsString()).split('\n').where((l) => l.isNotEmpty).last;
        expect(jsonDecode(tail), containsPair('overflow', true));
        expect(sent.where((s) => s.$1 == 'knx_dali_log_full').length, 1);
        expect(await file.length(), lessThan(emergencyLogMaxBytes + 200));

        // A file far beyond the limit (put there by somebody else) is read up to the limit.
        final big = File('${data.path}/dali_tests/2025.ndjson');
        final entry = jsonEncode(
          EmergencyTest(
            time: DateTime(2025, 6, 1),
            group: result,
            kind: EmergencyTestKind.function,
            result: EmergencyResult.passed,
            raw: '110050005CFF',
          ).toJson(),
        );
        await big.writeAsString('$entry\n${'y' * (emergencyLogReadBytes + 1000)}\n');
        final fresh = DaliWatch(
          data,
          dptOf: (g) => dpts[g],
          formatGroup: (g) => '$g',
          notify: ({required id, required title, required message}) async {},
        );
        await fresh.check(line(result, '110050005CFF', at: DateTime(2025, 6, 2)));
        fresh.dispose();
        expect(await big.length(), greaterThan(emergencyLogReadBytes), reason: 'never written to');
      });

      test('converter failure from the status counts as a fault of that luminaire, only from the gateway', () async {
        await model();
        await check(line(status, '5256', source: 0x7777));
        expect(sent, isEmpty);
        await check(line(status, '5256'));
        expect(sent.single.$2, 'Konverterfehler: Notlicht 16');
        await check(line(status, '1055', at: t0.add(const Duration(minutes: 1))));
        expect(sent.last.$2, 'Wieder in Ordnung: Notlicht 16');
      });

      test('box without a synchronized clock: no log entry with a wrong date', () async {
        await model();
        timeKnown = false;
        await check(line(result, '110050005CFF'));
        expect(await log(), isEmpty);
        timeKnown = true;
        await check(line(result, '110050005CFF', at: t0.add(const Duration(minutes: 5))));
        expect((await log()).length, 2);
      });
    });
  });
}
