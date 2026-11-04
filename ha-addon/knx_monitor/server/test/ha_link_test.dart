import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max;
import 'dart:typed_data';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

/// Nachgebauter Home-Assistant-WebSocket mit KNX-Integration.
class _FakeHa {
  _FakeHa._(this.server) {
    server.listen((r) async {
      final ws = await WebSocketTransformer.upgrade(r);
      client = ws;
      ws.add(jsonEncode({'type': 'auth_required'}));
      ws.listen((m) {
        final j = jsonDecode(m as String) as Map<String, Object?>;
        received.add(j);
        switch (j['type']) {
          case 'auth':
            ws.add(jsonEncode({'type': j['access_token'] == 'token' ? 'auth_ok' : 'auth_invalid'}));
          case 'knx/subscribe_telegrams':
            subscription = j['id']! as int;
            ws.add(jsonEncode({'id': j['id'], 'type': 'result', 'success': true}));
          case 'call_service':
            ws.add(jsonEncode({'id': j['id'], 'type': 'result', 'success': true}));
          case 'knx/query_telegrams':
            if (renamed) {
              ws.add(
                jsonEncode({
                  'id': j['id'],
                  'type': 'result',
                  'success': true,
                  'result': {'items': []},
                }),
              );
              return;
            }
            if (stored == null) {
              ws.add(
                jsonEncode({
                  'id': j['id'],
                  'type': 'result',
                  'success': false,
                  'error': {'code': 'unknown_command', 'message': 'Unknown command.'},
                }),
              );
              return;
            }
            final from = DateTime.parse(j['start_time']! as String);
            final to = DateTime.parse(j['end_time']! as String);
            final match = [
              for (final t in stored!)
                if (!DateTime.parse(t['timestamp']! as String).isBefore(from) &&
                    !DateTime.parse(t['timestamp']! as String).isAfter(to))
                  t,
            ];
            final offset = j['offset']! as int;
            final page = match.skip(offset).take(j['limit']! as int).toList();
            ws.add(
              jsonEncode({
                'id': j['id'],
                'type': 'result',
                'success': true,
                'result': {'telegrams': page, 'total_count': match.length, 'limit_reached': false},
              }),
            );
        }
      });
    });
  }

  static Future<_FakeHa> start() async => _FakeHa._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer server;
  WebSocket? client;
  int? subscription;
  final received = <Map<String, Object?>>[];

  /// Telegram store (oldest first); `null` = Home Assistant without one.
  List<Map<String, Object?>>? stored;

  /// Answers with a field name the add-on does not know.
  bool renamed = false;

  String get url => 'ws://127.0.0.1:${server.port}';

  void telegram(Map<String, Object?> t) => client!.add(jsonEncode({'id': subscription, 'type': 'event', 'event': t}));
}

