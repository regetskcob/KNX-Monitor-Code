import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/cause_chain.dart';
import '../model/expert_mode.dart';
import '../model/plain_text.dart';
import '../model/plan.dart';
import '../model/telegram_log.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'plan_screen.dart';
import 'figure_box.dart';
import 'telegram_row.dart' show formatDate, formatTime;

/// Cause chain of a telegram in the inspector: one sentence, below it the
/// telegrams before and after with their time offset. When locked (Plus), only
/// a button. Outside expert mode the rows use the same sentences as the live
/// list ([telegramSentence]).
class CauseChainView extends StatelessWidget {
  const CauseChainView({super.key, required this.telegram, required this.log, this.limit = 12});

  final Telegram telegram;

  /// Mitschnitt, zeitlich sortiert.
  final List<Telegram> log;

  /// At most this many rows per direction.
  final int limit;

  static String deviceName(int pa) {
    final d = CatalogStore.instance.device(pa);
    return d == null ? formatIndividual(pa) : '${formatIndividual(pa)} ${d.name}';
  }

  static String groupName(Telegram t) => CatalogStore.instance.infoOf(t)?.name ?? t.destinationText;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Plan.instance, ExpertMode.instance]),
      builder: (context, _) {
        if (!Plan.instance.allows(Feature.causeChain)) {
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: () => unlock(context, Feature.causeChain),
              icon: const Icon(AppIcons.locked, size: 18),
              label: Text(s.chainLocked),
            ),
          );
        }
        final chain = CauseChain.of(telegram, log, CatalogStore.instance.catalog);
        final theme = Theme.of(context);
        final hz = context.hz;
        final before = chain.before.take(limit).toList().reversed.toList();
        final after = chain.after.take(limit).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              chain.describe(title: groupName, device: deviceName),
              style: theme.textTheme.bodyMedium,
            ),
            if (before.isEmpty && after.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: HzSpace.s8),
                child: Text(s.chainQuiet, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
              ),
            if (before.isNotEmpty || after.isNotEmpty) ...[
              const SizedBox(height: HzSpace.s8),
              for (final l in before) _LinkRow(link: l),
              _FocusRow(telegram: telegram),
              for (final l in after) _LinkRow(link: l),
            ],
          ],
        );
      },
    );
  }
}

String roleLabel(ChainRole r) => switch (r) {
  ChainRole.cause => s.chainRoleCause,
  ChainRole.feedback => s.chainRoleFeedback,
  ChainRole.followUp => s.chainRoleFollowUp,
  ChainRole.coincident => s.chainRoleCoincident,
};

class _FocusRow extends StatelessWidget {
  const _FocusRow({required this.telegram});

  final Telegram telegram;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    return DecoratedBox(
      decoration: BoxDecoration(color: hz.accentTint, borderRadius: Radii.row),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: HzSpace.s8, vertical: HzSpace.s4),
        child: expert
            ? _RowContent(
                offset: s.chainThis,
                title: CauseChainView.groupName(telegram),
                detail: '${CatalogStore.instance.value(telegram)} · ${CauseChainView.deviceName(telegram.source)}',
                strong: true,
                time: telegram.time,
              )
            : _RowContent(offset: s.chainThis, title: telegramSentence(telegram), strong: true, time: telegram.time),
      ),
    );
  }
}

/// Row of the chain: offset, role and address, below it value and sender;
/// without expert mode the plain-language sentence, below it the role.
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.link});

  final ChainLink link;

  @override
  Widget build(BuildContext context) {
    final t = link.telegram;
    final ms = link.offset.inMilliseconds;
    final muted = link.role == ChainRole.coincident;
    return Opacity(
      opacity: muted ? 0.6 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: HzSpace.s8, vertical: HzSpace.s4),
        child: _RowContent(
          offset: '${ms < 0 ? '−' : '+'}${formatMs(link.offset)}',
          title: expert ? '${roleLabel(link.role)} · ${CauseChainView.groupName(t)}' : telegramSentence(t),
          detail: expert
              ? '${CatalogStore.instance.value(t)} · ${CauseChainView.deviceName(t.source)}'
              : roleLabel(link.role),
        ),
      ),
    );
  }
}

class _RowContent extends StatelessWidget {
  const _RowContent({required this.offset, required this.title, this.detail, this.strong = false, this.time});

  final String offset;
  final String title;
  final String? detail;
  final bool strong;

