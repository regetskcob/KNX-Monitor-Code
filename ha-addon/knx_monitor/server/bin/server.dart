import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:knx_monitor_server/box.dart';
import 'package:knx_monitor_server/bus.dart';
import 'package:knx_monitor_server/files.dart';

/// Server of the Home Assistant add-on "KNX Monitor".
///
/// - serves the Flutter web app (via HA Ingress in the sidebar),
/// - relays KNXnet/IP between the WebSocket "/ws" and UDP (browsers cannot do UDP),
/// - stores catalog, recordings and history under "/api/files/…" in the folder
///   of the active installation (`installations/<id>/`, "/api/installations"),
/// - in continuous mode, keeps its own bus connection, records, and distributes
///   the frames to all open views ("/ws/bus", "/api/bus").
///
/// Environment: PORT (8765), WEB_DIR (/app/web), DATA_DIR (/data/app),
/// ALLOW_ALL=1 allows access outside of Ingress (development only).
/// BOX=1: KNX box without Home Assistant – access with the box password or
/// device access instead of Ingress (BOX_PASSWORD for the first password, BOX_NAME;
/// LAN_ACCESS=yes allows access over the cable, otherwise only from the box Wi-Fi).
/// MQTT_HOST (+ MQTT_PORT, MQTT_USER, MQTT_PASSWORD, MQTT_SSL): MQTT device
/// without Supervisor, e.g. in a Docker container next to ioBroker.
///
/// `server sheet <folder>`: writes the box sheet as knx-box-de.pdf and
/// knx-box-en.pdf (firstboot.sh). The values come from BOX_NAME, WLAN_SSID,
/// WLAN_PASSWORD, BOX_PASSWORD, BOX_LINK and LAN_ACCESS, not from arguments,
/// so that no passwords show up in the process list.
///
/// `server grafana [prometheus|influxdb]`: writes the Grafana template to
/// standard output (the same as `/api/export/grafana`).
///
/// `server hat [seconds]`: checks the KNX HAT (kBerry on /dev/ttyAMA0, see
/// docs/kberry.md) and writes the report as JSON; run via SSH on the box.
Future<void> main(List<String> args) async {
  final env = Platform.environment;
  if (args.isNotEmpty && args.first == 'sheet') {
    await _writeSheets(args.length > 1 ? args[1] : '.', env);
    return;
  }
  if (args.isNotEmpty && args.first == 'grafana') {
    stdout.writeln(jsonEncode(grafanaDashboard(args.length > 1 ? args[1] : 'prometheus')));
    return;
  }
  if (args.isNotEmpty && args.first == 'hat') {
    final hat = KberryService();
    final seconds = int.tryParse(args.length > 1 ? args[1] : '') ?? 10;
    final report = await KberryProbe(
      (baud) => TtyLine.open(hat.device, baud),
      onStep: (step) => stderr.writeln('… $step'),
    ).run(listen: Duration(seconds: seconds.clamp(1, 120)));
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({'system': await kberrySystem(hat.device), 'report': report}),
    );
    return;
  }
  final port = int.tryParse(env['PORT'] ?? '') ?? 8765;
  final web = Directory(env['WEB_DIR'] ?? '/app/web');
  final data = Directory(env['DATA_DIR'] ?? '/data/app');
  await data.create(recursive: true);
  final crash = CrashWatch(data, version: BusService.version);
  await crash.start();
  // As before, the process exits on an unhandled error (systemd or the
  // watchdog restarts it), except that the reason is recorded first.
  await runZonedGuarded(() => _serve(env, port, web, data, crash), (error, stack) {
    stderr.writeln('Unbehandelter Fehler: $error\n$stack');
    crash.recordError(error, stack);
    exit(255);
  });
}

