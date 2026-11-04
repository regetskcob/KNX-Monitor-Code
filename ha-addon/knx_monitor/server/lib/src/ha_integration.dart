/// Access for the KNX Monitor integration of Home Assistant
/// (`custom_components/knx_monitor`, repository KNX-Monitor-HA).
///
/// Ingress only lets the Supervisor through; the integration runs in Home
/// Assistant Core and needs its own way in. The add-on creates a token once
/// (`ha_integration.json` in the data root, outside the file store) and
/// announces itself to the Supervisor (discovery `knx_monitor`): Home
/// Assistant then shows "New device found: KNX Monitor" and hands host, port
/// and token to the integration.
///
/// The token opens only the endpoints below `/api/ha/`, nothing else:
///
/// - `GET /api/ha/state`: key figures as the MQTT device publishes them
///   ([KeyFigures]), plus version, connection state and read-only.
/// - `POST /api/ha/recording` `{"on": bool}`: continuous recording on or off.
/// - `POST /api/ha/report`: create the installation report now.
/// - `GET /api/ha/history?days=<n>` or `?all=1`: history as ETS file
///   (ets_xml.dart).
/// - `GET /api/ha/diagnostics`: connection, storage and restarts, without
///   names, addresses or values.
/// - `POST /api/ha/claim`, `DELETE /api/ha/claim`: the integration takes
///   over the entities; the MQTT device stops announcing them, and announces
///   them again when the integration is removed.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'bus.dart';
import 'ets_xml.dart';
import 'http.dart';
import 'key_figures.dart';

/// Discovery service name, as in `discovery:` of the add-on's config.yaml and
/// the integration's manifest (`hassio` config flow step).
const haDiscoveryService = 'knx_monitor';

class HaIntegration {
  HaIntegration(
    this.data,
    this.currentBus, {
    required this.version,
    required this.port,
    this.onClaim,
    String? supervisorToken,
    Uri? supervisor,
    this.releaseAfter = const Duration(hours: 1),
    DateTime Function() clock = DateTime.now,
  }) : _supervisorToken = supervisorToken ?? Platform.environment['SUPERVISOR_TOKEN'],
       _supervisor = supervisor ?? Uri.parse('http://supervisor/'),
       _clock = clock,
       _lastSeen = clock(),
       figures = KeyFigures(currentBus, clock: clock);

  final Directory data;
  final BusService Function() currentBus;
  final String version;
  final int port;

  /// Called when the integration takes over (true) or gives back (false).
  final FutureOr<void> Function(bool claimed)? onClaim;

  final String? _supervisorToken;
  final Uri _supervisor;
  final KeyFigures figures;

  String? _token;
  bool _claimed = false;
  Timer? _timer;

  /// Last request of the integration (token); after [releaseAfter] without one
  /// the claim is given back, see [checkClaim].
  DateTime _lastSeen;

  /// The integration polls every 30 seconds; this long without a request it is
  /// gone (removed while the add-on was not running, Home Assistant without it).
  final Duration releaseAfter;
  final DateTime Function() _clock;

  /// Token the integration authenticates with; created on [start].
  String? get token => _token;

  /// Whether the integration has taken over the entities.
  bool get claimed => _claimed;

  File get _file => File('${data.path}/ha_integration.json');

  /// Loads or creates the token, starts the key figures and announces the
  /// add-on to the Supervisor.
  Future<void> start({Duration tick = const Duration(seconds: 60)}) async {
    await _load();
    figures.count();
    await figures.measure();
    _timer = Timer.periodic(tick, (_) async {
      figures.count();
      await figures.measure();
      await checkClaim();
    });
    unawaited(announce());
  }

  void stop() => _timer?.cancel();

