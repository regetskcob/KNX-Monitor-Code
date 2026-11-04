import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/activity_range.dart';
import '../model/telegram_log.dart';
import '../monitor_model.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'telegram_row.dart';

/// Activity bar: average telegrams per minute large in Monaspace, bars of the
/// last 60 s (or hour, today), total count, counters per kind with letters, all
/// in the green box; alarms as a badge. Below it in the box, [footer] shows the
/// state of the installation.
class BusActivity extends StatelessWidget {
  const BusActivity({super.key, required this.data, this.compact = false, this.detailed = false, this.footer});

  /// Last row of the box, separated by a line.
  final Widget? footer;

  final TelegramLog data;

  /// Telefon: weniger Kennzahlen.
  final bool compact;

  /// Expert mode: additional counters per telegram kind (repetitions and
  /// unanswered read requests are shown by the filter chips).
  final bool detailed;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: ActivityRangeSetting.instance,
    builder: (context, _, _) => _build(context),
  );

  /// One size for all values of the bar (Monaspace, title-2).
  static TextStyle valueStyle(BuildContext context) =>
      context.figures(Theme.of(context).textTheme.titleMedium).copyWith(fontWeight: FontWeight.w600);

  /// Height of the value row; the bars use this height too so values and
  /// history line up.
  static double valueHeight(BuildContext context) {
    final style = valueStyle(context);
    return MediaQuery.textScalerOf(context).scale(style.fontSize! * (style.height ?? 1.3));
  }

  Widget _build(BuildContext context) {
    final hz = context.hz;
    final live = data is MonitorModel ? data as MonitorModel : null;
    final alarms = data.activeAlarmCount;
    final bins = data.activityBins;
    final value = valueStyle(context);

    final range = data.activitySwitchable
        // Zeitraum durchtippen: 60 s → Stunde → heute.
        ? Tooltip(
            message: s.activityRangeHint,
            child: InkWell(
              borderRadius: Radii.row,
              onTap: ActivityRangeSetting.instance.next,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Kennung(data.activityLabel, color: hz.accentText),
                  const SizedBox(width: HzSpace.s2),
                  Icon(AppIcons.cycle, size: 14, color: hz.accentText),
                ],
              ),
            ),
          )
        : Kennung(data.activityLabel);

    final bars = bins.isEmpty
        ? const SizedBox.shrink()
        : Semantics(
            label: s.activitySemantics(data.activityLabel),
            excludeSemantics: true,
            child: _HoverBars(
              count: bins.length,
              past: data.activityPast,
              timeOf: data.activityTimeOf,
              seconds: data.activitySwitchable && ActivityRangeSetting.instance.value == ActivityRange.seconds,
              painter: _ActivityPainter(
                values: List.of(bins),
                alarms: List.of(data.alarmBins),
                color: hz.accent,
                alarmColor: hz.critical,
                idle: hz.line,
                past: data.activityPast,
                ticks: data.activityTicks,
                tick: hz.textFaint,
              ),
            ),
          );

    final items = <Widget>[
      if (live != null)
        _StripItem(
          label: Kennung(s.statsPerMinuteShort),
          value: Text(
            formatRate(live.ratePerMinute),
            style: value.copyWith(color: hz.accentText, fontWeight: FontWeight.w700),
          ),
        ),
      _StripItem(
        label: Kennung(s.activityTotal),
        value: Text(formatInt(data.total), style: value),
      ),
      // Active alarms/faults: always visible as soon as there are any.
      if (alarms > 0)
        _StripItem(
          label: Kennung(s.activityAlarms),
          value: HorizontBadge(HorizontStatus.critical, label: '${s.alarmLabel} · ${formatInt(alarms)}'),
        ),
      if (detailed && !compact) ...[
        for (final type in Palette.order) _TypeCount(type: type, count: data.typeCounts[type]!),
        // Sent by ourselves: outlined badge as in the list.
        if (data.sentCount > 0)
          _TypeCount(type: TelegramType.write, count: data.sentCount, label: s.activitySent, outgoing: true),
      ],
    ];
    final metrics = Padding(
      padding: const EdgeInsets.fromLTRB(HzSpace.s16, HzSpace.s12, HzSpace.s16, HzSpace.s12),
      // Large text on a phone: key figures wrap, history below at full width;
      // side by side the bar would overflow.
      child: compact && MediaQuery.textScalerOf(context).scale(10) > 13
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(spacing: HzSpace.s16, runSpacing: HzSpace.s8, children: [...items.take(2)]),
                // Without history (e.g. a recording) no empty area below.
                if (bins.isNotEmpty) ...[
                  const SizedBox(height: HzSpace.s8),
                  _StripItem(
                    label: Align(alignment: AlignmentDirectional.centerEnd, child: range),
                    value: bars,
                    stretch: true,
                  ),
                ],
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: compact ? HzSpace.s16 : HzSpace.s24,
              children: [
                // Phone: rate and total, with the history next to them.
                ...compact ? items.take(2) : items,
                Expanded(
                  child: _StripItem(
                    label: Align(alignment: AlignmentDirectional.centerEnd, child: range),
                    value: bars,
                    stretch: true,
                  ),
                ),
              ],
            ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(color: hz.accentTint, borderRadius: Radii.box),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          metrics,
          if (footer case final footer?) ...[
            Divider(
              height: Lines.hairline,
              thickness: Lines.hairline,
              indent: HzSpace.s16,
              endIndent: HzSpace.s16,
              color: hz.accentText.withValues(alpha: 0.22),
            ),
            footer,
          ],
        ],
      ),
    );
  }
}