Future<void> _serve(Map<String, String> env, int port, Directory web, Directory data, CrashWatch crash) async {
  final allowAll = env['ALLOW_ALL'] == '1';
  // Read-only (read_only.dart): in the add-on the option `read_only`, on by default;
  // Docker, Linux and box with READ_ONLY=1, off by default.
  _readOnly = HomeAssistant.instance.available ? await _flag('read_only') : env['READ_ONLY'] == '1';
  if (_readOnly) stdout.writeln('KNX Monitor: Nur-Lesen, es geht nichts auf den Bus');
  final box = env['BOX'] == '1'
      ? await BoxAccess.open(
          data,
          initialPassword: env['BOX_PASSWORD'],
          name: env['BOX_NAME'],
          initialLanAccess: env['LAN_ACCESS'] == 'yes',
          sticker: env['BOX_STICKER'] == '1',
        )
      : null;
  // Without BOX_PASSWORD (development only) the first password is logged once;
  // on the box, firstboot.sh sets it from knx-box.txt.
  if (box?.firstPassword != null && (env['BOX_PASSWORD'] ?? '').isEmpty) {
    stdout.writeln('KNX-Box: erstes Passwort ${box!.firstPassword}');
  }

  // Box: set the clock without internet (iPhone, KNX time sender); the request is
  // carried out on the host by knx-box-time.path (DATA_DIR is /var/lib/knx-box there).
  final clock = box == null ? null : BoxClock(requestFile: File('${data.path}/time-request.json'));
  // Each installation has its own bus connection, catalog and history; on first
  // start, the previous data folder becomes the installation "default".
  // In the add-on with an MQTT broker: device "KNX Monitor" (see below).
  MqttBridge? mqtt;
  final installations = InstallationService(
    await Installations.open(data),
    (root, installation) => BusService(
      root,
      notify: _busNotify,
      event: (type, data) async {
        mqtt?.onEvent(type, data);
        await HomeAssistant.instance.fire(type, data);
      },
      clock: clock,
      installation: installation,
      hatDevice: box == null ? null : BusConfig.defaultHatDevice,
      homeAssistant: HomeAssistant.instance.available ? _sendNotification : null,
      restarts: (from, to) async => crash.between(from, to),
      restartSummary: crash.summary,
      readOnly: _readOnly,
    ),
    clock: clock,
  );
  box?.status = () => {
    'clock': clock!.status(),
    'waiting': installations.bus.recorder.waiting,
    'installation': installations.info,
    'restarts': ?crash.summary(),
  };
  await installations.start();
  // In the add-on: is the KNX integration set up? Then the app suggests the
  // mode without its own tunnel (status "haKnx").
  if (HomeAssistant.instance.available) {
    unawaited(HomeAssistant.instance.refreshKnx());
    Timer.periodic(const Duration(minutes: 10), (_) => HomeAssistant.instance.refreshKnx());
  }
  // Device "KNX Monitor" via MQTT: in the add-on with the Supervisor's broker,
  // otherwise (Docker, box) with MQTT_HOST and friends.
  final envBroker = MqttBroker.fromEnvironment(env);
  if (HomeAssistant.instance.available || envBroker != null) {
    mqtt = MqttBridge(
      () => installations.bus,
      version: env['ADDON_VERSION'] ?? 'dev',
      broker: envBroker != null ? () async => envBroker : null,
      discovery: env['MQTT_DISCOVERY'] != 'false',
    );
    unawaited(mqtt.start());
  }
  // Dashboard card "KNX Monitor Diagramm" (can be disabled: option dashboard_card).
  if (HomeAssistant.instance.available && await _flag('dashboard_card')) {
    unawaited(_installCard(env['ADDON_VERSION'] ?? 'dev', Directory(env['CARD_DIR'] ?? '/app/card')));
  }
  final hat = box == null ? null : KberryService();
  // Supervisor stops with SIGTERM: write history, disconnect the tunnel.
  for (final signal in [ProcessSignal.sigterm, ProcessSignal.sigint]) {
    signal.watch().listen((_) async {
      try {
        // With a deadline: if the serial line to the HAT hangs, systemd otherwise kills
        // the process after 20 s, and that counted as an unexpected restart.
        await () async {
          await mqtt?.stop();
          await installations.shutdown();
        }().timeout(const Duration(seconds: 8));
      } on TimeoutException {
        stderr.writeln('Beenden: Aufräumen nach 8 s abgebrochen');
      } finally {
        // Intentional stop, even if something went wrong during cleanup.
        await crash.cleanExit();
      }
      exit(0);
    });
  }

  void accept(HttpServer server) => server.listen(
    (request) => unawaited(
      _handle(request, web: web, installations: installations, allowAll: allowAll, box: box, hat: hat, crash: crash),
    ),
    onError: (Object e) => stderr.writeln('Verbindung: $e'),
  );

  accept(await HttpServer.bind(InternetAddress.anyIPv4, port));
  stdout.writeln('KNX Monitor: Port $port, Web ${web.path}, Daten ${data.path}');
  // Box: HTTPS with its own certificate (see box_tls.dart); HTTP stays for the
  // browser in the box Wi-Fi. Without a certificate or if the port is taken, HTTP only.
  if (box != null) {
    box.onAccessChanged = () {
      unawaited(installations.bus.closeClients());
      for (final ws in _relays.toList()) {
        unawaited(ws.close(WebSocketStatus.policyViolation));
      }
    };
    final tls = await BoxTls.load(env['TLS_CERT'], env['TLS_KEY']);
    if (tls != null) {
      final tlsPort = int.tryParse(env['TLS_PORT'] ?? '') ?? 443;
      try {
        accept(await HttpServer.bindSecure(InternetAddress.anyIPv4, tlsPort, tls.context));
        box.tlsFingerprint = tls.fingerprint;
        box.tlsPort = tlsPort;
        stdout.writeln('KNX Monitor: HTTPS auf Port $tlsPort');
      } on SocketException catch (e) {
        stderr.writeln('HTTPS auf Port $tlsPort nicht möglich: $e');
      }
    }
  }
}

