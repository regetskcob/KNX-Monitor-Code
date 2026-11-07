import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

import 'mqtt_bridge_test.dart' show FakeSink;

/// Project lookup as the bus has it: 1/2/3 switch, 3/1/7 temperature.
class _Project implements ExportSource {
  _Project({this.empty = false});
  final bool empty;

  @override
  bool get connected => true;
  @override
  int get recorderDropped => 0;
  @override
  Map<String, Object?>? get busmon => null;
  @override
  bool get timeKnown => true;
  @override
  String formatGroup(int group) => TelegramStream.formatGroup3(group);
  @override
  String? nameOf(int group) => empty
      ? null
      : switch (group) {
          0x0A03 => 'Wohnen Deckenlicht Schalten',
          0x1907 => 'Wohnen Temperatur',
          _ => null,
        };
  @override
  (int, int?)? dptOf(int group) => empty
      ? null
      : switch (group) {
          0x0A03 => (1, 1),
          0x1907 => (9, 1),
          _ => null,
        };
}

Map<String, Object?> line({
  int group = 0x0A03,
  int type = 2,
  String x = '01',
  bool small = true,
  bool repeat = false,
}) => {
  't': DateTime.utc(2025, 11, 7, 12).microsecondsSinceEpoch + 123456,
  's': 0x110E,
  'd': group,
  'y': type,
  'x': x,
  if (small) 'm': true,
  if (repeat) 'rp': true,
};

