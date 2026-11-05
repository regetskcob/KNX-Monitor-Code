import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../l10n/locale_controller.dart';
import 'addon.dart';
import 'box_link.dart';

/// Native: connection to the paired KNX box ([Addon.box]) over the LAN/Wi-Fi.
const addonAvailable = false;

const _timeout = Duration(seconds: 5);

BoxLink get _box => Addon.box ?? (throw AddonException(s.boxNone));

Map<String, String> _headers(BoxLink box) => {if (box.key.isNotEmpty) 'Authorization': 'Bearer ${box.key}'};

/// Client that accepts only the certificate with fingerprint [fp].
///
/// Without root certificates, so that every certificate passes through the check here: otherwise
/// Dart only consults `badCertificateCallback` for certificates it does not already consider valid
/// itself, and one from a public authority would bypass the fingerprint. Validity period and name
/// do not count: the box often has no clock, and the fingerprint says more than both.
///
/// Which certificate the platform hands to that callback is not documented: on some it may be
/// another one of the chain the server sent. So each connection is opened here ([pinnedConnection])
/// and only handed on once the peer certificate – the leaf whose key the server proved in the
/// handshake – matches.
HttpClient pinnedHttpClient(String fp) {
  final context = SecurityContext(withTrustedRoots: false);
  bool matches(X509Certificate cert) => certificateFingerprint(cert.der) == fp;
  return HttpClient(context: context)
    ..badCertificateCallback = ((cert, host, port) => matches(cert))
    // The box is in the local network; a proxy from the environment would only stand in between.
    ..findProxy = ((_) => 'DIRECT')
    ..connectionFactory = ((uri, proxyHost, proxyPort) => pinnedConnection(uri, context, matches));
}

/// Opens the TLS connection for [pinnedHttpClient] and checks the leaf certificate with [matches]
/// before anything is sent over it. The handshake itself accepts any chain: whatever the platform
/// would pass to `onBadCertificate`, only the leaf decides, the same way on every platform. Plain
/// HTTP stays as it is.
Future<ConnectionTask<Socket>> pinnedConnection(
  Uri uri,
  SecurityContext context,
  bool Function(X509Certificate cert) matches,
) async {
  if (uri.scheme != 'https' && uri.scheme != 'wss') return Socket.startConnect(uri.host, uri.port);
  final task = await SecureSocket.startConnect(uri.host, uri.port, context: context, onBadCertificate: (_) => true);
  return ConnectionTask.fromSocket(
    task.socket.then((socket) {
      final leaf = socket.peerCertificate;
      if (leaf == null || !matches(leaf)) {
        socket.destroy();
        throw const HandshakeException('Box: certificate does not match the fingerprint');
      }
      return socket;
    }),
    task.cancel,
  );
}

/// SHA-256 of [der], base64url without padding (like the server and `tls-cert.sh`).
String certificateFingerprint(List<int> der) => base64Url.encode(sha256.convert(der).bytes).replaceAll('=', '');

final _clients = <String, http.Client>{};

http.Client _http(BoxLink box) =>
    _clients[box.fp] ??= box.fp.isEmpty ? http.Client() : IOClient(pinnedHttpClient(box.fp));

/// Whether the box responds. 401 and 428 count too: it is there, it just wants credentials.
Future<bool> addonReachable(BoxLink link) async {
  try {
    final r = await _http(link).get(link.url.resolve('api/box')).timeout(const Duration(seconds: 3));
    return r.statusCode == HttpStatus.ok || r.statusCode == HttpStatus.unauthorized;
  } on Object {
    return false;
  }
}

/// Reason for a rejection: lacking admin rights is different from lacking access.
AddonException _refused(http.Response r) {
  final text = utf8.decode(r.bodyBytes, allowMalformed: true);
  if (r.statusCode == HttpStatus.forbidden && text.startsWith('Nur mit dem Box-Passwort')) {
    return AddonException(s.boxNotAdmin);
  }
  // Password change or "lock out all" with a wrong current password.
  if (r.statusCode == HttpStatus.forbidden && text.startsWith('Das aktuelle Passwort')) {
    return AddonException(s.boxPasswordCurrentWrong, status: HttpStatus.forbidden);
  }
  if (r.statusCode == HttpStatus.preconditionRequired) return AddonException(s.boxPasswordRequired);
  return AddonException(s.boxUnauthorized);
}