Future<void> _writeSheets(String dir, Map<String, String> env) async {
  final sheet = BoxSheet(
    name: env['BOX_NAME'] ?? 'KNX-Box',
    ssid: env['WLAN_SSID'] ?? '',
    wifiPassword: env['WLAN_PASSWORD'] ?? '',
    boxPassword: env['BOX_PASSWORD'] ?? '',
    link: env['BOX_LINK'] ?? '',
    lanAccess: env['LAN_ACCESS'] == 'yes',
  );
  for (final lang in ['de', 'en']) {
    await File('$dir/knx-box-$lang.pdf').writeAsBytes(await boxSheetPdf(sheet, lang: lang), flush: true);
  }
}

/// Supervisor address that Ingress requests come from.
const _ingressPeer = '172.30.32.2';

Future<void> _handle(
  HttpRequest request, {
  required Directory web,
  required InstallationService installations,
  required bool allowAll,
  BoxAccess? box,
  KberryService? hat,
  CrashWatch? crash,
}) async {
  final response = request.response;
  response.headers
    ..set('X-Content-Type-Options', 'nosniff')
    ..set('Referrer-Policy', 'no-referrer');
  try {
    final peer = request.connectionInfo?.remoteAddress.address;
    // Supervisor watchdog (does not come via Ingress) and the startup check of
    // setup.sh on the box: a response below 300 without login, but without data,
    // so that it reveals nothing on the network either.
    if (request.uri.path == healthPath) return await answerHealth(response);
    // Without the box only Ingress gets through (Home Assistant users): may administer.
    var admin = true;
    if (box != null) {
      final role = await box.guard(request);
      if (role == null || await box.handle(request, role)) return;
      admin = role == BoxRole.admin;
    } else if (!allowAll && peer != _ingressPeer) {
      response.statusCode = HttpStatus.forbidden;
      response.write('Nur über Home Assistant (Ingress) erreichbar.');
      await response.close();
      return;
    }
    final path = request.uri.path;
    final bus = installations.bus;
    if (await serveInstallations(request, installations, admin: admin)) return;
    if (await serveReports(request, bus.report, admin: admin)) return;
    if (await serveExport(request, bus.exporter, admin: admin)) return;
    if (path == '/api/box/time' && bus.clock != null) return await _boxTime(request, bus.clock!, admin: admin);
    if (path == '/ws') return await _relay(request);
    if (path == '/ws/bus') return await bus.serve(await WebSocketTransformer.upgrade(request), admin: admin);
    if (path == '/api/bus') return await _bus(request, bus, admin: admin);
    if (path == '/api/bus/availability' || path == '/api/bus/stats') {
      // `?installation=<id>`: history of another installation (read-only).
      final id = request.uri.queryParameters['installation'] ?? installations.installations.activeId;
      if (installations.installations.byId(id) == null) {
        response.statusCode = HttpStatus.notFound;
        return await response.close();
      }
      if (path == '/api/bus/availability') return await _availability(request, installations.availabilityOf(id));
      final days = (int.tryParse(request.uri.queryParameters['days'] ?? '') ?? 7).clamp(1, 366);
      return await sendJson(response, await installations.recorderOf(id).stats(days));
    }
    if (path == '/api/restarts' && crash != null) return await sendJson(response, crash.recent());
    if (path == '/api/charts') return await sendJson(response, await _charts.list(installations.installations.root));
    if (path == '/api/charts/series') return await _chartSeries(request, installations);
    if (path.startsWith('/api/files/')) {
      return await serveFile(
        request,
        installations.installations.root,
        path.substring('/api/files/'.length),
        admin: admin,
      );
    }
    if (path == '/api/network') return await sendJson(response, {'ip': await _lanAddress()});
    if (path == '/api/discover' && box != null) {
      return await sendJson(response, [
        for (final g in await discoverGateways()) {'host': g.host, 'port': g.port, 'dibs': hexOf(g.dibs)},
      ]);
    }
    if (path == '/api/box/hat' && hat != null) return await _hat(request, hat, bus, admin: admin);
    if (path == '/api/resolve') return await _resolve(request);
    if (path == '/api/notify' && request.method == 'POST') return await _notify(request);
    await _static(request, web);
  } on Object catch (e) {
    stderr.writeln('${request.method} ${request.uri}: $e');
    try {
      response.statusCode = HttpStatus.internalServerError;
      await response.close();
    } on Object {
      // Response already sent.
    }
  }
}

