import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../l10n/locale_controller.dart';
import '../model/week_summary.dart';
import '../platform/addon.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'statistics_screen.dart' show FigureRow;

/// Overview of the last seven days of the continuous recording (add-on, box): figures and
/// the findings worth a look. Loaded once when the monitor opens; hidden when the server has
/// none (older version, no history) or cannot be reached.
class WeekSummaryCard extends StatefulWidget {
  const WeekSummaryCard({super.key, this.load});

  /// Source of the overview; the add-on's `/api/summary` by default (tests pass their own).
  final Future<Map<String, Object?>> Function()? load;

  /// Findings shown before "more".
  static const shown = 3;

  @override
  State<WeekSummaryCard> createState() => _WeekSummaryCardState();
}

class _WeekSummaryCardState extends State<WeekSummaryCard> {
  late final Future<WeekSummary?> _summary = _fetch();
  bool _all = false;

  Future<WeekSummary?> _fetch() async {
    try {
      final j = await (widget.load ?? Addon.summary)();
      if (j['v'] != 1) return null;
      return WeekSummary.fromJson(j);
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<WeekSummary?>(
    future: _summary,
    builder: (context, snap) {
      final w = snap.data;
      if (w == null || (w.perDay == 0 && w.findings.isEmpty)) {
        return const SizedBox(width: double.infinity);
      }
      return _card(context, w);
    },
  );

  Widget _card(BuildContext context, WeekSummary w) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final findings = _all ? w.findings : w.findings.take(WeekSummaryCard.shown).toList();
    return SectionCard(
      soft: true,
      title: s.weekSumTitle(w.days),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(w.headline, style: theme.textTheme.bodyMedium),
          const SizedBox(height: Gap.inner),
          FigureRow(
            figures: [
              (s.weekSumPerDay, formatInt(w.perDay)),
              (s.weekSumLoad, '${formatPercent(w.loadMean)} / ${formatPercent(w.loadMax)}'),
              if (w.availability != null) (s.weekSumAvailability, formatPercent(w.availability!)),
              (s.weekSumRepeatsLabel, formatInt(w.repeats)),
            ],
          ),
          if (findings.isNotEmpty) const SizedBox(height: Gap.inner),
          for (final f in findings)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: HzSpace.s4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    f.warn ? HorizontStatus.warning.icon : HorizontStatus.info.icon,
                    size: HzIconSize.inline,
                    color: f.warn ? hz.warning : hz.textMuted,
                  ),
                  const SizedBox(width: HzSpace.s8),
                  Expanded(child: Text(f.text, style: theme.textTheme.bodySmall)),
                ],
              ),
            ),
          if (w.findings.length > WeekSummaryCard.shown)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => setState(() => _all = !_all),
                icon: Icon(_all ? AppIcons.collapse : AppIcons.expand, size: HzIconSize.inline),
                label: Text(_all ? s.weekSumLess : s.weekSumMore(w.findings.length - WeekSummaryCard.shown)),
              ),
            ),
        ],
      ),
    );
  }
}
