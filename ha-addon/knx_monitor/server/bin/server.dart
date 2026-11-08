import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:knx_monitor_server/box.dart';
import 'package:knx_monitor_server/bus.dart';
import 'package:knx_monitor_server/files.dart';

/// Server of the Home Assistant add-on "Busclear".
///
/// - serves the Flutter web app (via HA Ingress in the sidebar),
/// - relays KNXnet/IP between the WebSocket "/ws" and UDP (browsers cannot do UDP),
/// - stores catalog, recordings and history under "/api/files/…" in the folder
///   of the active installation (`installations/<id>/`, "/api/installations"),
/// - in continuous mode, keeps its own bus connection, records, and distributes
///   the frames to all open views ("/ws/bus", "/api/bus").
///
/// Environment: PORT (8765), WEB_DIR (/app/web), DATA_DIR (/data/app),
/// ALLOW_ALL=1 allows access outside of Ingress (development only; listens on
/// 127.0.0.1, a network BIND only together with ALLOW_ALL_EXPOSED=1, as the CI's
/// throwaway container behind -p, see refuseToStart).
/// BOX_PASSWORD_FILE and MQTT_PASSWORD_FILE: the password from a file (Docker
/// secrets) instead of the environment.
/// BOX=1: KNX box without Home Assistant – access with the box password or
/// device access instead of Ingress (BOX_PASSWORD for the first password, BOX_NAME;
/// LAN_ACCESS=yes allows access over the cable, otherwise only from the box
/// Wi-Fi, or in Docker only from the host itself). BOX=1 without BOX_STICKER=1
/// (which only the real box sets, knx-box.service) is the Docker container:
/// LAN_ACCESS then applies on every start, and texts speak of the network
/// instead of cable and box Wi-Fi.
/// MQTT_HOST (+ MQTT_PORT, MQTT_USER, MQTT_PASSWORD, MQTT_SSL): MQTT device
/// without Supervisor, e.g. in a Docker container next to ioBroker.
/// MQTT_TELEGRAMS=true: every telegram as JSON to knx_monitor/telegram/…
/// (in the add-on: option mqtt_telegrams); MQTT_REPEATS=true includes repeats,
/// MQTT_SECURE_TELEGRAMS=true decrypted KNX Data Secure telegrams (option
/// mqtt_secure_telegrams).
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
  final Map<String, String> env;
  try {
    env = withSecretFiles(Platform.environment);
  } on ContainerEnvException catch (e) {
    stderr.writeln('Busclear: $e');
    exit(78); // EX_CONFIG
  }
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
  // Docker (box mode without the real box's sticker): the data folder is a
  // bind mount on the host, keys must not be readable there for everyone.
  // The real box (systemd StateDirectory) and the add-on set their own modes.
  if (env['BOX'] == '1' && env['BOX_STICKER'] != '1') restrictDataFolder(data);
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
  // Ingress requests come from the Supervisor's proxy; only inside Home
  // Assistant (with SUPERVISOR_TOKEN) is that address really the proxy. In a
  // Docker network it could be any container.
  _inHomeAssistant = (env['SUPERVISOR_TOKEN'] ?? '').isNotEmpty;
  if (env['BOX'] != '1' && !allowAll && !_inHomeAssistant) {
    stderr.writeln(
      'Busclear: weder Home Assistant (SUPERVISOR_TOKEN) noch BOX=1 noch ALLOW_ALL=1 – '
      'der Server lehnt alle Anfragen ab. Für Docker BOX=1 und BOX_PASSWORD setzen.',
    );
  }
  // Read-only (read_only.dart): in the add-on the option `read_only`, on by default;
  // Docker, Linux and box with READ_ONLY=1, off by default.
  _readOnly = HomeAssistant.instance.available ? await _flag('read_only') : env['READ_ONLY'] == '1';
  if (_readOnly) stdout.writeln('Busclear: Nur-Lesen, es geht nichts auf den Bus');
  // Docker without BOX_PASSWORD: the server would invent a password and could
  // only tell it through the log, which other tools collect. Refuse instead,
  // also a password that is too short (only on the very first start; later
  // the stored password counts). And ALLOW_ALL open to the network, see
  // refuseToStart.
  final sticker = env['BOX_STICKER'] == '1';
  final stored = await File('${data.path}/access.json').exists() || await File('${data.path}/access.json.bak').exists();
  final refusal = refuseToStart(env, firstStart: !stored);
  if (refusal != null) {
    stderr.writeln('Busclear: $refusal');
    exit(78); // EX_CONFIG
  }
  if (allowAll && env['BOX'] != '1') {
    stderr.writeln('Busclear: ALLOW_ALL=1 – keine Anmeldung, jeder Zugriff darf auf den Bus. Nur für Tests.');
  }
  // Standalone without the real box (Docker): see the doc comment of main.
  final docker = env['BOX'] == '1' && !sticker;
  final box = env['BOX'] == '1'
      ? await BoxAccess.open(
          data,
          initialPassword: env['BOX_PASSWORD'],
          name: env['BOX_NAME'],
          initialLanAccess: env['LAN_ACCESS'] == 'yes',
          sticker: env['BOX_STICKER'] == '1',
          container: docker,
          // Only the real box has its own Wi-Fi (10.42.0.0/24). In Docker,
          // "no LAN access" means the host itself: 10.42.x can be a home
          // network or a k3s pod network there.
          fromWlan: env['BOX_STICKER'] == '1' ? BoxAccess.wlanPeer : (peer) => peer.isLoopback,
        )
      : null;
  // The variable only counts on the first start; changing it later would
  // look like a new password while the old one stays valid.
  if (box != null && docker && stored && (env['BOX_PASSWORD'] ?? '').isNotEmpty) {
    unawaited(
      box.verifyPassword(env['BOX_PASSWORD']!).then((same) {
        if (!same) {
          stderr.writeln(
            'Busclear: BOX_PASSWORD weicht vom gespeicherten Passwort ab und wird ignoriert. '
            'Das Passwort in der App oder unter /pair ändern.',
          );
        }
      }),
    );
  }
  if (box != null && docker) {
    stdout.writeln(
      box.lanAccess
          ? 'Busclear: aus dem Netzwerk erreichbar (LAN_ACCESS=yes), mit Passwort'
          : 'Busclear: nur am Rechner selbst erreichbar (http://localhost:$port). '
                'Für andere Geräte im Netzwerk LAN_ACCESS=yes setzen.',
    );
  }

  // Box: set the clock without internet (iPhone, KNX time sender); the request is
  // carried out on the host by knx-box-time.path (DATA_DIR is /var/lib/knx-box there).
  // In Docker the host keeps the time (NTP); there is nobody to carry out a
  // request, and a clock the app may set would let any paired device move the
  // history's time stamps and with them the retention (deleting everything).
  final clock = box == null || docker ? null : BoxClock(requestFile: File('${data.path}/time-request.json'));
  // Each installation has its own bus connection, catalog and history; on first
  // start, the previous data folder becomes the installation "default".
  // In the add-on with an MQTT broker: device "Busclear" (see below).
  MqttBridge? mqtt;
  // Access for the Busclear integration (created below).
  HaIntegration? ha;
  final installations = InstallationService(
    await Installations.open(data),
    (root, installation) {
      late final BusService bus;
      return bus = BusService(
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
        mqttTelegrams: () => mqtt?.telegramStatus(),
        telegram: (line, {required secure, required decrypted}) {
          ha?.cycles.observe(bus, line);
          mqtt?.onTelegram(line, bus.exporter.source, secure: secure, decrypted: decrypted);
        },
      );
    },
    clock: clock,
    // The restart entry of this start carries the wrong clock of the boot.
    onClockSet: (time, _) => unawaited(crash.retime(time)),
  );
  final health = box == null ? null : (BoxHealth()..start());
  box?.status = () => {
    'clock': ?clock?.status(),
    'health': ?health?.status(),
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
  // Access for the Busclear integration (ha_integration.dart). While it is
  // set up, it provides the entities instead of the MQTT device. In the add-on
  // with the token from the Supervisor's discovery; on the box and in Docker
  // (Home Assistant Container) with a paired admin device instead (see _handle).
  final mqttDiscovery = env['MQTT_DISCOVERY'] != 'false';
  ha = HomeAssistant.instance.available || box != null
      ? HaIntegration(
          data,
          () => installations.bus,
          version: env['ADDON_VERSION'] ?? BusService.version ?? 'dev',
          port: port,
          tokenAccess: HomeAssistant.instance.available,
          onClaim: (claimed) => mqtt?.setDiscovery(mqttDiscovery && !claimed),
        )
      : null;
  await ha?.start();
  // Device "Busclear" via MQTT: in the add-on with the Supervisor's broker,
  // otherwise (Docker, box) with MQTT_HOST and friends.
  final envBroker = MqttBroker.fromEnvironment(env);
  if (HomeAssistant.instance.available || envBroker != null) {
    // Every telegram to knx_monitor/telegram/… (issue #11): add-on option
    // mqtt_telegrams, Docker and box MQTT_TELEGRAMS=true. Off by default.
    final telegrams =
        env['MQTT_TELEGRAMS'] == 'true' || (HomeAssistant.instance.available && await _on('mqtt_telegrams'));
    Future<bool> option(String name, String key) async =>
        env[name] == 'true' || (HomeAssistant.instance.available && await _on(key));
    // Raw data (cEMI frame, priority, dedup key) and "raw only" without ETS data.
    final rawOnly = telegrams && await option('MQTT_RAW_ONLY', 'mqtt_raw_only');
    final raw = rawOnly || (telegrams && await option('MQTT_RAW', 'mqtt_raw'));
    // Only these group addresses, e.g. "1/#,3/2/#,4/1/7"; empty = all.
    final filter = GroupFilter.parse(
      env['MQTT_FILTER'] ?? (HomeAssistant.instance.available ? await _option('mqtt_filter') : null),
    );
    if (telegrams && filter.invalid.isNotEmpty) {
      stderr.writeln(
        'MQTT-Filter: nicht lesbar und ignoriert: ${filter.invalid.join(', ')} (Beispiel: 1/#,3/2/#,4/1/7)',
      );
    }
    final installationId =
        (env['MQTT_INSTALLATION'] ?? (HomeAssistant.instance.available ? await _option('mqtt_installation') : null))
            ?.trim();
    mqtt = MqttBridge(
      () => installations.bus,
      version: env['ADDON_VERSION'] ?? 'dev',
      broker: envBroker != null ? () async => envBroker : null,
      discovery: mqttDiscovery && !(ha?.claimed ?? false),
      telegrams: telegrams
          ? TelegramStream(
              repeats: env['MQTT_REPEATS'] == 'true',
              // KNX Data Secure telegrams only on request: the broker gets them in plain text.
              secure:
                  env['MQTT_SECURE_TELEGRAMS'] == 'true' ||
                  (HomeAssistant.instance.available && await _on('mqtt_secure_telegrams')),
              raw: raw,
              rawOnly: rawOnly,
              filter: filter,
            )
          : null,
      installation: installationId == null || installationId.isEmpty ? null : installationId,
    );
    if (telegrams) {
      stdout.writeln(
        'MQTT: jedes Telegramm an knx_monitor/telegram/…'
        '${rawOnly
            ? ', nur Rohdaten'
            : raw
            ? ', mit Rohdaten'
            : ''}'
        '${filter.isAll ? '' : ', nur ${filter.text}'}',
      );
    }
    unawaited(mqtt.start());
  }
  // Dashboard card "Busclear Diagramm" (can be disabled: option dashboard_card).
  if (HomeAssistant.instance.available && await _flag('dashboard_card')) {
    unawaited(_installCard(env['ADDON_VERSION'] ?? 'dev', Directory(env['CARD_DIR'] ?? '/app/card')));
  }
  final hat = box == null ? null : KberryService();
  final discovery = box == null ? null : _Discovery();
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
      _handle(
        request,
        web: web,
        installations: installations,
        allowAll: allowAll,
        box: box,
        hat: hat,
        crash: crash,
        ha: ha,
        discovery: discovery,
      ),
    ),
    onError: (Object e) => stderr.writeln('Verbindung: $e'),
  );

  // ALLOW_ALL turns off every access check, so only this machine may connect,
  // unless BIND names an address (refuseToStart: only with ALLOW_ALL_EXPOSED).
  // Docker without LAN access listens on loopback only, so the port is not
  // even open on the network (the access check stays as the second layer).
  final bind = env['BIND'] != null
      ? InternetAddress(env['BIND']!)
      : allowAll || (box != null && box.container && !box.lanAccess)
      ? InternetAddress.loopbackIPv4
      : InternetAddress.anyIPv4;
  // On loopback a web page could still reach the open server through DNS
  // rebinding (its own name resolving to 127.0.0.1): only local host names.
  // With another BIND the developer chose to expose it.
  _localHostOnly = allowAll && bind.isLoopback;
  accept(await HttpServer.bind(bind, port));
  stdout.writeln('Busclear: Port $port, Web ${web.path}, Daten ${data.path}');
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
      // Docker drops all capabilities: no port below 1024.
      final tlsPort = int.tryParse(env['TLS_PORT'] ?? '') ?? (box.container ? 8443 : 443);
      try {
        accept(await HttpServer.bindSecure(bind, tlsPort, tls.context));
        box.tlsFingerprint = tls.fingerprint;
        box.tlsPort = tlsPort;
        stdout.writeln('Busclear: HTTPS auf Port $tlsPort');
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

/// Running inside Home Assistant (set in [_serve]); only then is
/// [_ingressPeer] the Ingress proxy.
var _inHomeAssistant = false;

/// `ALLOW_ALL=1` on loopback: only requests to a local host name (set in [_serve]).
var _localHostOnly = false;

const _methods = {'GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE'};

Future<void> _handle(
  HttpRequest request, {
  required Directory web,
  required InstallationService installations,
  required bool allowAll,
  BoxAccess? box,
  KberryService? hat,
  CrashWatch? crash,
  HaIntegration? ha,
  _Discovery? discovery,
}) async {
  final response = request.response;
  response.headers
    ..set('X-Content-Type-Options', 'nosniff')
    ..set('Referrer-Policy', 'no-referrer');
  // The box is opened directly in the browser (in Home Assistant, Ingress
  // shows it in a frame): no foreign page may frame it (clickjacking).
  if (box != null) {
    response.headers
      ..set('X-Frame-Options', 'DENY')
      ..set('Content-Security-Policy', "frame-ancestors 'none'");
  }
  try {
    final peer = request.connectionInfo?.remoteAddress.address;
    // Supervisor watchdog (does not come via Ingress) and the startup check of
    // setup.sh on the box: a response below 300 without login, but without data,
    // so that it reveals nothing on the network either.
    if (request.uri.path == healthPath) return await answerHealth(response);
    if (_localHostOnly && !BoxAccess.localHostName(request.headers.value(HttpHeaders.hostHeader))) {
      response
        ..statusCode = HttpStatus.forbidden
        ..write('Nur über localhost erreichbar.');
      return await response.close();
    }
    // Only the methods the API uses; TRACE, CONNECT, PROPFIND and the like
    // used to reach the GET handlers.
    if (!_methods.contains(request.method)) {
      response
        ..statusCode = HttpStatus.methodNotAllowed
        ..headers.set(HttpHeaders.allowHeader, _methods.join(', '));
      return await response.close();
    }
    // The Busclear integration with its token: only the endpoints below /api/ha/.
    if (ha != null && HaIntegration.handles(request.uri.path) && ha.authorized(request)) {
      await ha.serve(request);
      return;
    }
    // Without the box only Ingress gets through (Home Assistant users): may administer.
    var admin = true;
    var maySend = true;
    String? owner;
    if (box != null) {
      final role = await box.guard(request);
      if (role == null || await box.handle(request, role)) return;
      admin = role == BoxRole.admin;
      maySend = role.maySend;
      // The integration without Supervisor: only a paired device with admin
      // rights (bearer token), not the password or a browser session, and
      // never a device without admin rights.
      if (HaIntegration.handles(request.uri.path)) {
        if (!admin || box.deviceIdOf(request) == null) {
          response
            ..statusCode = HttpStatus.forbidden
            ..write('Nur mit einem gekoppelten Gerät mit Admin-Recht.');
          return await response.close();
        }
        ha?.touch();
      }
      // What a device without admin rights stores is marked with its id.
      if (!admin) owner = box.deviceIdOf(request);
    } else if (!allowAll && (!_inHomeAssistant || peer != _ingressPeer)) {
      response.statusCode = HttpStatus.forbidden;
      response.write('Nur über Home Assistant (Ingress) erreichbar.');
      await response.close();
      return;
    }
    final path = request.uri.path;
    final bus = installations.bus;
    if (ha != null && await ha.serve(request)) return;
    if (await serveInstallations(request, installations, admin: admin)) return;
    if (await serveReports(request, bus.report, admin: admin)) return;
    // Read access like the history below, therefore before the export settings (admin).
    if (path != etsXmlPath && await serveExport(request, bus.exporter, admin: admin)) return;
    if (path == '/api/box/time' && bus.clock != null) {
      return await _boxTime(request, bus.clock!, admin: admin, maySend: maySend);
    }
    if (path == '/ws') return await _relay(request);
    if (path == '/ws/bus') {
      if (!bus.acceptsClient) {
        response
          ..statusCode = HttpStatus.serviceUnavailable
          ..headers.set(HttpHeaders.retryAfterHeader, '10');
        return await response.close();
      }
      return await bus.serve(
        await WebSocketTransformer.upgrade(request, compression: webSocketCompression)
          ..pingInterval = webSocketPing,
        admin: admin,
        maySend: maySend,
      );
    }
    if (path == '/api/bus') return await _bus(request, bus, admin: admin, maySend: maySend);
    if (path == '/api/bus/availability' ||
        path == '/api/bus/stats' ||
        path == etsXmlPath ||
        path == historyTelegramsPath) {
      // `?installation=<id>`: history of another installation (read-only).
      // Without admin rights only the active one: a paired device must not
      // read the customers and sites the box recorded before.
      final id = request.uri.queryParameters['installation'] ?? installations.installations.activeId;
      if (!admin && id != installations.installations.activeId) {
        response
          ..statusCode = HttpStatus.forbidden
          ..write('Nur die aktive Installation.');
        return await response.close();
      }
      if (installations.installations.byId(id) == null) {
        response.statusCode = HttpStatus.notFound;
        return await response.close();
      }
      if (path == etsXmlPath) return await serveEtsXml(request, installations.recorderOf(id));
      if (path == historyTelegramsPath) return await serveHistoryTelegrams(request, installations.recorderOf(id));
      if (path == '/api/bus/availability') return await _availability(request, installations.availabilityOf(id));
      final days = (int.tryParse(request.uri.queryParameters['days'] ?? '') ?? 7).clamp(1, 366);
      return await sendJson(response, await installations.recorderOf(id).stats(days));
    }
    if (path == '/api/restarts' && crash != null) return await sendJson(response, crash.recent(withError: admin));
    if (path == '/api/charts') return await sendJson(response, await _charts.list(installations.installations.root));
    if (path == '/api/charts/series') return await _chartSeries(request, installations);
    if (path.startsWith('/api/files/')) {
      return await serveFile(
        request,
        installations.installations.root,
        path.substring('/api/files/'.length),
        admin: admin,
        viewOnly: !maySend,
        owner: owner,
      );
    }
    // Only the admin sets up the connection: for others no map of the
    // networks (gateway search, own address, name lookup).
    if (path == '/api/network') return await sendJson(response, {'ip': admin ? await _lanAddress() : null});
    if (path == '/api/discover' && discovery != null) {
      return await sendJson(response, admin ? await discovery.run() : const <Object?>[]);
    }
    if (path == '/api/box/hat' && hat != null) return await _hat(request, hat, bus, admin: admin);
    if (path == '/api/resolve') {
      if (!admin) {
        response.statusCode = HttpStatus.forbidden;
        return await response.close();
      }
      return await _resolve(request);
    }
    if (path == '/api/notify' && request.method == 'POST') return await _notify(request);
    await _static(request, web);
  } on BodyBudgetException {
    try {
      await answerBusy(response);
    } on Object {
      // Response already sent.
    }
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

/// Each relay holds a UDP socket; a gateway has only a few tunnels anyway.
const _maxRelays = 16;

Future<void> _relay(HttpRequest request) async {
  if (_relays.length >= _maxRelays) {
    request.response
      ..statusCode = HttpStatus.serviceUnavailable
      ..headers.set(HttpHeaders.retryAfterHeader, '10');
    await request.response.close();
    return;
  }
  final ws = await WebSocketTransformer.upgrade(request, compression: webSocketCompression)
    // A browser that stopped reading would let packets pile up in memory.
    ..pingInterval = webSocketPing;
  _relays.add(ws);
  unawaited(ws.done.whenComplete(() => _relays.remove(ws)));
  final udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  // Open tunnels (gateway → channel), to disconnect them when the browser closes.
  final tunnels = <(InternetAddress, int), int>{};
  // Addresses this relay sent to: only they may answer (any port, a gateway's
  // data endpoint may differ from its control endpoint). Other hosts on the
  // network cannot inject packets into the admin's browser.
  final peers = <InternetAddress>{};
  udp.listen((e) {
    if (e != RawSocketEvent.read) return;
    final dg = udp.receive();
    if (dg == null || dg.address.type != InternetAddressType.IPv4) return;
    final p = dg.data;
    if (!relayPacketWellFormed(p) || !(peers.contains(dg.address) || relaySearchResponse(p))) return;
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
        // A packet is at most a few hundred bytes (see BusService.maxClientMessage).
        if (BusService.tooLarge(message)) {
          unawaited(ws.close(WebSocketStatus.messageTooBig, 'too big'));
          return;
        }
        if (message is! List<int> || message.length < 6) return;
        final address = InternetAddress.fromRawAddress(Uint8List.fromList(message.sublist(0, 4)));
        final port = (message[4] << 8) | message[5];
        // Only complete KNXnet/IP packets and only to where a gateway can be
        // (relay_policy.dart): the relay must be neither a UDP stepping stone into
        // the internet nor a UDP proxy to other services in the home network.
        final packet = message.sublist(6);
        if (relayPacketWellFormed(packet) && relayTargetAllowed(address, port)) {
          if (_readOnly && !relayMaySendReadOnly(packet)) return;
          if (peers.length < 64) peers.add(address);
          udp.send(packet, address, port);
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

// --- Box clock -----------------------------------------------------------------

/// `POST /api/box/time` `{epochMs, force?}`: offers the time of the iPhone/iPad.
/// Response `{result: set|ok|differs|unsupported, clock}`; on `differs` the app
/// asks the user and then sends `force: true`.
///
/// `force` requires admin rights: otherwise any device could change a clock that
/// is already set, and with it the timing of the entire history.
Future<void> _boxTime(HttpRequest request, BoxClock clock, {required bool admin, required bool maySend}) async {
  if (request.method == 'GET') return sendJson(request.response, clock.status());
  // A viewer changes nothing, the clock neither.
  if (request.method == 'POST' && !maySend) {
    request.response.statusCode = HttpStatus.forbidden;
    return request.response.close();
  }
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

  // A notification without a way to the details left the user guessing: link to the add-on.
  final panel = await _panelPath(token);
  await call('persistent_notification/create', {
    'title': title,
    'message': panel == null ? message : '$message\n\n[Busclear →]($panel)',
    'notification_id': id,
  });
  final service = await _option('notify_service');
  // Only "notify.<name>" – the value ends up in the path of the Supervisor URL.
  if (service != null && RegExp(r'^notify\.[a-z0-9_]+$').hasMatch(service)) {
    await call('notify/${service.substring('notify.'.length)}', {
      'title': title,
      'message': message,
      // Tapping the push opens the add-on (iOS: url, Android: clickAction).
      if (panel != null) 'data': {'url': panel, 'clickAction': panel},
    });
  }
  return true;
}

/// Path of the add-on's page in the Home Assistant frontend
/// (`/hassio/ingress/<slug>`), asked once from the Supervisor; `null` if it
/// cannot be determined.
Future<String?>? _panel;

Future<String?> _panelPath(String token) => _panel ??= () async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(Uri.parse('http://supervisor/addons/self/info'));
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final res = await req.close();
    final json = jsonDecode(await utf8.decodeStream(res)) as Map<String, Object?>;
    return panelPathOf(json);
  } on Object catch (e) {
    stderr.writeln('Add-on-Seite für Mitteilungen: $e');
    _panel = null;
    return null;
  } finally {
    client.close();
  }
}();

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
      title: 'Busclear',
      message:
          'Die Dashboard-Karte „Busclear Diagramm“ ist eingerichtet. Starte Home Assistant einmal neu, '
          'damit sie geladen wird.\n\nThe dashboard card “Busclear chart” is installed. Restart Home '
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
Future<void> _bus(HttpRequest request, BusService bus, {required bool admin, bool maySend = true}) async {
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
    if (BusConfig.invalidChange(body) case final error?) {
      response
        ..statusCode = HttpStatus.badRequest
        ..headers.contentType = ContentType.text
        ..write(error);
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
  return sendJson(response, {
    ...bus.status(),
    // A viewer sees read-only as on, like over the WebSocket.
    if (!maySend) ...{'readOnly': true, 'viewOnly': true},
    'storage': await bus.recorder.usage(),
  });
}

/// Recording outages in the period `from`–`to` (milliseconds), at most
/// [availabilityMaxRange]; without them the last day.
Future<void> _availability(HttpRequest request, Availability availability) async {
  final range = availabilityRange(request.uri.queryParameters, DateTime.now());
  if (range case (error: final String error, from: _, to: _)) {
    request.response
      ..statusCode = HttpStatus.badRequest
      ..headers.contentType = ContentType.text
      ..write(error);
    return request.response.close();
  }
  return sendJson(request.response, await availability.outages(range.from!, range.to!));
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

/// Add-on option that is off unless set to `true` (unlike [_flag]).
Future<bool> _on(String key) async {
  try {
    final options = jsonDecode(await File('/data/options.json').readAsString()) as Map<String, Object?>;
    return options[key] == true;
  } on Object {
    return false;
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

/// Gateway search of the box (`/api/discover`, any role): it sends to every
/// address of every network, so only one runs at a time and its result is
/// reused for a few seconds.
class _Discovery {
  static const _fresh = Duration(seconds: 10);
  Future<List<Map<String, Object?>>>? _running;
  ({DateTime at, List<Map<String, Object?>> result})? _last;

  Future<List<Map<String, Object?>>> run() async {
    final last = _last;
    if (last != null && DateTime.now().difference(last.at) < _fresh) return last.result;
    return _running ??= () async {
      try {
        final result = [
          for (final g in await discoverGateways()) {'host': g.host, 'port': g.port, 'dibs': hexOf(g.dibs)},
        ];
        _last = (at: DateTime.now(), result: result);
        return result;
      } finally {
        _running = null;
      }
    }();
  }
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

/// Compressible assets, gzipped once per file version (main.dart.js: several
/// MB, about a third packed). Kept in memory: the web folder is small and only
/// changes with an update.
const _compressible = {'js', 'mjs', 'json', 'css', 'svg', 'wasm', 'otf', 'ttf', 'frag', 'bin'};
final _gzipCache = <String, ({String tag, List<int> bytes})>{};

Future<void> _static(HttpRequest request, Directory web) async {
  final response = request.response;
  // An API path that no handler took does not exist: 404 instead of the web
  // app with 200, which looked like success to clients and scanners.
  if (request.uri.path.startsWith('/api/') || request.uri.path.startsWith('/ws')) {
    response.statusCode = HttpStatus.notFound;
    return response.close();
  }
  var relative = request.uri.path == '/' ? 'index.html' : request.uri.path.substring(1);
  if (relative.split('/').contains('..')) relative = 'index.html';
  var file = File('${web.path}/$relative');
  if (!await file.exists()) file = File('${web.path}/index.html');
  final extension = file.path.split('.').last;
  response.headers.set(HttpHeaders.contentTypeHeader, _types[extension] ?? 'application/octet-stream');
  response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
  if (file.path.endsWith('index.html')) {
    // Ingress path as <base href>, so that all relative URLs end up under Ingress.
    // The header comes from the Supervisor; still, only accept path characters, since
    // it is written unescaped into the HTML.
    // Only from the Ingress proxy itself, and only "/segment/segment": "//host"
    // would load every script from another host.
    final header = _inHomeAssistant && request.connectionInfo?.remoteAddress.address == _ingressPeer
        ? request.headers.value('X-Ingress-Path') ?? ''
        : '';
    final ingress = RegExp(r'^(/[A-Za-z0-9_-]+)*$').hasMatch(header) ? header : '';
    final html = (await file.readAsString()).replaceFirst('<base href="/">', '<base href="$ingress/">');
    response.write(html);
    return response.close();
  }
  // no-cache means "ask first": with the tag an unchanged file costs a 304
  // instead of the whole download on every page load.
  final stat = await file.stat();
  final tag = '"${stat.size.toRadixString(36)}-${stat.modified.microsecondsSinceEpoch.toRadixString(36)}"';
  response.headers.set(HttpHeaders.etagHeader, tag);
  if (request.headers.value(HttpHeaders.ifNoneMatchHeader) == tag) {
    response.statusCode = HttpStatus.notModified;
    return response.close();
  }
  final gzipOk = (request.headers.value(HttpHeaders.acceptEncodingHeader) ?? '').contains('gzip');
  if (gzipOk && _compressible.contains(extension) && stat.size > 1024) {
    var packed = _gzipCache[file.path];
    if (packed == null || packed.tag != tag) {
      packed = (tag: tag, bytes: gzip.encode(await file.readAsBytes()));
      _gzipCache[file.path] = packed;
    }
    response.headers
      ..set(HttpHeaders.contentEncodingHeader, 'gzip')
      ..set(HttpHeaders.varyHeader, 'Accept-Encoding')
      ..contentLength = packed.bytes.length;
    if (request.method != 'HEAD') response.add(packed.bytes);
    return response.close();
  }
  if (request.method != 'HEAD') await response.addStream(file.openRead());
  await response.close();
}