// --- UDP relay -----------------------------------------------------------------

/// One UDP socket per WebSocket. Messages: 4 bytes IPv4, 2 bytes port, payload.
/// Open relays, so that revoked access does not keep them.
final _relays = <WebSocket>{};

/// Read-only, set at startup in [_serve].
var _readOnly = false;

Future<void> _relay(HttpRequest request) async {
  final ws = await WebSocketTransformer.upgrade(request);
  _relays.add(ws);
  unawaited(ws.done.whenComplete(() => _relays.remove(ws)));
  final udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  // Open tunnels (gateway → channel), to disconnect them when the browser closes.
  final tunnels = <(InternetAddress, int), int>{};
  udp.listen((e) {
    if (e != RawSocketEvent.read) return;
    final dg = udp.receive();
    if (dg == null || dg.address.type != InternetAddressType.IPv4) return;
    final p = dg.data;
    if (p.length >= 8 && p[2] == 0x02 && p[3] == 0x06 && p[7] == 0) {
      tunnels[(dg.address, dg.port)] = p[6]; // CONNECT_RESPONSE ok
    } else if (p.length >= 8 && p[2] == 0x02 && (p[3] == 0x09 || p[3] == 0x0A)) {
      tunnels.remove((dg.address, dg.port)); // disconnected by the gateway
    }
    // A packet may still arrive after closing (disconnect below).
    if (ws.readyState == WebSocket.open) {
      ws.add(Uint8List.fromList([...dg.address.rawAddress, dg.port >> 8, dg.port & 0xFF, ...p]));
    }
  }, onError: (Object _) {}); // E.g. "Send failed": without a listener the process would die.
  await ws
      .listen((message) {
        if (message is! List<int> || message.length < 6) return;
        final address = InternetAddress.fromRawAddress(Uint8List.fromList(message.sublist(0, 4)));
        final port = (message[4] << 8) | message[5];
        // Only KNXnet/IP packets (header 06 10) and only into the local network – the relay
        // must not be a UDP stepping stone into the internet.
        if (message.length >= 8 && message[6] == 0x06 && message[7] == 0x10 && _isLocalTarget(address)) {
          if (_readOnly && !relayMaySendReadOnly(message.sublist(6))) return;
          udp.send(message.sublist(6), address, port);
          // The app disconnects itself → nothing left to clean up.
          if (message.length >= 10 && message[8] == 0x02 && message[9] == 0x09) tunnels.remove((address, port));
        }
      })
      .asFuture<void>()
      .catchError((_) {});
  // Tab closed or connection lost: release the tunnel instead of blocking it at the
  // gateway until the heartbeat timeout (up to 2 min).
  for (final MapEntry(key: (address, port), value: channel) in tunnels.entries) {
    udp.send([0x06, 0x10, 0x02, 0x09, 0x00, 0x10, channel, 0x00, 0x08, 0x01, 0, 0, 0, 0, 0, 0], address, port);
  }
  await Future<void>.delayed(const Duration(milliseconds: 100));
  udp.close();
}

