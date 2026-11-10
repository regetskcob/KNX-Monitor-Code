import 'package:knx/knx.dart';

// Same logic as lib/model/tap_points.dart (TapWindowMeter) in the app.

/// Merge window that measures itself (issue #8). If a tap point lags more than its window, the
/// same telegram leaves twice, each time seen at one tap point only. [released] spots such late
/// pairs and, after [needed] of them, widens that tap point's window to 1.5 × the largest lag
/// seen (rounded up to 10 ms, at most [max]). It never narrows: a wider window only delays the
/// list by a moment, a narrow one shows doubles. Tap points with a window set by hand are not
/// touched (the caller passes only the others in [auto]).
class TapWindowMeter {
  TapWindowMeter({required this.current, this.auto = const {}});

  /// Lags beyond this are not a late copy but a new telegram (cyclic sending).
  static const max = Duration(seconds: 2);

  /// Late pairs per tap point before its window grows: one alone may be chance.
  static const needed = 3;

  /// Current window of a tap point.
  final Duration Function(int tap) current;

  /// Tap points whose window may be adjusted.
  final Set<int> auto;

  final _recent = <String, (int, DateTime)>{};
  final _count = <int, int>{};
  final _lag = <int, Duration>{};

  /// Feed every telegram the merger releases. Returns the tap point and its new window when one
  /// should grow now, else `null`.
  (int, Duration)? released(Telegram t) {
    if (t.sightings.isNotEmpty) return null;
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
    if (!auto.contains(late)) return null;
    _recent.remove(key);
    _count[late] = (_count[late] ?? 0) + 1;
    if (lag > (_lag[late] ?? Duration.zero)) _lag[late] = lag;
    if (_count[late]! < needed) return null;
    final ms = ((_lag[late]!.inMicroseconds * 1.5) / 1000 / 10).ceil() * 10;
    final next = Duration(milliseconds: ms.clamp(10, max.inMilliseconds));
    _count[late] = 0;
    return next > current(late) ? (late, next) : null;
  }
}
