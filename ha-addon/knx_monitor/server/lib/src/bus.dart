import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'alarms.dart';
import 'exporter.dart';
import 'ft12_link.dart';
import 'ha.dart';
import 'ha_link.dart';
import 'kberry.dart' show TtyLine;
import 'knxip.dart';
import 'link.dart';
import 'box_clock.dart';
import 'cemi_policy.dart';
import 'read_only.dart';
import 'recorder.dart';
import 'report.dart';
import 'secure/data_secure.dart';
import 'secure/ip_secure.dart';
import 'telegram_json.dart';
import 'fault_hunt.dart';
import 'watchers.dart';

/// Settings for continuous recording (`server.json` in the data folder), set
/// from the app.
class BusConfig {
  BusConfig({
    this.enabled = false,
    this.mode = 'udp',
    this.host = '',
    this.port = 3671,
    this.tunnelAddress,
    this.fallback = true,
    this.routingAddress = '0.0.254',
    this.retentionDays = 7,
    this.maxMegabytes = 1000,
    this.flushSeconds = 5,
    this.alarms = true,
    this.language = 'de',
    this.secure = const {},
    this.clockFromKnx = true,
    this.recordOnlyWithTime = false,
    this.device = defaultHatDevice,
    this.hatAddress,
    this.hatBusmonitor = false,
  });

  /// Serial port of the KNX HAT (kBerry on GPIO 14/15).
  static const defaultHatDevice = '/dev/ttyAMA0';

  /// Whether to keep the connection open and record.
  bool enabled;

  /// `udp`, `tcp`, `routing`, `secure` (IP Secure over TCP), `ha`
  /// (telegrams from the Home Assistant KNX integration, no own tunnel)
  /// or `hat` (the box's KNX HAT at [device], no gateway).
  String mode;
  String host;
  int port;

  /// Requested tunnel address, e.g. "1.1.240" (tunnelling v2 only).
  String? tunnelAddress;

  /// Whether to take any free slot if the tunnel address is taken.
  bool fallback;

  /// Source address for routing.
  String routingAddress;

  int retentionDays;
  int maxMegabytes;

  /// Write interval of the history; 0 = immediately.
  int flushSeconds;

  bool alarms;
  String language;

  /// IP Secure credentials (userId, userPassword, deviceAuthentication).
  Map<String, Object?> secure;

  /// Box: set the clock from a time sender on the line (DPT 19.001, 10 + 11).
  bool clockFromKnx;

  /// Box: start recording only once the time is confirmed, instead of
  /// correcting earlier lines afterwards.
  bool recordOnlyWithTime;

  /// KNX HAT: serial device (only `/dev/tty…` and `/dev/serial…`).
  String device;

  /// KNX HAT: own individual address, `null` = the module's.
  String? hatAddress;

  /// KNX HAT in bus monitor mode: all frames including acknowledgements, but
  /// no sending (no reads/writes from the app, no time request).
  bool hatBusmonitor;

  /// Modes without a gateway address.
  static const _withoutHost = {'routing', 'ha', 'hat'};

  /// Whether [mode] works without a host.
  static bool needsNoHost(String mode) => _withoutHost.contains(mode);

  factory BusConfig.fromJson(Map<String, Object?> j) => BusConfig(
    enabled: j['enabled'] == true,
    mode: const {'udp', 'tcp', 'routing', 'secure', 'ha', 'hat'}.contains(j['mode']) ? j['mode']! as String : 'udp',
    host: j['host'] as String? ?? '',
    port: (j['port'] as int?)?.clamp(1, 65535) ?? 3671,
    tunnelAddress: parseIndividual(j['tunnelAddress'] as String?) == null ? null : j['tunnelAddress'] as String?,
    fallback: j['fallback'] != false,
    routingAddress: parseIndividual(j['routingAddress'] as String?) == null
        ? '0.0.254'
        : j['routingAddress']! as String,
    retentionDays: (j['retentionDays'] as int?)?.clamp(0, 3650) ?? 7,
    maxMegabytes: (j['maxMegabytes'] as int?)?.clamp(10, 1000000) ?? 1000,
    flushSeconds: (j['flushSeconds'] as int?)?.clamp(0, 600) ?? 5,
    alarms: j['alarms'] != false,
    language: j['language'] as String? ?? 'de',
    secure: (j['secure'] as Map?)?.cast<String, Object?>() ?? const {},
    clockFromKnx: j['clockFromKnx'] != false,
    recordOnlyWithTime: j['recordOnlyWithTime'] == true,
    // Serial devices only: otherwise the app could open any file.
    device: switch (j['device']) {
      final String d when RegExp(r'^/dev/(tty[A-Za-z0-9]+|serial[0-9]+)$').hasMatch(d) => d,
      _ => defaultHatDevice,
    },
    hatAddress: parseIndividual(j['hatAddress'] as String?) == null ? null : j['hatAddress'] as String?,
    hatBusmonitor: j['hatBusmonitor'] == true,
  );

