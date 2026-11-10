import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

    test('whole history as zip: one ETS file per day, readable by unzip', () async {
      File('${data.path}/history/$day.ndjson.gz').writeAsBytesSync(gzip.encode(utf8.encode('${lines.join('\n')}\n')));
      final later = DateTime(first.year, first.month, first.day + 2, 9);
      final laterDay = Recorder.dayName(later);
      File('${data.path}/history/$laterDay.ndjson').writeAsStringSync(
        '${jsonEncode({'t': later.microsecondsSinceEpoch, 's': 4402, 'd': 4096, 'y': 2, 'x': '01', 'm': true})}\n',
      );
      final bytes = BytesBuilder();
      final count = await writeEtsZip(recorder, (b) async => bytes.add(b));
      expect(count, lines.length + 1);
      final file = File('${data.path}/all.zip')..writeAsBytesSync(bytes.takeBytes());

      final test = await Process.run('unzip', ['-t', file.path]);
      expect(test.exitCode, 0, reason: '${test.stdout}${test.stderr}');
      final list = await Process.run('unzip', ['-Z1', file.path]);
      expect(const LineSplitter().convert(list.stdout as String), [
        'knx-monitor-$day.xml',
        'knx-monitor-$laterDay.xml',
      ]);
      final content = await Process.run('unzip', ['-p', file.path, 'knx-monitor-$day.xml'], stdoutEncoding: utf8);
      expect(content.stdout, expected);
    });

    test('nur ein Export zur Zeit: der zweite bekommt 429', () async {
      // Enough history that the first download blocks while nobody reads it.
      final big = [
        for (var i = 0; i < 60000; i++)
          jsonEncode({
            't': first.microsecondsSinceEpoch + i * 1000,
            's': 4402,
            'd': 4096 + i % 50,
            'y': 2,
            'x': '0c33',
          }),
      ];
      File('${data.path}/history/$day.ndjson').writeAsStringSync('${big.join('\n')}\n');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) => serveEtsXml(r, recorder));
      final uri = Uri.parse('http://127.0.0.1:${server.port}$etsXmlPath?all=1');
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
      socket.write('GET ${uri.path}?all=1 HTTP/1.1\r\nHost: x\r\n\r\n');
      // The first export runs; its answer is not read.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final client = HttpClient();
      final second = await (await client.getUrl(uri)).close();
      expect(second.statusCode, HttpStatus.tooManyRequests);
      expect(second.headers.value(HttpHeaders.retryAfterHeader), '30');
      await second.drain<void>();
      // The check without a body goes through meanwhile.
      final check = await (await client.getUrl(uri.replace(query: 'check=1&from=0&to=1'))).close();
      expect(check.statusCode, isNot(HttpStatus.tooManyRequests));
      await check.drain<void>();
      socket.destroy();
      client.close(force: true);
      await server.close(force: true);
    });

    test('crc32 like zlib', () {
      expect(crc32(utf8.encode('123456789')), 0xCBF43926);
      expect(crc32(utf8.encode('6789'), crc32(utf8.encode('12345'))), 0xCBF43926);
    });

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
