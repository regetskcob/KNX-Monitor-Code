import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:knx_monitor_server/src/catalog_info.dart';
import 'package:knx_monitor_server/src/dpt_value.dart' show hexBytes;
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
  int? hop,
  String? cemi,
}) => {
  't': DateTime.utc(2025, 11, 7, 12).microsecondsSinceEpoch + 123456,
  's': 0x110E,
  'd': group,
  'y': type,
  'x': x,
  if (small) 'm': true,
  if (repeat) 'rp': true,
  'h': ?hop,
  'r': ?cemi,
};

/// L_Data.ind from 1.0.202 to 29/1/232, GroupValueWrite 4 bytes, priority low,
/// hop count 6 (the example from issue #11).
const _frame = '2900bce010cae9e805008000000000';

void main() {
  const stream = TelegramStream();

  test('write with ETS data: topic per group address, JSON with name, DPT, value', () {
    final (topic, payload) = stream.message(line(), _Project())!;
    expect(topic, 'knx_monitor/telegram/1/2/3');
    expect(jsonDecode(payload), {
      't': DateTime.utc(2025, 11, 7, 12).millisecondsSinceEpoch + 123,
      'ts': '2025-11-07T12:00:00.123456Z',
      'ga': '1/2/3',
      'ga_name': 'Wohnen Deckenlicht Schalten',
      'src': '1.1.14',
      'type': 'write',
      'dpt': '1.001',
      'value': true,
      'hop': 6,
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
    expect(p.keys, containsAll(['t', 'ts', 'ga', 'src', 'type', 'hop', 'raw', 'repeat']));
    expect(p.keys, isNot(contains('ga_name')));
    expect(p.keys, isNot(contains('value')));
  });

  test('tap points (#8): taps with the first one first, only when there are further ones', () {
    final merged = {
      ...line(),
      'tp': 1,
      'sg': [
        [0, 1500, 5],
      ],
    };
    expect(stream.payload(merged, _Project())!['taps'], [1, 0]);
    expect(stream.payload(line(), _Project())!.containsKey('taps'), isFalse);
    expect(stream.payload(line(), _Project())!.containsKey('tap_names'), isFalse);
    // Stable names next to the numbers; a tap point no longer configured gets `tap <n>`.
    const meta = TelegramMeta(tapNames: ['main', 'Linie 1.2']);
    expect(stream.payload(merged, _Project(), meta: meta)!['tap_names'], ['Linie 1.2', 'main']);
    expect(stream.payload({...merged, 'tp': 3}, _Project(), meta: meta)!['tap_names'], ['tap 3', 'main']);
    expect(stream.payload(merged, _Project())!['tap_names'], ['tap 1', 'tap 0']);
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

  group('traceability and raw data (#11, part 5)', () {
    Map<String, Object?> issueLine({bool repeat = false, int hop = 6}) {
      final l = telegramJson(hexBytes(_frame), DateTime.utc(2026, 11, 7, 21, 56, 22, 430, 79))!;
      return {...l, if (repeat) 'rp': true, if (hop != 6) 'h': hop};
    }

    test('always: seq, boot, inst, ts with microseconds, hop', () {
      const meta = TelegramMeta(seq: 7, boot: 'b-1', installation: 'wohnhaus');
      final p = stream.payload(line(hop: 5), _Project(), meta: meta)!;
      expect(p['seq'], 7);
      expect(p['boot'], 'b-1');
      expect(p['inst'], 'wohnhaus');
      expect(p['ts'], '2025-11-07T12:00:00.123456Z');
      expect(p['t'], DateTime.utc(2025, 11, 7, 12).millisecondsSinceEpoch + 123);
      expect(p['hop'], 5);
      expect(
        TelegramStream.isoMicros(DateTime.utc(2026, 1, 2, 3, 4, 5).microsecondsSinceEpoch),
        '2026-01-02T03:04:05.000000Z',
      );
      expect(p.containsKey('cemi'), isFalse, reason: 'raw data only on request');
      expect(p.containsKey('key'), isFalse);
    });

    test('raw data: cemi, msg, prio, ack_req, key as in the issue example', () {
      const raw = TelegramStream(raw: true);
      final p = raw.payload(issueLine(), _Project(empty: true))!;
      expect(p['ts'], '2026-11-07T21:56:22.430079Z');
      expect(p['ga'], '29/1/232');
      expect(p['src'], '1.0.202');
      expect(p['raw'], '00000000');
      expect(p['cemi'], _frame.toUpperCase(), reason: 'hex as in raw: upper case');
      expect(p['msg'], 'ind');
      expect(p['prio'], 'low');
      expect(p['ack_req'], isFalse);
      expect(p['hop'], 6);
      expect(p['key'], hasLength(16));
      expect(p['key'], matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('key ignores hop count and repeat bit, not the payload', () {
      const raw = TelegramStream(raw: true, repeats: true);
      final key = raw.payload(issueLine(), _Project())!['key'];
      expect(raw.payload(issueLine(hop: 5), _Project())!['key'], key);
      expect(raw.payload(issueLine(repeat: true), _Project())!['key'], key);
      expect(TelegramStream.dedupKey(0x10CA, 0xE9E8, 2, '00000001'), isNot(key));
      expect(TelegramStream.dedupKey(0x10CA, 0xE9E8, 2, '00000000'), key);
    });

    test('raw data: confirmation of an own telegram, priority, ack request', () {
      // L_Data.con, ctrl1 0xB2 = 1011 0010: priority 00 (system), acknowledge requested.
      final con = telegramJson(hexBytes('2e00b2e010cae9e805008000000001'), DateTime.utc(2026))!;
      final p = const TelegramStream(raw: true).payload(con, _Project())!;
      expect(p['msg'], 'con');
      expect(p['outgoing'], isTrue);
      expect(p['prio'], 'system');
      expect(p['ack_req'], isTrue);
      // Line without frame (older history): msg from "outgoing", no cemi or ack_req.
      final plain = const TelegramStream(raw: true).payload(line(), _Project())!;
      expect(plain['msg'], 'ind');
      expect(plain['prio'], 'low');
      expect(plain.containsKey('cemi'), isFalse);
      expect(plain.containsKey('ack_req'), isFalse);
    });

    test('raw only leaves out what comes from the ETS project', () {
      String? device(int a) => a == 0x110E ? 'Schaltaktor Wohnen' : null;
      final meta = TelegramMeta(deviceName: device, project: const {'id': 'abcd1234', 'date': '2026-11-02T08:00:00Z'});
      final full = stream.payload(line(), _Project(), meta: meta)!;
      expect(full['src_name'], 'Schaltaktor Wohnen');
      expect(full['ga_name'], isNotNull);
      final only = const TelegramStream(rawOnly: true).payload(line(cemi: _frame), _Project(), meta: meta)!;
      expect(const TelegramStream(rawOnly: true).raw, isTrue, reason: 'raw only implies raw');
      for (final k in ['ga_name', 'src_name', 'dpt', 'value', 'unit']) {
        expect(only.containsKey(k), isFalse, reason: k);
      }
      expect(only['cemi'], _frame);
      expect(only['raw'], '01');
      expect(only['project'], {'id': 'abcd1234', 'date': '2026-11-02T08:00:00Z'}, reason: 'project stays');
    });

    test('group address filter', () {
      final f = GroupFilter.parse('1/#, 3/2/#,4/1/7 x/1 9/9/9');
      expect(f.text, '1/#,3/2/#,4/1/7,x/1,9/9/9');
      expect(f.invalid, ['x/1', '9/9/9']);
      int ga(int a, int b, int c) => a << 11 | b << 8 | c;
      expect(f.matches(ga(1, 0, 0)), isTrue);
      expect(f.matches(ga(1, 7, 255)), isTrue);
      expect(f.matches(ga(3, 2, 9)), isTrue);
      expect(f.matches(ga(3, 1, 9)), isFalse);
      expect(f.matches(ga(4, 1, 7)), isTrue);
      expect(f.matches(ga(4, 1, 8)), isFalse);
      expect(f.matches(ga(2, 0, 1)), isFalse);
      expect(GroupFilter.parse('').isAll, isTrue);
      expect(GroupFilter.parse(null).matches(ga(31, 7, 255)), isTrue);
      expect(GroupFilter.parse('#').matches(ga(5, 5, 5)), isTrue);
      expect(GroupFilter.parse('1/2').invalid, ['1/2'], reason: 'without # only full addresses');
      final filtered = TelegramStream(filter: GroupFilter.parse('3/#'));
      expect(filtered.payload(line(), _Project()), isNull);
      expect(filtered.payload(line(group: 0x1907, x: '0C1A', small: false), _Project()), isNotNull);
    });

    test('bridge: seq per sent-or-due telegram, gaps for drops, not for filtered ones', () async {
      final data = await Directory.systemTemp.createTemp('knx_stream');
      final bus = BusService(data, describe: (_, _) async => null)..installation = {'id': 'abc123', 'name': 'Haus'};
      final sink = FakeSink();
      var now = DateTime(2026, 11, 7, 12);
      final bridge = MqttBridge(
        () => bus,
        version: 'test',
        sink: (_) => sink,
        broker: () async => const MqttBroker(host: 'core-mosquitto', port: 1883),
        interval: const Duration(hours: 1),
        clock: () => now,
        telegrams: TelegramStream(filter: GroupFilter.parse('1/#')),
      );
      try {
        await bridge.start();
        bridge.onTelegram(line(), _Project());
        bridge.onTelegram(line(group: 0x1907), _Project()); // 3/1/7: filtered
        for (var i = 0; i < MqttBridge.maxTelegramsPerSecond; i++) {
          bridge.onTelegram(line(), _Project());
        }
        now = now.add(const Duration(seconds: 1));
        bridge.onTelegram(line(), _Project());
        final sent = [
          for (final p in sink.published.where((p) => p.$1.startsWith('knx_monitor/telegram/')))
            jsonDecode(p.$2) as Map<String, Object?>,
        ];
        expect(sent.first['seq'], 1);
        expect(sent.first['inst'], 'abc123', reason: 'default: active installation id');
        expect(sent.first['boot'], bridge.boot);
        expect(bridge.boot, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
        expect(sent.last['seq'], MqttBridge.maxTelegramsPerSecond + 2, reason: 'the dropped one left a gap');
        expect(sent.length, MqttBridge.maxTelegramsPerSecond + 1);
        expect(bridge.telegramsDropped, 1);
        final status = bridge.telegramStatus();
        expect(status, containsPair('seq', MqttBridge.maxTelegramsPerSecond + 2));
        expect(status, containsPair('filter', '1/#'));
        expect(status, containsPair('raw', false));
        expect(status, containsPair('rawOnly', false));
        expect(status, containsPair('boot', bridge.boot));
      } finally {
        await bridge.stop();
        await bus.shutdown();
        await data.delete(recursive: true);
      }
    });

    test('bridge: installation override, project and device names from the catalog', () async {
      final data = await Directory.systemTemp.createTemp('knx_stream');
      await File('${data.path}/catalog.json').writeAsString(
        jsonEncode({
          'v': 1,
          'project': 'Demo',
          'groups': <Object?>[],
          'devices': [
            {'a': 0x110E, 'n': 'Schaltaktor Wohnen'},
            {'a': 0x110F, 'n': ''},
          ],
        }),
      );
      final bus = BusService(data, describe: (_, _) async => null);
      final sink = FakeSink();
      final bridge = MqttBridge(
        () => bus,
        version: 'test',
        sink: (_) => sink,
        broker: () async => const MqttBroker(host: 'core-mosquitto', port: 1883),
        interval: const Duration(hours: 1),
        installation: 'wohnhaus',
        boot: 'fixed',
        telegrams: const TelegramStream(),
      );
      try {
        await bridge.start();
        bridge.onTelegram(line(), _Project()); // starts reading the catalog
        await Future<void>.delayed(const Duration(milliseconds: 100));
        bridge.onTelegram(line(), _Project());
        final last = jsonDecode(bridge.lastTelegram!['payload']! as String) as Map<String, Object?>;
        expect(last['inst'], 'wohnhaus');
        expect(last['boot'], 'fixed');
        expect(last['src_name'], 'Schaltaktor Wohnen');
        final project = last['project']! as Map;
        expect(project['id'], matches(RegExp(r'^[0-9a-f]{8}$')));
        expect(project['date'], matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$')));
      } finally {
        await bridge.stop();
        await bus.shutdown();
        await data.delete(recursive: true);
      }
    });

    test('catalog info: new id after a change, nothing without a catalog', () async {
      final data = await Directory.systemTemp.createTemp('knx_catalog');
      var now = DateTime(2026, 11, 7);
      final info = CatalogInfo(clock: () => now);
      try {
        info.poll(data);
        await info.ready;
        expect(info.project, isNull);
        final file = File('${data.path}/catalog.json');
        await file.writeAsString('{"groups":[],"devices":[]}');
        info.poll(data);
        await info.ready;
        expect(info.project, isNull, reason: 'checked at most every 10 s');
        now = now.add(const Duration(seconds: 11));
        info.poll(data);
        await info.ready;
        final first = info.project!['id'];
        await file.writeAsString('{"groups":[],"devices":[{"a":1,"n":"X"}]}');
        await file.setLastModified(DateTime(2026, 11, 8));
        now = now.add(const Duration(seconds: 11));
        info.poll(data);
        await info.ready;
        expect(info.project!['id'], isNot(first));
        expect(info.project!['date'], DateTime(2026, 11, 8).toUtc().toIso8601String().split('.').first + 'Z');
        expect(info.deviceName(1), 'X');
      } finally {
        await data.delete(recursive: true);
      }
    });
  });
}
