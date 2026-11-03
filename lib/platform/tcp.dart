import 'dart:async';
import 'dart:typed_data';

import 'tcp_io.dart' if (dart.library.js_interop) 'tcp_web.dart' as impl;

/// TCP connection for KNXnet/IP (tunnel over TCP, IP Secure).
///
/// [packets] delivers complete KNXnet/IP frames (split at the header). Not available in the browser
/// – there the add-on holds the connection.
abstract class TcpStream {
  static Future<TcpStream> open(String host, int port) => impl.openTcp(host, port);

  /// Whether TCP works on this platform.
  static bool get supported => impl.tcpSupported;

  Stream<Uint8List> get packets;
  void send(List<int> data);
  void close();
}

/// Splits a byte stream into KNXnet/IP frames (length in the header).
class KnxFrameSplitter {
  final _buffer = BytesBuilder();

  /// Returns all complete frames; throws [FormatException] for an invalid header.
  List<Uint8List> add(List<int> chunk) {
    _buffer.add(chunk);
    var bytes = _buffer.takeBytes();
    final frames = <Uint8List>[];
    while (bytes.length >= 6) {
      final len = (bytes[4] << 8) | bytes[5];
      if (bytes[0] != 0x06 || bytes[1] != 0x10 || len < 6) throw const FormatException('Ungültiger KNXnet/IP-Strom');
      if (bytes.length < len) break;
      frames.add(Uint8List.fromList(bytes.sublist(0, len)));
      bytes = Uint8List.sublistView(bytes, len);
    }
    _buffer.add(bytes);
    return frames;
  }
}
