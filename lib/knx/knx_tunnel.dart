import 'dart:async';

import 'package:flutter/foundation.dart';

import '../l10n/locale_controller.dart';
import '../platform/tcp.dart';
import '../platform/udp.dart';
import 'busmon.dart';
import 'gateway_info.dart';

import 'package:knx/secure.dart';

import 'secure/keyring_store.dart';
import 'telegram.dart';

enum TunnelState { disconnected, connecting, connected }

/// Reason for a connection error, for help with a next step.
enum ConnectProblem {
  /// No response to the connection request (wrong IP, other network, port).
  noResponse,

  /// Network unreachable (no Wi-Fi, invalid address, firewall).
  network,

  /// All tunnels in use (ETS, visualisation, logic module hold them).
  noFreeTunnel,

  /// Requested fixed tunnel address in use or rejected.
  tunnelAddress,

  /// The gateway does not support tunnelling or this tunnel type.
  unsupported,

  /// IP Secure: user or password rejected.
  secureAuth,

  /// IP Secure: device authentication code does not match.
  secureDevice,

  /// IP Secure selected, but no credentials stored.
  secureMissing,

  /// Routing (multicast) not possible.
  routing,
}

/// [ConnectProblem] for its name (from the add-on server), otherwise `null`.
ConnectProblem? connectProblemNamed(String? name) => name == null ? null : ConnectProblem.values.asNameMap()[name];

class KnxException implements Exception {
  const KnxException(this.message, [this.problem]);
  final String message;

  /// Known reason, otherwise `null`.
  final ConnectProblem? problem;
  @override
  String toString() => message;
}

/// Minimal KNXnet/IP tunnelling client (UDP or TCP, link layer).
///
/// Establishes a tunnel connection, acknowledges incoming tunnelling requests, keeps the connection
/// alive with a heartbeat, delivers group telegrams via [telegrams] and sends read/write telegrams.
///
/// Subclasses (routing, IP Secure, shared tunnel in the add-on, demo) override [connect],
/// [disconnect] and [transmit] and feed received frames in via [receiveCemi].
class KnxTunnel {
  KnxTunnel(
    this.host, {
    this.port = 3671,
    this.busMonitor = false,
    this.tcp = false,
    this.requestedAddress,
    this.fallback = true,
  });

  final String host;
  final int port;

  /// Tunnel over TCP instead of UDP (KNXnet/IP 2.0) – more robust against packet loss.
  final bool tcp;

  /// Requested tunnel address (tunnelling v2, "Extended CRI").
  final int? requestedAddress;

  /// If [requestedAddress] is in use or unknown, take a free slot.
  final bool fallback;

  /// Short description of the connection type for display and diagnostics.
  String get kind => tcp ? 'TCP' : 'UDP';

  /// Whether a bus monitor tunnel can be opened over the same interface.
  bool get supportsBusMonitor => true;

  /// Bus monitor tunnel: all frames including acknowledgements and errors ([busmon]); sending is
  /// not possible.
  final bool busMonitor;

  final _busmon = StreamController<BusmonFrame>.broadcast();

  /// Raw frames in bus monitor mode.
  Stream<BusmonFrame> get busmon => _busmon.stream;

  final state = ValueNotifier(TunnelState.disconnected);

  /// Reason for the last disconnection, unless disconnected by us.
  final error = ValueNotifier<String?>(null);

  /// Device name of the gateway (from DESCRIPTION_RESPONSE), once known.
  final deviceName = ValueNotifier<String?>(null);

  /// Full self-description of the gateway, once known.
  final gatewayInfo = ValueNotifier<GatewayInfo?>(null);

  /// Communication channel of the tunnel connection (for the gateway info).
  int get channel => _channel;

  /// Individual address the gateway assigned to this tunnel.
  int? tunnelAddress;

  final _telegrams = StreamController<Telegram>.broadcast();
  Stream<Telegram> get telegrams => _telegrams.stream;