  Map<String, Object?> toJson({bool secrets = true}) => {
    'enabled': enabled,
    'mode': mode,
    'host': host,
    'port': port,
    'tunnelAddress': tunnelAddress,
    'fallback': fallback,
    'routingAddress': routingAddress,
    'retentionDays': retentionDays,
    'maxMegabytes': maxMegabytes,
    'flushSeconds': flushSeconds,
    'alarms': alarms,
    'language': language,
    'clockFromKnx': clockFromKnx,
    'recordOnlyWithTime': recordOnlyWithTime,
    'device': device,
    'hatAddress': hatAddress,
    'hatBusmonitor': hatBusmonitor,
    // Passwords never leave the server; the app only sees whether there are any.
    'secure': secrets
        ? secure
        : {
            'userId': secure['userId'],
            'hasUserPassword': (secure['userPassword'] as String?)?.isNotEmpty == true,
            'hasDeviceAuthentication': (secure['deviceAuthentication'] as String?)?.isNotEmpty == true,
          },
  };
}

/// A new bus connection could not be established while probing
/// ([BusService.update] with `probe`); the previous one stays in effect.
class BusProbeException implements Exception {
  const BusProbeException(this.message, {this.problem});
  final String message;

  /// See [LinkException.problem].
  final String? problem;
  @override
  String toString() => message;
}

/// Creates the bus connection for a configuration (replaceable in tests).
typedef LinkFactory = BusLink Function(BusConfig config);

BusLink defaultLink(BusConfig c) => switch (c.mode) {
  'routing' => RoutingLink(address: parseIndividual(c.routingAddress) ?? 0x00FE),
  'ha' => HaLink(),
  'hat' => Ft12CemiLink(
    open: (baud) => TtyLine.open(c.device, baud),
    device: c.device,
    busmonitor: c.hatBusmonitor,
    requestedAddress: parseIndividual(c.hatAddress),
  ),
  _ => KnxIpTunnel(
    host: c.host,
    port: c.port,
    tcp: c.mode == 'tcp' || c.mode == 'secure',
    requestedAddress: parseIndividual(c.tunnelAddress),
    fallback: c.fallback,
    secure: c.mode != 'secure'
        ? null
        : () => IpSecureSession(
            userId: (c.secure['userId'] as int?) ?? 2,
            userPassword: (c.secure['userPassword'] as String?) ?? '',
            deviceAuthentication: c.secure['deviceAuthentication'] as String?,
          ),
  ),
};

/// Keeps a bus connection open, records and distributes the frames to all
/// open browser tabs (WebSocket `/ws/bus`).
///
/// Messages (binary, first byte = type):
/// - Server → app: `0x01` cEMI frame, `0x02` status (JSON), `0x03` watcher hit
///   (JSON `{ids, line}`, line in history format), `0x11` send result
///   (2-byte id, 1-byte result, text),
/// - App → server: `0x10` send (2-byte id, cEMI L_Data.req), `0x12` release
///   the tunnel (1 byte: 1 = release, 0 = take back) – for the bus monitor,
///   which needs its own tunnel slot. Applies until the view takes it back or
///   disconnects; meanwhile the status is `yielded`.
class BusService {
  BusService(
    this.data, {
    LinkFactory? link,
    Future<void> Function({required String id, required String title, required String message})? notify,
    this.event,
    this.describe = describeGateway,
    this.clock,
    this.installation,
    this.hatDevice,
    Future<bool> Function({required String id, required String title, required String message})? homeAssistant,
    Future<List<Map<String, Object?>>> Function(DateTime from, DateTime to)? restarts,
    this.restartSummary,
    this.readOnly = false,
  }) : _linkFactory = readOnly ? ((c) => ReadOnlyLink((link ?? defaultLink)(c))) : link ?? defaultLink,
       recorder = Recorder(data),
       hunt = FaultHunt(data),
       availability = Availability(data) {
    final send = notify ?? ({required id, required title, required message}) async {};
    alarms = AlarmWatch(data, notify: send, onChange: _alarmEvent);
    watchers = WatchRuleSet(data, notify: send);
    report = ReportService(
      data,
      recorder: recorder,
      alarms: alarms,
      language: () => config.language,
      now: () => clock?.now() ?? DateTime.now(),
      timeKnown: () => clock?.synced != false,
      homeAssistant: homeAssistant,
      restarts: restarts,
    );
    exporter = DataExporter(data, source: _ExportSource(this));
  }

