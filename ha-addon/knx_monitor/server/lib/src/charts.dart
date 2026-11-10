import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'dpt_value.dart';
import 'recorder.dart';
import 'report.dart' show busySeconds;

/// The app's saved charts as history for the dashboard card
/// (`knx-monitor-chart-card`, see [LovelaceCard]).
///
/// The app stores them as `charts.json` next to the project (`SavedCharts` in
/// `lib/model/saved_charts.dart`): per chart the series with address, name,
/// DPT, unit and switch labels in the app's language. The values come from the
/// [Recorder]'s daily history, converted as in the app and thinned out to at
/// most two points per column ([thin]).
class ChartService {
  ChartService({this.cacheDays = 40});

  /// This many completed days stay loaded in memory (per day only the
  /// requested addresses) – cards poll every minute.
  final int cacheDays;

  final _cache = <String, _Day>{};

  static const fileName = 'charts.json';

  /// Columns that [series] thins out to (roughly the width of a card in pixels).
  static const buckets = 400;

  /// Longest time span of a query.
  static const maxHours = 24 * 31;

  /// Charts of the installation in [root], without values: name and series.
  Future<Map<String, Object?>> list(Directory root) async {
    final json = await _read(root);
    return {
      'allowed': json?['allowed'] != false,
      'charts': [
        for (final c in _charts(json))
          {
            'name': c['name'],
            'series': [for (final s in _seriesOf(c)) _describe(s)],
          },
      ],
    };
  }

  /// History of the chart [name] over the last [hours] hours; `null` if the
  /// chart does not exist.
  Future<Map<String, Object?>?> series(
    Directory root,
    Recorder recorder,
    String name, {
    int hours = 24,
    DateTime? now,
  }) async {
    final json = await _read(root);
    final chart = _charts(json).where((c) => c['name'] == name).firstOrNull;
    if (chart == null) return null;
    final to = now ?? DateTime.now();
    final from = to.subtract(Duration(hours: hours.clamp(1, maxHours)));
    final allowed = json?['allowed'] != false;
    final result = <String, Object?>{
      'name': name,
      'allowed': allowed,
      'from': from.millisecondsSinceEpoch,
      'to': to.millisecondsSinceEpoch,
    };
    // Without the unlock, only the description and no values.
    final defs = _seriesOf(chart).toList();
    if (!allowed)
      return {
        ...result,
        'series': [for (final s in defs) _describe(s)],
      };
    await recorder.flush();
    bool isMetric(Map<String, Object?> s) => s['metric'] is String;
    final addresses = {
      for (final s in defs)
        if (!isMetric(s)) s['address']! as int,
    };
    final raw = await _raw(recorder, addresses, from, to);
    final minutes = defs.any(isMetric) ? await _perMinute(recorder, from, to) : null;
    return {
      ...result,
      'series': [
        for (final s in defs)
          if (isMetric(s))
            _withRates(s, minutes!, from, to)
          else
            _withPoints(s, raw[s['address']] ?? const [], from, to),
      ],
    };
  }

  /// Metric (`metric`: `telegrams`, `repeats`, `line` with `line`) as
  /// telegrams per minute, `load` as the share of time the line was busy in
  /// percent, in at most [buckets] columns.
  Map<String, Object?> _withRates(Map<String, Object?> s, _Minutes minutes, DateTime from, DateTime to) {
    final load = s['metric'] == 'load';
    final counts = switch (s['metric']) {
      'load' => minutes.busyMs,
      'telegrams' => minutes.telegrams,
      'repeats' => minutes.repeats,
      'line' => minutes.lines[s['line']] ?? List.filled(minutes.telegrams.length, 0),
      _ => List.filled(minutes.telegrams.length, 0),
    };
    final per = math.max(1, (counts.length / buckets).ceil());
    final start = minutes.start.millisecondsSinceEpoch;
    final end = to.millisecondsSinceEpoch;
    final points = <List<num>>[];
    for (var i = 0; i < counts.length; i += per) {
      final at = start + i * 60000;
      final sum = counts.skip(i).take(per).fold(0, (a, b) => a + b);
      // The last, incomplete column is scaled by the elapsed time.
      final span = math.min(per * 60000, end - at);
      final value = load ? sum / math.max(span, 10000) * 100 : sum / (math.max(span, 10000) / 60000);
      points.add([at, double.parse(value.toStringAsFixed(2))]);
    }
    return {..._describe(s), 'kind': 'line', 'points': points, if (points.isNotEmpty) 'last': points.last};
  }

  /// Telegrams per minute from [from] to [to]: total, repeated and per line of
  /// the sender. Completed days come from memory, as in [_raw].
  Future<_Minutes> _perMinute(Recorder recorder, DateTime from, DateTime to) async {
    final start = DateTime(from.year, from.month, from.day, from.hour, from.minute);
    final n = to.difference(start).inMinutes + 1;
    final out = _Minutes(start, n);
    for (var d = DateTime(from.year, from.month, from.day); !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
      final name = Recorder.dayName(d);
      final settled = DateTime(d.year, d.month, d.day + 1, 1).isBefore(to);
      final day = settled ? await _cachedMinutes(recorder, name, d) : await _scanMinutes(recorder, name, d);
      out.add(day);
    }
    return out;
  }