  /// All data frames including individual addressing (for device diagnostics).
  final _frames = StreamController<CemiFrame>.broadcast();
  Stream<CemiFrame> get frames => _frames.stream;

  UdpEndpoint? _socket;
  StreamSubscription<Datagram>? _socketSub;
  TcpStream? _tcp;
  StreamSubscription<Uint8List>? _tcpSub;
  String? _gateway;

  /// Local address for the HPAI; `null` = NAT mode.
  List<int>? _localIp;
  int _channel = 0;
  int? _lastSeq;
  int _sendSeq = 0;
  Timer? _heartbeat;
  Timer? _heartbeatTimeout;
  Completer<Uint8List>? _connectResponse;
  Completer<int>? _ack;
  int? _ackSeq;
  Future<void> _sendQueue = Future.value();

  static const _descriptionRequest = 0x0203;
  static const _descriptionResponse = 0x0204;
  static const _connectRequest = 0x0205;
  static const _connectResponseType = 0x0206;
  static const _stateRequest = 0x0207;
  static const _stateResponse = 0x0208;
  static const _disconnectRequest = 0x0209;
  static const _disconnectResponse = 0x020A;
  static const _tunnelRequest = 0x0420;
  static const _tunnelAck = 0x0421;

  Future<void> connect({Duration timeout = const Duration(seconds: 5)}) async {
    if (state.value != TunnelState.disconnected) return;
    state.value = TunnelState.connecting;
    error.value = null;
    try {
      final gateway = await resolveIPv4(host);
      _gateway = formatIPv4(gateway);
      if (tcp) {
        _tcp = await TcpStream.open(_gateway!, port);
        _tcpSub = _tcp!.packets.listen((p) {
          final plain = decodeIncoming(p);
          if (plain != null) _onPacket(plain);
        }, onError: (Object e) => _lost(s.errorSocket('$e')));
        await openSession();
      } else {
        _localIp = await localAddressFor(gateway);
        _socket = await UdpEndpoint.open();
        _socketSub = _socket!.datagrams.listen(_onDatagram, onError: (Object e) => _lost(s.errorSocket('$e')));
      }

      var res = await _requestConnection(requestedAddress, timeout);
      if (res[7] != 0 && requestedAddress != null && fallback && _addressProblem(res[7])) {
        res = await _requestConnection(null, timeout);
      }
      final status = res[7];
      if (status != 0) throw KnxException(_statusText(status), _statusProblem(status));
      _channel = res[6];
      tunnelAddress = res.length >= 20 ? (res[18] << 8) | res[19] : null;
      _lastSeq = null;
      _sendSeq = 0;
      state.value = TunnelState.connected;
      _heartbeat = Timer.periodic(const Duration(seconds: 60), (_) => _sendHeartbeat());
      if (gatewayInfo.value == null && !tcp) _send(_descriptionRequest, _hpai());
    } on UdpException catch (e) {
      _cleanup();
      throw KnxException(s.errorNetwork(e.message), ConnectProblem.network);
    } catch (_) {
      _cleanup();
      rethrow;
    }
  }

  Future<Uint8List> _requestConnection(int? address, Duration timeout) {
    _connectResponse = Completer();
    _send(_connectRequest, [
      ..._hpai(),
      ..._hpai(),
      // CRI: tunnel, bus monitor or link layer; with an address as Extended CRI
      if (address == null || busMonitor) ...[
        0x04,
        0x04,
        busMonitor ? 0x80 : 0x02,
        0x00,
      ] else ...[
        0x06,
        0x04,
        0x02,
        0x00,
        address >> 8,
        address & 0xFF,
      ],
    ]);
    return _connectResponse!.future.timeout(
      timeout,
      onTimeout: () => throw KnxException(s.errorGatewayNoResponse, ConnectProblem.noResponse),
    );
  }

