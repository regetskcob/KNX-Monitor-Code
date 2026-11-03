import '../knx/group_catalog.dart';
import '../knx/telegram.dart';
import 'project_check.dart';

/// Checks the couplers' filter tables, passively and from the project only. The
/// table itself is never read or written: we only see what arrives on a line.
/// All results are therefore probabilities.

/// Line (area and line) of an individual address.
int lineOfDevice(int address) => (address >> 8) & 0xFF;

/// "1.1" from [lineOfDevice].
String formatLine(int line) => '${(line >> 4) & 0x0F}.${line & 0x0F}';

/// Rules for when "not seen" means something.
abstract final class FilterRules {
  /// Both captures must have run simultaneously for at least this long.
  static const minOverlap = Duration(minutes: 10);

  /// An address must have appeared on the other line at least this often.
  static const minSeen = 2;

  /// Share of direct telegrams needed for a capture's line to count as certain.
  static const lineShare = 0.6;
}

/// Line on which a capture was made. Telegrams sent by us carry the interface's
/// address, which is certain. Otherwise the most frequent line among telegrams
/// with hop count 6 (directly from the sender, no coupler in between), but only
/// with a clear majority. `null`: unclear, then the capture does not count.
int? observationLine(Iterable<Telegram> telegrams) {
  final own = <int, int>{};
  final direct = <int, int>{};
  for (final t in telegrams) {
    if (t.source == 0) continue;
    if (t.outgoing) {
      own[lineOfDevice(t.source)] = (own[lineOfDevice(t.source)] ?? 0) + 1;
    } else if (t.hopCount == 6) {
      direct[lineOfDevice(t.source)] = (direct[lineOfDevice(t.source)] ?? 0) + 1;
    }
  }
  int? top(Map<int, int> counts) =>
      counts.isEmpty ? null : counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  if (top(own) case final line?) return line;
  final line = top(direct);
  if (line == null) return null;
  final total = direct.values.fold<int>(0, (a, b) => a + b);
  return direct[line]! / total >= FilterRules.lineShare ? line : null;
}

/// An observation point: a capture on a known line.
class FilterObservation {
  const FilterObservation({
    required this.name,
    required this.line,
    required this.from,
    required this.to,
    required this.telegrams,
  });

  final String name;
  final int line;
  final DateTime from;
  final DateTime to;
  final List<Telegram> telegrams;

  /// `null` if the capture is empty or its line remains unclear.
  static FilterObservation? of(String name, List<Telegram> telegrams, {DateTime? from, DateTime? to}) {
    if (telegrams.isEmpty) return null;
    final line = observationLine(telegrams);
    if (line == null) return null;
    return FilterObservation(
      name: name,
      line: line,
      from: from ?? telegrams.first.time,
      to: to ?? telegrams.last.time,
      telegrams: telegrams,
    );
  }
}

/// Address whose sender and receivers lie on different lines according to the
/// project. It only arrives if the coupler's filter table knows it.
class CrossLineGroup {
  const CrossLineGroup(this.group, {required this.senderLines, required this.receiverLines, this.confirmed = const {}});

  final GroupInfo group;
  final Set<int> senderLines;
  final Set<int> receiverLines;

  /// Receiver lines on which it has already arrived from another line.
  final Set<int> confirmed;

  /// Receiver lines for which no telegram proves yet that it gets through.
  Set<int> get open => receiverLines.difference(senderLines).difference(confirmed);
}

/// Seen on one line during the same period but not on the other, although a
/// receiver sits there according to the project: probably missing from the
/// filter table.
class NotForwardedGroup {
  const NotForwardedGroup(this.group, {required this.seenOn, required this.missingOn, required this.count});

  final GroupInfo group;
  final int seenOn;
  final int missingOn;

  /// Number of times seen on [seenOn].
  final int count;
}

/// Result of the check.
class FilterCheck {
  const FilterCheck._({
    required this.mainGroups,
    required this.crossLine,
    required this.notForwarded,
    required this.comparedPoints,
  });

