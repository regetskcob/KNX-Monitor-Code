import 'package:flutter/foundation.dart';

import '../model/telegram_log.dart';
import '../platform/addon.dart';
import 'log_view.dart' show ThrottledListenable;

/// Throttled view per log, one for all drawings so they repaint together.
final _throttled = Expando<ThrottledListenable>();

/// What device drawings listen to in order to show new values: in the Home
/// Assistant add-on (browser, many drawings in the topology) at most once per
/// second, otherwise on every telegram.
Listenable liveUpdates(TelegramLog log) {
  if (!Addon.embedded) return log;
  return _throttled[log] ??= ThrottledListenable(log, () => 1000);
}
