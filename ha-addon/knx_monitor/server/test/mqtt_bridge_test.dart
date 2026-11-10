import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

/// Broker zum Mitschreiben: gespeicherte Nachrichten wie beim echten Broker.
class FakeSink implements MqttSink {
  final published = <(String, String, bool)>[];
  final subscribed = <String>[];
  final retained = <String, String>{};

  /// Topics sent with QoS 0 (the telegram stream).
  final atMostOnce = <String>[];
  (String, String)? will;
  final _messages = StreamController<(String, String)>.broadcast();

  @override
  Future<void> connect({required String willTopic, required String willPayload}) async =>
      will = (willTopic, willPayload);

  @override
  void publish(String topic, String payload, {bool retain = false, bool atMostOnce = false}) {
    published.add((topic, payload, retain));
    if (retain) retained[topic] = payload;
    if (atMostOnce) this.atMostOnce.add(topic);
  }

  @override
  void subscribe(String topic) => subscribed.add(topic);

  @override
  Stream<(String, String)> get messages => _messages.stream;

  void receive(String topic, String payload) => _messages.add((topic, payload));

  Map<String, Object?> json(String topic) => jsonDecode(retained[topic]!) as Map<String, Object?>;

  List<Map<String, Object?>> sent(String topic) => [
    for (final p in published)
      if (p.$1 == topic) jsonDecode(p.$2) as Map<String, Object?>,
  ];

  @override
  Future<void> close() => _messages.close();
}

