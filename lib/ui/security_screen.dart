import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/demo_tunnel.dart';
import '../knx/knx_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/security_check.dart';
import '../model/telegram_log.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'statistics_screen.dart' show FigureBox;

/// Security check: Secure usage of the connection and the project, unknown
/// senders. Plain-language recommendations without alarm colors.
class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key, required this.tunnel, required this.log});

  final KnxTunnel tunnel;
  final TelegramLog log;

  static HorizontStatus _status(SecurityLevel l) => switch (l) {
    SecurityLevel.good => HorizontStatus.positive,
    SecurityLevel.info => HorizontStatus.neutral,
    SecurityLevel.advice => HorizontStatus.warning,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.secTitle),
        actions: [
          // The introduction sits behind the info button; the page starts with the key figures.
          IconButton(
            tooltip: s.secTitle,
            icon: const Icon(AppIcons.info),
            onPressed: () => showAdaptiveDialog<void>(
              context: context,
              builder: (context) => AlertDialog.adaptive(
                title: Text(s.secTitle),
                content: Text(s.secExplain),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(MaterialLocalizations.of(context).okButtonLabel),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Widths.dashboard),
          child: ListenableBuilder(
            listenable: Listenable.merge([log, tunnel.gatewayInfo]),
            builder: (context, _) {
              final store = CatalogStore.instance;
              final check = SecurityCheck.of(SecurityInput.live(tunnel, store.catalog, log.log));
              // Recommendations first and highlighted individually, the rest quietly in one card.
              final advice = [
                for (final f in check.findings)
                  if (f.level == SecurityLevel.advice) f,
              ];
              final others = [
                for (final f in check.findings)
                  if (f.level != SecurityLevel.advice) f,
              ];
              return ListView(
                padding: Gap.page,
                children: [
                  FigureBox(
                    figures: [
                      (s.secMetricLink, tunnel is DemoTunnel ? 'Demo' : tunnel.kind),
                      (
                        s.secMetricGateway,
                        switch (check.gatewaySecure) {
                          true => s.secGatewaySecure,
                          false => s.secGatewayPlain,
                          null => '—',
                        },
                      ),
                      if (check.projectGroups > 0)
                        (
                          s.secMetricProject,
                          check.keyringLoaded
                              ? '${formatInt(check.projectSecured)} / ${formatInt(check.projectGroups)}'
                              : '—',
                        ),
                      (
                        s.secMetricSeen,
                        check.keyringLoaded ? '${formatInt(check.seenSecured)} / ${formatInt(check.seenGroups)}' : '—',
                      ),
                    ],
                  ),
                  for (final f in advice) ...[
                    const SizedBox(height: Gap.inner),
                    DecoratedBox(
                      decoration: BoxDecoration(color: hz.warningTint, borderRadius: Radii.box),
                      child: Padding(
                        padding: const EdgeInsets.all(Gap.card),
                        child: _Finding(finding: f, status: _status(f.level)),
                      ),
                    ),
                  ],
                  if (check.foreign.isNotEmpty) ...[
                    const SizedBox(height: Gap.section),
                    SectionTitle(s.secForeignList, count: check.foreign.length),
                    const SizedBox(height: HzSpace.s4),
                    for (final (i, f) in check.foreign.take(50).indexed) ...[
                      if (i > 0) const Divider(height: Lines.hairline),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: HzSpace.s12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formatIndividual(f.address),
                              style: context.mono(theme.textTheme.bodyMedium).copyWith(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              s.secForeignRow(
                                f.count,
                                f.groups.take(3).map((g) => store.info(g)?.name ?? formatGroup(g)).join(', '),
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                  if (others.isNotEmpty) ...[
                    const SizedBox(height: Gap.section),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, f) in others.indexed) ...[
                            if (i > 0) const ToolSectionDivider(),
                            _Finding(finding: f, status: _status(f.level)),
                          ],
                        ],
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

/// A finding: state symbol, title and explanation.
class _Finding extends StatelessWidget {
  const _Finding({required this.finding, required this.status});

  final SecurityFinding finding;
  final HorizontStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(status.icon, size: HzIconSize.row, color: status.color(context.hz)),
        const SizedBox(width: Gap.inner),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(finding.title, style: theme.textTheme.titleSmall),
              const SizedBox(height: HzSpace.s4),
              Text(finding.text, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
