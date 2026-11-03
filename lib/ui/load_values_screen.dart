import 'dart:async';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/history_store.dart';
import '../model/load_values.dart';
import '../model/telegram_log.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'charts_screen.dart';
import 'figure_box.dart';
import 'telegram_row.dart' show formatDate, formatTime;
import 'value_board.dart' show Sparkline;

/// Number of days of the long-term history that go into the usual values.
const _historyDays = 7;

/// Points of the curve per channel.
const _sparkPoints = 120;

/// Current and power from actuators with current measurement: per channel the
/// present value, history and maximum. Deliberately gets no tunnel: the view only
/// listens and cannot request anything.
class LoadValuesScreen extends StatefulWidget {
  const LoadValuesScreen({super.key, required this.log});

  final TelegramLog log;

  /// Clock for the hints; tests set their own.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  @override
  State<LoadValuesScreen> createState() => _LoadValuesScreenState();
}

class _LoadValuesScreenState extends State<LoadValuesScreen> {
  List<Telegram> _history = const [];

  /// Recomputes every few seconds instead of per telegram: the recording can be
  /// large, and load values do not change that fast.
  late final Timer _refresh = Timer.periodic(const Duration(seconds: 2), (_) {
    if (mounted) setState(() {});
  });

  @override
  void initState() {
    super.initState();
    _refresh;
    unawaited(_loadHistory());
  }

  @override
  void dispose() {
    _refresh.cancel();
    super.dispose();
  }

  /// The long-term history gives the hints enough lead time. Without it, the
  /// session recording is used.
  Future<void> _loadHistory() async {
    final store = CatalogStore.instance;
    final addresses = {
      for (final g in store.catalog.groups.values)
        if (loadKindOf(g, store.dptOf(g.address)) != null) g.address,
    };
    if (addresses.isEmpty) return;
    try {
      final days = await HistoryStore.instance.days();
      final recent = (days.toList()..sort((a, b) => b.date.compareTo(a.date))).take(_historyDays);
      final telegrams = <Telegram>[];
      for (final day in recent) {
        final recording = await HistoryStore.instance.open(day, name: '');
        telegrams.addAll(recording.telegrams.where((t) => addresses.contains(t.destination)));
      }
      if (mounted) setState(() => _history = telegrams);
    } on Object catch (e) {
      debugPrint('Verlauf für Lastwerte nicht lesbar: $e');
    }
  }

  /// History and session without duplicates (the same telegram is in both).
  Iterable<Telegram> _telegrams() {
    if (_history.isEmpty) return widget.log.log;
    final seen = {for (final t in _history) (t.time.microsecondsSinceEpoch, t.destination, t.source)};
    return [
      ..._history,
      for (final t in widget.log.log)
        if (!seen.contains((t.time.microsecondsSinceEpoch, t.destination, t.source))) t,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final store = CatalogStore.instance;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.loadTitle),
        actions: [
          InfoAction(
            title: s.loadTitle,
            text:
                '${s.loadExplain}\n\n${s.loadRulesExplain(LoadRules.baselineSamples, LoadRules.baselineSpan.inHours, (LoadRules.deviation * 100).round(), LoadRules.recent)}',
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Widths.reading),
          child: ListenableBuilder(
            listenable: store,
            builder: (context, _) {
              final channels = loadChannels(
                store.catalog.groups.values,
                _telegrams(),
                dptOf: store.dptOf,
                now: LoadValuesScreen.clock(),
              );
              if (channels.isEmpty) {
                return Center(
                  child: HorizontEmptyHint(icon: AppIcons.chart, text: s.loadNone, detail: s.loadNoneDetail),
                );
              }
              // Largest first; current and power can only be compared per kind.
              final sorted = [...channels]
                ..sort((a, b) {
                  final kind = b.kind.index.compareTo(a.kind.index);
                  return kind != 0 ? kind : (b.latest?.value ?? 0).compareTo(a.latest?.value ?? 0);
                });
              final top = sorted.firstOrNull;
              return ListView(
                padding: Gap.page,
                children: [
                  FigureBox(
                    figures: [
                      (label: s.loadChannelsLabel, value: formatInt(channels.length), status: null),
                      if (top?.latest case final latest?)
                        (label: s.loadHighest, value: formatLoad(top!.kind, latest.value), status: null),
                    ],
                  ),
                  SectionHead(s.loadConsumers, count: sorted.length),
                  RowCard(
                    flat: true,
                    children: [for (final c in sorted) _ChannelRow(channel: c, log: widget.log)],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Value with unit: current in A, power in W, or in kW from 1000 W.
String formatLoad(LoadKind kind, double value) => switch (kind) {
  LoadKind.current => '${localizeDecimal(value.toStringAsFixed(2))} A',
  LoadKind.power when value.abs() >= 1000 => '${localizeDecimal((value / 1000).toStringAsFixed(2))} kW',
  LoadKind.power => '${value.toStringAsFixed(0)} W',
};

/// Text of a hint, always with the numbers behind it and phrased as "probably".
String loadHintText(LoadKind kind, LoadHint hint) => switch (hint.kind) {
  LoadHintKind.silent => s.loadHintSilent(
    formatLoad(kind, hint.typical),
    hint.cycle?.inMinutes ?? 0,
    formatTime(hint.since!, seconds: false),
  ),
  LoadHintKind.dropped => s.loadHintDropped(formatLoad(kind, hint.typical), formatLoad(kind, hint.latest)),
  LoadHintKind.deviation => s.loadHintDeviation(
    formatLoad(kind, hint.typical),
    formatLoad(kind, hint.latest),
    '${hint.percent > 0 ? '+' : ''}${hint.percent}',
  ),
};

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({required this.channel, required this.log});

  final LoadChannel channel;
  final TelegramLog log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final latest = channel.latest;
    final peak = channel.peak;
    final recent = channel.samples.length > _sparkPoints
        ? channel.samples.sublist(channel.samples.length - _sparkPoints)
        : channel.samples;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChartsScreen(log: log, initial: [channel.address]),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: HzSpace.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(channel.group.name, style: theme.textTheme.bodyLarge),
                      Text(
                        formatGroup(channel.address),
                        style: context.mono(theme.textTheme.bodySmall).copyWith(color: hz.textFaint),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: HzSpace.s12),
                Text(
                  latest == null ? '—' : formatLoad(channel.kind, latest.value),
                  style: context.figures(theme.textTheme.bodyLarge).copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            if (recent.length >= 2) ...[
              const SizedBox(height: HzSpace.s8),
              ExcludeSemantics(
                child: SizedBox(
                  height: HzSpace.s24,
                  child: Sparkline(values: [for (final x in recent) x.value], color: hz.accentText),
                ),
              ),
            ],
            const SizedBox(height: HzSpace.s4),
            Text(
              latest == null
                  ? s.loadNoValues
                  : s.loadPeak(
                      formatLoad(channel.kind, peak!.value),
                      '${formatDate(peak.time)} ${formatTime(peak.time, seconds: false)}',
                      channel.samples.length,
                    ),
              style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint),
            ),
            if (channel.hint case final hint?) ...[
              const SizedBox(height: HzSpace.s8),
              HorizontNotice(HorizontStatus.warning, child: Text(loadHintText(channel.kind, hint))),
            ],
          ],
        ),
      ),
    );
  }
}