  /// Arrival of the telegram itself on the right (with the date if it is not
  /// today); the other rows have their offset instead.
  final DateTime? time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final data = context.hzTheme.data;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(offset, style: data.copyWith(color: hz.textMuted, fontSize: 12)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: strong ? FontWeight.w600 : null)),
              if (detail != null) Text(detail!, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
            ],
          ),
        ),
        // Same quiet style as the offsets on the left.
        if (time case final t?) ...[
          const SizedBox(width: HzSpace.s12),
          Text(
            DateUtils.isSameDay(t, DateTime.now()) ? formatTime(t) : '${formatDate(t)} ${formatTime(t)}',
            style: data.copyWith(color: hz.textMuted, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

/// Response times command → feedback per channel, slowest first.
class ReactionTimesScreen extends StatelessWidget {
  const ReactionTimesScreen({super.key, required this.log});

  final TelegramLog log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.reactTitle),
        actions: [InfoAction(title: s.reactTitle, text: s.reactExplain)],
      ),
      // The ranking runs in two or three columns up to [Widths.wide]; a single column (phone, large
      // text) and the hints of an empty page stay a reading column.
      body: ListenableBuilder(
        listenable: log,
        builder: (context, _) {
          final stats = ReactionStats.of(log.log, CatalogStore.instance.catalog);
          // Median over all measured commands, not over the channels.
          final all = [for (final r in stats) ...r.samples]..sort();
          final slowest = all.lastOrNull;
          return LayoutBuilder(
            builder: (context, box) {
              final columns = RowColumns.columnsFor(
                context,
                box.maxWidth.clamp(0, Widths.wide) - 2 * Gap.gutter,
                _StatsRow.minWidth,
              );
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: stats.isEmpty || columns == 1 ? Widths.reading : Widths.wide),
                  child: ListView(
                    padding: Gap.page,
                    children: [
                      if (stats.isEmpty)
                        Text(
                          CatalogStore.instance.catalog.isEmpty ? s.reactNoProject : s.reactEmpty,
                          style: theme.textTheme.bodyMedium,
                        )
                      else ...[
                        if (slowest != null)
                          FigureBox(
                            figures: [
                              (label: s.reactMedian, value: formatMs(all[(all.length - 1) ~/ 2]), status: null),
                              (label: s.reactSlowest, value: formatMs(slowest), status: null),
                            ],
                          ),
                        SectionHead(s.reactPairs, count: stats.length),
                        RowColumns(
                          minWidth: _StatsRow.minWidth,
                          children: [for (final r in stats) _StatsRow(stats: r, slowest: slowest)],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats, required this.slowest});

  final ReactionStats stats;

  /// Longest time of all channels: scale of the bar.
  final Duration? slowest;

  /// From here a channel counts as slow (actuators usually respond within
  /// 100–300 ms).
  static const slow = Duration(seconds: 1);

  /// Narrowest column a row still reads well in: name, both addresses and the line of figures.
  static const minWidth = 340.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final r = stats;
    final o = r.object;
    final name = o.room == null || o.title.startsWith(o.room!) ? o.title : '${o.room} ${o.title}';
    final warn = !r.measured || r.median! >= slow || r.missing > 0;
    final meta = theme.textTheme.bodySmall?.copyWith(color: hz.textFaint);
    final max = slowest?.inMicroseconds ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HzSpace.s12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  spacing: HzSpace.s4,
                  children: [
                    // Anomalies with an icon, not just color.
                    if (warn) Icon(HorizontStatus.warning.icon, size: 16, color: hz.warning),
                    Expanded(child: Text(name, style: theme.textTheme.bodyLarge)),
                  ],
                ),
                if (o.commands.firstOrNull case final command?)
                  Text(
                    [
                      formatGroup(command.address),
                      if (o.feedbacks.firstOrNull case final feedback?) formatGroup(feedback.address),
                    ].join(' → '),
                    style: context.mono(meta),
                  ),
                if (r.measured)
                  Text(s.reactLine(formatMs(r.median!), formatMs(r.p90!), formatMs(r.max!), r.count), style: meta),
                if (r.missing > 0)
                  Text(s.reactMissing(r.missing), style: theme.textTheme.bodySmall?.copyWith(color: hz.warning)),
                if (r.measured && max > 0) ...[
                  const SizedBox(height: HzSpace.s4),
                  LinearProgressIndicator(
                    value: r.median!.inMicroseconds / max,
                    minHeight: HzSpace.s4,
                    borderRadius: Radii.row,
                    color: hz.accent,
                    backgroundColor: hz.line,
                    semanticsLabel: name,
                  ),
                ],
              ],
            ),
          ),
          if (r.measured) ...[
            const SizedBox(width: HzSpace.s16),
            Text(
              formatMs(r.median!),
              style: context.figures(theme.textTheme.bodyLarge).copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}
