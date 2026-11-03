import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:knx/knx.dart';

import 'link.dart';

/// No tunnel of its own: reads the telegrams that Home Assistant's KNX
/// integration receives anyway (WebSocket `knx/subscribe_telegrams`), and
/// sends via its services `knx.send`/`knx.read`.
///
/// Device access (programming mode, checking an address, bus monitor) does not
/// work this way – in return the add-on does not occupy a tunnel slot.
class HaLink implements BusLink {
  HaLink({String? url, String? token, this.connector = WebSocket.connect})
    : url = url ?? 'ws://supervisor/core/websocket',
      token = token ?? Platform.environment['SUPERVISOR_TOKEN'];

  final String url;
  final String? token;
  final Future<WebSocket> Function(String url) connector;

  WebSocket? _ws;
  final _frames = StreamController<Uint8List>.broadcast();
  final _lost = Completer<String>();
  final _pending = <int, Completer<Map<String, Object?>>>{};
  int _nextId = 1;

  @override
  int? get address => null;

  @override
  String get label => 'Home Assistant KNX';

  @override
  Stream<Uint8List> get frames => _frames.stream;

  @override
  Future<String> get lost => _lost.future;

  @override
  Future<void> connect() async {
    if (token == null) throw const LinkException('Kein Zugriff auf Home Assistant (SUPERVISOR_TOKEN fehlt)');
    try {
      _ws = await connector(url).timeout(const Duration(seconds: 10));
    } on Object catch (e) {
      throw LinkException('Home Assistant nicht erreichbar: $e');
    }
    final authed = Completer<void>();
    _ws!.listen(
      (message) {
        if (message is! String) return;
        final Map<String, Object?> m;
        try {
          m = jsonDecode(message) as Map<String, Object?>;
        } on FormatException {
          return;
        }
        switch (m['type']) {
          case 'auth_required':
            _ws!.add(jsonEncode({'type': 'auth', 'access_token': token}));
          case 'auth_ok':
            if (!authed.isCompleted) authed.complete();
          case 'auth_invalid':
            if (!authed.isCompleted) authed.completeError(const LinkException('Home Assistant lehnt den Zugriff ab'));
          case 'event':
            final event = (m['event'] as Map?)?.cast<String, Object?>();
            final cemi = event == null ? null : cemiFromHa(event);
            if (cemi != null) _frames.add(cemi);
          case 'result':
            _pending.remove(m['id'])?.complete(m);
        }
      },
      onDone: () => _drop('Verbindung zu Home Assistant getrennt'),
      onError: (Object e) => _drop('Home Assistant: $e'),
    );
    await authed.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw const LinkException('Home Assistant antwortet nicht'),
    );
    final result = await _call({'type': 'knx/subscribe_telegrams'});
    if (result['success'] != true) {
      throw LinkException('KNX-Integration nicht verfügbar: ${(result['error'] as Map?)?['message'] ?? 'unbekannt'}');
    }
  }

  Future<Map<String, Object?>> _call(Map<String, Object?> message) {
    final id = _nextId++;
    final done = Completer<Map<String, Object?>>();
    _pending[id] = done;
    _ws!.add(jsonEncode({...message, 'id': id}));
    return done.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _pending.remove(id);
        throw const LinkException('Home Assistant antwortet nicht');
      },
    );
  }

  @override
  Future<void> send(Uint8List cemi) async {
    if (_ws == null) throw const LinkException('Nicht verbunden');
    final i = 2 + cemi[1];
    if (cemi.length < i + 9 || cemi[i + 1] & 0x80 == 0) {
      throw const LinkException('Im Home-Assistant-Modus nur Gruppentelegramme');
    }
    final destination = (cemi[i + 4] << 8) | cemi[i + 5];
    final npdu = cemi[i + 6];
    final apci = ((cemi[i + 7] & 0x03) << 8) | cemi[i + 8];
    final address = '${(destination >> 11) & 0x1F}/${(destination >> 8) & 0x07}/${destination & 0xFF}';
    final Map<String, Object?> call;
    switch (apci & 0x3C0) {
      case 0x000:
        call = {
          'domain': 'knx',
          'service': 'read',
          'service_data': {'address': address},
        };
      case 0x040 || 0x080:
        final Object payload = npdu <= 1 ? cemi[i + 8] & 0x3F : cemi.sublist(i + 9, i + 8 + npdu);
        call = {
          'domain': 'knx',
          'service': 'send',
          'service_data': {'address': address, 'payload': payload, if (apci & 0x3C0 == 0x040) 'response': true},
        };
      default:
        throw const LinkException('Im Home-Assistant-Modus nicht möglich');
    }
    final result = await _call({'type': 'call_service', ...call});
    if (result['success'] != true) {
      throw LinkException('${(result['error'] as Map?)?['message'] ?? 'Home Assistant lehnt ab'}');
    }
  }

  void _drop(String reason) {
    if (!_lost.isCompleted) _lost.complete(reason);
    for (final p in _pending.values) {
      if (!p.isCompleted) p.completeError(LinkException(reason));
    }
    _pending.clear();
  }

  @override
  Future<void> close() async {
    _drop('Getrennt');
    await _ws?.close();
    _ws = null;
    if (!_frames.isClosed) await _frames.close();
  }
}

/// Telegram from Home Assistant (TelegramDict of the KNX integration) as a
/// cEMI frame: incoming as L_Data.ind, sent by Home Assistant as L_Data.con.
/// `null` if it cannot be mapped.
Uint8List? cemiFromHa(Map<String, Object?> t) {
  final source = parseIndividual(t['source'] as String?) ?? 0;
  final destination = parseGroupText(t['destination'] as String?);
  if (destination == null) return null;
  final apci = switch (t['telegramtype']) {
    'GroupValueRead' => 0x00,
    'GroupValueResponse' => 0x40,
    'GroupValueWrite' => 0x80,
    _ => null,
  };
  if (apci == null) return null;
  final payload = t['payload'];
  final List<int> tpdu;
  if (payload is int) {
    tpdu = [0x00, apci | (payload & 0x3F)];
  } else if (payload is List) {
    tpdu = [0x00, apci, for (final b in payload) (b as int) & 0xFF];
  } else {
    tpdu = [0x00, apci];
  }
  final outgoing = t['direction'] == 'Outgoing';
  return Uint8List.fromList([
    outgoing ? 0x2E : 0x29,
    0x00,
    0xBC,
    0xE0,
    source >> 8,
    source & 0xFF,
    destination >> 8,
    destination & 0xFF,
    tpdu.length - 1,
    ...tpdu,
  ]);
}

/// "1/2/3", "1/234" or "2563" → raw value.
int? parseGroupText(String? s) {
  final parts = (s ?? '').split('/').map(int.tryParse).toList();
  return switch (parts) {
    [final m?, final mi?, final sub?] when m <= 31 && mi <= 7 && sub <= 255 => (m << 11) | (mi << 8) | sub,
    [final m?, final sub?] when m <= 31 && sub <= 2047 => (m << 11) | sub,
    [final free?] when free >= 0 && free <= 0xFFFF => free,
    _ => null,
  };
}
