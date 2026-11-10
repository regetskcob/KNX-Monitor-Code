import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'bus.dart';
import 'catalog_info.dart';
import 'exporter.dart';
import 'key_figures.dart';
import 'ha.dart';
import 'telegram_stream.dart';

/// Access to the MQTT broker as the Supervisor reports it under
/// `/services/mqtt` (usually the Mosquitto add-on).
class MqttBroker {
  const MqttBroker({required this.host, required this.port, this.username, this.password, this.ssl = false});

  final String host;
  final int port;
  final String? username;
  final String? password;
  final bool ssl;

  /// Broker from environment variables (Docker, without Supervisor): MQTT_HOST,
  /// MQTT_PORT (1883), MQTT_USER, MQTT_PASSWORD, MQTT_SSL (`true`).
  static MqttBroker? fromEnvironment(Map<String, String> env) {
    final host = env['MQTT_HOST'];
    if (host == null || host.isEmpty) return null;
    return MqttBroker(
      host: host,
      port: int.tryParse(env['MQTT_PORT'] ?? '') ?? 1883,
      username: env['MQTT_USER'],
      password: env['MQTT_PASSWORD'],
      ssl: env['MQTT_SSL'] == 'true',
    );
  }

  static MqttBroker? fromJson(Map<String, Object?> j) {
    final host = j['host'] as String?;
    if (host == null || host.isEmpty) return null;
    return MqttBroker(
      host: host,
      port: (j['port'] as num?)?.toInt() ?? 1883,
      username: j['username'] as String?,
      password: j['password'] as String?,
      ssl: j['ssl'] == true,
    );
  }
}

/// Asks the Supervisor for the MQTT broker; `null` without a broker or
/// without Supervisor (`services: mqtt:want` in config.yaml).
Future<MqttBroker?> brokerFromSupervisor({String? token, Uri? base}) async {
  token ??= Platform.environment['SUPERVISOR_TOKEN'];
  if (token == null) return null;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl((base ?? Uri.parse('http://supervisor/')).resolve('services/mqtt'));
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final res = await req.close().timeout(const Duration(seconds: 10));
    if (res.statusCode != HttpStatus.ok) {
      await res.drain<void>();
      return null;
    }
    final json = jsonDecode(await utf8.decodeStream(res)) as Map<String, Object?>;
    return MqttBroker.fromJson((json['data'] as Map?)?.cast<String, Object?>() ?? const {});
  } on Object catch (e) {
    stderr.writeln('MQTT-Broker beim Supervisor: $e');
    return null;
  } finally {
    client.close();
  }
}

/// Connection to the broker; replaceable so tests can run without a broker.
abstract interface class MqttSink {
  /// Connects with a "last will": if the connection drops, the broker sets
  /// [willTopic] to [willPayload].
  Future<void> connect({required String willTopic, required String willPayload});

  /// Sends [payload]; [atMostOnce] uses QoS 0 (the telegram stream), else QoS 1.
  void publish(String topic, String payload, {bool retain = false, bool atMostOnce = false});
  void subscribe(String topic);
  Stream<(String, String)> get messages;
  Future<void> close();
}

/// [MqttSink] using the mqtt_client package (MQTT 3.1.1, reconnects itself).
class MqttClientSink implements MqttSink {
  MqttClientSink(this.broker, {String clientId = 'knx-monitor'})
    : _client = MqttServerClient.withPort(broker.host, clientId, broker.port);

  final MqttBroker broker;
  final MqttServerClient _client;
  final _messages = StreamController<(String, String)>.broadcast();

  @override
  Future<void> connect({required String willTopic, required String willPayload}) async {
    _client
      ..secure = broker.ssl
      ..keepAlivePeriod = 60
      ..autoReconnect = true
      ..logging(on: false)
      ..connectionMessage = MqttConnectMessage()
          .withWillTopic(willTopic)
          .withWillMessage(willPayload)
          .withWillRetain()
          .withWillQos(MqttQos.atLeastOnce)
          .startClean()
          .authenticateAs(broker.username, broker.password);
    await _client.connect();
    _client.updates?.listen((batch) {
      for (final m in batch) {
        final message = m.payload;
        if (message is MqttPublishMessage) {
          _messages.add((m.topic, MqttPublishPayload.bytesToStringAsString(message.payload.message)));
        }
      }
    });
  }

