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

/// Native: connection to the paired Busclear Box ([Addon.box]) over the LAN/Wi-Fi.
const addonAvailable = false;

const _timeout = Duration(seconds: 5);

/// The paired box, checked: a box whose device access would cross the internet in plain HTTP gets
/// no request at all ([addonRefusal]). Every request with the device access starts here, so the
/// refusal comes before a connection is opened.
BoxLink get _box {
  final box = Addon.box ?? (throw AddonException(s.boxNone));
  if (box.key.isNotEmpty) _requireProtected(box);
  return box;
}

/// [AddonException.problem] of a request the app refused to send, see [addonRefusal].
const plainRefusedProblem = 'plainRefused';

/// Why the app sends nothing secret to [link]: device access, box password and pairing code never
/// go over unencrypted HTTP to a host that is not in the local network ([BoxLink.plainOverInternet];
/// with a certificate fingerprint the link is HTTPS). `null` if it may: HTTPS, or plain HTTP
/// to a local address (a box without a certificate in the home network, the box's own Wi-Fi).
String? addonRefusal(BoxLink link) => link.plainOverInternet ? s.boxPlainRefused(link.address) : null;

void _requireProtected(BoxLink link) {
  if (addonRefusal(link) case final reason?) throw AddonException(reason, problem: plainRefusedProblem);
}

/// The device access as a header. Checked here once more: no `Authorization` header is built for
/// a link [addonRefusal] refuses, wherever the call comes from.
Map<String, String> _headers(BoxLink box) {
  if (box.key.isEmpty) return const {};
  _requireProtected(box);
  return {'Authorization': 'Bearer ${box.key}'};
}

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
    // Closed by the returned AddonSocket.
    // ignore: close_sinks
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
  if (r.statusCode == HttpStatus.tooManyRequests && Addon.errorOf(r.bodyBytes) == null) {
    throw AddonException(s.boxTooManyAttempts, status: r.statusCode);
  }
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

Future<Object?> addonPost(String path, Map<String, Object?> body, {Duration? timeout}) => _request(
  (box, url) =>
      _http(box).post(url, headers: {..._headers(box), 'Content-Type': 'application/json'}, body: jsonEncode(body)),
  path,
  timeout: timeout ?? _timeout,
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

/// Error of a streamed request, like [_request] does for buffered ones.
AddonException _failure(int status, List<int> body) {
  final r = http.Response.bytes(body, status);
  if (_isRefusal(status)) return _refused(r);
  final error = Addon.errorOf(body);
  if (error != null) return error;
  if (status == HttpStatus.tooManyRequests) return AddonException(s.boxTooManyAttempts, status: status);
  return AddonException(
    body.isNotEmpty && body.length < 300 ? utf8.decode(body, allowMalformed: true) : 'Box: HTTP $status',
    status: status,
  );
}

/// Download from the box straight into the file [target], without holding it in memory (a box
/// backup holds the whole history). A download the box broke off shows as an error: the zip's
/// end record is checked, since the box cannot report an error once it started sending.
Future<void> addonDownloadToFile(
  String path,
  String target,
  void Function(int bytes)? onProgress,
  bool Function()? cancelled,
) async {
  final box = _box;
  final request = http.Request('GET', box.url.resolve(path))..headers.addAll(_headers(box));
  final http.StreamedResponse r;
  try {
    // The box reads and packs the first files before it answers.
    r = await _http(box).send(request).timeout(const Duration(minutes: 2));
  } on Object {
    throw AddonException(s.boxUnreachable(box.address));
  }
  if (r.statusCode >= 300) throw _failure(r.statusCode, await r.stream.toBytes());
  final file = File(target);
  final out = file.openWrite();
  var bytes = 0;
  var stopped = false;
  var complete = false;
  try {
    try {
      await for (final chunk in r.stream.timeout(const Duration(minutes: 2))) {
        if (cancelled?.call() ?? false) {
          stopped = true;
          break;
        }
        out.add(chunk);
        bytes += chunk.length;
        onProgress?.call(bytes);
      }
      await out.flush();
    } on Object {
      throw AddonException(s.boxUnreachable(box.address));
    } finally {
      await out.close();
    }
    if (stopped) throw AddonException(s.boxBackupCancelled, problem: 'cancelled');
    if (!await zipComplete(file)) throw AddonException(s.boxBackupIncomplete);
    complete = true;
  } finally {
    // A broken or cancelled download holds part of the history in plain text: remove it.
    if (!complete && await file.exists()) await file.delete();
  }
}

/// Whether [file] ends with a zip's end-of-central-directory record.
Future<bool> zipComplete(File file) async {
  final raf = await file.open();
  try {
    final length = await raf.length();
    if (length < 22) return false;
    final tail = length < 22 + 0xFFFF ? length : 22 + 0xFFFF;
    await raf.setPosition(length - tail);
    final b = await raf.read(tail);
    for (var i = b.length - 22; i >= 0; i--) {
      if (b[i] == 0x50 && b[i + 1] == 0x4b && b[i + 2] == 0x05 && b[i + 3] == 0x06) {
        return i + 22 + (b[i + 20] | (b[i + 21] << 8)) == b.length;
      }
    }
    return false;
  } finally {
    await raf.close();
  }
}

/// A request whose body is a stream: [IOClient] reads it only as fast as it sends, so a large
/// upload never sits in memory (unlike [http.StreamedRequest], whose sink buffers).
class _StreamRequest extends http.BaseRequest {
  _StreamRequest(super.method, super.url, this._data);
  final Stream<List<int>> _data;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_data);
  }
}

