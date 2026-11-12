import 'dart:async';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../export/dali_export.dart';
import '../export/telegram_files.dart' show csvBytes;
import '../knx/dali_text.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/dali.dart';
import '../model/dali_labels.dart';
import '../model/dali_log.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'dali_screen.dart' show DaliChoice, daliDaysChoice;
import 'dali_widgets.dart';
import 'figure_box.dart';
import 'telegram_row.dart' show formatDate, formatTime;

enum _Filter { all, open, failed }

/// Emergency lighting log: per emergency luminaire the last function and duration test, with the
/// overdue and failed ones first, and the export as PDF and CSV for the operator or inspector.
class DaliLogScreen extends StatefulWidget {
  const DaliLogScreen({super.key, this.now});

  /// Clock for tests.
  final DateTime Function()? now;

  @override
  State<DaliLogScreen> createState() => _DaliLogScreenState();
}

class _DaliLogScreenState extends State<DaliLogScreen> {
  final _log = DaliTestLog.instance;
  final _store = DaliStore.instance;

  /// Period in months; 0 = everything.
  int _months = 12;
  _Filter _filter = _Filter.all;
  List<({DateTime from, DateTime to})>? _gaps;
  bool _noHistory = false;
  bool _rebuilding = false;

  static const _periods = [1, 3, 12, 0];

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  DateTime? get _from => _months == 0 ? null : DateTime(_now.year, _now.month - _months, _now.day);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    await _store.load();
    await _log.load();
    await _findGaps();
  }

  Future<void> _findGaps() async {
    final now = _now;
    // Without a period: as far as the log reaches.
    final from = _from ?? (_log.entries.isEmpty ? now : _log.entries.first.time);
    final gaps = await _log.gaps(from, now);
    if (!mounted) return;
    setState(() {
      _gaps = gaps;
      _noHistory = gaps == null;
    });
  }

  EmergencyLogData _data() => EmergencyLogData.collect(from: _from, to: _now, gaps: _gaps ?? const []);

  Future<void> _csv(BuildContext buttonContext) => shareFile(
    context,
    csvBytes(buildEmergencyCsv(_data())),
    fileName(s.daliLogTitle, 'csv'),
    'text/csv',
    origin: rectOf(buttonContext),
  );

  Future<void> _rebuild() async {
    final messenger = ScaffoldMessenger.of(context);
    final colors = context.hz;
    setState(() => _rebuilding = true);
    try {
      final added = await _log.rebuildFromHistory();
      messenger.showSnackBar(
        horizontMessageSnackBar(
          colors,
          added == null ? s.daliLogServerKeeps : s.daliLogRebuilt(added),
          status: (added ?? 0) > 0 ? HorizontStatus.positive : HorizontStatus.info,
        ),
      );
    } finally {
      if (mounted) setState(() => _rebuilding = false);
    }
  }

  String _periodText(int months) => months == 0 ? s.daliPeriodAll : s.daliMonths(months);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_log, _store]),
    builder: (context, _) {
      final theme = Theme.of(context);
      final hz = context.hz;
      final now = _now;
      final rows = _log.overview(now);
      final shown = [
        for (final r in rows)
          if (_filter == _Filter.all || (_filter == _Filter.open && r.open) || (_filter == _Filter.failed && r.failed))
            r,
      ];
      final open = rows.where((r) => r.open).length;
      final failed = rows.where((r) => r.failed).length;
      return Scaffold(
        appBar: AppBar(
          title: Text(s.daliLogTitle),
          actions: [
            InfoAction(
              title: s.daliLogTitle,
              text: '${s.daliLogExplain}\n\n${s.daliLogRepeats}\n\n${s.daliLogTrust}\n\n${s.daliLogLimit}',
            ),
            // Less frequent actions with words, not symbols.
            PopupMenuButton<VoidCallback>(
              tooltip: s.commonMore,
              icon: Icon(AppIcons.more),
              onSelected: (action) => action(),
              itemBuilder: (_) => [
                PopupMenuItem(value: _intervals, child: Text(s.daliIntervals)),
                if (!_log.serverKeeps)
                  PopupMenuItem(value: _rebuilding ? () {} : _rebuild, child: Text(s.daliLogRebuild)),
              ],
            ),
          ],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Widths.wide),
            child: ListView(
              padding: Gap.page,
              children: [
                if (_rebuilding) const LinearProgressIndicator(minHeight: HzSpace.s4),
                Wrap(
                  spacing: HzSpace.s8,
                  runSpacing: HzSpace.s8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DropdownButton<int>(
                      // Large text: the period takes the row's width and breaks, instead of
                      // running past the edge.
                      isExpanded: MediaQuery.textScalerOf(context).scale(1) > 1.3,
                      icon: const Icon(AppIcons.expand),
                      value: _months,
                      items: [for (final m in _periods) DropdownMenuItem(value: m, child: Text(_periodText(m)))],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _months = v);
                        unawaited(_findGaps());
                      },
                    ),
                    Builder(
                      builder: (button) => OutlinedButton.icon(
                        onPressed: rows.isEmpty
                            ? null
                            : () => sharePdf(
                                context,
                                () async => EmergencyLogPdf(_data()),
                                pdfName(s.daliLogTitle),
                                origin: rectOf(button),
                              ),
                        icon: const Icon(AppIcons.pdf, size: 18),
                        label: Text(s.daliExportPdf),
                      ),
                    ),
                    Builder(
                      builder: (button) => OutlinedButton.icon(
                        onPressed: _log.entries.isEmpty ? null : () => _csv(button),
                        icon: const Icon(AppIcons.table, size: 18),
                        label: Text(s.daliExportCsv),
                      ),
                    ),
                  ],
                ),
                for (final gap in (_gaps ?? const <({DateTime from, DateTime to})>[]).take(3)) ...[
                  const SizedBox(height: Gap.item),
                  HorizontNotice(
                    HorizontStatus.warning,
                    child: Text(s.daliLogGap(formatDate(gap.from), formatDate(gap.to))),
                  ),
                ],
                if ((_gaps?.length ?? 0) > 3) ...[
                  const SizedBox(height: HzSpace.s4),
                  Text(
                    s.daliLogMoreGaps(_gaps!.length - 3),
                    style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                  ),
                ],
                for (final year in _log.limitedYears.toList()..sort()) ...[
                  const SizedBox(height: Gap.item),
                  HorizontNotice(HorizontStatus.warning, child: Text(s.daliLogLimited('$year'))),
                ],
                if (_noHistory) ...[
                  const SizedBox(height: Gap.item),
                  HorizontNotice(HorizontStatus.info, child: Text(s.daliLogNoHistory)),
                ],
                const SizedBox(height: Gap.section),
                if (rows.isEmpty)
                  HorizontEmptyHint(icon: AppIcons.light, text: s.daliLogEmpty, detail: s.daliLogEmptyDetail)
                else ...[
                  FilterBar<_Filter>(
                    segments: [
                      ButtonSegment(value: _Filter.all, label: Text('${s.daliFilterAll} · ${rows.length}')),
                      ButtonSegment(value: _Filter.open, label: Text('${s.daliFilterOpen} · $open')),
                      ButtonSegment(value: _Filter.failed, label: Text('${s.daliFilterFailed} · $failed')),
                    ],
                    selected: _filter,
                    onChanged: (f) => setState(() => _filter = f),
                  ),
                  const SizedBox(height: Gap.inner),
                  if (shown.isEmpty)
                    HorizontEmptyHint(icon: AppIcons.success, text: s.daliLogNothingHere)
                  else if (shown.length == 1)
                    // One card does not stretch over the whole width.
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: Widths.reading),
                        child: _row(context, shown.single, now),
                      ),
                    )
                  else
                    // Wide: luminaires in columns instead of one stretched list.
                    CardColumns(gap: Gap.item, children: [for (final r in shown) _row(context, r, now)]),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  String _test(String kind, EmergencyTest? e, TestDue due, DateTime now) {
    if (e == null) return '$kind$metaSeparator${s.daliLogNoResult}';
    return [
      if (e.first) '$kind$metaSeparator${s.daliAgeUnknown}' else '$kind ${daliAgo(e.time, now)}',
      [
        daliResultText(e.result),
        for (final r in e.reasons) daliReasonText(r),
        if (e.minutes case final m?) daliMinutesText(m),
      ].join(', '),
    ].join(metaSeparator);
  }

  Widget _row(BuildContext context, EmergencyOverview row, DateTime now) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final gear = row.gear;
    final name = gear == null ? s.daliEmergencyAt(formatGroup(row.group)) : daliGearLabel(gear);
    final meta = theme.textTheme.bodySmall?.copyWith(color: hz.textMuted);
    return SectionCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () => _entries(row, name),
        child: Padding(
          padding: const EdgeInsets.all(Gap.inner),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: HzSpace.s12,
            children: [
              EmergencyMark(failed: row.failed),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: HzSpace.s2,
                  children: [
                    Row(
                      spacing: HzSpace.s8,
                      children: [
                        Expanded(
                          child: Text(name, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                        ),
                        if (gear?.address case final a?) Text(s.daliAddressShort(a), style: context.mono(meta)),
                      ],
                    ),
                    Text(_test(s.daliTestFunction, row.lastFunction, row.functionDue, now), style: meta),
                    Text(_test(s.daliTestDuration, row.lastDuration, row.durationDue, now), style: meta),
                    if (row.failed) ...[
                      const SizedBox(height: HzSpace.s4),
                      HorizontBadge(HorizontStatus.critical, label: s.daliTestFailedChip),
                    ],
                    // Overdue with what it means: no new result for so long.
                    for (final (kind, last, due) in [
                      (s.daliTestFunction, row.lastFunction, row.functionDue),
                      (s.daliTestDuration, row.lastDuration, row.durationDue),
                    ])
                      if (due == TestDue.overdue) ...[
                        const SizedBox(height: HzSpace.s4),
                        HorizontStatusLine(
                          HorizontStatus.warning,
                          s.daliOverdueReason(kind, last == null ? 0 : now.difference(last.time).inDays),
                        ),
                      ],
                    if (row.foreign > 0) ...[
                      const SizedBox(height: HzSpace.s4),
                      HorizontStatusLine(HorizontStatus.info, s.daliForeignCount(row.foreign)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// All entries of one luminaire, newest first.
  Future<void> _entries(EmergencyOverview row, String name) {
    final entries = [
      for (final e in _log.entries.reversed)
        if (e.group == row.group) e,
    ];
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (sheet) {
        final theme = Theme.of(sheet);
        final hz = sheet.hz;
        return SafeArea(
          top: false,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, Gap.gutter),
            children: [
              SectionTitle(name, count: entries.length),
              const SizedBox(height: Gap.item),
              if (entries.isEmpty)
                Text(s.daliLogNoResult, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
              for (final (i, e) in entries.indexed) ...[
                if (i > 0) const Divider(height: Lines.hairline),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final raw = Text(
                        e.raw,
                        style: sheet.mono(theme.textTheme.bodySmall).copyWith(color: hz.textFaint),
                      );
                      // Large text or a narrow sheet: the raw value goes under the text instead of
                      // squeezing it into a column of broken words.
                      final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3 || box.maxWidth < 360;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: HzSpace.s12,
                        children: [
                          Icon(
                            e.result == EmergencyResult.failed
                                ? HorizontSymbols.close
                                : e.result == EmergencyResult.passed
                                ? HorizontSymbols.checkCircle
                                : HorizontSymbols.circle,
                            size: HzIconSize.row,
                            color: switch (e.result) {
                              EmergencyResult.failed => hz.critical,
                              EmergencyResult.passed => hz.positive,
                              EmergencyResult.unknown => hz.textMuted,
                            },
                            semanticLabel: daliResultText(e.result),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  [
                                    daliTestKindText(e.kind),
                                    daliResultText(e.result),
                                    for (final r in e.reasons) daliReasonText(r),
                                    if (e.minutes case final m?) daliMinutesText(m),
                                    if (e.charge case final c?) daliChargeText(c),
                                  ].join(metaSeparator),
                                ),
                                Text(
                                  [
                                    '${formatDate(e.time)} ${formatTime(e.time, seconds: false)}',
                                    if (e.start != ConverterTestStart.unknown) daliStartText(e.start),
                                    ...daliEntryNotes(e),
                                  ].join(metaSeparator),
                                  style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                                ),
                                if (stacked) raw,
                              ],
                            ),
                          ),
                          if (!stacked) raw,
                        ],
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _intervals() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (sheet) => SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: _store,
        builder: (sheet, _) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, Gap.gutter),
          children: [
            SectionTitle(s.daliIntervals),
            const SizedBox(height: HzSpace.s8),
            DaliChoice<int>(
              label: s.daliIntervalFunction,
              value: _store.settings.functionDays,
              choices: DaliSettings.functionChoices,
              text: daliDaysChoice,
              onChanged: (v) => _store.updateSettings((x) => x.functionDays = v),
            ),
            const SizedBox(height: HzSpace.s8),
            DaliChoice<int>(
              label: s.daliIntervalDuration,
              value: _store.settings.durationDays,
              choices: DaliSettings.durationChoices,
              text: daliDaysChoice,
              onChanged: (v) => _store.updateSettings((x) => x.durationDays = v),
            ),
            const SizedBox(height: Gap.inner),
            Text(s.daliLogLimit, style: Theme.of(sheet).textTheme.bodySmall?.copyWith(color: sheet.hz.textMuted)),
          ],
        ),
      ),
    ),
  );
}