  @override
  void publish(String topic, String payload, {bool retain = false, bool atMostOnce = false}) {
    final builder = MqttClientPayloadBuilder()..addUTF8String(payload);
    _client.publishMessage(
      topic,
      atMostOnce ? MqttQos.atMostOnce : MqttQos.atLeastOnce,
      builder.payload!,
      retain: retain,
    );
  }

  /// Whether the client is connected right now (between reconnects it is not).
  bool get isConnected => _client.connectionStatus?.state == MqttConnectionState.connected;

  @override
  void subscribe(String topic) => _client.subscribe(topic, MqttQos.atLeastOnce);

  @override
  Stream<(String, String)> get messages => _messages.stream;

  @override
  Future<void> close() async {
    _client.disconnect();
    await _messages.close();
  }
}

/// The add-on as the device "Busclear" in Home Assistant via MQTT discovery:
/// entities (bus connected, recording, telegrams per minute, …), event
/// entities for watchers and alarms, and device triggers for the automation
/// picker. Without a broker, events still come from [HomeAssistant].
///
/// Topics under [base]: `status` (online/offline, "last will"), `state`
/// (JSON, every [interval] and on changes), `recording/set` (switch),
/// `event/watcher`, `event/alarm`, `watcher/<id>`, `alarm/<typ>`,
/// `bus/connected` and `bus/disconnected`.
///
/// Key figures in the state come from data the server already has: bus load
/// from the estimated occupancy per telegram ([BusService.busy]), open and last
/// alarms from [AlarmWatch], history size and free space from the [Recorder],
/// availability over 24 hours from the heartbeats ([Availability.ratio]).
class MqttBridge {
  MqttBridge(
    this.currentBus, {
    required this.version,
    MqttSink Function(MqttBroker broker)? sink,
    Future<MqttBroker?> Function()? broker,
    this.interval = const Duration(seconds: 60),
    this.retry = const Duration(minutes: 5),
    bool discovery = true,
    this.telegrams,
    this.installation,
    String? boot,
    DateTime Function() clock = DateTime.now,
  }) : _clock = clock,
       boot = boot ?? uuidV4(),
       _catalog = CatalogInfo(clock: clock),
       _sinkFactory = sink ?? MqttClientSink.new,
       _broker = broker ?? brokerFromSupervisor,
       _discoveryOn = discovery,
       _figures = KeyFigures(currentBus, clock: clock);

  /// Bus of the active installation (changes with the installation).
  final BusService Function() currentBus;
  final String version;
  final Duration interval;
  final Duration retry;

  /// Every telegram to `knx_monitor/telegram/…` (issue #11); `null` = off.
  /// Switched on by the add-on option `mqtt_telegrams` or MQTT_TELEGRAMS=true.
  final TelegramStream? telegrams;

  /// Installation id in the stream's payload (`inst`); `null` = the active
  /// installation's id (MQTT_INSTALLATION overrides it).
  final String? installation;

  /// Random id of this server start (`boot` in the stream): a new value tells
  /// a database that [telegramSeq] starts over, which is not a gap.
  final String boot;

  /// Running number of the last telegram that passed the filters and was due
  /// to be sent (`seq`); a dropped one (rate limit, broker down) leaves a gap.
  int telegramSeq = 0;

  /// Device names and project state for the stream, from the active
  /// installation's catalog.
  final CatalogInfo _catalog;

  /// Telegrams sent to the broker since the start.
  int telegramsSent = 0;

  /// Telegrams not sent because the broker was not connected or refused them.
  /// Nothing is replayed; the history and the ETS file have them.
  int telegramsDropped = 0;

  Map<String, Object?>? _lastTelegram;

  /// Last values sent to `knx_monitor/value/…` ([TelegramStream.retainValues]).
  int valuesSent = 0;

  /// Group address → payload (hex) last sent to its value topic, for the bus
  /// in [_valuesOf]; a new installation starts empty.
  final _lastValues = <int, String>{};
  BusService? _valuesOf;

  /// Upper limit of telegrams sent per second. A TP line carries about 50; the
  /// cap keeps a flood (forged routing frames, a looping device) from filling
  /// the broker connection's send buffer. Beyond it telegrams count as dropped.
  static const maxTelegramsPerSecond = 500;

  final DateTime Function() _clock;
  int _second = 0;
  int _inSecond = 0;

