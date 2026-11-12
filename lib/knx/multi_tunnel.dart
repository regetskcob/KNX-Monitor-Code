import 'dart:async';

import 'package:flutter/foundation.dart';

import '../model/installation.dart';
import '../model/tap_points.dart';
import 'busmon.dart';
import 'secure/keyring_store.dart';
import 'secure/secure_tap_cache.dart';
import 'knx_tunnel.dart';
import 'telegram.dart';

/// Several bus connections of one installation as one tunnel (issue #8, tap points).
///
/// Holds N single connections ([KnxTunnel], [RoutingTunnel], [SecureTunnel]), merges their
/// telegrams with a [TapMerger] and tags each with the tap point where it was seen first.
/// [MonitorModel] and all analyses keep working with *one* tunnel and do not need to know how many
/// connections are behind it.
///
/// - [state] is `connected` as soon as one tap point is connected; [tapPoints] has the state per tap
///   point. A tap point that drops reconnects on its own with growing intervals while the others
///   keep running. Only when every tap point is gone does [state] fall back and [error] tell why,
///   so the usual AutoReconnect takes over.
/// - Sending goes over the first connected tap point; [frames], [busmon] and the gateway details
///   are those of the first tap point (device diagnostics, send confirmation).
class MultiTunnel extends KnxTunnel {
  MultiTunnel(
    this.children, {
    required this.names,
    List<Duration?> windows = const [],
    Set<int> paused = const {},
    this.retryDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 30),
      Duration(seconds: 60),
    ],
  }) : assert(children.isNotEmpty),
       _paused = {...paused},
       super(children.first.host, port: children.first.port, tcp: children.first.tcp) {
    for (var i = 0; i < windows.length; i++) {
      if (windows[i] case final w?) _merger.windows[i] = w;
    }
    _meter = TapWindowMeter(
      current: (tap) => _merger.windows[tap] ?? _merger.window,
      auto: {
        for (var i = 0; i < children.length; i++)
          if (i >= windows.length || windows[i] == null) i,
      },
    );
    // Data Secure counts windows set by hand only, never the measured ones.
    secureTapCache.windows = Map.of(_merger.windows);
    for (var i = 0; i < children.length; i++) {
      final c = children[i];
      c.tapIndex = i;
      _subs.add(c.telegrams.listen((t) => _onTelegram(i, t)));
      _subs.add(c.frames.listen((f) => _onFrame(i, f)));
      c.state.addListener(_update);
      c.error.addListener(_update);
    }
    children.first.deviceName.addListener(_mirror);
    children.first.gatewayInfo.addListener(_mirror);
    _update();
  }

  final List<KnxTunnel> children;

  /// Names of the tap points, by number.
  final List<String> names;
  final Set<int> _paused;
  final List<Duration> retryDelays;

  final _merger = TapMerger();
  final _backlog = TapBacklog();
  final _silence = TapSilence();
  late final TapWindowMeter _meter;

  /// Windows widened by measurement ([TapWindowMeter]), by tap point.
  final _autoWindows = <int, Duration>{};
  final _live = <int>{};
  final _subs = <StreamSubscription<Object>>[];

  /// Data frames of every tap point (device diagnostics): the answer of a device comes back over
  /// the tap point that asked it, see [senderFor].
  final _allFrames = StreamController<CemiFrame>.broadcast();
  final _retry = <int, Timer>{};
  final _attempts = <int, int>{};
  Timer? _flush;
  bool _wanted = false;
  bool _disposed = false;

  @override
  String get kind => '${children.first.kind} +${children.length - 1}';

  @override
  bool get supportsBusMonitor => false;

  KnxTunnel? get _sender {
    for (final c in children) {
      if (c.state.value == TunnelState.connected) return c;
    }
    return null;
  }

  @override
  Stream<BusmonFrame> get busmon => children.first.busmon;

  void _mirror() {
    deviceName.value = children.first.deviceName.value;
    gatewayInfo.value = children.first.gatewayInfo.value;
    tunnelAddress = children.first.tunnelAddress;
  }

  String _labelOf(int i) => tapLabel(children[i].tunnelAddress, names.length > i ? names[i] : '${i + 1}');

  /// A frame a coupler forwarded arrives at several tap points; device diagnostics must see it
  /// once. The copy from another tap point within the merge window is dropped; the same frame
  /// twice at one tap point is a real double and passes.
  final _frameSeen = <String, (int, DateTime)>{};

  void _onFrame(int tap, CemiFrame f) {
    if (_disposed || _allFrames.isClosed) return;
    final key = '${f.code}|${f.source}|${f.destination}|${f.groupAddressed ? 1 : 0}|${hexOf(f.tpdu)}';
    final now = DateTime.now();
    final before = _frameSeen[key];
    if (before != null && before.$1 != tap && now.difference(before.$2) <= (_merger.windows[tap] ?? _merger.window)) {
      return;
    }
    _frameSeen.remove(key);
    _frameSeen[key] = (tap, now);
    if (_frameSeen.length > 200) _frameSeen.remove(_frameSeen.keys.first);
    _allFrames.add(f);
  }

  void _onTelegram(int tap, Telegram t) {
    if (_disposed) return;
    if (children.length > 1 && _silence.heard(tap)) _update();
    final ready = _merger.add(tap, t);
    _emit(ready);
    // Never hold back without limit (clock set back, flood).
    if (_backlog.note(fed: 1, left: TapBacklog.leaving(ready), pending: _merger.pending)) _emit(_merger.flushAll());
    _scheduleFlush();
  }

  void _emit(List<Telegram> ready) {
    if (_disposed) return;
    var widened = false;
    for (final t in ready) {
      // A Data Secure copy that did not end up in the entry of its first copy is a replay.
      if (!secureTapCache.released(t.raw, merged: t.sightings.isNotEmpty)) {
        KeyringStore.instance.rejected.value++;
        continue;
      }
      final lags = t.sightings.isEmpty ? null : [for (final s in t.sightings) _meter.lagOf(s.tap)];
      if (_meter.released(t) case (final tap, final window)?) {
        _merger.windows[tap] = window;
        window > TapWindowMeter.floor ? _autoWindows[tap] = window : _autoWindows.remove(tap);
        widened = true;
      }
      // A measured lag that changed shows in the list of tap points.
      if (lags != null && !widened) {
        for (final (i, s) in t.sightings.indexed) {
          if (_meter.lagOf(s.tap) != lags[i]) widened = true;
        }
      }
      inject(t);
    }
    if (widened) _update();
  }

  void _scheduleFlush() {
    _flush?.cancel();
    final due = _merger.nextDue;
    if (due == null) return;
    var wait = due.difference(DateTime.now());
    if (wait.isNegative) wait = Duration.zero;
    _flush = Timer(wait, () {
      final ready = _merger.flush(DateTime.now());
      _backlog.note(left: TapBacklog.leaving(ready), pending: _merger.pending);
      _emit(ready);
      _scheduleFlush();
    });
  }

  void _update() {
    if (_disposed) return;
    for (var i = 1; i < children.length; i++) {
      final up = children[i].state.value == TunnelState.connected;
      if (up && _live.add(i)) _silence.connected(i);
      if (!up && _live.remove(i)) _silence.disconnected(i);
    }
    final list = [
      for (var i = 0; i < children.length; i++)
        TapStatus(
          index: i,
          name: names.length > i ? names[i] : '${i + 1}',
          label: _labelOf(i),
          state: children[i].state.value,
          error: children[i].error.value,
          paused: _paused.contains(i),
          silent: _silence.silent(i),
          autoWindow: _autoWindows[i],
          lag: _meter.lagOf(i),
        ),
    ];
    tapPoints.value = list;
    tapLabels.value = [for (final p in list) p.label];
    final live = list.where((p) => p.connected).length;
    // A tap point that hears nothing is not waited for: entries leave once the others saw them.
    final listening = list.where((p) => p.listening).length;
    _merger.taps = listening < 1 ? 1 : listening;
    final before = state.value;
    if (live > 0) {
      state.value = TunnelState.connected;
    } else if (list.any((p) => p.state == TunnelState.connecting)) {
      state.value = TunnelState.connecting;
    } else {
      // Everything gone: let the usual AutoReconnect take over with the first reason.
      if (before == TunnelState.connected && _wanted) {
        error.value = list.map((p) => p.error).whereType<String>().firstOrNull ?? error.value;
      }
      state.value = TunnelState.disconnected;
    }
    if (_wanted) {
      for (final p in list) {
        if (!p.paused && p.state == TunnelState.disconnected && p.error != null && live > 0) _scheduleRetry(p.index);
        if (p.connected) _attempts.remove(p.index);
      }
    }
  }

  void _scheduleRetry(int i) {
    if (_retry.containsKey(i) || _disposed) return;
    final n = _attempts[i] ?? 0;
    _attempts[i] = n + 1;
    _retry[i] = Timer(retryDelays[n.clamp(0, retryDelays.length - 1)], () async {
      _retry.remove(i);
      if (!_wanted || _disposed || _paused.contains(i)) return;
      try {
        await children[i].connect();
      } on Object catch (e) {
        children[i].error.value = '$e';
      }
    });
  }

  @override
  Future<void> connect({Duration timeout = const Duration(seconds: 5)}) async {
    _wanted = true;
    error.value = null;
    Object? first;
    final attempts = [
      for (var i = 0; i < children.length; i++)
        if (!_paused.contains(i) && children[i].state.value == TunnelState.disconnected)
          children[i]
              .connect(timeout: timeout)
              .then<Object?>(
                (_) => null,
                onError: (Object e) {
                  children[i].error.value = '$e';
                  return e;
                },
              ),
    ];
    final results = await Future.wait(attempts);
    for (final r in results) {
      first ??= r;
    }
    _update();
    if (state.value != TunnelState.connected) {
      _wanted = false;
      if (first is KnxException) throw first;
      throw KnxException('${first ?? 'not connected'}');
    }
  }

  /// Pauses tap point [i] (frees its tunnel) or resumes it.
  Future<void> setPaused(int i, bool paused) async {
    if (i <= 0 || i >= children.length) return;
    if (paused) {
      _paused.add(i);
      _retry.remove(i)?.cancel();
      await children[i].disconnect();
    } else {
      _paused.remove(i);
      if (_wanted) {
        try {
          await children[i].connect();
        } on Object catch (e) {
          children[i].error.value = '$e';
        }
      }
    }
    _update();
  }

  @override
  Future<void> disconnect() async {
    _wanted = false;
    for (final t in _retry.values) {
      t.cancel();
    }
    _retry.clear();
    await Future.wait([for (final c in children) c.disconnect()]);
    _flush?.cancel();
    _emit(_merger.flushAll());
    _update();
  }

  /// The connected tap point on the line of the individual address [cemi] goes to, `null` for a
  /// group telegram or without a tap point there. Its line is that of its tunnel address.
  KnxTunnel? _onLineOf(Uint8List cemi) {
    if (cemi.length < 2) return null;
    final i = 2 + cemi[1];
    if (cemi.length < i + 6 || cemi[i + 1] & 0x80 != 0) return null;
    final line = cemi[i + 4];
    for (final c in children) {
      final own = c.tunnelAddress;
      if (c.state.value == TunnelState.connected && own != null && own != 0 && own >> 8 == line) return c;
    }
    return null;
  }

  /// The tap point that sends [cemi]: device access (individual address) goes over the tap point
  /// on the device's line, which saves coupler hops; everything else, and a device without a tap
  /// point on its line, over the first connected one.
  @visibleForTesting
  KnxTunnel? senderFor(Uint8List cemi) => _onLineOf(cemi) ?? _sender;

  @override
  Stream<CemiFrame> get frames => _allFrames.stream;

  @override
  Future<bool?> sendFrame(Uint8List cemi, {Duration timeout = const Duration(seconds: 3)}) {
    final sender = senderFor(cemi);
    if (sender == null) throw const KnxException('not connected');
    return sender.sendFrame(cemi, timeout: timeout);
  }

  @override
  void dispose() {
    _disposed = true;
    _wanted = false;
    _flush?.cancel();
    for (final t in _retry.values) {
      t.cancel();
    }
    for (final s in _subs) {
      s.cancel();
    }
    for (final c in children) {
      c.state.removeListener(_update);
      c.error.removeListener(_update);
      c.dispose();
    }
    _allFrames.close();
    super.dispose();
  }
}

/// [primary] alone, or together with the further tap points of [installation] as a [MultiTunnel]
/// (issue #8). [host] names the first tap point if the gateway has no name yet.
KnxTunnel withTapPoints(KnxTunnel primary, Installation installation, String host) {
  final taps = installation.taps;
  if (taps.isEmpty || taps.every((t) => t.paused)) return primary;
  return MultiTunnel(
    [primary, for (final t in taps) t.create()],
    names: [installation.gateway?.name ?? host, for (final t in taps) t.name],
    windows: [null, for (final t in taps) t.window],
    paused: {
      for (var i = 0; i < taps.length; i++)
        if (taps[i].paused) i + 1,
    },
  );
}
