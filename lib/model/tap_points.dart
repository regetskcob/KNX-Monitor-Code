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
  });

  final int index;
  final String name;

  /// Short label for chips, e.g. the line "1.2".
  final String label;
  final TunnelState state;
  final String? error;
  final bool paused;

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
