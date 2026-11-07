/// Rules of the UDP relay `/ws` (bin/server.dart): the web app opens its own
/// KNXnet/IP tunnel through it, since browsers cannot send UDP. The relay
/// must not become a general UDP hop into the home network: only well-formed
/// KNXnet/IP packets, only to addresses where a KNX gateway can be, and back
/// only from addresses the relay sent to.
library;

import 'dart:io';

/// Standard KNXnet/IP port.
const knxPort = 3671;

/// KNXnet/IP service types a client exchanges with a gateway: core (search,
/// description, connect, connection state, disconnect, extended search),
/// device management, tunnelling (with feature services), routing, secure.
const _services = {
  0x0201, 0x0202, 0x0203, 0x0204, 0x0205, 0x0206, 0x0207, 0x0208, 0x0209, 0x020A, 0x020B, 0x020C, //
  0x0310, 0x0311, //
  0x0420, 0x0421, 0x0422, 0x0423, 0x0424, 0x0425, //
  0x0530, 0x0531, 0x0532, 0x0533, //
  0x0950, 0x0951, 0x0952, 0x0953, 0x0954, 0x0955,
};

/// Whether [packet] is a complete KNXnet/IP frame: header 06 10, a known
/// service type and a total length equal to the packet's length. Arbitrary
/// UDP protocols do not survive this, even if they start with 06 10 (a DNS
/// query with that transaction ID would need as many questions as bytes).
bool relayPacketWellFormed(List<int> packet) =>
    packet.length >= 6 &&
    packet[0] == 0x06 &&
    packet[1] == 0x10 &&
    _services.contains((packet[2] << 8) | packet[3]) &&
    ((packet[4] << 8) | packet[5]) == packet.length;

/// Search responses (classic and extended): they come from every gateway on
/// the network, also from those the relay did not send to (multicast search).
bool relaySearchResponse(List<int> packet) =>
    packet.length >= 4 && packet[2] == 0x02 && (packet[3] == 0x02 || packet[3] == 0x0C);

/// Targets that can be a KNX gateway: private networks (RFC 1918), CGNAT/VPN
/// (100.64/10, e.g. Tailscale), link-local, the KNXnet/IP multicast address
/// (search, routing) and broadcast. Loopback only on [knxPort] (a gateway or
/// test gateway on the same machine): with the host network the container
/// shares the host's loopback, and services there trust local senders.
bool relayTargetAllowed(InternetAddress address, int port) {
  if (address.type != InternetAddressType.IPv4 || port <= 0 || port > 0xFFFF) return false;
  final [a, b, c, d] = address.rawAddress;
  if (a == 127) return port == knxPort;
  return a == 10 ||
      (a == 172 && b >= 16 && b < 32) ||
      (a == 192 && b == 168) ||
      (a == 100 && b >= 64 && b < 128) ||
      (a == 169 && b == 254) ||
      (a == 224 && b == 0 && c == 23 && d == 12) ||
      (a == 255 && b == 255 && c == 255 && d == 255);
}
