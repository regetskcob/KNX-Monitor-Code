import '../knx/group_catalog.dart';
import '../knx/telegram.dart';
import 'tap_points.dart';
import 'topology.dart';

/// What the tap points of several lines show about the couplers' filter tables (issue #8).
///
/// A tap point in line B sees a group telegram from line A only if the couplers on the way pass
/// it. With the project's associations that becomes a live filter table check, without reading a
/// coupler: blocked although devices in B listen ([blocked]), or passed although nobody in B
/// listens ([leaked], needless bus load). Only lines with a tap point can be judged ([lines]).
class TapCoverage {
  TapCoverage._(this.lines, this.blocked, this.leaked);

  /// A telegram counts for line B only if B's tap point delivered anything this close in time:
  /// a tap point that was down says nothing about the coupler.
  static const activeWithin = Duration(minutes: 5);

  /// Telegrams per address and direction before something counts: one alone may be chance.
  static const needed = 2;

  /// Lines with a tap point.
  final Set<int> lines;

  /// Addresses that never reached a line where devices listen to them.
  final List<FilterFinding> blocked;

  /// Addresses that reach a line where no device listens to them.
  final List<FilterFinding> leaked;

  bool get isEmpty => blocked.isEmpty && leaked.isEmpty;

  /// From the [log] and the tap point [labels] (the line "1.2" from the tunnel address, see
  /// `tapLabel`). `null` with fewer than two tap points in different lines.
  ///
  /// [gaps] knows when a tap point was away: a telegram from such a time is not counted against
  /// the coupler of that line, whatever the tap point delivered before and after.
  static TapCoverage? build(GroupCatalog catalog, Iterable<Telegram> log, List<String> labels, {TapGaps? gaps}) {
    final lineOfTap = <int, int>{};
    for (final (i, label) in labels.indexed) {
      if (lineOfTapLabel(label) case final line?) lineOfTap[i] = line;
    }
    final lines = lineOfTap.values.toSet();
    if (lines.length < 2) return null;

    // When each line's tap point delivered something, for "was it up at that time?".
    final heard = <int, List<DateTime>>{for (final l in lines) l: []};
    final received = [
      for (final t in log)
        if (!t.outgoing && t.type != TelegramType.read) t,
    ];
    for (final t in received) {
      for (final l in _seenAt(t, lineOfTap)) {
        heard[l]!.add(t.time);
      }
    }
    for (final times in heard.values) {
      times.sort();
    }

    final receivers = <int, Set<int>>{
      for (final g in catalog.groups.values) g.address: {for (final l in g.links) lineOf(l.device)},
    };
    final counts = <(int, int, int), (int, int)>{}; // (ga, from, to) → (passed, blocked)
    for (final t in received) {
      final from = lineOf(t.source);
      final seen = _seenAt(t, lineOfTap);
      for (final to in lines) {
        if (to == from) continue;
        final pass = seen.contains(to);
        if (!pass && !_upAt(heard[to]!, t.time)) continue;
        if (!pass && gaps != null && _awayAt(gaps, lineOfTap, to, t.time)) continue;
        final key = (t.destination, from, to);
        final (p, b) = counts[key] ?? (0, 0);
        counts[key] = pass ? (p + 1, b) : (p, b + 1);
      }
    }

    final blocked = <FilterFinding>[];
    final leaked = <FilterFinding>[];
    for (final MapEntry(key: (ga, from, to), value: (passed, stopped)) in counts.entries) {
      final listeners = receivers[ga];
      if (listeners == null || listeners.isEmpty) continue; // unknown address: nothing to compare
      final wanted = listeners.contains(to);
      if (wanted && passed == 0 && stopped >= needed) {
        blocked.add(FilterFinding(ga, from, to, stopped));
      } else if (!wanted && passed >= needed) {
        leaked.add(FilterFinding(ga, from, to, passed));
      }
    }
    int byAddress(FilterFinding a, FilterFinding b) =>
        a.group != b.group ? a.group.compareTo(b.group) : a.to.compareTo(b.to);
    return TapCoverage._(lines, blocked..sort(byAddress), leaked..sort(byAddress));
  }

  static Set<int> _seenAt(Telegram t, Map<int, int> lineOfTap) => {
    ?lineOfTap[t.tap],
    for (final s in t.sightings) ?lineOfTap[s.tap],
  };

  static bool _upAt(List<DateTime> times, DateTime t) {
    // Binary search for the first time ≥ t − activeWithin.
    final lo = t.subtract(activeWithin), hi = t.add(activeWithin);
    var a = 0, b = times.length;
    while (a < b) {
      final m = (a + b) >> 1;
      if (times[m].isBefore(lo)) {
        a = m + 1;
      } else {
        b = m;
      }
    }
    return a < times.length && !times[a].isAfter(hi);
  }

  /// Whether every tap point of line [line] was away at [time].
  static bool _awayAt(TapGaps gaps, Map<int, int> lineOfTap, int line, DateTime time) {
    for (final MapEntry(key: tap, value: l) in lineOfTap.entries) {
      if (l == line && gaps.at(tap, time) == null) return false;
    }
    return true;
  }
}

/// One address in one direction between two lines.
class FilterFinding {
  const FilterFinding(this.group, this.from, this.to, this.count);

  final int group;

  /// Line of the sender and line of the tap point, as in [lineOf].
  final int from;
  final int to;

  /// Telegrams that were blocked (for [TapCoverage.blocked]) or passed ([TapCoverage.leaked]).
  final int count;
}
