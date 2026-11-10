import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../l10n/locale_controller.dart';
import '../model/installation.dart';
import '../model/week_summary.dart';
import '../model/week_summary_prefs.dart';
import '../platform/addon.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'statistics_screen.dart' show FigureRow;

/// Overview of the last seven days of the continuous recording (add-on, box): figures and
/// the findings worth a look. Loaded once when the monitor opens; hidden when the server has
/// none (older version, no history) or cannot be reached.
///
/// It takes room, so the user decides how much ([WeekSummaryPrefs]): collapsed to the headline,
/// away for this week, or switched off (back on in the menu "More").
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
  late final Future<WeekSummary?> _summary = widget.load != null ? _fetch() : _shared();

  /// The server's overview, kept for a few minutes: the card lives in the scrolling overview and
  /// is rebuilt with it (switching between overview, objects and live), which must not ask the
  /// server again each time.
  ///
  /// Kept for one server and installation: after switching to another box or installation the
  /// card must not show the previous one's week.
  static Future<WeekSummary?>? _kept;
  static DateTime? _keptAt;
  static String? _keptFor;
  static const _keep = Duration(minutes: 5);

  Future<WeekSummary?> _shared() {
    final source = '${Addon.box?.url ?? ''}|${InstallationStore.instance.active.id}';
    final at = _keptAt;
    if (_kept == null || at == null || _keptFor != source || DateTime.now().difference(at) > _keep) {
      _kept = _fetch();
      _keptAt = DateTime.now();
      _keptFor = source;
    }
    return _kept!;
  }

  bool _all = false;
  final _prefs = WeekSummaryPrefs.instance;

  @override
  void initState() {
    super.initState();
    _prefs.load();
  }

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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _prefs,
    builder: (context, _) => FutureBuilder<WeekSummary?>(
      future: _summary,
      builder: (context, snap) {
        final w = snap.data;
        if (!_prefs.visible || w == null || (w.perDay == 0 && w.findings.isEmpty)) {
          return const SizedBox(width: double.infinity);
        }
        return _card(context, w);
      },
    ),
  );

  /// Collapse, and the menu to put the card away.
  Widget _actions() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      PopupMenuButton<VoidCallback>(
        tooltip: s.commonMore,
        icon: Icon(AppIcons.more),
        onSelected: (run) => run(),
        itemBuilder: (context) => [
          PopupMenuItem(value: _prefs.hideThisWeek, child: Text(s.weekSumHideWeek)),
          PopupMenuItem(value: () => _prefs.setShow(false), child: Text(s.weekSumHideAlways)),
        ],
      ),
      IconButton(
        tooltip: _prefs.collapsed ? s.weekSumExpand : s.weekSumCollapse,
        icon: Icon(_prefs.collapsed ? AppIcons.expand : AppIcons.collapse),
        onPressed: () => _prefs.setCollapsed(!_prefs.collapsed),
      ),
    ],
  );

  Widget _card(BuildContext context, WeekSummary w) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final findings = _all ? w.findings : w.findings.take(WeekSummaryCard.shown).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.inner),
      child: SectionCard(
        soft: true,
        title: s.weekSumTitle(w.days),
        trailing: _actions(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(w.headline, style: theme.textTheme.bodyMedium),
            if (!_prefs.collapsed) ...[
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
          ],
        ),
      ),
    );
  }
}
