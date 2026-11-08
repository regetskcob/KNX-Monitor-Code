import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Dashboard card "Busclear Diagramm" (`custom:knx-monitor-chart-card`):
/// On every start the add-on places the card in `/config/www/knx-monitor/`
/// (`/local/knx-monitor/…` in Home Assistant) and registers it as a
/// dashboard resource. It then appears in the card picker without HACS.
///
/// The card fetches its values via Ingress (`/api/charts`, see
/// [ChartService]); [install] writes the add-on's Ingress path into the
/// file. Dashboards in YAML mode have no resource API – there the user has
/// to add the resource manually (DOCS.md).
class LovelaceCard {
  LovelaceCard({
    required this.template,
    String? token,
    Directory? config,
    this.supervisor = 'http://supervisor',
    this.websocket = 'ws://supervisor/core/websocket',
    this.connector = WebSocket.connect,
  }) : token = token ?? Platform.environment['SUPERVISOR_TOKEN'],
       config = config ?? Directory('/homeassistant');

  /// Card with the placeholders `__KNX_MONITOR_INGRESS__` and
  /// `__KNX_MONITOR_VERSION__` (in the image under /app/card/).
  final File template;

  final String? token;

  /// Home Assistant configuration folder (`map: homeassistant_config`).
  final Directory config;
  final String supervisor;
  final String websocket;
  final Future<WebSocket> Function(String url) connector;

  static const fileName = 'knx-monitor-chart-card.js';

  /// Path in Home Assistant, without `?v=`.
  static const url = '/local/knx-monitor/$fileName';

  /// Places the card and registers it. Returns a result for the log; errors
  /// do not throw – the add-on runs just the same without the card.
  ///
  /// [freshWww]: `www` did not exist before – Home Assistant only serves
  /// `/local` after a restart.
  Future<({String message, bool freshWww})> install({required String version}) async {
    if (token == null) return (message: 'ohne Supervisor', freshWww: false);
    if (!await config.exists()) {
      return (message: 'Konfigurationsordner fehlt (map homeassistant_config)', freshWww: false);
    }
    try {
      final ingress = await _ingressEntry();
      final source = (await template.readAsString())
          .replaceAll('__KNX_MONITOR_INGRESS__', ingress)
          .replaceAll('__KNX_MONITOR_VERSION__', version);
      final www = Directory('${config.path}/www');
      final freshWww = !await www.exists();
      final dir = Directory('${www.path}/knx-monitor');
      await dir.create(recursive: true);
      final file = File('${dir.path}/$fileName');
      if (!await file.exists() || await file.readAsString() != source) {
        await file.writeAsString(source, flush: true);
      }
      // Content hash in the name: browsers load a new version immediately,
      // even if only the Ingress path changed (reinstallation).
      final resource = '$url?v=${_hash(source)}';
      final registered = await _register(resource);
      return (message: registered, freshWww: freshWww);
    } on Object catch (e) {
      return (message: 'nicht eingerichtet: $e', freshWww: false);
    }
  }

  /// The add-on's `/api/hassio_ingress/<token>` (Supervisor, `addons/self/info`).
  Future<String> _ingressEntry() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse('$supervisor/addons/self/info'));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final res = await req.close().timeout(const Duration(seconds: 10));
      final body = jsonDecode(await utf8.decodeStream(res)) as Map<String, Object?>;
      final entry = (body['data'] as Map?)?['ingress_entry'];
      if (res.statusCode != HttpStatus.ok || entry is! String || !entry.startsWith('/api/hassio_ingress/')) {
        throw StateError('Ingress-Adresse fehlt (HTTP ${res.statusCode})');
      }
      return entry;
    } finally {
      client.close();
    }
  }

  /// Registers [resource] as a module or replaces an older version.
  Future<String> _register(String resource) async {
    final ws = await connector(websocket).timeout(const Duration(seconds: 10));
    final replies = StreamIterator(
      ws.where((m) => m is String).map((m) => jsonDecode(m as String) as Map<String, Object?>),
    );
    Future<Map<String, Object?>> next() async {
      if (!await replies.moveNext().timeout(const Duration(seconds: 10))) {
        throw StateError('Home Assistant hat die Verbindung getrennt');
      }
      return replies.current;
    }

    var id = 0;
    Future<Map<String, Object?>> call(Map<String, Object?> message) async {
      final mine = ++id;
      ws.add(jsonEncode({...message, 'id': mine}));
      while (true) {
        final m = await next();
        if (m['type'] == 'result' && m['id'] == mine) return m;
      }
    }

    try {
      if ((await next())['type'] != 'auth_required') throw StateError('unerwartete Begrüßung');
      ws.add(jsonEncode({'type': 'auth', 'access_token': token}));
      if ((await next())['type'] != 'auth_ok') throw StateError('Anmeldung abgelehnt');
      final list = await call({'type': 'lovelace/resources'});
      if (list['success'] != true) {
        // YAML mode: resources are defined in configuration.yaml.
        return 'Ressourcen nicht änderbar (YAML-Modus?) – $url von Hand eintragen';
      }
      final existing = [
        for (final r in list['result'] as List? ?? const [])
          if (r is Map && '${r['url']}'.split('?').first == url) r,
      ];
      if (existing.any((r) => r['url'] == resource)) return 'aktuell';
      final result = existing.isEmpty
          ? await call({'type': 'lovelace/resources/create', 'res_type': 'module', 'url': resource})
          : await call({
              'type': 'lovelace/resources/update',
              'resource_id': existing.first['id'],
              'res_type': 'module',
              'url': resource,
            });
      if (result['success'] != true) throw StateError('${(result['error'] as Map?)?['message']}');
      return existing.isEmpty ? 'angemeldet' : 'aktualisiert';
    } finally {
      await replies.cancel();
      await ws.close();
    }
  }

  /// Short, stable fingerprint (FNV-1a, 32 bit) for `?v=`.
  static String _hash(String s) {
    var h = 0x811c9dc5;
    for (final b in utf8.encode(s)) {
      h = ((h ^ b) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}
