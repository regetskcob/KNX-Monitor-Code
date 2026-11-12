import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../knx/knx_tunnel.dart';
import '../knx/shared_tunnel.dart';
import '../l10n/locale_controller.dart';
import '../model/health.dart';
import '../model/weekly_report.dart';
import '../platform/addon.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'telegram_row.dart' show formatDate, formatTime;

/// Weekly report for the current state. With [tunnel] via box/add-on, continuous
/// operation is the basis.
WeeklyReport currentReport(KnxTunnel? tunnel, {DateTime? at}) {
  final now = at ?? DateTime.now();
  final (listened, days) = ListeningLog.instance.week(now);
  return weeklyReport(
    HealthCheck.instance.runs,
    now,
    basis: ReportBasis(
      continuous: tunnel is SharedTunnel,
      server: Addon.onBox ? s.weekServerBox : s.weekServerAddon,
      listened: listened,
      days: days,
    ),
  );
}

/// Symbol and color of the traffic light; the word is always next to it.
(IconData, Color) lightStyle(BuildContext context, HealthLight light) {
  final hz = context.hz;
  return switch (light) {
    HealthLight.unknown => (AppIcons.health, hz.textMuted),
    HealthLight.green => (AppIcons.success, hz.positive),
    HealthLight.yellow => (HorizontStatus.warning.icon, hz.warning),
    HealthLight.red => (HorizontStatus.critical.icon, hz.critical),
  };
}

/// Traffic light on the start page: state in one word, one sentence, tapping
/// opens the weekly report. For all users.
class HealthLightCard extends StatefulWidget {
  const HealthLightCard({super.key, this.tunnel, this.onOpenHealth});

  final KnxTunnel? tunnel;

  /// Opens the health check ("Jetzt prüfen", check now).
  final VoidCallback? onOpenHealth;

  @override
  State<HealthLightCard> createState() => _HealthLightCardState();
}

