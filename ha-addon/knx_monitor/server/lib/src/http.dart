import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Reads the request body completely, at most [limit] bytes.
Future<Uint8List?> readBody(HttpRequest request, int limit) async {
  if (request.contentLength > limit) return null;
  final builder = BytesBuilder(copy: false);
  await for (final chunk in request) {
    builder.add(chunk);
    if (builder.length > limit) return null;
  }
  return builder.takeBytes();
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
