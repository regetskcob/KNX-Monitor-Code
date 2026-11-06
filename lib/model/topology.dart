import 'activity_range.dart';
import '../knx/group_catalog.dart';
import '../knx/telegram.dart';

/// Line as a key: area and line from the individual address (1.2.20 → 0x12).
int lineOf(int individualAddress) => individualAddress >> 8;

/// „1.2“
String formatLine(int line) => '${(line >> 4) & 0x0F}.${line & 0x0F}';

/// Factory individual address of KNX devices and interfaces (15.15.255), also
/// the one the KNX HAT of a KNX Monitor Box keeps until one is entered.
const factoryAddress = 0xFFFF;

/// A line with its devices according to the project and the observed traffic.
class LineInfo {
  LineInfo(this.line);

  final int line;

  /// Devices according to the ETS project (without the coupler itself).
  final devices = <DeviceInfo>[];

  /// Tunnel addresses of IP interfaces on this line (not devices).
  final tunnels = <DeviceInfo>[];

  /// Line/area coupler of this line (address x.y.0), if in the project.
  DeviceInfo? coupler;

  /// Observed senders and their hop count (last value).
  final activeSources = <int, int>{};

  /// Frequency of the observed hop counts.
  final hops = <int, int>{};
  int telegrams = 0;

  /// Most frequent hop count – "this is how telegrams from this line arrive at the gateway".
  int? get typicalHops {
    if (hops.isEmpty) return null;
    return hops.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  /// Number of couplers between this line and the gateway (6 − hop count).
  int? get couplersToGateway => typicalHops == null ? null : 6 - typicalHops!;
}

/// Group address with devices on several lines.
class CrossGroup {
  CrossGroup(this.info, {required this.lines, required this.senderLines});

  final GroupInfo info;
  int get address => info.address;

  /// Lines of all associated devices.
  final Set<int> lines;

  /// Lines of the devices that send on this address.
  final Set<int> senderLines;

  /// Observed telegrams per line of origin.
  final seenFrom = <int, int>{};
}

/// Sender whose hop count does not match its line – probably physically located
/// on a different line than its address says.
class HopMismatch {
  const HopMismatch({required this.source, required this.observed, required this.expected});

  final int source;
  final int observed;
  final int expected;
}

/// Logical topology from the ETS project and observed traffic.
///
/// The gateway only sees its own line and what couplers forward from other
/// lines. The hop count (6 when sent, −1 per coupler) reveals how many couplers
/// a telegram passed through.
class Topology {
  Topology._(this.lines, this.cross, this.mismatches, this.unneeded, this.gatewayLine, this.strays);

  /// Lines sorted, the gateway line first.
  final List<LineInfo> lines;

  /// Group addresses spanning several lines.
  final List<CrossGroup> cross;

  /// Devices with a mismatched hop count.
  final List<HopMismatch> mismatches;

  /// Telegrams forwarded from other lines on addresses without a receiver on the
  /// gateway line (group address → count).
  final Map<int, int> unneeded;

  /// Line the gateway is on (tunnel address, or estimated).
  final int? gatewayLine;

  /// Senders listed on the gateway line although their address belongs to
  /// another line: that line is not in the project and their telegrams arrive
  /// without passing a coupler. Typically the factory address 15.15.255 (e.g.
  /// the KNX HAT of a KNX Monitor Box) or a visualisation. Without this they
  /// would appear as a line of their own behind an invented coupler.
  final Set<int> strays;

  LineInfo? line(int line) => lines.where((l) => l.line == line).firstOrNull;

  /// Line a sender is listed on: its own, or the gateway line for [strays].
  int lineOfSource(int address) => strays.contains(address) ? gatewayLine! : lineOf(address);

