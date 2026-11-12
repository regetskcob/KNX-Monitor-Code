import 'package:flutter/foundation.dart';

import '../knx/knx_tunnel.dart';
import '../knx/routing_tunnel.dart';
import '../knx/telegram.dart';

/// Kind of an additional tap point (issue #8). The first tap point is the installation's normal
/// connection (ConnectionOptions); further ones are plain tunnels or routing.
enum TapMode { udp, tcp, routing }

/// An additional bus connection of an installation, e.g. one interface per line (issue #8).
@immutable
class TapPoint {
  const TapPoint({
    required this.name,
    required this.host,
    this.port = 3671,
    this.mode = TapMode.udp,
    this.tunnelAddress,
    this.window,
    this.paused = false,
  });

  /// Display name, e.g. "Linie 1.2 · MDT IP-Interface".
  final String name;
  final String host;
  final int port;
  final TapMode mode;

  /// Requested tunnel address (raw individual address), `null` = any free one.
  final int? tunnelAddress;

  /// Own merge window, e.g. for a tap point over VPN; `null` = the default (100 ms).
  final Duration? window;

  /// Paused: not connected, the tunnel stays free (ETS, visualisation).
  final bool paused;

  TapPoint copyWith({String? name, bool? paused, Duration? window}) => TapPoint(
    name: name ?? this.name,
    host: host,
    port: port,
    mode: mode,
    tunnelAddress: tunnelAddress,
    window: window ?? this.window,
    paused: paused ?? this.paused,
  );

  /// Whether [other] is the same bus connection: the same interface and port for a tunnel
  /// (whether UDP or TCP, a second tunnel there shows nothing new), the same multicast group for
  /// routing.
  bool sameConnection(TapPoint other) {
    final routing = mode == TapMode.routing, otherRouting = other.mode == TapMode.routing;
    if (routing != otherRouting) return false;
    if (routing) return _group(host) == _group(other.host);
    return host.toLowerCase() == other.host.toLowerCase() && port == other.port;
  }

  static String _group(String host) => host.isEmpty ? RoutingTunnel.multicastGroup : host;