class _HealthLightCardState extends State<HealthLightCard> {
  @override
  void initState() {
    super.initState();
    HealthCheck.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return ListenableBuilder(
      listenable: Listenable.merge([HealthCheck.instance, ListeningLog.instance]),
      builder: (context, _) {
        final report = currentReport(widget.tunnel);
        final (icon, color) = lightStyle(context, report.light);
        final checkNow = report.light == HealthLight.unknown && widget.onOpenHealth != null;
        final large = MediaQuery.textScalerOf(context).scale(10) > 13;
        return SectionCard(
          soft: true,
          padding: EdgeInsets.zero,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => WeeklyReportScreen(tunnel: widget.tunnel, onOpenHealth: widget.onOpenHealth),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(Gap.card),
              child: Row(
                children: [
                  Icon(icon, color: color, semanticLabel: report.light.label),
                  const SizedBox(width: HzSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(report.light.label, style: theme.textTheme.titleSmall),
                        const SizedBox(height: HzSpace.s2),
                        Text(report.summary, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
                        // Large text: button below the text; next to it "Not checked yet" would break mid-word.
                        if (checkNow && large) TextButton(onPressed: widget.onOpenHealth, child: Text(s.weekCheckNow)),
                      ],
                    ),
                  ),
                  if (checkNow && !large)
                    TextButton(onPressed: widget.onOpenHealth, child: Text(s.weekCheckNow))
                  else if (!checkNow)
                    Icon(AppIcons.next, color: hz.textFaint),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Last row of the green box: state in one sentence, on a warning surface when
/// there are findings. Tapping opens the weekly report.
class HealthStatusLine extends StatefulWidget {
  const HealthStatusLine({super.key, this.tunnel, this.onOpenHealth});

  final KnxTunnel? tunnel;
  final VoidCallback? onOpenHealth;

  @override
  State<HealthStatusLine> createState() => _HealthStatusLineState();
}

class _HealthStatusLineState extends State<HealthStatusLine> {
  @override
  void initState() {
    super.initState();
    HealthCheck.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return ListenableBuilder(
      listenable: Listenable.merge([HealthCheck.instance, ListeningLog.instance]),
      builder: (context, _) {
        final report = currentReport(widget.tunnel);
        final (icon, _) = lightStyle(context, report.light);
        final good = report.light == HealthLight.green;
        final checkNow = report.light == HealthLight.unknown && widget.onOpenHealth != null;
        final color = switch (report.light) {
          HealthLight.green || HealthLight.unknown => hz.accentText,
          HealthLight.red => hz.critical,
          _ => hz.warning,
        };
        final style = theme.textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600);
        return Material(
          color: good || report.light == HealthLight.unknown
              ? Colors.transparent
              : (report.light == HealthLight.red ? hz.criticalTint : hz.warningTint),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(Radii.xl)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => WeeklyReportScreen(tunnel: widget.tunnel, onOpenHealth: widget.onOpenHealth),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: HzSpace.s16, vertical: HzSpace.s8),
              child: Row(
                children: [
                  Icon(icon, size: HzIconSize.row, color: color, semanticLabel: report.light.label),
                  const SizedBox(width: HzSpace.s8),
                  Expanded(child: Text(good ? report.light.label : report.summary, style: style)),
                  if (checkNow)
                    TextButton(onPressed: widget.onOpenHealth, child: Text(s.weekCheckNow))
                  else
                    Icon(AppIcons.next, size: HzIconSize.row, color: color),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Weekly report: traffic light, sentence, open and resolved findings, basis.
class WeeklyReportScreen extends StatelessWidget {
  const WeeklyReportScreen({super.key, this.tunnel, this.onOpenHealth, this.at});

  final KnxTunnel? tunnel;
  final VoidCallback? onOpenHealth;

  /// Fixed point in time instead of "now" (goldens).
  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return Scaffold(
      appBar: AppBar(title: Text(s.weekTitle)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Widths.reading),
          child: ListenableBuilder(
            listenable: Listenable.merge([HealthCheck.instance, ListeningLog.instance]),
            builder: (context, _) {
              final report = currentReport(tunnel, at: at);
              final (icon, color) = lightStyle(context, report.light);
              final last = report.runs.firstOrNull?.time;
              Widget list(String title, List<HealthFinding> findings) => SectionCard(
                title: title,
                count: findings.length,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final f in findings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: HzSpace.s8),
                        child: Text(plainFinding(f), style: theme.textTheme.bodyMedium),
                      ),
                  ],
                ),
              );
              return ListView(
                padding: Gap.page,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: color, size: 32),
                      const SizedBox(width: HzSpace.s12),
                      Expanded(child: Text(report.light.label, style: theme.textTheme.titleLarge)),
                    ],
                  ),
                  const SizedBox(height: Gap.item),
                  Text(report.summary, style: theme.textTheme.bodyLarge),
                  if (last != null) ...[
                    const SizedBox(height: HzSpace.s4),
                    Text(
                      s.weekLastCheck('${formatDate(last)} ${formatTime(last, seconds: false)}'),
                      style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                    ),
                  ],
                  // Newest run without a read test: say when it was last read.
                  if (report.lastFull case final full?)
                    Text(
                      s.weekLastFullCheck('${formatDate(full)} ${formatTime(full, seconds: false)}'),
                      style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                    ),
                  const SizedBox(height: Gap.section),
                  if (report.open.isNotEmpty) ...[list(s.weekOpen, report.open), const SizedBox(height: Gap.inner)],
                  if (report.resolved.isNotEmpty) ...[
                    list(s.weekDone, report.resolved),
                    const SizedBox(height: Gap.inner),
                  ],
                  Text(report.basisText, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
                  if (onOpenHealth != null) ...[
                    const SizedBox(height: Gap.section),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onOpenHealth!();
                        },
                        icon: const Icon(AppIcons.health, size: 18),
                        label: Text(s.weekOpenHealth),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
