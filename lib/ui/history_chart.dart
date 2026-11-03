import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../knx/dpt_codec.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'telegram_row.dart';

enum ChartKind {
  /// Zahlenwerte (Temperatur, Helligkeit …).
  line,

  /// States 0/1 (switching, up/down …).
  step,

  /// No meaningful chart, list only.
  none,
}

class ChartPoint {
  const ChartPoint(this.time, this.value, this.telegram);
  final DateTime time;
  final double value;
  final Telegram telegram;
}

/// Data points of a group address and the matching chart type.
({ChartKind kind, List<ChartPoint> points}) chartData(Dpt? dpt, List<Telegram> telegrams) {
  final points = [
    for (final t in telegrams)
      if (numericValue(dpt, t) case final v?) ChartPoint(t.time, v, t),
  ];
  if (points.length < 2) return (kind: ChartKind.none, points: points);
  final binary = dpt?.main == 1 || points.every((p) => p.telegram.isSmall && p.value <= 1);
  return (kind: binary ? ChartKind.step : ChartKind.line, points: points);
}

/// Label of a value for axis and tooltip.
String chartLabel(Dpt? dpt, ChartKind kind, double v) {
  if (kind == ChartKind.step) {
    final (off, on) = dpt1Labels(dpt?.sub);
    return v >= 0.5 ? on : off;
  }
  final unit = dpt == null ? '' : dptUnit(dpt);
  final digits = v.abs() >= 100 ? 0 : (v.abs() >= 10 ? 1 : 2);
  var text = v.toStringAsFixed(digits);
  if (text.contains('.')) text = text.replaceFirst(RegExp(r'\.?0+$'), '');
  return '${localizeDecimal(text)}${unit.isEmpty ? '' : ' $unit'}';
}

/// Number like [chartLabel] but without unit, for the Y axis, above which the
/// unit is shown once.
String chartNumber(double v) => chartLabel(null, ChartKind.line, v);

/// Round Y ticks (1, 2 or 5 × 10ⁿ) between [lo] and [hi], about [count].
List<double> niceTicks(double lo, double hi, {int count = 3}) {
  final span = hi - lo;
  if (span <= 0) return [lo];
  final raw = span / math.max(1, count);
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final step = [1, 2, 5, 10].map((m) => m * mag).firstWhere((s) => s >= raw);
  return [
    for (var t = (lo / step).ceil() * step; t <= hi + step * 1e-9; t += step) double.parse(t.toStringAsFixed(10)),
  ];
}

/// Time tick intervals, from seconds to weeks.
const _timeSteps = [
  Duration(seconds: 1),
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 15),
  Duration(seconds: 30),
  Duration(minutes: 1),
  Duration(minutes: 2),
  Duration(minutes: 5),
  Duration(minutes: 10),
  Duration(minutes: 15),
  Duration(minutes: 30),
  Duration(hours: 1),
  Duration(hours: 2),
  Duration(hours: 3),
  Duration(hours: 6),
  Duration(hours: 12),
  Duration(days: 1),
  Duration(days: 2),
  Duration(days: 7),
];

/// Time ticks at round local times (full minutes, hours, midnight), at most
/// [max] between [t0] and [t1], also across DST changes.
({List<DateTime> ticks, Duration step}) timeTicks(DateTime t0, DateTime t1, int max) {
  final span = t1.difference(t0);
  final step = _timeSteps.firstWhere(
    (s) => span.inMicroseconds / s.inMicroseconds <= max,
    orElse: () => _timeSteps.last,
  );
  final ticks = <DateTime>[];
  if (step >= const Duration(days: 1)) {
    // Mitternacht; Wochen am Montag.
    var d = DateTime(t0.year, t0.month, t0.day);
    if (d.isBefore(t0)) d = DateTime(d.year, d.month, d.day + 1);
    final days = step.inDays;
    for (; !d.isAfter(t1); d = DateTime(d.year, d.month, d.day + 1)) {
      // Count calendar days in UTC: local time differences are an hour short
      // across a DST change.
      final n = days == 7
          ? d.weekday - 1
          : DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(d.year)).inDays;
      if (n % days == 0) ticks.add(d);
    }
  } else {
    // Count in seconds of the day so ticks land on round local times.
    final secs = step.inSeconds;
    int offset(DateTime t) => (secs - (t.hour * 3600 + t.minute * 60 + t.second) % secs) % secs;
    var t = DateTime(t0.year, t0.month, t0.day, t0.hour, t0.minute, t0.second);
    if (t.isBefore(t0)) t = t.add(const Duration(seconds: 1));
    t = t.add(Duration(seconds: offset(t)));
    for (; !t.isAfter(t1); t = t.add(step)) {
      // After a DST change, realign to round times.
      t = t.add(Duration(seconds: offset(t)));
      if (!t.isAfter(t1)) ticks.add(t);
    }
  }
  return (ticks: ticks, step: step);
}