/// Targets that can be a KNX gateway: private networks (RFC 1918), CGNAT/VPN
/// (100.64/10, e.g. Tailscale), link-local, loopback, the KNXnet/IP multicast
/// address (search, routing) and broadcast.
bool _isLocalTarget(InternetAddress address) {
  final [a, b, c, d] = address.rawAddress;
  return a == 10 ||
      a == 127 ||
      (a == 172 && b >= 16 && b < 32) ||
      (a == 192 && b == 168) ||
      (a == 100 && b >= 64 && b < 128) ||
      (a == 169 && b == 254) ||
      (a == 224 && b == 0 && c == 23 && d == 12) ||
      (a == 255 && b == 255 && c == 255 && d == 255);
}

// --- Box clock -----------------------------------------------------------------

/// `POST /api/box/time` `{epochMs, force?}`: offers the time of the iPhone/iPad.
/// Response `{result: set|ok|differs|unsupported, clock}`; on `differs` the app
/// asks the user and then sends `force: true`.
///
/// `force` requires admin rights: otherwise any device could change a clock that
/// is already set, and with it the timing of the entire history.
Future<void> _boxTime(HttpRequest request, BoxClock clock, {required bool admin}) async {
  if (request.method == 'GET') return sendJson(request.response, clock.status());
  if (request.method != 'POST') {
    request.response.statusCode = HttpStatus.methodNotAllowed;
    return request.response.close();
  }
  final raw = await readBody(request, 1024);
  final Map<String, Object?> body;
  try {
    body = jsonDecode(utf8.decode(raw ?? const [])) as Map<String, Object?>;
  } on Object {
    request.response.statusCode = HttpStatus.badRequest;
    return request.response.close();
  }
  final ms = body['epochMs'];
  // 2025 to 2100, like settime.sh.
  if (ms is! int || ms < 1735689600000 || ms > 4102444800000) {
    request.response.statusCode = HttpStatus.badRequest;
    return request.response.close();
  }
  final result = await clock.offer(
    DateTime.fromMillisecondsSinceEpoch(ms),
    ClockSource.client,
    force: admin && body['force'] == true,
  );
  return sendJson(request.response, {'result': result, 'clock': clock.status()});
}

/// Checks the KNX HAT (admin only): `GET` returns the system check, the running step
/// and the last report; `POST {seconds}` starts a check in the background.
/// One at a time, and not while the box is connected via the HAT (the line then
/// belongs to the link); `server hat` via SSH bypasses this lock, so do not
/// check from the app at the same time.
Future<void> _hat(HttpRequest request, KberryService hat, BusService bus, {required bool admin}) async {
  final response = request.response;
  if (!admin) {
    response.statusCode = HttpStatus.forbidden;
    return response.close();
  }
  if (request.method == 'GET') return sendJson(response, await hat.status());
  if (request.method != 'POST') {
    response.statusCode = HttpStatus.methodNotAllowed;
    return response.close();
  }
  var seconds = 10;
  try {
    final body = jsonDecode(utf8.decode(await readBody(request, 1024) ?? const [])) as Map<String, Object?>;
    seconds = ((body['seconds'] as num?)?.toInt() ?? 10).clamp(3, 60);
  } on Object {
    // Default: ten seconds per listening step.
  }
  if (bus.config.enabled && bus.config.mode == 'hat') {
    response.statusCode = HttpStatus.conflict;
    return sendJson(response, {...await hat.status(), 'busy': 'link'});
  }
  if (!hat.start(Duration(seconds: seconds))) response.statusCode = HttpStatus.conflict;
  return sendJson(response, await hat.status());
}

// --- Notifications ---------------------------------------------------------------

/// Alarm from the app to Home Assistant (only without continuous mode – otherwise
/// the server reports itself).
Future<void> _notify(HttpRequest request) async {
  final response = request.response;
  final raw = await readBody(request, 16 * 1024);
  if (raw == null) {
    response.statusCode = HttpStatus.requestEntityTooLarge;
    return response.close();
  }
  final body = jsonDecode(utf8.decode(raw)) as Map<String, Object?>;
  final sent = await _sendNotification(
    id: '${body['id'] ?? 'knx_alarm'}',
    title: '${body['title'] ?? 'KNX'}',
    message: '${body['message'] ?? ''}',
  );
  // Outside of Home Assistant there is no Supervisor.
  response.statusCode = sent ? HttpStatus.noContent : HttpStatus.serviceUnavailable;
  await response.close();
}

