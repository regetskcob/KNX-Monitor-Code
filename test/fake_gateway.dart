import 'dart:io';
import 'dart:typed_data';

/// Minimaler KNXnet/IP-Gateway für Tests (UDP auf localhost).
///
/// Nimmt eine Tunnelverbindung an, quittiert Tunneling-Requests, schickt
/// L_Data.con zurück und simuliert Geräte: Status-Antworten, Programmiermodus
/// und Gerätedeskriptor.
class FakeGateway {
  FakeGateway._(this._socket) {
    _socket.listen((e) {
      if (e != RawSocketEvent.read) return;
      final dg = _socket.receive();
      if (dg != null) _handle(dg);
    });
  }

  static Future<FakeGateway> start() async =>
      FakeGateway._(await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0));

  final RawDatagramSocket _socket;
  int get port => _socket.port;

  static const tunnelAddress = 0x1126; // 1.1.38

  /// Geräte am Bus: physikalische Adresse → Maskenversion.
  final devices = <int, int>{};

  /// Eigenschaften je Gerät: (Objektindex, PID) → Daten.
  final properties = <int, Map<(int, int), List<int>>>{};
  final _deviceSeq = <int, int>{};

  int _nextSeq(int device) {
    final seq = _deviceSeq[device] ?? 0;
    _deviceSeq[device] = (seq + 1) & 0x0F;
    return seq;
  }

  /// Wie Gira X1: bestätigt jede Einzeladresse positiv, auch ohne Gerät.
  bool confirmAll = false;

  /// Alle Tunnel belegt: CONNECT_REQUEST wird abgelehnt (wie der X1: 0x24).
  bool full = false;

  /// Trennt die Verbindung von Gateway-Seite (DISCONNECT_REQUEST an den Client).
  void kick() => _send(0x0209, [0x01, 0x00, 0x08, 0x01, 127, 0, 0, 1, port >> 8, port & 0xFF]);

  /// Geräte mit gedrückter Programmiertaste.
  final programmingMode = <int>{};

  /// Gruppenadresse → (Absender, Antwortdaten) für GroupValueResponse.
  final responders = <int, (int, List<int>)>{};

  /// CRIs der Verbindungsanfragen (zum Prüfen im Test).
  final connectCris = <List<int>>[];

  /// Nur Tunnelling v1: Extended CRI (feste Tunneladresse) wird abgelehnt.
  bool rejectExtended = false;

  /// Empfangene L_Data.req (zum Prüfen im Test).
  final requests = <Uint8List>[];

  /// DIBs der DESCRIPTION_RESPONSE: Geräteinfo, Dienste, Tunnelplätze.
  static final description = <int>[
    // Device Info (54 Byte): TP1, Programmiermodus aus, 1.1.250, Projekt 0,
    // Seriennummer, Multicast 224.0.23.12, MAC, Name
    0x36, 0x01, 0x02, 0x00, 0x11, 0xFA, 0x00, 0x00,
    0x00, 0x08, 0x12, 0x34, 0x56, 0x78,
    224, 0, 23, 12,
    0x00, 0x0A, 0xB3, 0x01, 0x02, 0x03,
    ...'Fake X1'.codeUnits, ...List.filled(30 - 7, 0),
    // Supported Service Families: Core v2, Device Mgmt v1, Tunnelling v2
    0x08, 0x02, 0x02, 0x02, 0x03, 0x01, 0x04, 0x02,
    // Tunnelling Info: max. APDU 254, Plätze 1.1.38 (belegt), 1.1.39 (frei)
    0x0C, 0x07, 0x00, 0xFE, 0x11, 0x26, 0x00, 0x04, 0x11, 0x27, 0x00, 0x05,
  ];

  InternetAddress? _client;
  int _clientPort = 0;
  int _seq = 0;

  void close() => _socket.close();

  void _send(int service, List<int> body) {
    final len = 6 + body.length;
    _socket.send([0x06, 0x10, service >> 8, service & 0xFF, len >> 8, len & 0xFF, ...body], _client!, _clientPort);
  }

  void _toClient(List<int> cemi) => _send(0x0420, [0x04, 0x01, _seq++ & 0xFF, 0x00, ...cemi]);

  void _handle(Datagram dg) {
    final p = dg.data;
    _client = dg.address;
    _clientPort = dg.port;
    final service = (p[2] << 8) | p[3];
    switch (service) {
      case 0x0205 when full: // CONNECT_REQUEST, keine Plätze frei
        connectCris.add(p.sublist(22));
        _send(0x0206, [0x00, 0x24]);
      case 0x0205 when rejectExtended && p[22] == 6:
        connectCris.add(p.sublist(22));
        _send(0x0206, [0x00, 0x23]);
      case 0x0205: // CONNECT_REQUEST
        connectCris.add(p.sublist(22));
        _send(0x0206, [0x01, 0x00, 0x08, 0x01, 127, 0, 0, 1, port >> 8, port & 0xFF, 0x04, 0x04, 0x11, 0x26]);
      case 0x0203: // DESCRIPTION_REQUEST
        _send(0x0204, description);
      case 0x0209: // DISCONNECT_REQUEST
        _send(0x020A, [0x01, 0x00]);
      case 0x0420: // TUNNELING_REQUEST
        _send(0x0421, [0x04, 0x01, p[8], 0x00]);
        _onCemi(Uint8List.sublistView(p, 10));
    }
  }

  void _onCemi(Uint8List c) {
    if (c[0] != 0x11) return; // nur L_Data.req
    requests.add(Uint8List.fromList(c));
    final group = c[3] & 0x80 != 0;
    final dst = (c[6] << 8) | c[7];
    final tpdu = c.sublist(9);
    final apci = tpdu.length >= 2 ? ((tpdu[0] & 0x03) << 8) | tpdu[1] : null;

    // Ohne Empfänger quittiert niemand (Einzeladresse unbekannt).
    final acked = group || confirmAll || devices.containsKey(dst);
    _toClient([0x2E, 0x00, c[2] | (acked ? 0 : 1), c[3], tunnelAddress >> 8, tunnelAddress & 0xFF, ...c.sublist(6)]);

    if (group && dst == 0 && apci == 0x100) {
      for (final pa in programmingMode) {
        _ind(pa, 0, group: true, tpdu: [0x01, 0x40]); // A_IndividualAddress_Response
      }
    } else if (group && apci == 0x000) {
      final r = responders[dst];
      if (r != null) _ind(r.$1, dst, group: true, tpdu: [0x00, 0x40, ...r.$2]);
    } else if (!group && devices.containsKey(dst) && tpdu[0] & 0xC0 == 0x40 && tpdu.length >= 2) {
      // T_Data_Connected: quittieren und beantworten.
      _ind(dst, tunnelAddress, group: false, tpdu: [0xC2 | (tpdu[0] & 0x3C)]); // T_ACK
      if (apci == 0x300) {
        final mask = devices[dst]!;
        _ind(dst, tunnelAddress, group: false, tpdu: [0x43 | (_nextSeq(dst) << 2), 0x40, mask >> 8, mask & 0xFF]);
      } else if (apci == 0x3D5) {
        final data = properties[dst]?[(tpdu[2], tpdu[3])];
        _ind(
          dst,
          tunnelAddress,
          group: false,
          tpdu: [
            0x43 | (_nextSeq(dst) << 2),
            0xD6,
            tpdu[2],
            tpdu[3],
            if (data == null) ...[0x00, 0x01] else ...[0x10, 0x01, ...data],
          ],
        );
      }
    }
  }

  void _ind(int src, int dst, {required bool group, required List<int> tpdu}) => _toClient([
    0x29,
    0x00,
    0xBC,
    (group ? 0x80 : 0x00) | 0x60,
    src >> 8,
    src & 0xFF,
    dst >> 8,
    dst & 0xFF,
    tpdu.length - 1,
    ...tpdu,
  ]);
}