bool _isRefusal(int status) =>
    status == HttpStatus.unauthorized || status == HttpStatus.forbidden || status == HttpStatus.preconditionRequired;

class _IoAddonSocket implements AddonSocket {
  _IoAddonSocket(this._socket) {
    _socket.listen(
      (m) {
        // A packet may still arrive after close().
        if (m is List<int> && !_messages.isClosed) _messages.add(m is Uint8List ? m : Uint8List.fromList(m));
      },
      onDone: _lost,
      onError: (Object _) => _lost(),
      cancelOnError: true,
    );
  }

  final WebSocket _socket;
  final _messages = StreamController<Uint8List>.broadcast();

  void _lost() {
    if (_messages.isClosed) return;
    _messages.addError(AddonException(Addon.box != null ? s.boxConnectionLost : s.addonConnectionLost));
    _messages.close();
  }

  @override
  Stream<Uint8List> get messages => _messages.stream;

  @override
  void send(List<int> data) {
    if (_socket.readyState == WebSocket.open) _socket.add(data);
  }

  @override
  void close() {
    if (!_messages.isClosed) _messages.close();
    _socket.close();
  }
}

Future<AddonSocket> openAddonBus() async {
  final box = _box;
  final base = box.url.resolve('ws/bus');
  final url = base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws');
  try {
    final socket = await WebSocket.connect(
      '$url',
      headers: _headers(box),
      customClient: box.fp.isEmpty ? null : pinnedHttpClient(box.fp),
    ).timeout(_timeout);
    // Keeps NAT/Wi-Fi paths open and notices drops while the iPad sleeps.
    socket.pingInterval = const Duration(seconds: 20);
    return _IoAddonSocket(socket);
  } on WebSocketException catch (e) {
    // dart:io reports the rejected upgrade only as text with a status code.
    if (RegExp(r'\b428\b').hasMatch(e.message)) throw AddonException(s.boxPasswordRequired);
    if (RegExp(r'\b40[13]\b').hasMatch(e.message)) throw AddonException(s.boxUnauthorized);
    throw AddonException(s.boxUnreachable(box.address));
  } on Object {
    throw AddonException(s.boxUnreachable(box.address));
  }
}

Future<Object?> _request(
  Future<http.Response> Function(BoxLink box, Uri url) send,
  String path, {
  Duration timeout = _timeout,
}) async {
  final box = _box;
  final http.Response r;
  try {
    r = await send(box, box.url.resolve(path)).timeout(timeout);
  } on Object {
    throw AddonException(s.boxUnreachable(box.address));
  }
  if (_isRefusal(r.statusCode)) throw _refused(r);
  if (r.statusCode >= 300) {
    throw Addon.errorOf(r.bodyBytes) ??
        // Plain text from the server (box settings: e.g. „Passwort vom Aufkleber“, password from
        // the sticker).
        (r.statusCode == HttpStatus.badRequest && r.bodyBytes.isNotEmpty
            ? AddonException(utf8.decode(r.bodyBytes, allowMalformed: true))
            : AddonException('Box: HTTP ${r.statusCode}', status: r.statusCode));
  }
  // 204 (e.g. after DELETE) has no content.
  return r.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
}

Future<Map<String, Object?>> addonGet(String path) async =>
    (await _request((box, url) => _http(box).get(url, headers: _headers(box)), path)) as Map<String, Object?>;

Future<List<Object?>> addonGetList(String path) async =>
    (await _request((box, url) => _http(box).get(url, headers: _headers(box)), path)) as List<Object?>;

Future<Map<String, Object?>> addonPut(String path, Map<String, Object?> body, {Duration? timeout}) async =>
    (await _request(
      (box, url) =>
          _http(box).put(url, headers: {..._headers(box), 'Content-Type': 'application/json'}, body: jsonEncode(body)),
      path,
      timeout: timeout ?? _timeout,
    )) as Map<String, Object?>;

