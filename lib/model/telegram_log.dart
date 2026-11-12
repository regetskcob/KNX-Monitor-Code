import 'package:flutter/foundation.dart';

import '../catalog_store.dart';
import '../knx/dpt_codec.dart';
import '../knx/telegram.dart';
import 'alarms.dart';

/// Telegram history with derived views (latest values, counters, histories).
///
/// The basis for the live monitor ([MonitorModel]) and saved recordings
/// ([RecordingLog]); all views work only against this class.
class TelegramLog extends ChangeNotifier {
  TelegramLog({this.maxEntries});

  /// Limit for [log]; `null` = unlimited (recordings).
  final int? maxEntries;

  /// Whether it is currently listening on the bus (monitor): metrics extend up to
  /// now, not only up to the last telegram as with recordings.
  bool get live => false;

  /// Older telegrams drop out of [log] (live monitor in Free); `null` = no limit.
  Duration? maxAge;

  static const historyLength = 40;

  /// All telegrams, oldest first.
  final log = <Telegram>[];

  /// Last write/response telegram per group address.
  final latest = <int, Telegram>{};

  /// Telegrams per group address.
  final counts = <int, int>{};

  /// Latest numeric values per group address for mini charts.
  final history = <int, List<double>>{};

  /// Timestamps for [history] (same length) – time axis for switching states.
  final historyTimes = <int, List<DateTime>>{};

  final _sums = <int, double>{};
  final _samples = <int, int>{};

  /// Average of all numeric values of a group address since the start; `null`
  /// with fewer than two values.
  double? average(int address) {
    final n = _samples[address] ?? 0;
    return n < 2 ? null : _sums[address]! / n;
  }

  final typeCounts = {for (final t in TelegramType.values) t: 0};

  /// Increments on every telegram – for pulse animations.
  final pulse = ValueNotifier(0);

  int? _frozenLength;

  /// Telegrams that arrive while the display is paused are still collected, but
  /// only shown after resuming.
  bool get paused => _frozenLength != null;

  int get pending => paused ? log.length - _frozenLength! : 0;

  /// Displayed history (frozen while paused).
  List<Telegram> get visibleLog => paused ? log.sublist(0, _frozenLength) : log;

  int get total => typeCounts.values.fold(0, (a, b) => a + b);

  /// Segments with active alarms/faults, parallel to [activityBins].
  List<int> get alarmBins => const [];

  /// Group addresses whose last value reports an active alarm/fault.
  int get activeAlarmCount => latest.values.where((t) => activeAlarm(t) != null).length;

  /// Activity as bars (telegrams per segment), for [BusActivity].
  List<int> get activityBins => const [];

  /// Segments of [activityBins] that have already passed; the others lie in the
  /// future (for "today", the rest of the day).
  int get activityPast => activityBins.length;

  /// Tick marks below the bars every this many segments (0 = none).
  int get activityTicks => 0;

  /// Start of segment [i] of [activityBins], for the time shown on hover;
  /// `null` if the segments have no time.
  DateTime? activityTimeOf(int i) => null;

  /// Label of the activity bars, e.g. "last 60 s".
  String get activityLabel => '';

  /// Whether the time range of the activity bar can be switched (live only).
  bool get activitySwitchable => false;

  /// When a telegram was displayed (real time) – for arrival animations, live as
  /// well as when playing back a recording.
  final _shownAt = Expando<DateTime>();

  /// Display times of the last second – for [recentRate].
  final _recent = <DateTime>[];

