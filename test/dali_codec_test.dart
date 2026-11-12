import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/dali.dart';
import 'package:knx_monitor/knx/dali_text.dart';
import 'package:knx_monitor/knx/dpt_codec.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/analysis.dart';

List<int> bytes(String hex) => [
  for (var i = 0; i + 1 < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
];

Telegram write(String hex, {TelegramType type = TelegramType.write}) => Telegram(
  time: DateTime(2026, 11, 10, 12, 4, 11),
  source: 0x1128,
  destination: 0x0C14,
  type: type,
  data: Uint8List.fromList(bytes(hex)),
  isSmall: false,
);

/// A decoded value as the fixture writes it down (the server's test has the same function).
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
  final fixture = jsonDecode(File('test/fixtures/dali/codec.json').readAsStringSync()) as Map<String, Object?>;

  tearDown(() => LocaleController.instance.debugSetLocale(const Locale('de')));

  test('Fixtures: jede Nutzlast ergibt genau die erwarteten Felder, Ungültiges null', () {
    for (final f in (fixture['values']! as List).cast<Map<String, Object?>>()) {
      expect(describe(f['dpt']! as int, bytes(f['x']! as String)), f['v'], reason: 'DPT ${f['dpt']} ${f['x']}');
    }
  });

  test('Fixtures: Prüfart bits', () {
    for (final f in (fixture['bits']! as List).cast<Map<String, Object?>>()) {
      expect(
        bitsCheckMatches((f['check']! as Map).cast(), bytes(f['x']! as String)),
        f['match'],
        reason: '${f['check']} ${f['x']}',
      );
    }
  });

  test('DPT 237.600: Lampenfehler setzen und zurücknehmen, EVG-Fehler, Gruppe, Abfrage', () {
    final lamp = decodeDaliGearDiagnostic(bytes('010C'))!;
    expect((lamp.lampFailure, lamp.ballastFailure, lamp.converterError), (true, false, false));
    expect((lamp.address, lamp.isGroup, lamp.readRequest), (12, false, false));
    expect(decodeDaliGearDiagnostic(bytes('000C'))!.faults, 0);
    expect(decodeDaliGearDiagnostic(bytes('020C'))!.ballastFailure, isTrue);
    // The example of the UI draft ("04 0C") is the converter error, not the lamp failure.
    expect(decodeDaliGearDiagnostic(bytes('040C'))!.converterError, isTrue);
    expect(decodeDaliGearDiagnostic(bytes('0143'))!.isGroup, isTrue);
    expect(decodeDaliGearDiagnostic(bytes('008C'))!.readRequest, isTrue);
  });

  test('Nur die DALI-Typen: 238.001 (Szenenkonfiguration) gehört nicht dazu', () {
    expect(isDaliDpt(237, 600), isTrue);
    expect(isDaliDpt(237, null), isTrue);
    expect(isDaliDpt(238, 600), isTrue);
    expect(isDaliDpt(238, 1), isFalse);
    expect(isDaliDpt(238, null), isFalse);
    expect(isDaliDpt(9, 1), isFalse);
    expect(daliFaultBits(238, address: 3, isGroup: true), isNull);
    expect(daliFaultBits(9), isNull);
  });

  test('Klartext im Monitor, deutsch und englisch', () {
    expect(decodeDpt(const Dpt(237, 600), write('010C')), 'EVG 12 · Lampenfehler');
    expect(decodeDpt(const Dpt(237, 600), write('000C')), 'EVG 12 · in Ordnung');
    expect(decodeDpt(const Dpt(237, 600), write('030C')), 'EVG 12 · EVG-Fehler, Lampenfehler');
    expect(decodeDpt(const Dpt(237, 600), write('0043')), 'Gruppe 3 · in Ordnung');
    expect(decodeDpt(const Dpt(237, 600), write('008C')), 'EVG 12 · Abfrage');
    expect(decodeDpt(const Dpt(238, 600), write('8C')), 'EVG 12 · EVG-Fehler');
    expect(decodeDpt(const Dpt(244, 600), write('7065')), 'Funktionstest läuft');
    expect(decodeDpt(const Dpt(244, 600), write('5256')), 'Notbetrieb, Konverterfehler');
    expect(
      decodeDpt(const Dpt(245, 600), write('111054005CFF')),
      'Funktionstest bestanden, Dauertest bestanden (92 min), Teil-Dauertest bestanden',
    );
    expect(decodeDpt(const Dpt(245, 600), write('1300600029C8')), 'Funktionstest bestanden, Dauertest durchgefallen');
    expect(decodeDpt(const Dpt(245, 600), write('000000000000')), 'kein Testergebnis');
    LocaleController.instance.debugSetLocale(const Locale('en'));
    expect(decodeDpt(const Dpt(237, 600), write('010C')), 'ECG 12 · Lamp failure');
    expect(decodeDpt(const Dpt(244, 600), write('1055')), 'normal mode');
  });

  test('Falsche Länge, reservierte Werte, Lesen: kein geratener Klartext', () {
    expect(decodeDpt(const Dpt(237, 600), write('0A3F00')), isNull);
    expect(decodeDpt(const Dpt(237, 600), write('080C')), isNull);
    expect(decodeDpt(const Dpt(238, 1), write('8C')), isNull);
    expect(decodeDpt(const Dpt(237, 600), write('010C', type: TelegramType.read)), isNull);
    expect(daliMismatch(const Dpt(237, 600), write('0A3F00')), 'DPT 237.600 erwartet 2 Byte, empfangen 3.');
    expect(daliMismatch(const Dpt(237, 600), write('080C')), contains('reservierte'));
    expect(daliMismatch(const Dpt(237, 600), write('010C')), isNull);
    expect(daliDetailRows(const Dpt(237, 600), write('0A3F00')), isEmpty);
    // The health check and the project comparison know the lengths.
    expect(expectedSize(const Dpt(237, 600)), 2);
    expect(expectedSize(const Dpt(238, 600)), 1);
    expect(expectedSize(const Dpt(244, 600)), 2);
    expect(expectedSize(const Dpt(245, 600)), 6);
  });

  test('Details: alle Merker als Zeilen', () {
    final rows = daliDetailRows(const Dpt(237, 600), write('010C'));
    expect(
      [for (final r in rows) (r.label, r.value, r.flag, r.fault)],
      [
        ('Lampenfehler', 'gesetzt', true, true),
        ('EVG-Fehler', 'nicht gesetzt', false, true),
        ('Konverterfehler', 'nicht gesetzt', false, true),
        ('Adresse meint', 'Gerät', null, false),
        ('DALI-Adresse', '12', null, false),
        // A yes/no field looks like the flags, without the alarm colour.
        ('Abfrage an das Gateway', 'nicht gesetzt', false, false),
      ],
    );
    expect(daliDetailRows(const Dpt(245, 600), write('2540A801FE00')).last.value, '0 %');
    expect(
      daliDetailRows(const Dpt(245, 600), write('1140A801FE00')).map((r) => r.value),
      contains('510 min oder länger'),
    );
    // After a failed (here: stopped) duration test the discharge time says nothing: "—", not a value.
    final stopped = daliDetailRows(const Dpt(245, 600), write('2540A801FE00'));
    expect(stopped.firstWhere((r) => r.label == 'Entladedauer im letzten Dauertest').value, '—');
  });

  group('Prüfbuch: was ist ein neues Ergebnis', () {
    final t0 = DateTime(2026, 11, 1, 2);
    const ga = 0x5010;

    test('erstes Ergebnis je Art, gleiche Bytes zählen nicht doppelt', () {
      final tracker = EmergencyTracker();
      final first = tracker.result(ga, bytes('110054005CFF'), t0, gateway: 0x1128, address: 16);
      expect(
        [for (final e in first) (e.kind, e.result, e.minutes, e.first)],
        [
          (EmergencyTestKind.function, EmergencyResult.passed, null, true),
          (EmergencyTestKind.duration, EmergencyResult.passed, 92, true),
        ],
      );
      expect(first.first.raw, '110054005CFF');
      expect(tracker.result(ga, bytes('110054005CFF'), t0.add(const Duration(hours: 1))), isEmpty);
    });

    test('nur die geänderte Art ergibt einen Eintrag, mit Grund', () {
      final tracker = EmergencyTracker()..result(ga, bytes('110054005CFF'), t0);
      final next = tracker.result(ga, bytes('140054005CFF'), t0.add(const Duration(days: 7)));
      expect(next.single.kind, EmergencyTestKind.duration);
      expect(next.single.result, EmergencyResult.failed);
      expect(next.single.reasons, [EmergencyReason.delayExceeded]);
      expect(next.single.minutes, isNull);
      expect(next.single.first, isFalse);
    });

    test('gleiches Ergebnis nach einem gemeldeten Testlauf zählt neu, während des Tests nicht', () {
      final tracker = EmergencyTracker()..result(ga, bytes('110054005CFF'), t0);
      tracker.status(ga, decodeConverterStatus(bytes('7055'))!);
      // Still running: the old result repeated is nothing new, and the hint stays.
      expect(tracker.result(ga, bytes('110054005CFF'), t0.add(const Duration(days: 7))), isEmpty);
      tracker.status(ga, decodeConverterStatus(bytes('1055'))!);
      final again = tracker.result(ga, bytes('110054005CFF'), t0.add(const Duration(days: 7, minutes: 2)));
      expect(again.single.kind, EmergencyTestKind.function);
      expect(tracker.result(ga, bytes('110054005CFF'), t0.add(const Duration(days: 8))), isEmpty);
    });

    test('angekündigter Test (anstehend, dann nicht mehr) macht gleiche Bytes zu einem neuen Ergebnis', () {
      final tracker = EmergencyTracker()..result(ga, bytes('110054005CFF'), t0);
      tracker.status(ga, decodeConverterStatus(bytes('1095'))!); // function test pending
      tracker.status(ga, decodeConverterStatus(bytes('1055'))!); // no longer pending
      final again = tracker.result(ga, bytes('110054005CFF'), t0.add(const Duration(days: 7)));
      expect(again.single.kind, EmergencyTestKind.function);
    });

    test('Ergebnis eines fremden Absenders: eigener Vergleich, als fremd markiert, Status von ihm zählt nicht', () {
      final tracker = EmergencyTracker()..result(ga, bytes('130054005CFF'), t0, gateway: 0x1128, source: 0x1128);
      final forged = tracker.result(
        ga,
        bytes('110054005CFF'),
        t0.add(const Duration(hours: 2)),
        gateway: 0x1128,
        source: 0x7777,
      );
      expect(forged, isNotEmpty);
      expect(forged.every((e) => e.foreign && e.source == 0x7777 && e.gateway == 0x1128 && !e.counts), isTrue);
      // The gateway repeats its own result: not new, the forged one did not move its baseline.
      expect(
        tracker.result(ga, bytes('130054005CFF'), t0.add(const Duration(hours: 3)), gateway: 0x1128, source: 0x1128),
        isEmpty,
      );
      // A forged status "running, then normal" makes no unchanged result a new test.
      tracker
        ..status(ga, decodeConverterStatus(bytes('7055'))!, trusted: false)
        ..status(ga, decodeConverterStatus(bytes('1055'))!, trusted: false);
      expect(
        tracker.result(ga, bytes('130054005CFF'), t0.add(const Duration(hours: 5)), gateway: 0x1128, source: 0x1128),
        isEmpty,
      );
    });

    test('Flut: abwechselnde Werte ergeben je Testart höchstens einen Eintrag pro Stunde', () {
      final tracker = EmergencyTracker();
      var entries = 0;
      for (var i = 0; i < 52000; i++) {
        entries += tracker
            .result(ga, bytes(i.isEven ? '110054005CFF' : '330054005CFF'), t0.add(Duration(milliseconds: 25 * i)))
            .length;
      }
      // 52,000 telegrams in 22 minutes: two first entries, nothing more within the hour.
      expect(entries, 2);
      expect(tracker.suppressed, greaterThan(50000));
    });

    test('Jahresdatei: Überlaufzeile statt weiterer Einträge, nichts mehr danach; teilweise gelesen', () {
      final entry = EmergencyTracker().result(ga, bytes('110054005CFF'), t0);
      expect(emergencyLogChunk(0, entry, t0).overflow, isFalse);
      final full = emergencyLogChunk(emergencyLogMaxBytes - 10, entry, t0);
      expect((full.overflow, (jsonDecode(full.text.trim()) as Map)['overflow']), (true, true));
      expect(emergencyLogChunk(emergencyLogMaxBytes, entry, t0).text, isEmpty);
      final text = '${jsonEncode(entry.first.toJson())}\n${full.text}';
      final read = readEmergencyLog(text);
      expect((read.entries.length, read.overflow, read.truncated), (1, true, false));
      // A cut text: the incomplete last line is left out, the cut is visible.
      final cut = readEmergencyLog('${jsonEncode(entry.first.toJson())}\n{"t":1,', cut: true);
      expect((cut.entries.length, cut.truncated), (1, true));
    });

    test('Zeitstempel außerhalb des Bereichs: Zeile übersprungen statt Absturz', () {
      expect(
        EmergencyTest.fromJson({'t': 9000000000000000, 'ga': 1, 'k': 'function', 'r': 'passed', 'x': 'AA'}),
        isNull,
      );
    });

    test('nach Neustart aus dem Prüfbuch: bekannte Bytes sind nicht neu', () {
      final first = EmergencyTracker().result(ga, bytes('110054005CFF'), t0);
      final tracker = EmergencyTracker();
      first.forEach(tracker.seed);
      expect(tracker.result(ga, bytes('110054005CFF'), t0.add(const Duration(days: 1))), isEmpty);
    });

    test('Zeilen: hin und zurück, kaputte und fremde Zeilen werden übersprungen', () {
      final entries = EmergencyTracker().result(ga, bytes('140054005CFF'), t0, gateway: 0x1128, address: 16);
      final text = [
        for (final e in entries) jsonEncode(e.toJson()),
        '{"t": "gestern"}',
        'kein json',
        '[1,2,3]',
        '',
        '{"t":1,"ga":2,"k":"function","r":"passed","x":"${'A' * 3000}"}',
      ].join('\n');
      final read = parseEmergencyLog(text);
      expect(read.length, entries.length);
      expect(read.last.key, entries.last.key);
      expect(read.last.reasons, [EmergencyReason.delayExceeded]);
      expect(parseEmergencyLog(text, maxLines: 1).length, 1);
      expect(emergencyLogPath(2026), 'dali_tests/2026.ndjson');
    });
  });

  test('Die Kopie im Add-on-Server ist dieselbe Datei', () {
    expect(
      File('ha-addon/knx_monitor/server/lib/src/dali.dart').readAsStringSync(),
      File('lib/knx/dali.dart').readAsStringSync(),
    );
  });
}