  /// From the project only; [observations] makes it more precise and adds
  /// [notForwarded] (only where two observation points ran simultaneously).
  factory FilterCheck.of(GroupCatalog catalog, {List<FilterObservation> observations = const []}) {
    final sorted = catalog.groups.values.toList()..sort((a, b) => a.address.compareTo(b.address));
    // Only projects with flags know the sending direction; without them we say nothing.
    ({Set<int> senders, Set<int> receivers})? linesOf(GroupInfo g) {
      if (g.links.isEmpty || g.links.any((l) => l.flags == null)) return null;
      return (
        senders: {
          for (final l in g.links)
            if (l.sends) lineOfDevice(l.device),
        },
        receivers: {
          for (final l in g.links)
            if (!l.sends && l.flags!.communication && l.flags!.write) lineOfDevice(l.device),
        },
      );
    }

    final seenAcross = <int, Set<int>>{};
    for (final o in observations) {
      for (final t in o.telegrams) {
        if (t.outgoing || t.type == TelegramType.read) continue;
        if (lineOfDevice(t.source) != o.line) (seenAcross[t.destination] ??= {}).add(o.line);
      }
    }
    final crossLine = <CrossLineGroup>[];
    for (final g in sorted) {
      final lines = linesOf(g);
      if (lines == null || lines.senders.isEmpty || lines.receivers.isEmpty) continue;
      if (lines.receivers.difference(lines.senders).isEmpty) continue;
      crossLine.add(
        CrossLineGroup(
          g,
          senderLines: lines.senders,
          receiverLines: lines.receivers,
          confirmed: seenAcross[g.address] ?? const {},
        ),
      );
    }

    final found = <(int, int), NotForwardedGroup>{};
    var compared = 0;
    for (final a in observations) {
      for (final b in observations) {
        if (identical(a, b) || a.line == b.line) continue;
        final from = a.from.isAfter(b.from) ? a.from : b.from;
        final to = a.to.isBefore(b.to) ? a.to : b.to;
        if (to.difference(from) < FilterRules.minOverlap) continue;
        compared++;
        bool within(Telegram t) => !t.time.isBefore(from) && !t.time.isAfter(to);
        final onB = {
          for (final t in b.telegrams)
            if (within(t)) t.destination,
        };
        final onA = <int, int>{};
        for (final t in a.telegrams) {
          // Only what comes from outside the missing line has to pass the coupler.
          if (t.outgoing || t.type == TelegramType.read || !within(t) || lineOfDevice(t.source) == b.line) continue;
          onA[t.destination] = (onA[t.destination] ?? 0) + 1;
        }
        for (final MapEntry(key: address, value: count) in onA.entries) {
          if (count < FilterRules.minSeen || onB.contains(address)) continue;
          final g = catalog.groups[address];
          final lines = g == null ? null : linesOf(g);
          // Without a receiver there, "not seen" is exactly right.
          if (lines == null || !lines.receivers.contains(b.line)) continue;
          final key = (address, b.line);
          if ((found[key]?.count ?? 0) < count) {
            found[key] = NotForwardedGroup(g!, seenOn: a.line, missingOn: b.line, count: count);
          }
        }
      }
    }
    return FilterCheck._(
      mainGroups: ProjectLint.of(catalog).unfilteredMainGroups,
      crossLine: crossLine,
      notForwarded: found.values.toList()
        ..sort((x, y) {
          final address = x.group.address.compareTo(y.group.address);
          return address != 0 ? address : x.missingOn.compareTo(y.missingOn);
        }),
      comparedPoints: compared ~/ 2,
    );
  }

  /// Main group 14 or 15 with several lines ([ProjectLint]).
  final List<GroupInfo> mainGroups;

  /// Sender and receiver on different lines.
  final List<CrossLineGroup> crossLine;

  /// Probably not passed by a coupler.
  final List<NotForwardedGroup> notForwarded;

  /// How many pairs of observation points were compared. Zero means nothing can
  /// be said from the bus traffic.
  final int comparedPoints;

  /// Transitions not yet confirmed, per receiver line, for the tasks in the ETS.
  Map<int, int> get openByLine {
    final out = <int, int>{};
    for (final c in crossLine) {
      for (final line in c.open) {
        out[line] = (out[line] ?? 0) + 1;
      }
    }
    return Map.fromEntries(out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }
}
