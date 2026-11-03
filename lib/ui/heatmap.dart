import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../l10n/locale_controller.dart';
import '../model/telegram_log.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../model/filter.dart';

/// Resolution of the activity heatmap, chosen by the time span of the data.
enum HeatmapScale {
  /// Up to 1 h: rows per hour, columns per minute.
  minutes,

  /// Up to 12 h: rows per hour, columns per 5 minutes.
  fiveMinutes,

  /// Up to 7 days: rows per day, columns per hour.
  days,

  /// Beyond that: weekday × hour, aggregated over all weeks.
  weekly;

  /// Short suffix for the label, e.g. "je Minute" (per minute).
  String get label => switch (this) {
    minutes => s.heatmapPerMinute,
    fiveMinutes => s.heatmapPerFiveMinutes,
    days => s.heatmapPerHour,
    weekly => s.heatmapWeekly,
  };
}

/// Cells of a heatmap: labeled rows, columns with occasional axis labels, the
/// number of telegrams per cell.
class Heatmap {
  const Heatmap({
    required this.scale,
    required this.rows,
    required this.cells,
    required this.axis,
    required this.cellLabel,
    this.query,
  });

  final HeatmapScale scale;

  /// Label per row (hour "20:00", day "Sa 17.10.", weekday).
  final List<String> rows;

  /// [rows] × Spalten.
  final List<List<int>> cells;

  /// Axis label per column, `null` = none.
  final List<String?> axis;

  /// Tooltip and screen reader: the time of a cell.
  final String Function(int row, int column) cellLabel;

  /// Filter for the monitor that shows a cell's telegrams; `null` if the cell
  /// can't be expressed as a time of day (days, weekdays).
  final String? Function(int row, int column)? query;

  int get max => cells.expand((r) => r).fold(0, (a, b) => a > b ? a : b);
}

/// Telegrams per time slice, oldest to newest: [count] equally long slices
/// across the whole span. Unlike the weekly heatmap, always in chronological
/// order.
List<int> activityBuckets(List<DateTime> times, int count) {
  if (times.isEmpty) return const [];
  final first = times.reduce((a, b) => a.isBefore(b) ? a : b);
  final span = times.reduce((a, b) => a.isAfter(b) ? a : b).difference(first).inMicroseconds;
  final buckets = List.filled(count, 0);
  for (final t in times) {
    final i = span == 0 ? count - 1 : t.difference(first).inMicroseconds * count ~/ (span + 1);
    buckets[i]++;
  }
  return buckets;
}

String _two(int v) => v.toString().padLeft(2, '0');

List<String> get _weekdays => [
  s.weekdayMon,
  s.weekdayTue,
  s.weekdayWed,
  s.weekdayThu,
  s.weekdayFri,
  s.weekdaySat,
  s.weekdaySun,
];

/// Heatmap of the log's telegrams, resolution by time span: a short recording
/// shows minutes, a long one weekdays.
Heatmap heatmapOf(TelegramLog log) => heatmapForTimes([for (final t in log.log) t.time]);

/// Like [heatmapOf], for arbitrary timestamps (testable).
Heatmap heatmapForTimes(List<DateTime> times) {
  if (times.isEmpty) return weeklyHeatmap(List.generate(7, (_) => List.filled(24, 0)));
  final first = times.reduce((a, b) => a.isBefore(b) ? a : b);
  final last = times.reduce((a, b) => a.isAfter(b) ? a : b);
  final span = last.difference(first);

  if (span <= const Duration(hours: 12)) {
    final perMinute = span <= const Duration(hours: 1);
    final columns = perMinute ? 60 : 12;
    final width = perMinute ? 1 : 5;
    final startHour = DateTime(first.year, first.month, first.day, first.hour);
    final hours = last.difference(startHour).inHours + 1;
    final cells = List.generate(hours, (_) => List.filled(columns, 0));
    for (final t in times) {
      final r = t.difference(startHour).inHours.clamp(0, hours - 1);
      cells[r][t.minute ~/ width]++;
    }
    String hourOf(int r) => _two(startHour.add(Duration(hours: r)).hour);
    return Heatmap(
      scale: perMinute ? HeatmapScale.minutes : HeatmapScale.fiveMinutes,
      rows: [for (var r = 0; r < hours; r++) '${hourOf(r)}:00'],
      cells: cells,
      axis: [for (var c = 0; c < columns; c++) (c * width) % 15 == 0 ? ':${_two(c * width)}' : null],
      cellLabel: (r, c) => '${hourOf(r)}:${_two(c * width)}',
      query: (r, c) => perMinute
          ? timeQuery('${hourOf(r)}:${_two(c)}')
          : timeQuery('${hourOf(r)}:${_two(c * width)}-${hourOf(r)}:${_two(c * width + width)}'),
    );
  }

  if (span <= const Duration(days: 7)) {
    final startDay = DateTime(first.year, first.month, first.day);
    final days = DateTime(last.year, last.month, last.day).difference(startDay).inDays + 1;
    final cells = List.generate(days, (_) => List.filled(24, 0));
    for (final t in times) {
      cells[DateTime(t.year, t.month, t.day).difference(startDay).inDays][t.hour]++;
    }
    String dayOf(int r) {
      final d = startDay.add(Duration(days: r));
      return '${_weekdays[d.weekday - 1]} ${_two(d.day)}.${_two(d.month)}.';
    }

    return Heatmap(
      scale: HeatmapScale.days,
      rows: [for (var r = 0; r < days; r++) dayOf(r)],
      cells: cells,
      axis: [for (var h = 0; h < 24; h++) h % 6 == 0 ? '$h' : null],
      cellLabel: (r, h) => '${dayOf(r)} ${_two(h)}:00',
    );
  }

  final grid = List.generate(7, (_) => List.filled(24, 0));
  for (final t in times) {
    grid[t.weekday - 1][t.hour]++;
  }
  return weeklyHeatmap(grid);
}

