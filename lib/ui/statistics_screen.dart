import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../export/pdf_export.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/statistics.dart';
import '../model/telegram_log.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../theme/palette.dart';
import '../platform/addon.dart';
import '../model/filter.dart';
import 'bus_activity.dart';
import 'common.dart';
import 'heatmap.dart';
import 'telegram_row.dart';

/// Key figures without their own surface: label small in the accent color,
/// value in the text font with tabular figures, the first as the main value
/// larger and bold. [trailing] (history) sits to the right; narrow at a fixed width.
class FigureRow extends StatelessWidget {
  const FigureRow({super.key, required this.figures, this.trailing});

  /// Label and fully formatted value.
  final List<(String, String)> figures;
  final Widget? trailing;

  /// Width of the history on the phone.
  static const _narrowTrailing = 40.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final items = Wrap(
      spacing: MediaQuery.sizeOf(context).width < Breakpoints.medium ? HzSpace.s12 : HzSpace.s24,
      runSpacing: HzSpace.s12,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        for (final (i, (label, value)) in figures.indexed)
          Semantics(
            container: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(color: hz.accentText, fontWeight: FontWeight.w600),
                ),
                Text(
                  value,
                  style: i == 0
                      ? context
                            .figures(theme.textTheme.titleLarge)
                            .copyWith(color: hz.accentText, fontWeight: FontWeight.w700)
                      : context.figures(theme.textTheme.titleMedium).copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
      ],
    );
    final chart = trailing;
    if (chart == null) return Align(alignment: AlignmentDirectional.centerStart, child: items);
    // Window width instead of LayoutBuilder: the row also sits in IntrinsicHeight.
    final narrow = MediaQuery.sizeOf(context).width < Breakpoints.medium;
    return Row(
      spacing: Gap.inner,
      children: [
        Flexible(flex: 3, child: items),
        if (narrow) SizedBox(width: _narrowTrailing, child: chart) else Expanded(flex: 2, child: chart),
      ],
    );
  }
}

/// Green box for key figures, see [FigureRow].
class FigureBox extends StatelessWidget {
  const FigureBox({super.key, required this.figures, this.trailing});

  final List<(String, String)> figures;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SectionCard(
    soft: true,
    child: FigureRow(figures: figures, trailing: trailing),
  );
}

