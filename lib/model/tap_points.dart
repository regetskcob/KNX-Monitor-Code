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
    final windowMs = j['windowMs'];
    return TapPoint(
      name: j['name'] as String? ?? host,
      host: host,
      port: j['port'] as int? ?? 3671,
      mode: mode,
      tunnelAddress: j['tunnelAddress'] as int?,
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

  bool get connected => state == TunnelState.connected;
}

/// Labels of the tap points of the open monitor, by number (0 = first). Rows and details show them
/// as chips; empty with a single tap point, so nothing changes there.
final tapLabels = ValueNotifier<List<String>>(const []);

/// Short label of a tap point: its line from the tunnel address ("1.2"), else [fallback].
String tapLabel(int? address, String fallback) {
  if (address == null || address == 0) return fallback;
  return '${(address >> 12) & 0x0F}.${(address >> 8) & 0x0F}';
}

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
