/// History as an ETS group monitor file (`CommunicationLog` XML).
///
/// Home Assistant's KNX integration (library knx-telegram-store) and
/// SpectrumKNX read and write this format, as does the ETS itself. The output
/// is byte for byte what the app's `buildEtsXml` (`lib/export/telegram_files.dart`)
/// writes for the same telegrams; `test/ets_xml_test.dart` here and
/// `test/telegram_files_test.dart` in the app compare both against the same
/// fixture (`test/fixtures/ets_xml/`). Apply format changes in both places.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:knx/knx.dart';

import 'recorder.dart';
import 'zip_stream.dart';

/// Namespace of the ETS telegram format.
const etsNamespace = 'http://knx.org/xml/telegrams/01';

/// `GET /api/export/ets-xml?from=<ms>&to=<ms>[&installation=<id>]`, or with
/// `all=1` instead of `from`/`to` the whole history as a zip ([writeEtsZip]).
const etsXmlPath = '/api/export/ets-xml';

/// Longest period one download may cover.
const etsXmlMaxRange = Duration(days: 31);

/// Timestamp like the app: UTC, ISO 8601 with milliseconds (and microseconds
/// if there are any), `Z`.
String etsTimestamp(int micros) => DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true).toIso8601String();

/// Attribute value in double quotes, escaped like package:xml does it.
String _attr(String value) => value.replaceAllMapped(
  RegExp('["&<\n\r\t\u0001-\u0008\u000b\u000c\u000e-\u001f\u007f-\u0084\u0086-\u009f]'),
  (m) => switch (m[0]!) {
    '"' => '&quot;',
    '&' => '&amp;',
    '<' => '&lt;',
    final c => '&#x${c.codeUnitAt(0).toRadixString(16).toUpperCase()};',
  },
);

/// XML declaration, root element and `RecordStart` (time of the first telegram).
String etsXmlHeader(int firstMicros, {String? host}) =>
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<CommunicationLog xmlns="$etsNamespace">\n'
    '  <RecordStart Timestamp="${etsTimestamp(firstMicros)}" Mode="LinkLayer" Host="${_attr(host ?? 'KNX Monitor')}" '
    'ConnectionName="KNX Monitor" ConnectorType="KnxIpTunneling" MediumType="TP"/>\n';

/// `RecordStop` (time of the last telegram) and the end of the document,
/// without a final line break (like the app).
String etsXmlFooter(int lastMicros) => '  <RecordStop Timestamp="${etsTimestamp(lastMicros)}"/>\n</CommunicationLog>';

/// One history line (`recorder.dart`, the app's `Telegram.toJson()`) as a
/// `Telegram` element with its line break, together with its time; `null` for
/// lines that are not a readable telegram.
({int time, String xml})? etsXmlTelegram(String line) {
  final Object? decoded;
  try {
    decoded = jsonDecode(line);
  } on FormatException {
    return null; // truncated line after a power failure
  }
  if (decoded is! Map<String, Object?>) return null;
  final cemi = cemiOfLine(decoded);
  final t = decoded['t'];
  if (cemi == null || t is! int) return null;
  final service = decoded['o'] == true ? 'L_Data.con' : 'L_Data.ind';
  return (
    time: t,
    xml:
        '  <Telegram Timestamp="${etsTimestamp(t)}" Service="$service" FrameFormat="CommonEmi" '
        'RawData="${hexOf(cemi)}"/>\n',
  );
}

/// cEMI frame of a history line: the recorded `r`, otherwise rebuilt from the
/// fields exactly like the app's `cemiOf` (lines without `r` came from older
/// versions or from the app).
Uint8List? cemiOfLine(Map<String, Object?> j) {
  final raw = j['r'];
  if (raw is String) {
    final bytes = parseHex(raw);
    if (bytes != null) return Uint8List.fromList(bytes);
  }
  final (s, d, y) = (j['s'], j['d'], j['y']);
  if (s is! int || d is! int || y is! int || y < 0 || y > 2) return null;
  final x = j['x'];
  final data = (x is String ? parseHex(x) : null) ?? const <int>[];
  final outgoing = j['o'] == true;
  final priority = (j['p'] as int? ?? 3) & 0x03;
  final hop = j['h'] as int? ?? 6;
  final apci = const [0x00, 0x40, 0x80][y];
  final ctrl1 = 0x80 | (j['rp'] == true ? 0x00 : 0x20) | 0x10 | (priority << 2) | (j['ce'] == true ? 0x01 : 0);
  final small = j['m'] == true || y == 0;
  return Uint8List.fromList([
    outgoing ? 0x2E : 0x29,
    0x00,
    ctrl1,
    0x80 | ((hop & 0x07) << 4),
    (s >> 8) & 0xFF,
    s & 0xFF,
    (d >> 8) & 0xFF,
    d & 0xFF,
    if (small) ...[
      1,
      0x00,
      apci | ((data.isEmpty ? 0 : data[0]) & 0x3F),
    ] else ...[
      1 + data.length,
      0x00,
      apci,
      ...data,
    ],
  ]);
}

