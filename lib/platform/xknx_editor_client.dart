import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/xknx_editor_handover.dart';

/// Default address of the XKNX Editor's MCP server (Settings › AI/MCP in the editor).
final xknxEditorDefaultEndpoint = Uri.parse('http://127.0.0.1:8766/mcp');

/// The editor answered with an error, or could not be reached.
class XknxEditorException implements Exception {
  const XknxEditorException(this.message);

  /// [message] when a token would go unencrypted over the network.
  static const insecureToken = 'insecure-token';
  final String message;
  @override
  String toString() => message;
}

/// Minimal client for the MCP server of the XKNX Editor (Streamable HTTP, JSON-RPC): just enough to
/// call its tools. Reaches the editor on the same computer or, if the editor listens on the
/// network with a bearer token, on another one.
class XknxEditorClient {
  XknxEditorClient(this.endpoint, {this.token, http.Client? client}) : _http = client ?? http.Client();

  final Uri endpoint;
  final String? token;
  final http.Client _http;
  String? _session;
  var _id = 0;

  Future<void> _initialize() async {
    await _post({
      'jsonrpc': '2.0',
      'id': ++_id,
      'method': 'initialize',
      'params': {
        'protocolVersion': '2025-06-18',
        'capabilities': <String, Object?>{},
        'clientInfo': {'name': 'busclear', 'version': '1'},
      },
    });
    await _post({'jsonrpc': '2.0', 'method': 'notifications/initialized'});
  }

