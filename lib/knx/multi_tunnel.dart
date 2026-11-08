import 'dart:async';

import 'package:flutter/foundation.dart';

import '../model/installation.dart';
import '../model/tap_points.dart';
import 'busmon.dart';
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
    for (var i = 0; i < children.length; i++) {
      final c = children[i];
      _subs.add(c.telegrams.listen((t) => _onTelegram(i, t)));
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
  final _subs = <StreamSubscription<Telegram>>[];
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
  Stream<CemiFrame> get frames => (_sender ?? children.first).frames;

  @override
  Stream<BusmonFrame> get busmon => children.first.busmon;

  void _mirror() {
    deviceName.value = children.first.deviceName.value;
    gatewayInfo.value = children.first.gatewayInfo.value;
    tunnelAddress = children.first.tunnelAddress;
  }

  String _labelOf(int i) => tapLabel(children[i].tunnelAddress, names.length > i ? names[i] : '${i + 1}');

  void _onTelegram(int tap, Telegram t) {
    if (_disposed) return;
    _emit(_merger.add(tap, t));
    _scheduleFlush();
  }

  void _emit(List<Telegram> ready) {
    if (_disposed) return;
    for (final t in ready) {
      inject(t);
    }
  }

  void _scheduleFlush() {
    _flush?.cancel();
    final due = _merger.nextDue;
    if (due == null) return;
    var wait = due.difference(DateTime.now());
    if (wait.isNegative) wait = Duration.zero;
    _flush = Timer(wait, () {
      _emit(_merger.flush(DateTime.now()));
      _scheduleFlush();
    });
  }

  void _update() {
    if (_disposed) return;
    final list = [
      for (var i = 0; i < children.length; i++)
        TapStatus(
          index: i,
          name: names.length > i ? names[i] : '${i + 1}',
          label: _labelOf(i),
          state: children[i].state.value,
          error: children[i].error.value,
          paused: _paused.contains(i),
        ),
    ];
    tapPoints.value = list;
    tapLabels.value = [for (final p in list) p.label];
    final live = list.where((p) => p.connected).length;
    _merger.taps = live < 1 ? 1 : live;
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

  @override
  Future<bool?> sendFrame(Uint8List cemi, {Duration timeout = const Duration(seconds: 3)}) {
    final sender = _sender;
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
    if (tapLabels.value.isNotEmpty) tapLabels.value = const [];
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