  factory Topology.build(GroupCatalog catalog, Iterable<Telegram> log, {int? gatewayLine}) {
    final lines = <int, LineInfo>{};
    LineInfo lineFor(int l) => lines.putIfAbsent(l, () => LineInfo(l));

    for (final d in catalog.devices.values) {
      final info = lineFor(lineOf(d.address));
      if (d.address & 0xFF == 0) {
        info.coupler = d;
      } else if (d.isTunnel) {
        info.tunnels.add(d);
      } else {
        info.devices.add(d);
      }
    }
    for (final l in lines.values) {
      l.devices.sort((a, b) => a.address.compareTo(b.address));
      l.tunnels.sort((a, b) => a.address.compareTo(b.address));
    }
    // Lines that exist in the project; only these are real lines.
    final projectLines = lines.keys.toSet();
    // The own address only shows the gateway line if that line is in the
    // project: the KNX HAT of a box keeps 15.15.255 until one is entered.
    final given = gatewayLine != null && (projectLines.isEmpty || projectLines.contains(gatewayLine))
        ? gatewayLine
        : null;

    // Addresses spanning several lines, from the associations.
    final cross = <int, CrossGroup>{};
    final receiverLines = <int, Set<int>>{};
    for (final g in catalog.groups.values) {
      final linked = {for (final l in g.links) lineOf(l.device)};
      receiverLines[g.address] = linked;
      if (linked.length > 1) {
        cross[g.address] = CrossGroup(
          g,
          lines: linked,
          senderLines: {
            for (final l in g.links)
              if (l.sends) lineOf(l.device),
          },
        );
      }
    }

    // Observed traffic (telegrams sent by us do not count).
    final received = [
      for (final t in log)
        if (!t.outgoing) t,
    ];
    for (final t in received) {
      final info = lineFor(lineOf(t.source));
      info.telegrams++;
      info.activeSources[t.source] = t.hopCount;
      info.hops[t.hopCount] = (info.hops[t.hopCount] ?? 0) + 1;
      final c = cross[t.destination];
      if (c != null) c.seenFrom[lineOf(t.source)] = (c.seenFrom[lineOf(t.source)] ?? 0) + 1;
    }

    // Gateway line: from the tunnel address, otherwise the line with hop count 6
    // and the most telegrams – a line from the project before a foreign one.
    LineInfo? busiest(Iterable<LineInfo> ls) => ls
        .where((l) => l.typicalHops == 6)
        .fold<LineInfo?>(null, (best, l) => best == null || l.telegrams > best.telegrams ? l : best);
    final gw =
        given ?? (busiest(lines.values.where((l) => projectLines.contains(l.line))) ?? busiest(lines.values))?.line;

    // Senders from a line that is not in the project whose telegrams arrive
    // like those of the gateway line (hop count 6, no coupler) sit on the
    // gateway line with a foreign address. Only with a project: without one
    // no line is known.
    final strays = <int>{};
    final home = gw == null ? null : lines[gw];
    if (home != null && projectLines.isNotEmpty) {
      for (final l in lines.values.toList()) {
        if (l.line == gw || projectLines.contains(l.line) || l.hops.isEmpty || l.hops.keys.any((h) => h != 6)) {
          continue;
        }
        strays.addAll(l.activeSources.keys);
        home.activeSources.addAll(l.activeSources);
        home.telegrams += l.telegrams;
        for (final MapEntry(key: h, value: n) in l.hops.entries) {
          home.hops[h] = (home.hops[h] ?? 0) + n;
        }
        for (final c in cross.values) {
          final n = c.seenFrom.remove(l.line);
          if (n != null) c.seenFrom[gw!] = (c.seenFrom[gw] ?? 0) + n;
        }
        lines.remove(l.line);
      }
    }
    int origin(int source) => strays.contains(source) ? gw! : lineOf(source);

    // Hop count does not match the line: deviation from what is typical for the
    // line, or from 6 for the gateway line.
    final mismatches = <HopMismatch>[];
    for (final l in lines.values) {
      final expected = l.line == gw ? 6 : l.typicalHops;
      if (expected == null) continue;
      for (final MapEntry(key: source, value: hops) in l.activeSources.entries) {
        if (hops != expected) mismatches.add(HopMismatch(source: source, observed: hops, expected: expected));
      }
    }

    // Forwarded from other lines although nobody here is listening.
    final unneeded = <int, int>{};
    if (gw != null) {
      for (final t in received) {
        final from = origin(t.source);
        if (from == gw) continue;
        final receivers = receiverLines[t.destination];
        if (receivers == null || receivers.isEmpty || receivers.contains(gw)) continue;
        unneeded[t.destination] = (unneeded[t.destination] ?? 0) + 1;
      }
    }

    final sorted = lines.values.toList()
      ..sort((a, b) => a.line == gw ? -1 : (b.line == gw ? 1 : a.line.compareTo(b.line)));
    return Topology._(
      sorted,
      cross.values.toList()..sort((a, b) => a.address.compareTo(b.address)),
      mismatches,
      unneeded,
      gw,
      strays,
    );
  }
}

/// Result of a coupler check for an address.
enum CouplerCheck {
  /// Response received from the other line – the coupler forwards.
  passed,