void main() {
  const stream = TelegramStream();

  test('write with ETS data: topic per group address, JSON with name, DPT, value', () {
    final (topic, payload) = stream.message(line(), _Project())!;
    expect(topic, 'knx_monitor/telegram/1/2/3');
    expect(jsonDecode(payload), {
      't': DateTime.utc(2025, 11, 7, 12).millisecondsSinceEpoch + 123,
      'ga': '1/2/3',
      'ga_name': 'Wohnen Deckenlicht Schalten',
      'src': '1.1.14',
      'type': 'write',
      'dpt': '1.001',
      'value': true,
      'raw': '01',
      'repeat': false,
    });
  });

  test('temperature with unit; read without value and raw', () {
    final temp = stream.payload(line(group: 0x1907, x: '0C1A', small: false), _Project())!;
    expect(temp['value'], closeTo(21.0, 0.01));
    expect(temp['unit'], '°C');
    expect(temp['dpt'], '9.001');
    final read = stream.payload(line(group: 0x1907, type: 0, x: '', small: false), _Project())!;
    expect(read['type'], 'read');
    expect(read.containsKey('value'), isFalse);
    expect(read.containsKey('raw'), isFalse);
  });

  test('without ETS project only address, sender and raw', () {
    final p = stream.payload(line(), _Project(empty: true))!;
    expect(p.keys, containsAll(['t', 'ga', 'src', 'type', 'raw', 'repeat']));
    expect(p.keys, isNot(contains('ga_name')));
    expect(p.keys, isNot(contains('value')));
  });

  test('repeats only when switched on', () {
    expect(stream.message(line(repeat: true), _Project()), isNull);
    expect(const TelegramStream(repeats: true).payload(line(repeat: true), _Project())!['repeat'], isTrue);
  });

  test('bridge sends with the stream on, counts dropped ones without broker', () async {
    final sink = FakeSink();
    final bridge = MqttBridge(
      () => throw StateError('no bus needed'),
      version: 'test',
      sink: (_) => sink,
      broker: () async => null,
      retry: const Duration(hours: 1),
      telegrams: const TelegramStream(),
    );
    bridge.onTelegram(line(), _Project());
    expect(bridge.telegramsDropped, 1);
    expect(sink.published, isEmpty);
    final off = MqttBridge(() => throw StateError('no bus'), version: 'test', broker: () async => null);
    off.onTelegram(line(), _Project());
    expect(off.telegramsDropped, 0, reason: 'stream off: nothing counted');
  });

  test('bridge publishes topic and payload with QoS 0, not retained', () async {
    final data = await Directory.systemTemp.createTemp('knx_stream');
    final bus = BusService(data, describe: (_, _) async => null);
    final sink = FakeSink();
    final bridge = MqttBridge(
      () => bus,
      version: 'test',
      sink: (_) => sink,
      broker: () async => const MqttBroker(host: 'core-mosquitto', port: 1883),
      interval: const Duration(hours: 1),
      telegrams: const TelegramStream(),
    );
    try {
      await bridge.start();
      bridge.onTelegram(line(), _Project());
      final sent = sink.published.where((p) => p.$1.startsWith('knx_monitor/telegram/')).toList();
      expect(sent, hasLength(1));
      expect(sent.single.$1, 'knx_monitor/telegram/1/2/3');
      expect(sent.single.$3, isFalse, reason: 'not retained');
      expect((jsonDecode(sent.single.$2) as Map)['value'], isTrue);
      expect(sink.atMostOnce, ['knx_monitor/telegram/1/2/3']);
      expect(bridge.telegramsSent, 1);
      expect(bridge.lastTelegram?['topic'], 'knx_monitor/telegram/1/2/3');
    } finally {
      await bridge.stop();
      await bus.shutdown();
      await data.delete(recursive: true);
    }
  });

  test('KNX Data Secure telegrams only on request, then marked secure', () {
    expect(stream.message(line(), _Project(), secure: true), isNull, reason: 'decrypted data stays off the broker');
    final p = const TelegramStream(secure: true).payload(line(), _Project(), secure: true)!;
    expect(p['secure'], isTrue);
    expect(stream.payload(line(), _Project())!.containsKey('secure'), isFalse);
  });

  test('bridge caps telegrams per second and counts the rest as dropped', () async {
    final data = await Directory.systemTemp.createTemp('knx_stream');
    final bus = BusService(data, describe: (_, _) async => null);
    final sink = FakeSink();
    var now = DateTime(2026, 11, 7, 12);
    final bridge = MqttBridge(
      () => bus,
      version: 'test',
      sink: (_) => sink,
      broker: () async => const MqttBroker(host: 'core-mosquitto', port: 1883),
      interval: const Duration(hours: 1),
      clock: () => now,
      telegrams: const TelegramStream(),
    );
    try {
      await bridge.start();
      for (var i = 0; i < MqttBridge.maxTelegramsPerSecond + 20; i++) {
        bridge.onTelegram(line(), _Project());
      }
      expect(bridge.telegramsSent, MqttBridge.maxTelegramsPerSecond);
      expect(bridge.telegramsDropped, 20);
      now = now.add(const Duration(seconds: 1));
      bridge.onTelegram(line(), _Project());
      expect(bridge.telegramsSent, MqttBridge.maxTelegramsPerSecond + 1, reason: 'next second sends again');
    } finally {
      await bridge.stop();
      await bus.shutdown();
      await data.delete(recursive: true);
    }
  });

  test('bridge: secured telegrams stay off without opt-in, undecryptable ones always', () async {
    final data = await Directory.systemTemp.createTemp('knx_stream');
    final bus = BusService(data, describe: (_, _) async => null);
    final sink = FakeSink();
    MqttBridge bridgeWith(TelegramStream stream) => MqttBridge(
      () => bus,
      version: 'test',
      sink: (_) => sink,
      broker: () async => const MqttBroker(host: 'core-mosquitto', port: 1883),
      interval: const Duration(hours: 1),
      telegrams: stream,
    );
    final off = bridgeWith(const TelegramStream());
    final on = bridgeWith(const TelegramStream(secure: true));
    try {
      await off.start();
      off.onTelegram(line(), _Project(), secure: true, decrypted: true);
      off.onTelegram(line(), _Project(), secure: true);
      expect(off.telegramsSent, 0, reason: 'default: no secured telegram, keyring or not');
      expect(off.telegramsSecureSkipped, 1);
      expect(off.telegramsUndecrypted, 1);
      expect(off.telegramStatus(), containsPair('secureSkipped', 1));
      expect(off.telegramStatus(), containsPair('undecrypted', 1));
      // The same reasons for systems without the app, in the state topic.
      await off.tick();
      expect(sink.json('knx_monitor/state'), containsPair('telegrams_secure_skipped', 1));
      await on.start();
      on.onTelegram(line(), _Project(), secure: true);
      expect(on.telegramsSent, 0, reason: 'not decrypted: never sent, even with opt-in');
      on.onTelegram(line(), _Project(), secure: true, decrypted: true);
      expect(on.telegramsSent, 1);
      expect((jsonDecode(on.lastTelegram!['payload']! as String) as Map)['secure'], isTrue);
    } finally {
      await off.stop();
      await on.stop();
      await bus.shutdown();
      await data.delete(recursive: true);
    }
  });

  test('data export status carries the stream state for the app', () async {
    final data = await Directory.systemTemp.createTemp('knx_stream');
    final bus = BusService(data, describe: (_, _) async => null, mqttTelegrams: () => {'enabled': false});
    try {
      expect(bus.exporter.status()['mqttTelegrams'], {'enabled': false});
      expect(MqttBridge(() => bus, version: 'test', broker: () async => null).telegramStatus(), {'enabled': false});
    } finally {
      await bus.shutdown();
      await data.delete(recursive: true);
    }
  });
}