Future<Object?> addonPatch(String path, Map<String, Object?> body) => _request(
  (box, url) =>
      _http(box).patch(url, headers: {..._headers(box), 'Content-Type': 'application/json'}, body: jsonEncode(body)),
  path,
);

Future<Object?> addonDelete(String path) =>
    _request((box, url) => _http(box).delete(url, headers: _headers(box)), path);

Future<Object?> addonPost(String path, Map<String, Object?> body) => _request(
  (box, url) =>
      _http(box).post(url, headers: {..._headers(box), 'Content-Type': 'application/json'}, body: jsonEncode(body)),
  path,
);

/// File from the box's data folder (`api/files/…`), `null` if it does not exist.
Future<Uint8List?> addonGetFile(String path, {String base = 'api/files/'}) async {
  final box = _box;
  final http.Response r;
  try {
    r = await _http(box)
        .get(box.url.resolve('$base$path'), headers: _headers(box))
        .timeout(const Duration(seconds: 30));
  } on Object {
    throw AddonException(s.boxUnreachable(box.address));
  }
  if (r.statusCode == HttpStatus.notFound) return null;
  if (_isRefusal(r.statusCode)) throw _refused(r);
  if (r.statusCode >= 300) throw AddonException('Box: HTTP ${r.statusCode}');
  return r.bodyBytes;
}

/// Download from the box (e.g. `api/export/ets-xml`) as bytes; the caller saves
/// them. Generous timeout: the server reads up to a month of history ([timeout]
/// longer for the whole history).
Future<Uint8List?> addonDownload(String path, String fileName, {Duration timeout = const Duration(minutes: 5)}) async {
  final box = _box;
  final http.Response r;
  try {
    r = await _http(box).get(box.url.resolve(path), headers: _headers(box)).timeout(timeout);
  } on Object {
    throw AddonException(s.boxUnreachable(box.address));
  }
  if (_isRefusal(r.statusCode)) throw _refused(r);
  if (r.statusCode >= 300) {
    final text = utf8.decode(r.bodyBytes, allowMalformed: true).trim();
    throw AddonException(text.isEmpty || text.length > 200 ? 'Box: HTTP ${r.statusCode}' : text, status: r.statusCode);
  }
  return r.bodyBytes;
}

/// Stores a file in the box's data folder (replacing it).
Future<void> addonPutFile(String path, List<int> bytes) async {
  final box = _box;
  final http.Response r;
  try {
    r = await _http(box)
        .put(box.url.resolve('api/files/$path'), headers: _headers(box), body: bytes)
        .timeout(const Duration(seconds: 60));
  } on Object {
    throw AddonException(s.boxUnreachable(box.address));
  }
  if (_isRefusal(r.statusCode)) throw _refused(r);
  if (r.statusCode >= 300) throw AddonException('Box: HTTP ${r.statusCode}');
}

/// Pairs using the box password from the sticker's QR code and returns the device access (with
/// admin rights). Runs before [Addon.box].
Future<String> addonPairBox(BoxLink link, String password, String deviceName) async {
  final http.Response r;
  try {
    r = await _http(link)
        .post(
          link.url.resolve('api/box/pair'),
          headers: {
            'Authorization': 'Basic ${base64.encode(utf8.encode('app:$password'))}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'name': deviceName}),
        )
        // The box checks the password; on the Pi this takes many seconds.
        .timeout(const Duration(seconds: 60));
  } on Object catch (e) {
    debugPrint('Box koppeln: $e');
    throw AddonException(s.boxUnreachable(link.address));
  }
  if (r.statusCode == HttpStatus.unauthorized || r.statusCode == HttpStatus.forbidden) {
    throw AddonException(s.boxUnauthorized);
  }
  if (r.statusCode == HttpStatus.tooManyRequests) throw AddonException(s.boxUnauthorized);
  if (r.statusCode >= 300) throw AddonException('Box: HTTP ${r.statusCode}');
  final key = (jsonDecode(utf8.decode(r.bodyBytes)) as Map)['key'];
  if (key is! String || key.isEmpty) throw AddonException(s.boxUnauthorized);
  return key;
}
