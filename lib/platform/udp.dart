import 'dart:async';
import 'dart:typed_data';

import 'udp_io.dart' if (dart.library.js_interop) 'udp_web.dart' as impl;

/// Received UDP packet.
typedef Datagram = ({String host, Uint8List data});

/// Network error of the transport (socket, relay).
class UdpException implements Exception {
  const UdpException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// UDP endpoint for KNXnet/IP.
///
/// Natively a real socket; in the browser (Home Assistant add-on) a WebSocket to the add-on server,
/// which forwards the packets via UDP.
abstract class UdpEndpoint {
  static Future<UdpEndpoint> open() => impl.openUdp();

  /// Multicast reception for KNXnet/IP routing (port 3671, group [group]). Not in the browser; on
  /// iOS only with the multicast entitlement from Apple.
  static Future<UdpEndpoint> multicast(String group, int port) => impl.openMulticast(group, port);

  Stream<Datagram> get datagrams;

  /// Local port (0 if unknown – e.g. in the browser).
  int get port;

  void send(List<int> data, String host, int port);
  void close();
}

/// Local IPv4 address in the network of [gateway] for the HPAI; `null` = NAT mode.
Future<List<int>?> localAddressFor(List<int> gateway) => impl.localAddressFor(gateway);

/// Own IPv4 address in the LAN (for gateway discovery).
Future<List<int>?> localNetworkAddress() => impl.localNetworkAddress();

/// All own IPv4 addresses except loopback. Throws if the system does not report them; empty means
/// no network.
Future<List<String>> localNetworkAddresses() => impl.localNetworkAddresses();

/// Resolves a host name to an IPv4 address.
Future<List<int>> resolveIPv4(String host) async => parseIPv4(host) ?? await impl.lookupIPv4(host);

/// "192.168.1.22" → [192, 168, 1, 22]; `null` for invalid input.
List<int>? parseIPv4(String text) {
  final parts = text.trim().split('.');
  if (parts.length != 4) return null;
  final bytes = [for (final p in parts) int.tryParse(p) ?? -1];
  return bytes.every((b) => b >= 0 && b <= 255) && parts.every((p) => p.isNotEmpty && p.length <= 3) ? bytes : null;
}

String formatIPv4(List<int> ip) => ip.join('.');
