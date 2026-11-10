import 'dart:io' show FileSystemException;

import 'package:knx_io/knx_io.dart' show LinkException;

/// German texts for the English messages of `package:knx_io` (tunnel, routing,
/// FT1.2/KNX HAT), as the server shows them in status, log and app. Unknown
/// messages stay as they are.
String linkText(Object error) {
  final message = switch (error) {
    LinkException(:final message) => message,
    FileSystemException(:final message) => message,
    _ => '$error',
  };
  final exact = _exact[message];
  if (exact != null) return exact;
  for (final (pattern, german) in _patterns) {
    final m = pattern.firstMatch(message);
    if (m != null) return german(m);
  }
  return message;
}

const _exact = {
  'Disconnected': 'Getrennt',
  'Not connected': 'Nicht verbunden',
  'Invalid frame': 'Ungültiger Frame',
  'Gateway closed the TCP connection': 'TCP-Verbindung vom Gateway geschlossen',
  'Invalid KNXnet/IP stream': 'Ungültiger KNXnet/IP-Strom',
  'IP Secure: user or password rejected': 'IP Secure: Benutzer oder Passwort abgelehnt',
  'IP Secure: device authentication code does not match': 'IP Secure: Geräte-Authentifizierungscode passt nicht',
  'IP Secure: invalid key from the gateway': 'IP Secure: ungültiger Schlüssel vom Gateway',
  'IP Secure: gateway does not respond': 'IP Secure: Gateway antwortet nicht',
  'Gateway does not respond': 'Gateway antwortet nicht',
  'Gateway does not acknowledge': 'Gateway quittiert nicht',
  'Gateway ended the connection': 'Gateway hat die Verbindung beendet',
  'Gateway stopped responding': 'Gateway antwortet nicht mehr',
  'Gateway has no free tunnel': 'Gateway meldet: keine freien Tunnel',
  'Tunnel address is in use': 'Tunneladresse ist belegt',
  'Gateway does not support tunnelling': 'Gateway unterstützt keine Tunnelverbindung',
  'Gateway does not support the connection option': 'Gateway unterstützt die Verbindungsoption nicht',
  'Gateway does not support the link layer': 'Gateway unterstützt den Link Layer nicht',
  'No permission for the tunnel address': 'Keine Berechtigung für die Tunneladresse',
  'Address is not a tunnel address of the gateway': 'Adresse ist keine Tunneladresse des Gateways',
  'Telegram not acknowledged on the bus (NCON)': 'Telegramm auf dem Bus nicht quittiert (NCON)',
  'FT1.2 module does not respond (bus voltage, wiring, UART?)':
      'KNX-HAT antwortet nicht (Busspannung, Steckplatz, UART?)',
  'FT1.2 module: no answer to identify': 'KNX-HAT: keine Antwort auf Identify',
  'FT1.2 module has no bus monitor mode': 'KNX-HAT kann keinen Busmonitor',
  'FT1.2 module has no link layer mode': 'KNX-HAT kann keinen Link Layer',
  'FT1.2 module rejects the mode switch (PID 52)': 'KNX-HAT lehnt das Umschalten ab (PID 52)',
  'FT1.2 module restarted': 'KNX-HAT neu gestartet',
  'FT1.2 module stopped responding': 'KNX-HAT antwortet nicht mehr',
  'FT1.2 module left the operating mode': 'KNX-HAT hat die Betriebsart verlassen',
  'FT1.2 bus monitor mode cannot send': 'KNX-HAT im Busmonitor: Senden nicht möglich',
  'FT1.2 module does not acknowledge': 'KNX-HAT quittiert nicht',
  'FT1.2 module does not confirm the telegram': 'KNX-HAT bestätigt das Telegramm nicht',
  'M_PropWrite PID 52 = 0x00 rejected': 'M_PropWrite PID 52 = 0x00 abgelehnt',
  'M_PropWrite PID 52 = 0x01 rejected': 'M_PropWrite PID 52 = 0x01 abgelehnt',
  'Device missing (on a Raspberry Pi: UART overlay in config.txt, then reboot)':
      'Gerät fehlt (UART-Overlay in config.txt, danach neu starten)',
};

final _patterns = <(RegExp, String Function(RegExpMatch))>[
  (RegExp(r'^Gateway unreachable: (.*)$'), (m) => 'Gateway nicht erreichbar: ${m[1]}'),
  (RegExp(r'^Gateway rejects the telegram \((.*)\)$'), (m) => 'Gateway lehnt Telegramm ab (${m[1]})'),
  (RegExp(r'^Gateway rejects the connection \((.*)\)$'), (m) => 'Gateway lehnt die Verbindung ab (${m[1]})'),
  (RegExp(r'^Host (.*) not found$'), (m) => 'Host ${m[1]} nicht gefunden'),
  (RegExp(r'^Routing not possible: (.*)$'), (m) => 'Routing nicht möglich: ${m[1]}'),
  (RegExp(r'^FT1\.2: cannot open (\S+) \((.*)\)$'), (m) => 'KNX-HAT: ${m[1]} lässt sich nicht öffnen (${m[2]})'),
  (RegExp(r'^FT1\.2: read error \((.*)\)$'), (m) => 'KNX-HAT: Lesefehler (${m[1]})'),
  (RegExp(r'^FT1\.2 module does not take the address (.*)$'), (m) => 'KNX-HAT übernimmt die Adresse ${m[1]} nicht'),
];

/// German form of [BusLink.label] for status and log, e.g. "UDP-Tunnel 1.1.38"
/// or "KNX-HAT Busmonitor 15.15.255".
String linkLabel(String label) {
  for (final (english, german) in _labels) {
    if (label.startsWith(english)) return german + label.substring(english.length);
  }
  return label;
}

const _labels = [
  ('FT1.2 bus monitor', 'KNX-HAT Busmonitor'),
  ('FT1.2 link layer', 'KNX-HAT Link Layer'),
  ('IP Secure tunnel', 'IP-Secure-Tunnel'),
  ('UDP tunnel', 'UDP-Tunnel'),
  ('TCP tunnel', 'TCP-Tunnel'),
];

/// [KberryProbe] report (or any JSON value) with every `error` text in
/// German ([linkText]), for the HAT check in the app and the `hat` command.
Object? linkReport(Object? value) => switch (value) {
  Map() => <String, Object?>{
    for (final MapEntry(:key, :value) in value.entries)
      '$key': key == 'error' && value is String ? linkText(value) : linkReport(value),
  },
  List() => [for (final v in value) linkReport(v)],
  _ => value,
};