/// Uploads [data] ([length] bytes, if known) with PUT, streamed, and returns the JSON answer.
Future<Map<String, Object?>> addonUpload(
  String path,
  Stream<List<int>> data,
  int? length,
  void Function(int bytes)? onProgress,
) async {
  final box = _box;
  var sent = 0;
  final request = _StreamRequest(
    'PUT',
    box.url.resolve(path),
    data.map((chunk) {
      sent += chunk.length;
      onProgress?.call(sent);
      return chunk;
    }),
  )..headers.addAll({..._headers(box), 'Content-Type': 'application/zip'});
  if (length != null) request.contentLength = length;
  final http.Response r;
  try {
    // The box unpacks and checks the whole backup before it answers.
    r = await http.Response.fromStream(await _http(box).send(request)).timeout(const Duration(minutes: 30));
  } on Object {
    throw AddonException(s.boxUnreachable(box.address));
  }
  if (r.statusCode >= 300) throw _failure(r.statusCode, r.bodyBytes);
  return (jsonDecode(utf8.decode(r.bodyBytes)) as Map).cast<String, Object?>();
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
Future<String> addonPairBox(BoxLink link, String password, String deviceName, {String? app}) async {
  // The box password is worth more than a device access: same rule.
  _requireProtected(link);
  final http.Response r;
  try {
    r = await _http(link)
        .post(
          link.url.resolve('api/box/pair'),
          headers: {
            'Authorization': 'Basic ${base64.encode(utf8.encode('app:$password'))}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'name': deviceName, 'app': ?app}),
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

/// Exchanges the one-time pairing code of [link] for the device access (`POST /api/box/claim`).
/// Runs before [Addon.box], over the same connection as everything else: HTTPS with the pinned
/// certificate when the link has a fingerprint. The code is sent in the body, never in a URL or
/// a header, and like every secret not over plain HTTP outside the local network.
Future<String> addonClaimBox(BoxLink link, String deviceName, {String? app}) async {
  _requireProtected(link);
  final http.Response r;
  try {
    r = await _http(link)
        .post(
          link.url.resolve('api/box/claim'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'code': link.code, 'name': deviceName, 'app': ?app}),
        )
        .timeout(const Duration(seconds: 30));
  } on Object catch (e) {
    debugPrint('Box koppeln: $e');
    throw AddonException(s.boxUnreachable(link.address));
  }
  if (r.statusCode == HttpStatus.tooManyRequests) throw AddonException(s.boxTooManyAttempts, status: r.statusCode);
  // 403: wrong, used or expired. 401 and 404: a box that does not hand out codes.
  if (r.statusCode >= 300) throw AddonException(s.boxCodeInvalid, status: r.statusCode);
  final Object? key;
  try {
    key = (jsonDecode(utf8.decode(r.bodyBytes)) as Map)['key'];
  } on Object {
    throw AddonException(s.boxCodeInvalid);
  }
  if (key is! String || key.isEmpty) throw AddonException(s.boxCodeInvalid);
  return key;
}
