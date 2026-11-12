import 'dart:async';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/demo_tunnel.dart';
import '../knx/group_catalog.dart';
import '../knx/knx_tunnel.dart';
import '../knx/read_sweep.dart';
import '../knx/shared_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/dali.dart';
import '../model/dali_labels.dart';
import '../model/dali_health.dart' show daliSilentAfter;
import '../model/dali_log.dart';
import '../model/history_store.dart';
import '../model/installation.dart';
import '../model/plan.dart';
import '../model/telegram_log.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'catalog_actions.dart';
import 'common.dart';
import 'dali_commissioning_screen.dart';
import 'dali_log_screen.dart';
import 'dali_watch.dart';
import 'dali_widgets.dart';
import 'figure_box.dart';
import 'plan_screen.dart';
import 'teach_in_screen.dart';
import 'tool_shell.dart';

/// The connection the DALI view works with. The monitor sets it while it is open, so views
/// without a tunnel of their own (device sheet, health check) can open the DALI view.
abstract final class DaliAccess {
  static KnxTunnel? _tunnel;
  static TelegramLog? _log;

  static bool get available => _tunnel != null && _log != null;

  /// Installations whose history was read in this run of the app.
  static final _caughtUp = <String>{};

  static void attach(KnxTunnel tunnel, TelegramLog log) {
    _tunnel = tunnel;
    _log = log;
  }

  static void detach(KnxTunnel tunnel) {
    if (!identical(_tunnel, tunnel)) return;
    _tunnel = null;
    _log = null;
  }

  /// Loads the DALI model and the log of the active installation and brings them up to date with
  /// what the daily history recorded while the app was closed.
  static Future<void> prepare() async {
    final store = DaliStore.instance;
    await store.load();
    await DaliTestLog.instance.load();
    if (store.isEmpty || DemoTunnel.active) return;
    final history = HistoryStore.instance;
    // Only where a server records without the app (add-on, box): the app's own history holds
    // nothing it has not seen live. Once per installation and start of the app.
    final installation = InstallationStore.instance.active.id;
    if (!history.enabled || !HistoryStore.serverManaged || !_caughtUp.add(installation)) return;
    try {
      final from = store.lastObserved ?? DateTime.now().subtract(const Duration(days: 2));
      final days = [
        for (final d in await history.days())
          // At most a week back: older changes are in the log of the gateway, not worth the read.
          if (!d.date.isBefore(DateTime(from.year, from.month, from.day)) &&
              DateTime.now().difference(d.date) < const Duration(days: 8))
            d,
      ]..sort((a, b) => a.date.compareTo(b.date));
      for (final day in days) {
        store.catchUp((await history.open(day, name: '')).telegrams);
      }
    } on Object catch (e) {
      debugPrint('DALI: Tagesverlauf nicht nachgelesen: $e');
    }
  }
}

/// Opens the DALI view, optionally at [gateway] or at one luminaire ([gear], a [DaliGear.id]).
/// Does nothing without a connection.
Future<void> openDali(BuildContext context, {int? gateway, String? gear, bool asTool = false}) async {
  final tunnel = DaliAccess._tunnel;
  final log = DaliAccess._log;
  if (tunnel == null || log == null) return;
  Widget build(BuildContext _) => DaliScreen(tunnel: tunnel, log: log, gateway: gateway, gear: gear);
  if (asTool) {
    await pushTool<void>(context, build);
  } else {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: build));
  }
}

/// Whether the installation has DALI: a gateway in the project, a DALI type on an address, or a
/// gateway heard before. The menu offers the view only then.
bool daliKnown() {
  final store = DaliStore.instance;
  if (!store.isEmpty) return true;
  final catalog = CatalogStore.instance;
  return catalog.overrides.values.any((d) => isDaliDpt(d.main, d.sub));
}

