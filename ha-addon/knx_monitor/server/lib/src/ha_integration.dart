/// Access for the Busclear integration of Home Assistant
/// (`custom_components/knx_monitor`, repository KNX-Monitor-HA).
///
/// Ingress only lets the Supervisor through; the integration runs in Home
/// Assistant Core and needs its own way in. The add-on creates a token once
/// (`ha_integration.json` in the data root, outside the file store) and
/// announces itself to the Supervisor (discovery `knx_monitor`): Home
/// Assistant then shows "New device found: Busclear" and hands host, port
/// and token to the integration.
///
/// The token opens only the endpoints below `/api/ha/`, nothing else:
///
/// - `GET /api/ha/state`: key figures as the MQTT device publishes them
///   ([KeyFigures]), plus version, connection state and read-only, and
///   `events`: the format version of the event channel `/ws/events`
///   ([EventChannel]); an integration without Supervisor connects to it only
///   when the field is there (older servers have no channel).
/// - `POST /api/ha/recording` `{"on": bool}`: continuous recording on or off.
/// - `POST /api/ha/report`: create the installation report now.
/// - `GET /api/ha/history?days=<n>` or `?all=1`: history as ETS file
///   (ets_xml.dart).
/// - `GET /api/ha/diagnostics`: connection, storage and restarts, without
///   names, addresses or values.
/// - `POST /api/ha/claim`, `DELETE /api/ha/claim`: the integration takes
///   over the entities; the MQTT device stops announcing them, and announces
///   them again when the integration is removed.
/// - `GET /api/ha/watchers`: id and name of each watcher, for one device
///   trigger per watcher (no conditions, no addresses).
/// - `GET /api/ha/silent`: addresses that stopped sending ([CycleWatch]), at
///   most 20, oldest silence first; `POST /api/ha/silent/ignore`
///   `{"address": "1/2/3"}` stops reporting one until it sends again.
/// - `GET /api/ha/health`: the last result of the server's health check
///   ([ServerHealthCheck]); `POST /api/ha/health/run` runs it now and returns the
///   result. Both answer 409 `{"error": "not_enabled"}` while the feature is off
///   (add-on option `health_check`, `HEALTH_CHECK=true`). The check never sends on
///   the bus; `{"read": true}` asks for the read test, which this server does not
///   have (422, in read-only mode with `"error": "read_only"`).
///
/// Without Supervisor (Busclear Box, Docker; `BOX=1`) there is no discovery and no
/// token ([tokenAccess] off): the server lets a paired device with admin
/// rights (box_access.dart, bearer token from the pairing link) through to the
/// same endpoints and calls [touch] for it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'bus.dart';
import 'cycle_watch.dart';
import 'ets_xml.dart';
import 'event_channel.dart';
import 'health_check.dart';
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
    this.tokenAccess = true,
    DateTime Function() clock = DateTime.now,
    CycleWatch? cycles,
    Duration minSilence = CycleWatch.defaultMinSilence,
    bool healthCheck = false,
    int healthQuietHour = 3,
    Future<Map<String, Object?>> Function(HealthScanInput input)? healthScan,
  }) : _supervisorToken = supervisorToken ?? Platform.environment['SUPERVISOR_TOKEN'],
       _supervisor = supervisor ?? Uri.parse('http://supervisor/'),
       _clock = clock,
       _lastSeen = clock(),
       figures = KeyFigures(currentBus, clock: clock),
       cycles = cycles ?? CycleWatch(currentBus, clock: clock, minSilence: minSilence) {
    health = ServerHealthCheck(
      currentBus,
      enabled: healthCheck,
      cycles: this.cycles,
      quietHour: healthQuietHour,
      clock: clock,
      scan: healthScan,
    );
  }

  final Directory data;
  final BusService Function() currentBus;
  final String version;
  final int port;

  /// Called when the integration takes over (true) or gives back (false).
  final FutureOr<void> Function(bool claimed)? onClaim;

  final String? _supervisorToken;
  final Uri _supervisor;
  final KeyFigures figures;

  /// Addresses that stopped sending (`/api/ha/silent`).
  final CycleWatch cycles;

  /// The server's health check (`/api/ha/health`), off unless switched on.
  late final ServerHealthCheck health;

  /// Whether the integration authenticates with the add-on's own token (Home
  /// Assistant with Supervisor, which hands it over through discovery). Off on
  /// the box and in Docker: there the token could not be delivered safely, and
  /// a paired admin device opens `/api/ha/` instead.
  final bool tokenAccess;

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

  /// Loads or creates the token, starts the key figures and the cycle watch
  /// and announces the add-on to the Supervisor.
  Future<void> start({Duration tick = const Duration(seconds: 60), Duration? firstCycleCheck}) async {
    await _load();
    if (firstCycleCheck != null) {
      cycles.start(first: firstCycleCheck);
    } else {
      cycles.start();
    }
    figures.count();
    await figures.measure();
    await health.load();
    _timer = Timer.periodic(tick, (_) async {
      figures.count();
      await figures.measure();
      await checkClaim();
      // The daily run, and the first one soon after the feature was switched on.
      await health.tick();
    });
    if (tokenAccess) unawaited(announce());
  }

  void stop() {
    _timer?.cancel();
    cycles.stop();
  }

  Future<void> _load() async {
    try {
      final json = jsonDecode(await _file.readAsString()) as Map<String, Object?>;
      _token = json['token'] as String?;
      _claimed = json['claimed'] == true;
    } on Object {
      // Missing or damaged: a new token, the integration is offered again.
    }
    if (!tokenAccess) {
      // No token without Supervisor: nothing could hand it over. One left
      // from an earlier start in the add-on does not stay valid on disk.
      if (_token != null) {
        _token = null;
        await _save();
      }
      return;
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
    await tmp.writeAsString(jsonEncode({'token': ?_token, 'claimed': _claimed}), flush: true);
    await tmp.rename(_file.path);
  }

  /// Announces host, port and token to the Supervisor (`POST /discovery`).
  /// The add-on runs in the host network; the Supervisor's DNS resolves its
  /// host name to the gateway of the hassio network (the host), so Home
  /// Assistant reaches it there. The integration sends the token only to the
  /// announced address; 127.0.0.1 only if no host name is known.
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
      stdout.writeln(ok ? 'Home Assistant: Busclear-Integration angeboten' : 'Discovery abgelehnt: $res');
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

  /// Whether [request] carries the token, compared in constant time. Always
  /// `false` without [tokenAccess].
  bool authorized(HttpRequest request) {
    final token = _token;
    if (!tokenAccess) return false;
    final header = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    if (token == null || !header.startsWith('Bearer ')) return false;
    final given = header.substring(7).trim();
    if (given.length != token.length) return false;
    var diff = 0;
    for (var i = 0; i < token.length; i++) {
      diff |= given.codeUnitAt(i) ^ token.codeUnitAt(i);
    }
    if (diff != 0) return false;
    touch();
    return true;
  }

  /// The integration has just made a request (the claim stays, see
  /// [checkClaim]); for requests the caller authorised otherwise (box device).
  void touch() => _lastSeen = _clock();

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
      case ('GET', '/api/ha/watchers'):
        // Only what a trigger needs: no conditions, no addresses.
        await sendJson(response, [
          for (final r in await bus.watchers.rules()) {'id': r.id, 'name': r.name},
        ]);
      case ('GET', '/api/ha/silent'):
        await sendJson(response, cycles.silent());
      case ('POST', '/api/ha/silent/ignore'):
        final address = (await _body(request))?['address'];
        if (address is! String || address.length > 16) {
          response.statusCode = HttpStatus.badRequest;
          await response.close();
        } else if (!await cycles.ignore(address)) {
          response.statusCode = HttpStatus.notFound;
          await response.close();
        } else {
          await sendJson(response, {'ignored': address});
        }
      case ('GET', '/api/ha/health'):
        if (!health.enabled) {
          await _healthOff(response);
        } else {
          await health.load();
          await sendJson(response, health.last());
        }
      case ('POST', '/api/ha/health/run'):
        final body = await _body(request);
        if (!health.enabled) {
          await _healthOff(response);
        } else if (body == null) {
          response.statusCode = HttpStatus.badRequest;
          await response.close();
        } else if (body['read'] == true) {
          // Read requests only when asked for, and never in read-only mode. This server has
          // no read test yet, so it refuses either way and sends nothing.
          response.statusCode = HttpStatus.unprocessableEntity;
          await sendJson(response, {'error': bus.readOnly ? 'read_only' : 'read_test_not_supported'});
        } else {
          await sendJson(response, await health.run());
        }
      default:
        response.statusCode = HttpStatus.notFound;
        await response.close();
    }
    return true;
  }

  /// The feature is off: say so, and how to switch it on.
  static Future<void> _healthOff(HttpResponse response) {
    response.statusCode = HttpStatus.conflict;
    return sendJson(response, {
      'enabled': false,
      'error': 'not_enabled',
      'option': ServerHealthCheck.option,
      'env': ServerHealthCheck.variable,
    });
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
      'silent': cycles.count,
      'events': EventChannel.formatVersion,
      // On or off, and state, time and counts of the last run (without the findings).
      'health_check': health.summary(),
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
      // Only how many, no addresses.
      'silent': cycles.count,
      // Only whether it is on and how the last run ended, no addresses.
      'health_check': {
        'enabled': health.enabled,
        if (health.enabled) ...{'status': health.summary()['status'], 'time': health.summary()['time']},
      },
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
