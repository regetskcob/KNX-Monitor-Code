import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'udp.dart';

class _IoUdp implements UdpEndpoint {
  _IoUdp(this._socket, {this.onClose}) {
    _socket.listen(
      (e) {
        if (e != RawSocketEvent.read) return;
        final dg = _socket.receive();
        if (dg != null) _datagrams.add((host: dg.address.address, data: dg.data));
      },
      onError: (Object e) => _datagrams.addError(UdpException('$e')),
      onDone: _datagrams.close,
    );
  }

  final RawDatagramSocket _socket;
  final void Function()? onClose;
  final _datagrams = StreamController<Datagram>.broadcast();

  @override
  Stream<Datagram> get datagrams => _datagrams.stream;

  @override
  int get port => _socket.port;

  @override
  void send(List<int> data, String host, int port) => _socket.send(data, InternetAddress(host), port);

  @override
  void close() {
    if (_closed) return; // onClose only once (counter for the MulticastLock)
    _closed = true;
    _socket.close();
    onClose?.call();
  }

  bool _closed = false;
}

/// Android drops multicast on Wi-Fi without a MulticastLock (MainActivity.kt). Counted, because
/// several multicast sockets can be open at the same time.
int _multicastUsers = 0;

Future<void> _multicastLock(bool acquire) async {
  if (!Platform.isAndroid) return;
  _multicastUsers += acquire ? 1 : -1;
  if (acquire ? _multicastUsers != 1 : _multicastUsers != 0) return;
  try {
    await const MethodChannel('knx/native').invokeMethod<void>('multicastLock', {'enabled': acquire});
  } on PlatformException {
    // Without the lock routing may only work partially – no reason to abort.
  }
}

Future<UdpEndpoint> openUdp() async {
  try {
    return _IoUdp(await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0));
  } on SocketException catch (e) {
    throw UdpException(e.osError?.message ?? e.message);
  }
}

Future<UdpEndpoint> openMulticast(String group, int port) async {
  try {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true, reusePort: true);
    socket
      ..multicastLoopback = false
      ..joinMulticast(InternetAddress(group));
    await _multicastLock(true);
    return _IoUdp(socket, onClose: () => _multicastLock(false));
  } on SocketException catch (e) {
    throw UdpException(e.osError?.message ?? e.message);
  } on UnsupportedError {
    // reusePort does not exist everywhere (e.g. Windows).
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true);
      socket
        ..multicastLoopback = false
        ..joinMulticast(InternetAddress(group));
      await _multicastLock(true);
      return _IoUdp(socket, onClose: () => _multicastLock(false));
    } on SocketException catch (e) {
      throw UdpException(e.osError?.message ?? e.message);
    }
  }
}

Future<List<int>> lookupIPv4(String host) async {
  try {
    return (await InternetAddress.lookup(host, type: InternetAddressType.IPv4)).first.rawAddress;
  } on SocketException catch (e) {
    throw UdpException(e.osError?.message ?? e.message);
  }
}

/// Best match by common prefix with the gateway; otherwise NAT mode.
Future<List<int>?> localAddressFor(List<int> gateway) async {
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    List<int>? best;
    var bestScore = 0;
    for (final a in interfaces.expand((i) => i.addresses)) {
      if (a.isLoopback) continue;
      final r = a.rawAddress;
      var score = 0;
      while (score < 4 && r[score] == gateway[score]) {
        score++;
      }
      if (score > bestScore) {
        best = r;
        bestScore = score;
      }
    }
    if (best != null && bestScore >= 2) return best;
  } catch (_) {
    // Interfaces not readable → NAT mode.
  }
  return null;
}

Future<List<String>> localNetworkAddresses() async => [
  for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4))
    for (final a in i.addresses)
      if (!a.isLoopback) a.address,
];

Future<List<int>?> localNetworkAddress() async {
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    // Prefer Wi-Fi/Ethernet (en0/en1), private networks.
    final candidates = [
      for (final i in interfaces)
        for (final a in i.addresses)
          if (!a.isLoopback && !a.isLinkLocal) (i.name, a),
    ]..sort((a, b) => (a.$1.startsWith('en') ? 0 : 1).compareTo(b.$1.startsWith('en') ? 0 : 1));
    return candidates.isEmpty ? null : candidates.first.$2.rawAddress;
  } on SocketException {
    return null;
  }
}