/// Lighting (DALI): gateways with their groups and luminaires. On the phone a list with the faults
/// first, on wide layouts the groups on the left, the grid of the 64 short addresses in the middle
/// and the selected luminaire on the right.
class DaliScreen extends StatefulWidget {
  const DaliScreen({super.key, required this.tunnel, required this.log, this.gateway, this.gear, this.now});

  /// Clock for tests.
  final DateTime Function()? now;

  final KnxTunnel tunnel;
  final TelegramLog log;

  /// Gateway shown first (wide layout).
  final int? gateway;

  /// Luminaire shown first ([DaliGear.id]): selected in the grid, or its sheet on the phone.
  final String? gear;

  /// From this width (divided by the text scale) groups and grid side by side.
  static const medium = 700.0;

  /// From this width (divided by the text scale) the selected luminaire stays visible on the
  /// right.
  static const wide = 1040.0;

  @override
  State<DaliScreen> createState() => _DaliScreenState();
}

class _DaliScreenState extends State<DaliScreen> {
  final _store = DaliStore.instance;
  final _tests = DaliTestLog.instance;

  int? _gateway;
  String? _selected;
  int? _group;
  final _expanded = <int>{};

  /// The luminaire to open as a sheet once the phone layout is shown.
  String? _pendingSheet;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway;
    _selected = widget.gear;
    _pendingSheet = widget.gear;
    if (widget.gear case final id?) _gateway ??= int.tryParse(id.split(':').first);
    unawaited(_store.load());
    unawaited(_tests.load());
  }

  bool get _canRead => DaliStore.canRead(widget.tunnel);

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  Future<void> _read([int? gateway]) async {
    final messenger = ScaffoldMessenger.of(context);
    final colors = context.hz;
    final answered = await _store.readDiagnostics(widget.tunnel, gateway: gateway);
    if (!mounted || answered == null) return;
    messenger.showSnackBar(
      horizontMessageSnackBar(
        colors,
        s.daliReadDone(answered, _store.readTotal),
        status: answered > 0 ? HorizontStatus.positive : HorizontStatus.info,
      ),
    );
  }

  void _openLog() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DaliLogScreen()));

  Future<void> _openCommissioning() async {
    if (!await unlock(context, Feature.commissioning) || !mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => DaliCommissioningScreen(tunnel: widget.tunnel)));
  }

  List<EmergencyTest> _lastTests(DaliGear gear) {
    final row = _tests.overview(_now).where((r) => identical(r.gear, gear)).firstOrNull;
    return [?row?.lastFunction, ?row?.lastDuration, ?row?.lastPartial];
  }

  /// Text of the ETS object a converter was found by.
  String? _objectText(DaliGear gear) {
    final group = gear.resultGroup ?? gear.statusGroup;
    if (group == null) return null;
    final links = CatalogStore.instance.catalog[group]?.links ?? const <GroupLink>[];
    return links.where((l) => l.device == gear.gateway).firstOrNull?.text;
  }

  Future<void> _showGear(DaliGear gear, DaliGateway gateway, {required bool inline}) async {
    if (inline) {
      setState(() => _selected = _selected == gear.id ? null : gear.id);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (sheet) => SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([_store, _tests]),
          builder: (sheet, _) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, Gap.gutter),
            child: _detail(sheet, gear, gateway),
          ),
        ),
      ),
    );
  }

  Widget _detail(BuildContext context, DaliGear gear, DaliGateway gateway, {VoidCallback? onClose}) => DaliGearDetail(
    gear: gear,
    gateway: gateway,
    state: _store.overall(gear),
    lastTests: _lastTests(gear),
    objectText: gear.emergency ? _objectText(gear) : null,
    now: _now,
    onClose: onClose,
    onEdit: () => editDaliGear(context, gear),
    onWatch: !gateway.trusted || gear.address == null || _store.diagnosticGroupsOf(gateway.address).isEmpty
        ? null
        : () => addDaliWatch(context, gateway: gateway, gear: gear),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_store, _tests, widget.tunnel.state]),
    builder: (context, _) {
      final gateways = _store.gateways;
      final hasEmergency = _store.emergencyGear.isNotEmpty || _tests.entries.isNotEmpty;
      return Scaffold(
        appBar: AppBar(
          title: Text(s.daliTitle),
          actions: [
            if (hasEmergency)
              IconButton(tooltip: s.daliLogTitle, onPressed: _openLog, icon: const Icon(AppIcons.history)),
            if (gateways.isNotEmpty)
              PopupMenuButton<VoidCallback>(
                tooltip: s.commonMore,
                icon: Icon(AppIcons.more),
                onSelected: (action) => action(),
                itemBuilder: (_) => [
                  if (hasEmergency) PopupMenuItem(value: _openLog, child: Text(s.daliLogTitle)),
                  if (gateways.any((g) => g.trusted))
                    PopupMenuItem(value: () => addDaliWatch(context), child: Text(s.daliWatchTemplate)),
                  if (gateways.any((g) => _store.groupsOf(g.address).any((x) => x.switchGroup != null)))
                    PopupMenuItem(value: _openCommissioning, child: Text(s.daliCommTitle)),
                  PopupMenuItem(value: _settings, child: Text(s.daliSettings)),
                ],
              ),
            InfoAction(title: s.daliTitle, text: s.daliExplain),
          ],
        ),
        body: gateways.isEmpty ? _empty(context) : _body(context, gateways),
      );
    },
  );

  Widget _empty(BuildContext context) => ListView(
    padding: Gap.page,
    children: [
      HorizontEmptyHint(
        icon: AppIcons.light,
        text: s.daliEmptyTitle,
        detail: s.daliEmptyDetail,
        action: (label: s.daliEmptyProject, onPressed: () => unawaited(importCatalog(context))),
      ),
      Center(
        child: OutlinedButton(
          onPressed: () => unawaited(openTeachIn(context, widget.tunnel, history: widget.log.log)),
          child: Text(s.daliEmptyListen),
        ),
      ),
    ],
  );

  Widget _body(BuildContext context, List<DaliGateway> gateways) => LayoutBuilder(
    builder: (context, box) {
      // Large text needs the room of a wider screen: the layout follows the width per letter.
      final width = box.maxWidth / MediaQuery.textScalerOf(context).scale(1);
      if (width < DaliScreen.medium) {
        if (_pendingSheet case final id?) {
          _pendingSheet = null;
          final gear = _store.gearById(id);
          final gw = gear == null ? null : _store.gateway(gear.gateway);
          if (gear != null && gw != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(_showGear(gear, gw, inline: false));
            });
          }
        }
        return _phone(context, gateways);
      }
      _pendingSheet = null;
      final gateway = gateways.firstWhere((g) => g.address == _gateway, orElse: () => gateways.first);
      return _wide(context, gateways, gateway, inlineDetail: width >= DaliScreen.wide);
    },
  );

  // --- Phone: list ------------------------------------------------------------------------------

  Widget _phone(BuildContext context, List<DaliGateway> gateways) => ListView(
    padding: Gap.page,
    children: [
      for (final (i, gw) in gateways.indexed) ...[
        if (i > 0) const SizedBox(height: Gap.section),
        gw.trusted ? _gatewayCard(context, gw, collapsible: gateways.length > 1) : _suggestion(context, gw),
      ],
      if (_store.emergencyGear.isNotEmpty || _tests.entries.isNotEmpty) ...[
        const SizedBox(height: Gap.section),
        OutlinedButton.icon(
          onPressed: _openLog,
          icon: const Icon(AppIcons.history, size: 18),
          label: Text(s.daliLogTitle),
        ),
      ],
    ],
  );

  /// A gateway heard while listening that is not taken over: its reports do not count yet.
  Widget _suggestion(BuildContext context, DaliGateway gw) {
    final theme = Theme.of(context);
    final gear = _store.gearOf(gw.address);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${daliGatewayLabel(gw)} ${formatIndividual(gw.address)}',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: HzSpace.s4),
          HorizontNotice(HorizontStatus.info, child: Text(s.daliSuggestion(gear.length))),
          const SizedBox(height: Gap.inner),
          EvenRow(
            children: [
              FilledButton(onPressed: () => _store.confirmGateway(gw), child: Text(s.daliConfirm)),
              OutlinedButton(onPressed: () => _store.removeGateway(gw), child: Text(s.daliDismiss)),
            ],
          ),
        ],
      ),
    );
  }

  String _gatewayMeta(DaliGateway gw, int luminaires) {
    final last = gw.lastReport;
    return [
      ?gw.location,
      s.daliLuminaires(luminaires),
      if (last != null) s.daliLastAt(daliWhen(last, _now)),
    ].join(metaSeparator);
  }

  /// Whether the gateway was not heard for longer than the health check allows.
  int? _silentDays(DaliGateway gw) {
    final seen = gw.lastSeen ?? gw.lastReport;
    if (seen == null) return null;
    final quiet = _now.difference(seen);
    return quiet > daliSilentAfter ? quiet.inDays : null;
  }

  /// The badge of a gateway: faults (failed tests count), silent, no report yet, or OK.
  Widget _gatewayBadge(DaliGateway gw, List<DaliGear> gear) {
    final faults = gear.where(_store.needsAttention).length;
    if (faults > 0) return HorizontBadge(HorizontStatus.critical, label: s.daliFaultCount(faults));
    if (gw.lastReport == null) return HorizontBadge(HorizontStatus.neutral, label: s.daliNoReport);
    if (_silentDays(gw) case final days?) return HorizontBadge(HorizontStatus.warning, label: s.daliSilentFor(days));
    return HorizontBadge(HorizontStatus.positive, label: s.daliOk);
  }

  Widget _gatewayHeader(BuildContext context, DaliGateway gw, List<DaliGear> gear, {Widget? trailing}) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final settings = _store.settings;
    final title = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '${daliGatewayLabel(gw)} '),
          TextSpan(
            text: formatIndividual(gw.address),
            style: context.mono(theme.textTheme.titleSmall).copyWith(color: hz.textMuted),
          ),
        ],
      ),
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: HzSpace.s8,
          children: [
            Expanded(
              child: Wrap(
                spacing: HzSpace.s8,
                runSpacing: HzSpace.s4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [title, _gatewayBadge(gw, gear)],
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: HzSpace.s2),
        Text(_gatewayMeta(gw, gear.length), style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
        if (settings.poll && _canRead) ...[
          const SizedBox(height: HzSpace.s2),
          Text(
            s.daliPollActive(daliMinutesChoice(settings.pollMinutes)),
            style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
          ),
        ],
        if (gw.profile case final profile?) ...[
          const SizedBox(height: Gap.item),
          HorizontNotice(
            profile.status == DaliProfileStatus.verified ? HorizontStatus.positive : HorizontStatus.info,
            action: TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              onPressed: () => showInfoDialog(
                context,
                title: profile.name,
                content: Text(
                  [
                    profile.sourceText(s.localeName),
                    profile.noteText(s.localeName),
                  ].where((t) => t.isNotEmpty).join('\n\n'),
                ),
              ),
              child: Text(s.commonMore),
            ),
            child: Text(
              profile.status == DaliProfileStatus.verified
                  ? s.daliProfileVerified(profile.name)
                  : s.daliProfileDocumented(profile.name),
            ),
          ),
        ],
      ],
    );
  }

  /// Read button with what it does: it sends read requests.
  Widget _readAction(BuildContext context, DaliGateway gw, {bool primary = false}) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final count = _store.readableAddresses(gw.address).length;
    if (count == 0) return const SizedBox.shrink();
    final label = '${s.daliReadNow} · ≈ ${ReadSweep.estimate(count).inSeconds} s';
    final onPressed = _canRead && !_store.reading ? () => _read(gw.address) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_store.reading)
          SizedBox(
            width: double.infinity,
            child: LinearProgressIndicator(
              value: _store.readTotal == 0 ? null : _store.readSent / _store.readTotal,
              minHeight: HzSpace.s4,
              borderRadius: Radii.row,
            ),
          )
        else if (primary)
          FilledButton(onPressed: onPressed, child: Text(label))
        else
          OutlinedButton.icon(onPressed: onPressed, icon: const Icon(AppIcons.read, size: 18), label: Text(label)),
        const SizedBox(height: HzSpace.s4),
        Text(
          _canRead ? s.daliReadSends(count) : s.daliReadOnlyHint,
          style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
        ),
      ],
    );
  }

  Widget _gatewayCard(BuildContext context, DaliGateway gw, {required bool collapsible}) {
    final gear = _store.gearOf(gw.address);
    final groups = _store.groupsOf(gw.address);
    final attention = gear.where(_store.needsAttention).toList();
    final healthy = gear.length - attention.length;
    // Several gateways: the healthy ones fold to one row; one without a report never.
    final canFold = collapsible && attention.isEmpty && gw.lastReport != null;
    final folded = canFold && !_expanded.contains(gw.address);
    final showAll = _expanded.contains(-gw.address - 1);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: canFold
                ? () => setState(() => folded ? _expanded.add(gw.address) : _expanded.remove(gw.address))
                : null,
            child: _gatewayHeader(
              context,
              gw,
              gear,
              trailing: canFold
                  ? Icon(
                      folded ? AppIcons.expand : AppIcons.collapse,
                      color: context.hz.textMuted,
                      semanticLabel: folded ? s.daliExpand : s.daliCollapse,
                    )
                  : null,
            ),
          ),
          if (!folded) ...[
            if (gw.lastReport == null) ...[
              const SizedBox(height: Gap.inner),
              Text(s.daliNoReportYet, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: Gap.inner),
              _readAction(context, gw, primary: true),
            ],
            for (final g in attention) ...[const Divider(height: Gap.section), _gearRow(context, g, gw, inline: false)],
            if (groups.isNotEmpty) ...[
              const SizedBox(height: Gap.inner),
              SectionTitle(s.daliGroups, count: groups.length),
              for (final group in groups) _groupRow(context, group, gear, selectable: false),
            ],
            if (healthy > 0) ...[
              const Divider(height: Gap.section),
              InkWell(
                onTap: () =>
                    setState(() => showAll ? _expanded.remove(-gw.address - 1) : _expanded.add(-gw.address - 1)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
                  child: Row(
                    children: [
                      Expanded(child: Text(s.daliOtherLuminaires(healthy))),
                      Icon(showAll ? AppIcons.collapse : AppIcons.expand, color: context.hz.textMuted),
                    ],
                  ),
                ),
              ),
              if (showAll)
                for (final g in gear)
                  if (!attention.contains(g)) _gearRow(context, g, gw, inline: false),
            ],
            if (gw.lastReport != null) ...[const SizedBox(height: Gap.inner), _readAction(context, gw)],
          ],
        ],
      ),
    );
  }

  Widget _gearRow(BuildContext context, DaliGear gear, DaliGateway gw, {required bool inline}) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final state = _store.overall(gear);
    final since = gear.since;
    final meta = daliGearMeta(gear, state: state);
    final sinceText = gear.faulty && since != null ? daliSince(since, _now) : null;
    // Large text: the duration goes below the name instead of squeezing it.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final sinceStyle = theme.textTheme.bodySmall?.copyWith(color: hz.textMuted);
    return Semantics(
      button: true,
      child: InkWell(
        onTap: () => _showGear(gear, gw, inline: inline),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
          child: Row(
            spacing: HzSpace.s12,
            children: [
              if (gear.emergency && !gear.faulty)
                EmergencyMark(failed: state == DaliState.testFailed)
              else
                DaliStateIcon(state, excludeSemantics: true),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(daliGearLabel(gear), style: theme.textTheme.bodyLarge),
                    if (meta.isNotEmpty) Text(meta, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
                    if (stacked && sinceText != null) Text(sinceText, style: sinceStyle),
                  ],
                ),
              ),
              if (!stacked && sinceText != null) Text(sinceText, style: sinceStyle),
            ],
          ),
        ),
      ),
    );
  }

  String _groupMeta(DaliGroup group, List<DaliGear> gear) {
    final members = gear.where((g) => g.groups.contains(group.group)).toList();
    if (members.isEmpty) return group.faults == null ? s.daliGroupNoMembers : daliStateText(group);
    final emergency = members.where((g) => g.emergency).length;
    final failed = members.where((g) => _store.overall(g) == DaliState.testFailed).length;
    if (emergency == members.length) {
      return [s.daliEmergencyCount(emergency), if (failed > 0) s.daliTestsFailed(failed)].join(metaSeparator);
    }
    final ok = members.where((g) => !_store.needsAttention(g)).length;
    return s.daliGroupOk(ok, members.length);
  }

  Widget _groupRow(BuildContext context, DaliGroup group, List<DaliGear> gear, {required bool selectable}) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final selected = selectable && _group == group.group;
    final state = _store.groupState(group);
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: HzSpace.s8, horizontal: selectable ? HzSpace.s12 : 0),
      child: Row(
        spacing: HzSpace.s12,
        children: [
          DaliStateIcon(state),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(daliGroupLabel(group), style: theme.textTheme.bodyLarge),
                Text(_groupMeta(group, gear), style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
              ],
            ),
          ),
          IconButton(
            tooltip: s.daliRenameGroup,
            icon: Icon(AppIcons.edit, size: 18, color: hz.textMuted),
            onPressed: () async {
              final name = await askDaliName(
                context,
                title: '${s.daliRenameGroup} · ${s.daliGroupN(group.group)}',
                current: group.name,
              );
              if (name != null) _store.rename(group, name);
            },
          ),
        ],
      ),
    );
    if (!selectable) return row;
    return Padding(
      padding: const EdgeInsets.only(bottom: HzSpace.s8),
      child: Material(
        color: selected ? hz.accentTint : hz.surface,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.card,
          side: BorderSide(color: selected ? hz.accent : hz.line, width: selected ? Lines.selection : Lines.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _group = selected ? null : group.group),
          child: Semantics(selected: selected, button: true, child: row),
        ),
      ),
    );
  }

  // --- Wide: groups, grid, luminaire ------------------------------------------------------------

  Widget _wide(BuildContext context, List<DaliGateway> gateways, DaliGateway gw, {required bool inlineDetail}) {
    final theme = Theme.of(context);
    final hz = context.hz;
    if (!gw.trusted) {
      return ListView(
        padding: EdgeInsets.fromLTRB(Gap.gutterWide, Gap.item, Gap.gutterWide, Gap.bottom),
        children: [
          _gatewayChoice(gateways, gw),
          const SizedBox(height: Gap.section),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Widths.reading),
              child: _suggestion(context, gw),
            ),
          ),
        ],
      );
    }
    final gear = _store.gearOf(gw.address);
    final groups = _store.groupsOf(gw.address);
    final selected = gear.where((g) => g.id == _selected).firstOrNull;
    final unaddressed = gear.where((g) => g.address == null).toList();
    final hasEmergency = _store.emergencyGear.isNotEmpty || _tests.entries.isNotEmpty;
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(s.daliGroups, count: groups.isEmpty ? null : groups.length),
        const SizedBox(height: Gap.item),
        if (groups.isEmpty)
          Text(s.daliNoGroups, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted))
        else
          for (final group in groups) _groupRow(context, group, gear, selectable: true),
        const SizedBox(height: Gap.inner),
        SectionCard(
          child: Text(s.daliNamesHint, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
        ),
      ],
    );
    final grid = SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.daliGridTitle.toUpperCase(),
                  style: context.mono(theme.textTheme.labelSmall).copyWith(color: hz.textMuted),
                ),
              ),
              Text(
                s.daliGridUsed(gear.where((g) => g.address != null).length),
                style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
              ),
            ],
          ),
          const SizedBox(height: Gap.inner),
          if (gw.lastReport == null) ...[
            Text(s.daliNoReportYet, style: theme.textTheme.bodyMedium),
            const SizedBox(height: Gap.section),
          ],
          _grid(context, gw, gear, inline: inlineDetail),
          if (unaddressed.isNotEmpty) ...[
            const SizedBox(height: Gap.inner),
            SectionTitle(s.daliUnaddressed, count: unaddressed.length),
            for (final g in unaddressed) _gearRow(context, g, gw, inline: inlineDetail),
          ],
          const SizedBox(height: Gap.section),
          const DaliLegend(),
        ],
      ),
    );
    return ListView(
      padding: EdgeInsets.fromLTRB(Gap.gutterWide, Gap.item, Gap.gutterWide, Gap.bottom),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Widths.wide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (gateways.length > 1) ...[_gatewayChoice(gateways, gw), const SizedBox(height: Gap.section)],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Gap.section,
                  children: [
                    Expanded(child: _gatewayHeader(context, gw, gear)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      spacing: HzSpace.s8,
                      children: [
                        if (hasEmergency)
                          OutlinedButton.icon(
                            onPressed: _openLog,
                            icon: const Icon(AppIcons.history, size: 18),
                            label: Text(s.daliLogTitle),
                          ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: _readAction(context, gw, primary: gw.lastReport == null),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: Gap.section),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Gap.section,
                  children: [
                    SizedBox(width: 280, child: left),
                    Expanded(child: grid),
                    if (inlineDetail)
                      SizedBox(
                        width: 340,
                        child: SectionCard(
                          child: selected == null
                              ? Text(s.daliSelectHint, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted))
                              : _detail(context, selected, gw, onClose: () => setState(() => _selected = null)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The gateways as chips: they wrap instead of cutting long names.
  Widget _gatewayChoice(List<DaliGateway> gateways, DaliGateway current) => Wrap(
    spacing: HzSpace.s8,
    runSpacing: HzSpace.s8,
    children: [
      for (final g in gateways)
        ChoiceChip(
          label: Text([formatIndividual(g.address), ?g.location?.split(' › ').last].join(' ')),
          tooltip: daliGatewayLabel(g),
          selected: g.address == current.address,
          avatar: g.trusted ? null : const Icon(HorizontSymbols.help, size: 16),
          onSelected: (_) => setState(() {
            _gateway = g.address;
            _selected = null;
            _group = null;
          }),
        ),
    ],
  );

  Widget _grid(BuildContext context, DaliGateway gw, List<DaliGear> gear, {required bool inline}) {
    final byAddress = {for (final g in gear) ?g.address: g};
    return LayoutBuilder(
      builder: (context, box) {
        const gap = HzSpace.s8;
        // Eight per row as in the gateway's own tool; four where a cell would get smaller than a
        // finger (narrow column, large text). The cell size follows from the columns.
        final min = MediaQuery.textScalerOf(context).scale(44).clamp(44.0, 88.0);
        final columns = (box.maxWidth + gap) / 8 - gap >= min ? 8 : 4;
        final size = (box.maxWidth + gap) / columns - gap;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var a = 0; a < 64; a++)
              SizedBox(
                width: size,
                height: size.clamp(44.0, 96.0),
                child: DaliCell(
                  address: a,
                  gear: byAddress[a],
                  state: byAddress[a] == null ? null : _store.overall(byAddress[a]!),
                  selected: byAddress[a] != null && byAddress[a]!.id == _selected,
                  dimmed: _group != null && !(byAddress[a]?.groups.contains(_group) ?? false),
                  onTap: byAddress[a] == null ? null : () => _showGear(byAddress[a]!, gw, inline: inline),
                ),
              ),
          ],
        );
      },
    );
  }

  // --- Settings ---------------------------------------------------------------------------------

  Future<void> _settings() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (sheet) => SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: _store,
        builder: (sheet, _) {
          final settings = _store.settings;
          final readOnly = !_canRead;
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, Gap.gutter),
            children: [
              SectionTitle(s.daliSettings),
              SwitchRow(
                title: s.daliPoll,
                meta: readOnly ? s.daliReadOnlyHint : s.daliPollHint(_store.readableAddresses().length),
                value: settings.poll && !readOnly,
                onChanged: readOnly ? null : (v) => _store.updateSettings((x) => x.poll = v),
              ),
              if (settings.poll && !readOnly) ...[
                const SizedBox(height: HzSpace.s4),
                DaliChoice<int>(
                  label: s.daliPollEvery,
                  value: settings.pollMinutes,
                  choices: DaliSettings.pollChoices,
                  text: daliMinutesChoice,
                  onChanged: (v) => _store.updateSettings((x) => x.pollMinutes = v),
                ),
              ],
              const SizedBox(height: Gap.section),
              SectionTitle(s.daliIntervals),
              const SizedBox(height: HzSpace.s8),
              DaliChoice<int>(
                label: s.daliIntervalFunction,
                value: settings.functionDays,
                choices: DaliSettings.functionChoices,
                text: daliDaysChoice,
                onChanged: (v) => _store.updateSettings((x) => x.functionDays = v),
              ),
              const SizedBox(height: HzSpace.s8),
              DaliChoice<int>(
                label: s.daliIntervalDuration,
                value: settings.durationDays,
                choices: DaliSettings.durationChoices,
                text: daliDaysChoice,
                onChanged: (v) => _store.updateSettings((x) => x.durationDays = v),
              ),
              const SizedBox(height: Gap.inner),
              Text(s.daliLogLimit, style: Theme.of(sheet).textTheme.bodySmall?.copyWith(color: sheet.hz.textMuted)),
            ],
          );
        },
      ),
    ),
  );
}