/// Notification from alarms and watchers, unless disabled in the add-on options.
/// The events for automations are sent regardless.
Future<void> _busNotify({required String id, required String title, required String message}) async {
  final key = id.startsWith('knx_watch_') ? 'watcher_notifications' : 'alarm_notifications';
  if (!await _flag(key)) return;
  await _sendNotification(id: id, title: title, message: message);
}

/// Persistent notification in Home Assistant and – if `notify_service` is set
/// in the add-on options (e.g. "notify.mobile_app_iphone") – additionally as
/// a push message.
Future<bool> _sendNotification({required String id, required String title, required String message}) async {
  final token = Platform.environment['SUPERVISOR_TOKEN'];
  if (token == null) return false;
  Future<void> call(String domainService, Map<String, Object?> data) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse('http://supervisor/core/api/services/$domainService'));
      req.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..contentType = ContentType.json;
      req.write(jsonEncode(data));
      final res = await req.close();
      await res.drain<void>();
      if (res.statusCode >= 300) stderr.writeln('Mitteilung $domainService: HTTP ${res.statusCode}');
    } finally {
      client.close();
    }
  }

  await call('persistent_notification/create', {'title': title, 'message': message, 'notification_id': id});
  final service = await _option('notify_service');
  // Only "notify.<name>" – the value ends up in the path of the Supervisor URL.
  if (service != null && RegExp(r'^notify\.[a-z0-9_]+$').hasMatch(service)) {
    await call('notify/${service.substring('notify.'.length)}', {'title': title, 'message': message});
  }
  return true;
}

// --- Dashboard card ---------------------------------------------------------------

/// Saved charts for the card in Home Assistant (values from the history).
final _charts = ChartService();

/// `?name=<chart>&hours=<period>`: history of a saved chart.
Future<void> _chartSeries(HttpRequest request, InstallationService installations) async {
  final q = request.uri.queryParameters;
  final result = await _charts.series(
    installations.installations.root,
    installations.bus.recorder,
    q['name'] ?? '',
    hours: int.tryParse(q['hours'] ?? '') ?? 24,
  );
  if (result == null) {
    request.response.statusCode = HttpStatus.notFound;
    return request.response.close();
  }
  return sendJson(request.response, result);
}

/// Places the card in Home Assistant and registers it; if `www` did not exist yet,
/// Home Assistant needs a restart – a notification says so.
Future<void> _installCard(String version, Directory dir) async {
  final card = LovelaceCard(template: File('${dir.path}/${LovelaceCard.fileName}'));
  final result = await card.install(version: version);
  stdout.writeln('Dashboard-Karte: ${result.message}');
  if (result.freshWww) {
    await _sendNotification(
      id: 'knx_monitor_card',
      title: 'KNX Monitor',
      message:
          'Die Dashboard-Karte „KNX Monitor Diagramm“ ist eingerichtet. Starte Home Assistant einmal neu, '
          'damit sie geladen wird.\n\nThe dashboard card “KNX Monitor chart” is installed. Restart Home '
          'Assistant once to load it.',
    );
  }
}

// --- Continuous recording ------------------------------------------------------------

/// GET: status and settings; PUT: change settings (JSON, only the changed
/// fields).
///
/// Changes require [admin]: gateway, mode and credentials determine where the
/// box connects to. Unchanged settings pass (see [BusService.wouldChange]).
Future<void> _bus(HttpRequest request, BusService bus, {required bool admin}) async {
  final response = request.response;
  if (request.method == 'PUT' || request.method == 'POST') {
    final raw = await readBody(request, 64 * 1024);
    if (raw == null) {
      response.statusCode = HttpStatus.requestEntityTooLarge;
      return response.close();
    }
    final Object? body;
    try {
      body = jsonDecode(utf8.decode(raw));
    } on FormatException {
      response.statusCode = HttpStatus.badRequest;
      return response.close();
    }
    if (body is! Map<String, Object?>) {
      response.statusCode = HttpStatus.badRequest;
      return response.close();
    }
    // Credentials do not count here: a comparison would reveal whether a guessed password is right.
    if (!admin && bus.wouldChange({...body}..remove('secure'))) {
      response
        ..statusCode = HttpStatus.forbidden
        ..headers.contentType = ContentType.text
        ..write('Nur mit dem Box-Passwort.');
      return response.close();
    }
    try {
      if (admin) await bus.update(body);
    } on BusProbeException catch (e) {
      // The new connection could not be established; the previous one remains.
      response.statusCode = HttpStatus.unprocessableEntity;
      return sendJson(response, {'error': e.message, 'problem': ?e.problem});
    }
  }
  return sendJson(response, {...bus.status(), 'storage': await bus.recorder.usage()});
}