/// Whole document from history lines, sorted by time like the app. For small
/// amounts and tests; the endpoint streams with [writeEtsXml].
String etsXmlOf(Iterable<String> lines, {String? host, DateTime Function()? now}) {
  final items = [for (final l in lines) ?etsXmlTelegram(l)]..sort((a, b) => a.time.compareTo(b.time));
  final fallback = (now ?? DateTime.now)().microsecondsSinceEpoch;
  return [
    etsXmlHeader(items.isEmpty ? fallback : items.first.time, host: host),
    for (final i in items) i.xml,
    etsXmlFooter(items.isEmpty ? fallback : items.last.time),
  ].join();
}

/// Writes the telegrams of [recorder] in `[from, to)` as an ETS file to [emit],
/// day by day, without holding the whole period in memory. Returns the number
/// of telegrams.
///
/// Each day is read twice: first only the times (first telegram for
/// `RecordStart`, whether the day is in order), then the telegrams. A day out of
/// order (clock corrected later, see [Recorder.retime]) is sorted in memory;
/// usually the lines go straight through.
Future<int> writeEtsXml(
  Recorder recorder,
  DateTime from,
  DateTime to,
  Future<void> Function(String chunk) emit, {
  String? host,
  DateTime Function()? now,
}) async {
  final start = from.microsecondsSinceEpoch;
  final end = to.microsecondsSinceEpoch;
  bool inRange(int t) => t >= start && t < end;
  int? first;
  int? last;
  var count = 0;
  final buffer = StringBuffer();
  Future<void> write(String text) async {
    buffer.write(text);
    if (buffer.length < 64 * 1024) return;
    final chunk = buffer.toString();
    buffer.clear();
    await emit(chunk);
  }

  final lastDay = to.subtract(const Duration(microseconds: 1));
  for (
    var day = DateTime(from.year, from.month, from.day);
    !day.isAfter(lastDay);
    day = DateTime(day.year, day.month, day.day + 1)
  ) {
    final name = Recorder.dayName(day);
    // Pass 1: times only, without decoding the lines.
    var inDay = 0;
    var sorted = true;
    int? previous;
    int? dayFirst;
    await for (final line in await recorder.dayLines(name) ?? const Stream<String>.empty()) {
      final t = int.tryParse(Recorder.field(line, 't') ?? '');
      if (t == null || !inRange(t)) continue;
      if (previous != null && t < previous) sorted = false;
      previous = t;
      if (dayFirst == null || t < dayFirst) dayFirst = t;
      inDay++;
    }
    if (inDay == 0) continue;
    if (first == null) {
      first = dayFirst!;
      await write(etsXmlHeader(first, host: host));
    }
    // Pass 2: the telegrams.
    final lines = await recorder.dayLines(name) ?? const Stream<String>.empty();
    final unsorted = <({int time, String xml})>[];
    await for (final line in lines) {
      final t = int.tryParse(Recorder.field(line, 't') ?? '');
      if (t == null || !inRange(t)) continue;
      final item = etsXmlTelegram(line);
      if (item == null) continue;
      if (sorted) {
        await write(item.xml);
      } else {
        unsorted.add(item);
      }
      if (last == null || item.time > last) last = item.time;
      count++;
    }
    unsorted.sort((a, b) => a.time.compareTo(b.time));
    for (final item in unsorted) {
      await write(item.xml);
    }
  }
  final fallback = (now ?? DateTime.now)().microsecondsSinceEpoch;
  if (first == null) await write(etsXmlHeader(fallback, host: host));
  await write(etsXmlFooter(last ?? first ?? fallback));
  if (buffer.isNotEmpty) await emit(buffer.toString());
  return count;
}

/// Days of the history from the first to the last (`YYYY-MM-DD`), including
/// the days between without a file; empty without history.
Future<List<String>> historyDays(Recorder recorder) async {
  final first = (await recorder.usage())['first'] as String?;
  if (first == null) return const [];
  final start = DateTime.parse(first);
  final today = DateTime.now();
  return [for (var d = start; !d.isAfter(today); d = DateTime(d.year, d.month, d.day + 1)) Recorder.dayName(d)];
}

