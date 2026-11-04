/// Fills gaps in the history from Home Assistant's telegram store.
///
/// In mode `ha` the KNX integration records anyway (since 2026.7 in its own
/// store, retention set there). Whatever it received while the add-on was not
/// listening – before the first start, during an update or restart, while the
/// WebSocket was down – is taken from there once the connection is up. The
/// add-on's own history stays the source for everything else; nothing is
/// replaced, only added.
library;

import 'dart:async';
import 'dart:io';

import 'ha_link.dart';
import 'recorder.dart';
import 'telegram_json.dart';

/// History line for a telegram of the store (TelegramDict); `null` if it
/// cannot be mapped.
Map<String, Object?>? haHistoryLine(Map<String, Object?> t) {
  final time = DateTime.tryParse(t['timestamp'] as String? ?? '');
  final cemi = cemiFromHa(t);
  if (time == null || cemi == null) return null;
  return telegramJson(cemi, time);
}

/// Adds the telegrams Home Assistant has from the time before [TelegramStore.liveSince]
/// that the history lacks, back to the first day retention keeps. Returns how
/// many were added.
///
/// Both sides stamp a telegram with their own time of arrival, a few
/// milliseconds apart. Around the newest recorded telegram and around the
/// start of the subscription the same telegram can be in both; there a
/// telegram counts as known if the history has one with the same sender,
/// address, type and data within [window]. [settle] waits until the first live
/// telegrams are written, so the end of the gap can be compared too.
Future<int> fillFromHomeAssistant(
  TelegramStore link,
  Recorder recorder, {
  Duration window = const Duration(seconds: 3),
  Duration settle = const Duration(seconds: 5),
}) async {
  final to = link.liveSince;
  if (to == null || !recorder.enabled) return 0;
  await Future<void>.delayed(settle);
  await recorder.flush();
  // The first day retention keeps (today and the days before it).
  final earliest = DateTime(to.year, to.month, to.day - (recorder.retentionDays - 1));
  final last = await recorder.lastTime(before: to);
  final from = last == null || last.isBefore(earliest) ? earliest : last.subtract(window);
  if (!from.isBefore(to)) return 0;

  // Recorded telegrams at both edges of the gap, by content.
  final known = <String, List<int>>{};
  final (a1, b1) = (from.subtract(window), from.add(window * 2));
  final (a2, b2) = (to.subtract(window), to.add(window));
  // When the gap is short the edges overlap; read them as one range then, so
  // each recorded line counts once (identical telegrams too).
  final edges = a2.isAfter(b1)
      ? [...await recorder.linesBetween(a1, b1), ...await recorder.linesBetween(a2, b2)]
      : await recorder.linesBetween(a1, b2.isAfter(b1) ? b2 : b1);
  for (final line in edges) {
    (known[_key(line)] ??= []).add(line['t']! as int);
  }

  var added = 0;
  await for (final page in link.storedTelegrams(from, to)) {
    for (final t in page) {
      final line = haHistoryLine(t);
      if (line == null || _seen(known, line, window)) continue;
      recorder.add(line);
      added++;
    }
    await recorder.flush();
  }
  if (added > 0) {
    // Earlier days were already packed; packing merges the new lines in.
    await recorder.maintain();
    stdout.writeln('Verlauf: $added Telegramme aus dem Telegrammspeicher von Home Assistant nachgeladen');
  }
  return added;
}

String _key(Map<String, Object?> line) => '${line['s']}|${line['d']}|${line['y']}|${line['x']}';

/// Whether the history already has [line]; each recorded telegram matches once.
bool _seen(Map<String, List<int>> known, Map<String, Object?> line, Duration window) {
  final times = known[_key(line)];
  if (times == null) return false;
  final t = line['t']! as int;
  final i = times.indexWhere((r) => (r - t).abs() <= window.inMicroseconds);
  if (i < 0) return false;
  times.removeAt(i);
  return true;
}