/// Column of the activity bar: eyebrow label on top, below it the value row at
/// a uniform height, so labels, values and bars line up.
class _StripItem extends StatelessWidget {
  const _StripItem({required this.label, required this.value, this.stretch = false});

  final Widget label;
  final Widget value;
  final bool stretch;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: stretch ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      label,
      const SizedBox(height: HzSpace.s4),
      SizedBox(
        height: BusActivity.valueHeight(context),
        child: stretch ? value : Align(alignment: AlignmentDirectional.bottomStart, widthFactor: 1, child: value),
      ),
    ],
  );
}

class _TypeCount extends StatelessWidget {
  const _TypeCount({required this.type, required this.count, this.label, this.outgoing = false});

  final TelegramType type;
  final int count;
  final String? label;
  final bool outgoing;

  @override
  Widget build(BuildContext context) => _StripItem(
    label: Kennung(label ?? Palette.label(type)),
    value: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TypeBadge(type: type, outgoing: outgoing, size: 20),
        const SizedBox(width: HzSpace.s8),
        Text(formatInt(count), style: BusActivity.valueStyle(context)),
      ],
    ),
  );
}

/// Bars per segment, height relative to the maximum; segments with alarms in
/// critical (the key figure next to it names them with a word and symbol).
/// Segments from [past] on lie in the future: no bars, only the baseline, so
/// the rest of the day doesn't read as a gap.
/// Bars with the time of the segment under the pointer (or finger): only
/// the time for today, otherwise date and time.
class _HoverBars extends StatefulWidget {
  const _HoverBars({
    required this.painter,
    required this.count,
    required this.past,
    required this.timeOf,
    required this.seconds,
  });

  final CustomPainter painter;
  final int count;
  final int past;
  final DateTime? Function(int segment) timeOf;

  /// Segments of one second: the time with seconds.
  final bool seconds;

  @override
  State<_HoverBars> createState() => _HoverBarsState();
}

class _HoverBarsState extends State<_HoverBars> {
  int? _segment;

  void _at(double x, double width) {
    final i = (x / (width / widget.count)).floor().clamp(0, widget.count - 1);
    if (i != _segment) setState(() => _segment = i);
  }

  void _clear() {
    if (_segment != null) setState(() => _segment = null);
  }