  /// Secured telegrams left out because sending them is not switched on.
  int telegramsSecureSkipped = 0;

  /// Secured telegrams left out because the server could not decrypt them
  /// (no keyring, wrong key, invalid MAC, replay).
  int telegramsUndecrypted = 0;

  /// Group addresses already named in the log per reason, so the log says it
  /// once per address instead of on every telegram (at most [_maxNoted]).
  final _noted = <String>{};
  static const _maxNoted = 200;

  /// Last telegram sent as topic and payload (for the example in the docs and
  /// for diagnosis); `null` before the first one.
  Map<String, Object?>? get lastTelegram => _lastTelegram;

  /// Whether to send Home Assistant discovery; off (MQTT_DISCOVERY=false) for
  /// systems like ioBroker that would only create superfluous data points
  /// from it, and while the Busclear integration provides the entities
  /// (ha_integration.dart). State, single values and events are sent regardless.
  bool get discovery => _discoveryOn;
  bool _discoveryOn;

  /// Switches discovery on or off while running: off clears this device's
  /// announcements (retained, delivered again on subscribe), on announces it.
  Future<void> setDiscovery(bool on) async {
    if (on == _discoveryOn) return;
    _discoveryOn = on;
    final sink = _sink;
    if (sink == null) return;
    if (on) {
      await announce();
    } else {
      sink.subscribe('$_discovery/+/$_device/+/config');
    }
  }

  final MqttSink Function(MqttBroker broker) _sinkFactory;
  final Future<MqttBroker?> Function() _broker;
  final KeyFigures _figures;

  static const base = 'knx_monitor';
  static const _discovery = 'homeassistant';
  static const _device = 'knx_monitor';
  static const alarmTriggers = ['alarm_on', 'alarm_off', 'fault_on', 'fault_off'];

  /// Device triggers on a change of the bus connection; topics
  /// `bus/connected` and `bus/disconnected`.
  static const busTriggers = ['bus_connected', 'bus_disconnected'];

  MqttSink? _sink;
  Timer? _timer;
  bool _stopped = false;
  final _watcherTriggers = <String>{};

  bool get connected => _sink != null;

  /// Looks up the broker and connects; without a broker, retries after [retry].
  Future<void> start() async {
    while (!_stopped && _sink == null) {
      final broker = await _broker();
      if (broker != null) {
        final sink = _sinkFactory(broker);
        try {
          await sink.connect(willTopic: '$base/status', willPayload: 'offline');
          _sink = sink;
          stdout.writeln('MQTT verbunden: ${broker.host}:${broker.port}');
          break;
        } on Object catch (e) {
          stderr.writeln('MQTT nicht erreichbar: $e');
        }
      }
      await Future<void>.delayed(retry);
    }
    final sink = _sink;
    if (sink == null) return;
    sink.messages.listen((m) => _settled = Future.wait([_settled, _onMessage(m)]).then((_) {}));
    sink.subscribe('$base/recording/set');
    // Home Assistant restarted: announce everything again.
    sink.subscribe('$_discovery/status');
    // Discovery off: the broker delivers earlier retained announcements of this
    // device on subscribe; each one is cleared (including those of long-deleted
    // watchers), otherwise Home Assistant keeps building the entities.
    if (!discovery) sink.subscribe('$_discovery/+/$_device/+/config');
    await _figures.measure();
    await announce();
    _timer = Timer.periodic(interval, (_) => unawaited(tick()));
  }

  Future<void> stop() async {
    _stopped = true;
    _timer?.cancel();
    final sink = _sink;
    _sink = null;
    if (sink != null) {
      sink.publish('$base/status', 'offline', retain: true);
      await sink.close();
    }
  }

  /// Event from the [BusService] (same data as for [HomeAssistant]).
  void onEvent(String type, Map<String, Object?> data) {
    final sink = _sink;
    if (sink == null) return;
    switch (type) {
      case HomeAssistant.watcherEvent:
        sink.publish('$base/event/watcher', jsonEncode({'event_type': 'fired', ...data}));
        if (data['watcher_id'] case final String id) sink.publish('$base/watcher/${_safe(id)}', jsonEncode(data));
      case HomeAssistant.alarmEvent:
        final trigger = '${data['kind'] == 'fault' ? 'fault' : 'alarm'}_${data['active'] == true ? 'on' : 'off'}';
        sink.publish('$base/event/alarm', jsonEncode({'event_type': trigger, ...data}));
        sink.publish('$base/alarm/$trigger', jsonEncode(data));
        _publishState();
      case HomeAssistant.busEvent:
        sink.publish('$base/bus/${data['connected'] == true ? 'connected' : 'disconnected'}', jsonEncode(data));
        _publishState();
    }
  }