/// Statistics over the history: top senders, top addresses, "flappers", load
/// peaks. Tapping an entry filters the monitor.
class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key, required this.log, required this.onFilter, this.gateway});

  final TelegramLog log;
  final ValueChanged<String> onFilter;
  final String? gateway;

  static const _top = 15;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final store = CatalogStore.instance;
    final stats = BusStatistics.of(log);

    void filter(String q) {
      Navigator.pop(context);
      onFilter(q);
    }

    String pct(double v) => '${localizeDecimal((v * 100).toStringAsFixed(v < 0.1 ? 1 : 0))} %';

    /// Row with a share bar: address and name, the value in bold on the right,
    /// below it [meta] small and the bar in the accent color; anything notable
    /// with a warning symbol and warning color.
    Widget bar({
      required String title,
      required String value,
      required double share,
      String? meta,
      String? query,
      bool warning = false,
    }) => InkWell(
      onTap: query == null ? null : () => filter(query),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: HzSpace.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Gap.inner,
              children: [
                // Address in Monaspace, the name in the UI font.
                Expanded(child: AddressTitle(title)),
                if (warning) Icon(HorizontStatus.warning.icon, size: 16, color: hz.warning),
                Text(
                  value,
                  style: context
                      .figures(theme.textTheme.bodyLarge)
                      .copyWith(color: warning ? hz.warning : hz.text, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            if (meta != null)
              Text(meta, style: theme.textTheme.bodySmall?.copyWith(color: warning ? hz.warning : hz.textFaint)),
            const SizedBox(height: HzSpace.s8),
            LinearProgressIndicator(
              value: share.clamp(0, 1),
              minHeight: HzSpace.s4,
              borderRadius: Radii.row,
              backgroundColor: hz.sunken,
              color: warning ? hz.warning : hz.accent,
            ),
          ],
        ),
      ),
    );

    /// Rows under a section title, with a hairline between them.
    Widget rows(List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed) ...[if (i > 0) const Divider(height: Lines.hairline), child],
      ],
    );

    /// Section without a surface: title with counter, the rows below.
    Widget section(String title, int count, Widget child) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: HzSpace.s4,
      children: [
        SectionTitle(title, count: count),
        child,
      ],
    );

    final maxSender = stats.senders.isEmpty ? 1 : stats.senders.first.count;
    final maxGroup = stats.groups.isEmpty ? 1 : stats.groups.first.count;

    final sendersCard = section(
      s.statsSenders,
      stats.senders.length,
      rows([
        for (final x in stats.senders.take(_top))
          bar(
            title:
                '${formatIndividual(x.address)}  ${store.device(x.address)?.name ?? (store.catalog.devices.isEmpty ? '' : s.diagNotInProject)}',
            value: formatInt(x.count),
            meta: x.repeated > 0 ? s.statsRepeatRate(pct(x.repeatRate)) : null,
            share: x.count / maxSender,
            warning: x.repeatRate >= 0.05,
            query: senderQuery(formatIndividual(x.address)),
          ),
      ]),
    );
    final groupsCard = section(
      s.statsGroups,
      stats.groups.length,
      rows([
        for (final g in stats.groups.take(_top))
          bar(
            title: '${formatGroup(g.address)}  ${store.info(g.address)?.name ?? ''}',
            value: formatInt(g.count),
            meta: '${localizeDecimal(stats.groupPerMinute(g).toStringAsFixed(1))}/min',
            share: g.count / maxGroup,
            query: formatGroup(g.address),
          ),
      ]),
    );
    final flappersCard = section(
      s.statsFlappers,
      stats.flappers.length,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.statsFlappersHint, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
          const SizedBox(height: Gap.item),
          if (stats.flappers.isEmpty)
            Row(
              children: [
                Icon(HorizontStatus.positive.icon, size: 18, color: hz.positive),
                const SizedBox(width: Gap.item),
                Expanded(
                  child: Text(s.checkAllGood, style: TextStyle(color: hz.positive)),
                ),
              ],
            )
          else
            rows([
              for (final g in stats.flappers)
                bar(
                  title: '${formatGroup(g.address)}  ${store.info(g.address)?.name ?? ''}',
                  value: s.statsEvery(formatInterval(g.medianInterval!)),
                  share: g.count / maxGroup,
                  warning: true,
                  query: formatGroup(g.address),
                ),
            ]),
        ],
      ),
    );
    final peaksCard = section(
      s.statsPeaks,
      stats.peaks.length,
      rows([
        for (final p in stats.peaks)
          bar(
            title: '${formatDate(p.time)}  ${formatTime(p.time, millis: false)}',
            value: s.statsPerSecond(p.count),
            share: p.count / stats.peaks.first.count,
            query: timeQuery(formatTime(p.time, millis: false)),
          ),
      ]),
    );
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final heatmap = heatmapOf(log);

    return Scaffold(
      extendBody: stats.total > 0,
      appBar: AppBar(
        title: Text(s.statsTitle),
        actions: [
          Builder(
            builder: (buttonContext) => IconButton(
              tooltip: s.exportAllPdf,
              onPressed: stats.total == 0
                  ? null
                  : () => sharePdf(
                      context,
                      () async => StatisticsPdf(stats, gateway: gateway),
                      pdfName(s.statsPdfTitle),
                      origin: rectOf(buttonContext),
                    ),
              icon: Icon(AppIcons.share),
            ),
          ),
        ],
      ),
      body: stats.total == 0 && !Addon.available
          ? HorizontEmptyHint(icon: AppIcons.statistics, text: s.statsEmpty)
          : Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? double.infinity : Widths.reading),
                child: ListView(
                  // Room for the floating activity.
                  padding: Gap.page.copyWith(bottom: stats.total > 0 ? 280 : Gap.bottom),
                  children: [
                    // Add-on: analysis of the continuous recording history.
                    if (Addon.available) ...[_LongTermCard(onFilter: filter), const SizedBox(height: Gap.section)],
                    if (stats.total > 0) ...[
                      FigureBox(
                        figures: [
                          (s.statsPerMinuteShort, localizeDecimal(stats.perMinute.toStringAsFixed(1))),
                          (s.activityTotal, formatInt(stats.total)),
                          (s.statsSendersShort, formatInt(stats.senders.length)),
                          (s.statsGroupsShort, formatInt(stats.groups.length)),
                        ],
                        trailing: SizedBox(
                          height: HzSpace.s32,
                          child: ActivityBars(
                            values: activityBuckets([for (final t in log.log) t.time], 16),
                            label: s.heatmapActivity,
                          ),
                        ),
                      ),
                      const SizedBox(height: Gap.section),
                      // iPad landscape and Mac: columns instead of one long list.
                      CardColumns(
                        minWidth: 340,
                        // Rows with name, counter and rate need room: at most
                        // two columns.
                        maxColumns: 2,
                        heights: [
                          for (final n in [
                            stats.senders.length.clamp(0, _top),
                            stats.groups.length.clamp(0, _top),
                            stats.flappers.length,
                            stats.peaks.length,
                          ])
                            2.0 + n,
                        ],
                        children: [sendersCard, groupsCard, flappersCard, peaksCard],
                      ),
                    ],
                  ],
                ),
              ),
            ),
      // The activity floats pinned at the bottom edge; the lists scroll beneath it.
      bottomNavigationBar: stats.total == 0
          ? null
          // Blur over the full width: it increases in steps from top to bottom,
          // plus a gradient so no edge is visible.
          : Stack(
              children: [
                for (final (top, sigma) in const [(0.0, 0.6), (10.0, 1.4), (20.0, 2.6), (30.0, 4.5), (40.0, 7.0)])
                  Positioned.fill(
                    top: top,
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0, 0.45],
                          colors: [hz.bg.withValues(alpha: 0), hz.bg.withValues(alpha: 0.75)],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: HzSpace.s48),
                  child: SafeArea(
                    top: false,
                    child: Center(
                      heightFactor: 1,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: wide ? double.infinity : Widths.reading),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, Gap.inner),
                          // Floats only by its shadow, without a border.
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: context.hz.surface,
                              borderRadius: Radii.box,
                              boxShadow: const [
                                BoxShadow(color: Color(0x29141812), blurRadius: 22, offset: Offset(0, 6)),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(Gap.inner),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: Text(s.heatmapActivity, style: theme.textTheme.titleSmall)),
                                      Text(
                                        heatmap.scale.label,
                                        style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: Gap.item),
                                  ActivityStrip(heatmap: heatmap, onQuery: filter),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Long-term (add-on): heatmap and most active addresses/senders over days.
class _LongTermCard extends StatefulWidget {
  const _LongTermCard({required this.onFilter});

  final ValueChanged<String> onFilter;

  @override
  State<_LongTermCard> createState() => _LongTermCardState();
}

class _LongTermCardState extends State<_LongTermCard> {
  static const _choices = [1, 7, 30, 90];
  int _days = 7;
  late Future<Map<String, Object?>> _stats = Addon.stats(_days);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final store = CatalogStore.instance;
    return SectionCard(
      title: s.statsLongTerm,
      trailing: SegmentedButton<int>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [for (final d in _choices) ButtonSegment(value: d, label: Text(s.historyDays(d)))],
        selected: {_days},
        onSelectionChanged: (v) => setState(() {
          _days = v.first;
          _stats = Addon.stats(_days);
        }),
      ),
      child: FutureBuilder(
        future: _stats,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (snapshot.hasError) return Text(s.statsLongTermUnavailable, style: theme.textTheme.bodySmall);
          if (data == null) {
            return const Padding(
              padding: EdgeInsets.all(HzSpace.s24),
              child: Center(child: CircularProgressIndicator.adaptive()),
            );
          }
          final grid = [
            for (final r in data['heatmap']! as List) [for (final v in r as List) v as int],
          ];
          List<(int, int)> top(String key) => [
            for (final e in (data[key] as List? ?? const []).take(10)) ((e as List)[0] as int, e[1] as int),
          ];
          final total = data['total'] as int? ?? 0;
          // Row with hairline: address and name, the counter in bold on the right.
          Widget row(String title, int count, String query) => DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: hz.line, width: Lines.hairline),
              ),
            ),
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: AddressTitle(title, maxLines: 1),
              trailing: Text(
                formatInt(count),
                style: context.figures(theme.textTheme.bodyLarge).copyWith(fontWeight: FontWeight.w700),
              ),
              onTap: () => widget.onFilter(query),
            ),
          );
          final groups = top('groups');
          final senders = top('senders');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s.statsLongTermTotal(formatInt(total)),
                style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
              ),
              const SizedBox(height: Gap.inner),
              ActivityHeatmap.weekly(grid: grid),
              if (total > 0) ...[
                const SizedBox(height: Gap.section),
                // Wide: addresses and senders side by side.
                CardColumns(
                  minWidth: Widths.form,
                  maxColumns: 2,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionTitle(s.statsGroups),
                        const SizedBox(height: Gap.item),
                        for (final (a, n) in groups)
                          row('${formatGroup(a)}  ${store.info(a)?.name ?? ''}', n, formatGroup(a)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionTitle(s.statsSenders),
                        const SizedBox(height: Gap.item),
                        for (final (a, n) in senders)
                          row('${formatIndividual(a)}  ${store.device(a)?.name ?? ''}', n, formatIndividual(a)),
                      ],
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
