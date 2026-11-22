import '../l10n/locale_controller.dart';
import 'tcp.dart';
import 'udp.dart';

const tcpSupported = false;

Future<TcpStream> openTcp(String host, int port) async => throw UdpException(s.webNoTcp);