  final _minuteCache = <String, _Minutes>{};

  Future<_Minutes> _cachedMinutes(Recorder recorder, String name, DateTime day) async {
    final key = '${recorder.data.path}|$name';
    final hit = _minuteCache[key];
    if (hit != null) return hit;
    final minutes = await _scanMinutes(recorder, name, day);
    _minuteCache[key] = minutes;
    while (_minuteCache.length > cacheDays) {
      _minuteCache.remove(_minuteCache.keys.first);
    }
    return minutes;
  }

  static Future<_Minutes> _scanMinutes(Recorder recorder, String name, DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final out = _Minutes(start, DateTime(day.year, day.month, day.day + 1).difference(start).inMinutes);
    final lines = await recorder.dayLines(name);
    if (lines == null) return out;
    await for (final line in lines) {
      final t = int.tryParse(Recorder.field(line, 't') ?? '');
      if (t == null) continue;
      final i = (t ~/ 1000 - start.millisecondsSinceEpoch) ~/ 60000;
      if (i < 0 || i >= out.telegrams.length) continue;
      out.telegrams[i]++;
      if (line.contains('"rp":true')) out.repeats[i]++;
      out.busyMs[i] += (busySeconds(_payload(line), small: line.contains('"m":true')) * 1000).round();
      if (!line.contains('"o":true')) {
        final src = int.tryParse(Recorder.field(line, 's') ?? '');
        if (src != null) (out.lines[src >> 8] ??= List.filled(out.telegrams.length, 0))[i]++;
      }
    }
    return out;
  }

  Map<String, Object?> _withPoints(Map<String, Object?> s, List<_Raw> raw, DateTime from, DateTime to) {
    final dpt = switch (s['dpt']) {
      [final int main, final int sub] => (main, sub),
      [final int main] => (main, null),
      _ => null,
    };
    final fromMs = from.millisecondsSinceEpoch;
    final points = <(int, double)>[];
    var smallOnly = true;
    (int, double)? before;
    for (final r in raw) {
      final v = numericValue(dpt, hexBytes(r.hex), small: r.small);
      if (v == null) continue;
      final ms = r.micros ~/ 1000;
      smallOnly &= r.small && v <= 1;
      // Last value before the time span: the chart starts with it at the edge.
      if (ms < fromMs) {
        before = (fromMs, v);
        continue;
      }
      points.add((ms, v));
    }
    if (before != null) points.insert(0, before);
    final step = dpt?.$1 == 1 || (points.isNotEmpty && smallOnly);
    return {
      ..._describe(s),
      'kind': step ? 'step' : 'line',
      'points': [
        for (final (t, v) in thin(points, fromMs, to.millisecondsSinceEpoch, buckets, step: step)) [t, v],
      ],
      if (points.isNotEmpty) 'last': [points.last.$1, points.last.$2],
    };
  }

  /// Telegrams (write, response) to [addresses] from [from] to [to], plus the
  /// day before [from] (for the value at the edge, also shortly after midnight).
  Future<Map<int, List<_Raw>>> _raw(Recorder recorder, Set<int> addresses, DateTime from, DateTime to) async {
    final out = <int, List<_Raw>>{};
    final toMicros = to.microsecondsSinceEpoch;
    for (
      var d = DateTime(from.year, from.month, from.day - 1);
      !d.isAfter(to);
      d = DateTime(d.year, d.month, d.day + 1)
    ) {
      final name = Recorder.dayName(d);
      // A day only counts as complete one hour after midnight: until then,
      // buffered or (on the box) retroactively converted data may still arrive.
      final settled = DateTime(d.year, d.month, d.day + 1, 1).isBefore(to);
      final day = settled ? await _cached(recorder, name, addresses) : await _scan(recorder, name, addresses);
      for (final MapEntry(key: a, value: list) in day.entries) {
        (out[a] ??= []).addAll(list.where((r) => r.micros <= toMicros));
      }
    }
    return out;
  }

  Future<Map<int, List<_Raw>>> _cached(Recorder recorder, String name, Set<int> addresses) async {
    final key = '${recorder.data.path}|$name';
    final hit = _cache[key];
    if (hit != null && hit.addresses.containsAll(addresses)) return hit.points;
    final wanted = {...addresses, ...?hit?.addresses};
    final points = await _scan(recorder, name, wanted);
    _cache.remove(key);
    _cache[key] = _Day(wanted, points);
    while (_cache.length > cacheDays) {
      _cache.remove(_cache.keys.first);
    }
    return points;
  }

