import 'dart:async';

import 'package:flutter/foundation.dart';

import '../knx/knx_tunnel.dart';

/// Reconnects on its own after a connection loss – with growing intervals, so a
/// full or restarting gateway is not queried every second. A deliberate
/// disconnect (without an error) triggers nothing.
class AutoReconnect extends ChangeNotifier {
  AutoReconnect(this.tunnel, {this.delays = defaultDelays}) {
    tunnel.state.addListener(_onState);
  }

  static const defaultDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  final KnxTunnel tunnel;
  final List<Duration> delays;

  /// A connection attempt is in progress.
  bool busy = false;

  /// Time of the next automatic attempt; `null` = none scheduled.
  DateTime? retryAt;

  int _attempt = 0;
  Timer? _timer;
  bool _disposed = false;

  bool get _lost => tunnel.state.value == TunnelState.disconnected && tunnel.error.value != null;

  void _onState() {
    if (tunnel.state.value == TunnelState.connected) {
      _attempt = 0;
      _cancel();
    } else if (_lost && !busy) {
      _schedule();
    }
  }

  void _schedule() {
    if (_timer != null || _disposed) return;
    final delay = delays[_attempt.clamp(0, delays.length - 1)];
    _attempt++;
    retryAt = DateTime.now().add(delay);
    _timer = Timer(delay, reconnectNow);
    notifyListeners();
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
    if (retryAt != null) {
      retryAt = null;
      if (!_disposed) notifyListeners();
    }
  }

  /// Connects immediately (button in the banner, returning to the foreground).
  Future<void> reconnectNow() async {
    if (busy || _disposed) return;
    _cancel();
    busy = true;
    notifyListeners();
    try {
      await tunnel.connect();
    } on KnxException catch (e) {
      tunnel.error.value = e.message;
    } finally {
      busy = false;
      if (!_disposed) {
        notifyListeners();
        if (_lost) _schedule();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    tunnel.state.removeListener(_onState);
    super.dispose();
  }
}
