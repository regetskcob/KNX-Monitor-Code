import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:knx_monitor_server/bus.dart';
import 'package:knx/secure.dart';
import 'package:knx_monitor_server/src/secure_taps.dart';
import 'package:test/test.dart';

/// Bus connection without a network, one per host.
class _Link implements BusLink {
  _Link(this.host);
  final String host;
  final _frames = StreamController<Uint8List>.broadcast();
  final _lost = Completer<String>();
  @override
  Stream<Uint8List> get frames => _frames.stream;
  void receive(Uint8List frame) => _frames.add(frame);
  @override
  int? get address => host == 'a' ? 0x1101 : 0x1201;
  @override
  String get label => 'Test $host';
  @override
  Future<void> connect() async {}
  final sent = <Uint8List>[];
  @override
  Future<void> send(Uint8List cemi) async => sent.add(cemi);
  @override
  Future<String> get lost => _lost.future;
  void drop() {
    if (!_lost.isCompleted) _lost.complete('weg');
  }

  @override
  Future<void> close() async => drop();
}

/// The receive path of server and app in small: Data Secure with the tap point cache, the merger,
/// and the caller's duty to drop what [SecureTapCache.released] refuses.
class _SecureBus {
  _SecureBus(Uint8List key, {required int taps, Map<int, Duration> hand = const {}})
    : ds = DataSecure(groupKeys: {0x0A03: key}, sequenceNumbers: {0x1105: 0}),
      merger = TapMerger(taps: taps, windows: Map.of(hand)) {
    cache.windows = Map.of(hand);
  }

  final DataSecure ds;
  final TapMerger merger;
  final cache = SecureTapCache();
  final out = <Telegram>[];
  int rejected = 0;

  void frame(int tap, Uint8List cemi, DateTime at) {
    final (result, plain) = cache.receive(ds, tap, cemi, at: at);
    if (result != SecureResult.decrypted) {
      rejected++;
      return;
    }
    final t = Telegram.fromCemi(plain, time: at)!;
    cache.tag(t.raw);
    _emit(merger.add(tap, t));
  }

  void flush(DateTime at) => _emit(merger.flush(at));

  void _emit(List<Telegram> ready) {
    for (final t in ready) {
      cache.released(t.raw, merged: t.sightings.isNotEmpty) ? out.add(t) : rejected++;
    }
  }
}

/// L_Data.ind from 1.1.5 to 1/2/3, GroupValueWrite 1, with [hop].
Uint8List _ind({int hop = 6}) =>
    Uint8List.fromList([0x29, 0x00, 0xBC, 0x80 | (hop << 4), 0x11, 0x05, 0x0A, 0x03, 0x01, 0x00, 0x81]);

