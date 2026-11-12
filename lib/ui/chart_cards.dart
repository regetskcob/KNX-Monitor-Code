import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/pinned_sections.dart';
import '../model/saved_charts.dart';
import '../model/telegram_log.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'charts_screen.dart';
import 'history_chart.dart';
import 'value_board.dart';

/// Saved charts as their own section at the top of the dashboard: one card per
/// chart with a mini history and current values. Tapping opens the chart.
class ChartCardsSliver extends StatelessWidget {
  const ChartCardsSliver({super.key, required this.log, required this.onOpen, this.onAdd});

  /// "+" in the header: new chart.
  final VoidCallback? onAdd;

  final TelegramLog log;
  final ValueChanged<String> onOpen;

  static const _sectionId = 'charts';

  @override
  Widget build(BuildContext context) {
    final saved = SavedCharts.instance;
    final collapsed = CollapsedSections.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([saved, collapsed, log]),
      builder: (context, _) {
        final charts = saved.charts;
        // No charts, no empty header; new ones are then created under
        // "Diagramme" (charts).
        if (charts.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
        return SliverLayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.crossAxisExtent;
            final gutter = Gap.gutterFor(width);
            final phone = width < Breakpoints.medium;
            final columns = columnsFor(width - 2 * gutter, phone: phone);
            final names = charts.keys.toList();
            final closed = collapsed.contains(_sectionId);
            return SliverMainAxisGroup(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(gutter - HzSpace.s8, 0, gutter - HzSpace.s8, HzSpace.s4),
                  sliver: SliverToBoxAdapter(
                    child: SectionHeader(
                      title: s.chartsTitle,
                      icon: null,
                      count: charts.length,
                      activity: 0,
                      latest: null,
                      collapsed: closed,
                      onToggle: () => collapsed.toggle(_sectionId),
                      onAdd: onAdd,
                    ),
                  ),
                ),
                if (!closed)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(gutter, 0, gutter, HzSpace.s16),
                    sliver: SliverList.builder(
                      itemCount: (names.length / columns).ceil(),
                      itemBuilder: (context, line) => Padding(
                        padding: const EdgeInsets.only(bottom: HzSpace.s12),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: HzSpace.s12,
                            children: [
                              for (var c = 0; c < columns; c++)
                                Expanded(
                                  child: line * columns + c < names.length
                                      ? ChartCard(
                                          name: names[line * columns + c],
                                          addresses: charts[names[line * columns + c]]!,
                                          log: log,
                                          onTap: () => onOpen(names[line * columns + c]),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// A saved chart as a card: name, mini history of all series, below it the
/// current values.
class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.name,
    required this.addresses,
    required this.log,
    required this.onTap,
    this.footer,
  });

  final String name;
  final List<int> addresses;
  final TelegramLog log;
  final VoidCallback onTap;

  /// Below the values, e.g. "Übernehmen" (adopt) for templates.
  final Widget? footer;

  /// At most this many values below the history; the rest as "+ n".
  static const _legend = 4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final data = context.hzTheme.data;
    final store = CatalogStore.instance;
    final dark = theme.colorScheme.isDark;
    // Like the full screen: data points with time, kind per data type.
    final series = [
      for (final (i, a) in addresses.indexed)
        seriesFor(a, log, Palette.series(i, dark: dark)) ??
            ChartSeries(a, const [], ChartKind.line, store.dptOf(a), Palette.series(i, dark: dark)),
    ];
    return Material(
      color: hz.surface,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.card,
        side: BorderSide(color: hz.line, width: Lines.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(HzSpace.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
              const SizedBox(height: HzSpace.s8),
              SizedBox(
                height: HzSpace.s48,
                child: ExcludeSemantics(child: CustomPaint(painter: _MiniChartPainter(series, hz.line))),
              ),
              const SizedBox(height: HzSpace.s8),
              for (final sr in series.take(_legend))
                Row(
                  children: [
                    SizedBox.square(
                      dimension: HzSpace.s8,
                      child: ColoredBox(color: sr.color),
                    ),
                    const SizedBox(width: HzSpace.s8),
                    Expanded(
                      child: Text(
                        sr.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                      ),
                    ),
                    // Gap before the value, even if the name fills the row
                    // ("Dimmwert0 %").
                    const SizedBox(width: HzSpace.s8),
                    // Metric: last point; address: last telegram, even without
                    // a numeric value.
                    if (sr.metric != null)
                      if (sr.points.lastOrNull case final p?)
                        Text(sr.valueOf(p), style: data.copyWith(color: hz.text))
                      else
                        const SizedBox.shrink()
                    else if (log.latest[sr.address] case final t?)
                      Text(store.value(t), style: data.copyWith(color: hz.text)),
                  ],
                ),
              if (series.length > _legend) Text('+ ${series.length - _legend}', style: context.hzTheme.count),
              if (footer case final f?) ...[const Spacer(), f],
            ],
          ),
        ),
      ),
    );
  }
}

/// Simplified full screen without axes: numbers as steps over time, sharing one
/// range per unit (actual and setpoint stay comparable); switching values as
/// narrow bands at the bottom, active in the series color.
class _MiniChartPainter extends CustomPainter {
  _MiniChartPainter(this.series, this.baseline);

  final List<ChartSeries> series;
  final Color baseline;

  /// Height of a switching band.
  static const _lane = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final drawn = [
      for (final sr in series)
        if (sr.points.isNotEmpty) sr,
    ];
    final lanes = [
      for (final sr in drawn)
        if (sr.kind == ChartKind.step) sr,
    ];
    final lines = [
      for (final sr in drawn)
        if (sr.kind != ChartKind.step) sr,
    ];
    final bottom = size.height - lanes.length * (_lane + 1);
    canvas.drawLine(
      Offset(0, bottom),
      Offset(size.width, bottom),
      Paint()
        ..color = baseline
        ..strokeWidth = Lines.hairline,
    );
    if (drawn.isEmpty) return;

    final times = drawn.expand((sr) => sr.points.map((p) => p.time.microsecondsSinceEpoch));
    final a = times.reduce((p, q) => p < q ? p : q).toDouble();
    final b = times.reduce((p, q) => p > q ? p : q).toDouble();
    double x(DateTime t) => b > a ? (t.microsecondsSinceEpoch - a) / (b - a) * size.width : 0;

    // Range per unit.
    final spans = <String, (double, double)>{};
    for (final sr in lines) {
      for (final p in sr.points) {
        final (lo, hi) = spans[sr.unit] ?? (p.value, p.value);
        spans[sr.unit] = (p.value < lo ? p.value : lo, p.value > hi ? p.value : hi);
      }
    }
    for (final sr in lines) {
      final (lo, hi) = spans[sr.unit]!;
      final span = hi - lo == 0 ? 1.0 : hi - lo;
      // Without variation, centered instead of at the bottom.
      double y(double v) => hi == lo ? bottom / 2 : bottom - 2 - (v - lo) / span * (bottom - 4);
      final pts = downsample(sr.points, size.width.round());
      final path = Path()..moveTo(x(pts.first.time), y(pts.first.value));
      // Steps: a value holds until the next telegram.
      for (var i = 1; i < pts.length; i++) {
        path
          ..lineTo(x(pts[i].time), y(pts[i - 1].value))
          ..lineTo(x(pts[i].time), y(pts[i].value));
      }
      // The last value holds until the end.
      path.lineTo(size.width, y(pts.last.value));
      canvas.drawPath(
        path,
        Paint()
          ..color = sr.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = Lines.data
          ..strokeJoin = StrokeJoin.round,
      );
    }

    for (final (i, sr) in lanes.indexed) {
      final top = bottom + 1 + i * (_lane + 1);
      final on = Paint()..color = sr.color;
      final pts = sr.points;
      for (var j = 0; j < pts.length; j++) {
        if (pts[j].value < 0.5) continue;
        final end = j + 1 < pts.length ? x(pts[j + 1].time) : size.width;
        // At least one pixel so that short switching stays visible.
        final start = x(pts[j].time);
        canvas.drawRect(Rect.fromLTRB(start, top, end < start + 1 ? start + 1 : end, top + _lane), on);
      }
    }
  }

  @override
  bool shouldRepaint(_MiniChartPainter old) => true;
}

/// List of telegrams suitable as chart candidates (numeric value).
List<Telegram> chartCandidates(TelegramLog log, Iterable<Telegram> items) => [
  for (final t in items)
    if (log.history[t.destination]?.isNotEmpty ?? false) t,
];

/// Data types with a numeric or switching value (like `numericValue`).
const _chartable = {1, 5, 6, 7, 8, 9, 12, 13, 14};

/// Addresses that sent a numeric value plus the project addresses that have not
/// sent anything yet, so charts can be prepared before the telegrams arrive.
/// Still silent addresses appear as placeholders (read, no data; the picker
/// shows them with count 0 as "no telegram yet").
List<Telegram> chartChoices(TelegramLog log) {
  final store = CatalogStore.instance;
  return [
    ...chartCandidates(log, log.latest.values),
    for (final g in store.catalog.groups.values)
      if (!log.latest.containsKey(g.address) && _chartable.contains(store.dptOf(g.address)?.main))
        Telegram(
          time: DateTime.fromMillisecondsSinceEpoch(0),
          source: 0,
          destination: g.address,
          type: TelegramType.read,
          data: Uint8List(0),
          isSmall: false,
        ),
  ];
}
