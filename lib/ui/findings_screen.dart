import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/findings.dart';
import '../model/recording.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'annotation_editor.dart';
import 'annotations.dart';
import 'recording_timeline.dart';
import 'telegram_row.dart';

/// Findings of an opened diagnostic package: problem description with
/// screenshots, automatic hints, comments (tapping jumps to the timeline),
/// technical details, and the app log with errors highlighted.
class FindingsScreen extends StatefulWidget {
  const FindingsScreen({super.key, required this.recording, this.onShowTime});

  final Recording recording;

  /// Tapping a comment opens the timeline at that point.
  final ValueChanged<DateTime>? onShowTime;

  @override
  State<FindingsScreen> createState() => _FindingsScreenState();
}

class _FindingsScreenState extends State<FindingsScreen> {
  late final Future<String?> _version = PackageInfo.fromPlatform().then<String?>(
    (i) => i.version,
    onError: (_) => null,
  );
  bool _onlyErrors = true;

  Recording get _r => widget.recording;
  Map<String, Object?> get _d => _r.diagnostics ?? const {};

  @override
  void initState() {
    super.initState();
    AnnotationScope.open(_r);
    RecordingStore.instance.addListener(_changed);
  }

  @override
  void dispose() {
    RecordingStore.instance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: hz.textMuted);
    final problem = _d['problem'] as String? ?? '';
    final expected = _d['expected'] as String?;
    final occurred = DateTime.tryParse(_d['occurred'] as String? ?? '');
    final shots = [...?(_d['shots'] as List?)?.cast<String>()];
    final tech = (_d['technical'] as Map?)?.cast<String, Object?>() ?? const {};
    final log = [...?(_d['log'] as List?)?.cast<String>()];
    final shownLog = _onlyErrors ? log.where(isErrorLine).toList() : log;
    final width = MediaQuery.sizeOf(context).width;
    final gutter = Gap.gutterFor(width);
    // Two columns as soon as two card columns fit (iPad landscape, Mac):
    // problem description, hints and comments on the left, addresses and
    // technical details on the right.
    final columns = width.clamp(0, Widths.wide + 2 * gutter) - 2 * gutter >= 2 * Widths.column + Gap.section * 2;
    final side =
        gutter + ((width - 2 * gutter - (columns ? Widths.wide : Widths.reading)) / 2).clamp(0, double.infinity);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Kennung(_r.name), Text(s.findingsTitle)],
        ),
      ),
      body: FutureBuilder(
        future: _version,
        builder: (context, snapshot) {
          final findings = findingsOf(_r, currentVersion: snapshot.data);
          final primary = <Widget>[
            // Problem description in the user's words.
            Kennung(s.findingsProblem),
            const SizedBox(height: HzSpace.s8),
            Text(problem.isEmpty ? s.findingsNoProblem : problem, style: theme.textTheme.bodyLarge),
            if (expected != null && expected.isNotEmpty) ...[
              const SizedBox(height: HzSpace.s8),
              Text(s.findingsExpected(expected), style: theme.textTheme.bodyMedium),
            ],
            if (occurred != null) ...[
              const SizedBox(height: HzSpace.s4),
              Text(s.findingsOccurred('${formatDate(occurred)} ${formatTime(occurred, millis: false)}'), style: muted),
            ],
            if (shots.isNotEmpty) ...[
              const SizedBox(height: HzSpace.s12),
              Wrap(
                spacing: HzSpace.s8,
                runSpacing: HzSpace.s8,
                children: [for (final id in shots) ShotThumb(id: id, size: 72)],
              ),
            ],
            const SizedBox(height: Gap.section * 2),

            // Automatische Hinweise.
            Kennung(s.findingsHints),
            const SizedBox(height: HzSpace.s8),
            if (findings.isEmpty)
              Text(s.findingsNoHints, style: muted)
            else
              for (final f in findings)
                Padding(
                  padding: const EdgeInsets.only(bottom: HzSpace.s8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HorizontBadge(
                        switch (f.level) {
                          FindingLevel.critical => HorizontStatus.critical,
                          FindingLevel.warning => HorizontStatus.warning,
                          FindingLevel.info => HorizontStatus.info,
                        },
                        label: switch (f.level) {
                          FindingLevel.critical => s.findingLevelCritical,
                          FindingLevel.warning => s.findingLevelWarning,
                          FindingLevel.info => s.findingLevelInfo,
                        },
                      ),
                      const SizedBox(width: HzSpace.s8),
                      Expanded(child: SelectableText(f.text)),
                    ],
                  ),
                ),
            const SizedBox(height: Gap.section * 2),

            // User comments on telegrams, charts, points in time.
            Kennung(s.annotationsLabel),
            const SizedBox(height: HzSpace.s4),
            if (_r.annotations.isEmpty)
              Text(s.findingsNoAnnotations, style: muted)
            else
              for (final a in _r.annotations)
                AnnotationTile(
                  annotation: a,
                  onTap: widget.onShowTime == null ? null : () => widget.onShowTime!(a.time),
                  onEdit: () => editAnnotation(context, a),
                ),
            const SizedBox(height: Gap.section * 2),
          ];
          final secondary = <Widget>[
            // Most frequent addresses of the recording.
            if (_r.telegrams.isNotEmpty) ...[
              Kennung(s.findingsBusiest),
              const SizedBox(height: HzSpace.s8),
              for (final (ga, n) in busiestGroups(_r.telegrams))
                HorizontFact(
                  term: formatGroup(ga),
                  value: '${CatalogStore.instance.catalog[ga]?.name ?? ''}$metaSeparator${s.telegramCount(n)}',
                  selectable: true,
                ),
              const SizedBox(height: Gap.section * 2),
            ],

            // Technik.
            Kennung(s.findingsTechnical),
            const SizedBox(height: HzSpace.s8),
            for (final (term, value) in technicalFacts(tech)) HorizontFact(term: term, value: value, selectable: true),
            const SizedBox(height: Gap.section * 2),
          ];
          return ListView(
            padding: EdgeInsets.fromLTRB(side, Gap.page.top, side, Gap.page.bottom),
            children: [
              if (columns)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Gap.section * 2,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: primary),
                    ),
                    Expanded(
                      flex: 2,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: secondary),
                    ),
                  ],
                )
              else ...[
                ...primary,
                ...secondary,
              ],

              // App log.
              Row(
                children: [
                  Expanded(child: Kennung(s.findingsLog(log.length))),
                  FilterChip(
                    label: Text(s.findingsOnlyErrors),
                    selected: _onlyErrors,
                    onSelected: (v) => setState(() => _onlyErrors = v),
                  ),
                ],
              ),
              const SizedBox(height: HzSpace.s8),
              if (shownLog.isEmpty)
                Text(_onlyErrors ? s.findingsNoLogErrors : s.findingsNoLog, style: muted)
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: hz.sunken,
                    borderRadius: Radii.tile,
                    border: Border.all(color: hz.line, width: Lines.hairline),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(HzSpace.s12),
                    child: SelectableText.rich(
                      TextSpan(
                        children: [
                          for (final line in shownLog)
                            TextSpan(
                              text: '$line\n',
                              style: isErrorLine(line) ? TextStyle(color: hz.critical) : null,
                            ),
                        ],
                      ),
                      style: context.mono(theme.textTheme.bodySmall),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