  /// "10:15", "10:15:42" or "03.11.2026 10:15".
  String _label(DateTime t) {
    final now = DateTime.now();
    final time = formatTime(t, seconds: widget.seconds, millis: false);
    return DateUtils.isSameDay(t, now) ? time : '${formatDate(t)} $time';
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final width = box.maxWidth;
      final i = _segment;
      final time = i == null || i >= widget.past ? null : widget.timeOf(i);
      final slot = width / widget.count;
      final hz = context.hz;
      final style = context.mono(Theme.of(context).textTheme.labelSmall).copyWith(color: hz.text);
      return MouseRegion(
        onHover: (e) => _at(e.localPosition.dx, width),
        onExit: (_) => _clear(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _at(d.localPosition.dx, width),
          onHorizontalDragUpdate: (d) => _at(d.localPosition.dx, width),
          onTapUp: (_) => _clear(),
          onHorizontalDragEnd: (_) => _clear(),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: CustomPaint(painter: widget.painter)),
              if (time != null) ...[
                // Marker over the segment, the time above it, kept inside the bars.
                Positioned(
                  left: (i! + 0.5) * slot - Lines.hairline / 2,
                  top: 0,
                  bottom: 0,
                  child: SizedBox(
                    width: Lines.hairline,
                    child: ColoredBox(color: hz.textMuted),
                  ),
                ),
                Positioned(
                  bottom: box.maxHeight + HzSpace.s2,
                  left: ((i + 0.5) * slot - 60).clamp(0.0, math.max(0.0, width - 120)),
                  width: 120,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: hz.surface,
                        borderRadius: Radii.row,
                        border: Border.all(color: hz.line, width: Lines.hairline),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: HzSpace.s4, vertical: HzSpace.s2),
                        child: Text(_label(time), style: style, maxLines: 1),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _ActivityPainter extends CustomPainter {
  _ActivityPainter({
    required this.values,
    required this.alarms,
    required this.color,
    required this.alarmColor,
    required this.idle,
    int? past,
    this.ticks = 0,
    this.tick,
  }) : past = past ?? values.length;

  /// Past segments (the rest stays empty).
  final int past;

  /// Tick mark every this many segments, e.g. every 6 hours (0 = none).
  final int ticks;
  final Color? tick;

  /// Segments with alarm messages; empty = no alarm data.
  final List<int> alarms;
  final Color alarmColor;

  /// Copy of the values at build time.
  final List<int> values;
  final Color color;
  final Color idle;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    final max = values.fold(1, (a, b) => a > b ? a : b);
    final slot = size.width / n;
    final barWidth = (slot * 0.6).clamp(1.0, 8.0);
    if (past < n) {
      // The future: a continuous baseline instead of individual ticks.
      final x0 = past * slot;
      canvas.drawRect(Rect.fromLTRB(x0, size.height - Lines.hairline, size.width, size.height), Paint()..color = idle);
    }
    if (ticks > 0 && tick != null) {
      final paint = Paint()..color = tick!;
      for (var i = ticks; i < n; i += ticks) {
        final x = i * slot;
        canvas.drawRect(
          Rect.fromLTRB(x - Lines.hairline / 2, size.height - 4, x + Lines.hairline / 2, size.height),
          paint,
        );
      }
    }
    for (var i = 0; i < math.min(past, n); i++) {
      final v = values[i];
      final h = v == 0 ? Lines.hairline : 2 + (size.height - 2) * (v / max);
      final x = i * slot + (slot - barWidth) / 2;
      final alarm = i < alarms.length && alarms[i] > 0;
      final paint = Paint()..color = v == 0 ? idle : (alarm ? alarmColor : color);
      canvas.drawRect(Rect.fromLTRB(x, size.height - h, x + barWidth, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_ActivityPainter old) =>
      old.color != color ||
      old.alarmColor != alarmColor ||
      old.idle != idle ||
      old.past != past ||
      old.ticks != ticks ||
      old.tick != tick ||
      !listEquals(old.values, values) ||
      !listEquals(old.alarms, alarms);
}

/// Compact average rate: whole numbers from 10, one decimal place below.
String formatRate(double v) => v >= 10 || v == v.roundToDouble()
    ? v.round().toString()
    : v.toStringAsFixed(1).replaceAll('.', s.localeName.startsWith('de') ? ',' : '.');

/// Only the bars of the activity bar, e.g. for a line in the topology.
class ActivityBars extends StatelessWidget {
  const ActivityBars({super.key, required this.values, required this.label});

  final List<int> values;

  /// For screen readers: time range and subject.
  final String label;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: CustomPaint(
        painter: _ActivityPainter(
          values: List.of(values),
          alarms: const [],
          color: hz.accent,
          alarmColor: hz.critical,
          idle: hz.line,
        ),
        size: Size.infinite,
      ),
    );
  }
}
