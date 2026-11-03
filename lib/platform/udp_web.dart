import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'udp.dart';

/// UDP via the add-on server's relay (WebSocket "ws" next to the page).
///
/// Messages in both directions: 4 bytes IPv4, 2 bytes port, payload.
class _RelayUdp implements UdpEndpoint {
  _RelayUdp(this._socket) {
    _socket.onmessage = ((web.MessageEvent e) {
      final bytes = (e.data as JSArrayBuffer).toDart.asUint8List();
      if (bytes.length < 6) return;
      _datagrams.add((host: formatIPv4(bytes.sublist(0, 4)), data: Uint8List.sublistView(bytes, 6)));
    }).toJS;
    _socket.onclose = ((web.Event _) {
      if (!_datagrams.isClosed) {
        _datagrams.addError(const UdpException('Verbindung zum Add-on getrennt'));
        _datagrams.close();
      }
    }).toJS;
  }

  final web.WebSocket _socket;
  final _datagrams = StreamController<Datagram>.broadcast();

  @override
  Stream<Datagram> get datagrams => _datagrams.stream;

  @override
  int get port => 0;

  @override
  void send(List<int> data, String host, int port) {
    final ip = parseIPv4(host);
    if (ip == null || _socket.readyState != web.WebSocket.OPEN) return;
    _socket.send(Uint8List.fromList([...ip, port >> 8, port & 0xFF, ...data]).toJS);
  }

  @override
  void close() {
    _socket.onclose = null;
    _socket.close();
    _datagrams.close();
  }
}

Uri _api(String path) => Uri.parse(web.document.baseURI).removeFragment().resolve(path);

Future<UdpEndpoint> openUdp() async {
  final base = _api('ws');
  final url = base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws').toString();
  final socket = web.WebSocket(url)..binaryType = 'arraybuffer';
  final opened = Completer<void>();
  socket.onopen = ((web.Event _) => opened.complete()).toJS;
  socket.onerror = ((web.Event _) {
    if (!opened.isCompleted) opened.completeError(const UdpException('Add-on-Server nicht erreichbar'));
  }).toJS;
  await opened.future.timeout(
    const Duration(seconds: 5),
    onTimeout: () => throw const UdpException('Add-on-Server nicht erreichbar'),
  );
  socket.onerror = null;
  return _RelayUdp(socket);
}

Future<UdpEndpoint> openMulticast(String group, int port) async =>
    throw const UdpException('Routing ist im Browser nicht möglich – das Add-on hält die Verbindung.');

Future<List<int>> lookupIPv4(String host) async {
  final r = await http.get(_api('api/resolve').replace(queryParameters: {'host': host}));
  final ip = r.statusCode == 200 ? parseIPv4(r.body) : null;
  if (ip == null) throw UdpException('Host $host nicht gefunden');
  return ip;
}

/// In the browser the gateway responds to the add-on server (NAT mode).
Future<List<int>?> localAddressFor(List<int> gateway) async => null;

Future<List<String>> localNetworkAddresses() async => throw UnsupportedError('Im Browser nicht verfügbar');

Future<List<int>?> localNetworkAddress() async {
  try {
    final r = await http.get(_api('api/network'));
    if (r.statusCode != 200) return null;
    return parseIPv4((jsonDecode(r.body) as Map<String, Object?>)['ip'] as String? ?? '');
  } on Object {
    return null;
  }
}
