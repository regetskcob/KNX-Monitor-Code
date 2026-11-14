import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../l10n/locale_controller.dart';
import '../model/heating_check.dart';
import '../model/telegram_log.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'figure_box.dart';

/// Heating check: per room the actual temperature, the setpoint and the valve
/// side by side, with a verdict in plain words that says whom to ask. For
/// people who are not electricians: it reads only and explains.
class HeatingCheckScreen extends StatefulWidget {
  const HeatingCheckScreen({super.key, required this.log});

  final TelegramLog log;

  /// Time to judge at; tests set their own.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  @override
  State<HeatingCheckScreen> createState() => _HeatingCheckScreenState();
}

class _HeatingCheckScreenState extends State<HeatingCheckScreen> {
  late List<HeatingRoom> _rooms = _check();

  /// Not per telegram: the check walks the whole recording.
  late final _timer = Timer.periodic(const Duration(seconds: 5), (_) => setState(() => _rooms = _check()));

  List<HeatingRoom> _check() {
    final rooms = checkHeating(
      CatalogStore.instance.catalog,
      widget.log.latest,
      widget.log.log,
      now: HeatingCheckScreen.clock(),
    );
    // What needs attention first.
    return rooms..sort((a, b) {
      if (a.verdict.issue != b.verdict.issue) return a.verdict.issue ? -1 : 1;
      return a.room.compareTo(b.room);
    });
  }

  @override
  void initState() {
    super.initState();
    _timer;
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  static String _degrees(double? v) => v == null ? '–' : '${v.toStringAsFixed(1).replaceAll('.', decimalSeparator)} °C';
  static String _percent(double? v) => v == null ? '–' : '${v.round()} %';

  static String _title(HeatingVerdict v) => switch (v) {
    HeatingVerdict.noData => s.heatNoData,
    HeatingVerdict.incomplete => s.heatIncomplete,
    HeatingVerdict.staleActual => s.heatStale,
    HeatingVerdict.notCalling => s.heatNotCalling,
    HeatingVerdict.notWarming => s.heatNotWarming,
    HeatingVerdict.overheating => s.heatOverheating,
    HeatingVerdict.heating => s.heatHeating,
    HeatingVerdict.ok => s.heatOk,
  };

  static String _advice(HeatingVerdict v) => switch (v) {
    HeatingVerdict.noData => s.heatNoDataHint,
    HeatingVerdict.incomplete => s.heatIncompleteHint,
    HeatingVerdict.staleActual => s.heatStaleHint,
    HeatingVerdict.notCalling => s.heatNotCallingHint,
    HeatingVerdict.notWarming => s.heatNotWarmingHint,
    HeatingVerdict.overheating => s.heatOverheatingHint,
    HeatingVerdict.heating => s.heatHeatingHint,
    HeatingVerdict.ok => s.heatOkHint,
  };

  static HorizontStatus _status(HeatingVerdict v) => switch (v) {
    HeatingVerdict.ok => HorizontStatus.positive,
    HeatingVerdict.heating => HorizontStatus.info,
    HeatingVerdict.noData || HeatingVerdict.incomplete => HorizontStatus.neutral,
    HeatingVerdict.staleActual || HeatingVerdict.notCalling || HeatingVerdict.overheating => HorizontStatus.warning,
    HeatingVerdict.notWarming => HorizontStatus.critical,
  };

  /// The findings as text for the electrician or the heating engineer.
  String _report() => [
    s.heatReportHeading,
    '',
    for (final r in _rooms)
      '${r.room}: ${s.heatActual} ${_degrees(r.actual)}, ${s.heatSetpoint} ${_degrees(r.setpoint)}, '
          '${s.heatValve} ${_percent(r.valve)} – ${_title(r.verdict)}',
    '',
    for (final v in {
      for (final r in _rooms)
        if (r.verdict.issue) r.verdict,
    })
      '${_title(v)}: ${_advice(v)}',
  ].join('\n');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final issues = _rooms.where((r) => r.verdict.issue).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.heatTitle),
        actions: [InfoAction(title: s.heatTitle, text: s.heatExplain)],
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          // No more columns than rooms: two rooms share the width instead of leaving a third empty.
          final columns = (box.maxWidth >= 1200 ? 3 : (box.maxWidth >= Breakpoints.expanded ? 2 : 1)).clamp(
            1,
            _rooms.isEmpty ? 1 : _rooms.length,
          );
          final perColumn = (_rooms.length / columns).ceil();
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: columns > 1 ? Widths.wide : Widths.reading),
              child: ListView(
                padding: Gap.page,
                children: [
                  FigureBox(
                    figures: [
                      (label: s.heatRooms, value: formatInt(_rooms.length), status: null),
                      (
                        label: s.heatIssues,
                        value: formatInt(issues),
                        status: issues > 0 ? HorizontStatus.warning : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.item),
                  if (_rooms.isEmpty)
                    Text(s.heatNone, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted))
                  else ...[
                    Text(s.heatLimits, style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint)),
                    const SizedBox(height: Gap.section),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: Gap.section,
                      children: [
                        for (var c = 0; c < columns; c++)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              spacing: Gap.item,
                              children: [for (final r in _rooms.skip(c * perColumn).take(perColumn)) _room(context, r)],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: Gap.section),
                    Builder(
                      builder: (context) => OutlinedButton(
                        onPressed: () => shareFile(
                          context,
                          Uint8List.fromList(utf8.encode(_report())),
                          fileName(s.heatTitle, 'txt'),
                          'text/plain',
                          origin: rectOf(context),
                        ),
                        child: Text(s.heatShare),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _room(BuildContext context, HeatingRoom r) {
    final theme = Theme.of(context);
    final hz = context.hz;
    Widget value(String label, String text) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: hz.textFaint)),
          Text(text, style: context.mono(theme.textTheme.titleMedium)),
        ],
      ),
    );
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.item,
        children: [
          Wrap(
            spacing: HzSpace.s8,
            runSpacing: HzSpace.s4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(r.room, style: theme.textTheme.titleMedium),
              HorizontBadge(_status(r.verdict), label: _title(r.verdict)),
            ],
          ),
          Row(
            children: [
              value(s.heatActual, _degrees(r.actual)),
              value(s.heatSetpoint, _degrees(r.setpoint)),
              value(s.heatValve, _percent(r.valve)),
            ],
          ),
          if (r.verdict != HeatingVerdict.ok)
            Text(_advice(r.verdict), style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
        ],
      ),
    );
  }
}