  /// Calls the tool [name] and returns its result, decoded from JSON where it is JSON.
  Future<Object?> call(String name, [Map<String, Object?> args = const {}]) async {
    if (_session == null) await _initialize();
    final reply = await _post({
      'jsonrpc': '2.0',
      'id': ++_id,
      'method': 'tools/call',
      'params': {'name': name, 'arguments': args},
    });
    if (reply == null) throw const XknxEditorException('no answer');
    if (reply['error'] case final Map<String, Object?> e) {
      throw XknxEditorException('${e['message'] ?? e}');
    }
    final result = (reply['result'] as Map?)?.cast<String, Object?>() ?? const {};
    final text = [
      for (final c in (result['content'] as List? ?? const []))
        if (c is Map && c['type'] == 'text') c['text'] as String? ?? '',
    ].join('\n');
    if (result['isError'] == true) throw XknxEditorException(text);
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  /// The token only goes over HTTPS or to this computer: in plain HTTP on the network anyone
  /// listening could take it over.
  bool get _tokenSafe =>
      token == null ||
      token!.isEmpty ||
      endpoint.scheme == 'https' ||
      const {'127.0.0.1', 'localhost', '::1', '[::1]'}.contains(endpoint.host);

  Future<Map<String, Object?>?> _post(Map<String, Object?> body) async {
    if (!_tokenSafe) throw const XknxEditorException(XknxEditorException.insecureToken);
    final http.Response response;
    try {
      response = await _http
          .post(
            endpoint,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json, text/event-stream',
              'MCP-Protocol-Version': '2025-06-18',
              'Mcp-Session-Id': ?_session,
              if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(minutes: 10));
    } on Object catch (e) {
      throw XknxEditorException('$e');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const XknxEditorException('401');
    }
    if (response.statusCode >= 400) throw XknxEditorException('HTTP ${response.statusCode}');
    _session ??= response.headers['mcp-session-id'];
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (text.trim().isEmpty) return null;
    if (text.trimLeft().startsWith('{')) return (jsonDecode(text) as Map).cast<String, Object?>();
    // Server-sent events: the last message with an id is the answer.
    Map<String, Object?>? answer;
    for (final line in const LineSplitter().convert(text)) {
      if (!line.startsWith('data:')) continue;
      final data = jsonDecode(line.substring(5).trim());
      if (data is Map && data.containsKey('id')) answer = data.cast<String, Object?>();
    }
    return answer;
  }

  void close() => _http.close();

  // --- What Busclear uses -------------------------------------------------------------------------

  /// Name and file of the open project, or `null` if none is open.
  Future<({String name, String path})?> openProject() async {
    final status = await call('project_status');
    if (status is! Map || status['open'] != true) return null;
    final info = await call('project_info');
    if (info is! Map) return null;
    return (name: '${info['name'] ?? ''}', path: '${info['path'] ?? ''}');
  }

  /// Hands [handover] over: corrections via `project_batch` (checked with a dry run first, applied
  /// as one undoable unit), then the notes appended to the comments. Programs nothing.
  Future<XknxHandoverResult> apply(XknxEditorHandover handover) async {
    var applied = 0;
    final failed = <String>[];
    if (handover.operations.isNotEmpty) {
      final check = await call('project_batch', {'operations': handover.operations, 'dry_run': true});
      if (check is Map && check['valid'] == false) {
        throw XknxEditorException(_issues(check));
      }
      final result = await call('project_batch', {'operations': handover.operations, 'atomic': false});
      if (result is Map) {
        for (final r in (result['results'] as List? ?? const [])) {
          if (r is! Map) continue;
          if (r['status'] == 'ok') {
            applied++;
          } else if (r['status'] == 'error') {
            failed.add('${handover.operations[r['index'] as int]['op']}: ${r['error']}');
          }
        }
      }
    }
    var noted = 0;
    final project = await call('project_get_comment', {'kind': 'project'});
    final projectText = project is Map ? project['text'] as String? : null;
    final previous = parseXknxIndex(projectText);
    if (handover.notes.isNotEmpty || previous.groups.isNotEmpty || previous.devices.isNotEmpty) {
      final gaIds = <String, int>{};
      final list = await call('project_list_group_addresses');
      for (final g in (list is Map ? list['items'] as List? ?? const [] : const [])) {
        if (g is Map && g['address'] is String && g['id'] is int) gaIds[g['address'] as String] = g['id'] as int;
      }
      final nodeIds = <String, int>{};
      final devices = await call('project_list_devices');
      for (final d in (devices is Map ? devices['items'] as List? ?? const [] : const [])) {
        if (d is Map && d['individual_address'] is String && d['node_id'] is int) {
          nodeIds[d['individual_address'] as String] = d['node_id'] as int;
        }
      }
      // New notes per element, then the elements annotated last time that have none now (their
      // old lines go).
      final targets = <(String, int), List<String>>{};
      for (final n in handover.notes) {
        final json = n.toJson(handover.style);
        final key = (json['group_address'] ?? json['device_address'])! as String;
        final id = n.group != null ? gaIds[key] : nodeIds[key];
        if (id == null) {
          failed.add('$key: not in the project');
          continue;
        }
        targets[(n.group != null ? 'group_address' : 'device', id)] = n.lines;
      }
      for (final id in previous.groups) {
        targets.putIfAbsent(('group_address', id), () => const []);
      }
      for (final id in previous.devices) {
        targets.putIfAbsent(('device', id), () => const []);
      }
      final ops = <Map<String, Object?>>[];
      for (final MapEntry(key: (kind, id), value: lines) in targets.entries) {
        try {
          final current = await call('project_get_comment', {'kind': kind, 'element_id': id});
          final before = current is Map ? current['text'] as String? ?? '' : '';
          final after = mergeXknxComment(before, lines);
          if (after != before.trim()) {
            ops.add({
              'op': 'set_comment',
              'params': {'kind': kind, 'element_id': id, 'text': after},
            });
          }
        } on XknxEditorException {
          // Removed from the project since the last handover: nothing to clean.
        }
      }
      final index = xknxIndexLine(
        [
          for (final (kind, id) in targets.keys)
            if (kind == 'group_address' && targets[(kind, id)]!.isNotEmpty) id,
        ],
        [
          for (final (kind, id) in targets.keys)
            if (kind == 'device' && targets[(kind, id)]!.isNotEmpty) id,
        ],
      );
      ops.add({
        'op': 'set_comment',
        'params': {
          'kind': 'project',
          'text': mergeXknxComment(projectText, [index]),
        },
      });
      // One batch instead of one call per comment (the editor still records each as a step).
      final result = await call('project_batch', {'operations': ops, 'atomic': false});
      if (result is Map) {
        for (final r in (result['results'] as List? ?? const [])) {
          if (r is! Map) continue;
          final params = ops[r['index'] as int]['params']! as Map;
          if (params['kind'] == 'project') continue;
          if (r['status'] == 'ok') {
            if (targets[(params['kind'], params['element_id'])]?.isNotEmpty ?? false) noted++;
          } else if (r['status'] == 'error') {
            failed.add('${params['kind']} ${params['element_id']}: ${r['error']}');
          }
        }
      }
    }
    return (applied: applied, noted: noted, failed: failed);
  }

  /// Compares a programmed device with the project without writing anything ("Test Programming"
  /// in the editor): reads the device and returns the bytes a download would change.
  Future<XknxDevicePreview> previewDownload(
    String individualAddress, {
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final r = await call('connection_evaluate_device', {
      'device_address': individualAddress,
      'timeout': timeout.inSeconds,
    });
    if (r is! Map) throw XknxEditorException('$r');
    return (
      config: (r['config_bytes'] as num?)?.toInt() ?? 0,
      changed: (r['changed_bytes'] as num?)?.toInt() ?? 0,
      summary: '${r['summary'] ?? ''}',
    );
  }

  /// Individual addresses of the devices in the editor's open project, in address order.
  Future<List<String>> deviceAddresses() async {
    final list = await call('project_list_devices');
    final out = [
      for (final d in (list is Map ? list['items'] as List? ?? const [] : const []))
        if (d is Map && d['individual_address'] is String) d['individual_address'] as String,
    ];
    int key(String a) => a.split('.').fold(0, (v, p) => v * 256 + (int.tryParse(p) ?? 0));
    return out..sort((a, b) => key(a).compareTo(key(b)));
  }

  static String _issues(Map<Object?, Object?> check) => [
    for (final r in (check['results'] as List? ?? const []))
      if (r is Map && r['valid'] == false) '${r['op']}: ${r['issue']}',
  ].join('\n');
}

/// Outcome of a handover: corrections applied, notes written, and what failed.
typedef XknxHandoverResult = ({int applied, int noted, List<String> failed});

/// Download preview: configuration bytes that would change ([config], 0 = the device carries the
/// project), all changed bytes and the editor's summary.
typedef XknxDevicePreview = ({int config, int changed, String summary});