  /// Events for Home Assistant automations (see [HomeAssistant]);
  /// `null` on the box and in tests without Home Assistant.
  final Future<void> Function(String type, Map<String, Object?> data)? event;

  void _fire(String type, Map<String, Object?> data) {
    final event = this.event;
    if (event == null) return;
    unawaited(event(type, {...data, if (installation?['name'] case final String name) 'installation': name}));
  }

  void _alarmEvent(AlarmChange c) =>
      _fire(HomeAssistant.alarmEvent, {'address': c.groupAddress, 'name': c.name, 'kind': c.kind, 'active': c.active});

  /// Loads the catalog first: it determines the group address style, and the
  /// alarm check may not have loaded it yet when the first telegram arrives.
  void _watcherEvent(WatchHit hit, Map<String, Object?> line) =>
      unawaited(alarms.loadCatalog().then((_) => _watcherEventNow(hit, line)));

  void _watcherEventNow(WatchHit hit, Map<String, Object?> line) => _fire(HomeAssistant.watcherEvent, {
    'watcher_id': hit.id,
    'name': hit.name,
    'label': hit.label,
    'address': alarms.formatGroup(line['d']! as int),
    'source': formatIndividual(line['s']! as int),
    'value': ?hit.value,
    'raw': line['x'],
  });

  final Directory data;

  /// Read-only ([ReadOnlyLink]): every connection refuses to send, including
  /// read requests and the box's time request.
  final bool readOnly;
  final LinkFactory _linkFactory;
  final Future<Uint8List?> Function(String host, int port) describe;
  final Recorder recorder;
  final FaultHunt hunt;
  final Availability availability;
  late final AlarmWatch alarms;
  late final WatchRuleSet watchers;

  /// Data export to Prometheus and InfluxDB; off until the user enables it.
  late final DataExporter exporter;

  /// Unexpected server restarts, for the status (see [CrashWatch]).
  final Map<String, Object?>? Function()? restartSummary;

  /// Installation report and notifications; off until the user enables it.
  late final ReportService report;

  /// Clock of the KNX box; `null` in the add-on (Home Assistant sets the time).
  final BoxClock? clock;
  KnxTimeWatch? _knxTime;

  /// Active installation `{id, name}` for the status (see installations.dart).
  Map<String, Object?>? installation;

  /// Box: device of the KNX HAT; the status then offers the connection type
  /// `hat` (`hat.present` tells whether the device exists). `null` in the add-on.
  final String? hatDevice;

  BusConfig config = BusConfig();
  BusLink? _link;
  String state = 'disconnected';
  String? error;

  /// Known cause of [error] for the app's connection assistant
  /// (see [LinkException.problem]).
  String? problem;
  DateTime? since;
  DateTime? lastLost;
  Uint8List? _description;
  int _generation = 0;
  int _beatCount = 0;
  int today = 0;

  /// KNX HAT in bus monitor mode: acknowledgements and corrupt frames since start.
  final busmon = BusmonCounters();

  /// Value of [busmon] at the start of the day, for the daily total.
  BusmonCounters? _busmonDay;

  /// Repeated telegrams since start (for per-minute counters, MQTT).
  int repeats = 0;

  /// Time of the last telegram.
  DateTime? lastTelegram;
  String _todayName = '';
  Timer? _beat;
  Timer? _maintenance;
  Timer? _reportSoon;
  final _clients = <_Client>{};

  /// View whose bus monitor the tunnel is released for.
  _Client? _yieldedTo;

  /// Data Secure: keys from `secure_keys.json` (written by the app on keyring
  /// import), so secured telegrams are recorded in readable form.
  DataSecure? _dataSecure;
  DateTime? _keysTime;

  Future<void> _reloadKeys() async {
    final file = File('${data.path}/secure_keys.json');
    try {
      if (!await file.exists()) {
        _dataSecure = null;
        _keysTime = null;
        return;
      }
      final modified = await file.lastModified();
      if (modified == _keysTime) return;
      _keysTime = modified;
      final ds = DataSecure.fromJson(jsonDecode(await file.readAsString()) as Map<String, Object?>);
      _dataSecure = ds.groupKeys.isEmpty ? null : ds;
    } on Object catch (e) {
      stderr.writeln('secure_keys.json: $e');
    }
  }

  /// Exclusive device session (T_Connect … T_Disconnect) per destination address.
  final _deviceLocks = <int, (_Client, DateTime)>{};

  File get _configFile => File('${data.path}/server.json');

