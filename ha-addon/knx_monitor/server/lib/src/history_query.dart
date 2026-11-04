/// Telegrams of a few group addresses over a longer period, for the app's
/// charts (Diagramme › period). The app itself keeps only the latest telegrams
/// in memory; for "7 days" it asks here instead.
///
/// `GET /api/bus/telegrams?a=<address>[:<main>.<sub>],…&from=<ms>&to=<ms>[&installation=<id>]`
///
/// Answer: `{from, to, telegrams: {"<address>": [history line, …]}}`, lines
/// as the recorder writes them (the app reads them with `Telegram.fromJson`),
/// oldest first. Per address the last value before `from` comes first, so the
/// chart starts with the state at the left edge. Reads are left out.
///
/// Thinned per address to about [maxPerAddress] lines: a value repeated
/// unchanged is dropped (only the first of a run counts, plus the last before
/// a change), and if that is still too many, each time column keeps its first,
/// last, lowest and highest value – peaks stay visible.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'dpt_value.dart';
import 'recorder.dart';

const historyTelegramsPath = '/api/bus/telegrams';

/// Longest period of one query.
const historyMaxRange = Duration(days: 31);

/// Most addresses of one query (a chart has at most 8 series).
const historyMaxAddresses = 12;

const maxPerAddress = 4000;

/// Query parameters; a message if they are invalid.
({Map<int, (int, int?)?> addresses, DateTime from, DateTime to})? historyQuery(
  Map<String, String> q, {
  void Function(String error)? onError,
}) {
  final from = int.tryParse(q['from'] ?? '');
  final to = int.tryParse(q['to'] ?? '');
  final addresses = <int, (int, int?)?>{};
  for (final part in (q['a'] ?? '').split(',').where((p) => p.isNotEmpty)) {
    final [address, ...dpt] = part.split(':');
    final a = int.tryParse(address);
    if (a == null || a < 0 || a > 0xFFFF) {
      onError?.call('Adresse ungültig: $address');
      return null;
    }
    final d = dpt.isEmpty ? null : dpt.first.split('.').map(int.tryParse).toList();
    addresses[a] = switch (d) {
      [final main?] => (main, null),
      [final main?, final sub] => (main, sub),
      _ => null,
    };
  }
  String? error;
  if (addresses.isEmpty) {
    error = 'Keine Adresse.';
  } else if (addresses.length > historyMaxAddresses) {
    error = 'Höchstens $historyMaxAddresses Adressen.';
  } else if (from == null || to == null || from < 0 || to <= from || to > 8640000000000000) {
    error = 'from und to (Millisekunden) fehlen oder sind verdreht.';
  } else if (to - from > historyMaxRange.inMilliseconds) {
    error = 'Höchstens ${historyMaxRange.inDays} Tage.';
  }
  if (error != null) {
    onError?.call(error);
    return null;
  }
  return (
    addresses: addresses,
    from: DateTime.fromMillisecondsSinceEpoch(from!),
    to: DateTime.fromMillisecondsSinceEpoch(to!),
  );
}

/// Lines of [addresses] between [from] and [to], see the library comment.
Future<Map<int, List<Map<String, Object?>>>> historyTelegrams(
  Recorder recorder,
  Map<int, (int, int?)?> addresses,
  DateTime from,
  DateTime to, {
  int max = maxPerAddress,
}) async {
  final start = from.microsecondsSinceEpoch;
  final end = to.microsecondsSinceEpoch;
  final inRange = {for (final a in addresses.keys) a: <Map<String, Object?>>[]};
  final before = <int, Map<String, Object?>>{};
  // The day before as well: the value at the left edge, also shortly after midnight.
  for (
    var d = DateTime(from.year, from.month, from.day - 1);
    !d.isAfter(to);
    d = DateTime(d.year, d.month, d.day + 1)
  ) {
    final lines = await recorder.dayLines(Recorder.dayName(d));
    if (lines == null) continue;
    await for (final line in lines) {
      // Cheap filters first: most lines belong to other addresses.
      final a = int.tryParse(Recorder.field(line, 'd') ?? '');
      if (a == null || !inRange.containsKey(a)) continue;
      final t = int.tryParse(Recorder.field(line, 't') ?? '');
      if (t == null || t > end || Recorder.field(line, 'y') == '0') continue;
      final Map<String, Object?> j;
      try {
        j = jsonDecode(line) as Map<String, Object?>;
      } on FormatException {
        continue; // truncated line
      }
      if (t < start) {
        final previous = before[a];
        if (previous == null || (previous['t']! as int) < t) before[a] = j;
      } else {
        inRange[a]!.add(j);
      }
    }
  }
  // Addresses quiet for longer: further back, day by day, until each has its
  // value at the edge or the history ends.
  final missing = {
    for (final a in addresses.keys)
      if (!before.containsKey(a)) a,
  };
  final first = (await recorder.usage())['first'] as String?;
  if (missing.isNotEmpty && first != null) {
    final oldest = DateTime.parse(first);
    for (
      var d = DateTime(from.year, from.month, from.day - 2);
      missing.isNotEmpty && !d.isBefore(oldest);
      d = DateTime(d.year, d.month, d.day - 1)
    ) {
      final lines = await recorder.dayLines(Recorder.dayName(d));
      if (lines == null) continue;
      final found = <int, Map<String, Object?>>{};
      await for (final line in lines) {
        final a = int.tryParse(Recorder.field(line, 'd') ?? '');
        if (a == null || !missing.contains(a) || Recorder.field(line, 'y') == '0') continue;
        final t = int.tryParse(Recorder.field(line, 't') ?? '');
        if (t == null || (found[a] != null && (found[a]!['t']! as int) >= t)) continue;
        try {
          found[a] = jsonDecode(line) as Map<String, Object?>;
        } on FormatException {
          // truncated line
        }
      }
      before.addAll(found);
      missing.removeAll(found.keys);
    }
  }
  return {
    for (final MapEntry(key: a, value: lines) in inRange.entries)
      a: thinLines([?before[a], ...lines..sort(_byTime)], addresses[a], start, end, max),
  };
}

