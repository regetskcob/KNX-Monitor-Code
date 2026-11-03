import 'dart:async';

import 'knx_tunnel.dart';
import 'telegram.dart';

/// Reads group addresses one after another (5 per second spares the bus) and collects the
/// responses. Shared basis for commissioning and the health check.
abstract final class ReadSweep {
  static const interval = Duration(milliseconds: 200);
  static const answerWindow = Duration(seconds: 3);

  /// Duration for [count] addresses including the response window.
  static Duration estimate(int count) => interval * count + answerWindow;

  /// Reads [addresses] and returns the first response per address. [onSent] reports progress,
  /// [onAnswer] each response immediately, [cancelled] aborts early (then without response window).
  static Future<Map<int, Telegram>> run(
    KnxTunnel tunnel,
    List<int> addresses, {
    void Function(int sent)? onSent,
    void Function(Telegram answer)? onAnswer,
    bool Function()? cancelled,
  }) async {
    final wanted = addresses.toSet();
    final answers = <int, Telegram>{};
    final sub = tunnel.telegrams.listen((t) {
      if (t.type != TelegramType.response || !wanted.contains(t.destination)) return;
      if (answers.containsKey(t.destination)) return;
      answers[t.destination] = t;
      onAnswer?.call(t);
    });
    try {
      var sent = 0;
      for (final address in addresses) {
        if (cancelled?.call() ?? false) return answers;
        final before = DateTime.now();
        try {
          await tunnel.read(address);
        } on KnxException {
          // Do not abort on individual errors – they then count as "no response".
        }
        onSent?.call(++sent);
        final wait = interval - DateTime.now().difference(before);
        if (wait > Duration.zero) await Future<void>.delayed(wait);
      }
      if (!(cancelled?.call() ?? false)) await Future<void>.delayed(answerWindow);
      return answers;
    } finally {
      await sub.cancel();
    }
  }
}
