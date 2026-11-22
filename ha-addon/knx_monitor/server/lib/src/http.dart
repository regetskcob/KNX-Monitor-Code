import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Bytes of request bodies that all requests together may hold in memory
/// while they are being read: each request has its own limit, but many at once
/// (64 MiB for a catalog each) would fill the memory of a Pi.
const bodyBudget = 32 * 1024 * 1024;

/// Bytes [readBody] currently holds over all requests.
int get bodiesInFlight => _inFlight;
var _inFlight = 0;

/// Thrown by [readBody] when the [bodyBudget] is used up; the server answers
/// 503 with `Retry-After` ([answerBusy]).
class BodyBudgetException implements Exception {
  const BodyBudgetException();
  @override
  String toString() => 'Zu viele Uploads gleichzeitig';
}

/// Reads the request body completely, at most [limit] bytes; `null` if it is
/// larger. Throws [BodyBudgetException] if the bodies of all requests being
/// read together would exceed [bodyBudget]; a single request alone may always
/// use its whole [limit].
Future<Uint8List?> readBody(HttpRequest request, int limit) async {
  if (request.contentLength > limit) return null;
  var held = 0;
  void reserve(int bytes) {
    if (_inFlight > held && _inFlight + bytes > bodyBudget) throw const BodyBudgetException();
    _inFlight += bytes;
    held += bytes;
  }

  try {
    // Announced length: refuse before receiving anything.
    if (request.contentLength > 0) reserve(request.contentLength);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
      if (builder.length > limit) return null;
      if (builder.length > held) reserve(builder.length - held);
    }
    return builder.takeBytes();
  } finally {
    _inFlight -= held;
  }
}

/// 503 with `Retry-After` for [BodyBudgetException] and similar overload.
Future<void> answerBusy(HttpResponse response, {int seconds = 5}) async {
  response
    ..statusCode = HttpStatus.serviceUnavailable
    ..headers.set(HttpHeaders.retryAfterHeader, '$seconds')
    ..headers.contentType = ContentType.text
    ..write('Der Server ist gerade ausgelastet, bitte gleich noch einmal versuchen.');
  await response.close();
}

/// Responds with [value] as JSON, without buffering.
Future<void> sendJson(HttpResponse response, Object? value) async {
  response.headers
    ..contentType = ContentType.json
    ..set(HttpHeaders.cacheControlHeader, 'no-store');
  response.write(jsonEncode(value));
  await response.close();
}

/// Sign of life for the add-on's watchdog (`watchdog` in `config.yaml`).
const healthPath = '/healthz';

/// Responds only while the event loop is running; a hung server shows up this
/// way. Says nothing about the bus: a missing gateway must not trigger a
/// restart. Neither does a full disk, which a restart does not cure. With
/// [stalled] (the recorder's write queue hangs) the answer is 503: the process
/// lives but records nothing, and a restart is what helps.
Future<void> answerHealth(HttpResponse response, {bool stalled = false}) async {
  response.headers.contentType = ContentType.text;
  if (stalled) response.statusCode = HttpStatus.serviceUnavailable;
  response.write(stalled ? 'recorder stalled' : 'ok');
  await response.close();
}

/// `server healthcheck`: asks the running server for [healthPath] on this
/// machine. `true` for an answer below 300 within [timeout]. For Docker's
/// HEALTHCHECK and a systemd timer on the box, where no Supervisor watches.
Future<bool> checkHealth(Map<String, String> env, {Duration timeout = const Duration(seconds: 5)}) async {
  final port = int.tryParse(env['PORT'] ?? '') ?? 8765;
  final bind = env['BIND'];
  final host = bind == null || bind == '0.0.0.0' ? '127.0.0.1' : bind;
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(Uri(scheme: 'http', host: host, port: port, path: healthPath)).timeout(timeout);
    final response = await request.close().timeout(timeout);
    await response.drain<void>().timeout(timeout);
    return response.statusCode < 300;
  } on Object {
    return false;
  } finally {
    client.close(force: true);
  }
}
