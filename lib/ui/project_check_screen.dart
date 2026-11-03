import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/demo_tunnel.dart';
import '../knx/group_catalog.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/coupler_filter.dart';
import '../model/project_check.dart';
import '../model/telegram_log.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../theme/palette.dart';
import '../model/filter.dart';
import 'common.dart';
import 'ets_tasks_export.dart';
import 'filter_observations.dart';

/// Comparison of the bus traffic with the ETS project, plus checks on the
/// project itself (flags, links). Tapping an entry closes the view and filters
/// the monitor to this address.
class ProjectCheckScreen extends StatefulWidget {
  const ProjectCheckScreen({super.key, required this.log, required this.onFilter});

  final TelegramLog log;
  final ValueChanged<String> onFilter;

  @override
  State<ProjectCheckScreen> createState() => _ProjectCheckScreenState();
}

class _ProjectCheckScreenState extends State<ProjectCheckScreen> {
  static const _limit = 100;

  /// Loaded once, not on every repaint: it reads recordings.
  Future<List<FilterObservation>>? _observations;

  TelegramLog get log => widget.log;
  ValueChanged<String> get onFilter => widget.onFilter;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  ProjectCheck? _check;
  ProjectLint? _lint;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    // Passive only: the check neither reads nor writes any coupler.
    future: _observations ??= CatalogStore.instance.catalog.devices.isEmpty
        ? Future.value(const <FilterObservation>[])
        : loadFilterObservations(log),
    builder: (context, snapshot) => _content(context, snapshot.data ?? const []),
  );

  Widget _content(BuildContext context, List<FilterObservation> observations) {
    // Show the page first, then compute: on weak devices it takes noticeably long.
    if (!_ready) return const Center(child: CircularProgressIndicator.adaptive());
    final theme = Theme.of(context);
    final hz = context.hz;
    final store = CatalogStore.instance;
    // Compute only once: the FutureBuilder builds the page several times.
    final check = _check ??= ProjectCheck.of(log);
    final lint = _lint ??= ProjectLint.of(store.catalog);

    void filter(String q) {
      Navigator.pop(context);
      onFilter(q);
    }

    // Finding row: address in monospace, name, small meta below; on the right
    // the count in bold and, if tappable, a chevron.
    Widget row({required String title, required String subtitle, String? trailing, String? query}) {
      final split = title.indexOf('  ');
      return InkWell(
        onTap: query == null ? null : () => filter(query),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: HzSpace.s48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
            child: Row(
              spacing: HzSpace.s8,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: split <= 0 ? title : title.substring(0, split),
                              style: context.mono(theme.textTheme.bodyMedium).copyWith(color: hz.textMuted),
                            ),
                            if (split > 0) TextSpan(text: title.substring(split), style: theme.textTheme.bodyLarge),
                          ],
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint),
                        ),
                    ],
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing,
                    style: context.figures(theme.textTheme.bodyMedium).copyWith(fontWeight: FontWeight.w600),
                  ),
                if (query != null) Icon(AppIcons.next, size: HzIconSize.row, color: hz.textFaint),
              ],
            ),
          ),
        ),
      );
    }

    // Check with findings: section title with count, hint, the rows.
    // Without a finding or without a basis (catalog without flags): a quiet row
    // with hint and result as symbol and word. Findings come first, see
    // [ordered]; the green box shows the total.
    var findings = 0;
    Widget section(
      String title,
      int count,
      List<Widget> rows, {
      String? hint,
      bool warning = true,
      bool available = true,
    }) {
      final status = !available
          ? HorizontStatus.info
          : (count == 0 ? HorizontStatus.positive : (warning ? HorizontStatus.warning : HorizontStatus.info));
      if (available) findings += count;
      if (!available || count == 0) {
        return _QuietCheck(
          title: title,
          hint: hint ?? '',
          status: status,
          // The demo project cannot be reimported.
          result: available ? s.checkAllGood : (DemoTunnel.active ? s.checkDemoNoFlags : s.checkReimport),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(title, count: count),
          if (hint != null && hint.isNotEmpty) ...[
            const SizedBox(height: Gap.item),
            Text(hint, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
          ],
          const SizedBox(height: Gap.item),
          for (final (i, r) in rows.take(_limit).indexed) ...[if (i > 0) const Divider(height: Lines.hairline), r],
          if (rows.length > _limit)
            Padding(
              padding: const EdgeInsets.only(top: Gap.item),
              child: Text(
                s.checkMore(rows.length - _limit),
                style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
              ),
            ),
        ],
      );
    }

    // Checks of a group, findings first; the quiet rows follow.
    Widget group(String title, List<Widget> checks) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.section,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        ...checks.where((c) => c is! _QuietCheck),
        ...checks.whereType<_QuietCheck>(),
      ],
    );

    String size(int bytes) => bytes == 0 ? s.checkSmall : s.checkBytes(bytes);
    String groupTitle(GroupInfo g) => '${formatGroup(g.address)}  ${g.name}';
    // Linked object: device, object text and flags.
    String object(GroupLink l) => [
      formatIndividual(l.device),
      l.text ?? store.device(l.device)?.name ?? '',
      if (l.flags != null) formatFlags(l.flags!),
    ].where((t) => t.isNotEmpty).join(' ');
    Widget groupRow(GroupInfo g, Iterable<GroupLink> links) =>
        row(title: groupTitle(g), subtitle: links.map(object).join(metaSeparator), query: formatGroup(g.address));
    // Checks on the project itself: independent of the observation period, only
    // with devices from the .knxproj.
    // Data types changed in the app: update them in ETS.
    final changed = store.overrides.keys.toList()..sort();
    final dptSection = changed.isEmpty
        ? null
        : section(
            s.checkDptChanged,
            changed.length,
            [
              for (final ga in changed)
                row(
                  title: '${formatGroup(ga)}  ${store.info(ga)?.name ?? ''}',
                  subtitle: s.checkDptChangedRow(
                    store.catalog[ga]?.dpt == null ? s.checkDptNone : 'DPT ${store.catalog[ga]!.dpt}',
                    '${store.overrides[ga]}',
                  ),
                  query: formatGroup(ga),
                ),
            ],
            hint: s.checkDptChangedHint,
            warning: false,
          );
    // Without a name or datapoint type: works with CSV too.
    final incompleteSection = !lint.hasIncomplete
        ? null
        : section(
            s.checkIncomplete,
            lint.incomplete.length,
            [
              for (final i in lint.incomplete)
                row(
                  title: groupTitle(i.group),
                  subtitle: [if (i.noName) s.checkNoName, if (i.noDpt) s.checkDptNone].join(metaSeparator),
                  query: formatGroup(i.group.address),
                ),
            ],
            hint: s.checkIncompleteHint,
            warning: false,
          );
    final filterCheck = FilterCheck.of(store.catalog, observations: observations);
    String lines(Iterable<int> list) => (list.toList()..sort()).map(formatLine).join(', ');
    final open = [
      for (final c in filterCheck.crossLine)
        if (c.open.isNotEmpty) c,
    ];
    final confirmed = [
      for (final c in filterCheck.crossLine)
        if (c.open.isEmpty) c,
    ];
    final projectCard = store.catalog.devices.isEmpty && dptSection == null && incompleteSection == null
        ? null
        : group(s.checkSectionProject, [
            ?dptSection,
            ?incompleteSection,
            if (store.catalog.devices.isNotEmpty) ...[
              section(
                s.checkStatusNoTransmit,
                lint.statusWithoutTransmit.length,
                [for (final g in lint.statusWithoutTransmit) groupRow(g, g.links)],
                hint: s.checkStatusNoTransmitHint,
                available: lint.hasFlags,
              ),
              section(
                s.checkReadNoReadFlag,
                lint.readWithoutReadFlag.length,
                [for (final g in lint.readWithoutReadFlag) groupRow(g, g.links)],
                hint: s.checkReadNoReadFlagHint,
                available: lint.hasFlags,
              ),
              section(
                s.checkObjectsNoComm,
                lint.objectsWithoutCommunication.length,
                [
                  for (final (g, l) in lint.objectsWithoutCommunication) groupRow(g, [l]),
                ],
                hint: s.checkObjectsNoCommHint,
                available: lint.hasFlags,
              ),
              section(s.checkDevicesNoLinks, lint.devicesWithoutLinks.length, [
                for (final d in lint.devicesWithoutLinks)
                  row(
                    title: '${formatIndividual(d.address)}  ${d.name}',
                    subtitle: [?d.product, ?d.location].join(metaSeparator),
                    query: senderQuery(formatIndividual(d.address)),
                  ),
              ], hint: s.checkDevicesNoLinksHint),
              section(
                s.checkMultipleSenders,
                lint.multipleSenders.length,
                [for (final g in lint.multipleSenders) groupRow(g, g.links.where((l) => l.sends))],
                hint: s.checkMultipleSendersHint,
                warning: false,
                available: lint.hasFlags,
              ),
              section(
                s.checkMultipleReadAnswers,
                lint.multipleReadAnswers.length,
                [
                  for (final g in lint.multipleReadAnswers)
                    groupRow(g, g.links.where((l) => l.flags?.answersReads ?? false)),
                ],
                hint: s.checkMultipleReadAnswersHint,
                available: lint.hasFlags,
              ),
              section(
                s.checkWithoutSender,
                lint.withoutSender.length,
                [for (final g in lint.withoutSender) groupRow(g, g.links)],
                hint: s.checkWithoutSenderHint,
                warning: false,
                available: lint.hasFlags,
              ),
              section(
                s.checkWithoutReceiver,
                lint.withoutReceiver.length,
                [for (final g in lint.withoutReceiver) groupRow(g, g.links)],
                hint: s.checkWithoutReceiverHint,
                warning: false,
                available: lint.hasFlags,
              ),
              section(
                s.checkFilterTitle,
                filterCheck.notForwarded.length + open.length,
                [
                  for (final n in filterCheck.notForwarded)
                    row(
                      title: groupTitle(n.group),
                      subtitle: s.checkFilterMissingRow(formatLine(n.seenOn), n.count, formatLine(n.missingOn)),
                      query: formatGroup(n.group.address),
                    ),
                  for (final c in open)
                    row(
                      title: groupTitle(c.group),
                      subtitle: s.checkFilterCrossRow(lines(c.senderLines), lines(c.open)),
                      query: formatGroup(c.group.address),
                    ),
                  for (final c in confirmed)
                    row(
                      title: groupTitle(c.group),
                      subtitle: s.checkFilterConfirmedRow(lines(c.confirmed)),
                      query: formatGroup(c.group.address),
                    ),
                ],
                hint: filterCheck.comparedPoints == 0
                    ? '${s.checkFilterHint} ${s.checkFilterNoPoints}'
                    : s.checkFilterHint,
                warning: filterCheck.notForwarded.isNotEmpty,
                available: lint.hasFlags,
              ),
              section(s.checkCrowdedLines, lint.crowdedLines.length, [
                for (final l in lint.crowdedLines)
                  row(
                    title: '${(l.line >> 4) & 0x0F}.${l.line & 0x0F}',
                    subtitle: s.checkLineDevices(l.devices),
                    trailing: '${l.devices}',
                  ),
              ], hint: s.checkCrowdedLinesHint(ProjectLint.lineReserveLimit)),
              if (lint.unfilteredMainGroups.isNotEmpty) ...[
                section(
                  s.checkMainGroup1415,
                  lint.unfilteredMainGroups.length,
                  [
                    for (final g in lint.unfilteredMainGroups)
                      row(title: groupTitle(g), subtitle: g.path ?? '', query: formatGroup(g.address)),
                  ],
                  hint: s.checkMainGroup1415Hint,
                  warning: false,
                ),
              ],
            ],
          ]);
    final traffic = group(s.checkSectionTraffic, [
      section(s.checkUnknownAddresses, check.unknownAddresses.length, [
        for (final u in check.unknownAddresses)
          row(
            title: formatGroup(u.address),
            subtitle: [
              s.telegramCount(u.count),
              s.checkSenders(u.senders.length),
              if (u.last != null) store.value(u.last!),
            ].join(metaSeparator),
            query: formatGroup(u.address),
          ),
      ]),
      if (store.catalog.devices.isNotEmpty) ...[
        section(s.checkUnknownDevices, check.unknownDevices.length, [
          for (final d in check.unknownDevices)
            row(
              title: formatIndividual(d.address),
              subtitle: [s.telegramCount(d.count), s.checkGroups(d.groups.length)].join(metaSeparator),
              query: senderQuery(formatIndividual(d.address)),
            ),
        ]),
      ],
      section(s.checkSizeMismatch, check.sizeMismatches.length, [
        for (final m in check.sizeMismatches)
          row(
            title: '${formatGroup(m.address)}  ${store.info(m.address)?.name ?? ''}',
            subtitle: 'DPT ${m.dpt} · ${s.checkExpected(size(m.expected), m.seen.map(size).join(', '))}',
            trailing: '${m.count}×',
            query: formatGroup(m.address),
          ),
      ]),
      section(s.checkCentralOffOn, check.centralOffOn.length, [
        for (final c in check.centralOffOn)
          row(
            title: '${formatGroup(c.address)}  ${store.info(c.address)?.name ?? ''}',
            subtitle: s.telegramCount(c.count),
            trailing: '${c.count}×',
            query: formatGroup(c.address),
          ),
      ], hint: s.issueCentralOffOnHint),
      section(
        s.checkNeverSeen,
        check.neverSeen.length,
        [
          for (final ga in check.neverSeen)
            row(title: '${formatGroup(ga)}  ${store.info(ga)?.name ?? ''}', subtitle: store.info(ga)?.path ?? ''),
        ],
        hint: s.checkNeverSeenHint,
        warning: false,
      ),
    ]);
    // Key figures: total of all findings (main value), size of the project and
    // the basis of the checks in the bus traffic.
    final summary = SectionCard(
      soft: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: HzSpace.s4,
        children: [
          Text(
            findings == 0 ? s.checkAllGood : s.checkFindings(findings),
            style: context
                .figures(theme.textTheme.titleLarge)
                .copyWith(color: hz.accentText, fontWeight: FontWeight.w700),
          ),
          Text(
            [
              s.groupAddressCount(store.catalog.groups.length),
              s.checkEvaluatedTelegrams(check.total),
            ].join(metaSeparator),
            style: context.figures(theme.textTheme.bodySmall).copyWith(color: hz.accentText),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(s.checkTitle),
        actions: [
          if (!store.catalog.isEmpty)
            Builder(
              builder: (button) => IconButton(
                icon: const Icon(AppIcons.etsTasks),
                tooltip: '${s.etsTasks} – ${s.etsTasksHint}',
                onPressed: () => exportEtsTasks(context, origin: rectOf(button), log: log),
              ),
            ),
        ],
      ),
      body: store.catalog.isEmpty
          ? Center(
              child: HorizontEmptyHint(icon: AppIcons.noProject, text: s.checkNoProject),
            )
          // One row per check as in the diagnostics; from tablet width project
          // and bus traffic side by side instead of stacked.
          : LayoutBuilder(
              builder: (context, box) {
                final columns = projectCard != null && box.maxWidth >= Breakpoints.expanded;
                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: columns ? Widths.wide : Widths.dashboard),
                    child: ListView(
                      padding: Gap.page,
                      children: [
                        summary,
                        const SizedBox(height: Gap.section),
                        if (columns)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: Gap.section,
                            children: [
                              Expanded(child: projectCard),
                              Expanded(child: traffic),
                            ],
                          )
                        else ...[
                          if (projectCard != null) ...[projectCard, const SizedBox(height: Gap.section)],
                          traffic,
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Check without a finding or without a basis: title and hint, below it the
/// result as symbol and word.
class _QuietCheck extends StatelessWidget {
  const _QuietCheck({required this.title, required this.hint, required this.status, required this.result});

  final String title;
  final String hint;
  final HorizontStatus status;
  final String result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final hz = context.hz;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: theme.bodyLarge),
        if (hint.isNotEmpty) Text(hint, style: theme.bodySmall?.copyWith(color: hz.textFaint)),
        const SizedBox(height: HzSpace.s4),
        Row(
          spacing: Gap.item,
          children: [
            Icon(status.icon, size: HzIconSize.row, color: status.color(hz)),
            Expanded(
              child: Text(result, style: theme.bodySmall?.copyWith(color: status.color(hz))),
            ),
          ],
        ),
      ],
    );
  }
}