  static Future<Map<int, List<_Raw>>> _scan(Recorder recorder, String name, Set<int> addresses) async {
    final out = <int, List<_Raw>>{};
    final lines = await recorder.dayLines(name);
    if (lines == null) return out;
    await for (final line in lines) {
      final d = int.tryParse(Recorder.field(line, 'd') ?? '');
      if (d == null || !addresses.contains(d)) continue;
      // A read (y = 0) has no value.
      if (Recorder.field(line, 'y') == '0') continue;
      try {
        final t = jsonDecode(line) as Map<String, Object?>;
        (out[d] ??= []).add(_Raw(t['t']! as int, t['x'] as String? ?? '', small: t['m'] == true));
      } on FormatException {
        // half-written line at the end of today
      }
    }
    return out;
  }

  static Future<Map<String, Object?>?> _read(Directory root) async {
    final file = File('${root.path}/$fileName');
    try {
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString()) as Map<String, Object?>;
    } on Object catch (e) {
      stderr.writeln('$fileName: $e');
      return null;
    }
  }

  static Iterable<Map<String, Object?>> _charts(Map<String, Object?>? json) sync* {
    for (final c in json?['charts'] as List? ?? const []) {
      if (c is Map && c['name'] is String) yield c.cast<String, Object?>();
    }
  }

  /// Most series of one chart, as in the app; a chart file written by hand or by an old app version
  /// cannot make the server read hundreds of addresses at once.
  static const maxSeries = 8;

  static Iterable<Map<String, Object?>> _seriesOf(Map<String, Object?> chart) => [
    for (final s in chart['series'] as List? ?? const [])
      if (s is Map && s['address'] is int) s.cast<String, Object?>(),
  ].take(maxSeries);

  static Map<String, Object?> _describe(Map<String, Object?> s) => {
    'address': s['address'],
    'label': s['label'] ?? '${s['address']}',
    if (s['name'] case final String name) 'name': name,
    if (s['unit'] case final String unit) 'unit': unit,
    if (s['metric'] case final String metric) 'metric': metric,
    if (s['off'] case final String off) 'off': off,
    if (s['on'] case final String on) 'on': on,
  };
}

/// Thins out [points] (time in ms, value; sorted by time) to at most two
/// points per column: the smallest and the largest, in chronological order –
/// peaks stay visible. [step]: switch states, where consecutive equal values
/// count only once.
List<(int, double)> thin(List<(int, double)> points, int from, int to, int buckets, {bool step = false}) {
  var list = points;
  if (step) {
    list = [
      for (var i = 0; i < points.length; i++)
        if (i == 0 || points[i].$2 != points[i - 1].$2) points[i],
    ];
  }
  if (list.length <= buckets * 2 || to <= from) return list;
  final out = <(int, double)>[];
  var bucket = -1;
  (int, double)? lo;
  (int, double)? hi;
  void close() {
    final l = lo, h = hi;
    if (l == null || h == null) return;
    out.addAll(l == h ? [l] : (l.$1 <= h.$1 ? [l, h] : [h, l]));
  }

  for (final p in list) {
    final b = ((p.$1 - from) * buckets ~/ (to - from)).clamp(0, buckets - 1);
    if (b != bucket) {
      close();
      bucket = b;
      lo = hi = p;
    } else {
      if (p.$2 < lo!.$2) lo = p;
      if (p.$2 > hi!.$2) hi = p;
    }
  }
  close();
  // The last value is always kept: it holds until now (open end).
  if (out.last != list.last) out.add(list.last);
  return out;
}

/// Telegrams per minute from [start]: total, repeated, per line (`s >> 8`).
/// Payload hex (`"x":"…"`) of a history line; [Recorder.field] only reads numbers.
String _payload(String line) {
  final i = line.indexOf('"x":"');
  if (i < 0) return '';
  final end = line.indexOf('"', i + 5);
  return end < 0 ? '' : line.substring(i + 5, end);
}

class _Minutes {
  _Minutes(this.start, int n) : telegrams = List.filled(n, 0), repeats = List.filled(n, 0), busyMs = List.filled(n, 0);

  final DateTime start;
  final List<int> telegrams;
  final List<int> repeats;

  /// Milliseconds the line was busy (TP, 9600 bit/s), for the bus load.
  final List<int> busyMs;
  final lines = <int, List<int>>{};

  /// Adds the minutes of [other] that fall within this time span.
  void add(_Minutes other) {
    final offset = other.start.difference(start).inMinutes;
    void into(List<int> target, List<int> source) {
      for (var i = 0; i < source.length; i++) {
        final j = i + offset;
        if (j >= 0 && j < target.length) target[j] += source[i];
      }
    }

    into(telegrams, other.telegrams);
    into(repeats, other.repeats);
    into(busyMs, other.busyMs);
    for (final MapEntry(key: line, value: counts) in other.lines.entries) {
      into(lines[line] ??= List.filled(telegrams.length, 0), counts);
    }
  }
}

class _Raw {
  const _Raw(this.micros, this.hex, {required this.small});
  final int micros;
  final String hex;
  final bool small;
}

class _Day {
  _Day(this.addresses, this.points);
  final Set<int> addresses;
  final Map<int, List<_Raw>> points;
}
