import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The KNX project of Home Assistant's KNX integration, for the import in the app: the project as
/// the integration parsed it (xknxproject; uploaded in its panel or sent by the XKNX Editor) and
/// the group addresses Home Assistant itself writes to (entities and exposes), which Busclear then
/// counts as senders from outside the project.
///
/// Uses the Core WebSocket API through the Supervisor (`homeassistant_api`). Without a Supervisor
/// (box, development) [fetch] returns `null`.
class HaKnxProject {
  HaKnxProject({String? token, this.websocket = 'ws://supervisor/core/websocket', this.connector = WebSocket.connect})
    : token = token ?? Platform.environment['SUPERVISOR_TOKEN'];

  final String? token;
  final String websocket;
  final Future<WebSocket> Function(String url) connector;

  /// `{loaded, project, ha_groups}`; `loaded` false when the integration has no project.
  /// Throws [StateError] when Home Assistant cannot be reached or refuses.
  Future<Map<String, Object?>?> fetch() async {
    if (token == null) return null;
    final ws = await connector(websocket).timeout(const Duration(seconds: 10));
    final replies = StreamIterator(
      ws.where((m) => m is String).map((m) => jsonDecode(m as String) as Map<String, Object?>),
    );
    Future<Map<String, Object?>> next() async {
      // A large project takes a moment to serialise.
      if (!await replies.moveNext().timeout(const Duration(seconds: 60))) {
        throw StateError('Home Assistant hat die Verbindung getrennt');
      }
      return replies.current;
    }

    var id = 0;
    Future<Map<String, Object?>> call(String type) async {
      final mine = ++id;
      ws.add(jsonEncode({'type': type, 'id': mine}));
      while (true) {
        final m = await next();
        if (m['type'] == 'result' && m['id'] == mine) return m;
      }
    }

    try {
      if ((await next())['type'] != 'auth_required') throw StateError('unerwartete Begrüßung');
      ws.add(jsonEncode({'type': 'auth', 'access_token': token}));
      if ((await next())['type'] != 'auth_ok') throw StateError('Anmeldung abgelehnt');
      final project = await call('knx/get_knx_project');
      if (project['success'] != true) {
        // No KNX integration (unknown command) or no rights.
        throw StateError('${(project['error'] as Map?)?['message'] ?? 'knx/get_knx_project'}');
      }
      final result = project['result'];
      final loaded = result is Map && result['project_loaded'] == true && result['knxproject'] is Map;
      // Older Home Assistant versions lack these commands: then simply no external senders.
      final haGroups = <String>{};
      final entities = await call('knx/get_entities_by_group');
      if (entities['success'] == true && entities['result'] is Map) {
        haGroups.addAll((entities['result']! as Map).keys.cast<String>());
      }
      final exposes = await call('knx/get_expose_groups');
      if (exposes['success'] == true && exposes['result'] is Map) {
        for (final list in (exposes['result']! as Map).values) {
          if (list is List) haGroups.addAll(list.whereType<String>());
        }
      }
      return {'loaded': loaded, if (loaded) 'project': result['knxproject'], 'ha_groups': haGroups.toList()..sort()};
    } finally {
      await ws.close();
    }
  }
}
