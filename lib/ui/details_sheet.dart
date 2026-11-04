import 'dart:math' as math;
import 'dart:ui' as ui;

import '../model/cause_chain.dart';
import '../knx/dpt_codec.dart';
import '../model/sound_ack.dart';
import 'sound_ack_screen.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:horizont/horizont.dart';

import 'write_confirm.dart';

import '../catalog_store.dart';
import '../knx/group_catalog.dart';
import '../knx/knx_tunnel.dart';
import '../export/pdf_export.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/alarms.dart';
import '../model/annotation.dart';
import '../model/telegram_log.dart';
import '../model/analysis.dart';
import '../model/expert_mode.dart';
import '../model/pinned_sections.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'annotations.dart';
import 'cause_chain_view.dart';
import 'common.dart';
import 'recording_timeline.dart';
import 'history_chart.dart';
import 'value_board.dart' show Sparkline;
import 'telegram_row.dart';
import 'write_value.dart';
import '../theme/app_icons.dart';
import '../model/plan.dart';
import 'plan_screen.dart';
import '../model/watch_rules.dart';
import 'watch_screen.dart';
import '../model/commissioning.dart' show isStatusGroup;
import '../model/learning.dart';
import 'learn_screen.dart';

/// Shows all details of a telegram with quick actions (phone). [onFilter] sets
/// the monitor filter to the group address.
Future<void> showDetailsSheet(
  BuildContext context,
  Telegram t, {
  required KnxTunnel? tunnel,
  required List<Telegram> history,
  ValueChanged<String>? onFilter,
  bool filtered = false,
  List<TelegramIssue> issues = const [],
  String? gateway,
  ValueChanged<int>? onOpenChart,
  ValueChanged<int>? onOpenDevice,
  ValueChanged<int>? onOpenMap,
  TelegramLog? log,
}) {
  // Cross-links close the sheet first, then the target opens.
  ValueChanged<int>? closeThen(BuildContext sheet, ValueChanged<int>? open) => open == null
      ? null
      : (v) {
          Navigator.pop(sheet);
          open(v);
        };
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, controller) => _FollowLog(
          log: log,
          telegram: t,
          history: history,
          builder: (t, history) => TelegramDetails(
            telegram: t,
            tunnel: tunnel,
            history: history,
            issues: issues,
            gateway: gateway,
            inSheet: true,
            scrollController: controller,
            filtered: filtered,
            onFilter: onFilter == null
                ? null
                : (q) {
                    Navigator.pop(sheetContext);
                    onFilter(q);
                  },
            onOpenChart: closeThen(sheetContext, onOpenChart),
            onOpenDevice: closeThen(sheetContext, onOpenDevice),
            onOpenMap: closeThen(sheetContext, onOpenMap),
            around: log?.log,
          ),
        ),
      ),
    ),
  );
}

/// Keeps the sheet up to date: when a new telegram arrives for the address
/// (including one written by the user), it shows the value and history again.
/// Without [log] it stays at the state when opened.
class _FollowLog extends StatefulWidget {
  const _FollowLog({required this.log, required this.telegram, required this.history, required this.builder});

  final TelegramLog? log;
  final Telegram telegram;
  final List<Telegram> history;
  final Widget Function(Telegram telegram, List<Telegram> history) builder;

  @override
  State<_FollowLog> createState() => _FollowLogState();
}

class _FollowLogState extends State<_FollowLog> {
  late Telegram _telegram = widget.telegram;
  late List<Telegram> _history = widget.history;

  @override
  void initState() {
    super.initState();
    widget.log?.addListener(_changed);
  }

