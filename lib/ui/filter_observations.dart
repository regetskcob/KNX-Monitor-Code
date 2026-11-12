import 'package:flutter/foundation.dart';

import '../l10n/locale_controller.dart';
import '../model/coupler_filter.dart';
import '../model/installation.dart';
import '../model/recording.dart';
import '../model/tap_points.dart';
import '../model/telegram_log.dart';

/// Observation points of the active installation: the running capture and the
/// recordings that ran at the same time as another point. Other recordings stay
/// unread since they have nothing to compare. Broken ones are dropped.
Future<List<FilterObservation>> loadFilterObservations(TelegramLog? log) async {
  final out = <FilterObservation>[];
  final liveFrom = log == null || log.log.isEmpty ? null : log.log.first.time;
  final liveTo = log == null || log.log.isEmpty ? null : log.log.last.time;
  if (log != null) {
    // Several tap points (issue #8): each one with a known line observes all the time.
    final labels = TapScope.labels;
    final taps = tapObservations(
      log.log,
      {for (final (i, label) in labels.indexed) i: ?lineOfTapLabel(label)},
      name: (tap) => s.tapObservation(labels[tap]),
      away: (tap, time) => TapScope.gaps.at(tap, time) != null,
    );
    if (taps.isNotEmpty) {
      out.addAll(taps);
    } else if (FilterObservation.of(s.checkFilterLive, [...log.log]) case final live?) {
      out.add(live);
    }
  }
  try {
    final store = RecordingStore.instance;
    await store.load();
    final active = InstallationStore.instance.active.id;
    final mine = [
      for (final r in store.summaries)
        if (r.installation == null || r.installation == active) r,
    ];
    bool overlaps(DateTime aFrom, DateTime aTo, DateTime bFrom, DateTime bTo) {
      final from = aFrom.isAfter(bFrom) ? aFrom : bFrom;
      final to = aTo.isBefore(bTo) ? aTo : bTo;
      return to.difference(from) >= FilterRules.minOverlap;
    }

    for (final r in mine) {
      final useful =
          (liveFrom != null && overlaps(r.started, r.ended, liveFrom, liveTo!)) ||
          mine.any((o) => !identical(o, r) && overlaps(r.started, r.ended, o.started, o.ended));
      if (!useful) continue;
      final recording = await store.open(r.id);
      if (FilterObservation.of(r.name, recording.telegrams, from: r.started, to: r.ended) case final point?) {
        out.add(point);
      }
    }
  } on Object catch (e) {
    debugPrint('Aufnahmen für die Filterprüfung nicht lesbar: $e');
  }
  return out;
}
