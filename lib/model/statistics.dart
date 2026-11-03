import '../l10n/locale_controller.dart';
import 'telegram_log.dart';

class SenderStat {
  SenderStat(this.address);
  final int address;
  int count = 0;
  int repeated = 0;
  final groups = <int>{};

  double get repeatRate => count == 0 ? 0 : repeated / count;
}

class GroupStat {
  GroupStat(this.address);
  final int address;
  int count = 0;
  final _times = <DateTime>[];

  /// Median interval between two telegrams.
  Duration? get medianInterval {
    if (_times.length < 3) return null;
    final times = [..._times]..sort();
    final gaps = [for (var i = 1; i < times.length; i++) times[i].difference(times[i - 1])]..sort();
    return gaps[gaps.length ~/ 2];
  }
}

/// Statistics over a telegram history: who loads the bus, who sends
/// conspicuously often, when were the peaks?
class BusStatistics {
  BusStatistics._(this.total, this.start, this.end, this.senders, this.groups, this.peaks);

  factory BusStatistics.of(TelegramLog log) {
    final items = log.log;
    final senders = <int, SenderStat>{};
    final groups = <int, GroupStat>{};
    final perSecond = <int, int>{};
    for (final t in items) {
      if (!t.outgoing) {
        final s = senders.putIfAbsent(t.source, () => SenderStat(t.source));
        s.count++;
        if (t.repeated) s.repeated++;
        s.groups.add(t.destination);
      }
      final g = groups.putIfAbsent(t.destination, () => GroupStat(t.destination));
      g.count++;
      g._times.add(t.time);
      final second = t.time.millisecondsSinceEpoch ~/ 1000;
      perSecond[second] = (perSecond[second] ?? 0) + 1;
    }
    final peaks =
        perSecond.entries.map((e) => (time: DateTime.fromMillisecondsSinceEpoch(e.key * 1000), count: e.value)).toList()
          ..sort((a, b) => b.count.compareTo(a.count));
    return BusStatistics._(
      items.length,
      items.isEmpty ? null : items.map((t) => t.time).reduce((a, b) => a.isBefore(b) ? a : b),
      items.isEmpty ? null : items.map((t) => t.time).reduce((a, b) => a.isAfter(b) ? a : b),
      senders.values.toList()..sort((a, b) => b.count.compareTo(a.count)),
      groups.values.toList()..sort((a, b) => b.count.compareTo(a.count)),
      peaks.take(5).toList(),
    );
  }

  /// An address that sends more often than every 10 s on average counts as "flapping".
  static const flapInterval = Duration(seconds: 10);

  final int total;
  final DateTime? start;
  final DateTime? end;
  final List<SenderStat> senders;
  final List<GroupStat> groups;

  /// Seconds with the most telegrams.
  final List<({DateTime time, int count})> peaks;

  Duration get span => start == null ? Duration.zero : end!.difference(start!);

  /// Average telegrams per minute.
  double get perMinute => span.inSeconds < 1 ? total.toDouble() : total * 60 / span.inSeconds;

  /// Addresses that send conspicuously often (cycles too short, measured values without hysteresis).
  List<GroupStat> get flappers => [
    for (final g in groups)
      if (g.medianInterval case final i? when i < flapInterval && g.count >= 10) g,
  ];

  double groupPerMinute(GroupStat g) => span.inSeconds < 1 ? g.count.toDouble() : g.count * 60 / span.inSeconds;
}

String formatInterval(Duration d) {
  if (d.inMilliseconds < 1000) return '${d.inMilliseconds} ms';
  if (d.inSeconds < 60) return '${localizeDecimal((d.inMilliseconds / 1000).toStringAsFixed(1))} s';
  return '${d.inMinutes} min';
}