  static final _hostPattern = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9._:-]{0,251}[A-Za-z0-9])?$');

  /// Whether [host] can be an interface address: an IP address or a host name, nothing else
  /// (the server checks the same, `BusConfig.validTapHost`).
  ///
  /// Something made of digits and dots only is meant as an IPv4 address and must be one:
  /// "300.1" is neither an address nor a name anyone resolves.
  static bool validHost(String host) {
    if (!_hostPattern.hasMatch(host)) return false;
    if (!RegExp(r'^[0-9.]+$').hasMatch(host)) return true;
    final parts = host.split('.');
    return parts.length == 4 && parts.every((p) => p.isNotEmpty && p.length <= 3 && int.parse(p) <= 255);
  }

  /// The bus connection for this tap point. Routing sends with [routingSource] as source.
  KnxTunnel create({int routingSource = 0x11FF}) => switch (mode) {
    TapMode.routing => RoutingTunnel(address: routingSource, group: host.isEmpty ? RoutingTunnel.multicastGroup : host),
    TapMode.udp ||
    TapMode.tcp => KnxTunnel(host, port: port, tcp: mode == TapMode.tcp, requestedAddress: tunnelAddress),
  };

  /// Configuration for the add-on server / box (`taps` in server.json).
  Map<String, Object?> toAddon() => {
    'name': name,
    'mode': mode.name,
    'host': host,
    'port': port,
    'tunnelAddress': tunnelAddress == null ? null : formatIndividual(tunnelAddress!),
    if (window != null) 'windowMs': window!.inMilliseconds,
    if (paused) 'paused': true,
  };

  Map<String, Object?> toJson() => {
    'name': name,
    'host': host,
    'port': port,
    'mode': mode.name,
    'tunnelAddress': ?tunnelAddress,
    if (window != null) 'windowMs': window!.inMilliseconds,
    if (paused) 'paused': true,
  };

  /// `null` for an unusable entry (no host for a tunnel, unknown mode).
  static TapPoint? fromJson(Object? json) {
    if (json is! Map) return null;
    final j = json.cast<String, Object?>();
    final mode = TapMode.values.asNameMap()[j['mode']];
    final host = j['host'];
    if (mode == null || host is! String || (host.isEmpty && mode != TapMode.routing)) return null;
    if (host.isNotEmpty && !validHost(host)) return null;
    final windowMs = j['windowMs'];
    final name = j['name'];
    final port = j['port'];
    final address = j['tunnelAddress'];
    return TapPoint(
      name: name is String && name.isNotEmpty ? (name.length > 80 ? name.substring(0, 80) : name) : host,
      host: host,
      port: port is int && port >= 1 && port <= 65535 ? port : 3671,
      mode: mode,
      tunnelAddress: address is int && address > 0 && address <= 0xFFFF ? address : null,
      window: windowMs is int && windowMs > 0 ? Duration(milliseconds: windowMs.clamp(10, 5000)) : null,
      paused: j['paused'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TapPoint &&
      other.name == name &&
      other.host == host &&
      other.port == port &&
      other.mode == mode &&
      other.tunnelAddress == tunnelAddress &&
      other.window == window &&
      other.paused == paused;

  @override
  int get hashCode => Object.hash(name, host, port, mode, tunnelAddress, window, paused);

  /// At most this many tap points per installation, the first one included.
  static const max = 8;
}

/// State of one tap point of a tunnel (MultiTunnel, SharedTunnel), for banner and connect screen.
@immutable
class TapStatus {
  const TapStatus({
    required this.index,
    required this.name,
    required this.label,
    required this.state,
    this.error,
    this.paused = false,
    this.silent = false,
    this.autoWindow,
    this.lag,
  });

  final int index;
  final String name;

  /// Short label for chips, e.g. the line "1.2".
  final String label;
  final TunnelState state;
  final String? error;
  final bool paused;

  /// Connected, but nothing arrives there while the others deliver ([TapSilence]).
  final bool silent;

  /// Merge window widened by measurement ([TapWindowMeter]), `null` while the set one fits.
  final Duration? autoWindow;

  /// Largest lag measured behind the tap point that saw the same telegram first, `null` before
  /// enough telegrams arrived at both ([TapWindowMeter.lagOf]).
  final Duration? lag;

  bool get connected => state == TunnelState.connected;

  /// Connected and delivering: only such a tap point can say "not seen here".
  bool get listening => connected && !paused && !silent;
}

/// Labels of the tap points of the open monitor, by number (0 = first). Rows and details show them
/// as chips; empty with a single tap point, so nothing changes there.
final tapLabels = ValueNotifier<List<String>>(const []);

/// Short label of a tap point: its line from the tunnel address ("1.2"), else [fallback].
String tapLabel(int? address, String fallback) {
  if (address == null || address == 0) return fallback;
  return '${(address >> 12) & 0x0F}.${(address >> 8) & 0x0F}';
}

/// Line of a tap point from its chip label: "1.2" → `area << 4 | line` (as `source >> 8`), `null`
/// for a tap point without a tunnel address, which carries its name instead.
int? lineOfTapLabel(String label) {
  final m = RegExp(r'^(\d{1,2})\.(\d{1,2})$').firstMatch(label);
  if (m == null) return null;
  final area = int.parse(m[1]!), line = int.parse(m[2]!);
  if (area > 15 || line > 15) return null;
  return area << 4 | line;
}

/// Whether [t] was seen at one tap point only although another one was listening then (issue #8):
/// it stayed in its line or a coupler filtered it. A telegram from a time when every other tap
/// point was away does not count, it had nowhere else to show up.
bool seenAtOneTapOnly(Telegram t) =>
    TapScope.labels.length > 1 && t.sightings.isEmpty && TapScope.gaps.othersListening([t.tap], t.time);

/// Spots a tap point that is connected but hears nothing (issue #8), typically routing without an
/// IP router in the network: it says "connected", yet no telegram arrives there. A tap point counts as
/// silent once the others delivered [threshold] frames since it connected and it heard none.
class TapSilence {
  /// Frames from the other tap points before a quiet one counts as silent.
  static const threshold = 20;

  final _heard = <int, int>{};
  final _base = <int, int>{};
  int _total = 0;

  /// Tap point [tap] (0 = first) connected: starts counting afresh.
  void connected(int tap) {
    _heard[tap] = 0;
    _base[tap] = _total;
  }

  /// Tap point [tap] is gone or paused: no longer judged.
  void disconnected(int tap) {
    _heard.remove(tap);
    _base.remove(tap);
  }

  /// A frame arrived at [tap]. Returns whether that changed which tap points are silent.
  bool heard(int tap) {
    final before = _base.keys.where(silent).length;
    _total++;
    if (_heard.containsKey(tap)) _heard[tap] = _heard[tap]! + 1;
    return _base.keys.where(silent).length != before;
  }

  /// Whether [tap] is connected, has heard nothing, and the others delivered enough meanwhile.
  bool silent(int tap) {
    final base = _base[tap];
    return base != null && _heard[tap] == 0 && _total - base >= threshold;
  }
}

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

/// A span in which a tap point delivered nothing because it was not connected (issue #8).
@immutable
class TapGap {
  const TapGap(this.tap, this.from, this.to, {this.paused = false});

  final int tap;
  final DateTime from;

  /// `null` while the tap point is still away.
  final DateTime? to;

  /// Paused by the user rather than unreachable.
  final bool paused;

  /// Whether a telegram of [time] fell into the gap: from [from] − [slack] up to, but not
  /// including, [to] + [slack]. The same span decides where the list draws the gap's lines
  /// (`gapMarks`), so a row marked "not reachable" never sits outside them.
  bool covers(DateTime time, Duration slack) =>
      !time.isBefore(from.subtract(slack)) && (to == null || time.isBefore(to!.add(slack)));
}

/// When each tap point of the open monitor was away (issue #8). A telegram that is missing at a
/// tap point during such a span says nothing about a coupler: the tap point could not see it.
/// Details, the filter "seen at one tap point only" and the live filter table check ask here
/// before they read "missing" as "filtered".
///
/// Only knows the time since the monitor opened ([since]); for older telegrams (history of the
/// add-on) [state] answers [TapSeen.unknown].
class TapGaps extends ChangeNotifier {
  /// Closed gaps kept per tap point; older ones leave first.
  static const kept = 200;

  /// A telegram this close to a gap may still have fallen into it (merge window, reconnect).
  static const slack = Duration(seconds: 1);

  DateTime? _since;
  final _open = <int, TapGap>{};
  final _closed = <int, List<TapGap>>{};
  int _taps = 0;

  /// Start of tracking, `null` with a single tap point.
  DateTime? get since => _since;

  /// All gaps, closed and open, oldest first.
  List<TapGap> get all =>
      [for (final list in _closed.values) ...list, ..._open.values]..sort((a, b) => a.from.compareTo(b.from));

  /// Takes over the state of the tap points at [now]: opens a gap for each that is not connected
  /// (or paused), closes it when it is back. Fewer than two tap points end tracking.
  void update(List<TapStatus> points, DateTime now) {
    if (points.length < 2) {
      if (_since == null) return;
      _since = null;
      _taps = 0;
      _open.clear();
      _closed.clear();
      notifyListeners();
      return;
    }
    _since ??= now;
    _taps = points.length;
    var changed = false;
    for (final p in points) {
      final up = p.connected && !p.paused;
      final open = _open[p.index];
      if (!up && open == null) {
        _open[p.index] = TapGap(p.index, now, null, paused: p.paused);
        changed = true;
      } else if (up && open != null) {
        _open.remove(p.index);
        final list = _closed[p.index] ??= [];
        list.add(TapGap(p.index, open.from, now, paused: open.paused));
        if (list.length > kept) list.removeAt(0);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// The gap of [tap] that covers [time], `null` if it was listening then (or nothing is known).
  TapGap? at(int tap, DateTime time) {
    if (_open[tap] case final g? when g.covers(time, slack)) return g;
    for (final g in _closed[tap] ?? const <TapGap>[]) {
      if (g.covers(time, slack)) return g;
    }
    return null;
  }

  /// What "not seen at [tap]" means for a telegram of [time].
  TapSeen state(int tap, DateTime time) {
    final since = _since;
    if (since == null || time.isBefore(since)) return TapSeen.unknown;
    final gap = at(tap, time);
    if (gap == null) return TapSeen.listening;
    return gap.paused ? TapSeen.paused : TapSeen.away;
  }

  /// Whether a telegram of [time], seen at [seen] only, could have been seen elsewhere: at least
  /// one other tap point was listening then. Without that, "seen at one tap point only" says
  /// nothing.
  bool othersListening(Iterable<int> seen, DateTime time) {
    final since = _since;
    if (since == null || time.isBefore(since)) return true;
    final here = seen.toSet();
    for (var tap = 0; tap < _taps; tap++) {
      if (!here.contains(tap) && at(tap, time) == null) return true;
    }
    return false;
  }

  /// The gaps that touch [from]…[to] as JSON for a recording, `null` without tracking. A gap
  /// still open at [to] is closed there: what came after is not part of the recording. Without
  /// [from] and [to] all of them; a gap still open then ends at its start.
  ///
  /// `{"since": µs, "n": tap points, "gaps": [[tap, from µs, to µs, 1 if paused], …]}`.
  Map<String, Object?>? toJson({DateTime? from, DateTime? to}) {
    final since = _since;
    if (since == null || _taps < 2) return null;
    DateTime end(TapGap g) {
      final limit = to == null || to.isBefore(g.from) ? g.from : to;
      return g.to == null || g.to!.isAfter(limit) && to != null ? limit : g.to!;
    }

    return {
      'since': since.microsecondsSinceEpoch,
      'n': _taps,
      'gaps': [
        for (final g in all)
          if ((to == null || !g.from.isAfter(to.add(slack))) &&
              (from == null || g.to == null || !g.to!.isBefore(from.subtract(slack))))
            [g.tap, g.from.microsecondsSinceEpoch, end(g).microsecondsSinceEpoch, if (g.paused) 1],
      ],
    };
  }

  // DateTime throws outside ±8.64e15 ms; an edited file must not break loading the recording.
  // As a double, because the int does not fit exactly in JavaScript.
  static bool _inRange(int micros) => micros.abs() <= 8.64e18;

  /// Gaps saved with a recording ([toJson]); `null` for anything unusable. Entries that do not
  /// fit (unknown tap point, end before start) are dropped, at most [kept] per tap point.
  static TapGaps? fromJson(Object? json) {
    if (json is! Map) return null;
    final since = json['since'], n = json['n'], gaps = json['gaps'];
    if (since is! int || !_inRange(since) || n is! int || n < 2 || n > TapPoint.max || gaps is! List) return null;
    final result = TapGaps()
      .._since = DateTime.fromMicrosecondsSinceEpoch(since)
      .._taps = n;
    for (final g in gaps) {
      if (g is! List || g.length < 3) continue;
      final [tap, from, to, ...rest] = g;
      if (tap is! int || tap < 0 || tap >= n || from is! int || to is! int || to < from) continue;
      if (!_inRange(from) || !_inRange(to)) continue;
      final list = result._closed[tap] ??= [];
      if (list.length >= kept) continue;
      list.add(
        TapGap(
          tap,
          DateTime.fromMicrosecondsSinceEpoch(from),
          DateTime.fromMicrosecondsSinceEpoch(to),
          paused: rest.isNotEmpty && rest.first == 1,
        ),
      );
    }
    for (final list in result._closed.values) {
      list.sort((a, b) => a.from.compareTo(b.from));
    }
    return result;
  }
}

/// The tap points of a recording (issue #8): labels and names as the monitor showed them, and when
/// each one was away. Saved with the recording so that, opened later, it shows chips, the path
/// through the installation and the gaps as live did.
class TapRecord {
  TapRecord({required this.labels, required this.names, required this.gaps});

  /// Chip labels by tap point number (0 = first), as [tapLabels].
  final List<String> labels;

  /// Names by tap point number, as set up (e.g. "Linie 1.2 · MDT IP-Interface").
  final List<String> names;

  /// When each tap point was away; empty when nothing was tracked.
  final TapGaps gaps;

  /// What the monitor knows now about [points] and [gaps], for a recording over [from]…[to];
  /// `null` with a single tap point (then the recording stays as before).
  static TapRecord? capture(
    List<String> labels,
    List<TapStatus> points,
    TapGaps gaps, {
    required DateTime from,
    required DateTime to,
  }) {
    if (labels.length < 2) return null;
    final names = [
      for (var i = 0; i < labels.length; i++) points.where((p) => p.index == i).firstOrNull?.name ?? labels[i],
    ];
    return TapRecord(
      labels: List.unmodifiable(labels),
      names: List.unmodifiable(names),
      gaps: TapGaps.fromJson(gaps.toJson(from: from, to: to)) ?? TapGaps(),
    );
  }

  /// `{"labels": […], "names": […], "gaps": …}` – older versions ignore the key altogether.
  Map<String, Object?> toJson() => {
    'labels': labels,
    'names': names,
    // Already cut to the recording when captured.
    'gaps': ?gaps.toJson(),
  };

  /// `null` for anything unusable, or with fewer than two tap points.
  static TapRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final labels = json['labels'], names = json['names'];
    if (labels is! List || labels.length < 2 || labels.length > TapPoint.max) return null;
    String text(Object? v, String fallback) {
      if (v is! String || v.isEmpty) return fallback;
      final clean = v.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ');
      return clean.length > 80 ? clean.substring(0, 80) : clean;
    }

    final l = [for (final (i, v) in labels.indexed) text(v, '${i + 1}')];
    final n = [for (var i = 0; i < l.length; i++) text(names is List && i < names.length ? names[i] : null, l[i])];
    var gaps = TapGaps.fromJson(json['gaps']);
    // Gaps for a different number of tap points belong to something else.
    if (gaps != null && gaps._taps != l.length) gaps = null;
    return TapRecord(labels: List.unmodifiable(l), names: List.unmodifiable(n), gaps: gaps ?? TapGaps());
  }
}

/// Tap points of what is on screen (issue #8): those of an opened recording that saved them
/// ([TapRecord]), else the live monitor's ([tapLabels], [tapGaps]). Rows, details, filters,
/// topology and exports ask here, so a recording shows its own tap points and gaps.
abstract final class TapScope {
  static final _open = <TapRecord>[];

  /// Chip labels by tap point number; empty or one entry with a single tap point.
  static List<String> get labels => _open.isEmpty ? tapLabels.value : _open.last.labels;

  /// When each tap point was away.
  static TapGaps get gaps => _open.isEmpty ? tapGaps : _open.last.gaps;

  /// Name of tap point [tap] where an opened recording saved one that says more than its label,
  /// else `null` (live, or the name is the label).
  static String? nameOf(int tap) {
    final labels = TapScope.labels;
    final names = _open.isEmpty ? const <String>[] : _open.last.names;
    if (tap < 0 || tap >= labels.length || tap >= names.length) return null;
    final name = names[tap];
    return name.isEmpty || name == labels[tap] ? null : name;
  }

  /// Label of tap point [tap] with its name where a recording saved one that says more, e.g.
  /// "1.2 · MDT IP-Interface"; else the label, as live.
  static String described(int tap) {
    final labels = TapScope.labels;
    if (tap < 0 || tap >= labels.length) return '${tap + 1}';
    final name = nameOf(tap);
    return name == null ? labels[tap] : '${labels[tap]} · $name';
  }

  /// A recording with [record] is shown; `null` (a recording without tap points) changes nothing.
  static void open(TapRecord? record) {
    if (record != null) _open.add(record);
  }

  /// The recording with [record] is closed again.
  static void close(TapRecord? record) {
    if (record != null) _open.removeWhere((r) => identical(r, record));
  }
}

/// Whether a tap point could have seen a telegram ([TapGaps.state]).
enum TapSeen {
  /// Connected at that time: missing means filtered or line-local.
  listening,

  /// Not reachable at that time: missing means nothing.
  away,

  /// Paused by the user at that time.
  paused,

  /// Before the monitor opened: not known.
  unknown,
}

/// Gaps of the tap points of the open monitor; follows [KnxTunnel.tapPoints].
final tapGaps = TapGaps();

/// Bus load and errors at one tap point (issue #8): what that line really carried.
@immutable
class TapLoad {
  const TapLoad({required this.telegrams, required this.repeats, required this.busy, required this.span});

  /// Telegrams seen at the tap point within [span].
  final int telegrams;

  /// Of those, with the repeat flag.
  final int repeats;

  /// Seconds the line was busy with them (TP, 9600 bit/s).
  final double busy;
  final Duration span;

  double get perMinute => span.inMilliseconds <= 0 ? 0 : telegrams * 60000 / span.inMilliseconds;

  /// Share of the time the line was busy, in percent.
  double get percent => span.inMilliseconds <= 0 ? 0 : (busy * 100000 / span.inMilliseconds).clamp(0, 100).toDouble();

  /// Per tap point from the end of [log] (sorted by time), over the last [span] before [now].
  /// A sighting counts at its tap point, so a forwarded telegram loads every line it reached.
  static List<TapLoad> of(
    List<Telegram> log,
    int taps, {
    required DateTime now,
    Duration span = const Duration(minutes: 1),
  }) {
    final count = List.filled(taps, 0), repeats = List.filled(taps, 0);
    final busy = List.filled(taps, 0.0);
    final from = now.subtract(span);
    for (var i = log.length - 1; i >= 0; i--) {
      final t = log[i];
      if (t.time.isBefore(from)) break;
      if (t.time.isAfter(now)) continue;
      // As BusMetric.busySeconds: frame, gap and acknowledgement.
      final seconds = (50 + 13 * (t.isSmall ? 9 : 9 + t.data.length) + 15 + 13) / 9600;
      for (final tap in t.taps) {
        if (tap < 0 || tap >= taps) continue;
        count[tap]++;
        if (t.repeated) repeats[tap]++;
        busy[tap] += seconds;
      }
    }
    return [
      for (var i = 0; i < taps; i++) TapLoad(telegrams: count[i], repeats: repeats[i], busy: busy[i], span: span),
    ];
  }
}
