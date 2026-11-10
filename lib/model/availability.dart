import '../l10n/locale_controller.dart';

/// Gap in the add-on's continuous recording.
enum OutageKind {
  /// The add-on was running, but without a bus connection.
  disconnected,

  /// The add-on was not running (no sign of life).
  offline,

  /// A further tap point was not reachable ([Outage.tap]); the bus itself was recorded, only
  /// what stays in that tap point's line is missing (issue #8). No bus fault.
  tap,
}

class Outage {
  const Outage(this.from, this.to, this.kind, {this.tap});

  factory Outage.fromJson(Map<String, Object?> j) => Outage(
    DateTime.fromMillisecondsSinceEpoch(j['from']! as int),
    DateTime.fromMillisecondsSinceEpoch(j['to']! as int),
    switch (j['kind']) {
      'offline' => OutageKind.offline,
      'tap' => OutageKind.tap,
      _ => OutageKind.disconnected,
    },
    tap: j['tap'] as String?,
  );

  final DateTime from;
  final DateTime to;
  final OutageKind kind;

  /// Name of the tap point with [OutageKind.tap].
  final String? tap;

  Duration get duration => to.difference(from);
}

/// Assigns outages to calendar days (split at midnight).
Map<DateTime, List<Outage>> outagesByDay(List<Outage> outages) {
  final result = <DateTime, List<Outage>>{};
  for (final o in outages) {
    var start = o.from;
    while (start.isBefore(o.to)) {
      final day = DateTime(start.year, start.month, start.day);
      final next = DateTime(day.year, day.month, day.day + 1);
      final end = o.to.isBefore(next) ? o.to : next;
      (result[day] ??= []).add(Outage(start, end, o.kind, tap: o.tap));
      start = end;
    }
  }
  return result;
}

/// "Add-on lief 11 h 45 min nicht · Bus 3 min getrennt" (add-on down 11 h 45 min · bus disconnected 3 min).
String outageSummary(List<Outage> outages) {
  Duration sum(OutageKind k) => outages.where((o) => o.kind == k).fold(Duration.zero, (a, o) => a + o.duration);
  final offline = sum(OutageKind.offline);
  final disconnected = sum(OutageKind.disconnected);
  final taps = <String, Duration>{};
  for (final o in outages.where((o) => o.kind == OutageKind.tap)) {
    taps[o.tap ?? ''] = (taps[o.tap ?? ''] ?? Duration.zero) + o.duration;
  }
  return [
    if (offline > Duration.zero) s.outageOffline(formatDuration(offline)),
    if (disconnected > Duration.zero) s.outageDisconnected(formatDuration(disconnected)),
    for (final MapEntry(key: name, value: d) in taps.entries) s.outageTap(name, formatDuration(d)),
  ].join(' · ');
}

/// "11 h 45 min", "3 min", "< 1 min".
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0 && m == 0) return '< 1 min';
  return [if (h > 0) '$h h', if (m > 0) '$m min'].join(' ');
}
