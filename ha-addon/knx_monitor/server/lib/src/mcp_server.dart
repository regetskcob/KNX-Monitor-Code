import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'atomic_file.dart';
import 'http.dart';
import 'mcp_tools.dart';

/// Busclear's MCP server (Model Context Protocol, Streamable HTTP with JSON answers): AI tools such
/// as Claude or an assistant with the XKNX Editor read the recorded bus, the findings and the
/// project check. Read-only: no tool sends to the bus or changes data.
///
/// - `POST /api/mcp` with `Authorization: Bearer <token>`: JSON-RPC (`initialize`, `tools/list`,
///   `tools/call`, `ping`). Checked before the Ingress or box login, like the Home Assistant
///   integration's token, so a client outside Home Assistant gets in.
/// - `GET/PUT /api/mcp/settings` (admin, through the normal login): `{enabled, token, path}`;
///   PUT `{"enabled": true|false}` switches it, `{"renew": true}` issues a new token.
///
/// Off until an admin switches it on. The token lives in `mcp.json` in the data folder.
class McpService {
  McpService(this.data, this.source, {this.version = 'dev', this.plainHttp, Random? random})
    : _random = random ?? Random.secure();

  /// Whether [request] came in unencrypted although the server also offers HTTPS (box): then the
  /// token is refused, so it never crosses the network in plain text where it need not.
  final bool Function(HttpRequest request)? plainHttp;

  /// Largest request body; a tool call is a few hundred bytes.
  static const maxBody = 64 * 1024;

  /// Most messages in one JSON-RPC batch.
  static const maxBatch = 10;

  /// One tool call at a time: the tools read days of history, and the recording must not suffer.
  var _busy = false;

  final Directory data;

  /// The active installation's data, read on every call.
  final McpSource Function() source;
  final String version;
  final Random _random;

  static const path = '/api/mcp';
  static const settingsPath = '/api/mcp/settings';

  bool _enabled = false;
  String? _token;

  bool get enabled => _enabled;