  /// Displayed telegrams per second (live as well as during playback).
  int get recentRate {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 1));
    while (_recent.isNotEmpty && _recent.first.isBefore(cutoff)) {
      _recent.removeAt(0);
    }
    return _recent.length;
  }

  /// From this rate on, arrival animations are skipped – too fast to follow, and
  /// reordering the list then costs frame rate.
  static const animationRateLimit = 60;

  /// Whether it has only just arrived (for the arrival animation).
  bool isFresh(Telegram t) {
    final at = _shownAt[t];
    return at != null && DateTime.now().difference(at) < const Duration(milliseconds: 800);
  }

  /// Response deadline for read requests.
  static const readTimeout = Duration(seconds: 3);

  final _answered = Expando<bool>();
  final _openReads = <int, List<Telegram>>{};

  /// Reference time for deadlines: live the current time, for recordings the
  /// playback position or the end of the recording.
  DateTime get clock => DateTime.now();

  /// Whether it is a read request that received no response within [readTimeout].
  bool isUnanswered(Telegram t) =>
      t.type == TelegramType.read && _answered[t] != true && clock.difference(t.time) > readTimeout;

  /// Read requests in the history (for the response analysis without scanning all telegrams).
  final _reads = <Telegram>[];

  /// Number of read requests without a response.
  int get unansweredCount => _reads.where(isUnanswered).length;

  /// Telegrams sent by us (L_Data.con confirmations), since start/clear.
  int sentCount = 0;

  /// Repeated telegrams (first attempt not acknowledged), since start/clear.
  int repeatedCount = 0;

  /// All telegrams of a group address, oldest first.
  List<Telegram> forAddress(int destination) => [
    for (final t in log)
      if (t.destination == destination) t,
  ];

  void add(Telegram t) {
    final now = DateTime.now();
    _shownAt[t] = now;
    _recent.add(now);
    if (_recent.length > 4 * animationRateLimit) _recent.removeRange(0, _recent.length - 2 * animationRateLimit);
    _insert(t);
    pulse.value++;
    notifyListeners();
  }

  /// Adds many telegrams without animation and with a single notification.
  void addAll(Iterable<Telegram> telegrams) {
    for (final t in telegrams) {
      _insert(t);
    }
    notifyListeners();
  }

  void _dropOldest() {
    final dropped = log.removeAt(0);
    if (dropped.type == TelegramType.read && _reads.isNotEmpty && identical(_reads.first, dropped)) {
      _reads.removeAt(0);
    }
    if (_frozenLength != null && _frozenLength! > 0) _frozenLength = _frozenLength! - 1;
  }

  void _insert(Telegram t) {
    log.add(t);
    final max = maxEntries;
    if (max != null && log.length > max) _dropOldest();
    if (maxAge case final age?) {
      final cutoff = t.time.subtract(age);
      while (log.length > 1 && log.first.time.isBefore(cutoff)) {
        _dropOldest();
      }
    }
    counts.update(t.destination, (c) => c + 1, ifAbsent: () => 1);
    if (t.type == TelegramType.read) {
      _reads.add(t);
      (_openReads[t.destination] ??= []).add(t);
    } else if (t.type == TelegramType.response) {
      for (final r in _openReads.remove(t.destination) ?? const <Telegram>[]) {
        if (t.time.difference(r.time) <= readTimeout) _answered[r] = true;
      }
    }
    typeCounts[t.type] = typeCounts[t.type]! + 1;
    if (t.outgoing) sentCount++;
    if (t.repeated) repeatedCount++;
    if (t.type != TelegramType.read) {
      latest[t.destination] = t;
      final v = numericValue(CatalogStore.instance.dptFor(t), t);
      if (v != null) {
        final h = history.putIfAbsent(t.destination, () => []);
        final times = historyTimes.putIfAbsent(t.destination, () => []);
        h.add(v);
        times.add(t.time);
        if (h.length > historyLength) {
          h.removeAt(0);
          times.removeAt(0);
        }
        _sums[t.destination] = (_sums[t.destination] ?? 0) + v;
        _samples[t.destination] = (_samples[t.destination] ?? 0) + 1;
      }
    }
  }

  void setPaused(bool value) {
    if (value == paused) return;
    _frozenLength = value ? log.length : null;
    notifyListeners();
  }

  /// Rebuilds the list from [all] (e.g. with older telegrams loaded later). A
  /// pause stays in effect: the first [frozen] entries of [all] remain visible.
  @protected
  void rebuild(List<Telegram> all, {required int frozen}) {
    final wasPaused = paused;
    clear();
    if (wasPaused) _frozenLength = frozen;
    addAll(all);
  }

  void clear() {
    log.clear();
    _reads.clear();
    _openReads.clear();
    latest.clear();
    counts.clear();
    history.clear();
    historyTimes.clear();
    _sums.clear();
    _samples.clear();
    for (final t in TelegramType.values) {
      typeCounts[t] = 0;
    }
    sentCount = 0;
    repeatedCount = 0;
    if (paused) _frozenLength = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }
}