int _byTime(Map<String, Object?> a, Map<String, Object?> b) => (a['t']! as int).compareTo(b['t']! as int);

/// See the library comment; [lines] sorted by time.
List<Map<String, Object?>> thinLines(
  List<Map<String, Object?>> lines,
  (int, int?)? dpt,
  int startMicros,
  int endMicros,
  int max,
) {
  if (lines.length <= max) return lines;
  // Runs of the same value: keep the first and the last before a change, so a
  // step line still changes at the right time.
  final changes = <Map<String, Object?>>[];
  for (var i = 0; i < lines.length; i++) {
    final x = lines[i]['x'];
    final prev = i > 0 ? lines[i - 1]['x'] : null;
    final next = i + 1 < lines.length ? lines[i + 1]['x'] : null;
    if (i == 0 || i == lines.length - 1 || x != prev || x != next) changes.add(lines[i]);
  }
  if (changes.length <= max) return changes;
  double? value(Map<String, Object?> j) => numericValue(dpt, hexBytes(j['x'] as String? ?? ''), small: j['m'] == true);
  final buckets = math.max(1, max ~/ 4);
  // Columns over the time that has data, not the asked period: with only a
  // week of history, 30 days would otherwise be coarser than 7 for the same week.
  final firstInRange = changes.firstWhere((j) => (j['t']! as int) >= startMicros, orElse: () => changes.last);
  startMicros = math.max(startMicros, firstInRange['t']! as int);
  endMicros = math.min(endMicros, changes.last['t']! as int);
  final span = math.max(1, endMicros - startMicros);
  final out = <Map<String, Object?>>[];
  var i = 0;
  // The value before the period stays in front.
  if ((changes.first['t']! as int) < startMicros) out.add(changes[i++]);
  for (var b = 0; b < buckets && i < changes.length; b++) {
    final limit = startMicros + span * (b + 1) ~/ buckets;
    final bucket = <Map<String, Object?>>[];
    while (i < changes.length && ((changes[i]['t']! as int) <= limit || b == buckets - 1)) {
      bucket.add(changes[i++]);
    }
    if (bucket.isEmpty) continue;
    final keep = <Map<String, Object?>>{bucket.first, bucket.last};
    Map<String, Object?>? lo, hi;
    double? loV, hiV;
    for (final j in bucket) {
      final v = value(j);
      if (v == null) continue;
      if (loV == null || v < loV) (lo, loV) = (j, v);
      if (hiV == null || v > hiV) (hi, hiV) = (j, v);
    }
    keep.addAll([?lo, ?hi]);
    out.addAll(bucket.where(keep.contains));
  }
  return out;
}

/// Answers [historyTelegramsPath]. Read access like `/api/bus/stats`; the
/// caller checks access and installation.
Future<void> serveHistoryTelegrams(HttpRequest request, Recorder recorder) async {
  final response = request.response;
  String? error;
  final query = historyQuery(request.uri.queryParameters, onError: (e) => error = e);
  if (query == null) {
    response
      ..statusCode = HttpStatus.badRequest
      ..headers.contentType = ContentType.text
      ..write(error);
    return response.close();
  }
  await recorder.flush();
  final result = await historyTelegrams(recorder, query.addresses, query.from, query.to);
  response.headers
    ..contentType = ContentType.json
    ..set(HttpHeaders.cacheControlHeader, 'no-store');
  response.write(
    jsonEncode({
      'from': query.from.millisecondsSinceEpoch,
      'to': query.to.millisecondsSinceEpoch,
      'telegrams': {for (final MapEntry(:key, :value) in result.entries) '$key': value},
    }),
  );
  await response.close();
}