Future<void> _until(bool Function() ok) async {
  for (var i = 0; i < 200 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(ok(), isTrue);
}

void main() {
  late Directory data;
  setUp(() async => data = await Directory.systemTemp.createTemp('taps'));
  tearDown(() async => data.delete(recursive: true));

  test('BusConfig keeps only usable tap points', () {
    final c = BusConfig.fromJson({
      'taps': [
        {'mode': 'tcp', 'host': '10.0.0.2', 'name': 'Linie 1.2', 'windowMs': 99999},
        {'mode': 'udp', 'host': ''},
        {'mode': 'x', 'host': 'a'},
        {'mode': 'routing', 'host': ''},
      ],
    });
    expect(c.taps, hasLength(2));
    expect(c.taps.first['windowMs'], 5000);
    expect(BusConfig.invalidChange({'taps': 'x'}), isNotNull);
    expect(BusConfig.invalidChange({'taps': List.filled(8, <String, Object?>{})}), isNotNull);
    expect(BusConfig.invalidChange({'taps': []}), isNull);
  });

  test('main connection and tap point: one telegram with a sighting, status lists the tap point', () async {
    final links = <String, _Link>{};
    final lines = <Map<String, Object?>>[];
    final bus = BusService(
      data,
      link: (c) => links[c.host] = _Link(c.host),
      describe: (_, _) async => null,
      telegram: (line, {required secure, required decrypted}) => lines.add(line),
    );
    await bus.start();
    await bus.update({
      'enabled': true,
      'mode': 'udp',
      'host': 'a',
      'taps': [
        {'name': 'Linie 1.2', 'mode': 'udp', 'host': 'b'},
      ],
    });
    await _until(() => bus.state == 'connected' && links.containsKey('b'));
    await _until(() => (bus.status()['taps'] as List).first['state'] == 'connected');
    links['a']!.receive(_ind());
    links['b']!.receive(_ind(hop: 5));
    await _until(() => lines.isNotEmpty);
    expect(lines.single['sg'], [
      [1, isA<int>(), 5],
    ]);
    expect(lines.single.containsKey('tp'), isFalse);
    expect(bus.today, 1);

    // Seen only at the tap point (filtered towards the main line): leaves after the window.
    links['b']!.receive(_ind(hop: 5));
    await _until(() => lines.length == 2);
    expect(lines.last['tp'], 1);

    // Tap point drops: the main connection carries on, the tap point reconnects on its own.
    final first = links['b']!;
    first.drop();
    await _until(() => !identical(links['b'], first));
    expect(bus.state, 'connected');
    await _until(() => (bus.status()['taps'] as List).first['state'] == 'connected');
    await bus.shutdown();
  });

  group('Data Secure with several tap points', () {
    // A real secured telegram: 1.1.5 writes 1 to 1/2/3, encrypted with a group key.
    final key = Uint8List.fromList(List.generate(16, (i) => i + 1));
    Uint8List secured({int seq = 1000, int value = 1}) =>
        DataSecure(groupKeys: {0x0A03: key}, sequenceNumbers: const {}, sequenceStart: seq).send(
          Uint8List.fromList([0x29, 0x00, 0xBC, 0xE0, 0x00, 0x00, 0x0A, 0x03, 0x01, 0x00, 0x80 | value]),
          source: 0x1105,
        );
    // The same frame after a coupler: hop count 5.
    Uint8List forwarded(Uint8List f) => Uint8List.fromList(f)..[3] = (f[3] & 0x8F) | 0x50;
    // With the repeat flag set (bit 5 of control field 1 cleared), which no MAC protects.
    Uint8List repeated(Uint8List f) => Uint8List.fromList(f)..[2] = f[2] & 0xDF;
    final t0 = DateTime(2026, 11, 10, 12);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    test('the identical frame at another tap point within the window joins the entry of the first', () {
      final bus = _SecureBus(key, taps: 3);
      final frame = secured();
      bus.frame(0, frame, at(0));
      bus.frame(1, forwarded(frame), at(40));
      expect(bus.out, isEmpty, reason: 'waits for the third tap point');
      bus.frame(2, forwarded(frame), at(60));
      expect(bus.out, hasLength(1));
      expect(bus.out.single.data, [1]);
      expect(bus.out.single.taps.toList(), [0, 1, 2]);
      expect(bus.out.single.sightings.map((s) => s.hopCount), [5, 5]);
      expect(bus.rejected, 0);
    });

    test('a replay at the same tap point is refused, also within the window', () {
      final bus = _SecureBus(key, taps: 3);
      final frame = secured();
      bus.frame(0, frame, at(0));
      bus.frame(0, frame, at(10));
      bus.frame(1, forwarded(frame), at(20));
      // Each tap point counts once: a second copy there is a replay too.
      bus.frame(1, forwarded(frame), at(30));
      bus.flush(at(200));
      expect(bus.rejected, 2);
      expect(bus.out.single.taps.toList(), [0, 1]);
    });

    test('a replay at another tap point after the window is refused, also with a clock set back', () {
      final bus = _SecureBus(key, taps: 3);
      final frame = secured();
      bus.frame(0, frame, at(0));
      bus.frame(1, forwarded(frame), at(101));
      bus.frame(2, forwarded(frame), at(-5));
      bus.flush(at(200));
      expect(bus.rejected, 2);
      expect(bus.out.single.sightings, isEmpty);
    });

    test('variant 1: the wide window of a third tap point does not open the window of another pair', () {
      // Tap point 2 has 5 s by hand (VPN). The entry therefore waits up to 5 s in the merger.
      final bus = _SecureBus(key, taps: 3, hand: {2: const Duration(seconds: 5)});
      final frame = secured();
      bus.frame(0, frame, at(0));
      // Replay at tap point 1 after 2 s: its pair with tap point 0 has 100 ms.
      bus.frame(1, forwarded(frame), at(2000));
      expect(bus.rejected, 1);
      // The real copy over the VPN still counts within its own window.
      bus.frame(2, forwarded(frame), at(3000));
      bus.flush(at(6000));
      expect(bus.out, hasLength(1));
      expect(bus.out.single.taps.toList(), [0, 2]);
      expect(bus.rejected, 1);
    });

    test('variant 2: a copy with the repeat flag flipped joins the same entry, never a new one', () {
      for (final flipFirst in [false, true]) {
        final bus = _SecureBus(key, taps: 2);
        final frame = secured();
        bus.frame(0, flipFirst ? repeated(frame) : frame, at(0));
        bus.frame(1, forwarded(flipFirst ? frame : repeated(frame)), at(50));
        bus.flush(at(500));
        expect(bus.out, hasLength(1), reason: 'flipFirst $flipFirst');
        expect(bus.out.single.taps.toList(), [0, 1]);
        // The entry keeps the flag of the first copy.
        expect(bus.out.single.repeated, flipFirst);
        expect(bus.rejected, 0);
      }
    });

    test('variant 3: once the entry has left the merger, a copy is a replay (silent tap point)', () {
      // Tap point 1 is silent, so only one tap point is waited for: the entry leaves at once.
      final bus = _SecureBus(key, taps: 1);
      final frame = secured();
      bus.frame(0, frame, at(0));
      expect(bus.out, hasLength(1));
      bus.frame(1, forwarded(frame), at(60));
      bus.flush(at(500));
      expect(bus.out, hasLength(1));
      expect(bus.out.single.sightings, isEmpty);
      expect(bus.rejected, 1);
    });

    test('measured windows never count for Data Secure, only those set by hand', () {
      final bus = _SecureBus(key, taps: 2);
      // The meter widened tap point 1 to a second (lag can be faked with unsecured telegrams).
      bus.merger.windows[1] = const Duration(seconds: 1);
      final frame = secured();
      bus.frame(0, frame, at(0));
      bus.frame(1, forwarded(frame), at(600));
      bus.flush(at(2000));
      expect(bus.rejected, 1);
      expect(bus.out.single.sightings, isEmpty);
      // Windows by hand are capped at the widest one that can be set.
      final wide = _SecureBus(key, taps: 2, hand: {1: const Duration(hours: 1)});
      wide.merger.windows[1] = const Duration(hours: 1);
      final next = secured(seq: 2000);
      wide.frame(0, next, at(0));
      wide.frame(1, forwarded(next), at(5001));
      expect(wide.rejected, 1);
    });

    test('last line: a copy the merger releases on its own is dropped by the caller', () {
      final ds = DataSecure(groupKeys: {0x0A03: key}, sequenceNumbers: {0x1105: 0});
      final cache = SecureTapCache();
      final frame = secured();
      final (_, first) = cache.receive(ds, 0, frame, at: at(0));
      final a = Telegram.fromCemi(first, time: at(0))!;
      cache.tag(a.raw);
      final (result, copy) = cache.receive(ds, 1, forwarded(frame), at: at(20));
      expect(result, SecureResult.decrypted);
      final b = Telegram.fromCemi(copy, time: at(20))!;
      cache.tag(b.raw);
      // As if the merger had not matched them: the first is fine, the copy alone is not.
      expect(cache.released(a.raw, merged: false), isTrue);
      expect(cache.released(b.raw, merged: false), isFalse);
      expect(cache.dropped, 1);
      // Merged (also when the copy is the origin of the entry) it is fine.
      expect(cache.released(b.raw, merged: true), isTrue);
      // Frames the cache never saw pass untouched.
      expect(cache.released(Uint8List.fromList([1, 2, 3]), merged: false), isTrue);
      expect(cache.released(const [], merged: false), isTrue);
    });

    test('a known sequence number with other content is refused at another tap point', () {
      final bus = _SecureBus(key, taps: 2);
      final frame = secured();
      bus.frame(0, frame, at(0));
      // Same sequence number, other value.
      bus.frame(1, forwarded(secured(value: 0)), at(20));
      // Tampered bytes: other MAC, other payload byte, other destination, other address type.
      for (final change in [frame.length - 1, frame.length - 5, 7, 3]) {
        final bad = forwarded(frame);
        bad[change] ^= change == 3 ? 0x80 : 0x01;
        bus.frame(1, bad, at(30));
      }
      expect(bus.rejected, 5);
      // The untouched copy still counts afterwards.
      bus.frame(1, forwarded(frame), at(40));
      expect(bus.out.single.taps.toList(), [0, 1]);
    });

    test('an older sequence number stays a replay, a newer one is a new telegram', () {
      final bus = _SecureBus(key, taps: 1);
      bus.frame(0, secured(seq: 1000), at(0));
      bus.frame(1, secured(seq: 999), at(10));
      expect(bus.rejected, 1);
      bus.frame(1, secured(seq: 1001), at(20));
      expect(bus.out, hasLength(2));
    });

    test('remembers a bounded number of telegrams', () {
      final bus = _SecureBus(key, taps: 2, hand: {1: const Duration(seconds: 5)});
      final first = secured(seq: 1);
      bus.frame(0, first, at(0));
      for (var i = 0; i < SecureTapCache.maxEntries; i++) {
        bus.frame(0, secured(seq: 2 + i), at(1));
      }
      // Pushed out by the flood: the copy meets the replay check and is refused.
      bus.frame(1, forwarded(first), at(2));
      expect(bus.rejected, 1);
    });
  });

  test('a tap point that is connected but hears nothing is reported as silent', () async {
    final links = <String, _Link>{};
    final bus = BusService(
      data,
      link: (c) => links[c.host] = _Link(c.host),
      describe: (_, _) async => null,
      telegram: (_, {required secure, required decrypted}) {},
    );
    await bus.start();
    await bus.update({
      'enabled': true,
      'mode': 'udp',
      'host': 'a',
      'taps': [
        {'name': 'Routing', 'mode': 'routing', 'host': '224.0.23.12'},
      ],
    });
    await _until(() => (bus.status()['taps'] as List).first['state'] == 'connected');
    Map<String, Object?> tap() => (bus.status()['taps'] as List).first as Map<String, Object?>;
    for (var i = 0; i < 19; i++) {
      links['a']!.receive(_ind());
    }
    await _until(() => bus.today > 0);
    expect(tap().containsKey('silent'), isFalse);
    links['a']!.receive(_ind());
    await _until(() => tap()['silent'] == true);
    links['224.0.23.12']!.receive(_ind(hop: 5));
    await _until(() => !tap().containsKey('silent'));
    await bus.shutdown();
  });

  test('without tap points nothing waits', () async {
    late _Link link;
    final lines = <Map<String, Object?>>[];
    final bus = BusService(
      data,
      link: (c) => link = _Link(c.host),
      describe: (_, _) async => null,
      telegram: (line, {required secure, required decrypted}) => lines.add(line),
    );
    await bus.start();
    await bus.update({'enabled': true, 'mode': 'udp', 'host': 'a'});
    await _until(() => bus.state == 'connected');
    link.receive(_ind());
    await _until(() => lines.isNotEmpty);
    expect(lines, hasLength(1));
    expect(bus.status().containsKey('taps'), isFalse);
    await bus.shutdown();
  });

  test('tap points from a request are checked: address, port, window, name, number', () {
    String? bad(Map<String, Object?> tap) => BusConfig.invalidChange({
      'taps': [tap],
    });
    expect(bad({'mode': 'tcp', 'host': '10.8.0.2', 'port': 3671, 'windowMs': 250, 'name': 'Linie 1.2'}), isNull);
    expect(bad({'mode': 'udp', 'host': 'knx.example.org', 'tunnelAddress': '1.2.250', 'paused': true}), isNull);
    expect(bad({'mode': 'routing', 'host': ''}), isNull);
    expect(bad({'mode': 'routing', 'host': '224.0.23.12'}), isNull);
    // Not a multicast group, no address at all, things that are not an address.
    expect(bad({'mode': 'routing', 'host': '10.0.0.1'}), isNotNull);
    expect(bad({'mode': 'udp', 'host': ''}), isNotNull);
    expect(bad({'mode': 'udp', 'host': '10.0.0.1 --flag'}), isNotNull);
    expect(bad({'mode': 'udp', 'host': 'a/b'}), isNotNull);
    // Digits and dots must be a real IPv4 address.
    expect(bad({'mode': 'udp', 'host': '300.1'}), isNotNull);
    expect(bad({'mode': 'udp', 'host': '256.1.1.1'}), isNotNull);
    expect(bad({'mode': 'udp', 'host': '10.8.0.2'}), isNull);
    expect(bad({'mode': 'udp', 'host': 'x' * 300}), isNotNull);
    expect(bad({'mode': 'secure', 'host': '10.0.0.1'}), isNotNull);
    expect(bad({'mode': 'udp', 'host': '10.0.0.1', 'port': 0}), isNotNull);
    expect(bad({'mode': 'udp', 'host': '10.0.0.1', 'port': 70000}), isNotNull);
    expect(bad({'mode': 'udp', 'host': '10.0.0.1', 'windowMs': 5}), isNotNull);
    expect(bad({'mode': 'udp', 'host': '10.0.0.1', 'windowMs': 3600000}), isNotNull);
    expect(bad({'mode': 'udp', 'host': '10.0.0.1', 'windowMs': '100'}), isNotNull);
    expect(bad({'mode': 'udp', 'host': '10.0.0.1', 'name': 'x' * 81}), isNotNull);
    expect(bad({'mode': 'udp', 'host': '10.0.0.1', 'name': 7}), isNotNull);
    expect(bad({'mode': 'udp', 'host': '10.0.0.1', 'tunnelAddress': '99.99.999'}), isNotNull);
    expect(bad({'mode': 'udp', 'host': '10.0.0.1', 'paused': 'yes'}), isNotNull);
    expect(
      BusConfig.invalidChange({
        'taps': List.filled(8, {'mode': 'udp', 'host': '10.0.0.1'}),
      }),
      isNotNull,
    );

    // A stored file is cleaned instead: unusable entries and doubles go, names lose control
    // characters (they are written to the log), at most seven stay.
    final c = BusConfig.fromJson({
      'taps': [
        {'mode': 'udp', 'host': '10.0.0.1', 'name': 'A\nB\u001b[31m'},
        {'mode': 'tcp', 'host': '10.0.0.1'},
        {'mode': 'udp', 'host': '10.0.0.1', 'port': 3672},
        {'mode': 'routing', 'host': ''},
        {'mode': 'routing', 'host': ''},
        {'mode': 'routing', 'host': '8.8.8.8'},
        {'mode': 'udp', 'host': 'bad host'},
        for (var i = 2; i < 12; i++) {'mode': 'udp', 'host': '10.0.0.$i'},
      ],
    });
    expect(c.taps, hasLength(BusConfig.maxTaps));
    expect(c.taps.first['name'], 'A B [31m');
    expect(c.taps.map((t) => '${t['mode']} ${t['host']}:${t['port']}').take(3), [
      'udp 10.0.0.1:3671',
      'udp 10.0.0.1:3672',
      'routing :3671',
    ]);
  });

  test('sending: device access over the tap point on its line, read-only holds for every tap point', () async {
    for (final readOnly in [false, true]) {
      final links = <String, _Link>{};
      final bus = BusService(
        data,
        readOnly: readOnly,
        link: (c) => links[c.host] = _Link(c.host),
        describe: (_, _) async => null,
        telegram: (_, {required secure, required decrypted}) {},
      );
      await bus.start();
      await bus.update({
        'enabled': true,
        'mode': 'udp',
        'host': 'a',
        'taps': [
          {'name': 'Linie 1.2', 'mode': 'udp', 'host': 'b'},
        ],
      });
      await _until(() => bus.state == 'connected' && (bus.status()['taps'] as List).first['state'] == 'connected');
      Uint8List to(int address, {bool group = false}) => Uint8List.fromList([
        0x11, 0x00, 0xBC, group ? 0xE0 : 0x60, 0x00, 0x00, address >> 8, address & 0xFF, 0x00, 0x80, //
      ]);
      final onLine = bus.linkFor(to(0x1214))!;
      final other = bus.linkFor(to(0x1307))!;
      final group = bus.linkFor(to(0x1214, group: true))!;
      expect(onLine.address, 0x1201, reason: '1.2.20 over the tap point on line 1.2');
      expect(other.address, 0x1101, reason: 'no tap point on 1.3: the main connection');
      expect(group.address, 0x1101, reason: 'group telegrams over the main connection');
      expect(bus.linkFor(to(0x1105))!.address, 0x1101);
      if (readOnly) {
        // Whatever link is chosen, it refuses to send.
        for (final l in [onLine, other, group]) {
          await expectLater(l.send(to(0x1214)), throwsA(isA<LinkException>()));
        }
        expect(links.values.every((l) => l.sent.isEmpty), isTrue);
      } else {
        await onLine.send(to(0x1214));
        expect((links['a']!.sent.length, links['b']!.sent.length), (0, 1));
      }
      await bus.shutdown();
    }
  });

  test('a flood at one tap point while the other is silent neither blocks nor piles up', () async {
    final links = <String, _Link>{};
    var count = 0;
    final bus = BusService(
      data,
      link: (c) => links[c.host] = _Link(c.host),
      describe: (_, _) async => null,
      telegram: (_, {required secure, required decrypted}) => count++,
    );
    await bus.start();
    await bus.update({
      'enabled': true,
      'mode': 'udp',
      'host': 'a',
      'taps': [
        {'name': 'Linie 1.2', 'mode': 'udp', 'host': 'b', 'windowMs': 5000},
      ],
    });
    await _until(() => bus.state == 'connected' && (bus.status()['taps'] as List).first['state'] == 'connected');
    // Tap point b hangs: connected, delivers nothing. 3000 different telegrams at a.
    for (var i = 0; i < 3000; i++) {
      links['a']!.receive(Uint8List.fromList([0x29, 0x00, 0xBC, 0xE0, 0x11, 0x05, i >> 8, i & 0xFF, 0x01, 0x00, 0x81]));
    }
    // Long before the 5 s window ends, all of them are through: the silent tap point is not
    // waited for, and what was held back before that was released by the limit.
    await _until(() => count == 3000);
    expect((bus.status()['taps'] as List).first['silent'], isTrue);
    await bus.shutdown();
  });
}
