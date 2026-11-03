import 'dart:async';

import 'package:flutter/foundation.dart';

import '../l10n/locale_controller.dart';
import '../platform/udp.dart';
import 'knx_tunnel.dart';
import 'telegram.dart';

/// KNXnet/IP routing (multicast 224.0.23.12) instead of a tunnel.
///
/// Occupies no tunnel slot and sees everything the IP router forwards onto the line (mind the
/// filter tables). Sends with [address] as source; since routing has no confirmation, the link
/// creates it itself.
class RoutingTunnel extends KnxTunnel {
  RoutingTunnel({
    required this.address,
    this.group = multicastGroup,
    int port = 3671,
    this.open = UdpEndpoint.multicast,
    this.networkAddresses = localNetworkAddresses,
    this.networkCheck = const Duration(seconds: 20),
  }) : super(group, port: port);

  static const multicastGroup = '224.0.23.12';

  /// Own individual address on the bus.
  final int address;
  final String group;

  final Future<UdpEndpoint> Function(String group, int port) open;
  final Future<List<String>> Function() networkAddresses;

  /// Interval of the network check. Routing is silent as long as the bus is silent and has no
  /// heartbeat; "no telegrams" therefore says nothing about the connection. So we only check
  /// whether the network we joined in still exists. A failed IP router goes unnoticed this way: it
  /// cannot be told apart from a quiet installation.
  final Duration networkCheck;

  Timer? _networkTimer;
  Set<String> _joinedOn = const {};
  int _networkMisses = 0;

  UdpEndpoint? _socket;
  StreamSubscription<Datagram>? _sub;
  DateTime _busyUntil = DateTime(0);

  @override
  String get kind => 'Routing';

  @override
  bool get supportsBusMonitor => false;

  @override
  Future<void> connect({Duration timeout = const Duration(seconds: 5)}) async {
    if (state.value != TunnelState.disconnected) return;
    state.value = TunnelState.connecting;
    error.value = null;
    try {
      _socket = await open(group, port);
    } on UdpException catch (e) {
      state.value = TunnelState.disconnected;
      throw KnxException(s.routingUnavailable(e.message), ConnectProblem.routing);
    }
    _sub = _socket!.datagrams.listen(_onDatagram, onError: (Object e) => connectionLost(s.errorSocket('$e')));
    tunnelAddress = address;
    state.value = TunnelState.connected;
    _networkMisses = 0;
    _joinedOn = await _addressesOrNull() ?? const {};
    _networkTimer = Timer.periodic(networkCheck, (_) => unawaited(_checkNetwork()));
  }

  Future<Set<String>?> _addressesOrNull() async {
    try {
      return (await networkAddresses()).toSet();
    } on Object catch (e) {
      debugPrint('Routing: Netz nicht prüfbar: $e');
      return null;
    }
  }

  /// Without a response from the system everything stays as it is. Twice in a row, so a brief Wi-Fi
  /// switch does not disconnect. A different address means the group membership is tied to the old
  /// network; reconnecting joins again.
  Future<void> _checkNetwork() async {
    final now = await _addressesOrNull();
    if (now == null || state.value != TunnelState.connected) return;
    final gone = now.isEmpty || (_joinedOn.isNotEmpty && _joinedOn.intersection(now).isEmpty);
    if (!gone) {
      _networkMisses = 0;
      if (_joinedOn.isEmpty) _joinedOn = now;
      return;
    }
    if (++_networkMisses >= 2) connectionLost(s.errorNetworkGone);
  }

  /// Socket and check belong to this class; the base class's cleanup does not know them.
  @override
  void connectionLost(String reason) {
    _release();
    super.connectionLost(reason);
  }

  void _release() {
    _networkTimer?.cancel();
    _networkTimer = null;
    unawaited(_sub?.cancel());
    _sub = null;
    _socket?.close();
    _socket = null;
  }

  void _onDatagram(Datagram dg) {
    final p = dg.data;
    if (p.length < 6 || p[0] != 0x06 || p[1] != 0x10) return;
    final service = (p[2] << 8) | p[3];
    switch (service) {
      case 0x0530: // ROUTING_INDICATION
        final cemi = Uint8List.sublistView(p, 6);
        if (cemi.length > 5 && cemi[0] == 0x29 && _sourceOf(cemi) == address) return;
        receiveCemi(cemi);
      case 0x0532: // ROUTING_BUSY
        if (p.length >= 10) {
          final wait = (p[8] << 8) | p[9];
          _busyUntil = DateTime.now().add(Duration(milliseconds: wait.clamp(20, 1000)));
        }
    }
  }

  static int _sourceOf(Uint8List c) {
    final i = 2 + c[1];
    return c.length < i + 4 ? -1 : (c[i + 2] << 8) | c[i + 3];
  }

  @override
  @protected
  Future<void> transmit(Uint8List cemi) async {
    final socket = _socket;
    if (socket == null || state.value != TunnelState.connected) throw KnxException(s.errorNotConnected);
    final wait = _busyUntil.difference(DateTime.now());
    if (!wait.isNegative) await Future<void>.delayed(wait);
    final i = 2 + cemi[1];
    final ind = Uint8List.fromList(cemi)
      ..[0] = 0x29
      ..[i + 2] = address >> 8
      ..[i + 3] = address & 0xFF;
    socket.send([0x06, 0x10, 0x05, 0x30, (6 + ind.length) >> 8, (6 + ind.length) & 0xFF, ...ind], group, port);
    // Own confirmation (L_Data.con): routing does not acknowledge.
    receiveCemi(Uint8List.fromList(ind)..[0] = 0x2E);
    // Flow control: at most 50 telegrams per second.
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  @override
  Future<void> disconnect() async {
    _release();
    state.value = TunnelState.disconnected;
  }

  /// Hint for the display: source when sending.
  String get addressText => formatIndividual(address);
}
