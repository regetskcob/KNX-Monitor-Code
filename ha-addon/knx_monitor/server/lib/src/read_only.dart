/// Read-only: the server sends nothing to the bus.
///
/// Two paths lead to the bus, and both pass through here:
/// - the server's own bus connection ([BusLink.send]): [ReadOnlyLink] rejects
///   every telegram, including read requests,
/// - the UDP relay `/ws`, through which a view opens its own tunnel to the
///   gateway: [relayMaySendReadOnly] only lets management through (search,
///   description, connect, connection state, disconnect, acknowledgements).
///
/// Enabled in the add-on with the option `read_only` (on by default),
/// otherwise with `READ_ONLY=1`.
library;

import 'dart:typed_data';

import 'ha_link.dart';
import 'link.dart';

/// Text for log and view when a telegram is rejected.
const readOnlyMessage = 'Nur-Lesen ist an: Der Server sendet nichts auf den Bus.';

/// Wraps a bus connection and rejects every send. Receiving, connecting and
/// disconnecting are passed through unchanged.
class ReadOnlyLink implements BusLink {
  ReadOnlyLink(this._inner);

  final BusLink _inner;

  /// Home Assistant's telegram store if the wrapped connection has one; it
  /// only reads, so it is passed on (filling the history, ha_history.dart).
  TelegramStore? get telegramStore => switch (_inner) {
    HaLink(:final store) => store,
    _ => null,
  };

  @override
  Stream<Uint8List> get frames => _inner.frames;

  @override
  int? get address => _inner.address;

  @override
  String get label => _inner.label;

  @override
  Future<void> connect() => _inner.connect();

  @override
  Future<void> send(Uint8List cemi) async => throw const LinkException(readOnlyMessage);

  @override
  Future<String> get lost => _inner.lost;

  @override
  Future<void> close() => _inner.close();
}

/// KNXnet/IP services that may pass the relay in read-only mode. None of them
/// carries a telegram for the bus: without TUNNELLING_REQUEST (0x0420) a tunnel
/// sends nothing, without ROUTING_INDICATION (0x0530) routing sends nothing.
/// Also blocked are DEVICE_CONFIGURATION_REQUEST (0x0310, interface
/// properties), TUNNELLING_FEATURE_SET (0x0424) and SECURE_WRAPPER (0x0950),
/// whose content cannot be inspected. An IP Secure tunnel through the relay
/// therefore does not work in read-only mode; the server's continuous
/// recording is not affected.
const _readOnlyRelayServices = {
  0x0201, // SEARCH_REQUEST
  0x0203, // DESCRIPTION_REQUEST
  0x0205, // CONNECT_REQUEST
  0x0207, // CONNECTIONSTATE_REQUEST
  0x0209, // DISCONNECT_REQUEST
  0x020A, // DISCONNECT_RESPONSE
  0x020B, // SEARCH_REQUEST_EXTENDED
  0x0311, // DEVICE_CONFIGURATION_ACK
  0x0421, // TUNNELLING_ACK
  0x0422, // TUNNELLING_FEATURE_GET
};

/// Whether this KNXnet/IP packet may go to the gateway in read-only mode.
/// [packet] starts with the header (06 10, service, length).
bool relayMaySendReadOnly(List<int> packet) {
  if (packet.length < 6 || packet[0] != 0x06 || packet[1] != 0x10) return false;
  return _readOnlyRelayServices.contains((packet[2] << 8) | packet[3]);
}
