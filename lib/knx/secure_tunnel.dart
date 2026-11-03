import 'dart:async';

import 'package:flutter/foundation.dart';

import '../l10n/locale_controller.dart';
import 'knx_tunnel.dart';
import 'secure/ip_secure.dart';

/// Tunnel over KNX IP Secure (TCP, encrypted, AN159).
///
/// User ID and password are in the ETS at the interface's tunnel (or in the keyring); the device
/// authentication code is optional and verifies that it really is our own interface responding.
class SecureTunnel extends KnxTunnel {
  SecureTunnel(
    super.host, {
    super.port,
    super.requestedAddress,
    required this.userId,
    required this.userPassword,
    this.deviceAuthentication,
  }) : super(tcp: true);

  final int userId;
  final String userPassword;
  final String? deviceAuthentication;

  IpSecureSession? _session;
  Timer? _keepalive;

  @override
  String get kind => 'IP Secure';

  @override
  bool get supportsBusMonitor => false;

  @override
  @protected
  Future<void> openSession() async {
    final session = IpSecureSession(
      userId: userId,
      userPassword: userPassword,
      deviceAuthentication: deviceAuthentication,
    );
    _session = session;
    session.onStatus = (status) {
      if (status != IpSecureSession.statusKeepalive && status != IpSecureSession.statusOk) {
        connectionLost(s.secureSessionClosed);
      }
    };
    try {
      await session.handshake(sendRaw);
    } on IpSecureException catch (e) {
      throw switch (e.reason) {
        'auth' => KnxException(s.secureAuthFailed, ConnectProblem.secureAuth),
        'device' => KnxException(s.secureDeviceAuthFailed, ConnectProblem.secureDevice),
        _ => KnxException(s.errorGatewayNoResponse, ConnectProblem.noResponse),
      };
    }
    // Without traffic the gateway closes the session after 60 s.
    _keepalive = Timer.periodic(const Duration(seconds: 50), (_) {
      if (session.established) sendRaw(session.keepalive());
    });
  }

  @override
  @protected
  List<int> encodeOutgoing(List<int> frame) => _session?.established == true ? _session!.wrap(frame) : frame;

  @override
  @protected
  Uint8List? decodeIncoming(Uint8List packet) => _session?.handle(packet);

  @override
  @protected
  void closeSession() {
    _keepalive?.cancel();
    _keepalive = null;
    final session = _session;
    _session = null;
    if (session != null && session.established) sendRaw(session.close());
  }
}