  /// Telegram line in history format from the bus of the active installation
  /// ([BusService] calls it for every group telegram). Never throws.
  /// [secure]: a KNX Data Secure telegram (see [TelegramStream.secure]);
  /// [decrypted]: the server could decrypt it. A secured telegram that could
  /// not be decrypted (no key, invalid MAC, replay) is never sent: it would
  /// carry ciphertext under the "secure" marker that promises decrypted data.
  void onTelegram(Map<String, Object?> line, ExportSource source, {bool secure = false, bool decrypted = false}) {
    final stream = telegrams;
    if (stream == null) return;
    // Filtered out: as if it had never been there, not counted anywhere.
    if (line['d'] case final int group when !stream.accepts(group)) return;
    if (secure && !decrypted) {
      telegramsUndecrypted++;
      _note('undecrypted', line);
      return;
    }
    if (secure && !stream.secure) {
      telegramsSecureSkipped++;
      _note('secure', line);
      return;
    }
    try {
      final bus = _bus();
      if (bus != null) _catalog.poll(bus.data);
      final meta = TelegramMeta(
        seq: telegramSeq + 1,
        boot: boot,
        installation: installation ?? bus?.installation?['id'] as String?,
        project: _catalog.project,
        deviceName: _catalog.deviceName,
        tapNames: switch (bus?.config.taps) {
          final taps? when taps.isNotEmpty => [
            'main',
            for (final (i, t) in taps.indexed)
              t['name'] is String && (t['name'] as String).isNotEmpty ? t['name'] as String : 'tap ${i + 1}',
          ],
          _ => null,
        },
      );
      final message = stream.message(line, source, secure: secure, meta: meta);
      if (message == null) return;
      telegramSeq++;
      final second = _clock().millisecondsSinceEpoch ~/ 1000;
      if (second != _second) {
        _second = second;
        _inSecond = 0;
      }
      if (++_inSecond > maxTelegramsPerSecond) {
        telegramsDropped++;
        return;
      }
      final sink = _sink;
      if (sink == null || (sink is MqttClientSink && !sink.isConnected)) {
        telegramsDropped++;
        return;
      }
      final (topic, payload) = message;
      sink.publish(topic, payload, atMostOnce: true);
      telegramsSent++;
      _lastTelegram = {'topic': topic, 'payload': payload};
      if (stream.retainValues) _retainValue(stream, bus, line, payload, sink);
    } on Object catch (_) {
      // A broker hiccup must not disturb the recording.
      telegramsDropped++;
    }
  }

  /// "Keep last value": [payload] once more, retained, to the value topic of
  /// the address, if the telegram carries a value that differs from the last
  /// one sent there. Read requests carry none.
  void _retainValue(TelegramStream stream, BusService? bus, Map<String, Object?> line, String payload, MqttSink sink) {
    final group = line['d'];
    final type = line['y'];
    if (group is! int || type is! int || type == 0) return;
    if (!identical(bus, _valuesOf)) {
      _valuesOf = bus;
      _lastValues.clear();
    }
    final value = '${line['m'] == true ? 's' : ''}${line['x'] ?? ''}';
    if (_lastValues[group] == value) return;
    _lastValues[group] = value;
    sink.publish(stream.valueTopic(group), payload, retain: true);
    valuesSent++;
  }

  /// The active bus, `null` where there is none (tests).
  BusService? _bus() {
    try {
      return currentBus();
    } on Object {
      return null;
    }
  }