/// Label of a time tick matching the interval: seconds only when needed,
/// weekday and date from one day on ("Mi 21.").
String formatTick(DateTime t, Duration step) {
  if (step >= const Duration(days: 1)) {
    final day = [s.weekdayMon, s.weekdayTue, s.weekdayWed, s.weekdayThu, s.weekdayFri, s.weekdaySat, s.weekdaySun];
    return '${day[t.weekday - 1]} ${t.day}.';
  }
  return formatTime(t, seconds: step < const Duration(minutes: 1), millis: false);
}

/// Paints the history. Used in the app and for the PDF export.
///
/// Colors and font come from the caller (theme): [color] for the line, [colors]
/// for grid, labels and mean, [label] (style `data`) for the axes. No fill, no
/// glow: lines as in Horizont.
class HistoryChartPainter extends CustomPainter {
  HistoryChartPainter({
    required this.points,
    required this.kind,
    required this.dpt,
    required this.color,
    required this.colors,
    required this.label,
    this.highlight,
    this.scale = 1,
    this.even = false,
  });

  /// Like the overview sparkline: numeric values at equal spacing instead of by
  /// time, thin line without points. Switching states stay on the time axis.
  final bool even;

  final List<ChartPoint> points;
  final ChartKind kind;
  final Dpt? dpt;
  final Color color;
  final HorizontColors colors;
  final TextStyle label;
  final int? highlight;

  /// Scale factor for images (PDF) or the user's text scale.
  final double scale;

  static const _left = 64.0;
  static const _bottom = 26.0;
  static const _top = 10.0;
  static const _right = 12.0;

  /// Axis labels one step smaller than `data` (caption instead of callout).
  static final _labelRatio = HzType.caption.size / HzType.data.size;

  /// Left margin of the plot area (room for the Y labels).
  static double plotLeft(double scale) => _left * scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final plot = Rect.fromLTRB(plotLeft(scale), _top, size.width - _right, size.height - _bottom * scale);

    var lo = points.map((p) => p.value).reduce(math.min);
    var hi = points.map((p) => p.value).reduce(math.max);
    if (kind == ChartKind.step) {
      lo = 0;
      hi = 1;
    } else if (hi - lo < 1e-9) {
      lo -= 1;
      hi += 1;
    } else {
      final pad = (hi - lo) * 0.12;
      lo -= pad;
      hi += pad;
    }
    final t0 = points.first.time.microsecondsSinceEpoch.toDouble();
    final t1 = math.max(points.last.time.microsecondsSinceEpoch.toDouble(), t0 + 1);
    final byIndex = even && kind == ChartKind.line;
    Offset at(int i) => Offset(
      byIndex
          ? plot.left + plot.width * i / (points.length - 1)
          : plot.left + plot.width * (points[i].time.microsecondsSinceEpoch - t0) / (t1 - t0),
      plot.bottom - plot.height * (points[i].value - lo) / (hi - lo),
    );