/// Recording outages in the period `from`–`to` (milliseconds).
Future<void> _availability(HttpRequest request, Availability availability) async {
  final q = request.uri.queryParameters;
  final now = DateTime.now();
  final from = DateTime.fromMillisecondsSinceEpoch(
    int.tryParse(q['from'] ?? '') ?? now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
  );
  final to = DateTime.fromMillisecondsSinceEpoch(int.tryParse(q['to'] ?? '') ?? now.millisecondsSinceEpoch);
  return sendJson(request.response, await availability.outages(from, to));
}

/// Value from the add-on options (/data/options.json).
/// Switch from the add-on options; if it is missing (older options), it counts as on.
Future<bool> _flag(String key) async {
  try {
    final options = jsonDecode(await File('/data/options.json').readAsString()) as Map<String, Object?>;
    return options[key] != false;
  } on Object {
    return true;
  }
}

Future<String?> _option(String key) async {
  try {
    final options = jsonDecode(await File('/data/options.json').readAsString()) as Map<String, Object?>;
    final value = options[key];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  } on Object {
    return null;
  }
}

// --- Network ------------------------------------------------------------------

/// LAN address of the host for the gateway search (skips Docker and HA internal networks).
Future<String?> _lanAddress() async {
  final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
  final candidates = [
    for (final i in interfaces)
      if (!RegExp(r'^(docker|hassio|veth|br-|lo)').hasMatch(i.name))
        for (final a in i.addresses)
          if (!a.isLoopback && !a.isLinkLocal && !a.address.startsWith('172.30.')) a.address,
  ];
  // Prefer typical home networks.
  candidates.sort((a, b) => (a.startsWith('192.168.') ? 0 : 1).compareTo(b.startsWith('192.168.') ? 0 : 1));
  return candidates.firstOrNull;
}

Future<void> _resolve(HttpRequest request) async {
  final response = request.response;
  try {
    final host = request.uri.queryParameters['host'] ?? '';
    final ip = (await InternetAddress.lookup(host, type: InternetAddressType.IPv4)).first.address;
    response.write(ip);
  } on SocketException {
    response.statusCode = HttpStatus.notFound;
  }
  await response.close();
}

// --- Web app -------------------------------------------------------------------

const _types = {
  'html': 'text/html; charset=utf-8',
  'js': 'text/javascript',
  'mjs': 'text/javascript',
  'json': 'application/json',
  'wasm': 'application/wasm',
  'css': 'text/css',
  'png': 'image/png',
  'ico': 'image/x-icon',
  'svg': 'image/svg+xml',
  'otf': 'font/otf',
  'ttf': 'font/ttf',
  'bin': 'application/octet-stream',
  'frag': 'application/octet-stream',
};

Future<void> _static(HttpRequest request, Directory web) async {
  final response = request.response;
  var relative = request.uri.path == '/' ? 'index.html' : request.uri.path.substring(1);
  if (relative.split('/').contains('..')) relative = 'index.html';
  var file = File('${web.path}/$relative');
  if (!await file.exists()) file = File('${web.path}/index.html');
  final extension = file.path.split('.').last;
  response.headers.set(HttpHeaders.contentTypeHeader, _types[extension] ?? 'application/octet-stream');
  if (file.path.endsWith('index.html')) {
    // Ingress path as <base href>, so that all relative URLs end up under Ingress.
    // The header comes from the Supervisor; still, only accept path characters, since
    // it is written unescaped into the HTML.
    final header = request.headers.value('X-Ingress-Path') ?? '';
    final ingress = RegExp(r'^[A-Za-z0-9/_-]*$').hasMatch(header) ? header : '';
    final html = (await file.readAsString()).replaceFirst('<base href="/">', '<base href="$ingress/">');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    response.write(html);
  } else {
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    await response.addStream(file.openRead());
  }
  await response.close();
}
