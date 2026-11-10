import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Home Assistant from within the add-on, via the Supervisor API: events for
/// automations and whether the KNX integration is set up. Without a Supervisor
/// (Busclear Box, development) it does nothing.
///
/// Events (trigger "Event" in automations, blueprints in the public repo under
/// `blueprints/`):
///
/// - [watcherEvent] `knx_monitor_watcher`: a watcher fires.
/// - [alarmEvent] `knx_monitor_alarm`: an alarm or fault object turns on
///   or off.
/// - [busEvent] `knx_monitor_bus`: the bus connection is lost or restored.
class HomeAssistant {
  HomeAssistant({String? token, Uri? base})
    : token = token ?? Platform.environment['SUPERVISOR_TOKEN'],
      base = base ?? Uri.parse('http://supervisor/core/');

  static final instance = HomeAssistant();

  static const watcherEvent = 'knx_monitor_watcher';
  static const alarmEvent = 'knx_monitor_alarm';
  static const busEvent = 'knx_monitor_bus';

  final String? token;

  /// Base of the Core API, ends with "/" (tests: local server).
  final Uri base;

  bool get available => token != null;

  /// Whether the KNX integration is set up. `null` while unknown or without
  /// Home Assistant (see [refreshKnx]).
  bool? knx;

  /// Fires an event. Errors only go to the log: an automation that is not
  /// triggered must not disturb the recording.
  Future<void> fire(String type, Map<String, Object?> data) async {
    if (token == null) return;
    try {
      final res = await _request('POST', 'api/events/$type', body: data);
      await res.drain<void>();
      if (res.statusCode >= 300) stderr.writeln('Ereignis $type: HTTP ${res.statusCode}');
    } on Object catch (e) {
      stderr.writeln('Ereignis $type: $e');
    }
  }

  /// Asks Home Assistant whether the KNX integration is loaded
  /// (`/api/config`, `components`), and remembers it in [knx].
  Future<bool?> refreshKnx() async {
    if (token == null) return null;
    try {
      final res = await _request('GET', 'api/config');
      if (res.statusCode != HttpStatus.ok) {
        await res.drain<void>();
        return knx;
      }
      final json = jsonDecode(await utf8.decodeStream(res)) as Map<String, Object?>;
      final components = (json['components'] as List? ?? const []).cast<String>();
      return knx = components.contains('knx');
    } on Object catch (e) {
      stderr.writeln('Home Assistant /api/config: $e');
      return knx;
    }
  }

  Future<HttpClientResponse> _request(String method, String path, {Map<String, Object?>? body}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.openUrl(method, base.resolve(path));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      return await req.close().timeout(const Duration(seconds: 10));
    } finally {
      client.close();
    }
  }
}

/// Path of the add-on's page in the Home Assistant frontend from the answer of
/// the Supervisor (`GET /addons/self/info`): `/hassio/ingress/<slug>`, or `null`
/// without a usable slug. The slug ends up in a link, so only plain characters.
String? panelPathOf(Map<String, Object?> info) => switch ((info['data'] as Map?)?['slug']) {
  final String slug when RegExp(r'^[a-z0-9_]+$').hasMatch(slug) => '/hassio/ingress/$slug',
  _ => null,
};