  @override
  void dispose() {
    widget.log?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final log = widget.log!;
    final latest = log.latest[widget.telegram.destination];
    // Rebuild only on a new telegram for this address, not on every one.
    if (latest == null || identical(latest, _telegram)) return;
    setState(() {
      _telegram = latest;
      _history = log.forAddress(widget.telegram.destination);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(_telegram, _history);
}

/// Details of a telegram and its group address: current value, history (chart
/// or list), writing, telegram data, linked devices.
///
/// In a bottom sheet ([inSheet]) or as a side panel (iPad). Without [tunnel]
/// (recordings) reading and writing are omitted.
class TelegramDetails extends StatefulWidget {
  const TelegramDetails({
    super.key,
    required this.telegram,
    required this.tunnel,
    required this.history,
    this.onFilter,
    this.filtered = false,
    this.onClose,
    this.gateway,
    this.issues = const [],
    this.inSheet = false,
    this.scrollController,
    this.onOpenChart,
    this.onOpenDevice,
    this.onOpenMap,
    this.around,
  });

  /// Capture around the telegram (sorted by time) for the cause chain; without
  /// it the chain is omitted.
  final List<Telegram>? around;

  /// Opens the chart of this group address full size (charts view).
  final ValueChanged<int>? onOpenChart;

  /// Opens the device sheet of a device (sender, linked devices).
  final ValueChanged<int>? onOpenDevice;

  /// Opens the communication map of this group address.
  final ValueChanged<int>? onOpenMap;

  final Telegram telegram;
  final KnxTunnel? tunnel;

  /// All telegrams of the same group address, oldest first.
  final List<Telegram> history;

  /// Anomalies of this telegram (see [issuesOf]).
  final List<TelegramIssue> issues;

  /// Sets the monitor filter; without it (e.g. from the health view) the button
  /// is omitted.
  final ValueChanged<String>? onFilter;

  /// The monitor is currently filtered to this address: filtering clears it.
  final bool filtered;
  final VoidCallback? onClose;
  final String? gateway;
  final bool inSheet;
  final ScrollController? scrollController;

  @override
  State<TelegramDetails> createState() => _TelegramDetailsState();
}

class _TelegramDetailsState extends State<TelegramDetails> {
  /// At most this many values in the details history; all of them in full
  /// screen.

  Future<void> _exportChart(BuildContext buttonContext, ({ChartKind kind, List<ChartPoint> points}) data) async {
    final store = CatalogStore.instance;
    final address = widget.telegram.destination;
    final dpt = store.dptOf(address);
    final origin = rectOf(buttonContext);
    if (!await unlock(context, Feature.export) || !mounted) return;
    await sharePdf(
      context,
      () async {
        Uint8List? png;
        ({double min, double max, double avg})? stats;
        if (data.kind != ChartKind.none) {
          final image = await renderChartImage(data.points, data.kind, dpt);
          png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        }
        if (data.kind == ChartKind.line) {
          final v = data.points.map((p) => p.value).toList();
          stats = (min: v.reduce(math.min), max: v.reduce(math.max), avg: v.reduce((a, b) => a + b) / v.length);
        }
        return ChartPdf(
          address: address,
          telegrams: widget.history,
          kind: data.kind,
          dpt: dpt,
          chart: png,
          stats: stats,
          gateway: widget.gateway,
        );
      },
      pdfName(s.detailsHistoryPdfName(store.info(address)?.name ?? formatGroup(address))),
      origin: origin,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final store = CatalogStore.instance;
    final t = widget.telegram;
    final tunnel = widget.tunnel;
    final inSheet = widget.inSheet;
    final info = store.info(t.destination);
    final dpt = store.dptOf(t.destination);
    final typeLabel = Palette.label(t.type);
    final ownSource = t.outgoing || t.source == tunnel?.tunnelAddress;
    final interpretations = t.interpretations;
    final chart = chartData(dpt, widget.history);
    // The latest values, as on the card.
    final recent = chart.points.length > TelegramLog.historyLength
        ? chart.points.sublist(chart.points.length - TelegramLog.historyLength)
        : chart.points;
    final values = widget.history.where((h) => h.type != TelegramType.read).toList();
    final sender = ownSource
        ? '${s.rowThisTunnel} ${t.sourceText}'
        : '${store.device(t.source)?.name ?? ''} ${t.sourceText}'.trim();

    // Mean of the shown measurements; meaningless for on/off.
    final shown = chart.points.length > TelegramLog.historyLength
        ? chart.points.sublist(chart.points.length - TelegramLog.historyLength)
        : chart.points;
    final average = shown.length < 2 || dpt == null || dpt.main == 1 || t.isSmall
        ? null
        : shown.fold<double>(0, (sum, p) => sum + p.value) / shown.length;
    final unit = dpt == null ? '' : dptUnit(dpt);

    final summary = [
      '${t.destinationText}${info != null ? ' ${info.name}' : ''}',
      s.detailsSummaryLine(typeLabel, t.sourceText, '${formatDate(t.time)} ${formatTime(t.time)}'),
      '${s.columnValue}: ${store.value(t)}',
      'cEMI: ${hex(t.raw)}',
    ].join('\n');

    // Action buttons with narrower padding and no extra margin around the tap
    // target (the touch height stays), so that read, copy and filter fit on one
    // line even in the inspector (300).
    const compact = ButtonStyle(
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: HzSpace.s4)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    Future<void> readNow() async {
      final messenger = ScaffoldMessenger.of(context);
      final colors = context.hz;
      if (inSheet) Navigator.pop(context); // Response appears in the monitor
      try {
        final confirmed = await tunnel!.read(t.destination);
        messenger.showSnackBar(
          horizontMessageSnackBar(
            colors,
            s.detailsReadSent(confirmationText(confirmed)),
            status: confirmed == false ? HorizontStatus.warning : HorizontStatus.positive,
          ),
        );
      } on KnxException catch (e) {
        messenger.showSnackBar(horizontMessageSnackBar(colors, e.message, status: HorizontStatus.critical));
      }
    }

    void copyNow() {
      final messenger = ScaffoldMessenger.of(context);
      if (inSheet) Navigator.pop(context);
      Clipboard.setData(ClipboardData(text: summary));
      messenger.showSnackBar(SnackBar(content: Text(s.detailsCopied)));
    }

    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.fromLTRB(
        Gap.gutter,
        inSheet ? 0 : Gap.gutter,
        Gap.gutter,
        Gap.bottom + MediaQuery.viewInsetsOf(context).bottom,
      ),
      children: [
        // Header: eyebrow label, name, value, meta
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: Kennung([t.destinationText, if (dpt != null) 'DPT $dpt'].join(' · '))),
            // Watcher for this address on/off: sound and notification as soon
            // as it is sent.
            ValueListenableBuilder(
              valueListenable: WatchRules.instance,
              builder: (context, _, _) {
                final rule = WatchRules.instance.forAddress(t.destination);
                return IconButton(
                  tooltip: rule == null ? s.watchAdd : s.watchRemove,
                  onPressed: () => toggleWatch(context, t.destination),
                  icon: Icon(AppIcons.watch, color: rule == null ? hz.textMuted : hz.accentText),
                );
              },
            ),
            SoundAckButton(target: AckGroup(t.destination)),
            PopupMenuButton<VoidCallback>(
              tooltip: s.commonMore,
              icon: Icon(AppIcons.more, color: hz.textMuted),
              onSelected: (run) => run(),
              itemBuilder: (context) => [
                if (widget.onOpenMap case final onOpenMap?)
                  PopupMenuItem(value: () => onOpenMap(t.destination), child: Text(s.mapTitle)),
                if (tunnel != null) PopupMenuItem(value: readNow, child: Text(s.typeRead)),
                PopupMenuItem(value: copyNow, child: Text(s.detailsCopy)),
              ],
            ),
            if (widget.onClose != null)
              IconButton(tooltip: s.commonClose, onPressed: widget.onClose, icon: const Icon(AppIcons.close)),
          ],
        ),
        Text(info?.name ?? t.destinationText, style: theme.textTheme.titleMedium),
        if (info?.path != null) ...[
          const SizedBox(height: HzSpace.s2),
          Text(info!.path!, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
        ],
        const SizedBox(height: HzSpace.s12),
        // Current value in the green box as on the overview; the history runs
        // inside it to the edge.
        Material(
          color: hz.accentTint,
          borderRadius: Radii.box,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onOpenChart == null || chart.kind == ChartKind.none
                ? null
                : () => widget.onOpenChart!(t.destination),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(HzSpace.s16, HzSpace.s12, HzSpace.s16, HzSpace.s8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.detailsCurrent.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(color: hz.accentText, fontWeight: FontWeight.w600),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Expanded(
                            child: Text(
                              store.value(t),
                              style: context
                                  .figures(theme.textTheme.titleLarge)
                                  .copyWith(color: hz.accentText, fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (average != null)
                            Text(
                              'Ø ${formatWithUnit(average, unit.isEmpty ? '' : ' $unit')}',
                              style: context.figures(theme.textTheme.bodySmall).copyWith(color: hz.accentText),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (chart.kind != ChartKind.none && chart.points.length >= 2)
                  SizedBox(
                    height: 56,
                    child: Semantics(
                      label: s.detailsHistory,
                      child: Sparkline(
                        values: [for (final p in recent) p.value],
                        // Time axis: a state lasts until now, also the last one.
                        times: [for (final p in recent) p.time],
                        color: hz.accent,
                        fill: hz.accent.withValues(alpha: 0.16),
                        expand: true,
                        step: dpt?.main == 1 || t.isSmall,
                        average: average,
                        averageColor: hz.accentText,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: HzSpace.s4),
        Text(
          '${formatTime(t.time, millis: false)} · $sender',
          style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint),
        ),
        if (expert)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () async {
                await pickDpt(context, t.destination);
                if (mounted) setState(() {});
              },
              icon: const Icon(AppIcons.edit, size: 18),
              // Known from the ETS: "ändern" (change); changed: the ETS value
              // alongside, for the ETS.
              label: Text(switch ((store.overrides.containsKey(t.destination), store.catalog[t.destination]?.dpt)) {
                (true, final ets?) => s.dptChangedFromEts('$ets'),
                (true, null) => s.dptOverridden,
                (false, _?) => s.dptChange,
                (false, null) => s.dptChoose,
              }),
            ),
          ),
        if (activeAlarm(t) case final alarm?) ...[
          const SizedBox(height: Gap.inner),
          // Alarm: critical-tint surface, octagon and word, no borders.
          DecoratedBox(
            decoration: BoxDecoration(color: hz.criticalTint, borderRadius: Radii.tile),
            child: Padding(
              padding: const EdgeInsets.all(Gap.inner),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AlarmChip(kind: alarm, large: true),
                  const SizedBox(width: Gap.inner),
                  Expanded(
                    child: Text(
                      alarm == AlarmKind.alarm ? s.detailsAlarmAlarm : s.detailsAlarmFault,
                      style: theme.textTheme.bodyMedium?.copyWith(color: hz.critical, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        // Three primary actions with labels; map, read and copy in the menu at
        // the top.
        const SizedBox(height: Gap.inner),
        ListenableBuilder(
          listenable: PinnedSections.instance..load(),
          builder: (context, _) {
            final favorite = PinnedSections.instance.isFavorite(t.destination);
            Widget action(String label, VoidCallback onPressed, {bool selected = false}) => Expanded(
              child: OutlinedButton(
                onPressed: onPressed,
                style: compact.copyWith(
                  backgroundColor: selected ? WidgetStatePropertyAll(hz.accentTint) : null,
                  foregroundColor: selected ? WidgetStatePropertyAll(hz.accentText) : null,
                ),
                child: Text(label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
              ),
            );
            return Row(
              spacing: HzSpace.s8,
              children: [
                action(s.detailsComment, () async {
                  await annotateTelegram(context, t);
                  if (mounted) setState(() {});
                }),
                action(
                  s.detailsRemember,
                  () => PinnedSections.instance.toggleFavorite(t.destination),
                  selected: favorite,
                ),
                if (widget.onFilter case final onFilter?)
                  action(
                    widget.filtered ? s.detailsFilterOff : s.detailsFilter,
                    () => onFilter(t.destinationText),
                    selected: widget.filtered,
                  ),
              ],
            );
          },
        ),

        // Comments on this telegram.
        ListenableBuilder(
          listenable: AnnotationStore.instance,
          builder: (context, _) {
            // All comments on this address, including from earlier sessions;
            // those on this telegram first.
            final here = AnnotationScope.forTelegram(t);
            final notes = [...here, ...AnnotationScope.forGroup(t.destination).where((a) => !here.contains(a))];
            if (notes.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: Gap.section),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Kennung(s.annotationsLabel),
                  for (final a in notes)
                    AnnotationTile(
                      annotation: a,
                      onEdit: () async {
                        await editAnnotation(context, a);
                        if (mounted) setState(() {});
                      },
                    ),
                ],
              ),
            );
          },
        ),

        // Hinweise
        if (widget.issues.isNotEmpty)
          _Section(
            title: s.detailsIssues,
            count: widget.issues.length,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final issue in widget.issues)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: HzSpace.s4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IssueChips(issues: [issue], telegram: t),
                        const SizedBox(width: HzSpace.s8),
                        Expanded(child: Text(issue.hint, style: theme.textTheme.bodyMedium)),
                      ],
                    ),
                  ),
              ],
            ),
          ),

        // Cause chain: trigger and reactions around it. Without telegrams
        // before and after it says nothing; the sender is listed under
        // "Telegramm" anyway. When locked, the hint about the tier remains.
        if (widget.around case final around?
            when around.length > 1 &&
                (!Plan.instance.allows(Feature.causeChain) || CauseChain.of(t, around, store.catalog).hasContext))
          _Section(
            title: s.chainTitle,
            child: CauseChainView(telegram: t, log: around),
          ),

        // Telegramm
        _Section(
          title: s.detailsTelegram,
          child: Column(
            children: [
              if (info?.description != null)
                HorizontFact(term: s.detailsDescription, value: info!.description!, selectable: true),
              HorizontFact(
                term: s.columnSender,
                value: ownSource ? '${t.sourceText}  (${s.rowThisTunnel})' : _deviceText(t.source, store),
                measured: true,
                selectable: true,
                onTap: ownSource || widget.onOpenDevice == null ? null : () => widget.onOpenDevice!(t.source),
              ),
              HorizontFact(term: s.columnType, value: typeLabel),
              HorizontFact(
                term: s.detailsPriority,
                value: switch (t.priority) {
                  TelegramPriority.system => s.prioritySystem,
                  TelegramPriority.normal => s.priorityNormal,
                  TelegramPriority.urgent => s.priorityUrgent,
                  TelegramPriority.low => s.priorityLow,
                },
              ),
              HorizontFact(term: s.healthRepeated, value: t.repeated ? s.detailsRepeatedYes : s.commonNo),
              // Hop count only in expert mode.
              if (expert)
                HorizontFact(
                  term: s.detailsHopCount,
                  value:
                      '${t.hopCount} (${t.hopCount == 6
                          ? s.detailsHopDirect
                          : t.hopCount == 7
                          ? s.detailsHopUnlimited
                          : s.detailsHopCouplers(6 - t.hopCount)})',
                  measured: true,
                ),
              if (t.outgoing)
                HorizontFact(
                  term: s.detailsConfirmation,
                  value: t.confirmError ? s.issueNotConfirmedLabel : s.detailsAcknowledged,
                ),
              HorizontFact(
                term: s.columnTime,
                value: '${formatDate(t.time)}  ${formatTime(t.time)}',
                measured: true,
                selectable: true,
              ),
              if (t.type != TelegramType.read)
                HorizontFact(
                  term: s.detailsData,
                  value: t.isSmall ? '${t.data[0]} (6 bit)' : hex(t.data),
                  measured: true,
                  selectable: true,
                ),
              if (t.raw.isNotEmpty) HorizontFact(term: 'cEMI', value: hex(t.raw), measured: true, selectable: true),
            ],
          ),
        ),
        // Schreiben
        if (tunnel != null)
          _Section(
            title: s.detailsWriteValue,
            child: WriteValueControl(
              key: ValueKey(dpt),
              dpt: dpt,
              initial: t,
              primary: false,
              onWrite: ({int? small, List<int> data = const []}) async {
                await requireWriteConfirmation(context, t.destination, small: small, data: data);
                return tunnel.write(t.destination, small: small, data: data);
              },
            ),
          ),

        if (info != null && info.links.isNotEmpty)
          _Section(
            title: s.detailsLinkedDevices(info.links.length),
            child: Column(
              children: [
                for (final link in info.links)
                  _LinkTile(
                    link: link,
                    highlight: link.device == t.source,
                    onTap: widget.onOpenDevice == null ? null : () => widget.onOpenDevice!(link.device),
                  ),
              ],
            ),
          ),
        // Beginners: the technical terms of this telegram, tappable.
        if (!expert)
          _Section(
            title: s.glossaryTitle,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TermChips(
                terms: [
                  Term.groupAddress,
                  Term.individualAddress,
                  Term.dpt,
                  if (info != null && isStatusGroup(info)) Term.status,
                ],
              ),
            ),
          ),
        if (interpretations.isNotEmpty)
          _Section(
            title: dpt == null ? s.detailsInterpretations : s.detailsMoreInterpretations,
            child: Column(
              children: [
                for (final (dpt, value) in interpretations)
                  HorizontFact(term: dpt, value: value, measured: true, selectable: true),
              ],
            ),
          ),
        // History last: it is long, and the line is already shown at the top in
        // the box.
        if (values.isNotEmpty)
          _Section(
            title: s.detailsHistory,
            count: widget.history.length,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onOpenChart case final open? when chart.kind != ChartKind.none)
                  IconButton(
                    tooltip: s.chartsTitle,
                    onPressed: () => open(t.destination),
                    icon: const Icon(AppIcons.fullscreen, size: HzIconSize.row),
                  ),
                Builder(
                  builder: (buttonContext) => IconButton(
                    tooltip: s.detailsHistoryPdf,
                    onPressed: () => _exportChart(buttonContext, chart),
                    icon: Icon(AppIcons.share, size: HzIconSize.row),
                  ),
                ),
              ],
            ),
            child: _HistoryList(telegrams: values),
          ),
      ],
    );
  }
}