/// "30 Tage", "12 Monate", "2 Jahre" for a test interval in days.
String daliDaysChoice(int days) => days >= 730
    ? s.daliYears(days ~/ 365)
    : days >= 180
    ? s.daliMonths((days / 30.4).round())
    : s.daliDays(days);

/// "15 Min.", "1 Std.", "täglich" for the reading interval in minutes.
String daliMinutesChoice(int minutes) => minutes >= 1440
    ? s.daliDaily
    : minutes >= 60
    ? s.daliHoursChoice(minutes ~/ 60)
    : s.daliMinutesChoice(minutes);

/// A setting with a few fixed choices: label on the left, the choice as a menu on the right.
class DaliChoice<T> extends StatelessWidget {
  const DaliChoice({
    super.key,
    required this.label,
    required this.value,
    required this.choices,
    required this.text,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> choices;
  final String Function(T value) text;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    spacing: HzSpace.s12,
    children: [
      Expanded(child: Text(label)),
      DropdownButton<T>(
        icon: const Icon(AppIcons.expand),
        value: choices.contains(value) ? value : null,
        hint: Text(text(value)),
        items: [for (final c in choices) DropdownMenuItem(value: c, child: Text(text(c)))],
        onChanged: (v) => v == null ? null : onChanged(v),
      ),
    ],
  );
}

/// Whether the server the view is connected to refuses to send (for hints next to send buttons).
bool daliServerReadOnly(KnxTunnel tunnel) => tunnel is SharedTunnel && tunnel.readOnly;