  Future<void> start() async {
    config = await _loadConfig();
    final clock = this.clock;
    if (clock != null) {
      // After switching installations the clock is already set.
      if (!clock.synced) await clock.init();
      recorder
        ..timeKnown = (() => clock.synced)
        ..monoMicros = (() => clock.monoMicros);
      clock.onSet = (time, mono) {
        unawaited(recorder.retime(time, mono));
        _broadcastState();
      };
      _knxTime = KnxTimeWatch(clock, dptOf: alarms.dptMainOf);
      stdout.writeln('KNX-Box: Uhr ${clock.source.name}');
    }
    _applyStorage();
    await _reloadKeys();
    await recorder.start();
    _beat = Timer.periodic(const Duration(minutes: 1), (_) => _heartbeat());
    await report.load();
    await exporter.start();
    _maintenance = Timer.periodic(const Duration(hours: 1), (_) {
      recorder.maintain();
      unawaited(report.tick());
    });
    _reportSoon = Timer(const Duration(minutes: 2), () => unawaited(report.tick()));
    _restart();
  }

  static Future<BusConfig> _readConfig(File file) async =>
      BusConfig.fromJson(jsonDecode(await file.readAsString()) as Map<String, Object?>);

  /// Reads `server.json`. If it is corrupt, it is moved aside and the backup
  /// (`server.json.bak`, the state before the latest change) is used; if that
  /// is missing too, the server runs without a bus connection and says so in
  /// the status, instead of silently carrying on with defaults.
  Future<BusConfig> _loadConfig() async {
    final file = _configFile;
    if (!await file.exists()) return BusConfig();
    try {
      return await _readConfig(file);
    } on Object catch (e) {
      final aside = '${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}';
      try {
        await file.rename(aside);
      } on Object catch (e) {
        stderr.writeln('server.json nicht beiseitezulegen: $e');
      }
      final backup = File('${file.path}.bak');
      try {
        if (await backup.exists()) {
          final restored = await _readConfig(backup);
          await backup.copy(file.path);
          stdout.writeln('server.json nicht lesbar ($e) – Sicherung übernommen, kaputte Datei: $aside');
          return restored;
        }
      } on Object catch (e) {
        stderr.writeln('server.json.bak nicht lesbar: $e');
      }
      stderr.writeln(
        'server.json nicht lesbar ($e) – beiseitegelegt als $aside; ohne Busverbindung bis zum neuen Verbinden',
      );
      configLost = true;
      return BusConfig();
    }
  }

  /// `server.json` was corrupt and no backup helped: the app asks to connect
  /// again (status `configLost`) until someone sends settings.
  bool configLost = false;

  void _applyStorage() {
    recorder
      ..retentionDays = config.retentionDays
      ..maxMegabytes = config.maxMegabytes
      ..flushInterval = Duration(seconds: config.flushSeconds)
      ..holdUntilTime = config.recordOnlyWithTime;
    _knxTime?.enabled = config.clockFromKnx;
    alarms
      ..enabled = config.alarms
      ..language = config.language;
    watchers.language = config.language;
  }

  Future<void> _heartbeat() async {
    await _reloadKeys();
    if (!config.enabled) return;
    // Without a confirmed time the heartbeats would land on the wrong day.
    if (clock?.synced == false) return;
    final n = _beatCount;
    _beatCount = 0;
    try {
      await availability.beat(connected: state == 'connected', telegrams: n);
    } on Object catch (e) {
      stderr.writeln('Verfügbarkeit: $e');
    }
    await _saveBusmonDay();
  }

