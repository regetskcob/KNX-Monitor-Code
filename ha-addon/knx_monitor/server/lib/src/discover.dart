import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:knx/knx.dart';

/// A discovered KNXnet/IP device: address, port and the DIBs of the response
/// (device info, services, tunnelling slots), which the app evaluates itself.
typedef Discovered = ({String host, int port, Uint8List dibs});

/// Searches for gateways from the box, on all networks except its own Wi-Fi
/// ([skip], on the box 10.42.0.0/24). For the app in the box Wi-Fi, which
/// cannot get past the box firewall itself.
///
/// - Multicast SEARCH_REQUEST per network (also finds devices with a
///   link-local or entirely foreign address),
/// - Unicast DESCRIPTION_REQUEST to every target in the /24 (like the app), for
///   gateways that do not answer multicast.
Future<List<Discovered>> discoverGateways({
  Duration listen = const Duration(seconds: 2),
  bool Function(InternetAddress address) skip = isBoxWlan,
}) async {
  final found = <String, Discovered>{};
  final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
  final sockets = <RawDatagramSocket>[];
  try {
    for (final iface in interfaces) {
      for (final local in iface.addresses) {
        if (local.isLoopback || skip(local)) continue;
        final socket = await RawDatagramSocket.bind(local, 0);
        sockets.add(socket);
        socket.listen((e) {
          if (e != RawSocketEvent.read) return;
          final dg = socket.receive();
          if (dg == null) return;
          final service = serviceOf(dg.data);
          final Uint8List dibs;
          if (service == KnxIpService.descriptionResponse && dg.data.length > 6) {
            dibs = Uint8List.sublistView(dg.data, 6);
          } else if (service == 0x0202 && dg.data.length > 14) {
            dibs = Uint8List.sublistView(dg.data, 14); // SEARCH_RESPONSE: HPAI first
          } else {
            return;
          }
          found[dg.address.address] ??= (host: dg.address.address, port: dg.port, dibs: Uint8List.fromList(dibs));
        }, onError: (Object _) {});
        final hpai = [0x08, 0x01, ...local.rawAddress, socket.port >> 8, socket.port & 0xFF];
        _multicastFrom(socket, local);
        socket.send(knxFrame(KnxIpService.searchRequest, hpai), InternetAddress('224.0.23.12'), 3671);
        final [a, b, c, own] = local.rawAddress;
        if (a == 169 && b == 254) continue; // /16 is too large to scan
        for (var host = 1; host < 255; host++) {
          if (host == own) continue;
          socket.send(knxFrame(KnxIpService.descriptionRequest, hpai), InternetAddress('$a.$b.$c.$host'), 3671);
          if (host % 16 == 0) await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
    }
    await Future<void>.delayed(listen);
  } finally {
    for (final s in sockets) {
      s.close();
    }
  }
  return found.values.toList()..sort((x, y) => x.host.compareTo(y.host));
}

/// The box Wi-Fi (NetworkManager hotspot, `ipv4.method shared`).
bool isBoxWlan(InternetAddress address) {
  final [a, b, c, _] = address.rawAddress;
  return a == 10 && b == 42 && c == 0;
}

/// Sends multicast over exactly this interface (IP_MULTICAST_IF); otherwise
/// the kernel would use the default route – without DHCP possibly the Wi-Fi.
void _multicastFrom(RawDatagramSocket socket, InternetAddress local) {
  final option = Platform.isLinux ? 32 : (Platform.isMacOS ? 9 : null);
  if (option == null) return;
  try {
    socket.setRawOption(RawSocketOption(RawSocketOption.levelIPv4, option, Uint8List.fromList(local.rawAddress)));
  } on Object {
    // Not supported: default route.
  }
}
