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
/// restart.
Future<void> answerHealth(HttpResponse response) async {
  response.headers.contentType = ContentType.text;
  response.write('ok');
  await response.close();
}
