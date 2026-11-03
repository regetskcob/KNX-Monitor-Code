import 'tcp.dart';
import 'udp.dart';

const tcpSupported = false;

Future<TcpStream> openTcp(String host, int port) async =>
    throw const UdpException('TCP ist im Browser nicht möglich – das Add-on hält die Verbindung.');