  /// Bus monitor counters per day (`status/busmon-<day>.json`), only in this
  /// mode. Once per minute: the report's daily total reads them.
  Future<void> _saveBusmonDay() async {
    if (!(config.mode == 'hat' && config.hatBusmonitor) || busmon.total == 0) return;
    try {
      final name = Recorder.dayName(clock?.now() ?? DateTime.now());
      if (name != _busmonName) {
        _busmonName = name;
        _busmonDay = BusmonCounters()
          ..data = busmon.data
          ..acks = busmon.acks
          ..naks = busmon.naks
          ..busy = busmon.busy
          ..damaged = busmon.damaged
          ..orphanAcks = busmon.orphanAcks;
      }
      final base = _busmonDay!;
      final dir = Directory('${data.path}/status');
      await dir.create(recursive: true);
      final file = File('${dir.path}/busmon-$name.json');
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode({
          'data': busmon.data - base.data,
          'acks': busmon.acks - base.acks,
          'naks': busmon.naks - base.naks,
          'busy': busmon.busy - base.busy,
          'damaged': busmon.damaged - base.damaged,
          'orphanAcks': busmon.orphanAcks - base.orphanAcks,
        }),
        flush: true,
      );
      await tmp.rename(file.path);
    } on Object catch (e) {
      stderr.writeln('Busmonitor-Zähler: $e');
    }
  }

  String? _busmonName;

  /// Applies a new configuration from the app (known fields only).
  ///
  /// `probe: true` (connect screen): a changed bus connection is applied only
  /// once it is up. If it fails, settings, continuous recording and fault hunt
  /// stay with the previous connection, and [BusProbeException] gives the
  /// reason.
  Future<void> update(Map<String, Object?> changes) async {
    final probe = changes['probe'] == true;
    changes = {...changes}..remove('probe');
    final next = _merged(changes);
    // The HAT belongs to the box: the add-on image has neither `stty` nor UART
    // access (docs/kberry.md). Otherwise only an endless loop of failed attempts would remain.
    if (next.mode == 'hat' && config.mode != 'hat' && hatDevice == null) {
      throw const BusProbeException('KNX-HAT gibt es nur auf der KNX-Box.', problem: 'unsupported');
    }
    final reconnect = [
      'enabled',
      'mode',
      'host',
      'port',
      'tunnelAddress',
      'fallback',
      'routingAddress',
      'secure',
      'device',
      'hatAddress',
      'hatBusmonitor',
    ].any((k) => jsonEncode(next.toJson()[k]) != jsonEncode(config.toJson()[k]));
    final ready = probe && reconnect && _canConnect(next) && _yieldedTo == null ? await _probe(next) : null;
    configLost = false;
    if (next.host != config.host || next.port != config.port || next.mode != config.mode) _description = null;
    config = next;
    _applyStorage();
    // Back up the previous state in case the file gets corrupted later.
    if (await _configFile.exists()) await _configFile.copy('${_configFile.path}.bak');
    final tmp = File('${_configFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(config.toJson()), flush: true);
    await tmp.rename(_configFile.path);
    if (changes.containsKey('retentionDays') || changes.containsKey('maxMegabytes')) await recorder.maintain();
    if (reconnect) _restart(ready: ready);
    _broadcastState();
  }

  BusConfig _merged(Map<String, Object?> changes) {
    final merged = config.toJson()..addAll(changes);
    // Empty password fields from the app mean "leave unchanged".
    final secure = {...config.secure, ...?(changes['secure'] as Map?)?.cast<String, Object?>()};
    for (final key in ['userPassword', 'deviceAuthentication']) {
      if ((changes['secure'] as Map?)?[key] == '' && (config.secure[key] as String?)?.isNotEmpty == true) {
        secure[key] = config.secure[key];
      }
    }
    merged['secure'] = secure;
    return BusConfig.fromJson(merged);
  }

  /// Whether [changes] changes anything. A device without admin rights must not
  /// change anything, but the app always sends the settings when connecting; if
  /// they match the box's, that passes and nothing happens.
  bool wouldChange(Map<String, Object?> changes) {
    final rest = {...changes}..remove('probe');
    return jsonEncode(_merged(rest).toJson()) != jsonEncode(config.toJson());
  }

  static bool _canConnect(BusConfig c) => c.enabled && (BusConfig.needsNoHost(c.mode) || c.host.isNotEmpty);

  /// Connects to [next] on trial; the previous connection is closed for this
  /// (the same gateway often has only a few tunnel slots). On success the open
  /// connection goes to [_run]; otherwise the server reconnects as before.
  Future<BusLink> _probe(BusConfig next) async {
    ++_generation;
    final old = _link;
    _link = null;
    if (old != null) await old.close();
    _setState('connecting');
    final link = _linkFactory(next);
    try {
      await link.connect();
      return link;
    } on Object catch (e) {
      await link.close();
      stdout.writeln('Neue Busverbindung nicht möglich: $e – bisherige bleibt');
      _restart();
      throw BusProbeException('$e', problem: e is LinkException ? e.problem : null);
    }
  }

  /// Reconnects; [ready] is an already open connection (from [_probe]).
  void _restart({BusLink? ready}) {
    final generation = ++_generation;
    final old = _link;
    _link = null;
    if (old != null) unawaited(old.close());
    if (_yieldedTo != null || !_canConnect(config)) {
      if (ready != null) unawaited(ready.close());
      _setState(_yieldedTo != null ? 'yielded' : 'disconnected');
      return;
    }
    unawaited(_run(generation, ready: ready));
  }

  /// Releases or takes back the tunnel for a view's bus monitor.
  /// Reports it as released only once the tunnel is really closed – otherwise
  /// the bus monitor finds no free slot yet.
  Future<void> _yield(_Client client, {required bool release}) async {
    // The HAT has no second tunnel slot; the server provides the bus monitor
    // itself (hatBusmonitor).
    if (release && config.mode == 'hat') return;
    if (release) {
      _yieldedTo = client;
      ++_generation;
      final old = _link;
      _link = null;
      if (old != null) await old.close();
      error = null;
      _setState('yielded');
      stdout.writeln('Tunnel für den Busmonitor freigegeben');
    } else if (identical(_yieldedTo, client)) {
      _yieldedTo = null;
      stdout.writeln('Tunnel zurückgenommen');
      _restart();
    }
  }

  bool _current(int generation) => generation == _generation;

  Future<void> _run(int generation, {BusLink? ready}) async {
    var failures = 0;
    var reported = false;
    var open = ready;
    while (_current(generation)) {
      _setState('connecting');
      final link = open ?? _linkFactory(config);
      final fresh = open == null;
      open = null;
      try {
        if (fresh) await link.connect();
        if (!_current(generation)) {
          await link.close();
          return;
        }
        _link = link;
        failures = 0;
        reported = false;
        error = null;
        problem = null;
        since = DateTime.now();
        if (!BusConfig.needsNoHost(config.mode)) _description ??= await describe(config.host, config.port);
        final sub = link.frames.listen(_onFrame);
        _setState('connected');
        stdout.writeln('Bus verbunden: ${link.label}');
        unawaited(_askTime(link));
        final reason = await link.lost;
        await sub.cancel();
        if (!_current(generation)) return;
        _link = null;
        lastLost = DateTime.now();
        error = reason;
        problem = null;
        stdout.writeln('Bus getrennt: $reason');
        // Reconnect immediately – short dropouts should not leave a gap.
        continue;
      } on Object catch (e) {
        await link.close();
        if (!_current(generation)) return;
        error = '$e';
        problem = e is LinkException ? e.problem : (e is TimeoutException ? 'noResponse' : null);
        // Report an outage once, not on every attempt.
        if (!reported) {
          stdout.writeln('Bus nicht erreichbar: $e – versuche weiter');
          reported = true;
        }
        _setState('disconnected');
        final busy = e is LinkException && e.status == Status.noMoreConnections;
        final seconds = busy ? 15 : const [1, 2, 4, 8, 15, 30, 60][failures.clamp(0, 6)];
        failures++;
        await Future<void>.delayed(Duration(seconds: seconds));
      }
    }
  }

  void _setState(String next) {
    if (state == next) return;
    final was = state == 'connected';
    state = next;
    _broadcastState();
    // Report only real changes, not every connection attempt.
    if (was != (next == 'connected')) {
      _fire(HomeAssistant.busEvent, {'connected': next == 'connected', 'state': next, 'reason': ?error});
    }
  }

  /// Box without a confirmed time: asks the project's time sender once
  /// instead of waiting for its next send cycle.
  Future<void> _askTime(BusLink link) async {
    final watch = _knxTime;
    if (readOnly || watch == null || !watch.enabled || clock!.synced) return;
    try {
      await alarms.loadCatalog();
      final group = watch.timeGroup(alarms.groups);
      if (group == null) return;
      // L_Data.req, group, low priority, GroupValueRead
      await link.send(
        Uint8List.fromList([0x11, 0x00, 0xBC, 0xE0, 0x00, 0x00, group >> 8, group & 0xFF, 0x01, 0x00, 0x00]),
      );
    } on Object catch (e) {
      stderr.writeln('Zeit anfragen: $e');
    }
  }

  /// Whatever comes from the bus must never stop the server: frames can be
  /// forged (UDP), and a listener error would otherwise end the process.
  void _onFrame(Uint8List frame) {
    try {
      _handleFrame(frame);
    } on Object catch (e) {
      stderr.writeln('Frame verworfen: $e');
    }
  }

  void _handleFrame(Uint8List frame) {
    final now = clock?.now() ?? DateTime.now();
    for (final c in _clients) {
      c.send([0x01, ...frame]);
    }
    var cemi = frame;
    if (frame.isNotEmpty && frame[0] == 0x2B) {
      // KNX HAT in bus monitor mode: the views get the raw frame for the
      // bus monitor; data telegrams additionally go to them, the recorder and
      // the watchers as if from the tunnel. Acknowledgements and corrupt frames end here.
      busmon.add(frame);
      final ldata = busmonToLData(frame);
      if (ldata == null) return;
      cemi = ldata;
      for (final c in _clients) {
        c.send([0x01, ...cemi]);
      }
    }
    // Record secured telegrams decrypted; the views get the original frame
    // and decrypt it themselves.
    final ds = _dataSecure;
    final plain = ds != null && DataSecure.isSecure(cemi) ? ds.receive(cemi).$2 : cemi;
    final line = telegramJson(plain, now);
    if (line == null) return;
    _beatCount++;
    lastTelegram = now;
    if (line['rp'] == true) repeats++;
    final name = Recorder.dayName(now);
    if (name != _todayName) {
      _todayName = name;
      today = 0;
      unawaited(recorder.maintain()); // Day change: pack yesterday
    }
    today++;
    // Clock first (if it sets it, the following line is already sorted in
    // correctly), then record.
    final watch = _knxTime;
    if (watch != null) unawaited(watch.observe(line).catchError((Object e) => stderr.writeln('Uhr: $e')));
    recorder.add(line);
    exporter.add(line);
    unawaited(hunt.add(line, now).catchError((Object e) => stderr.writeln('Fehlerjagd: $e')));
    unawaited(alarms.check(line).catchError((Object e) => stderr.writeln('Alarm: $e')));
    unawaited(
      watchers
          .check(line, now: now, onHit: (hit) => _watcherEvent(hit, line))
          .then((ids) => _broadcastHits(ids, line))
          .catchError((Object e) => stderr.writeln('Wächter: $e')),
    );
  }

  /// Server version: in the add-on from the image (ADDON_VERSION), on the
  /// box from `VERSION` next to the program; `null` during development.
  static final String? version = () {
    final env = Platform.environment['ADDON_VERSION'];
    if (env != null && env.isNotEmpty && env != 'dev') return env;
    try {
      final file = File('${File(Platform.resolvedExecutable).parent.path}/VERSION');
      if (file.existsSync()) return file.readAsStringSync().trim();
    } on Object {
      // No access: no version.
    }
    return null;
  }();

  Map<String, Object?> status() => {
    'version': ?version,
    'state': state,
    'error': error,
    if (readOnly) 'readOnly': true,
    'problem': ?problem,
    if (configLost) 'configLost': true,
    'restarts': ?restartSummary?.call(),
    'since': since?.millisecondsSinceEpoch,
    'lastLost': lastLost?.millisecondsSinceEpoch,
    'link': _link?.label,
    'address': _link?.address,
    'description': _description == null ? null : hexOf(_description!),
    'today': today,
    'written': recorder.written,
    'dropped': recorder.dropped,
    // Recording paused because the disk is full: the app says so.
    if (recorder.lowSpace) 'lowSpace': true,
    if (recorder.droppedLowSpace > 0) 'droppedLowSpace': recorder.droppedLowSpace,
    if (config.mode == 'hat' && config.hatBusmonitor) 'busmon': busmon.toJson(),
    if (clock != null) 'clock': clock!.status(),
    if (clock != null) 'waiting': recorder.waiting,
    'clients': _clients.length,
    // In the add-on: is the KNX integration set up? Then the app suggests the
    // mode without its own tunnel.
    'haKnx': ?HomeAssistant.instance.knx,
    // Box: offer the KNX HAT as a connection type if the device exists.
    if (hatDevice case final standard?) 'hat': _hatStatus(config.mode == 'hat' ? config.device : standard),
    if (installation != null) 'installation': installation,
    'config': config.toJson(secrets: false),
  };

  static Map<String, Object?> _hatStatus(String device) => {'device': device, 'present': File(device).existsSync()};

  /// Sends watcher hits to all views: sound and notice there; the server sends
  /// the notification to Home Assistant itself.
  void _broadcastHits(List<String> ids, Map<String, Object?> line) {
    if (ids.isEmpty) return;
    final message = [
      0x03,
      ...utf8.encode(jsonEncode({'ids': ids, 'line': line})),
    ];
    for (final c in _clients) {
      c.send(message);
    }
  }

  void _broadcastState() {
    final message = [0x02, ...utf8.encode(jsonEncode(status()))];
    for (final c in _clients) {
      c.send(message);
    }
  }

  /// Serves a browser tab until it closes.
  ///
  /// [admin]: device with full rights (add-on, box password). Otherwise it may
  /// only send group values ([deviceMaySend]) and not release the tunnel.
  Future<void> serve(WebSocket ws, {bool admin = true}) async {
    final client = _Client(ws, admin: admin);
    _clients.add(client);
    client.send([0x02, ...utf8.encode(jsonEncode(status()))]);
    try {
      await for (final message in ws) {
        if (message is List<int> && message.length >= 3 && message[0] == 0x10) {
          unawaited(_clientSend(client, (message[1] << 8) | message[2], Uint8List.fromList(message.sublist(3))));
        } else if (message is List<int> && message.length == 2 && message[0] == 0x12) {
          // Releasing disconnects continuous recording; that is reserved for admins.
          if (admin || message[1] != 1) unawaited(_yieldSafely(client, release: message[1] == 1));
        }
      }
    } on Object {
      // Connection gone
    } finally {
      _clients.remove(client);
      _deviceLocks.removeWhere((_, lock) => lock.$1 == client);
      // View gone without taking back (tab closed): reconnect.
      if (identical(_yieldedTo, client)) unawaited(_yieldSafely(client, release: false));
    }
  }

  Future<void> _yieldSafely(_Client client, {required bool release}) async {
    try {
      await _yield(client, release: release);
    } on Object catch (e) {
      stderr.writeln('Tunnel freigeben: $e');
    }
  }

  /// Send results: 0 sent, 1 not connected, 2 connection error, 3 invalid
  /// frame, 4 device busy, 5 not allowed (only group values without admin
  /// rights), 6 read-only is on. Never throws: an error here would end as an
  /// unhandled error in process exit (`exit(255)`), and any logged-in client
  /// could have sent recording into a restart loop that way.
  Future<void> _clientSend(_Client client, int id, Uint8List cemi) async {
    void reply(int result, [String text = '']) => client.send([0x11, id >> 8, id & 0xFF, result, ...utf8.encode(text)]);

    try {
      if (readOnly) return reply(6, readOnlyMessage);
      if (!isLDataRequest(cemi)) return reply(3, 'Ungültiger Frame');
      if (!client.admin && !deviceMaySend(cemi)) {
        return reply(5, 'Dieses Gerät darf nur Gruppenwerte senden. Mit dem Box-Passwort koppeln.');
      }
      final link = _link;
      if (link == null || state != 'connected') return reply(1, 'Nicht verbunden');
      if (!_lockDevice(client, cemi)) return reply(4, 'Gerät wird gerade von einer anderen Ansicht geprüft');
      await link.send(cemi);
      reply(0);
    } on LinkException catch (e) {
      reply(2, e.message);
    } on Object catch (e) {
      try {
        reply(2, '$e');
      } on Object {
        // View already gone.
      }
    }
  }

  /// Connection-oriented device access (checking an address, device descriptor)
  /// runs over the shared tunnel address. Two views at once would break each
  /// other's session – hence exclusive per device.
  bool _lockDevice(_Client client, Uint8List cemi) {
    final i = 2 + cemi[1];
    final group = cemi[i + 1] & 0x80 != 0;
    if (group) return true;
    final destination = (cemi[i + 4] << 8) | cemi[i + 5];
    final tpci = cemi[i + 7];
    final now = DateTime.now();
    _deviceLocks.removeWhere((_, lock) => now.difference(lock.$2) > const Duration(seconds: 10));
    final lock = _deviceLocks[destination];
    if (lock != null && lock.$1 != client) return false;
    if (tpci == 0x81) {
      _deviceLocks.remove(destination); // T_Disconnect
    } else {
      _deviceLocks[destination] = (client, now);
    }
    return true;
  }

  /// Closes all open views (installation switched); the app reconnects and
  /// ends up on the new bus connection.
  Future<void> closeClients() async {
    final clients = List.of(_clients);
    _clients.clear();
    _deviceLocks.clear();
    for (final c in clients) {
      await c.ws.close(WebSocketStatus.goingAway, 'Installation gewechselt').catchError((Object _) {});
    }
  }

  /// On shutdown: writes the history and cleanly disconnects.
  Future<void> shutdown() async {
    _generation++;
    _beat?.cancel();
    _maintenance?.cancel();
    _reportSoon?.cancel();
    await recorder.flush(durable: true);
    await hunt.close();
    await exporter.stop();
    await _link?.close();
  }
}

class _ExportSource implements ExportSource {
  _ExportSource(this.bus);
  final BusService bus;

  @override
  bool get connected => bus.state == 'connected';
  @override
  int get recorderDropped => bus.recorder.dropped;
  @override
  Map<String, Object?>? get busmon => bus.config.mode == 'hat' && bus.config.hatBusmonitor ? bus.busmon.toJson() : null;
  @override
  bool get timeKnown => bus.clock?.synced != false;
  @override
  String formatGroup(int group) => bus.alarms.formatGroup(group);
  @override
  String? nameOf(int group) => bus.alarms.nameOf(group);
  @override
  (int, int?)? dptOf(int group) => bus.alarms.dptOf(group);
}

class _Client {
  _Client(this.ws, {required this.admin});
  final WebSocket ws;
  final bool admin;
  void send(List<int> bytes) {
    if (ws.readyState == WebSocket.open) ws.add(Uint8List.fromList(bytes));
  }
}