/// Weekday × hour from a 7 × 24 grid (row 0 = Monday). In German the week
/// starts on Monday, in English on Sunday.
Heatmap weeklyHeatmap(List<List<int>> grid) {
  final order = s.localeName.startsWith('de') ? [0, 1, 2, 3, 4, 5, 6] : [6, 0, 1, 2, 3, 4, 5];
  return Heatmap(
    scale: HeatmapScale.weekly,
    rows: [for (final d in order) _weekdays[d]],
    cells: [for (final d in order) grid[d]],
    axis: [for (var h = 0; h < 24; h++) h % 6 == 0 ? '$h' : null],
    cellLabel: (r, h) => '${_weekdays[order[r]]} ${_two(h)}:00',
  );
}

/// Activity as a heatmap: shows patterns and outliers (e.g. traffic at night)
/// in the resolution that fits the time span.
/// Activity as continuous blocks from the first to the last cell with
/// telegrams, the time axis below. Darker means more; the summary names the
/// peak for screen readers, tapping filters like in the grid.
class ActivityStrip extends StatelessWidget {
  const ActivityStrip({super.key, required this.heatmap, this.onQuery});

  final Heatmap heatmap;
  final ValueChanged<String>? onQuery;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final map = heatmap;
    final max = map.max;
    final at = [
      for (var r = 0; r < map.rows.length; r++)
        for (var c = 0; c < map.axis.length; c++) (r, c),
    ];
    final first = at.indexWhere((p) => map.cells[p.$1][p.$2] > 0);
    final last = at.lastIndexWhere((p) => map.cells[p.$1][p.$2] > 0);
    if (first < 0) return Text(s.heatmapEmpty, style: Theme.of(context).textTheme.bodySmall);
    final shown = at.sublist(first, last + 1);
    final peak = shown.reduce((a, b) => map.cells[b.$1][b.$2] > map.cells[a.$1][a.$2] ? b : a);
    Widget time((int, int) p) => Text(
      map.cellLabel(p.$1, p.$2),
      style: context.figures(Theme.of(context).textTheme.labelSmall).copyWith(color: hz.textMuted),
    );
    return Semantics(
      container: true,
      label: s.heatmapPeakAt(map.cellLabel(peak.$1, peak.$2), map.cells[peak.$1][peak.$2]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Wrap(
              spacing: 2,
              runSpacing: 2,
              children: [
                for (final (r, c) in shown)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: map.cells[r][c] == 0 || onQuery == null || map.query?.call(r, c) == null
                        ? null
                        : () => onQuery!(map.query!(r, c)!),
                    child: Container(
                      width: 12,
                      height: 14,
                      decoration: BoxDecoration(
                        // Four levels; empty keeps the line color.
                        color: map.cells[r][c] == 0
                            ? hz.line
                            : Color.lerp(hz.surface, hz.accent, ((map.cells[r][c] / max) * 4).ceil() / 4),
                        borderRadius: const BorderRadius.all(Radius.circular(3)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: HzSpace.s4),
          ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [time(shown.first), if (shown.length > 2) time(shown[shown.length ~/ 2]), time(shown.last)],
            ),
          ),
        ],
      ),
    );
  }
}

