import 'dart:math' as math;

import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';

/// Technical series for charts: not a group address but bus metrics. In saved
/// charts ([SavedCharts]) they are stored as negative ids next to the group
/// addresses – so settings and `charts.json` keep their existing format:
///
/// - −1 telegrams per minute,
/// - −2 repetitions per minute (telegrams with the repeat flag),
/// - −(256 + line) telegrams per minute from one line (area.line of the
///   sender, `source >> 8`).
///
/// The server computes the same series from the history (`charts.dart`).
class BusMetric {
  const BusMetric._(this.id);

  static const telegrams = BusMetric._(-1);
  static const repeats = BusMetric._(-2);

  /// Load of line [line] (`area << 4 | line`, like `source >> 8`).
  factory BusMetric.line(int line) => BusMetric._(-(_lineBase + (line & 0xFF)));

  static const _lineBase = 256;

  final int id;

  /// The metric for [id]; `null` for group addresses (not negative).
  static BusMetric? of(int id) {
    if (id == telegrams.id) return telegrams;
    if (id == repeats.id) return repeats;
    if (id <= -_lineBase && id > -_lineBase - 256) return BusMetric._(id);
    return null;
  }

  /// Line for line load, otherwise `null`.
  int? get line => id <= -_lineBase ? -id - _lineBase : null;

  /// For `charts.json`: `telegrams`, `repeats` or `line`.
  String get key => line != null ? 'line' : (id == telegrams.id ? 'telegrams' : 'repeats');

  /// "1.1" for a line.
  static String lineLabel(int line) => '${(line >> 4) & 0x0F}.${line & 0x0F}';

  String get name => switch (line) {
    final l? => s.busMetricLine(lineLabel(l)),
    null => id == telegrams.id ? s.busMetricTelegrams : s.busMetricRepeats,
  };

  /// Unit of all metrics.
  static const unit = '/min';

  bool _counts(Telegram t) => switch (line) {
    final l? => !t.outgoing && t.source >> 8 == l,
    null => id == telegrams.id || t.repeated,
  };

  /// History from [log] (sorted by time): telegrams per minute in buckets of one
  /// or more minutes, at most [maxBuckets]. Empty buckets count as 0; the
  /// incomplete last one is scaled by the elapsed time. The end is [now],
  /// otherwise the last telegram – recordings and the demo house also lie in the
  /// past.
  List<(DateTime, double)> rates(List<Telegram> log, {int maxBuckets = 400, DateTime? now}) {
    if (log.isEmpty) return const [];
    final first = log.first.time;
    final end = now ?? log.last.time;
    // Bucket width chosen so that, even with incomplete first and last buckets,
    // there are at most [maxBuckets].
    var minutes = math.max(1, (end.difference(first).inMinutes / maxBuckets).ceil());
    late DateTime start;
    late int n;
    while (true) {
      final ms = minutes * 60000;
      start = DateTime.fromMillisecondsSinceEpoch(first.millisecondsSinceEpoch - first.millisecondsSinceEpoch % ms);
      n = end.difference(start).inMilliseconds ~/ ms + 1;
      if (n <= maxBuckets) break;
      minutes++;
    }
    final bucket = Duration(minutes: minutes);
    final ms = bucket.inMilliseconds;
    final counts = List.filled(n, 0);
    for (final t in log) {
      if (!_counts(t)) continue;
      final i = t.time.difference(start).inMilliseconds ~/ ms;
      if (i >= 0 && i < n) counts[i]++;
    }
    return [
      for (var i = 0; i < n; i++)
        (start.add(bucket * i), counts[i] / _minutes(i == n - 1 ? end.difference(start.add(bucket * i)) : bucket)),
    ];
  }

  /// At least ten seconds, so the bucket that just started does not jump.
  static double _minutes(Duration d) => math.max(d.inMilliseconds, 10000) / 60000;

  @override
  bool operator ==(Object other) => other is BusMetric && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