/// Writes the whole history of [recorder] as a zip with one ETS file per day
/// (`knx-monitor-YYYY-MM-DD.xml`) to [emit]. SpectrumKNX imports such a zip in
/// one go; each file is also a regular ETS group monitor file. Days without
/// telegrams are left out. Returns the number of telegrams.
Future<int> writeEtsZip(Recorder recorder, Future<void> Function(List<int> bytes) emit, {String? host}) async {
  final zip = ZipStream(emit);
  var count = 0;
  for (final day in await historyDays(recorder)) {
    if (await recorder.dayLines(day) == null) continue;
    final from = DateTime.parse(day);
    final to = DateTime(from.year, from.month, from.day + 1);
    await zip.add('knx-monitor-$day.xml', from, (write) async {
      count += await writeEtsXml(recorder, from, to, write, host: host);
    });
  }
  await zip.close();
  return count;
}

/// Largest millisecond value a [DateTime] accepts.
const _maxEpochMs = 8640000000000000;

/// Parameters of [etsXmlPath]; a message if they are invalid.
({DateTime from, DateTime to})? etsXmlRange(Map<String, String> query, {void Function(String error)? onError}) {
  final from = int.tryParse(query['from'] ?? '');
  final to = int.tryParse(query['to'] ?? '');
  String? error;
  if (from == null || to == null) {
    error = 'from und to (Millisekunden) fehlen.';
  } else if (from < 0 || to <= from) {
    error = 'to muss nach from liegen.';
  } else if (to > _maxEpochMs) {
    error = 'Zeitraum ungültig.';
  } else if (to - from > etsXmlMaxRange.inMilliseconds) {
    error = 'Höchstens ${etsXmlMaxRange.inDays} Tage.';
  }
  if (error != null) {
    onError?.call(error);
    return null;
  }
  return (from: DateTime.fromMillisecondsSinceEpoch(from!), to: DateTime.fromMillisecondsSinceEpoch(to!));
}

/// Answers [etsXmlPath] with the history of [recorder] as a download. Read
/// access like `/api/bus/stats`; the caller checks access and installation.
Future<void> serveEtsXml(HttpRequest request, Recorder recorder, {String? host}) async {
  final response = request.response;
  if (request.method != 'GET') {
    response.statusCode = HttpStatus.methodNotAllowed;
    return response.close();
  }
  if (request.uri.queryParameters['all'] == '1') return _serveEtsZip(request, recorder, host: host);
  String? error;
  final range = etsXmlRange(request.uri.queryParameters, onError: (e) => error = e);
  if (range == null) {
    response
      ..statusCode = HttpStatus.badRequest
      ..headers.contentType = ContentType.text
      ..write(error);
    return response.close();
  }
  // `check=1`: same checks, no body. The browser asks first, because a plain
  // download link would save an error message as the file.
  if (request.uri.queryParameters['check'] == '1') {
    response.statusCode = HttpStatus.noContent;
    return response.close();
  }
  return serveEtsXmlRange(request, recorder, range.from, range.to, host: host);
}

/// The ETS file of `[from, to)` as a download (checked range).
Future<void> serveEtsXmlRange(
  HttpRequest request,
  Recorder recorder,
  DateTime from,
  DateTime to, {
  String? host,
}) async {
  final response = request.response;
  // What is still in the buffer belongs to the download.
  await recorder.flush();
  final lastDay = Recorder.dayName(to.subtract(const Duration(microseconds: 1)));
  final name = 'knx-monitor-${Recorder.dayName(from)}-$lastDay.xml';
  response.headers
    ..contentType = ContentType('application', 'xml', charset: 'utf-8')
    ..set(HttpHeaders.cacheControlHeader, 'no-store')
    ..set('Content-Disposition', 'attachment; filename="$name"');
  await writeEtsXml(recorder, from, to, (chunk) async {
    response.add(utf8.encode(chunk));
    await response.flush();
  }, host: host);
  await response.close();
}

Future<void> _serveEtsZip(HttpRequest request, Recorder recorder, {String? host}) async {
  final response = request.response;
  await recorder.flush();
  final days = await historyDays(recorder);
  if (days.isEmpty) {
    response
      ..statusCode = HttpStatus.badRequest
      ..headers.contentType = ContentType.text
      ..write('Noch kein Verlauf aufgezeichnet.');
    return response.close();
  }
  if (request.uri.queryParameters['check'] == '1') {
    response.statusCode = HttpStatus.noContent;
    return response.close();
  }
  response.headers
    ..contentType = ContentType('application', 'zip')
    ..set(HttpHeaders.cacheControlHeader, 'no-store')
    ..set('Content-Disposition', 'attachment; filename="knx-monitor-${days.first}-${days.last}.zip"');
  await writeEtsZip(recorder, (bytes) async {
    response.add(bytes);
    await response.flush();
  }, host: host);
  await response.close();
}