class ActivityHeatmap extends StatelessWidget {
  const ActivityHeatmap({super.key, required this.heatmap, this.onQuery});

  /// Weekday × hour from a 7 × 24 grid (long-term history).
  ActivityHeatmap.weekly({super.key, required List<List<int>> grid}) : heatmap = weeklyHeatmap(grid), onQuery = null;

  final Heatmap heatmap;

  /// Tapping a cell with telegrams filters the monitor to its time.
  final ValueChanged<String>? onQuery;

  /// Whether a cell is tappable: if there is a filter and a receiver, it is
  /// also a button with time and count for screen readers, otherwise silent.
  Widget _tappable(String? query, String label, Widget cell) => query == null || onQuery == null
      ? ExcludeSemantics(child: cell)
      : Semantics(
          button: true,
          label: label,
          onTap: () => onQuery!(query),
          excludeSemantics: true,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => onQuery!(query), child: cell),
          ),
        );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final map = heatmap;
    final max = map.max;
    var peak = (0, 0);
    for (var r = 0; r < map.rows.length; r++) {
      for (var c = 0; c < map.axis.length; c++) {
        if (map.cells[r][c] > map.cells[peak.$1][peak.$2]) peak = (r, c);
      }
    }
    // Times are values: Monaspace.
    final mono = context.mono(theme.textTheme.labelSmall).copyWith(color: hz.textMuted);
    final rowLabelWidth = map.scale == HeatmapScale.days ? HzSpace.s64 + HzSpace.s12 : HzSpace.s48;
    // The summary speaks for the grid; only tappable cells stay individually
    // reachable (_tappable), labels are silent.
    return Semantics(
      container: true,
      label: max == 0 ? s.heatmapEmpty : s.heatmapPeakAt(map.cellLabel(peak.$1, peak.$2), map.cells[peak.$1][peak.$2]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var r = 0; r < map.rows.length; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: HzSpace.s2),
              child: Row(
                children: [
                  SizedBox(
                    width: rowLabelWidth,
                    child: ExcludeSemantics(child: Text(map.rows[r], style: mono)),
                  ),
                  for (var c = 0; c < map.axis.length; c++)
                    Expanded(
                      child: _tappable(
                        map.cells[r][c] == 0 ? null : map.query?.call(r, c),
                        '${map.cellLabel(r, c)} · ${map.cells[r][c]}',
                        Tooltip(
                          message: '${map.cellLabel(r, c)} · ${map.cells[r][c]}',
                          child: Container(
                            height: HzSpace.s16,
                            margin: const EdgeInsets.symmetric(horizontal: Lines.hairline),
                            decoration: BoxDecoration(
                              borderRadius: Radii.row,
                              color: map.cells[r][c] == 0 ? hz.sunken : _rampColor(hz, map.cells[r][c], max),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ExcludeSemantics(
            child: Row(
              children: [
                SizedBox(width: rowLabelWidth),
                for (final a in map.axis)
                  Expanded(
                    // Labels may draw beyond the narrow cell.
                    child: Text(a ?? '', style: mono, maxLines: 1, softWrap: false, overflow: TextOverflow.visible),
                  ),
              ],
            ),
          ),
          if (max > 0) ...[
            const SizedBox(height: HzSpace.s8),
            // Legend: the level is also shown as a number, not just as color.
            ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('1', style: mono),
                  const SizedBox(width: HzSpace.s4),
                  for (final color in _greenRamp(hz))
                    Container(
                      width: HzSpace.s12,
                      height: HzSpace.s12,
                      margin: const EdgeInsets.symmetric(horizontal: Lines.hairline),
                      decoration: BoxDecoration(borderRadius: Radii.row, color: color),
                    ),
                  const SizedBox(width: HzSpace.s4),
                  Text('$max', style: mono),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Five levels in the product's accent color (green) instead of Horizont's
/// neutral data ramp (blue): from the tint to the full accent.
List<Color> _greenRamp(HorizontColors hz) => [
  for (final t in const [0.2, 0.4, 0.6, 0.8, 1.0]) Color.lerp(hz.accentTint, hz.accent, t)!,
];

/// Ramp level for [value] from 1 to [max]: five equally wide levels.
Color _rampColor(HorizontColors hz, int value, int max) {
  final ramp = _greenRamp(hz);
  final step = (value * ramp.length / max).ceil().clamp(1, ramp.length);
  return ramp[step - 1];
}
