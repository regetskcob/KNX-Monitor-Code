import 'dart:async';
import 'dart:typed_data';

import '../platform/udp.dart';
import 'telegram.dart';

/// A tunnel slot according to the DIB "Tunnelling Info" (KNXnet/IP v2).
class TunnelSlot {
  const TunnelSlot(this.address, {required this.free, required this.usable});
  final int address;
  final bool free;
  final bool usable;
}

/// Self-description of a KNXnet/IP device (DESCRIPTION_RESPONSE).
class GatewayInfo {
  const GatewayInfo({
    required this.name,
    required this.medium,
    required this.programmingMode,
    required this.address,
    required this.serial,
    required this.mac,
    required this.multicast,
    required this.projectInstallation,
    this.services = const {},
    this.slots = const [],
  });

  final String name;

  /// KNX medium: 0x02 TP1, 0x04 PL110, 0x10 RF, 0x20 KNX IP.
  final int medium;
  final bool programmingMode;

  /// The gateway's own individual address.
  final int address;
  final String serial;
  final String mac;
  final String multicast;
  final int projectInstallation;

  /// Service family (0x02 Core … 0x09 Security) → version.
  final Map<int, int> services;

  /// Tunnel slots, empty for KNXnet/IP v1.
  final List<TunnelSlot> slots;

  String get mediumText => switch (medium) {
    0x02 => 'TP1',
    0x04 => 'PL110',
    0x10 => 'RF',
    0x20 => 'KNX IP',
    _ => '0x${medium.toRadixString(16)}',
  };

  static String serviceName(int family) => switch (family) {
    0x02 => 'Core',
    0x03 => 'Device Management',
    0x04 => 'Tunnelling',
    0x05 => 'Routing',
    0x06 => 'Remote Logging',
    0x07 => 'Remote Configuration',
    0x08 => 'Object Server',
    0x09 => 'Security',
    _ => '0x${family.toRadixString(16)}',
  };

  /// Parses the body of a DESCRIPTION_RESPONSE (or SEARCH_RESPONSE without HPAI) – a sequence of
  /// DIBs. `null` if the device info is missing.
  static GatewayInfo? parse(Uint8List dibs) {
    GatewayInfo? info;
    final services = <int, int>{};
    final slots = <TunnelSlot>[];
    var i = 0;
    while (i + 2 <= dibs.length) {
      final len = dibs[i];
      final type = dibs[i + 1];
      if (len < 2 || i + len > dibs.length) break;
      final d = Uint8List.sublistView(dibs, i, i + len);
      switch (type) {
        case 0x01 when len >= 54:
          String hexBytes(int from, int count, String sep) =>
              [for (var k = from; k < from + count; k++) d[k].toRadixString(16).padLeft(2, '0').toUpperCase()]
                  .join(sep);
          info = GatewayInfo(
            medium: d[2],
            programmingMode: d[3] & 0x01 != 0,
            address: (d[4] << 8) | d[5],
            projectInstallation: (d[6] << 8) | d[7],
            serial: hexBytes(8, 6, ''),
            multicast: '${d[14]}.${d[15]}.${d[16]}.${d[17]}',
            mac: hexBytes(18, 6, ':'),
            name: String.fromCharCodes(d.sublist(24, 54).takeWhile((b) => b != 0)).trim(),
          );
        case 0x02:
          for (var k = 2; k + 1 < len; k += 2) {
            services[d[k]] = d[k + 1];
          }
        case 0x07: // Tunnelling Info: max. APDU (2), then per slot address (2) + status (2)
          for (var k = 4; k + 3 < len; k += 4) {
            final status = (d[k + 2] << 8) | d[k + 3];
            slots.add(TunnelSlot((d[k] << 8) | d[k + 1], free: status & 0x01 != 0, usable: status & 0x04 != 0));
          }
      }
      i += len;
    }
    if (info == null) return null;
    return GatewayInfo(
      name: info.name,
      medium: info.medium,
      programmingMode: info.programmingMode,
      address: info.address,
      serial: info.serial,
      mac: info.mac,
      multicast: info.multicast,
      projectInstallation: info.projectInstallation,
      services: services,
      slots: slots,
    );
  }

  String get addressText => formatIndividual(address);
}

/// Gateway found during discovery.
class FoundGateway {
  const FoundGateway(this.host, this.info);
  final String host;
  final GatewayInfo info;
}

/// Searches for KNXnet/IP devices in the local /24 network via unicast DESCRIPTION_REQUEST.
///
/// Replacement for the multicast search (SEARCH_REQUEST), which would need a separate entitlement
/// on iOS. Sends throttled to all 254 addresses.
Stream<FoundGateway> scanGateways({Duration listen = const Duration(seconds: 2)}) async* {
  final local = await localNetworkAddress();
  if (local == null) return;
  final socket = await UdpEndpoint.open();
  final found = StreamController<FoundGateway>();
  final seen = <String>{};
  final sub = socket.datagrams.listen((dg) {
    final p = dg.data;
    if (p.length < 8 || p[0] != 0x06 || p[1] != 0x10 || p[2] != 0x02 || p[3] != 0x04) return;
    final info = GatewayInfo.parse(Uint8List.sublistView(p, 6));
    if (info != null && seen.add(dg.host)) found.add(FoundGateway(dg.host, info));
  }, onError: (Object _) {});

  Future<void> send() async {
    // Without a known port (browser relay): NAT HPAI, response to the sender.
    final hpai = socket.port == 0
        ? [0x08, 0x01, 0, 0, 0, 0, 0, 0]
        : [0x08, 0x01, ...local, socket.port >> 8, socket.port & 0xFF];
    final packet = [0x06, 0x10, 0x02, 0x03, 0x00, 0x0E, ...hpai];
    for (var host = 1; host < 255; host++) {
      if (host == local[3]) continue;
      socket.send(packet, formatIPv4([local[0], local[1], local[2], host]), 3671);
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
    await Future<void>.delayed(listen);
    await sub.cancel();
    socket.close();
    await found.close();
  }

  unawaited(send());
  yield* found.stream;
}
