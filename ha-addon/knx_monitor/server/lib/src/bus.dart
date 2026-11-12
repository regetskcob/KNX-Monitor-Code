import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'alarms.dart';
import 'dali_watch.dart';
import 'atomic_file.dart';
import 'exporter.dart';
import 'ha.dart';
import 'ha_history.dart';
import 'ha_link.dart';

import 'package:knx/knx.dart';

import 'package:knx_io/knx_io.dart';

import 'link_texts.dart';
import 'box_clock.dart';
import 'cemi_policy.dart';
import 'read_only.dart';
import 'recorder.dart';
import 'report.dart';

import 'package:knx/secure.dart';

import 'secure_taps.dart';
import 'tap_silence.dart';
import 'tap_window.dart';
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
    this.taps = const [],
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

  /// Further tap points (issue #8): each `{name, mode: udp|tcp|routing, host, port, tunnelAddress?,
  /// windowMs?, paused?}`. The server holds them next to the main connection and merges the
  /// telegrams ([TapMerger]). Empty for most installations.
  List<Map<String, Object?>> taps;

  /// At most this many further tap points (8 in all, as in the app).
  static const maxTaps = 7;

  /// Longest name of a tap point; it ends up in status, log and history.
  static const maxTapName = 80;

  static final _tapHost = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9._:-]{0,251}[A-Za-z0-9])?$');

  /// Whether [host] can be a tap point's address for [mode]: a host name or IP address for a
  /// tunnel, an IPv4 multicast group (or empty = the KNX default) for routing.
  static bool validTapHost(String mode, String host) {
    if (mode == 'routing') {
      if (host.isEmpty) return true;
      final a = InternetAddress.tryParse(host);
      return a != null && a.type == InternetAddressType.IPv4 && a.rawAddress[0] >= 224 && a.rawAddress[0] <= 239;
    }
    if (!_tapHost.hasMatch(host)) return false;
    // Digits and dots only is meant as an IPv4 address and must be one ("300.1" is not).
    if (!RegExp(r'^[0-9.]+$').hasMatch(host)) return true;
    final parts = host.split('.');
    return parts.length == 4 && parts.every((p) => p.isNotEmpty && p.length <= 3 && int.parse(p) <= 255);
  }

  /// Name without control characters (it is written to the log) and at most [maxTapName] long.
  static String _tapName(Object? raw, String fallback) {
    var name = raw is String ? raw.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ').trim() : '';
    if (name.isEmpty) name = fallback.isEmpty ? 'Routing' : fallback;
    return name.length > maxTapName ? name.substring(0, maxTapName) : name;
  }

  /// Why one entry of `taps` in a request is not usable; `null` if it is.
  static String? invalidTap(Object? t) {
    if (t is! Map) return 'taps: Objekt je Messpunkt erwartet.';
    final mode = t['mode'];
    final host = t['host'];
    if (mode is! String || !const {'udp', 'tcp', 'routing'}.contains(mode)) {
      return 'taps: mode udp, tcp oder routing erwartet.';
    }
    if (host is! String || !validTapHost(mode, host)) return 'taps: host ist keine gültige Adresse.';
    if (t['name'] case final name? when name is! String || name.length > maxTapName) {
      return 'taps: name mit höchstens $maxTapName Zeichen erwartet.';
    }
    if (t['port'] case final port? when port is! int || port < 1 || port > 65535) {
      return 'taps: port von 1 bis 65535 erwartet.';
    }
    if (t['windowMs'] case final w? when w is! int || w < 10 || w > 5000) {
      return 'taps: windowMs von 10 bis 5000 erwartet.';
    }
    if (t['tunnelAddress'] case final a? when a is! String || parseIndividual(a) == null) {
      return 'taps: tunnelAddress wie 1.1.250 erwartet.';
    }
    if (t['paused'] case final p? when p is! bool) return 'taps: paused true oder false erwartet.';
    return null;
  }

  /// Usable tap point entries only, with known keys and clamped values. The same connection
  /// twice (mode, host and port; routing: the multicast group) counts once: a second tunnel to
  /// the same interface shows nothing new and takes a tunnel away from ETS or the visualisation.
  static List<Map<String, Object?>> cleanTaps(Object? raw) {
    if (raw is! List) return const [];
    final out = <Map<String, Object?>>[];
    final seen = <String>{};
    for (final t in raw) {
      if (t is! Map || out.length >= maxTaps) continue;
      final mode = t['mode'];
      final host = t['host'];
      if (mode is! String || !const {'udp', 'tcp', 'routing'}.contains(mode)) continue;
      if (host is! String || host.isEmpty && mode != 'routing' || !validTapHost(mode, host)) continue;
      final port = t['port'];
      final usedPort = port is int && port >= 1 && port <= 65535 ? port : 3671;
      if (!seen.add(mode == 'routing' ? 'routing|$host' : '${host.toLowerCase()}|$usedPort')) continue;
      final window = t['windowMs'];
      out.add({
        'name': _tapName(t['name'], host),
        'mode': mode,
        'host': host,
        'port': usedPort,
        'tunnelAddress': switch (t['tunnelAddress']) {
          final String a when parseIndividual(a) != null => a,
          _ => null,
        },
        if (window is int && window > 0) 'windowMs': window.clamp(10, 5000),
        if (t['paused'] == true) 'paused': true,
      });
    }
    return out;
  }

  /// Modes without a gateway address.
  static const _withoutHost = {'routing', 'ha', 'hat'};

  /// Whether [mode] works without a host.
  static bool needsNoHost(String mode) => _withoutHost.contains(mode);

  /// Why [changes] from a request cannot be applied; `null` if they can.
  /// [BusConfig.fromJson] clamps numbers and casts types, which is right for
  /// the stored file but not for a request: `"retentionDays": -5` became 0,
  /// and 0 means recording off, which deletes the whole history.
  static String? invalidChange(Map<String, Object?> changes) {
    const ranges = {
      'port': (1, 65535),
      'retentionDays': (0, 3650),
      'maxMegabytes': (10, 1000000),
      'flushSeconds': (0, 600),
    };
    const strings = {'mode', 'host', 'tunnelAddress', 'routingAddress', 'language', 'device', 'hatAddress'};
    const switches = {'enabled', 'fallback', 'alarms', 'clockFromKnx', 'recordOnlyWithTime', 'hatBusmonitor', 'probe'};
    for (final MapEntry(:key, :value) in changes.entries) {
      if (ranges[key] case (final min, final max)) {
        if (value is! int || value < min || value > max) return '$key: ganze Zahl von $min bis $max erwartet.';
      } else if (switches.contains(key)) {
        // "false" as text would count as off, anything else for fallback as on.
        if (value is! bool) return '$key: true oder false erwartet.';
      } else if (strings.contains(key)) {
        if (value != null && value is! String) return '$key: Text erwartet.';
      } else if (key == 'secure' && value != null && value is! Map) {
        return 'secure: Objekt erwartet.';
      } else if (key == 'taps' && value != null) {
        if (value is! List || value.length > maxTaps) {
          return 'taps: Liste mit höchstens $maxTaps Messpunkten erwartet.';
        }
        for (final t in value) {
          if (invalidTap(t) case final error?) return error;
        }
      }
    }
    return null;
  }

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
    taps: cleanTaps(j['taps']),
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
    'taps': taps,
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
    this.telegram,
    Map<String, Object?>? Function()? mqttTelegrams,
    Future<Map<String, Object?>> Function(Map<String, Object?> changes)? mqttConfigure,
    Map<String, Object?>? Function()? healthCheck,
  }) : _linkFactory = readOnly ? ((c) => ReadOnlyLink((link ?? defaultLink)(c))) : link ?? defaultLink,
       recorder = Recorder(data, clock: clock?.now),
       hunt = FaultHunt(data),
       availability = Availability(data) {
    final send = notify ?? ({required id, required title, required message}) async {};
    alarms = AlarmWatch(data, notify: send, onChange: _alarmEvent);
    watchers = WatchRuleSet(data, notify: send);
    dali = DaliWatch(
      data,
      dptOf: alarms.dptOf,
      formatGroup: alarms.formatGroup,
      notify: send,
      onChange: _daliEvent,
      timeKnown: () => clock?.synced != false,
    );
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
    exporter = DataExporter(data, source: _ExportSource(this))
      ..mqttTelegrams = mqttTelegrams
      ..mqttConfigure = mqttConfigure
      ..healthCheck = healthCheck;
  }

  /// Events for Home Assistant automations (see [HomeAssistant]);
  /// `null` on the box and in tests without Home Assistant.
  final Future<void> Function(String type, Map<String, Object?> data)? event;

  /// Every recorded group telegram (history line), e.g. for the cycle watch
  /// of the Home Assistant integration (cycle_watch.dart) and the MQTT
  /// telegram stream ([MqttBridge.onTelegram]). Must be cheap.
  /// [secure] is true for every KNX Data Secure telegram (also without a
  /// keyring), [decrypted] when the server could decrypt it: receivers that
  /// pass data on must not leak it by default.
  final void Function(Map<String, Object?> line, {required bool secure, required bool decrypted})? telegram;

  void _fire(String type, Map<String, Object?> data) {
    final event = this.event;
    if (event == null) return;
    unawaited(event(type, {...data, if (installation?['name'] case final String name) 'installation': name}));
  }

  void _alarmEvent(AlarmChange c) =>
      _fire(HomeAssistant.alarmEvent, {'address': c.groupAddress, 'name': c.name, 'kind': c.kind, 'active': c.active});

  /// A DALI luminaire or group enters or leaves a fault: the same event as an alarm address, with
  /// the luminaire's name and its DALI address.
  void _daliEvent(DaliFaultChange c) => _fire(HomeAssistant.alarmEvent, {
    'address': c.groupAddress,
    'name': c.name,
    'kind': 'fault',
    'active': c.faults != 0,
    'dali': {
      'gateway': c.gateway,
      c.test
              ? 'test'
              : c.isGroup
              ? 'group'
              : 'address':
          c.address,
      'faults': c.faults,
    },
  });

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

  /// DALI: faults per luminaire and the emergency lighting log.
  late final DaliWatch dali;

  /// What this server can do beyond the basics; the app asks before it relies on it (status
  /// `features`): `bitsCheck` = watchers on flags (check kind `bits`), `dali` = faults per
  /// luminaire and the emergency lighting log are handled here.
  static const features = ['bitsCheck', 'dali'];

  /// Data export to Prometheus and InfluxDB; off until the user enables it.
  late final DataExporter exporter;

  /// Unexpected server restarts, for the status (see [CrashWatch]).
  final Map<String, Object?>? Function()? restartSummary;

  /// Installation report and notifications; off until the user enables it.
  late final ReportService report;

  /// Clock of the Busclear Box; `null` in the add-on (Home Assistant sets the time).
  final BoxClock? clock;
  KnxTimeWatch? _knxTime;

  /// Active installation `{id, name}` for the status (see installations.dart).
  Map<String, Object?>? installation;

  /// Box: device of the KNX HAT; the status then offers the connection type
  /// `hat` (`hat.present` tells whether the device exists). `null` in the add-on.
  final String? hatDevice;

  BusConfig config = BusConfig();
  BusLink? _link;

  /// Links of the further tap points (issue #8) by tap number (1 = first further one).
  final _tapLinks = <int, BusLink>{};

  /// State per further tap point: `{state, error, address}`.
  final _tapState = <int, Map<String, Object?>>{};

  /// Merges main connection and tap points; `null` without further tap points.
  TapMerger? _merger;
  final _backlog = TapBacklog();
  Timer? _mergeFlush;

  /// Data Secure flags of a telegram until the merger releases it (keyed by its raw frame).
  final _secureOf = Expando<(bool, bool)>();
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

  /// Telegrams of the running day; after a restart preset from the history
  /// ([todayCounted]).
  int today = 0;

  /// Completes once [today] holds the telegrams recorded before the start.
  Future<void> todayCounted = Future.value();

  /// KNX HAT in bus monitor mode: acknowledgements and corrupt frames since start.
  final busmon = BusmonCounters();

  /// Value of [busmon] at the start of the day, for the daily total.
  BusmonCounters? _busmonDay;

  /// Repeated telegrams since start (for per-minute counters, MQTT).
  int repeats = 0;

  /// Estimated bus occupancy in seconds since start, per telegram as in the
  /// report ([busySeconds], 9600 bit/s); the bus load in percent is its
  /// increase per elapsed time (MQTT).
  double busy = 0;

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

  /// Highest valid Data Secure sequence number per sender seen so far. The
  /// keyring only knows the numbers from the time of its export; without this
  /// a recorded telegram replayed after a restart would count as valid again.
  /// Kept in [_sequenceFile], written at most every [_sequenceDelay] and on
  /// [shutdown].
  final _sequences = <int, int>{};
  Timer? _sequenceSave;
  static const _sequenceDelay = Duration(seconds: 30);

  /// Next to `secure_keys.json`; owned by the server (`/api/files/` keeps it private).
  File get _sequenceFile => File('${data.path}/$sequenceFileName');

  /// See [_sequences].
  static const sequenceFileName = 'secure_sequence.json';

  Future<void> _loadSequences() async {
    try {
      if (!await _sequenceFile.exists()) return;
      final json = jsonDecode(await _sequenceFile.readAsString()) as Map<String, Object?>;
      for (final MapEntry(:key, :value) in json.entries) {
        final source = int.tryParse(key);
        if (source != null && value is int) _sequences[source] = value;
      }
    } on Object catch (e) {
      stderr.writeln('$sequenceFileName: $e');
    }
  }

  /// Lets the copy of a secured telegram at a further tap point through, and only that
  /// ([SecureTapCache]); the window follows the merge windows in use.
  final secureTaps = SecureTapCache();

  /// Notes the sequence number of a telegram that [DataSecure.receive] accepted.
  void _noteSequence(Uint8List cemi) {
    final i = 2 + cemi[1];
    final source = (cemi[i + 2] << 8) | cemi[i + 3];
    var seq = 0;
    for (var b = i + 10; b < i + 16; b++) {
      seq = (seq << 8) | cemi[b];
    }
    _sequences[source] = seq;
    _sequenceSave ??= Timer(_sequenceDelay, () => unawaited(_saveSequences()));
  }

  Future<void> _saveSequences() async {
    _sequenceSave?.cancel();
    _sequenceSave = null;
    try {
      await writeAtomic(_sequenceFile, text: jsonEncode({for (final e in _sequences.entries) '${e.key}': e.value}));
    } on Object catch (e) {
      stderr.writeln('$sequenceFileName: $e');
    }
  }

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
      final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
      // Only senders from the keyring count; for those, the higher of the
      // keyring's number and the last one seen here.
      final sequence = {
        for (final MapEntry(:key, :value) in ((json['sequence'] as Map?) ?? const {}).entries)
          '$key': switch (_sequences[int.tryParse('$key')]) {
            final int seen when value is int && seen > value => seen,
            _ => value,
          },
      };
      final ds = DataSecure.fromJson({...json, 'sequence': sequence});
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
      stdout.writeln('Busclear Box: Uhr ${clock.source.name}');
    }
    _applyStorage();
    await _loadSequences();
    await _reloadKeys();
    await recorder.start();
    todayCounted = _countToday();
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

  /// Presets [today] from the history of the running day, so the counter does
  /// not start at 0 after a restart. Read in an isolate (a busy day has
  /// 100,000 lines) while telegrams keep coming; only lines from before the
  /// start count, the rest [_process] counts itself.
  Future<void> _countToday() async {
    final clock = this.clock;
    // Box without a confirmed time: the day is not known yet.
    if (clock != null && !clock.synced) return;
    final started = clock?.now() ?? DateTime.now();
    final day = Recorder.dayName(started);
    final path = data.path;
    final before = started.microsecondsSinceEpoch;
    try {
      final count = await Isolate.run(() => countDayBefore(path, day, before));
      if (_todayName.isEmpty) _todayName = day;
      // The day changed meanwhile: its counter starts at 0 anyway.
      if (_todayName == day) today += count;
    } on Object catch (e) {
      stderr.writeln('Telegramme heute: $e');
    }
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
    dali
      ..enabled = config.alarms
      ..language = config.language;
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
          ..orphanAcks = busmon.orphanAcks
          ..seqGaps = busmon.seqGaps;
      }
      final base = _busmonDay!;
      final dir = Directory('${data.path}/status');
      await dir.create(recursive: true);
      final file = File('${dir.path}/busmon-$name.json');
      await writeAtomic(
        file,
        text: jsonEncode({
          'data': busmon.data - base.data,
          'acks': busmon.acks - base.acks,
          'naks': busmon.naks - base.naks,
          'busy': busmon.busy - base.busy,
          'damaged': busmon.damaged - base.damaged,
          'orphanAcks': busmon.orphanAcks - base.orphanAcks,
          'seqGaps': busmon.seqGaps - base.seqGaps,
        }),
      );
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
      throw const BusProbeException('KNX-HAT gibt es nur auf der Busclear Box.', problem: 'unsupported');
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
      'taps',
    ].any((k) => jsonEncode(next.toJson()[k]) != jsonEncode(config.toJson()[k]));
    final ready = probe && reconnect && _canConnect(next) && _yieldedTo == null ? await _probe(next) : null;
    configLost = false;
    if (next.host != config.host || next.port != config.port || next.mode != config.mode) _description = null;
    config = next;
    _applyStorage();
    final json = jsonEncode(config.toJson());
    await serialized(_configFile, () async {
      // Back up the previous state in case the file gets corrupted later.
      if (await _configFile.exists()) await _configFile.copy('${_configFile.path}.bak');
      await writeAtomicNow(_configFile, text: json);
    });
    if (changes.containsKey('retentionDays') || changes.containsKey('maxMegabytes')) await recorder.maintain();
    if (reconnect) _restart(ready: ready);
    _broadcastState();
  }

  BusConfig _merged(Map<String, Object?> changes) {
    final merged = config.toJson()..addAll(changes);
    // Empty password fields from the app mean "leave unchanged" – but only for
    // the same gateway: IP Secure answers a foreign host with a MAC over the
    // user password, which can be guessed offline there.
    final sameHost = !changes.containsKey('host') || changes['host'] == config.host;
    final secure = {...config.secure, ...?(changes['secure'] as Map?)?.cast<String, Object?>()};
    for (final key in ['userPassword', 'deviceAuthentication']) {
      if (!sameHost && (changes['secure'] as Map?)?[key] == null) secure.remove(key);
      if (sameHost && (changes['secure'] as Map?)?[key] == '' && (config.secure[key] as String?)?.isNotEmpty == true) {
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
    await _closeTaps();
    _setState('connecting');
    final link = _linkFactory(next);
    try {
      await link.connect();
      return link;
    } on Object catch (e) {
      await link.close();
      stdout.writeln('Neue Busverbindung nicht möglich: $e – bisherige bleibt');
      _restart();
      throw BusProbeException(linkText(e), problem: e is LinkException ? e.problem : null);
    }
  }

  /// Reconnects; [ready] is an already open connection (from [_probe]).
  void _restart({BusLink? ready}) {
    final generation = ++_generation;
    final old = _link;
    _link = null;
    if (old != null) unawaited(old.close());
    unawaited(_closeTaps());
    if (_yieldedTo != null || !_canConnect(config)) {
      if (ready != null) unawaited(ready.close());
      _setState(_yieldedTo != null ? 'yielded' : 'disconnected');
      return;
    }
    unawaited(_run(generation, ready: ready));
    _startTaps(generation);
  }

  /// Starts the further tap points of [config] (issue #8), each in its own reconnect loop.
  void _startTaps(int generation) {
    final taps = config.taps;
    _silence = TapSilence();
    final active = [
      for (final (i, t) in taps.indexed)
        if (t['paused'] != true) i + 1,
    ];
    _merger = active.isEmpty
        ? null
        : TapMerger(
            windows: {
              for (final (i, t) in taps.indexed)
                if (t['windowMs'] case final int ms) i + 1: Duration(milliseconds: ms),
            },
          );
    final merger = _merger;
    // Data Secure counts windows set by hand only, never the measured ones.
    secureTaps
      ..clear()
      ..windows = Map.of(merger?.windows ?? const <int, Duration>{});
    _autoWindows.clear();
    _meter = merger == null
        ? null
        : TapWindowMeter(
            current: (tap) => merger.windows[tap] ?? merger.window,
            auto: {
              0,
              for (final (i, t) in taps.indexed)
                if (t['windowMs'] == null) i + 1,
            },
          );
    _updateMergerTaps();
    for (final i in active) {
      unawaited(_runTap(generation, i, taps[i - 1]));
    }
  }

  Future<void> _closeTaps() async {
    final links = [..._tapLinks.values];
    _tapLinks.clear();
    _tapState.clear();
    _mergeFlush?.cancel();
    final m = _merger;
    if (m != null) {
      for (final t in m.flushAll()) {
        _processMerged(t);
      }
    }
    for (final l in links) {
      await l.close();
    }
  }

  /// Measures the lag between tap points and widens their windows ([TapWindowMeter]).
  TapWindowMeter? _meter;

  /// Windows widened by [_meter], by tap point (0 = main connection).
  final _autoWindows = <int, Duration>{};

  /// Tap points that say connected but hear nothing (routing without an IP router).
  TapSilence _silence = TapSilence();

  void _updateMergerTaps() {
    final m = _merger;
    if (m == null) return;
    // A tap point that hears nothing is not waited for: entries leave once the others saw them.
    m.taps =
        (state == 'connected' && !_silence.silent(0) ? 1 : 0) +
        _tapState.entries.where((t) => t.value['state'] == 'connected' && !_silence.silent(t.key)).length;
    if (m.taps < 1) m.taps = 1;
  }

  void _setTapState(int i, Map<String, Object?> next) {
    _tapState[i] = next;
    if (next['state'] == 'connected') {
      _silence.connected(i);
    } else {
      _silence.disconnected(i);
    }
    _updateMergerTaps();
    _broadcastState();
  }

  Future<void> _runTap(int generation, int i, Map<String, Object?> t) async {
    var failures = 0;
    var reported = false;
    var gapOpen = false;
    final mode = t['mode']! as String;
    final c = BusConfig(
      enabled: true,
      mode: mode,
      host: t['host']! as String,
      port: t['port']! as int,
      tunnelAddress: t['tunnelAddress'] as String?,
      routingAddress: config.routingAddress,
    );
    while (_current(generation)) {
      _setTapState(i, {'state': 'connecting'});
      final link = _linkFactory(c);
      try {
        await link.connect();
        if (!_current(generation)) {
          await link.close();
          return;
        }
        _tapLinks[i] = link;
        failures = 0;
        reported = false;
        final sub = link.frames.listen((f) => _onFrame(f, tap: i));
        _setTapState(i, {'state': 'connected', 'address': link.address});
        stdout.writeln('Messpunkt ${t['name']} verbunden: ${linkLabel(link.label)}');
        if (gapOpen) {
          gapOpen = false;
          unawaited(availability.connectionEvent(tap: '${t['name']}').catchError((Object _) {}));
        }
        final reason = await link.lost;
        await sub.cancel();
        if (!_current(generation)) return;
        _tapLinks.remove(i);
        stdout.writeln('Messpunkt ${t['name']} getrennt: ${linkText(reason)}');
        gapOpen = true;
        unawaited(
          availability.connectionEvent(reason: linkText(reason), tap: '${t['name']}').catchError((Object _) {}),
        );
        _setTapState(i, {'state': 'disconnected', 'error': linkText(reason)});
      } on Object catch (e) {
        await link.close();
        if (!_current(generation)) return;
        if (!reported) {
          stdout.writeln('Messpunkt ${t['name']} nicht erreichbar: $e – versuche weiter');
          reported = true;
          // Not reachable from the start (or again): a gap too, until it connects.
          if (!gapOpen) {
            gapOpen = true;
            unawaited(availability.connectionEvent(reason: linkText(e), tap: '${t['name']}').catchError((Object _) {}));
          }
        }
        _setTapState(i, {'state': 'disconnected', 'error': linkText(e)});
        final seconds = const [1, 2, 4, 8, 15, 30, 60][failures.clamp(0, 6)];
        failures++;
        await Future<void>.delayed(Duration(seconds: seconds));
      }
    }
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
      await _closeTaps();
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
        // The module counts its sequence number from the start again.
        busmon.resync();
        final sub = link.frames.listen(_onFrame);
        _setState('connected');
        stdout.writeln('Bus verbunden: ${linkLabel(link.label)}');
        if (lastLost != null) unawaited(availability.connectionEvent().catchError((Object _) {}));
        unawaited(_askTime(link));
        unawaited(_fillGap(link, generation));
        final reason = await link.lost;
        await sub.cancel();
        if (!_current(generation)) return;
        _link = null;
        lastLost = DateTime.now();
        error = linkText(reason);
        problem = null;
        stdout.writeln('Bus getrennt: $error');
        unawaited(availability.connectionEvent(reason: '${linkLabel(link.label)}: $error').catchError((Object _) {}));
        // Reconnect immediately – short dropouts should not leave a gap.
        continue;
      } on Object catch (e) {
        await link.close();
        if (!_current(generation)) return;
        error = linkText(e);
        problem = e is LinkException ? e.problem : (e is TimeoutException ? 'noResponse' : null);
        // Report an outage once, not on every attempt.
        if (!reported) {
          stdout.writeln('Bus nicht erreichbar: $e – versuche weiter');
          reported = true;
        }
        _setState('disconnected');
        final busy = e is LinkException && e.status == KnxIpStatus.noMoreConnections;
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
    _updateMergerTaps();
    _broadcastState();
    // Report only real changes, not every connection attempt.
    if (was != (next == 'connected')) {
      _fire(HomeAssistant.busEvent, {'connected': next == 'connected', 'state': next, 'reason': ?error});
    }
  }

  /// Mode `ha`: adds what Home Assistant recorded while the add-on was not
  /// listening (see ha_history.dart). Never affects the connection.
  Future<void> _fillGap(BusLink link, int generation) async {
    final store = switch (link) {
      ReadOnlyLink(:final telegramStore) => telegramStore,
      HaLink(:final store) => store,
      _ => null,
    };
    if (store == null) return;
    try {
      await fillFromHomeAssistant(store, recorder, settle: gapSettle);
    } on Object catch (e) {
      if (_current(generation)) stdout.writeln('Verlauf aus Home Assistant nicht nachgeladen: $e');
    }
  }

  /// Wait before filling the gap, see [fillFromHomeAssistant] (shorter in tests).
  Duration gapSettle = const Duration(seconds: 5);

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
  void _onFrame(Uint8List frame, {int tap = 0}) {
    if (_merger != null && _silence.heard(tap)) {
      _updateMergerTaps();
      _broadcastState();
    }
    try {
      _handleFrame(frame, tap: tap);
    } on Object catch (e) {
      stderr.writeln('Frame verworfen: $e');
    }
  }

  void _handleFrame(Uint8List frame, {int tap = 0}) {
    final now = clock?.now() ?? DateTime.now();
    // Further tap points (issue #8) as 0x04 with the tap number; older apps ignore it.
    final head = tap == 0 ? const [0x01] : [0x04, tap];
    for (final c in _clients) {
      c.send([...head, ...frame]);
    }
    var cemi = frame;
    if (tap == 0 && frame.isNotEmpty && frame[0] == 0x2B) {
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
    } else if (frame.isNotEmpty && frame[0] == 0x2B) {
      return;
    }
    // Record secured telegrams decrypted; the views get the original frame
    // and decrypt it themselves.
    final ds = _dataSecure;
    var plain = cemi;
    // Secured by the frame itself, whether or not a keyring can decrypt it.
    final secured = DataSecure.isSecure(cemi);
    var decryptedOk = false;
    if (ds != null && secured) {
      // Several tap points (issue #8): the identical frame from another tap point within the merge
      // window is a further sighting, everything else meets the replay check ([SecureTapCache]).
      final merging = _merger;
      final (result, decrypted) = merging == null ? ds.receive(cemi) : secureTaps.receive(ds, tap, cemi, at: now);
      decryptedOk = result == SecureResult.decrypted;
      // The counter is the same for a further sighting; noting it again changes nothing.
      if (decryptedOk) _noteSequence(cemi);
      plain = decrypted;
    }
    final merger = _merger;
    if (merger == null) {
      final line = telegramJson(plain, now);
      if (line != null) _process(line, now, secured: secured, decrypted: decryptedOk);
      return;
    }
    final t = Telegram.fromCemi(plain, time: now);
    // So the cache recognises it when the merger gives it back (first copy or further sighting).
    if (ds != null && secured) secureTaps.tag(t?.raw ?? const []);
    if (t == null) return;
    _secureOf[t.raw] = (secured, decryptedOk);
    final ready = merger.add(tap, t);
    for (final r in ready) {
      _processMerged(r);
    }
    // Never hold back without limit (clock set back, flood).
    if (_backlog.note(fed: 1, left: TapBacklog.leaving(ready), pending: merger.pending)) {
      for (final r in merger.flushAll()) {
        _processMerged(r);
      }
    }
    _scheduleMergeFlush();
  }

  void _scheduleMergeFlush() {
    _mergeFlush?.cancel();
    final due = _merger?.nextDue;
    if (due == null) return;
    var wait = due.difference(clock?.now() ?? DateTime.now());
    if (wait.isNegative) wait = Duration.zero;
    _mergeFlush = Timer(wait, () {
      final ready = _merger?.flush(clock?.now() ?? DateTime.now()) ?? const <Telegram>[];
      _backlog.note(left: TapBacklog.leaving(ready), pending: _merger?.pending ?? false);
      for (final t in ready) {
        _processMerged(t);
      }
      _scheduleMergeFlush();
    });
  }

  void _processMerged(Telegram t) {
    // A Data Secure copy that did not end up in the entry of its first copy is a replay: it must
    // not become an entry of its own (history, MQTT, alarms, watchers).
    if (!secureTaps.released(t.raw, merged: t.sightings.isNotEmpty)) {
      if (secureTaps.dropped == 1 || secureTaps.dropped % 100 == 0) {
        stderr.writeln('Data Secure: Kopie ohne ihr erstes Exemplar verworfen (${secureTaps.dropped})');
      }
      return;
    }
    if (_meter?.released(t) case (final tap, final window)?) {
      _merger?.windows[tap] = window;
      window > TapWindowMeter.floor ? _autoWindows[tap] = window : _autoWindows.remove(tap);
      stdout.writeln(
        'Messpunkt ${tap == 0 ? 'Hauptanschluss' : config.taps[tap - 1]['name']}: Zeitfenster jetzt ${window.inMilliseconds} ms (gemessener Versatz)',
      );
      _broadcastState();
    }
    try {
      final (secured, decrypted) = _secureOf[t.raw] ?? (false, false);
      _process(t.toJson(), t.time, secured: secured, decrypted: decrypted);
    } on Object catch (e) {
      stderr.writeln('Telegramm verworfen: $e');
    }
  }

  /// One telegram (merged if there are tap points) in history format: counters, clock, recorder,
  /// export, MQTT, fault hunt, alarms, watchers.
  void _process(Map<String, Object?> line, DateTime now, {required bool secured, required bool decrypted}) {
    final decryptedOk = decrypted;
    _beatCount++;
    lastTelegram = now;
    if (line['rp'] == true) repeats++;
    busy += busySeconds(line['x'] as String? ?? '', small: line['m'] == true);
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
    telegram?.call(line, secure: secured, decrypted: decryptedOk);
    unawaited(hunt.add(line, now).catchError((Object e) => stderr.writeln('Fehlerjagd: $e')));
    unawaited(alarms.check(line).catchError((Object e) => stderr.writeln('Alarm: $e')));
    // After the catalog: the datapoint types decide what is DALI.
    unawaited(
      alarms
          .loadCatalog()
          .then((_) => dali.check(line, secure: secured))
          .catchError((Object e) => stderr.writeln('DALI: $e')),
    );
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
    'features': features,
    'problem': ?problem,
    if (configLost) 'configLost': true,
    'restarts': ?restartSummary?.call(),
    'since': since?.millisecondsSinceEpoch,
    'lastLost': lastLost?.millisecondsSinceEpoch,
    'link': _link == null ? null : linkLabel(_link!.label),
    'address': _link?.address,
    if (_autoWindows[0] case final w? when config.taps.isNotEmpty) 'autoWindowMs': w.inMilliseconds,
    if (_meter?.lagOf(0) case final lag? when config.taps.isNotEmpty) 'lagUs': lag.inMicroseconds,
    if (config.taps.isNotEmpty)
      'taps': [
        for (final (i, t) in config.taps.indexed)
          {
            'name': t['name'],
            if (t['windowMs'] != null) 'windowMs': t['windowMs'],
            if (t['paused'] == true) 'paused': true,
            'state': t['paused'] == true ? 'paused' : (_tapState[i + 1]?['state'] ?? 'disconnected'),
            'error': ?_tapState[i + 1]?['error'],
            'address': ?_tapState[i + 1]?['address'],
            if (_silence.silent(i + 1)) 'silent': true,
            if (_autoWindows[i + 1] case final w?) 'autoWindowMs': w.inMilliseconds,
            if (_meter?.lagOf(i + 1) case final lag?) 'lagUs': lag.inMicroseconds,
          },
      ],
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
    final current = status();
    final message = [0x02, ...utf8.encode(jsonEncode(current))];
    List<int>? viewing;
    for (final c in _clients) {
      c.send(c.maySend ? message : (viewing ??= _statusFor(c, current)));
    }
  }

  /// A viewer sees read-only as on: the app then hides sending everywhere,
  /// as with [readOnly].
  static List<int> _statusFor(_Client client, Map<String, Object?> current) => [
    0x02,
    ...utf8.encode(jsonEncode(client.maySend ? current : {...current, 'readOnly': true, 'viewOnly': true})),
  ];

  /// Serves a browser tab until it closes.
  ///
  /// [admin]: device with full rights (add-on, box password). Otherwise it may
  /// only send group values ([deviceMaySend]) and not release the tunnel.
  /// Live views at once: each one gets every frame, and on a Pi memory and
  /// CPU belong to the recording first.
  static const maxClients = 64;

  /// Whether another live view fits (checked before the upgrade, see [serve]).
  bool get acceptsClient => _clients.length < maxClients;

  /// Largest message a view may send: a frame to send is a few dozen bytes.
  /// dart:io assembles a message completely before handing it over, so the
  /// connection is closed on the first one that is larger (1009, message too
  /// big) instead of collecting more of them. Compression is off at the
  /// upgrade ([webSocketCompression]): a small compressed message used to
  /// unpack into hundreds of megabytes.
  static const maxClientMessage = 64 * 1024;

  /// Whether [message] from a client exceeds [maxClientMessage].
  static bool tooLarge(Object? message) =>
      (message is List<int> && message.length > maxClientMessage) ||
      (message is String && message.length > maxClientMessage);

  /// [maySend] false: a device paired for viewing only ([BoxRole.viewer]).
  Future<void> serve(WebSocket ws, {bool admin = true, bool maySend = true}) async {
    if (_clients.length >= maxClients) {
      // 1013: try again later.
      await ws.close(1013, 'busy');
      return;
    }
    final client = _Client(ws, admin: admin, maySend: maySend);
    _clients.add(client);
    client.send(_statusFor(client, status()));
    try {
      await for (final message in ws) {
        if (tooLarge(message)) {
          await ws.close(WebSocketStatus.messageTooBig, 'too big');
          break;
        }
        if (message is List<int> && message.length >= 3 && message[0] == 0x10) {
          unawaited(_clientSend(client, (message[1] << 8) | message[2], Uint8List.fromList(message.sublist(3))));
        } else if (message is List<int> && message.length == 2 && message[0] == 0x12) {
          // Releasing disconnects continuous recording; that is reserved for admins.
          // Handing the connection over to the app's own tunnel lets it send: not for viewers.
          if (maySend && (admin || message[1] != 1)) unawaited(_yieldSafely(client, release: message[1] == 1));
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

  /// The connection that sends [cemi] (issue #8): access to an individual address goes over the
  /// tap point on the device's line (fewer coupler hops), everything else, and a device without a
  /// tap point on its line, over the main connection. `null` if that one is not connected. Every
  /// link comes from the same factory, so read-only ([ReadOnlyLink]) holds for each.
  BusLink? linkFor(Uint8List cemi) {
    final main = _link;
    final i = cemi.length < 2 ? 0 : 2 + cemi[1];
    if (cemi.length >= i + 6 && i >= 2 && cemi[i + 1] & 0x80 == 0) {
      final line = cemi[i + 4];
      bool onLine(BusLink? l) => l?.address != null && l!.address != 0 && l.address! >> 8 == line;
      if (!(main != null && state == 'connected' && onLine(main))) {
        for (final MapEntry(key: n, value: l) in _tapLinks.entries) {
          if (_tapState[n]?['state'] == 'connected' && onLine(l)) return l;
        }
      }
    }
    return main == null || state != 'connected' ? null : main;
  }

  /// Send results: 0 sent, 1 not connected, 2 connection error, 3 invalid
  /// frame, 4 device busy, 5 not allowed (only group values without admin
  /// rights, nothing at all for a viewer), 6 read-only is on. Never throws: an error here would end as an
  /// unhandled error in process exit (`exit(255)`), and any logged-in client
  /// could have sent recording into a restart loop that way.
  Future<void> _clientSend(_Client client, int id, Uint8List frame) async {
    var cemi = frame;
    void reply(int result, [String text = '']) => client.send([0x11, id >> 8, id & 0xFF, result, ...utf8.encode(text)]);

    try {
      // The role first: a viewer gets its own reason also on a read-only server.
      if (!client.maySend) return reply(5, 'Dieses Gerät ist nur zum Ansehen gekoppelt.');
      if (readOnly) return reply(6, readOnlyMessage);
      if (!isLDataRequest(cemi)) return reply(3, 'Ungültiger Frame');
      if (!client.admin && !deviceMaySend(cemi)) {
        return reply(5, 'Dieses Gerät darf nur Gruppenwerte senden. Mit dem Box-Passwort koppeln.');
      }
      if (!client.admin) cemi = normalizeDeviceCemi(cemi);
      final link = linkFor(cemi);
      if (link == null) return reply(1, 'Nicht verbunden');
      if (!_lockDevice(client, cemi)) return reply(4, 'Gerät wird gerade von einer anderen Ansicht geprüft');
      await link.send(cemi);
      reply(0);
    } on LinkException catch (e) {
      reply(2, linkText(e));
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
    if (_sequenceSave != null) await _saveSequences();
    await recorder.flush(durable: true);
    await hunt.close();
    await exporter.stop();
    await _link?.close();
    await _closeTaps();
  }
}

/// For every WebSocket upgrade of the server: without permessage-deflate (see
/// [BusService.maxClientMessage]).
const webSocketCompression = CompressionOptions.compressionOff;

/// Ping of `/ws` and `/ws/bus`: a client that no longer reads (or answers)
/// is closed after two intervals, instead of the server queueing the whole
/// bus traffic for it in memory.
const webSocketPing = Duration(seconds: 20);

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
  _Client(this.ws, {required this.admin, this.maySend = true});
  final WebSocket ws;
  final bool admin;
  final bool maySend;
  void send(List<int> bytes) {
    if (ws.readyState == WebSocket.open) ws.add(Uint8List.fromList(bytes));
  }
}