/// Section in the inspector: a hairline at the top, eyebrow label with count
/// and optional action, the content below. No card: the line provides
/// structure.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.count, this.trailing});

  final String title;
  final int? count;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Gap.section),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: trailing == null ? 0 : context.hzTheme.controlHeight),
          child: Row(
            children: [
              Expanded(child: SectionTitle(title, count: count)),
              ?trailing,
            ],
          ),
        ),
        const SizedBox(height: HzSpace.s8),
        child,
      ],
    ),
  );
}

/// Values of a group address, newest first: rows with hairlines, time and value
/// in Monaspace.
class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.telegrams});

  final List<Telegram> telegrams;
  static const _limit = 50;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final theme = Theme.of(context);
    final hz = context.hz;
    final store = CatalogStore.instance;
    final rows = telegrams.reversed.take(_limit).toList();
    final line = BorderSide(color: hz.line, width: Lines.hairline);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final t in rows)
          DecoratedBox(
            decoration: BoxDecoration(border: Border(bottom: line)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
              // As in the design: time above the sender, value on the right.
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(formatTime(t.time, millis: false), style: context.figures(theme.textTheme.bodyMedium)),
                        Text(
                          t.outgoing ? s.detailsSentLower : (store.device(t.source)?.name ?? t.sourceText),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: small?.copyWith(color: hz.textFaint),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: HzSpace.s8),
                  // Long raw values without a project wrap in the narrow
                  // details column.
                  Expanded(
                    child: Text(
                      store.value(t),
                      textAlign: TextAlign.end,
                      style: context
                          .figures(theme.textTheme.bodyMedium)
                          .copyWith(color: hz.text, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (telegrams.length > _limit)
          Padding(
            padding: const EdgeInsets.only(top: HzSpace.s8),
            child: Text(s.detailsOlder(telegrams.length - _limit), style: small?.copyWith(color: hz.textMuted)),
          ),
      ],
    );
  }
}

/// "1.1.18 · Heizungsaktor\nProdukt · Hersteller · Ort" (product, manufacturer,
/// location), or just the address.
String _deviceText(int address, CatalogStore store) {
  final d = store.device(address);
  if (d == null) return formatIndividual(address);
  final details = [
    if (d.product != null && d.product != d.name) d.product,
    d.manufacturer,
    d.location,
  ].whereType<String>();
  return '${formatIndividual(address)} · ${d.name}${details.isEmpty ? '' : '\n${details.join(' · ')}'}';
}

/// A communication object linked to the group address: row with hairline,
/// individual address in Monaspace.
class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.link, required this.highlight, this.onTap});

  final GroupLink link;

  /// Opens the device sheet.
  final VoidCallback? onTap;

  /// Whether the device is the sender of the shown telegram.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final device = CatalogStore.instance.device(link.device);
    final meta = [
      if (link.object != null) s.detailsObject(link.object!),
      ?link.text,
      if (link.sends) s.detailsSends,
      // Flags as in the ETS: technical jargon, expert mode only.
      if (expert)
        if (link.flags case final f?) formatFlags(f),
      ?device?.location,
    ].join(' · ');

    final row = DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: hz.line, width: Lines.hairline),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: HzSpace.s2),
              child: Icon(
                link.sends ? AppIcons.sends : AppIcons.receives,
                size: 16,
                color: highlight ? hz.accentText : hz.textMuted,
                semanticLabel: link.sends ? s.detailsSends : s.detailsReceives,
              ),
            ),
            const SizedBox(width: HzSpace.s8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: formatIndividual(link.device), style: context.hzTheme.data),
                        if (device?.name != null) TextSpan(text: '  ${device!.name}'),
                      ],
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: highlight ? FontWeight.w600 : null),
                  ),
                  if (meta.isNotEmpty) Text(meta, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
                ],
              ),
            ),
            if (onTap != null) Icon(AppIcons.next, color: hz.textFaint),
          ],
        ),
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}

