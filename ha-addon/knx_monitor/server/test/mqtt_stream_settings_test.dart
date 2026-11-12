import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

import 'mqtt_bridge_test.dart' show FakeSink, until;

/// The telegram stream set from the app (issue #11): settings in mqtt_stream.json win over the
/// add-on options or environment, take effect while running, and the switch on the MQTT device
/// only pauses a stream an admin has set up.
void main() {
  late Directory data;
  late BusService bus;
  late FakeSink sink;
  late File file;

  Map<String, Object?> line({int group = 0x0A03, String x = '01'}) => {
    't': DateTime(2026, 11, 11, 12).microsecondsSinceEpoch,
    's': 0x1101,
    'd': group,
    'y': 2,
    'x': x,
    'm': true,
  };

  MqttBridge bridge({TelegramStreamSettings defaults = const TelegramStreamSettings(), bool discovery = true}) =>
      MqttBridge(
        () => bus,
        version: '1.12.0',
        sink: (_) => sink,
        broker: () async => const MqttBroker(host: 'core-mosquitto', port: 1883),
        interval: const Duration(hours: 1),
        defaults: defaults,
        settingsFile: file,
        discovery: discovery,
      );

  int telegrams() => sink.published.where((p) => p.$1.startsWith('knx_monitor/telegram/')).length;

  setUp(() async {
    data = await Directory.systemTemp.createTemp('knx_mqtt_settings');
    bus = BusService(data, describe: (_, _) async => null, installation: {'id': 'a', 'name': 'Zuhause'});
    await bus.start();
    sink = FakeSink();
    file = File('${data.path}/mqtt_stream.json');
  });

  tearDown(() async {
    await bus.shutdown();
    await data.delete(recursive: true);
  });

  test('switched on in the app: sends at once, survives a restart, reset goes back to the default', () async {
    var b = bridge();
    await b.loadSettings();
    await b.start();
    b.onTelegram(line(), bus.exporter.source);
    expect(telegrams(), 0);
    expect(b.telegramStatus(), containsPair('source', 'default'));

    final status = await b.configure({'enabled': true, 'filter': '1/#', 'retainValues': true});
    expect(status, allOf(containsPair('enabled', true), containsPair('source', 'app'), containsPair('filter', '1/#')));
    b.onTelegram(line(), bus.exporter.source);
    b.onTelegram(line(group: 0x1203), bus.exporter.source);
    expect(telegrams(), 1, reason: 'only 1/#');
    expect(sink.retained['knx_monitor/value/1/2/3'], isNotEmpty);
    await b.stop();

    sink = FakeSink();
    b = bridge();
    await b.loadSettings();
    await b.start();
    expect(b.settings.enabled, isTrue);
    expect(b.settings.filter, '1/#');
    b.onTelegram(line(), bus.exporter.source);
    expect(telegrams(), 1);

    await b.configure({'reset': true});
    expect(b.telegramStatus(), allOf(containsPair('enabled', false), containsPair('source', 'default')));
    expect(await file.exists(), isFalse);
    expect(sink.retained['knx_monitor/value/1/2/3'], '', reason: 'retained values are cleared from the broker');
    b.onTelegram(line(), bus.exporter.source);
    expect(telegrams(), 1);
    await b.stop();
  });

  test('the app can switch off what the options switched on', () async {
    final b = bridge(defaults: const TelegramStreamSettings(enabled: true));
    await b.loadSettings();
    await b.start();
    b.onTelegram(line(), bus.exporter.source);
    expect(telegrams(), 1);
    await b.configure({'enabled': false});
    b.onTelegram(line(), bus.exporter.source);
    expect(telegrams(), 1);
    expect(b.telegramStatus(), containsPair('defaultEnabled', true));
    await b.stop();
  });

  test('values that do not fit are refused and change nothing', () async {
    final b = bridge();
    await b.loadSettings();
    for (final bad in <Map<String, Object?>>[
      {'enabled': 'yes'},
      {'filter': 7},
      {'filter': '1/#,quatsch'},
      {'enabled': true, 'secure': 1},
    ]) {
      await expectLater(b.configure(bad), throwsFormatException, reason: '$bad');
    }
    expect(b.settings.enabled, isFalse);
    expect(await file.exists(), isFalse);
  });

  test('raw only implies raw, raw off ends raw only', () {
    const s = TelegramStreamSettings();
    final only = s.merge({'rawOnly': true});
    expect((only.raw, only.rawOnly), (true, true));
    final off = only.merge({'raw': false});
    expect((off.raw, off.rawOnly), (false, false));
  });

  test('switch on the MQTT device: pauses a stream that is set up, never starts one', () async {
    final b = bridge();
    await b.loadSettings();
    await b.start();
    // Not set up: no switch, and ON from the broker starts nothing.
    expect(sink.retained['homeassistant/switch/knx_monitor/telegram_stream/config'], '');
    sink.receive('knx_monitor/telegrams/set', 'ON');
    await b.settled;
    b.onTelegram(line(), bus.exporter.source);
    expect(telegrams(), 0);
    expect(b.settings.enabled, isFalse);

    await b.configure({'enabled': true});
    final config = sink.json('homeassistant/switch/knx_monitor/telegram_stream/config');
    expect(config['command_topic'], 'knx_monitor/telegrams/set');
    expect(sink.json('homeassistant/sensor/knx_monitor/telegrams_dropped/config')['entity_category'], 'diagnostic');
    expect(sink.json('knx_monitor/state')['telegram_stream'], isTrue);

    sink.receive('knx_monitor/telegrams/set', 'OFF');
    await until(() => sink.json('knx_monitor/state')['telegram_stream'] == false);
    b.onTelegram(line(), bus.exporter.source);
    expect(telegrams(), 0);
    expect(b.telegramStatus(), containsPair('paused', true));
    expect((jsonDecode(await file.readAsString()) as Map)['paused'], isTrue);

    sink.receive('knx_monitor/telegrams/set', 'vielleicht');
    await b.settled;
    expect(b.telegramStatus(), containsPair('paused', true));

    sink.receive('knx_monitor/telegrams/set', 'ON');
    await until(() => sink.json('knx_monitor/state')['telegram_stream'] == true);
    b.onTelegram(line(), bus.exporter.source);
    expect(telegrams(), 1);

    // Switched off in the app: the entities go away again.
    await b.configure({'enabled': false});
    expect(sink.retained['homeassistant/switch/knx_monitor/telegram_stream/config'], '');
    await b.stop();
  });

  test('a pause on default settings survives a restart without turning them into app settings', () async {
    var b = bridge(defaults: const TelegramStreamSettings(enabled: true));
    await b.loadSettings();
    await b.setPaused(true);
    b = bridge(defaults: const TelegramStreamSettings(enabled: true));
    await b.loadSettings();
    expect(b.telegramStatus(), allOf(containsPair('paused', true), containsPair('source', 'default')));
    expect(b.telegrams, isNull);
    await b.setPaused(false);
    expect(await file.exists(), isFalse);
  });

  test('a broken settings file falls back to the default', () async {
    for (final content in [
      '{kaputt',
      // Hand-edited with a filter that cannot be read: not "on, but sends nothing".
      '{"settings":{"enabled":false,"filter":"1/#,quatsch"}}',
    ]) {
      await file.writeAsString(content);
      final b = bridge(defaults: const TelegramStreamSettings(enabled: true));
      await b.loadSettings();
      expect(b.settings.enabled, isTrue, reason: content);
      expect(b.settings.filter, '', reason: content);
      expect(b.telegramStatus(), containsPair('source', 'default'), reason: content);
    }
  });
}