  /// No response: filter table outdated or read flag not set.
  noAnswer,
}

/// Actively checks addresses spanning several lines: a read request from the
/// gateway line to addresses whose sending device sits behind a coupler. If the
/// response comes from the other line, the coupler forwards in both
/// directions.
class CouplerCheckRun {
  CouplerCheckRun({required this.candidates, required this.gatewayLine, required this.read, required this.answers});

  /// Addresses to check.
  final List<int> candidates;
  final int gatewayLine;

  /// Sends a read request.
  final Future<void> Function(int address) read;

  /// Incoming telegrams (responses).
  final Stream<Telegram> answers;

  static const interval = Duration(milliseconds: 250);
  static const answerWindow = Duration(seconds: 3);

  final results = <int, CouplerCheck>{};

  /// Responding devices per address.
  final responders = <int, int>{};

  Future<void> run({void Function()? onProgress}) async {
    final pending = candidates.toSet();
    final sub = answers.listen((t) {
      if (t.type != TelegramType.response || !pending.contains(t.destination)) return;
      if (lineOf(t.source) == gatewayLine) return; // The response must come through the coupler
      results[t.destination] = CouplerCheck.passed;
      responders[t.destination] = t.source;
      onProgress?.call();
    });
    for (final ga in candidates) {
      await read(ga);
      await Future<void>.delayed(interval);
    }
    await Future<void>.delayed(answerWindow);
    await sub.cancel();
    for (final ga in candidates) {
      results.putIfAbsent(ga, () => CouplerCheck.noAnswer);
    }
    onProgress?.call();
  }
}

/// Group address that passes through a coupler in one direction.
class FlowGroup {
  FlowGroup(this.address, this.info);

  final int address;

  /// Entry in the ETS project, `null` for unknown addresses.
  final GroupInfo? info;

  /// Observed telegrams in this direction.
  int count = 0;

  /// Time of the last observed telegram.
  DateTime? last;

  /// Observed senders and their count.
  final senders = <int, int>{};

  /// Sending device according to the project (if nothing was observed).
  int? projectSender;

  /// Most frequent observed sender, otherwise the one from the project.
  int? get sender => senders.isEmpty ? projectSender : senders.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

/// One direction through a coupler: from line [from] to line [to].
class CouplerFlow {
  CouplerFlow(this.from, this.to);

  final int from;
  final int to;

  /// Addresses in this direction, most telegrams first.
  final groups = <FlowGroup>[];

  int get telegrams => groups.fold(0, (n, g) => n + g.count);
}

/// Traffic through the coupler of a line (x.y.0) – it separates the line from
/// the rest of the installation.
///
/// "From line X" means: the source address lies in X. "To line Y" means:
/// according to the project, devices in Y listen to the group address. Whether
/// the coupler actually forwards the telegram is only visible to the gateway for
/// telegrams that come out of the line to it ([seenAtGateway]).
class CouplerTraffic {
  CouplerTraffic._(this.line, this.coupler, this.flows, this.gatewayLine, this.seenAtGateway, this.withoutReceiver);

  /// Line behind the coupler.
  final int line;
  final DeviceInfo? coupler;

  /// First out of the line, then into the line, the gateway line first; only
  /// directions with addresses.
  final List<CouplerFlow> flows;
  final int? gatewayLine;

  /// Telegrams from the line that the gateway saw outside the line – those
  /// certainly came through the coupler.
  final int seenAtGateway;

  /// Of those, the ones on addresses without a receiver outside the line.
  final int withoutReceiver;

