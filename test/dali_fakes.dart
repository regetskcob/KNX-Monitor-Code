import 'dart:typed_data';

import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';

int ga(String s) => parseGroup(s)!;
int pa(String s) => parseIndividual(s)!;

List<int> hexBytes(String hex) => [
  for (var i = 0; i + 1 < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
];

final gatewayPa = pa('1.1.40');
final diag = ga('1/4/20');

/// Telegram from the gateway: [hex] bytes, or a 1-bit value with [bit].
Telegram tg(int dest, String hex, {DateTime? at, int? source, int? bit, TelegramType type = TelegramType.write}) =>
    Telegram(
      time: at ?? DateTime(2026, 11, 10, 12, 4, 11),
      source: source ?? gatewayPa,
      destination: dest,
      type: type,
      data: Uint8List.fromList(bit != null ? [bit] : hexBytes(hex)),
      isSmall: bit != null,
    );

/// A project with one DALI gateway: diagnostics (DPT 237.600), four groups with switch and
/// status, per-gear fault objects for ECG 0 and 1, and an emergency converter 16.
GroupCatalog daliCatalog({String product = 'DG 64', String manufacturer = 'Demo'}) {
  final groups = <int, GroupInfo>{};
  void add(String address, String name, Dpt dpt, String text, {bool sends = false, int? object, int? device}) {
    final a = ga(address);
    groups[a] = GroupInfo(
      address: a,
      name: name,
      dpt: dpt,
      links: [GroupLink(device: device ?? gatewayPa, text: text, sends: sends, object: object)],
    );
  }

  add('1/4/20', 'DALI-Diagnose Flur/Büro', const Dpt(237, 600), 'Diagnose', sends: true);
  for (var g = 0; g < 4; g++) {
    add('1/5/$g', 'Gruppe $g Schalten', const Dpt(1, 1), 'Gruppe $g Schalten');
    add('1/6/$g', 'Gruppe $g Status', const Dpt(1, 1), 'Gruppe $g Status', sends: true);
  }
  add('1/7/0', 'EVG 0 Lampenfehler', const Dpt(1, 5), 'EVG 0 Lampenfehler', sends: true);
  add('1/7/1', 'EVG 1 Fehler', const Dpt(1, 5), 'EVG 1 Fehler', sends: true);
  add('5/1/16', 'Notleuchte 16 Status', const Dpt(244, 600), 'Notleuchte 16 Status', sends: true);
  add('5/2/16', 'Notleuchte 16 Testergebnis', const Dpt(245, 600), 'Notleuchte 16 Testergebnis', sends: true);
  // An ordinary actuator whose texts also say "Gruppe": no gateway, no DALI group.
  add('2/0/1', 'Gruppe 1 Schalten', const Dpt(1, 1), 'Gruppe 1 Schalten', device: pa('1.1.10'));
  return GroupCatalog(
    groups,
    devices: {
      gatewayPa: DeviceInfo(
        address: gatewayPa,
        name: 'DALI-Gateway',
        product: product,
        manufacturer: manufacturer,
        location: 'EG › Flur/Büro',
      ),
      pa('1.1.10'): DeviceInfo(address: pa('1.1.10'), name: 'Schaltaktor', product: 'SA 8', manufacturer: 'Demo'),
    },
    projectName: 'Testhaus',
  );
}

/// A tunnel that sends nothing: writes and reads are recorded, [answer] decides what comes back.
class FakeTunnel extends KnxTunnel {
  FakeTunnel() : super('fake') {
    state.value = TunnelState.connected;
    tunnelAddress = pa('1.1.255');
  }

  final writes = <(int, int?)>[];
  final reads = <int>[];

  /// Called for every write and read; returns the telegrams the bus answers with.
  List<Telegram> Function(int destination, {int? small, required bool read})? answer;

  @override
  Future<void> connect({Duration timeout = const Duration(seconds: 5)}) async {}

  @override
  Future<void> disconnect() async => state.value = TunnelState.disconnected;

  @override
  Future<bool?> write(int destination, {int? small, List<int> data = const []}) async {
    writes.add((destination, small));
    for (final t in answer?.call(destination, small: small, read: false) ?? const <Telegram>[]) {
      inject(t);
    }
    return true;
  }

  @override
  Future<bool?> read(int destination) async {
    reads.add(destination);
    for (final t in answer?.call(destination, read: true) ?? const <Telegram>[]) {
      inject(t);
    }
    return true;
  }
}