  /// Random UUID version 4 (RFC 9562).
  static String uuidV4([Random? random]) {
    final r = random ?? Random.secure();
    final b = [for (var i = 0; i < 16; i++) r.nextInt(256)];
    b[6] = (b[6] & 0x0F) | 0x40;
    b[8] = (b[8] & 0x3F) | 0x80;
    final h = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Tells the user once per group address and reason why a telegram stays
  /// off the broker (add-on log, `docker logs`, box journal).
  void _note(String reason, Map<String, Object?> line) {
    final group = line['d'];
    if (group is! int || _noted.length >= _maxNoted) return;
    final ga = TelegramStream.formatGroup3(group);
    if (!_noted.add('$reason $ga')) return;
    stdout.writeln(switch (reason) {
      'secure' =>
        'MQTT: KNX-Secure-Telegramm an $ga nicht gesendet. Secure-Telegramme gehen nur mit der '
            'Option „Auch KNX-Secure-Telegramme an MQTT“ (MQTT_SECURE_TELEGRAMS=true) an den Broker, '
            'dort sind sie Klartext.',
      _ =>
        'MQTT: KNX-Secure-Telegramm an $ga nicht gesendet, weil es sich nicht entschlüsseln ließ '
            '(kein Keyring, Schlüssel fehlt oder ungültig). Keyring aus der ETS in der App unter Projekt › '
            'KNX Secure importieren.',
    });
  }

  /// State of the telegram stream for the app (`GET /api/export`,
  /// [DataExporter.mqttTelegrams]); `null` while the stream is off.
  Map<String, Object?> telegramStatus() => {
    'enabled': telegrams != null,
    if (telegrams case final t?) ...{
      'connected': connected,
      'secure': t.secure,
      'repeats': t.repeats,
      'raw': t.raw,
      'rawOnly': t.rawOnly,
      'retainValues': t.retainValues,
      'valuesSent': valuesSent,
      'filter': t.filter.text,
      'boot': boot,
      'seq': telegramSeq,
      'sent': telegramsSent,
      'dropped': telegramsDropped,
      'secureSkipped': telegramsSecureSkipped,
      'undecrypted': telegramsUndecrypted,
    },
  };

  Future<void> _onMessage((String, String) m) async {
    final (topic, payload) = m;
    if (topic == '$base/recording/set') {
      // Only ON and OFF: anything else used to switch the recording off. Every change is logged,
      // because anyone on the broker can send it (security review, 07.11.).
      final command = payload.trim().toUpperCase();
      if (command != 'ON' && command != 'OFF') {
        stderr.writeln('MQTT: recording/set mit "$command" ignoriert (nur ON oder OFF)');
        return;
      }
      stdout.writeln('MQTT: Aufzeichnung über recording/set ${command == 'ON' ? 'eingeschaltet' : 'ausgeschaltet'}');
      await currentBus().update({'enabled': command == 'ON'});
      _publishState();
    } else if (topic == '$_discovery/status' && payload.trim() == 'online') {
      await announce();
    } else if (!discovery && payload.isNotEmpty && _ownDiscovery.hasMatch(topic)) {
      _sink?.publish(topic, '', retain: true);
    }
  }

  /// Updates the counters, sends the state and syncs the watchers' device
  /// triggers (the app can change rules at any time).
  Future<void> tick() async {
    _figures.count();
    await _figures.measure();
    _publishState();
    await _syncWatcherTriggers();
  }

  void _publishState() {
    final sink = _sink;
    if (sink == null) return;
    final state = {
      ..._figures.state(),
      // Telegram stream (issue #11): counters for systems without the app.
      if (telegrams != null) ...{
        'telegrams_sent': telegramsSent,
        'telegrams_dropped': telegramsDropped,
        'telegrams_secure_skipped': telegramsSecureSkipped,
        'telegrams_undecrypted': telegramsUndecrypted,
      },
    };
    sink.publish('$base/state', jsonEncode(state), retain: true);
    // The same values individually, for systems without Home Assistant
    // discovery (ioBroker creates one data point per topic). Only on change.
    for (final MapEntry(:key, :value) in state.entries) {
      final text = value == null ? '' : '$value';
      if (_flat[key] == text) continue;
      _flat[key] = text;
      sink.publish('$base/$key', text, retain: true);
    }
  }

  Future<void> _settled = Future.value();

  /// Completes once all messages received so far are processed (switch,
  /// re-announcement); tests wait for it.
  Future<void> get settled => _settled;

  final _flat = <String, String>{};

  /// Announces device, entities and device triggers (discovery, retained).
  Future<void> announce() async {
    final sink = _sink;
    if (sink == null) return;
    if (!discovery) {
      sink.publish('$base/status', 'online', retain: true);
      _publishState();
      return;
    }
    final t = currentBus().config.language.startsWith('de') ? _de : _en;
    final device = {
      'identifiers': [_device],
      'name': 'Busclear',
      'manufacturer': 'regetskcob',
      'model': 'Home Assistant add-on',
      'sw_version': version,
    };
    final common = {'device': device, 'availability_topic': '$base/status', 'state_topic': '$base/state'};
    void entity(String component, String key, Map<String, Object?> config) => sink.publish(
      '$_discovery/$component/$_device/$key/config',
      jsonEncode({...common, 'unique_id': '${_device}_$key', ...config}),
      retain: true,
    );

    entity('binary_sensor', 'bus_connected', {
      'name': t['bus_connected'],
      'device_class': 'connectivity',
      'value_template': "{{ 'ON' if value_json.connected else 'OFF' }}",
    });
    entity('switch', 'recording', {
      'name': t['recording'],
      'icon': 'mdi:record-rec',
      'command_topic': '$base/recording/set',
      'value_template': "{{ 'ON' if value_json.recording else 'OFF' }}",
    });
    entity('sensor', 'telegrams_per_minute', {
      'name': t['per_minute'],
      'icon': 'mdi:swap-horizontal',
      'unit_of_measurement': t['per_minute_unit'],
      'state_class': 'measurement',
      'value_template': '{{ value_json.per_minute }}',
    });
    entity('sensor', 'repeats_per_minute', {
      'name': t['repeats'],
      'icon': 'mdi:repeat',
      'unit_of_measurement': t['per_minute_unit'],
      'state_class': 'measurement',
      'entity_category': 'diagnostic',
      'value_template': '{{ value_json.repeats_per_minute }}',
    });
    entity('sensor', 'telegrams_today', {
      'name': t['today'],
      'icon': 'mdi:counter',
      'state_class': 'total_increasing',
      'value_template': '{{ value_json.today }}',
    });
    entity('sensor', 'last_telegram', {
      'name': t['last'],
      'device_class': 'timestamp',
      'entity_category': 'diagnostic',
      'value_template': '{{ value_json.last }}',
    });
    entity('sensor', 'bus_load', {
      'name': t['bus_load'],
      'icon': 'mdi:gauge',
      'unit_of_measurement': '%',
      'state_class': 'measurement',
      'suggested_display_precision': 1,
      'value_template': '{{ value_json.bus_load }}',
    });
    entity('sensor', 'open_alarms', {
      'name': t['open_alarms'],
      'icon': 'mdi:alarm-light',
      'state_class': 'measurement',
      'value_template': '{{ value_json.open_alarms }}',
    });
    entity('sensor', 'last_alarm', {
      'name': t['last_alarm'],
      'icon': 'mdi:alert',
      'value_template': '{{ value_json.last_alarm }}',
      'json_attributes_topic': '$base/state',
      'json_attributes_template':
          '{{ {"kind": value_json.last_alarm_kind, "address": value_json.last_alarm_address, '
          '"time": value_json.last_alarm_time} | tojson }}',
    });
    entity('sensor', 'last_alarm_time', {
      'name': t['last_alarm_time'],
      'device_class': 'timestamp',
      'value_template': '{{ value_json.last_alarm_time }}',
    });
    entity('sensor', 'availability_24h', {
      'name': t['availability'],
      'icon': 'mdi:lan-check',
      'unit_of_measurement': '%',
      'state_class': 'measurement',
      'suggested_display_precision': 1,
      'value_template': '{{ value_json.availability_24h }}',
    });
    entity('sensor', 'history_size', {
      'name': t['history_size'],
      'device_class': 'data_size',
      'unit_of_measurement': 'MB',
      'state_class': 'measurement',
      'suggested_display_precision': 1,
      'entity_category': 'diagnostic',
      'value_template': '{{ value_json.history_mb }}',
    });
    entity('sensor', 'free_space', {
      'name': t['free_space'],
      'device_class': 'data_size',
      'unit_of_measurement': 'MB',
      'state_class': 'measurement',
      'suggested_display_precision': 0,
      'entity_category': 'diagnostic',
      'value_template': '{{ value_json.free_mb }}',
    });
    entity('binary_sensor', 'low_space', {
      'name': t['low_space'],
      'device_class': 'problem',
      'entity_category': 'diagnostic',
      'value_template': "{{ 'ON' if value_json.low_space else 'OFF' }}",
    });
    // Event entities have their own topic, not the state.
    for (final (key, types) in [
      ('watcher', ['fired']),
      ('alarm', alarmTriggers),
    ]) {
      sink.publish(
        '$_discovery/event/$_device/$key/config',
        jsonEncode({
          'device': device,
          'availability_topic': '$base/status',
          'unique_id': '${_device}_${key}_event',
          'name': t['${key}_event'],
          'icon': key == 'watcher' ? 'mdi:bell-ring' : 'mdi:alarm-light',
          'state_topic': '$base/event/$key',
          'event_types': types,
        }),
        retain: true,
      );
    }
    for (final trigger in alarmTriggers) {
      _trigger(
        'alarm_$trigger',
        topic: '$base/alarm/$trigger',
        type: trigger,
        subtype: t['alarm_subtype']!,
        device: device,
      );
    }
    for (final trigger in busTriggers) {
      _trigger(
        trigger,
        topic: '$base/bus/${trigger.substring(4)}',
        type: trigger,
        subtype: t['bus_subtype']!,
        device: device,
      );
    }
    sink.publish('$base/status', 'online', retain: true);
    _watcherTriggers.clear();
    await _syncWatcherTriggers(force: true);
    _publishState();
  }

  void _trigger(
    String key, {
    required String topic,
    required String type,
    required String subtype,
    required Map<String, Object?> device,
  }) => _sink?.publish(
    '$_discovery/device_automation/$_device/$key/config',
    jsonEncode({'automation_type': 'trigger', 'topic': topic, 'type': type, 'subtype': subtype, 'device': device}),
    retain: true,
  );

  /// One device trigger per watcher; deleted watchers disappear again (empty
  /// retained message on their discovery topic).
  Future<void> _syncWatcherTriggers({bool force = false}) async {
    final sink = _sink;
    if (sink == null || !discovery) return;
    final rules = await currentBus().watchers.rules();
    final keys = {for (final r in rules) _safe(r.id)};
    final device = {
      'identifiers': [_device],
    };
    for (final r in rules) {
      final key = _safe(r.id);
      if (!force && _watcherTriggers.contains(key)) continue;
      _trigger('watcher_$key', topic: '$base/watcher/$key', type: 'watcher_fired', subtype: r.name, device: device);
    }
    for (final gone in _watcherTriggers.difference(keys)) {
      sink.publish('$_discovery/device_automation/$_device/watcher_$gone/config', '', retain: true);
    }
    _watcherTriggers
      ..clear()
      ..addAll(keys);
  }

  /// Ids from the app for topics: only letters, digits, _ and -.
  static final _ownDiscovery = RegExp('^$_discovery/[^/]+/$_device/[^/]+/config\$');

  static String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static const _de = {
    'bus_connected': 'Bus verbunden',
    'recording': 'Aufzeichnung',
    'per_minute': 'Telegramme pro Minute',
    'per_minute_unit': 'Telegramme/min',
    'repeats': 'Wiederholungen pro Minute',
    'today': 'Telegramme heute',
    'last': 'Letztes Telegramm',
    'watcher_event': 'Wächter',
    'alarm_event': 'Alarm',
    'alarm_subtype': 'beliebige Adresse',
    'bus_load': 'Buslast',
    'open_alarms': 'Offene Alarme',
    'last_alarm': 'Letzter Alarm',
    'last_alarm_time': 'Letzter Alarm (Zeit)',
    'availability': 'Verfügbarkeit 24 h',
    'history_size': 'Verlauf belegt',
    'free_space': 'Freier Speicher',
    'low_space': 'Speicher knapp',
    'bus_subtype': 'KNX-Bus',
  };

  static const _en = {
    'bus_connected': 'Bus connected',
    'recording': 'Recording',
    'per_minute': 'Telegrams per minute',
    'per_minute_unit': 'telegrams/min',
    'repeats': 'Repeats per minute',
    'today': 'Telegrams today',
    'last': 'Last telegram',
    'watcher_event': 'Watcher',
    'alarm_event': 'Alarm',
    'alarm_subtype': 'any address',
    'bus_load': 'Bus load',
    'open_alarms': 'Open alarms',
    'last_alarm': 'Last alarm',
    'last_alarm_time': 'Last alarm time',
    'availability': 'Availability 24 h',
    'history_size': 'History size',
    'free_space': 'Free space',
    'low_space': 'Low space',
    'bus_subtype': 'KNX bus',
  };
}
