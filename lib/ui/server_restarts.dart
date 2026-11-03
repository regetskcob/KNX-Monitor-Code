import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../l10n/locale_controller.dart';
import 'telegram_row.dart' show formatDate, formatTime;

/// Unexpected restarts of the box or add-on, from the server status
/// (`restarts`: `{count, last: {t, lastSeen, reason}}`).
class ServerRestartsLine extends StatelessWidget {
  const ServerRestartsLine(this.restarts, {super.key});

  final Map<String, Object?> restarts;

  @override
  Widget build(BuildContext context) {
    final last = (restarts['last'] as Map?)?.cast<String, Object?>() ?? const {};
    final time = DateTime.fromMillisecondsSinceEpoch((last['t'] as int?) ?? 0);
    final reason = switch (last['reason']) {
      'error' => s.restartReasonError,
      'host' => s.restartReasonHost,
      _ => s.restartReasonUnknown,
    };
    return HorizontStatusLine(
      HorizontStatus.warning,
      s.serverRestarts(
        (restarts['count'] as int?) ?? 0,
        '${formatDate(time)} ${formatTime(time, seconds: false)}',
        reason,
      ),
    );
  }
}