/// Wartet, bis [condition] gilt (statt fester Pausen, die auf langsamen
/// CI-Rechnern zu kurz sind); nach [timeout] scheitert der Test.
Future<void> until(bool Function() condition, {Duration timeout = const Duration(seconds: 5)}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) fail('Bedingung nach ${timeout.inSeconds} s nicht erfüllt');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late Directory data;
  late BusService bus;
  late FakeSink sink;
  late MqttBridge bridge;
  var now = DateTime(2026, 10, 25, 12);

  Future<void> rules(List<(String, String)> list) async {
    final file = File('${data.path}/watch_rules.json');
    await file.writeAsString(
      jsonEncode({
        'rules': [
          for (final (id, name) in list)
            {
              'id': id,
              'address': 0x0A03,
              'label': '1/2/3 $name',
              'name': name,
              'check': {'any': true},
            },
        ],
      }),
    );
    // Neue Änderungszeit, sonst liest der Wächter die Datei nicht neu.
    await file.setLastModified(DateTime.now().add(Duration(seconds: list.length)));
  }

  setUp(() async {
    data = await Directory.systemTemp.createTemp('knx_mqtt');
    bus = BusService(data, describe: (_, _) async => null, installation: {'id': 'a', 'name': 'Zuhause'});
    await bus.start();
    sink = FakeSink();
    now = DateTime(2026, 10, 25, 12);
    bridge = MqttBridge(
      () => bus,
      version: '1.8.0',
      sink: (_) => sink,
      broker: () async => const MqttBroker(host: 'core-mosquitto', port: 1883),
      clock: () => now,
      interval: const Duration(hours: 1),
    );
  });

  tearDown(() async {
    await bridge.stop();
    await bus.shutdown();
    await data.delete(recursive: true);
  });

  test('integration takes over: announcements are cleared, and come back', () async {
    await bridge.start();
    const config = 'homeassistant/sensor/knx_monitor/bus_load/config';
    expect(sink.retained[config], isNotEmpty);
    await bridge.setDiscovery(false);
    expect(sink.subscribed, contains('homeassistant/+/knx_monitor/+/config'));
    // The broker delivers the retained announcement on subscribe; it is cleared.
    sink.receive(config, sink.retained[config]!);
    await until(() => sink.retained[config] == '');
    await bridge.settled;
    expect(sink.retained['knx_monitor/state'], isNotNull, reason: 'state keeps going');
    await bridge.setDiscovery(true);
    expect(jsonDecode(sink.retained[config]!), isA<Map<String, Object?>>());
  });

  test('kündigt Gerät, Entitäten und Gerätetrigger an', () async {
    await rules([('wind', 'Wind'), ('tuer', 'Haustür')]);
    await bridge.start();
    expect(sink.will, ('knx_monitor/status', 'offline'));
    expect(sink.retained['knx_monitor/status'], 'online');
    expect(sink.subscribed, containsAll(['knx_monitor/recording/set', 'homeassistant/status']));

    final connected = sink.json('homeassistant/binary_sensor/knx_monitor/bus_connected/config');
    expect(connected['unique_id'], 'knx_monitor_bus_connected');
    expect(connected['device_class'], 'connectivity');
    expect((connected['device']! as Map)['sw_version'], '1.8.0');
    expect(connected['name'], 'Bus verbunden');
    for (final topic in [
      'homeassistant/switch/knx_monitor/recording/config',
      'homeassistant/sensor/knx_monitor/telegrams_per_minute/config',
      'homeassistant/sensor/knx_monitor/repeats_per_minute/config',
      'homeassistant/sensor/knx_monitor/telegrams_today/config',
      'homeassistant/sensor/knx_monitor/last_telegram/config',
      'homeassistant/event/knx_monitor/watcher/config',
      'homeassistant/event/knx_monitor/alarm/config',
      for (final t in MqttBridge.alarmTriggers) 'homeassistant/device_automation/knx_monitor/alarm_$t/config',
    ]) {
      expect(sink.retained, contains(topic));
    }
    final wind = sink.json('homeassistant/device_automation/knx_monitor/watcher_wind/config');
    expect(wind['topic'], 'knx_monitor/watcher/wind');
    expect(wind['subtype'], 'Wind');
    expect(sink.retained, contains('homeassistant/device_automation/knx_monitor/watcher_tuer/config'));

    final state = sink.json('knx_monitor/state');
    expect(state['connected'], isFalse);
    expect(state['recording'], isFalse);
    expect(state['installation'], 'Zuhause');
  });

  test('gelöschter Wächter verschwindet, neuer kommt dazu', () async {
    await rules([('wind', 'Wind'), ('tuer', 'Haustür')]);
    await bridge.start();
    await rules([('wind', 'Wind'), ('regen', 'Regen')]);
    await bridge.tick();
    expect(sink.retained['homeassistant/device_automation/knx_monitor/watcher_tuer/config'], '');
    expect(sink.json('homeassistant/device_automation/knx_monitor/watcher_regen/config')['subtype'], 'Regen');
  });

  test('Ereignisse: Wächter, Alarm, Bus', () async {
    await bridge.start();
    bridge.onEvent(HomeAssistant.watcherEvent, {'watcher_id': 'wind', 'name': 'Wind', 'address': '1/2/3'});
    expect(sink.sent('knx_monitor/event/watcher').single['event_type'], 'fired');
    expect(sink.sent('knx_monitor/watcher/wind').single['name'], 'Wind');

    bridge.onEvent(HomeAssistant.alarmEvent, {'kind': 'fault', 'active': true, 'address': '1/0/1'});
    expect(sink.sent('knx_monitor/event/alarm').single['event_type'], 'fault_on');
    expect(sink.sent('knx_monitor/alarm/fault_on'), hasLength(1));

    final before = sink.sent('knx_monitor/state').length;
    bridge.onEvent(HomeAssistant.busEvent, {'connected': false});
    expect(sink.sent('knx_monitor/state').length, before + 1);
  });

  test('Schalter Aufzeichnung', () async {
    await bridge.start();
    sink.receive('knx_monitor/recording/set', 'ON');
    await until(() => sink.json('knx_monitor/state')['recording'] == true);
    expect(bus.config.enabled, isTrue);
    sink.receive('knx_monitor/recording/set', 'OFF');
    await until(() => sink.json('knx_monitor/state')['recording'] == false);
    await bridge.settled;
    expect(bus.config.enabled, isFalse);
  });

  test('Schalter Aufzeichnung: nur ON und OFF, alles andere ändert nichts', () async {
    await bridge.start();
    sink.receive('knx_monitor/recording/set', 'ON');
    await until(() => sink.json('knx_monitor/state')['recording'] == true);
    for (final junk in ['', 'off please', '0', 'false', '{"state":"OFF"}']) {
      sink.receive('knx_monitor/recording/set', junk);
    }
    await bridge.settled;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(bus.config.enabled, isTrue);
  });

  test('Home Assistant neu gestartet: alles erneut ankündigen', () async {
    await bridge.start();
    final before = sink.published.length;
    sink.receive('homeassistant/status', 'online');
    await until(
      () => sink.published
          .skip(before)
          .any((p) => p.$1 == 'homeassistant/binary_sensor/knx_monitor/bus_connected/config'),
    );
    await bridge.settled;
  });

  test('Telegramme und Wiederholungen pro Minute', () async {
    await bridge.start();
    await bridge.tick(); // Ausgangspunkt
    bus
      ..today += 30
      ..repeats += 3;
    now = now.add(const Duration(minutes: 2));
    await bridge.tick();
    final state = sink.json('knx_monitor/state');
    expect(state['per_minute'], 15.0);
    expect(state['repeats_per_minute'], 1.5);
    // Tageswechsel: kein negativer Wert.
    bus.today = 0;
    now = now.add(const Duration(minutes: 1));
    await bridge.tick();
    expect(sink.json('knx_monitor/state')['per_minute'], 0.0);
  });

  test('Kennzahlen: Entitäten mit Einheit, Klasse und Kategorie', () async {
    await bridge.start();
    Map<String, Object?> config(String component, String key) =>
        sink.json('homeassistant/$component/knx_monitor/$key/config');

    final load = config('sensor', 'bus_load');
    expect(load['unique_id'], 'knx_monitor_bus_load');
    expect(load['name'], 'Buslast');
    expect(load['unit_of_measurement'], '%');
    expect(load['state_class'], 'measurement');
    expect(load['availability_topic'], 'knx_monitor/status');
    expect(load.containsKey('entity_category'), isFalse);

    expect(config('sensor', 'open_alarms')['state_class'], 'measurement');
    expect(config('sensor', 'last_alarm')['json_attributes_topic'], 'knx_monitor/state');
    expect(config('sensor', 'last_alarm_time')['device_class'], 'timestamp');
    expect(config('sensor', 'availability_24h')['unit_of_measurement'], '%');
    for (final key in ['history_size', 'free_space']) {
      final c = config('sensor', key);
      expect((c['device_class'], c['unit_of_measurement'], c['entity_category']), ('data_size', 'MB', 'diagnostic'));
    }
    final low = config('binary_sensor', 'low_space');
    expect((low['device_class'], low['entity_category']), ('problem', 'diagnostic'));

    for (final trigger in MqttBridge.busTriggers) {
      final c = sink.json('homeassistant/device_automation/knx_monitor/$trigger/config');
      expect(c['type'], trigger);
      expect(c['subtype'], 'KNX-Bus');
    }
    expect(
      sink.json('homeassistant/device_automation/knx_monitor/bus_disconnected/config')['topic'],
      'knx_monitor/bus/disconnected',
    );

    // Existing unique_ids stay unchanged (backwards compatible discovery).
    expect(config('sensor', 'telegrams_per_minute')['unique_id'], 'knx_monitor_telegrams_per_minute');
    expect(config('binary_sensor', 'bus_connected')['unique_id'], 'knx_monitor_bus_connected');
  });

  test('Buslast in Prozent aus der Belegung', () async {
    await bridge.start();
    expect(sink.json('knx_monitor/state')['bus_load'], 0.0);
    await bridge.tick(); // starting point
    // 0.6 s occupied within one minute = 1 %.
    bus.busy += 0.6;
    now = now.add(const Duration(minutes: 1));
    await bridge.tick();
    expect(sink.json('knx_monitor/state')['bus_load'], 1.0);
    expect(sink.retained['knx_monitor/bus_load'], '1.0');
    // Never above 100 %.
    bus.busy += 120;
    now = now.add(const Duration(minutes: 1));
    await bridge.tick();
    expect(sink.json('knx_monitor/state')['bus_load'], 100.0);
  });

  test('Belegung je Telegramm wie im Bericht', () {
    // 1-bit value: 9 bytes, plus idle time and acknowledgement.
    expect(busySeconds('', small: true), closeTo((50 + 13 * 9 + 15 + 13) / 9600, 1e-12));
  });

  test('offene Alarme und letzter Alarm', () async {
    await File('${data.path}/catalog.json').writeAsString(
      jsonEncode({
        'style': 'threeLevel',
        'groups': [
          {
            'a': 0x0801,
            'n': 'Rauchmelder Flur',
            'd': [1, 5],
          },
          {
            'a': 0x0802,
            'n': '',
            'd': [21, 1],
          },
        ],
      }),
    );
    // The bus forwards alarm changes to the bridge as events, as in server.dart.
    await bus.shutdown();
    bus = BusService(
      data,
      describe: (_, _) async => null,
      installation: {'id': 'a', 'name': 'Zuhause'},
      event: (type, data) async => bridge.onEvent(type, data),
    );
    await bus.start();
    await bridge.start();
    var state = sink.json('knx_monitor/state');
    expect(state['open_alarms'], 0);
    expect(state['last_alarm'], isNull);

    final time = DateTime.utc(2026, 10, 25, 11, 30);
    Map<String, Object?> line(int address, String x, {bool small = false}) => {
      't': time.microsecondsSinceEpoch,
      'd': address,
      'x': x,
      'm': small,
    };
    await bus.alarms.check(line(0x0801, '01', small: true));
    await bus.alarms.check(line(0x0802, '02')); // bit 1: fault, without a name
    await until(() => sink.json('knx_monitor/state')['open_alarms'] == 2);
    state = sink.json('knx_monitor/state');
    expect(state['last_alarm'], '1/0/2');
    expect(state['last_alarm_kind'], 'fault');
    expect(state['last_alarm_address'], '1/0/2');
    expect(state['last_alarm_time'], '2026-10-25T11:30:00.000Z');

    await bus.alarms.check(line(0x0802, '00'));
    await until(() => sink.json('knx_monitor/state')['open_alarms'] == 1);
    // The last alarm stays until the next one.
    expect(sink.json('knx_monitor/state')['last_alarm'], '1/0/2');
  });

  test('Speicher: Verlauf, freier Platz, knapp', () async {
    await Directory('${data.path}/history').create(recursive: true);
    await File('${data.path}/history/2026-10-25.ndjson').writeAsBytes(List.filled(1500000, 0x20));
    bus.recorder
      ..lastFree = 200 * 1000 * 1000
      ..lowSpace = true;
    await bridge.start();
    final state = sink.json('knx_monitor/state');
    expect(state['history_mb'], 1.5);
    expect(state['free_mb'], 200.0);
    expect(state['low_space'], isTrue);
    expect(sink.retained['knx_monitor/low_space'], 'true');
  });

  test('Verfügbarkeit der letzten 24 Stunden', () async {
    // One heartbeat per minute: 30 minutes connected, then 30 minutes not.
    final start = now.subtract(const Duration(hours: 1));
    for (var i = 0; i <= 60; i++) {
      await bus.availability.beat(
        connected: i <= 30,
        telegrams: 1,
        now: start.add(Duration(minutes: i)),
      );
    }
    await bridge.start();
    expect(sink.json('knx_monitor/state')['availability_24h'], 50.0);
  });

  test('ohne Herzschläge: Verfügbarkeit unbekannt', () async {
    await bridge.start();
    expect(sink.json('knx_monitor/state')['availability_24h'], isNull);
    expect(sink.retained['knx_monitor/availability_24h'], '');
  });

  test('Gerätetrigger Bus verbunden und getrennt', () async {
    await bridge.start();
    bridge.onEvent(HomeAssistant.busEvent, {'connected': false, 'state': 'disconnected'});
    expect(sink.sent('knx_monitor/bus/disconnected').single['state'], 'disconnected');
    bridge.onEvent(HomeAssistant.busEvent, {'connected': true, 'state': 'connected'});
    expect(sink.sent('knx_monitor/bus/connected'), hasLength(1));
  });

  test('ohne Broker: später erneut versuchen', () async {
    var asked = 0;
    final waiting = MqttBridge(
      () => bus,
      version: 'dev',
      sink: (_) => sink,
      broker: () async => ++asked < 3 ? null : const MqttBroker(host: 'h', port: 1883),
      retry: const Duration(milliseconds: 10),
    );
    await waiting.start();
    expect(asked, 3);
    expect(waiting.connected, isTrue);
    await waiting.stop();
  });

  test('einzelne Werte als eigene Topics, nur bei Änderung', () async {
    await bridge.start();
    expect(sink.retained['knx_monitor/connected'], 'false');
    expect(sink.retained['knx_monitor/recording'], 'false');
    expect(sink.retained['knx_monitor/today'], '0');
    expect(sink.retained['knx_monitor/installation'], 'Zuhause');
    final before = sink.published.where((p) => p.$1 == 'knx_monitor/today').length;
    await bridge.tick();
    expect(sink.published.where((p) => p.$1 == 'knx_monitor/today').length, before);
    bus.today = 5;
    await bridge.tick();
    expect(sink.retained['knx_monitor/today'], '5');
  });

  test('ohne Discovery: nur Zustand, Werte und Ereignisse', () async {
    await rules([('wind', 'Wind')]);
    final plain = MqttBridge(
      () => bus,
      version: 'dev',
      sink: (_) => sink,
      broker: () async => const MqttBroker(host: 'h', port: 1883),
      discovery: false,
    );
    await plain.start();
    expect(sink.retained.keys.where((t) => t.startsWith('homeassistant/')), isEmpty);
    expect(sink.retained['knx_monitor/status'], 'online');
    expect(sink.retained['knx_monitor/connected'], 'false');
    plain.onEvent(HomeAssistant.watcherEvent, {'watcher_id': 'wind', 'name': 'Wind'});
    expect(sink.sent('knx_monitor/event/watcher'), hasLength(1));
    await plain.tick();
    expect(sink.retained.keys.where((t) => t.startsWith('homeassistant/')), isEmpty);
    await plain.stop();
  });

  test('Discovery aus: frühere Ankündigungen des Geräts werden geleert', () async {
    final plain = MqttBridge(
      () => bus,
      version: 'dev',
      sink: (_) => sink,
      broker: () async => const MqttBroker(host: 'h', port: 1883),
      discovery: false,
    );
    await plain.start();
    expect(sink.subscribed, contains('homeassistant/+/knx_monitor/+/config'));
    // Der Broker liefert gespeicherte Ankündigungen beim Abonnieren aus.
    sink
      ..receive('homeassistant/switch/knx_monitor/recording/config', '{"name":"x"}')
      ..receive('homeassistant/device_automation/knx_monitor/watcher_alt/config', '{"type":"t"}')
      ..receive('homeassistant/switch/anderes_geraet/x/config', '{"name":"y"}');
    await until(() => sink.retained['homeassistant/device_automation/knx_monitor/watcher_alt/config'] == '');
    await plain.settled;
    expect(sink.retained['homeassistant/switch/knx_monitor/recording/config'], '');
    expect(sink.retained['homeassistant/device_automation/knx_monitor/watcher_alt/config'], '');
    expect(sink.retained.containsKey('homeassistant/switch/anderes_geraet/x/config'), isFalse);
    await plain.stop();
  });

  test('erneute Ankündigung sendet unveränderte Werte nicht noch einmal', () async {
    await bridge.start();
    final before = sink.published.where((p) => p.$1 == 'knx_monitor/today').length;
    final count = sink.published.length;
    sink.receive('homeassistant/status', 'online');
    // Die Ankündigung ist durch, sobald die Konfiguration erneut gesendet wurde.
    await until(
      () =>
          sink.published.skip(count).any((p) => p.$1 == 'homeassistant/binary_sensor/knx_monitor/bus_connected/config'),
    );
    await bridge.settled;
    expect(sink.published.where((p) => p.$1 == 'knx_monitor/today').length, before);
  });

  test('Broker aus Umgebungsvariablen', () {
    expect(MqttBroker.fromEnvironment({}), isNull);
    final b = MqttBroker.fromEnvironment({'MQTT_HOST': '192.168.1.5', 'MQTT_USER': 'iobroker', 'MQTT_PASSWORD': 'pw'})!;
    expect((b.host, b.port, b.username, b.password, b.ssl), ('192.168.1.5', 1883, 'iobroker', 'pw', false));
    expect(MqttBroker.fromEnvironment({'MQTT_HOST': 'h', 'MQTT_PORT': '8883', 'MQTT_SSL': 'true'})!.ssl, isTrue);
  });

  test('Broker beim Supervisor erfragen', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      r.response.headers.contentType = ContentType.json;
      r.response.write(
        r.uri.path == '/services/mqtt' && r.headers.value(HttpHeaders.authorizationHeader) == 'Bearer t'
            ? jsonEncode({
                'result': 'ok',
                'data': {'host': 'core-mosquitto', 'port': 1883, 'username': 'addons', 'password': 'pw', 'ssl': false},
              })
            : '{}',
      );
      await r.response.close();
    });
    final broker = await brokerFromSupervisor(token: 't', base: Uri.parse('http://127.0.0.1:${server.port}/'));
    expect(broker?.host, 'core-mosquitto');
    expect(broker?.username, 'addons');
    expect(await brokerFromSupervisor(token: 'falsch', base: Uri.parse('http://127.0.0.1:${server.port}/')), isNull);
    await server.close(force: true);
  });
}
