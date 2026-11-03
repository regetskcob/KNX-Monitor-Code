import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

/// ETS file from the history. The fixture `history.xml` was written by the
/// app's `buildEtsXml` from `history.ndjson`; the app test
/// (`test/telegram_files_test.dart`) checks that it still writes exactly that.
void main() {
  final fixtures = 'test/fixtures/ets_xml';
  final lines = File('$fixtures/history.ndjson').readAsLinesSync();
  final expected = File('$fixtures/history.xml').readAsStringSync();

  test('gleiches Format wie die App (Fixture aus buildEtsXml)', () {
    expect(etsXmlOf(lines), expected);
  });

  group('aus dem Verlauf', () {
    late Directory data;
    late Recorder recorder;
    // Local days like the recorder; fixture times are 14.10.2026 around 13:20 UTC.
    final first = DateTime.fromMicrosecondsSinceEpoch(1791984001234000);
    final day = Recorder.dayName(first);

    setUp(() {
      data = Directory.systemTemp.createTempSync('ets_xml');
      Directory('${data.path}/history').createSync();
      recorder = Recorder(data);
    });
    tearDown(() => data.deleteSync(recursive: true));

    Future<String> export(DateTime from, DateTime to) async {
      final out = StringBuffer();
      await writeEtsXml(recorder, from, to, (chunk) async => out.write(chunk));
      return out.toString();
    }

    final dayStart = DateTime(first.year, first.month, first.day);
    final dayEnd = DateTime(first.year, first.month, first.day + 1);

    test('gepackt, ungeordnet und mit kaputter Zeile: wie die App', () async {
      // Day packed, plus an open part; one line out of order, one truncated.
      File('${data.path}/history/$day.ndjson.gz')
          .writeAsBytesSync(gzip.encode(utf8.encode('${lines.take(3).join('\n')}\n')));
      File('${data.path}/history/$day.ndjson').writeAsStringSync('${lines.skip(3).join('\n')}\n{"t":17919840\n');
      expect(await export(dayStart, dayEnd), expected);
    });

    test('Zeitraum schneidet ab, Nachbartage zählen mit', () async {
      File('${data.path}/history/$day.ndjson').writeAsStringSync('${lines.join('\n')}\n');
      final next = DateTime(first.year, first.month, first.day + 1, 12);
      final nextLine = jsonEncode({
        't': next.microsecondsSinceEpoch,
        's': 4402,
        'd': 4096,
        'y': 2,
        'x': '01',
        'm': true,
        'r': '2900BCE011321000010081',
      });
      File('${data.path}/history/${Recorder.dayName(next)}.ndjson').writeAsStringSync('$nextLine\n');
      // From the second telegram (13:20:02 UTC) to the end of the next day.
      final xml = await export(
        DateTime.fromMicrosecondsSinceEpoch(1791984002000000),
        DateTime(first.year, first.month, first.day + 2),
      );
      expect(RegExp('<Telegram ').allMatches(xml), hasLength(5));
      expect(xml, contains('<RecordStart Timestamp="2026-10-14T13:20:02.000Z"'));
      expect(xml, isNot(contains('2026-10-14T13:20:01.234Z')));
      expect(xml, contains('<RecordStop Timestamp="${next.toUtc().toIso8601String()}"/>'));
    });

    test('leerer Zeitraum: gültige Datei ohne Telegramme', () async {
      final xml = await export(dayStart, dayEnd);
      expect(xml, startsWith('<?xml version="1.0" encoding="utf-8"?>\n<CommunicationLog xmlns="$etsNamespace">'));
      expect(xml, contains('<RecordStart '));
      expect(xml, isNot(contains('<Telegram ')));
      expect(xml, endsWith('</CommunicationLog>'));
    });

    test('großer Tag geht in Stücken hinaus', () async {
      final sink = File('${data.path}/history/$day.ndjson').openWrite();
      for (var i = 0; i < 5000; i++) {
        sink.writeln(lines[1].replaceFirst('1791984001234000', '${1791984001234000 + i}'));
      }
      await sink.close();
      final chunks = <String>[];
      final count = await writeEtsXml(recorder, dayStart, dayEnd, (c) async => chunks.add(c));
      expect(count, 5000);
      expect(chunks.length, greaterThan(1));
      expect(chunks.join(), endsWith('</CommunicationLog>'));
    });
  });

  test('Host wird als Attribut maskiert', () {
    expect(etsXmlOf(lines, host: 'a"b<c&d'), contains('Host="a&quot;b&lt;c&amp;d"'));
  });

  group('Parameter', () {
    String? error;
    ({DateTime from, DateTime to})? range(Map<String, String> q) {
      error = null;
      return etsXmlRange(q, onError: (e) => error = e);
    }

    test('gültig', () {
      final r = range({'from': '1000', 'to': '2000'})!;
      expect(r.from.millisecondsSinceEpoch, 1000);
      expect(r.to.millisecondsSinceEpoch, 2000);
    });

    test('fehlend, verdreht, zu lang', () {
      expect(range({}), isNull);
      expect(range({'from': 'x', 'to': '2'}), isNull);
      expect(range({'from': '2000', 'to': '2000'}), isNull);
      expect(range({'from': '2000', 'to': '1000'}), isNull);
      expect(range({'from': '0', 'to': '${const Duration(days: 31).inMilliseconds + 1}'}), isNull);
      expect(error, contains('31'));
      expect(range({'from': '0', 'to': '${const Duration(days: 31).inMilliseconds}'}), isNotNull);
    });

    test('outside the range of DateTime: an error, not an exception', () {
      expect(range({'from': '1000000000000000000', 'to': '1000000000000000001'}), isNull);
      expect(error, isNotNull);
    });
  });
}
