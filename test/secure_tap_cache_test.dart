import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx/secure.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/secure/keyring.dart';
import 'package:knx_monitor/knx/secure/keyring_store.dart';
import 'package:knx_monitor/knx/secure/secure_tap_cache.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/model/tap_points.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';

/// As SharedTunnel: frames of the server's tap points with their number.
class _Server extends KnxTunnel {
  _Server() : super('server');
  void frame(int tap, List<int> cemi) => receiveCemiAt(tap, Uint8List.fromList(cemi));
  void live(int n) => useTaps(n);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('through the tunnel: second tap point merges, replays never become an entry, one tap point as before', () async {
    final dir = await Directory.systemTemp.createTemp('secure_taps');
    addTearDown(() => dir.delete(recursive: true));
    AppStorage.instance = IoStorage(dir);
    InstallationStore.instance.debugReset();
    final id = InstallationStore.instance.active.id;
    final keyring = Keyring.parse(File('test/resources/SecureTest.knxkeys').readAsStringSync(), 'test');
    FlutterSecureStorage.setMockInitialValues({'knx_keyring:$id': jsonEncode(keyring.toJson())});
    final keys = KeyringStore.instance;
    addTearDown(keys.clear);
    // A real secured telegram from 4.0.9 to 0/4/0 (xknx example) and its copy behind a coupler.
    final cemi = fromHex('29003ce0400904001103f110002446cfef4ac085e7092ab062b44d');
    final copy = Uint8List.fromList(cemi)..[3] = 0xD0;
    // The copy with the repeat flag set, which the MAC does not cover.
    final flipped = Uint8List.fromList(copy)..[2] = copy[2] & 0xDF;

    Future<(_Server, List<Telegram>, int)> open(int live) async {
      // Fresh sequence numbers, as on another day: the stored counters go.
      await keys.flushSequences();
      await AppStorage.instance.delete('installations/$id/${KeyringStore.sequencePath}');
      await keys.reload();
      final tunnel = _Server();
      addTearDown(tunnel.dispose);
      final got = <Telegram>[];
      final sub = tunnel.telegrams.listen(got.add);
      addTearDown(sub.cancel);
      tapLabels.value = ['4.0', '4.1'];
      tunnel.live(live);
      return (tunnel, got, keys.rejected.value);
    }

    addTearDown(() => tapLabels.value = const []);

    // The copy joins the entry; the same frame again at either tap point is a replay.
    var (tunnel, got, rejected) = await open(2);
    tunnel.frame(0, cemi);
    tunnel.frame(1, copy);
    await Future<void>.delayed(Duration.zero);
    expect(got, hasLength(1));
    expect(got.single.data, [116, 41, 41]);
    expect(got.single.taps.toList(), [0, 1]);
    expect(got.single.sightings.single.hopCount, 5);
    expect(keys.rejected.value, rejected);
    tunnel.frame(1, copy);
    tunnel.frame(0, cemi);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(got, hasLength(1));
    expect(keys.rejected.value, rejected + 2);
    secureTapCache.clear();

    // Variant 2: the copy with the repeat flag flipped merges too, it is not a second entry.
    (tunnel, got, rejected) = await open(2);
    tunnel.frame(0, cemi);
    tunnel.frame(1, flipped);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(got, hasLength(1));
    expect(got.single.taps.toList(), [0, 1]);
    expect(got.single.repeated, isFalse);
    expect(keys.rejected.value, rejected);
    secureTapCache.clear();

    // Variant 3: only one tap point is waited for (the other is silent), so the entry leaves at
    // once; the copy at the silent one is a replay.
    (tunnel, got, rejected) = await open(1);
    tunnel.frame(0, cemi);
    await Future<void>.delayed(Duration.zero);
    expect(got, hasLength(1));
    tunnel.frame(1, copy);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(got, hasLength(1));
    expect(got.single.sightings, isEmpty);
    expect(keys.rejected.value, rejected + 1);
    secureTapCache.clear();

    // Variant 1: after the window of the pair the copy is a replay, whatever else is configured.
    (tunnel, got, rejected) = await open(2);
    tunnel.frame(0, cemi);
    await Future<void>.delayed(const Duration(milliseconds: 160));
    tunnel.frame(1, copy);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(got, hasLength(1));
    expect(got.single.sightings, isEmpty);
    expect(keys.rejected.value, rejected + 1);
    secureTapCache.clear();

    // With a single tap point the cache is not asked at all: the plain replay check as before.
    (tunnel, got, rejected) = await open(1);
    tapLabels.value = const [];
    tunnel.frame(0, cemi);
    tunnel.frame(0, cemi);
    await Future<void>.delayed(Duration.zero);
    expect(got, hasLength(1));
    expect(keys.rejected.value, rejected + 1);
  });
}