  Future<void> _load() async {
    try {
      final json = jsonDecode(await _file.readAsString()) as Map<String, Object?>;
      _token = json['token'] as String?;
      _claimed = json['claimed'] == true;
    } on Object {
      // Missing or damaged: a new token, the integration is offered again.
    }
    if (_token == null || _token!.length < 32) {
      final random = Random.secure();
      _token = [for (var i = 0; i < 32; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
      _claimed = false;
      await _save();
    }
  }

  Future<void> _save() async {
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode({'token': _token, 'claimed': _claimed}), flush: true);
    await tmp.rename(_file.path);
  }

  /// Announces host, port and token to the Supervisor (`POST /discovery`).
  /// The add-on runs in the host network; Home Assistant reaches it under the
  /// add-on's host name, the integration falls back to 127.0.0.1.
  Future<bool> announce() async {
    final supervisorToken = _supervisorToken;
    if (supervisorToken == null || _token == null) return false;
    try {
      final info = await _supervisorJson('GET', 'addons/self/info');
      final host = (info?['data'] as Map?)?['hostname'] as String?;
      final res = await _supervisorJson('POST', 'discovery', {
        'service': haDiscoveryService,
        'config': {'host': host ?? '127.0.0.1', 'port': port, 'token': _token},
      });
      final ok = res?['result'] == 'ok';
      stdout.writeln(ok ? 'Home Assistant: KNX-Monitor-Integration angeboten' : 'Discovery abgelehnt: $res');
      return ok;
    } on Object catch (e) {
      stderr.writeln('Discovery: $e');
      return false;
    }
  }

  Future<Map<String, Object?>?> _supervisorJson(String method, String path, [Map<String, Object?>? body]) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.openUrl(method, _supervisor.resolve(path));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_supervisorToken');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close().timeout(const Duration(seconds: 15));
      final text = await res.transform(utf8.decoder).join();
      return text.isEmpty ? null : (jsonDecode(text) as Map).cast<String, Object?>();
    } finally {
      client.close(force: true);
    }
  }

  /// Gives the entities back to MQTT if the integration has not asked for
  /// [releaseAfter]: removed while the add-on was not running, the claim would
  /// otherwise keep the MQTT device silent forever. It claims again on setup.
  Future<void> checkClaim() async {
    if (_claimed && _clock().difference(_lastSeen) > releaseAfter) {
      stdout.writeln('Home Assistant: Integration meldet sich nicht mehr, MQTT-Gerät übernimmt wieder');
      await _setClaimed(false);
    }
  }

  /// Whether [request] carries the token, compared in constant time.
  bool authorized(HttpRequest request) {
    final token = _token;
    final header = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    if (token == null || !header.startsWith('Bearer ')) return false;
    final given = header.substring(7).trim();
    if (given.length != token.length) return false;
    var diff = 0;
    for (var i = 0; i < token.length; i++) {
      diff |= given.codeUnitAt(i) ^ token.codeUnitAt(i);
    }
    if (diff != 0) return false;
    _lastSeen = _clock();
    return true;
  }

  static bool handles(String path) => path.startsWith('/api/ha/');

  /// Answers the endpoints below `/api/ha/`; `false` for other paths. The
  /// caller checked the token (or Ingress).
  Future<bool> serve(HttpRequest request) async {
    final path = request.uri.path;
    if (!handles(path)) return false;
    final response = request.response;
    final method = request.method;
    final bus = currentBus();
    switch ((method, path)) {
      case ('GET', '/api/ha/state'):
        await sendJson(response, state());
      case ('POST', '/api/ha/recording'):
        final body = await _body(request);
        final on = body?['on'];
        if (on is! bool) {
          response.statusCode = HttpStatus.badRequest;
          await response.close();
        } else {
          await bus.update({'enabled': on});
          figures.count();
          await sendJson(response, state());
        }
      case ('POST', '/api/ha/report'):
        await sendJson(response, await bus.report.generate(null));
      case ('GET', '/api/ha/history'):
        await _history(request, bus);
      case ('GET', '/api/ha/diagnostics'):
        await sendJson(response, await diagnostics());
      case ('POST', '/api/ha/claim'):
        await _setClaimed(true);
        await sendJson(response, {'claimed': true});
      case ('DELETE', '/api/ha/claim'):
        await _setClaimed(false);
        await sendJson(response, {'claimed': false});
      default:
        response.statusCode = HttpStatus.notFound;
        await response.close();
    }
    return true;
  }

  Future<void> _setClaimed(bool on) async {
    if (_claimed == on) return;
    _claimed = on;
    await _save();
    await onClaim?.call(on);
  }

  /// Key figures plus what the integration needs for repairs.
  Map<String, Object?> state() {
    final bus = currentBus();
    return {
      ...figures.state(),
      'version': version,
      'state': bus.state,
      'since': bus.since?.toUtc().toIso8601String(),
      'last_lost': bus.lastLost?.toUtc().toIso8601String(),
      'read_only': bus.readOnly,
      'claimed': _claimed,
    };
  }

  /// For the diagnostics download: no installation name, no addresses, no
  /// values, no host of the gateway.
  Future<Map<String, Object?>> diagnostics() async {
    final bus = currentBus();
    final status = bus.status();
    final storage = await bus.recorder.usage();
    return {
      'version': version,
      'state': bus.state,
      // Only the code: the error text can name the gateway host.
      'problem': status['problem'],
      'has_error': bus.error != null,
      'mode': bus.config.mode,
      'recording': bus.config.enabled,
      'read_only': bus.readOnly,
      'since': bus.since?.toUtc().toIso8601String(),
      'last_lost': bus.lastLost?.toUtc().toIso8601String(),
      'today': bus.today,
      'repeats': bus.repeats,
      'retention_days': bus.recorder.retentionDays,
      'storage': {
        'bytes': storage['bytes'],
        'days': storage['days'],
        'free': storage['free'],
        'low_space': bus.recorder.lowSpace,
        'dropped': bus.recorder.dropped,
        'dropped_low_space': bus.recorder.droppedLowSpace,
      },
      'restarts': ?status['restarts'],
      'claimed': _claimed,
    };
  }

  Future<void> _history(HttpRequest request, BusService bus) async {
    final q = request.uri.queryParameters;
    if (q['all'] == '1') {
      return serveEtsXml(request, bus.recorder);
    }
    final days = (int.tryParse(q['days'] ?? '') ?? 1).clamp(1, etsXmlMaxRange.inDays);
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day - (days - 1));
    // The same handler as the app's download, with the period filled in.
    return serveEtsXmlRange(request, bus.recorder, from, now);
  }

  static Future<Map<String, Object?>?> _body(HttpRequest request) async {
    final raw = await readBody(request, 4096);
    if (raw == null) return null;
    try {
      return raw.isEmpty ? const {} : (jsonDecode(utf8.decode(raw)) as Map).cast<String, Object?>();
    } on Object {
      return null;
    }
  }
}