  /// Largest telegram count of a direction (for the arrow thickness).
  int get maxTelegrams => flows.fold(0, (n, f) => f.telegrams > n ? f.telegrams : n);

  /// [origin] gives the line of a sender (default: from its address, see
  /// [Topology.lineOfSource]).
  factory CouplerTraffic.build(
    GroupCatalog catalog,
    Iterable<Telegram> log,
    int line, {
    int? gatewayLine,
    int Function(int source) origin = lineOf,
  }) {
    // Receiver lines per address according to the project.
    final receivers = <int, Set<int>>{
      for (final g in catalog.groups.values) g.address: {for (final l in g.links) lineOf(l.device)},
    };
    final flows = <(int, int), CouplerFlow>{};
    final entries = <(int, int, int), FlowGroup>{};
    FlowGroup group(int from, int to, int ga) => entries.putIfAbsent((from, to, ga), () {
      final g = FlowGroup(ga, catalog[ga]);
      flows.putIfAbsent((from, to), () => CouplerFlow(from, to)).groups.add(g);
      return g;
    });

    // According to the project: sender on one line, receiver on another – one side
    // of it is this line.
    for (final g in catalog.groups.values) {
      final to = receivers[g.address]!;
      for (final link in g.links.where((l) => l.sends)) {
        final from = lineOf(link.device);
        for (final t in to) {
          if (t == from || (from != line && t != line)) continue;
          group(from, t, g.address).projectSender ??= link.device;
        }
      }
    }

    // Observed: origin from the source address, destination from the project.
    var seen = 0;
    var lonely = 0;
    for (final t in log) {
      final from = origin(t.source);
      final to = receivers[t.destination] ?? const <int>{};
      if (from == line && gatewayLine != null && gatewayLine != line) {
        seen++;
        if (!to.any((l) => l != line)) lonely++;
      }
      for (final target in to) {
        if (target == from || (from != line && target != line)) continue;
        final g = group(from, target, t.destination)..count += 1;
        g.senders[t.source] = (g.senders[t.source] ?? 0) + 1;
        if (g.last == null || t.time.isAfter(g.last!)) g.last = t.time;
      }
    }

    final sorted = flows.values.toList()
      ..sort((a, b) {
        // Outbound before inbound, then the gateway line first, then by line.
        final out = (a.from == line ? 0 : 1).compareTo(b.from == line ? 0 : 1);
        if (out != 0) return out;
        final oa = a.from == line ? a.to : a.from;
        final ob = b.from == line ? b.to : b.from;
        if (oa == gatewayLine) return -1;
        if (ob == gatewayLine) return 1;
        return oa.compareTo(ob);
      });
    for (final f in sorted) {
      f.groups.sort((a, b) => a.count != b.count ? b.count.compareTo(a.count) : a.address.compareTo(b.address));
    }
    return CouplerTraffic._(line, catalog.devices[line << 8], sorted, gatewayLine, seen, lonely);
  }
}

/// Telegrams from [line] per segment of the activity bar's time range, up to
/// [now]: 60 × 1 s, 60 × 1 min or 96 × 15 min from midnight. [origin] gives the
/// line of a sender (default: from its address, see [Topology.lineOfSource]).
List<int> lineActivity(
  Iterable<Telegram> log,
  int line,
  ActivityRange range,
  DateTime now, {
  int Function(int source) origin = lineOf,
}) {
  final (count, step, start) = switch (range) {
    ActivityRange.seconds => (60, const Duration(seconds: 1), now.subtract(const Duration(seconds: 60))),
    ActivityRange.hour => (60, const Duration(minutes: 1), now.subtract(const Duration(hours: 1))),
    ActivityRange.today => (96, const Duration(minutes: 15), DateTime(now.year, now.month, now.day)),
  };
  final bins = List.filled(count, 0);
  for (final t in log) {
    if (origin(t.source) != line || t.time.isBefore(start) || t.time.isAfter(now)) continue;
    final i = t.time.difference(start).inMicroseconds ~/ step.inMicroseconds;
    if (i >= 0 && i < count) bins[i]++;
  }
  return bins;
}