/// Lets the user set the datapoint type of a group address (or revert to the
/// project). On iOS and macOS as an action sheet, otherwise as a selection
/// dialog; the current choice has a check mark and is marked as selected for
/// screen readers.
Future<void> pickDpt(BuildContext context, int address) async {
  final store = CatalogStore.instance;
  final project = store.info(address)?.dpt;
  final own = store.overrides[address];
  // false = revert to the project, otherwise the selected DPT.
  final options = <(Object, String, bool)>[
    (false, project == null ? s.dptNone : s.dptFromProject('$project'), own == null),
    for (final f in writeFormats)
      if (f.dpt case final dpt?) (dpt, f.label, own == dpt),
  ];
  final title = Text(s.dptChooseTitle(formatGroup(address)));
  Widget label(String text, bool selected) => Semantics(
    selected: selected,
    inMutuallyExclusiveGroup: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: HzSpace.s24, child: selected ? const Icon(AppIcons.check, size: 18) : null),
        Flexible(child: Text(text)),
        const SizedBox(width: HzSpace.s24),
      ],
    ),
  );
  final apple = switch (Theme.of(context).platform) {
    TargetPlatform.iOS || TargetPlatform.macOS => true,
    _ => false,
  };
  final result = apple
      ? await showCupertinoModalPopup<Object>(
          context: context,
          builder: (context) => CupertinoActionSheet(
            title: title,
            actions: [
              for (final (value, text, selected) in options)
                CupertinoActionSheetAction(
                  isDefaultAction: selected,
                  onPressed: () => Navigator.pop(context, value),
                  child: label(text, selected),
                ),
            ],
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context),
              child: Text(s.commonCancel),
            ),
          ),
        )
      : await showDialog<Object>(
          context: context,
          builder: (context) => SimpleDialog(
            title: title,
            children: [
              for (final (value, text, selected) in options)
                SimpleDialogOption(onPressed: () => Navigator.pop(context, value), child: label(text, selected)),
            ],
          ),
        );
  if (result == null) return;
  await store.setDpt(address, result is Dpt ? result : null);
}