  /// Reasons for which a tunnel without a fixed address may still work.
  static bool _addressProblem(int status) => const {0x23, 0x25, 0x28, 0x2D, 0x2E}.contains(status);

  Future<void> disconnect() async {
    if (state.value == TunnelState.connected) {
      _send(_disconnectRequest, [_channel, 0x00, ..._hpai()]);
      // Wait briefly so the packet goes out before the socket closes.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    _cleanup();
  }

  void dispose() {
    // disconnect() waits briefly; datagrams from that time must no longer flow into the streams
    // that are about to close.
    _socketSub?.cancel();
    _socketSub = null;
    disconnect();
    _telegrams.close();
    _frames.close();
    _busmon.close();
  }

  /// Injects a telegram as if it came from the bus (tests, benchmark, screenshots).
  void inject(Telegram t) => _telegrams.add(t);

  /// For subclasses (IP Secure): after opening the TCP connection, before the tunnel request – e.g.
  /// to negotiate a session.
  @protected
  Future<void> openSession() async {}

  /// For subclasses (IP Secure): wraps an outgoing KNXnet/IP frame.
  @protected
  List<int> encodeOutgoing(List<int> frame) => frame;

  /// For subclasses (IP Secure): unwraps a received frame; `null` = discard.
  @protected
  Uint8List? decodeIncoming(Uint8List packet) => packet;

  /// For subclasses (IP Secure): ends the session before the connection closes.
  @protected
  void closeSession() {}

  /// For subclasses: sends raw bytes without [encodeOutgoing] (handshake).
  @protected
  void sendRaw(List<int> frame) => _tcp?.send(frame);

  /// For subclasses: a received cEMI frame (L_Data.ind/.con, bus monitor).
  @protected
  void receiveCemi(Uint8List input) {
    if (_telegrams.isClosed) return;
    var cemi = input;
    // KNX Data Secure: decrypt with a loaded keyring, otherwise count.
    if (DataSecure.isSecure(cemi)) {
      final keys = KeyringStore.instance;
      final ds = keys.dataSecure;
      if (ds == null) {
        keys.withoutKey.value++;
      } else {
        final (result, plain) = ds.receive(cemi);
        switch (result) {
          case SecureResult.decrypted:
            cemi = plain;
          case SecureResult.noKey:
            keys.withoutKey.value++;
          case SecureResult.invalid:
            keys.rejected.value++;
          case SecureResult.plain:
            break;
        }
      }
    }
    if (cemi.isNotEmpty && cemi[0] == 0x2B) {
      final raw = BusmonFrame.parse(cemi);
      if (raw != null) _busmon.add(raw);
      return;
    }
    final frame = CemiFrame.parse(cemi);
    if (frame != null) _frames.add(frame);
    final t = Telegram.fromCemi(cemi);
    if (t != null) _telegrams.add(t);
  }

  /// For subclasses: the connection was lost.
  @protected
  void connectionLost(String reason) => _lost(reason);

  /// Hands an L_Data.req to the interface. Returns once it has accepted it; otherwise throws
  /// [KnxException].
  @protected
  Future<void> transmit(Uint8List cemi) => _sendTunnel(cemi);

  /// Check before every send. Set only with the team feature (`Team`); otherwise `null` and without
  /// any effect. Throws [KnxException] if the role does not allow it, and writes the send log.
  /// Lives here so that all write paths (send, planner, replay) pass through it.
  static Future<void> Function(int destination, {required bool read, int? small, List<int> data})? sendGate;

  /// Sends GroupValueRead to [destination]. Result as with [sendFrame]: confirmation by the bus.
  Future<bool?> read(int destination) {
    final gate = sendGate;
    if (gate == null) return sendFrame(buildGroupRequest(destination, TelegramType.read));
    return gate(destination, read: true).then((_) => sendFrame(buildGroupRequest(destination, TelegramType.read)));
  }

  /// Sends GroupValueWrite. Either [small] (0–63, e.g. DPT 1) or [data].
  Future<bool?> write(int destination, {int? small, List<int> data = const []}) {
    final gate = sendGate;
    if (gate == null) return sendFrame(buildGroupRequest(destination, TelegramType.write, small: small, data: data));
    return gate(
      destination,
      read: false,
      small: small,
      data: data,
    ).then((_) => sendFrame(buildGroupRequest(destination, TelegramType.write, small: small, data: data)));
  }

  /// Sends an L_Data.req and waits for the confirmation (L_Data.con).
  ///
  /// `true` = acknowledged by the bus, `false` = not acknowledged (e.g. no receiver), `null` = no
  /// confirmation within [timeout]. Throws [KnxException] if the gateway does not accept the frame.
  Future<bool?> sendFrame(Uint8List cemi, {Duration timeout = const Duration(seconds: 3)}) async {
    final i = 2 + cemi[1]; // after message code and additional info
    final group = cemi[i + 1] & 0x80 != 0;
    final destination = (cemi[i + 4] << 8) | cemi[i + 5];
    final confirmation = Completer<bool?>();
    final sub = frames.listen((f) {
      if (f.isConfirmation && f.destination == destination && f.groupAddressed == group && !confirmation.isCompleted) {
        confirmation.complete(!f.confirmError);
      }
    });
    try {
      await _enqueue(cemi);
      return await confirmation.future.timeout(timeout, onTimeout: () => null);
    } finally {
      await sub.cancel();
    }
  }

  // ---------------------------------------------------------------------------

  Future<void> _enqueue(Uint8List plain) {
    // Secured group address: encrypt (the source goes into the MAC).
    final ds = KeyringStore.instance.dataSecure;
    final cemi = ds == null || tunnelAddress == null ? plain : ds.send(plain, source: tunnelAddress!);
    final f = _sendQueue.then((_) => transmit(cemi));
    _sendQueue = f.catchError((_) {});
    return f;
  }

  Future<void> _sendTunnel(Uint8List cemi) async {
    if (state.value != TunnelState.connected) {
      throw KnxException(s.errorNotConnected);
    }
    final seq = _sendSeq;
    if (tcp) {
      // TCP: no tunnel acknowledgement, TCP ensures delivery.
      _send(_tunnelRequest, [0x04, _channel, seq, 0x00, ...cemi]);
      _sendSeq = (seq + 1) & 0xFF;
      return;
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      _ack = Completer();
      _ackSeq = seq;
      _send(_tunnelRequest, [0x04, _channel, seq, 0x00, ...cemi]);
      try {
        final status = await _ack!.future.timeout(const Duration(seconds: 1));
        _sendSeq = (seq + 1) & 0xFF;
        if (status != 0) {
          throw KnxException(s.errorTelegramRejected(status.toRadixString(16)));
        }
        return;
      } on TimeoutException {
        // repeat once
      } finally {
        _ack = null;
      }
    }
    throw KnxException(s.errorNoAck);
  }

  void _onDatagram(Datagram dg) {
    // Only our own gateway: otherwise anyone on the LAN with a guessed channel ID could disconnect
    // the tunnel or inject telegrams.
    if (dg.host != _gateway) return;
    _onPacket(dg.data);
  }

  void _onPacket(Uint8List p) {
    if (p.length < 6 || p[0] != 0x06 || p[1] != 0x10) return;
    final service = (p[2] << 8) | p[3];

    switch (service) {
      case _connectResponseType:
        if (p.length >= 8 && !(_connectResponse?.isCompleted ?? true)) {
          _connectResponse!.complete(p);
        }
      case _tunnelRequest:
        _onTunnelRequest(p);
      case _tunnelAck:
        if (p.length >= 10 && p[7] == _channel && p[8] == _ackSeq) {
          if (!(_ack?.isCompleted ?? true)) _ack!.complete(p[9]);
        }
      case _stateResponse:
        if (p.length >= 8 && p[6] == _channel) {
          _heartbeatTimeout?.cancel();
          if (p[7] != 0) _lost(s.errorClosedByGateway);
        }
      case _disconnectRequest:
        if (p.length >= 7 && p[6] == _channel) {
          _send(_disconnectResponse, [_channel, 0x00]);
          _lost(s.errorClosedByGateway);
        }
      case _descriptionResponse:
        final info = GatewayInfo.parse(Uint8List.sublistView(p, 6));
        if (info != null) {
          gatewayInfo.value = info;
          if (info.name.isNotEmpty) deviceName.value = info.name;
        }
    }
  }

  void _onTunnelRequest(Uint8List p) {
    // The connection header length comes from the packet: it must not point past its end.
    if (p.length < 10 || p[7] != _channel || 6 + p[6] > p.length) return;
    if (!tcp) {
      final seq = p[8];
      _send(_tunnelAck, [0x04, _channel, seq, 0x00]);
      if (seq == _lastSeq) return; // repetition
      _lastSeq = seq;
    }
    receiveCemi(Uint8List.sublistView(p, 6 + p[6]));
  }

  void _sendHeartbeat([int attempt = 1]) {
    if (state.value != TunnelState.connected) return;
    _send(_stateRequest, [_channel, 0x00, ..._hpai()]);
    _heartbeatTimeout?.cancel();
    _heartbeatTimeout = Timer(const Duration(seconds: 10), () {
      if (attempt >= 3) {
        _lost(s.errorGatewayStoppedResponding);
      } else {
        _sendHeartbeat(attempt + 1);
      }
    });
  }

  void _lost(String reason) {
    if (state.value == TunnelState.disconnected) return;
    error.value = reason;
    _cleanup();
  }

  void _cleanup() {
    closeSession();
    _heartbeat?.cancel();
    _heartbeatTimeout?.cancel();
    _socketSub?.cancel();
    _socketSub = null;
    _socket?.close();
    _socket = null;
    _tcpSub?.cancel();
    _tcpSub = null;
    _tcp?.close();
    _tcp = null;
    state.value = TunnelState.disconnected;
  }

  void _send(int service, List<int> body) {
    final len = 6 + body.length;
    final frame = [0x06, 0x10, service >> 8, service & 0xFF, len >> 8, len & 0xFF, ...body];
    if (_tcp != null) {
      _tcp!.send(encodeOutgoing(frame));
    } else {
      _socket?.send(frame, _gateway!, port);
    }
  }

  /// Host Protocol Address Information (UDP or TCP, IPv4).
  List<int> _hpai() {
    if (tcp) return [0x08, 0x02, 0, 0, 0, 0, 0, 0];
    final p = _socket?.port ?? 0;
    final ip = _localIp;
    // 0.0.0.0:0 = NAT mode: the gateway responds to the sender address.
    if (ip == null || p == 0) return [0x08, 0x01, 0, 0, 0, 0, 0, 0];
    return [0x08, 0x01, ...ip, p >> 8, p & 0xFF];
  }

  /// Status codes according to KNXnet/IP Core (03.08.02).
  static ConnectProblem? _statusProblem(int status) => switch (status) {
    0x24 => ConnectProblem.noFreeTunnel,
    0x25 || 0x2E || 0x28 || 0x2D => ConnectProblem.tunnelAddress,
    0x22 || 0x23 || 0x29 => ConnectProblem.unsupported,
    _ => null,
  };

  static String _statusText(int status) => switch (status) {
    0x22 => s.errorTunnelUnsupported,
    0x23 => s.errorOptionUnsupported,
    0x24 => s.errorNoFreeTunnel,
    0x25 || 0x2E => s.errorTunnelAddressInUse,
    0x28 || 0x2D => s.errorTunnelAddressRejected,
    0x29 => s.errorLayerUnsupported,
    _ => s.errorConnectionRejected(status.toRadixString(16)),
  };
}
