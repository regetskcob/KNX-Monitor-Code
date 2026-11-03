import 'dart:async';

import 'package:flutter/foundation.dart';

import '../knx/knx_tunnel.dart';
import '../knx/telegram.dart';

/// Actually plays the write telegrams of a recording onto the bus – at the
/// original pace, with pauses shortened on request. Only in expert mode and
/// after confirmation (see the recording view).
class BusReplay extends ChangeNotifier {
  BusReplay({required this.telegrams, required this.send, this.maxGap, Future<void> Function(Duration)? wait})
    : _wait = wait ?? Future<void>.delayed;

  /// Sends via [tunnel] as GroupValueWrite.
  factory BusReplay.overTunnel(KnxTunnel tunnel, List<Telegram> telegrams, {Duration? maxGap}) => BusReplay(
    telegrams: telegrams,
    maxGap: maxGap,
    send: (t) => t.isSmall
        ? tunnel.write(t.destination, small: t.data.isEmpty ? 0 : t.data[0])
        : tunnel.write(t.destination, data: t.data),
  );

  /// Which telegrams of a recording can be replayed: write telegrams to
  /// [addresses] (`null` = all).
  static List<Telegram> writesOf(List<Telegram> telegrams, {Set<int>? addresses}) => [
    for (final t in telegrams)
      if (t.type == TelegramType.write && (addresses == null || addresses.contains(t.destination))) t,
  ];

  final List<Telegram> telegrams;

  /// Sends a telegram; result as in [KnxTunnel.sendFrame].
  final Future<bool?> Function(Telegram) send;

  /// Longest pause between two telegrams; `null` = original pace.
  final Duration? maxGap;

  final Future<void> Function(Duration) _wait;

  int sent = 0;

  /// Not acknowledged by the bus or rejected by the gateway.
  int failed = 0;

  bool running = false;
  bool _stopped = false;
  final _stop = Completer<void>();
  String? error;

  bool get done => !running && (sent + failed == telegrams.length || _stopped || error != null);
  bool get stopped => _stopped;
  double get progress => telegrams.isEmpty ? 1 : (sent + failed) / telegrams.length;

  Future<void> run() async {
    if (running) return;
    running = true;
    notifyListeners();
    try {
      for (var i = 0; i < telegrams.length && !_stopped; i++) {
        if (i > 0) {
          var gap = telegrams[i].time.difference(telegrams[i - 1].time);
          if (gap.isNegative) gap = Duration.zero;
          if (maxGap != null && gap > maxGap!) gap = maxGap!;
          // Stopping also cancels a long pause.
          if (gap > Duration.zero) await Future.any([_wait(gap), _stop.future]);
          if (_stopped) break;
        }
        try {
          final ok = await send(telegrams[i]);
          if (ok == false) {
            failed++;
          } else {
            sent++;
          }
        } on KnxException catch (e) {
          // Gateway nimmt nichts mehr an (Verbindung weg): abbrechen.
          error = e.message;
          break;
        }
        notifyListeners();
      }
    } finally {
      running = false;
      notifyListeners();
    }
  }

  void stop() {
    if (_stopped) return;
    _stopped = true;
    _stop.complete();
    notifyListeners();
  }
}
