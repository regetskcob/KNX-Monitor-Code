import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Time range of the activity bar.
enum ActivityRange {
  /// 60 bars of 1 s each.
  seconds,

  /// 60 bars of 1 min each.
  hour,

  /// 96 bars of 15 min each, 0:00–24:00.
  today,
}

/// Selected time range (persisted, applies to all monitors).
class ActivityRangeSetting extends ValueNotifier<ActivityRange> {
  ActivityRangeSetting._() : super(ActivityRange.seconds);

  static final instance = ActivityRangeSetting._();
  static const _key = 'activity_range';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    value = ActivityRange.values.asNameMap()[prefs.getString(_key)] ?? ActivityRange.seconds;
  }

  /// Next time range (for cycling through).
  Future<void> next() async {
    value = ActivityRange.values[(value.index + 1) % ActivityRange.values.length];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value.name);
  }
}

/// Telegrams and alarms per minute – the basis for "last hour" and "today",
/// independent of the capped telegram list.
class MinuteCounter {
  final _counts = <int, int>{};
  final _alarms = <int, int>{};

  /// Earliest recorded time (start of coverage).
  DateTime? _first;

  static int _minute(DateTime t) => t.millisecondsSinceEpoch ~/ 60000;

  void add(DateTime time, {bool alarm = false}) {
    final m = _minute(time);
    if (_first == null || time.isBefore(_first!)) _first = time;
    _counts[m] = (_counts[m] ?? 0) + 1;
    if (alarm) _alarms[m] = (_alarms[m] ?? 0) + 1;
  }

  /// Discards everything before 11 pm yesterday (today and the last hour remain).
  void prune(DateTime now) {
    final keep = _minute(DateTime(now.year, now.month, now.day).subtract(const Duration(hours: 1)));
    _counts.removeWhere((m, _) => m < keep);
    _alarms.removeWhere((m, _) => m < keep);
  }

  /// Average telegrams per minute since [from], measured only over the time that
  /// was actually recorded (from [coveredSince] or the first value).
  double perMinute(DateTime now, DateTime from, {required DateTime coveredSince}) {
    final first = _first;
    var start = from;
    final covered = first != null && first.isBefore(coveredSince) ? first : coveredSince;
    if (covered.isAfter(start)) start = covered;
    final startMinute = _minute(start);
    var sum = 0;
    for (final MapEntry(key: m, value: n) in _counts.entries) {
      if (m >= startMinute && m <= _minute(now)) sum += n;
    }
    final minutes = now.difference(start).inSeconds / 60;
    return minutes < 1 ? sum.toDouble() : sum / minutes;
  }

  /// 60 values, one per minute, the current one last.
  List<int> hour(DateTime now, {bool alarms = false}) {
    final source = alarms ? _alarms : _counts;
    final end = _minute(now);
    return [for (var m = end - 59; m <= end; m++) source[m] ?? 0];
  }

  /// 96 values, one per quarter hour from 0:00 to 24:00 (future = 0).
  List<int> today(DateTime now, {bool alarms = false}) {
    final source = alarms ? _alarms : _counts;
    final start = _minute(DateTime(now.year, now.month, now.day));
    final bins = List.filled(96, 0);
    for (final MapEntry(key: m, value: n) in source.entries) {
      if (m < start) continue; // yesterday (~/ rounds toward 0 – do not count it in bar 0)
      final i = (m - start) ~/ 15;
      if (i < 96) bins[i] += n;
    }
    return bins;
  }
}