  File get _file => File('${data.path}/mcp.json');

  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final j = jsonDecode(await _file.readAsString()) as Map<String, Object?>;
      _enabled = j['enabled'] == true;
      _token = j['token'] as String?;
    } on Object {
      _enabled = false;
      _token = null;
    }
  }

  Future<void> _save() => writeAtomic(_file, text: jsonEncode({'enabled': _enabled, 'token': ?_token}));

  String _newToken() => base64Url.encode(List.generate(32, (_) => _random.nextInt(256))).replaceAll('=', '');

  /// Whether [request] is a call of a client with the token (only while switched on).
  bool authorized(HttpRequest request) {
    if (!_enabled || _token == null || request.uri.path != path) return false;
    if (plainHttp?.call(request) ?? false) return false;
    final header = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    if (!header.startsWith('Bearer ')) return false;
    return _equal(header.substring(7).trim(), _token!);
  }

  /// Constant time, so the answer time tells nothing about the token.
  static bool _equal(String a, String b) {
    final x = utf8.encode(a);
    final y = utf8.encode(b);
    var diff = x.length ^ y.length;
    for (var i = 0; i < x.length && i < y.length; i++) {
      diff |= x[i] ^ y[i];
    }
    return diff == 0;
  }

  /// Settings for an admin (`GET`/`PUT` [settingsPath]); `false` if [request] is not for it.
  Future<bool> serveSettings(HttpRequest request, {required bool admin}) async {
    if (request.uri.path != settingsPath) return false;
    final response = request.response;
    if (!admin) {
      response.statusCode = HttpStatus.forbidden;
      await response.close();
      return true;
    }
    if (request.method == 'PUT') {
      final raw = await readBody(request, maxBody);
      final Object? body;
      try {
        body = raw == null ? null : jsonDecode(utf8.decode(raw));
      } on FormatException {
        response.statusCode = HttpStatus.badRequest;
        await response.close();
        return true;
      }
      if (body is! Map) {
        response.statusCode = raw == null ? HttpStatus.requestEntityTooLarge : HttpStatus.badRequest;
        await response.close();
        return true;
      }
      final wasEnabled = _enabled;
      if (body['enabled'] case final bool on) _enabled = on;
      // A new token on every switch-on, so a token handed out earlier does not come back to life.
      if (body['renew'] == true || (_enabled && (!wasEnabled || _token == null))) _token = _newToken();
      await _save();
    }
    await sendJson(response, {'enabled': _enabled, 'token': _enabled ? _token : null, 'path': path});
    return true;
  }

  /// Answers a JSON-RPC request of an [authorized] client.
  Future<void> serve(HttpRequest request) async {
    final response = request.response;
    if (request.method == 'DELETE') {
      response.statusCode = HttpStatus.ok;
      return response.close();
    }
    if (request.method != 'POST') {
      // No server-initiated stream: every answer comes with its request.
      response
        ..statusCode = HttpStatus.methodNotAllowed
        ..headers.set(HttpHeaders.allowHeader, 'POST, DELETE');
      return response.close();
    }
    final raw = await readBody(request, maxBody);
    if (raw == null) {
      response.statusCode = HttpStatus.requestEntityTooLarge;
      return response.close();
    }
    final Object? body;
    try {
      body = jsonDecode(utf8.decode(raw));
    } on FormatException {
      return _send(response, _error(null, -32700, 'parse error'));
    }
    if (body is List && body.length > maxBatch) return _send(response, _error(null, -32600, 'batch too large'));
    if (body is List) {
      final answers = [
        for (final m in body)
          if (await _handle(m) case final a?) a,
      ];
      if (answers.isEmpty) return _accepted(response);
      return _send(response, answers);
    }
    final answer = await _handle(body);
    if (answer == null) return _accepted(response);
    if (body is Map && body['method'] == 'initialize') {
      response.headers.set('Mcp-Session-Id', _newToken().substring(0, 16));
    }
    return _send(response, answer);
  }

  Future<Map<String, Object?>?> _handle(Object? message) async {
    if (message is! Map) return _error(null, -32600, 'invalid request');
    final Object? id = message['id'];
    final method = message['method'];
    final params = (message['params'] as Map?)?.cast<String, Object?>() ?? const {};
    // Notifications (no id) get no answer.
    if (id == null) return null;
    switch (method) {
      case 'initialize':
        return _result(id, {
          'protocolVersion': params['protocolVersion'] ?? '2025-06-18',
          'capabilities': {
            'tools': {'listChanged': false},
          },
          'serverInfo': {'name': 'busclear', 'title': 'Busclear', 'version': version},
          'instructions':
              'Busclear records a KNX installation continuously. Use overview first, then search_telegrams, '
              'device_activity, findings and project_check. All tools only read. editor_handover proposes '
              'corrections for the XKNX Editor; apply them there only with the user.',
        });
      case 'ping':
        return _result(id, const <String, Object?>{});
      case 'tools/list':
        return _result(id, {'tools': McpTools.definitions});
      case 'tools/call':
        final name = params['name'];
        final args = (params['arguments'] as Map?)?.cast<String, Object?>() ?? const {};
        if (name is! String) return _error(id, -32602, 'name missing');
        if (!McpTools.definitions.any((d) => d['name'] == name)) return _error(id, -32602, 'unknown tool $name');
        if (_busy) return _error(id, -32000, 'busy: another tool call is running, retry shortly');
        _busy = true;
        try {
          final result = await McpTools(source()).call(name, args);
          return _result(id, {
            'content': [
              {'type': 'text', 'text': jsonEncode(result)},
            ],
            if (result is Map) 'structuredContent': result,
          });
        } on McpToolError catch (e) {
          return _result(id, {
            'content': [
              {'type': 'text', 'text': e.message},
            ],
            'isError': true,
          });
        } on Object catch (e) {
          // Details only in the log: paths and internals are none of the client's business.
          stderr.writeln('MCP $name: $e');
          return _result(id, {
            'content': [
              {'type': 'text', 'text': 'internal error, see the add-on log'},
            ],
            'isError': true,
          });
        } finally {
          _busy = false;
        }
      default:
        return _error(id, -32601, 'method not found: $method');
    }
  }

  static Map<String, Object?> _result(Object id, Object result) => {'jsonrpc': '2.0', 'id': id, 'result': result};

  static Map<String, Object?> _error(Object? id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };

  static Future<void> _accepted(HttpResponse response) {
    response.statusCode = HttpStatus.accepted;
    return response.close();
  }

  static Future<void> _send(HttpResponse response, Object value) => sendJson(response, value);
}
