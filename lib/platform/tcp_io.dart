import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'tcp.dart';
import 'udp.dart';

const tcpSupported = true;

class _IoTcp implements TcpStream {
  _IoTcp(this._socket) {
    _socket.listen(
      (chunk) {
        try {
          for (final f in _splitter.add(chunk)) {
            _packets.add(f);
          }
        } on FormatException catch (e) {
          _packets.addError(UdpException(e.message));
          _socket.destroy();
        }
      },
      onError: (Object e) => _packets.addError(UdpException('$e')),
      onDone: () {
        if (!_packets.isClosed) {
          _packets.addError(const UdpException('TCP-Verbindung geschlossen'));
          _packets.close();
        }
      },
    );
  }

  final Socket _socket;
  final _splitter = KnxFrameSplitter();
  final _packets = StreamController<Uint8List>.broadcast();

  @override
  Stream<Uint8List> get packets => _packets.stream;

  @override
  void send(List<int> data) => _socket.add(data);

  @override
  void close() {
    _socket.destroy();
    if (!_packets.isClosed) _packets.close();
  }
}

Future<TcpStream> openTcp(String host, int port) async {
  try {
    final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
    socket.setOption(SocketOption.tcpNoDelay, true);
    return _IoTcp(socket);
  } on SocketException catch (e) {
    throw UdpException(e.osError?.message ?? e.message);
  }
}
