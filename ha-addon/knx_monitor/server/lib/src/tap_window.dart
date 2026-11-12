import 'package:knx/knx.dart';

// Same logic as lib/model/tap_points.dart (TapWindowMeter, TapBacklog) in the app.

/// Merge window that measures itself (issue #8), from the telegrams that arrive at several tap
/// points:
///
/// - A merged telegram carries the offset of every further sighting. [released] keeps the last
///   [kept] offsets per tap point ([lagOf]) and widens that tap point's window as soon as 1.5 ×
///   the largest one no longer fits, before a telegram misses the window.
/// - If a tap point lags more than its window, the same telegram leaves twice, each time seen at
///   one tap point only. [released] spots such late pairs and, after [needed] of them, widens the
///   window to 1.5 × the largest lag seen.
/// - A widened window comes back down: after [kept] merged telegrams in a row without a late
///   pair, it is set to what their largest offset needs, never below [floor]. So a burst of lag
///   (or lag faked with a few telegrams) does not stay for good.
///
/// Windows are rounded up to 10 ms and never exceed [max]. A window set by hand wins: such tap
/// points are not in [auto], and a telegram they took part in never changes another tap point's
/// window either (the merger uses the wider window of a pair). Measured windows are for merging
/// only; Data Secure does not use them (`SecureTapCache`).
class TapWindowMeter {
  TapWindowMeter({required this.current, this.auto = const {}});

  /// Widest window the meter sets, and the longest lag it takes for a late copy: beyond that it
  /// is a new telegram (cyclic sending). More than this needs a window set by hand.
  static const max = Duration(seconds: 1);

  /// The window without any measurement; the meter never goes below it.
  static const floor = Duration(milliseconds: 100);

  /// Measurements per tap point before its window grows: one alone may be chance.
  static const needed = 3;

  /// Offsets kept per tap point for [lagOf], and merged telegrams before a window may shrink.
  static const kept = 64;

  /// Current window of a tap point.
  final Duration Function(int tap) current;

  /// Tap points whose window may be adjusted.
  final Set<int> auto;

  final _recent = <String, (int, DateTime)>{};
  final _count = <int, int>{};
  final _lag = <int, Duration>{};
  final _offsets = <int, List<int>>{};

  /// Merged telegrams per tap point since its window last changed or a copy came late.
  final _calm = <int, int>{};

  /// Largest of the last [kept] offsets of [tap] behind the first sighting of the same telegram;
  /// `null` before [needed] of them.
  Duration? lagOf(int tap) {
    final list = _offsets[tap];
    if (list == null || list.length < needed) return null;
    var top = 0;
    for (final v in list) {
      if (v > top) top = v;
    }
    return Duration(microseconds: top);
  }

  static Duration _roomFor(Duration lag) {
    final ms = ((lag.inMicroseconds * 1.5) / 1000 / 10).ceil() * 10;
    return Duration(milliseconds: ms.clamp(floor.inMilliseconds, max.inMilliseconds));
  }

  /// Feed every telegram the merger releases. Returns the tap point and its new window when one
  /// should change now (wider, or narrower again), else `null`.
  (int, Duration)? released(Telegram t) {
    if (t.sightings.isNotEmpty) return _merged(t);
    final key =
        '${t.source}|${t.destination}|${t.type.index}|${t.isSmall ? 1 : 0}|${t.repeated ? 1 : 0}|${hexOf(t.data)}';
    final before = _recent[key];
    _recent[key] = (t.tap, t.time);
    if (_recent.length > 500) _recent.remove(_recent.keys.first);
    if (before == null) return null;
    final (tap, time) = before;
    final lag = t.time.difference(time);
    if (tap == t.tap || lag.isNegative || lag > max) return null;
    final late = t.tap;
    if (!auto.contains(late) || !auto.contains(tap)) return null;
    _recent.remove(key);
    _calm[late] = 0;
    _count[late] = (_count[late] ?? 0) + 1;
    if (lag > (_lag[late] ?? Duration.zero)) _lag[late] = lag;
    if (_count[late]! < needed) return null;
    final next = _roomFor(_lag[late]!);
    _count[late] = 0;
    _lag.remove(late);
    return next > current(late) ? (late, next) : null;
  }

  /// A merged telegram: notes the offsets, widens ahead of time, narrows after a calm stretch.
  (int, Duration)? _merged(Telegram t) {
    final free = auto.contains(t.tap) && t.sightings.every((s) => auto.contains(s.tap));
    (int, Duration)? change;
    for (final s in t.sightings) {
      if (s.offset <= Duration.zero || s.offset > max) continue;
      final list = _offsets[s.tap] ??= [];
      list.add(s.offset.inMicroseconds);
      if (list.length > kept) list.removeAt(0);
      if (!free || list.length < needed) continue;
      final calm = _calm[s.tap] = (_calm[s.tap] ?? 0) + 1;
      final next = _roomFor(lagOf(s.tap)!);
      final now = current(s.tap);
      if (next > now) {
        _calm[s.tap] = 0;
        if (change == null || next > change.$2) change = (s.tap, next);
      } else if (next < now && calm >= kept) {
        _calm[s.tap] = 0;
        change ??= (s.tap, next);
      }
    }
    return change;
  }
}

/// Bounds what a `TapMerger` holds back (issue #8). Its entries normally leave after their
/// window. If they cannot (a clock set back, a flood that never lets the list drain), the list
/// would grow without limit; then everything is released at once, at the price of a few telegrams
/// that leave unmerged.
///
/// Counts exactly what is inside the merger: every telegram fed, minus those that left, where a
/// released entry takes its sightings with it ([leaving]). Merged traffic therefore never adds up.
class TapBacklog {
  /// Telegrams held back at most.
  static const max = 1000;

  int _inside = 0;

  /// Telegrams that leave the merger with [released]: each entry and its sightings.
  static int leaving(Iterable<Telegram> released) {
    var n = 0;
    for (final t in released) {
      n += 1 + t.sightings.length;
    }
    return n;
  }

  /// Note [fed] telegrams given to the merger and the ones that [left] it ([leaving]); [pending]
  /// is the merger's own. Returns whether everything must be released now (`flushAll`).
  bool note({int fed = 0, required int left, required bool pending}) {
    if (!pending) {
      _inside = 0;
      return false;
    }
    _inside += fed - left;
    if (_inside < 0) _inside = 0;
    if (_inside <= max) return false;
    _inside = 0;
    return true;
  }
}