void main() {
  test('Telegramme aus Home Assistant als cEMI', () {
    expect(
      cemiFromHa({
        'destination': '1/2/3',
        'source': '1.1.5',
        'direction': 'Incoming',
        'telegramtype': 'GroupValueWrite',
        'payload': 1,
      }),
      [0x29, 0x00, 0xBC, 0xE0, 0x11, 0x05, 0x0A, 0x03, 0x01, 0x00, 0x81],
    );
    expect(
      cemiFromHa({
        'destination': '1/2/4',
        'source': '0.0.0',
        'direction': 'Outgoing',
        'telegramtype': 'GroupValueResponse',
        'payload': [12, 26],
      }),
      [0x2E, 0x00, 0xBC, 0xE0, 0x00, 0x00, 0x0A, 0x04, 0x03, 0x00, 0x40, 12, 26],
    );
    expect(cemiFromHa({'destination': '1/2/3', 'source': '1.1.5', 'telegramtype': 'GroupValueRead', 'payload': null}), [
      0x29,
      0x00,
      0xBC,
      0xE0,
      0x11,
      0x05,
      0x0A,
      0x03,
      0x01,
      0x00,
      0x00,
    ]);
  });

  test('verbindet, empfängt, sendet über knx.send/knx.read', () async {
    final ha = await _FakeHa.start();
    addTearDown(() => ha.server.close(force: true));
    final link = HaLink(url: ha.url, token: 'token');
    await link.connect();
    final frames = <Uint8List>[];
    link.frames.listen(frames.add);
    ha.telegram({
      'destination': '1/2/3',
      'source': '1.1.5',
      'direction': 'Incoming',
      'telegramtype': 'GroupValueWrite',
      'payload': [0x0C, 0x1A],
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(frames.single.sublist(6, 8), [0x0A, 0x03]);

    await link.send(Uint8List.fromList([0x11, 0x00, 0xBC, 0xE0, 0, 0, 0x0A, 0x03, 0x01, 0x00, 0x81]));
    await link.send(Uint8List.fromList([0x11, 0x00, 0xBC, 0xE0, 0, 0, 0x0A, 0x04, 0x03, 0x00, 0x80, 0x0C, 0x1A]));
    await link.send(Uint8List.fromList([0x11, 0x00, 0xBC, 0xE0, 0, 0, 0x0A, 0x03, 0x01, 0x00, 0x00]));
    final calls = ha.received.where((m) => m['type'] == 'call_service').toList();
    expect(calls.map((c) => c['service']), ['send', 'send', 'read']);
    expect((calls[0]['service_data']! as Map)['payload'], 1);
    expect((calls[1]['service_data']! as Map)['payload'], [12, 26]);
    expect((calls[2]['service_data']! as Map)['address'], '1/2/3');

    await expectLater(
      link.send(Uint8List.fromList([0x11, 0x00, 0xB0, 0x60, 0, 0, 0x11, 0x05, 0x00, 0x80])),
      throwsA(isA<LinkException>()),
    );
    await link.close();
  });

  group('telegram store', () {
    Map<String, Object?> stored(DateTime time, String destination, int payload) => {
      'timestamp': time.toIso8601String(),
      'destination': destination,
      'source': '1.1.5',
      'direction': 'Incoming',
      'telegramtype': 'GroupValueWrite',
      'payload': payload,
    };

    late _FakeHa ha;
    late HaLink link;
    late Directory data;
    late Recorder recorder;

    setUp(() async {
      ha = await _FakeHa.start();
      link = HaLink(url: ha.url, token: 'token');
      data = Directory.systemTemp.createTempSync('ha_store');
      recorder = Recorder(data, retentionDays: 7);
      await recorder.start();
    });

    tearDown(() async {
      await link.close();
      await ha.server.close(force: true);
      data.deleteSync(recursive: true);
    });

    test('reads in pages, oldest first, continuing at the last timestamp', () async {
      final start = DateTime.now().subtract(const Duration(hours: 1));
      ha.stored = [for (var i = 0; i < 7; i++) stored(start.add(Duration(minutes: i)), '1/2/$i', 1)];
      await link.connect();
      final pages = await link.storedTelegrams(start, DateTime.now(), page: 3).toList();
      expect(pages.map((p) => p.length), [3, 3, 1]);
      expect(pages.expand((p) => p).map((t) => t['destination']), [for (var i = 0; i < 7; i++) '1/2/$i']);
      final queries = ha.received.where((m) => m['type'] == 'knx/query_telegrams').toList();
      expect(queries.map((q) => q['offset']), [0, 1, 1]);
      expect(queries[1]['start_time'], start.add(const Duration(minutes: 2)).toIso8601String());
      expect(queries.first['order_descending'], false);
    });

    test('telegrams with the same timestamp across pages are read once', () async {
      final start = DateTime.now().subtract(const Duration(hours: 1));
      final same = start.add(const Duration(minutes: 1));
      ha.stored = [
        stored(start, '1/3/0', 1),
        for (var i = 1; i <= 5; i++) stored(same, '1/3/$i', 1),
        stored(start.add(const Duration(minutes: 2)), '1/3/6', 1),
      ];
      await link.connect();
      final pages = await link.storedTelegrams(start, DateTime.now(), page: 2).toList();
      expect(pages.expand((p) => p).map((t) => t['destination']), [for (var i = 0; i <= 6; i++) '1/3/$i']);
    });

    test('fills the gap and skips what both have', () async {
      await link.connect();
      final live = link.liveSince!;
      final last = live.subtract(const Duration(minutes: 10));
      // Recorded before the gap, and the first live telegram after it.
      recorder
        ..add(haHistoryLine(stored(last, '1/1/1', 1))!)
        ..add(haHistoryLine(stored(live.add(const Duration(milliseconds: 20)), '1/1/3', 1))!);
      await recorder.flush();
      ha.stored = [
        stored(live.subtract(const Duration(days: 9)), '1/1/9', 1), // beyond retention
        stored(last.subtract(const Duration(milliseconds: 15)), '1/1/1', 1), // already recorded
        stored(last.add(const Duration(minutes: 3)), '1/1/2', 1), // the gap
        stored(last.add(const Duration(minutes: 3, milliseconds: 1)), '1/1/2', 0),
        stored(live.subtract(const Duration(milliseconds: 5)), '1/1/3', 1), // also arrived live
      ];

      expect(await fillFromHomeAssistant(link.store, recorder, settle: Duration.zero), 2);
      final lines = await recorder.linesBetween(
        live.subtract(const Duration(days: 30)),
        live.add(const Duration(days: 1)),
      );
      expect(lines.map((l) => '${formatGroupAddress(l['d']! as int)} ${l['x']}').toList()..sort(), [
        '1/1/1 01',
        '1/1/2 00',
        '1/1/2 01',
        '1/1/3 01',
      ]);
      expect(
        await recorder.lastTime(),
        DateTime.fromMicrosecondsSinceEpoch(lines.map((l) => l['t']! as int).reduce(max)),
      );

      // A second run finds nothing new.
      expect(await fillFromHomeAssistant(link.store, recorder, settle: Duration.zero), 0);
    });

    test('without history it takes the whole retention', () async {
      await link.connect();
      final live = link.liveSince!;
      final firstKept = DateTime(live.year, live.month, live.day - 6);
      ha.stored = [
        stored(firstKept.subtract(const Duration(minutes: 1)), '1/1/8', 1), // retention would delete it
        stored(firstKept, '1/1/6', 1),
        stored(live.subtract(const Duration(hours: 1)), '1/1/0', 1),
      ];
      expect(await fillFromHomeAssistant(link.store, recorder, settle: Duration.zero), 2);
    });

    test('a changed answer is an error, not an empty store', () async {
      ha
        ..stored = []
        ..renamed = true;
      await link.connect();
      await expectLater(
        fillFromHomeAssistant(link.store, recorder, settle: Duration.zero),
        throwsA(isA<LinkException>()),
      );
    });

    test('read-only passes on the store, not the connection', () {
      final store = ReadOnlyLink(link).telegramStore;
      expect(store, isNotNull);
      expect(store, isNot(isA<BusLink>()));
      expect(ReadOnlyLink(HaLink(url: ha.url, token: 'token')).telegramStore, isNotNull);
    });

    test('Home Assistant without telegram store: error, nothing written', () async {
      await link.connect();
      await expectLater(
        fillFromHomeAssistant(link.store, recorder, settle: Duration.zero),
        throwsA(isA<LinkException>()),
      );
      expect(await recorder.lastTime(), isNull);
    });
  });

  test('falsches Token wird gemeldet', () async {
    final ha = await _FakeHa.start();
    addTearDown(() => ha.server.close(force: true));
    final link = HaLink(url: ha.url, token: 'falsch');
    await expectLater(link.connect(), throwsA(isA<LinkException>()));
  });
}
