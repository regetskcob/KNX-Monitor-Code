import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'addon.dart';
import 'box_link.dart';

const addonAvailable = true;

Uri _api(String path) => Uri.parse(web.document.baseURI).removeFragment().resolve(path);

class _WebAddonSocket implements AddonSocket {
  _WebAddonSocket(this._socket) {
    _socket.onmessage = ((web.MessageEvent e) {
      _messages.add((e.data as JSArrayBuffer).toDart.asUint8List());
    }).toJS;
    _socket.onclose = ((web.Event _) {
      if (!_messages.isClosed) {
        _messages.addError(const AddonException('Verbindung zum Add-on getrennt'));
        _messages.close();
      }
    }).toJS;
  }

  final web.WebSocket _socket;
  final _messages = StreamController<Uint8List>.broadcast();

  @override
  Stream<Uint8List> get messages => _messages.stream;

  @override
  void send(List<int> data) {
    if (_socket.readyState == web.WebSocket.OPEN) _socket.send(Uint8List.fromList(data).toJS);
  }

  @override
  void close() {
    _socket.onclose = null;
    _socket.close();
    if (!_messages.isClosed) _messages.close();
  }
}

Future<AddonSocket> openAddonBus() async {
  try {
    return await _openBus();
  } on AddonException catch (e) {
    // The page cannot see the HTTP status of the WebSocket handshake. On the box it may be a
    // missing login: the follow-up request makes the browser ask for the password, after which the
    // session cookie applies.
    final int status;
    // Generous: as long as the browser asks for the password, the request stays open.
    try {
      status = (await http.get(_api('api/box')).timeout(const Duration(seconds: 60))).statusCode;
    } on Object {
      throw e;
    }
    if (status == 401) {
      throw const AddonException('Anmeldung an der KNX-Box nötig. Seite neu laden und mit dem Box-Passwort anmelden.');
    }
    if (status == 403) throw const AddonException('Zugriff von der KNX-Box abgelehnt.');
    if (status != 200) rethrow;
    return _openBus();
  }
}

Future<AddonSocket> _openBus() async {
  final base = _api('ws/bus');
  final url = base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws').toString();
  final socket = web.WebSocket(url)..binaryType = 'arraybuffer';
  final opened = Completer<void>();
  socket.onopen = ((web.Event _) => opened.complete()).toJS;
  socket.onerror = ((web.Event _) {
    if (!opened.isCompleted) opened.completeError(const AddonException('Add-on-Server nicht erreichbar'));
  }).toJS;
  await opened.future.timeout(
    const Duration(seconds: 5),
    onTimeout: () => throw const AddonException('Add-on-Server nicht erreichbar'),
  );
  socket.onerror = null;
  return _WebAddonSocket(socket);
}

Future<Object?> _decode(http.Response r) {
  if (r.statusCode >= 300) throw Addon.errorOf(r.bodyBytes) ?? AddonException('Add-on: HTTP ${r.statusCode}');
  return Future.value(r.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes)));
}

Future<Map<String, Object?>> addonGet(String path) async =>
    (await _decode(await http.get(_api(path)))) as Map<String, Object?>;

Future<List<Object?>> addonGetList(String path) async => (await _decode(await http.get(_api(path)))) as List<Object?>;

// [timeout] only applies natively; the browser waits until the server responds.
Future<Map<String, Object?>> addonPut(String path, Map<String, Object?> body, {Duration? timeout}) async =>
    (await _decode(await http.put(_api(path), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))))
        as Map<String, Object?>;

Future<Object?> addonPost(String path, Map<String, Object?> body) async =>
    _decode(await http.post(_api(path), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body)));

Future<Object?> addonPatch(String path, Map<String, Object?> body) async =>
    _decode(await http.patch(_api(path), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body)));

Future<Object?> addonDelete(String path) async => _decode(await http.delete(_api(path)));

// In the browser the files already live on the server via AppStorage.
Future<Uint8List?> addonGetFile(String path, {String base = 'api/files/'}) async => null;

Future<void> addonPutFile(String path, List<int> bytes) async {}

/// In the browser, login is the browser's business.
/// In the browser the app only talks to the server that delivers it.
Future<bool> addonReachable(BoxLink link) async => true;

Future<String> addonPairBox(BoxLink link, String password, String deviceName) =>
    throw const AddonException('Nur in der App');