    // Grid (hairlines) and axis labels.
    final hairline = Paint()
      ..color = colors.line
      ..strokeWidth = Lines.hairline * scale;
    final ticks = kind == ChartKind.step ? [0.0, 1.0] : niceTicks(lo, hi);
    for (final v in ticks) {
      final y = plot.bottom - plot.height * (v - lo) / (hi - lo);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), hairline);
      _text(canvas, chartLabel(dpt, kind, v), Offset(plot.left - HzSpace.s8 * scale, y), align: TextAlign.right);
    }
    if (byIndex) {
      // Equal spacing instead of time: label only start and end.
      for (final (i, p) in [(0, points.first), (1, points.last)]) {
        _text(
          canvas,
          formatTime(p.time, millis: false),
          Offset(i == 0 ? plot.left : plot.right, plot.bottom + HzSpace.s4 * scale),
          align: i == 0 ? TextAlign.left : TextAlign.right,
          top: true,
        );
      }
    } else {
      // Round times of day as on the charts screen.
      final max = math.max(1, plot.width ~/ (120 * scale));
      final (:ticks, :step) = timeTicks(points.first.time, points.last.time, max);
      for (final t in ticks) {
        final x = plot.left + plot.width * (t.microsecondsSinceEpoch - t0) / (t1 - t0);
        _text(
          canvas,
          formatTick(t, step),
          Offset(x, plot.bottom + HzSpace.s4 * scale),
          align: TextAlign.center,
          top: true,
        );
      }
    }

    // Mean value dashed and neutral (numeric values only).
    if (kind == ChartKind.line) {
      final avg = points.fold(0.0, (sum, p) => sum + p.value) / points.length;
      final y = plot.bottom - plot.height * (avg - lo) / (hi - lo);
      final dash = Paint()
        ..color = colors.lineStrong
        ..strokeWidth = Lines.hairline * scale;
      final step = HzSpace.s2 * scale;
      for (var x = plot.left; x < plot.right; x += 2 * step) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + step, plot.right), y), dash);
      }
    }

    // Step line: a KNX value holds until the next telegram. Only the sparkline
    // (equal spacing, no time axis) connects points directly.
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final o = at(i);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else if (!byIndex) {
        path
          ..lineTo(o.dx, at(i - 1).dy)
          ..lineTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    if (kind == ChartKind.step) path.lineTo(plot.right, at(points.length - 1).dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = (even ? 1.5 : Lines.selection) * scale
        ..strokeJoin = even ? StrokeJoin.miter : StrokeJoin.round,
    );

    // Data points (for few values) and the last point: plain, without halo.
    final dot = Paint()..color = color;
    if (!even) {
      if (points.length <= 60) {
        for (var i = 0; i < points.length; i++) {
          canvas.drawCircle(at(i), HzSpace.s2 * scale, dot);
        }
      }
      canvas.drawCircle(at(points.length - 1), HzSpace.s4 * scale, dot);
    }

    // Highlighted point while scrubbing: hairline and dot.
    final h = highlight;
    if (h != null && h >= 0 && h < points.length) {
      final o = at(h);
      canvas.drawLine(Offset(o.dx, plot.top), Offset(o.dx, plot.bottom), hairline..color = colors.lineStrong);
      canvas.drawCircle(o, HzSpace.s4 * scale, dot);
    }
  }

  void _text(Canvas canvas, String s, Offset anchor, {required TextAlign align, bool top = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: label.copyWith(color: colors.textMuted),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(_labelRatio * scale),
    )..layout();
    final dx = switch (align) {
      TextAlign.right => anchor.dx - tp.width,
      TextAlign.center => anchor.dx - tp.width / 2,
      _ => anchor.dx,
    };
    tp.paint(canvas, Offset(dx, top ? anchor.dy : anchor.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(HistoryChartPainter old) =>
      old.points.length != points.length ||
      old.highlight != highlight ||
      old.color != color ||
      old.colors != colors ||
      old.label != label ||
      old.scale != scale ||
      old.even != even ||
      (points.isNotEmpty && !identical(old.points.last.telegram, points.last.telegram));
}

/// Interactive history chart: finger/mouse shows the nearest value.
class HistoryChart extends StatefulWidget {
  const HistoryChart({
    super.key,
    required this.points,
    required this.kind,
    required this.dpt,
    this.height = 200,
    this.even = false,
  });

  /// Equal spacing like the overview sparkline (see
  /// [HistoryChartPainter.even]).
  final bool even;

  final List<ChartPoint> points;
  final ChartKind kind;
  final Dpt? dpt;
  final double height;

  @override
  State<HistoryChart> createState() => _HistoryChartState();
}

class _HistoryChartState extends State<HistoryChart> {
  /// How long the tapped value stays visible (not a motion value).
  static const _hold = Duration(seconds: 2);

  int? _highlight;

  void _pick(double dx, double width, double scale) {
    final pts = widget.points;
    if (pts.length < 2) return;
    final left = HistoryChartPainter.plotLeft(scale);
    final rel = ((dx - left) / (width - left - HistoryChartPainter._right)).clamp(0.0, 1.0);
    if (widget.even && widget.kind == ChartKind.line) {
      final i = (rel * (pts.length - 1)).round();
      if (i != _highlight) setState(() => _highlight = i);
      return;
    }
    final t0 = pts.first.time.microsecondsSinceEpoch;
    final target = t0 + (pts.last.time.microsecondsSinceEpoch - t0) * rel;
    var best = 0;
    for (var i = 1; i < pts.length; i++) {
      if ((pts[i].time.microsecondsSinceEpoch - target).abs() <
          (pts[best].time.microsecondsSinceEpoch - target).abs()) {
        best = i;
      }
    }
    if (best != _highlight) setState(() => _highlight = best);
  }

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final data = context.hzTheme.data;
    // Axis text grows with the user's text scale.
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final h = _highlight;
    final picked = h == null || h >= widget.points.length ? null : widget.points[h];

    return Semantics(
      label: s.chartSemantics(widget.points.length, chartLabel(widget.dpt, widget.kind, widget.points.last.value)),
      child: LayoutBuilder(
        builder: (context, c) => GestureDetector(
          onTapDown: (d) => _pick(d.localPosition.dx, c.maxWidth, scale),
          onHorizontalDragUpdate: (d) => _pick(d.localPosition.dx, c.maxWidth, scale),
          onHorizontalDragEnd: (_) => setState(() => _highlight = null),
          onTapUp: (_) => Future.delayed(_hold, () {
            if (mounted) setState(() => _highlight = null);
          }),
          child: MouseRegion(
            onHover: (e) => _pick(e.localPosition.dx, c.maxWidth, scale),
            onExit: (_) => setState(() => _highlight = null),
            child: Stack(
              children: [
                SizedBox(
                  height: widget.height,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: HistoryChartPainter(
                      points: widget.points,
                      kind: widget.kind,
                      dpt: widget.dpt,
                      color: hz.accent,
                      colors: hz,
                      label: data,
                      highlight: h,
                      scale: scale,
                      even: widget.even,
                    ),
                  ),
                ),
                if (picked != null)
                  Positioned(
                    top: 0,
                    right: HzSpace.s12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: HzSpace.s8, vertical: HzSpace.s4),
                      decoration: BoxDecoration(
                        color: hz.surface,
                        borderRadius: Radii.tile,
                        border: Border.all(color: hz.line, width: Lines.hairline),
                      ),
                      child: Text(
                        '${chartLabel(widget.dpt, widget.kind, picked.value)}$metaSeparator${formatTime(picked.time)}',
                        style: data.copyWith(color: hz.text),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders the chart as PNG (for the PDF export) in app style, always light.
Future<ui.Image> renderChartImage(
  List<ChartPoint> points,
  ChartKind kind,
  Dpt? dpt, {
  Size size = const Size(1600, 600),
}) {
  final light = AppTheme.light().extension<HorizontTheme>()!;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & size, Paint()..color = light.colors.surface);
  HistoryChartPainter(
    points: points,
    kind: kind,
    dpt: dpt,
    color: light.colors.accent,
    colors: light.colors,
    label: light.data,
    scale: 2.2,
  ).paint(canvas, size);
  return recorder.endRecording().toImage(size.width.toInt(), size.height.toInt());
}
