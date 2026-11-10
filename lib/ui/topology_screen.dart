import 'dart:async';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../model/sound_ack.dart';
import 'sound_ack_screen.dart';

import 'bus_activity.dart';
import '../model/activity_range.dart';
import '../platform/addon.dart';
import 'details_sheet.dart';
import 'communication_map_screen.dart';
import '../model/communication_map.dart';
import '../model/plan.dart';
import 'plan_screen.dart';
import '../model/device_channels.dart';
import '../catalog_store.dart';
import '../knx/group_catalog.dart';
import '../knx/knx_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/alarms.dart';
import '../model/device_art.dart';
import '../model/device_shapes.dart';
import '../model/object_groups.dart';
import '../model/telegram_log.dart';
import '../model/tap_coverage.dart';
import '../model/tap_points.dart';
import '../model/topology.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../theme/palette.dart';
import '../model/filter.dart';
import 'common.dart';
import 'coupler_sheet.dart';
import 'actuator_view.dart';
import 'device_sheet.dart';
import 'telegram_row.dart';
import 'live_updates.dart';
import 'statistics_screen.dart' show FigureBox, FigureRow;

/// The "Topologie" (topology) tool: lines with couplers, cross-line group
/// addresses, coupler check and anomalies (hop count, needlessly forwarded
/// telegrams).
class TopologyScreen extends StatefulWidget {
  const TopologyScreen({super.key, required this.log, this.tunnel, this.onFilter});

  /// Sets a filter in the monitor (e.g. "von:1.1.36") and returns there.
  final ValueChanged<String>? onFilter;

  final TelegramLog log;

  /// Connection for the coupler check; `null` for recordings.
  final KnxTunnel? tunnel;

  @override
  State<TopologyScreen> createState() => _TopologyScreenState();
}

class _TopologyScreenState extends State<TopologyScreen> {
  late Topology _topo = _build();
  late _Live _live = _liveOf(_topo);
  late TapCoverage? _coverage = _coverageOf();

  /// With tap points in several lines: coverage and the couplers' filter tables, live (#8).
  TapCoverage? _coverageOf() => TapCoverage.build(CatalogStore.instance.catalog, widget.log.log, tapLabels.value);
  Timer? _refresh;
  CouplerCheckRun? _check;
  int _checked = 0;
  bool _checking = false;

  /// Coupler in the inspector (line behind the coupler) and its neighbouring
  /// line in the view; only in the wide layout.
  (int, int)? _coupler;

  /// Device in the detail area; only from 1200 (device tree on the left).
  int? _device;

  /// Group address in the detail area; only from 1200.
  int? _group;

  /// Line shown on the phone; `null` = the first (gateway line).
  int? _line;

  /// Marked device in iPad portrait, with its row below to open it.
  int? _box;

  /// Search in iPad portrait.
  final _query = TextEditingController();

  Topology _build() => Topology.build(
    CatalogStore.instance.catalog,
    widget.log.log,
    gatewayLine: widget.tunnel?.tunnelAddress == null ? null : lineOf(widget.tunnel!.tunnelAddress!),
  );

  _Live _liveOf(Topology topo) => _Live.build(
    topo,
    CatalogStore.instance.catalog,
    widget.log.log,
    ActivityRangeSetting.instance.value,
    live: widget.tunnel != null,
  );

  /// Recomputes topology and traffic, only on the tick, never in build().
  void _recompute() {
    if (!mounted) return;
    setState(() {
      _topo = _build();
      _live = _liveOf(_topo);
      _coverage = _coverageOf();
    });
  }

  @override
  void initState() {
    super.initState();
    // Traffic keeps flowing: refresh the view every 2 s.
    DeviceArtCatalog.instance.load().then((_) {
      if (mounted) setState(() {});
    });
    _refresh = Timer.periodic(const Duration(seconds: 2), (_) => _recompute());
    ActivityRangeSetting.instance.addListener(_recompute);
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _query.dispose();
    ActivityRangeSetting.instance.removeListener(_recompute);
    super.dispose();
  }

  /// Status, feedback and alarm addresses whose sending device is not on the
  /// gateway line. Commands ("Schalten", switching) usually have no read flag
  /// and would only produce apparent errors.
  List<int> get _candidates {
    final gw = _topo.gatewayLine;
    if (gw == null) return const [];
    return [
      for (final c in _topo.cross)
        if (c.senderLines.any((l) => l != gw) &&
            (ObjectIndex.isFeedbackName(c.info.name) || alarmKindOf(c.info) != null))
          c.address,
    ];
  }

  Future<void> _runCheck() async {
    final tunnel = widget.tunnel!;
    final run = CouplerCheckRun(
      candidates: _candidates,
      gatewayLine: _topo.gatewayLine!,
      read: (a) async {
        _checked++;
        if (mounted) setState(() {});
        await tunnel.read(a);
      },
      answers: tunnel.telegrams,
    );
    setState(() {
      _check = run;
      _checked = 0;
      _checking = true;
    });
    await run.run(
      onProgress: () {
        if (mounted) setState(() {});
      },
    );
    if (mounted) setState(() => _checking = false);
  }

  /// Tapping a coupler while the details are not shown in the page: as a sheet.
  void _openCoupler(int line, int partner) {
    showCouplerSheet(
      context,
      line: line,
      partner: partner,
      log: widget.log,
      gatewayLine: _topo.gatewayLine,
      origin: _topo.lineOfSource,
      onFilter: widget.onFilter,
    );
  }

  /// Tapping a device in the tree: shows it in the detail area, tapping again closes it.
  void _selectDevice(int address) => setState(() {
    _device = _device == address ? null : address;
    _coupler = null;
    _group = null;
  });

  /// Tapping a coupler in the tree: traffic in the detail area.
  void _selectCoupler(int line, int partner) => setState(() {
    _coupler = _coupler?.$1 == line ? null : (line, partner);
    _device = null;
    _group = null;
  });

  /// Whether details appear in the page below the lines (from [Breakpoints.expanded]
  /// available width, next to the toolbar); otherwise as a sheet.
  bool _inPage = false;

  /// Opens a group address: in the page below the lines (lines, devices,
  /// channels), on narrow layouts the detail sheet.
  void _openGroup(int ga) {
    if (_inPage) {
      setState(() {
        _group = _group == ga ? null : ga;
        _device = null;
        _coupler = null;
      });
      return;
    }
    _openGroupSheet(ga);
  }

  /// Detail sheet of the address: value history, writing, devices and map;
  /// without a telegram, the communication map right away.
  void _openGroupSheet(int ga) {
    final history = widget.log.forAddress(ga);
    final telegram = widget.log.latest[ga] ?? history.lastOrNull;
    if (telegram == null) {
      _openMap(ga);
      return;
    }
    showDetailsSheet(
      context,
      telegram,
      tunnel: widget.tunnel,
      history: history,
      onFilter: widget.onFilter,
      onOpenDevice: _openDevice,
      onOpenMap: _openMap,
      log: widget.log,
    );
  }

  /// Opens a device: in the page below the lines, on narrow layouts as a sheet.
  void _openDevice(int address) {
    if (_inPage) {
      setState(() {
        _device = address;
        _coupler = null;
        _group = null;
      });
      return;
    }
    showDeviceSheet(
      context,
      address: address,
      log: widget.log,
      hops: _hopsOf(address),
      line: _topo.lineOfSource(address),
      onFilter: widget.onFilter,
    );
  }

  Future<void> _openMap(int ga) async {
    if (!await unlock(context, Feature.communicationMap) || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunicationMapScreen(log: widget.log, start: MapNode.group(ga)),
      ),
    );
  }

  /// Hop count with which the device has been seen so far.
  int? _hopsOf(int address) {
    for (final l in _topo.lines) {
      if (l.line == _topo.lineOfSource(address)) return l.activeSources[address];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // In the Home Assistant add-on (browser) without any animation: no pulse on
    // cables and guide lines, no flashing of the traffic LEDs, no wind wheel;
    // status LEDs are either lit or not. All drawings respect "reduce motion";
    // here it is fixed for the page.
    if (Addon.embedded) {
      return MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: _page(context));
    }
    return _page(context);
  }

  Widget _page(BuildContext context) {
    final open = _device != null || _group != null || _coupler != null;
    // "Back" first closes the details in the page, then the topology.
    return LayoutBuilder(
      builder: (context, page) => PopScope(
        canPop: !open,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          setState(() {
            _device = null;
            _group = null;
            _coupler = null;
          });
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(s.topoTitle),
            actions: [
              if (page.maxWidth >= Breakpoints.medium && page.maxWidth < Breakpoints.expanded)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: HzSpace.s4),
                  child: SizedBox(
                    width: Widths.tree,
                    child: TextField(
                      style: context.hzTheme.field,
                      controller: _query,
                      autocorrect: false,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        hintText: s.mapSearch,
                      ),
                    ),
                  ),
                ),
              IconButton(
                tooltip: s.topoTitle,
                icon: const Icon(AppIcons.info),
                onPressed: () => showAdaptiveDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog.adaptive(
                    title: Text(s.topoTitle),
                    content: Text(CatalogStore.instance.catalog.devices.isEmpty ? s.topoNoProject : s.topoHint),
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
          body: LayoutBuilder(
            builder: (context, box) {
              // From 840 lines, distribution board and details in the page; the device
              // tree on the left only from 1200, since on the iPad with the toolbar the
              // distribution board is enough. Below that devices as tiles (iPad
              // portrait) or one line as a list (phone).
              _inPage = box.maxWidth >= Breakpoints.expanded;
              if (_inPage) return _split(context, box.maxWidth, tree: box.maxWidth >= Breakpoints.large);
              if (box.maxWidth >= Breakpoints.medium) return _tablet(context);
              return _phone(context);
            },
          ),
        ),
      ),
    );
  }

  /// Noch keine Linie (kein Projekt, kein Verkehr): Hinweis statt Inhalt.
  Widget _noLines() => Padding(
    padding: const EdgeInsets.symmetric(vertical: HzSpace.s48),
    child: HorizontEmptyHint(
      icon: AppIcons.sensors,
      text: CatalogStore.instance.catalog.devices.isEmpty ? s.topoNoProject : s.devNothing,
    ),
  );

  /// Coupler of line [i] (to the line before it).
  Widget _couplerLink(List<LineInfo> lines, int i) =>
      _Link(coupler: lines[i], log: widget.log, onTap: () => _openCoupler(lines[i].line, lines[i - 1].line));

  /// Phone: one line at a time, the choice at the top; key figures, devices,
  /// the couplers of this line and the analysis below.
  Widget _phone(BuildContext context) {
    final lines = _topo.lines;
    if (lines.isEmpty) return ListView(padding: Gap.page, children: [_noLines()]);
    final i = lines.indexWhere((l) => l.line == _line).clamp(0, lines.length - 1);
    final line = lines[i];
    final choice = SegmentedButton<int>(
      showSelectedIcon: false,
      // Viele Linien laufen seitlich statt zu quetschen.
      expandedInsets: lines.length <= 3 ? EdgeInsets.zero : null,
      segments: [for (final l in lines) ButtonSegment(value: l.line, label: Text(s.topoLine(formatLine(l.line))))],
      selected: {line.line},
      onSelectionChanged: (v) => setState(() => _line = v.first),
    );
    return ListView(
      padding: Gap.page,
      children: [
        if (lines.length > 1) ...[
          lines.length <= 3 ? choice : SingleChildScrollView(scrollDirection: Axis.horizontal, child: choice),
          const SizedBox(height: Gap.inner),
        ],
        _LineCard(
          line: line,
          bins: _live.lineBins[line.line] ?? const [],
          gateway: line.line == _topo.gatewayLine,
          tapPoint: _coverage?.lines.contains(line.line) ?? false,
          showTitle: false,
        ),
        // Couplers of the line above the long device list, reachable without scrolling.
        if (i > 0) _couplerLink(lines, i),
        if (i + 1 < lines.length) _couplerLink(lines, i + 1),
        const SizedBox(height: Gap.item),
        _LineDevices(
          key: ValueKey(line.line),
          line: line,
          telegrams: _live.deviceTelegrams,
          onDevice: (address, hops) => showDeviceSheet(
            context,
            address: address,
            log: widget.log,
            hops: hops,
            line: _topo.lineOfSource(address),
            onFilter: widget.onFilter,
          ),
        ),
        const SizedBox(height: Gap.section),
        _analysis(context),
      ],
    );
  }

  /// iPad portrait: key figures of the installation, per line the devices as
  /// tiles. A tile marks the device, its row at the bottom opens it.
  Widget _tablet(BuildContext context) {
    final lines = _topo.lines;
    if (lines.isEmpty) return ListView(padding: Gap.page, children: [_noLines()]);
    final store = CatalogStore.instance;
    final q = _query.text.trim().toLowerCase();
    bool matches(int address, String name) =>
        q.isEmpty ||
        formatIndividual(address).startsWith(q) ||
        name.toLowerCase().contains(q) ||
        (store.device(address)?.product?.toLowerCase().contains(q) ?? false);
    var devices = 0;
    var active = 0;
    var tunnels = 0;
    var telegrams = 0;
    for (final l in lines) {
      final unknown = _unknownOf(l);
      devices += l.devices.length + unknown.length;
      active += l.devices.where((d) => l.activeSources.containsKey(d.address)).length + unknown.length;
      tunnels += l.tunnels.length;
      telegrams += l.telegrams;
    }
    final selected = _box;
    return ListView(
      padding: Gap.page,
      children: [
        FigureBox(
          figures: [
            (s.topoDevices, formatInt(devices)),
            (s.topoActive, formatInt(active)),
            if (tunnels > 0) (s.topoTunnels, formatInt(tunnels)),
            (s.topoTelegrams, formatInt(telegrams)),
          ],
        ),
        for (final (i, line) in lines.indexed) ...[
          const SizedBox(height: Gap.item),
          if (i > 0) _couplerLink(lines, i),
          _Fold(
            title: s.topoLine(formatLine(line.line)),
            count: line.devices.length + _unknownOf(line).length + line.tunnels.length,
            initiallyExpanded: true,
            badge: line.line == _topo.gatewayLine ? HorizontBadge(HorizontStatus.info, label: s.topoGatewayHere) : null,
            children: [
              _DeviceGrid(
                devices: [
                  for (final d in line.devices)
                    if (matches(d.address, d.name)) (d.address, d.name, false),
                  for (final a in _unknownOf(line))
                    if (matches(a, store.device(a)?.name ?? ''))
                      (a, store.device(a)?.name ?? unknownDeviceName(a), true),
                  for (final d in line.tunnels)
                    if (matches(d.address, d.name)) (d.address, d.name, false),
                ],
                line: line,
                selected: selected,
                onTap: (address) => setState(() => _box = _box == address ? null : address),
              ),
            ],
          ),
        ],
        if (selected != null) ...[
          const SizedBox(height: Gap.section),
          _SelectedDevice(
            address: selected,
            telegrams: _live.deviceTelegrams[selected] ?? 0,
            onTap: () => showDeviceSheet(
              context,
              address: selected,
              log: widget.log,
              hops: _hopsOf(selected),
              line: _topo.lineOfSource(selected),
              onFilter: widget.onFilter,
            ),
          ),
        ],
        const SizedBox(height: Gap.section),
        _analysis(context),
      ],
    );
  }

  /// Lines at the top, below them the selected device (or the coupler, otherwise
  /// the overview with the distribution board); with [tree] the device tree on the
  /// left as in ETS, from 1600 the cross-line addresses as a separate column.
  Widget _split(BuildContext context, double width, {required bool tree}) {
    final hz = context.hz;
    final topo = _topo;
    final analysisColumn = width >= Widths.wide;
    final divider = BorderSide(color: hz.line, width: Lines.hairline);
    // Below the lines: the selected device, the selected coupler or the
    // overview (distribution board, traffic between the lines, live).
    final Widget below;
    if (_device case final address?) {
      below = DeviceTraffic(
        key: ValueKey(address),
        address: address,
        log: widget.log,
        hops: _hopsOf(address),
        line: _topo.lineOfSource(address),
        embedded: true,
        onMap: () => openDeviceMap(context, address: address, log: widget.log),
        onFilter: widget.onFilter == null ? null : () => widget.onFilter!(senderQuery(formatIndividual(address))),
        onClose: () => setState(() => _device = null),
      );
    } else if (_group case final ga?) {
      below = _GroupView(
        key: ValueKey(ga),
        address: ga,
        log: widget.log,
        onDevice: _openDevice,
        onDetails: () => _openGroupSheet(ga),
        onMap: () => _openMap(ga),
        onClose: () => setState(() => _group = null),
      );
    } else if (_coupler case final coupler?) {
      below = CouplerTrafficView(
        key: ValueKey(coupler.$1),
        line: coupler.$1,
        partner: coupler.$2,
        log: widget.log,
        gatewayLine: topo.gatewayLine,
        origin: topo.lineOfSource,
        embedded: true,
        onFilter: widget.onFilter,
        onClose: () => setState(() => _coupler = null),
      );
    } else {
      below = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.section,
        children: [
          _Rails(topo: topo, log: widget.log, onDevice: _selectDevice),
          _Traffic(topo: topo, live: _live, onGroup: _openGroup, onCoupler: _selectCoupler),
          if (!analysisColumn) _analysis(context),
        ],
      );
    }
    final detail = ListView(
      padding: Gap.page,
      children: [
        _Lines(
          topo: topo,
          log: widget.log,
          bins: _live.lineBins,
          tapLines: _coverage?.lines ?? const {},
          selected: _coupler?.$1,
          onCoupler: _selectCoupler,
        ),
        const SizedBox(height: Gap.section),
        below,
      ],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tree)
          Container(
            width: Widths.tree,
            decoration: BoxDecoration(border: BorderDirectional(end: divider)),
            child: _DeviceTree(
              topo: topo,
              telegrams: _live.deviceTelegrams,
              device: _device,
              coupler: _coupler?.$1,
              onOverview: () => setState(() {
                _device = null;
                _coupler = null;
              }),
              onDevice: _selectDevice,
              onCoupler: _selectCoupler,
            ),
          ),
        Expanded(child: detail),
        if (analysisColumn)
          Container(
            width: Widths.column,
            decoration: BoxDecoration(border: BorderDirectional(start: divider)),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Gap.gutter, Gap.item, Gap.gutter, Gap.bottom),
              children: [_analysis(context, stacked: true)],
            ),
          ),
      ],
    );
  }

  /// Cross-line addresses with coupler check and anomalies; side by side as
  /// soon as two card columns fit and not [stacked].
  Widget _analysis(BuildContext context, {bool stacked = false}) {
    final theme = Theme.of(context);
    final topo = _topo;
    final connected = widget.tunnel?.state.value == TunnelState.connected;
    final candidates = _candidates;
    return LayoutBuilder(
      builder: (context, area) {
        final crossCard = SectionCard(
          flat: stacked,
          padding: stacked ? _flatPadding : null,
          title: s.topoCross,
          count: topo.cross.length,
          trailing: widget.tunnel == null || candidates.isEmpty
              ? null
              : OutlinedButton.icon(
                  onPressed: connected && !_checking ? _runCheck : null,
                  icon: _checking
                      ? const SizedBox.square(
                          dimension: HzSpace.s16,
                          child: CircularProgressIndicator.adaptive(strokeWidth: Lines.selection),
                        )
                      : const Icon(AppIcons.search),
                  label: Text(_checking ? s.topoCheckRunning(_checked, candidates.length) : s.topoCheck),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.tunnel == null ? s.topoCrossHint : '${s.topoCrossHint} ${s.topoCheckHint}',
                style: theme.textTheme.bodySmall?.copyWith(color: context.hz.textMuted),
              ),
              if (widget.tunnel != null && candidates.isEmpty && topo.cross.isNotEmpty) ...[
                const SizedBox(height: HzSpace.s8),
                Text(s.topoCheckNone, style: theme.textTheme.bodySmall),
              ],
              const SizedBox(height: Gap.item),
              for (final (i, c) in topo.cross.indexed)
                _CrossRow(group: c, topo: topo, check: _check, first: i == 0, onTap: () => _openGroup(c.address)),
            ],
          ),
        );
        final issues = _Issues(
          topo: topo,
          coverage: _coverage,
          flat: stacked,
          onGroup: _openGroup,
          onDevice: _openDevice,
        );
        if (stacked || area.maxWidth < 2 * Widths.column + Gap.section) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: stacked ? HzSpace.s32 : Gap.section,
            children: [issues, crossCard],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Gap.section,
          children: [
            Expanded(flex: 3, child: crossCard),
            Expanded(flex: 2, child: issues),
          ],
        );
      },
    );
  }
}

/// Flat cards clip their corners: padding so the stroke of the section title
/// stays whole.
const _flatPadding = EdgeInsets.fromLTRB(HzSpace.s4, HzSpace.s4, 0, 0);

/// Project devices and observed senders of a line that are not in the project
/// (without couplers x.y.0).
List<int> _unknownOf(LineInfo line) {
  final project = {
    for (final d in [...line.devices, ...line.tunnels]) d.address,
  };
  return [
    for (final a in line.activeSources.keys)
      if (!project.contains(a) && a & 0xFF != 0) a,
  ]..sort();
}

/// Device tree as in ETS: root "Übersicht" (overview of the lines), per line a
/// header with key figures, couplers, devices and tunnels. Lines are expanded
/// and can be collapsed individually.
class _DeviceTree extends StatefulWidget {
  const _DeviceTree({
    required this.topo,
    required this.telegrams,
    required this.device,
    required this.coupler,
    required this.onOverview,
    required this.onDevice,
    required this.onCoupler,
  });

  final Topology topo;

  /// [_Live.deviceTelegrams].
  final Map<int, int> telegrams;
  final int? device;

  /// Line of the coupler in the detail area.
  final int? coupler;
  final VoidCallback onOverview;
  final ValueChanged<int> onDevice;
  final void Function(int line, int partner) onCoupler;

  @override
  State<_DeviceTree> createState() => _DeviceTreeState();
}

class _DeviceTreeState extends State<_DeviceTree> {
  final _collapsed = <int>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final store = CatalogStore.instance;
    final topo = widget.topo;
    final lines = topo.lines;
    final overview = widget.device == null && widget.coupler == null;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: HzSpace.s8, vertical: Gap.item),
      children: [
        _TreeRow(
          selected: overview,
          onTap: widget.onOverview,
          child: Row(
            children: [
              Icon(AppIcons.topology, size: HzIconSize.inline, color: overview ? hz.accentText : hz.textMuted),
              const SizedBox(width: HzSpace.s8),
              Text(s.mapOverview, style: theme.textTheme.labelLarge),
            ],
          ),
        ),
        for (final (i, line) in lines.indexed) ...[
          const SizedBox(height: Gap.item),
          _lineHeader(context, line, topo.gatewayLine == line.line),
          if (!_collapsed.contains(line.line)) ...[
            if (i > 0) _coupler(context, line, lines[i - 1].line),
            for (final d in line.devices)
              _DeviceRow(
                address: d.address,
                name: d.name,
                hops: line.activeSources[d.address],
                telegrams: widget.telegrams[d.address],
                selected: widget.device == d.address,
                onTap: () => widget.onDevice(d.address),
              ),
            for (final a in _unknownOf(line))
              _DeviceRow(
                address: a,
                name: store.device(a)?.name ?? unknownDeviceName(a),
                hops: line.activeSources[a],
                telegrams: widget.telegrams[a],
                unknown: true,
                selected: widget.device == a,
                onTap: () => widget.onDevice(a),
              ),
            if (line.tunnels.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(HzSpace.s4, Gap.inner, HzSpace.s4, HzSpace.s4),
                child: SectionTitle(s.topoTunnels, count: line.tunnels.length),
              ),
              for (final d in line.tunnels)
                _DeviceRow(
                  address: d.address,
                  name: d.name,
                  hops: line.activeSources[d.address],
                  telegrams: widget.telegrams[d.address],
                  selected: widget.device == d.address,
                  onTap: () => widget.onDevice(d.address),
                ),
            ],
          ],
        ],
      ],
    );
  }

  /// Header of a line: label, gateway badge and key figures; tapping collapses
  /// or expands the devices.
  Widget _lineHeader(BuildContext context, LineInfo line, bool gateway) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final collapsed = _collapsed.contains(line.line);
    final unknown = _unknownOf(line);
    final active = line.devices.where((d) => line.activeSources.containsKey(d.address)).length + unknown.length;
    return _TreeRow(
      expanded: !collapsed,
      onTap: () => setState(() => collapsed ? _collapsed.remove(line.line) : _collapsed.add(line.line)),
      child: Row(
        children: [
          Icon(collapsed ? AppIcons.next : AppIcons.expand, size: HzIconSize.inline, color: hz.textMuted),
          const SizedBox(width: HzSpace.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(s.topoLine(formatLine(line.line)), count: line.devices.length + unknown.length),
                const SizedBox(height: HzSpace.s2),
                Text(
                  ['${s.topoActive} $active', '${formatInt(line.telegrams)} ${s.topoTelegrams}'].join(metaSeparator),
                  style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint, fontFeatures: tabular),
                ),
              ],
            ),
          ),
          if (gateway) HorizontBadge(HorizontStatus.info, label: s.topoGatewayHere),
          SoundAckButton(target: AckLine((line.line >> 4) & 0x0F, line.line & 0x0F)),
        ],
      ),
    );
  }

  /// Coupler of the line (x.y.0) as the first row below the header.
  Widget _coupler(BuildContext context, LineInfo line, int partner) {
    final hz = context.hz;
    final data = context.hzTheme.data;
    final selected = widget.coupler == line.line;
    final d = line.coupler;
    return _TreeRow(
      selected: selected,
      semanticsLabel: s.hzHCouplerOpen(formatIndividual(line.line << 8)),
      onTap: () => widget.onCoupler(line.line, partner),
      child: Row(
        children: [
          Icon(AppIcons.topology, size: HzIconSize.inline, color: selected ? hz.accentText : hz.textMuted),
          const SizedBox(width: HzSpace.s8),
          SizedBox(
            width: HzSpace.s64,
            child: Text(formatIndividual(line.line << 8), style: data.copyWith(color: hz.text)),
          ),
          Expanded(
            child: Text(
              d?.name ?? s.hzHCouplerOpen(formatIndividual(line.line << 8)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Icon(AppIcons.next, size: HzIconSize.inline, color: hz.textMuted),
        ],
      ),
    );
  }
}

/// Row in the device tree: hover tone, selection following Horizont ([HorizontSelectable]).
class _TreeRow extends StatelessWidget {
  const _TreeRow({required this.child, required this.onTap, this.selected = false, this.expanded, this.semanticsLabel});

  final Widget child;
  final VoidCallback onTap;
  final bool selected;

  /// Expandable (line header): expanded or not.
  final bool? expanded;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    // `expanded` for line headers.
    return Semantics(
      expanded: expanded,
      child: HorizontSelectable(
        selected: selected,
        onTap: onTap,
        semanticsLabel: semanticsLabel,
        minHeight: HzSize.touch,
        padding: const EdgeInsets.symmetric(horizontal: HzSpace.s4, vertical: HzSpace.s2),
        child: child,
      ),
    );
  }
}

/// Lines as cards, connected via their couplers; the gateway line first.
class _Lines extends StatelessWidget {
  const _Lines({
    required this.topo,
    required this.log,
    required this.bins,
    required this.onCoupler,
    this.tapLines = const {},
    this.selected,
  });

  final Topology topo;

  /// Lines with a tap point (issue #8).
  final Set<int> tapLines;

  /// Traffic for the coupler graphics (traffic LEDs, pulse on the wires).
  final TelegramLog log;

  /// Verlauf je Linie ([_Live.lineBins]).
  final Map<int, List<int>> bins;

  /// Coupler tapped: the line behind it and the neighbouring line in the view.
  final void Function(int line, int partner) onCoupler;

  /// Line of the coupler in the inspector.
  final int? selected;

  @override
  Widget build(BuildContext context) {
    final lines = topo.lines;
    return LayoutBuilder(
      builder: (context, c) {
        // As many lines side by side as cards with minimum width fit (at most
        // four); further lines in the next row.
        const minCard = Widths.gridCard + HzSpace.s64;
        final perRow = ((c.maxWidth + HzSpace.s64) / (minCard + HzSpace.s64)).floor().clamp(1, 4);
        final cards = [
          for (final l in lines)
            _LineCard(
              line: l,
              bins: bins[l.line] ?? const [],
              gateway: l.line == topo.gatewayLine,
              tapPoint: tapLines.contains(l.line),
            ),
        ];
        // Noch keine Linie (kein Projekt, kein Verkehr): Hinweis statt Reihe.
        if (lines.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: HzSpace.s48),
            child: HorizontEmptyHint(
              icon: AppIcons.sensors,
              text: CatalogStore.instance.catalog.devices.isEmpty ? s.topoNoProject : s.devNothing,
            ),
          );
        }
        if (perRow == 1 || lines.length == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, card) in cards.indexed) ...[if (i > 0) _link(lines, i), card],
            ],
          );
        }
        final columns = perRow.clamp(1, lines.length);
        // Cards do not grow arbitrarily: at most [Widths.lineCard] wide, the
        // row centered in the window.
        final link = lines.length > 1 && _hasArt(lines[1]) ? _Link.artWidth : HzSpace.s64;
        final rowWidth = columns * Widths.lineCard + (columns - 1) * link;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: rowWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var start = 0; start < cards.length; start += columns) ...[
                  // Coupler of the first line of a row: vertically above it.
                  // Coupler of the first line of a row: centered above its box.
                  if (start > 0)
                    Row(
                      children: [
                        Expanded(child: Center(child: _link(lines, start))),
                        for (var i = 1; i < columns; i++) ...[SizedBox(width: link), const Expanded(child: SizedBox())],
                      ],
                    ),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = start; i < start + columns; i++) ...[
                          if (i > start) i < cards.length ? _link(lines, i, horizontal: true) : SizedBox(width: link),
                          Expanded(
                            child: i < cards.length
                                // When expanding and collapsing, the row height briefly lags behind the content.
                                ? OverflowBox(
                                    alignment: Alignment.topCenter,
                                    maxHeight: double.infinity,
                                    child: cards[i],
                                  )
                                : const SizedBox(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  bool _hasArt(LineInfo line) => DeviceArtCatalog.instance.of(line.coupler) != null;

  Widget _link(List<LineInfo> lines, int i, {bool horizontal = false}) => _Link(
    coupler: lines[i],
    log: log,
    horizontal: horizontal,
    selected: selected == lines[i].line,
    onTap: () => onCoupler(lines[i].line, lines[i - 1].line),
  );
}

/// Connection between two lines: the coupler of the right/lower line.
class _Link extends StatefulWidget {
  const _Link({
    required this.coupler,
    required this.log,
    required this.onTap,
    this.horizontal = false,
    this.selected = false,
  });

  /// Width of the connection when the coupler appears as a manufacturer graphic.
  static const artWidth = 112.0;

  final LineInfo coupler;
  final TelegramLog log;
  final bool horizontal;

  /// Whether the coupler is opened in the inspector.
  final bool selected;

  /// Shows traffic via the coupler.
  final VoidCallback onTap;

  @override
  State<_Link> createState() => _LinkState();
}

class _LinkState extends State<_Link> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final d = widget.coupler.coupler;
    final address = formatIndividual(widget.coupler.line << 8);
    final label = d == null ? '' : s.topoCoupler(formatIndividual(d.address), d.name);
    final selected = widget.selected;
    // Connection as a neutral hairline, the coupler as a tile (radius 6).
    final line = Container(width: Lines.hairline, height: HzSpace.s16, color: hz.lineStrong);
    final tile = Container(
      padding: const EdgeInsets.all(HzSpace.s8),
      decoration: BoxDecoration(
        color: selected ? hz.accentTint : hz.surface,
        borderRadius: Radii.tile,
        border: Border.all(
          color: selected ? hz.accentText : hz.lineStrong,
          width: selected ? Lines.selection : Lines.hairline,
        ),
      ),
      child: Icon(AppIcons.topology, color: selected ? hz.accentText : hz.textMuted),
    );
    // Button: tile (narrow with label), hover tone and focus ring (2 px accent
    // with 2 px gap).
    Widget button(Widget child) => Semantics(
      button: true,
      selected: selected,
      label: s.hzHCouplerOpen(address),
      excludeSemantics: true,
      child: Tooltip(
        message: label.isEmpty ? s.hzHCouplerOpen(address) : label,
        child: Container(
          padding: const EdgeInsets.all(HzSpace.s2),
          decoration: BoxDecoration(
            borderRadius: Radii.tile,
            border: Border.all(color: _focused ? hz.accent : Colors.transparent, width: HzLine.focus),
          ),
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: (f) => setState(() => _focused = f),
            borderRadius: Radii.tile,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: HzSize.touch, minHeight: HzSize.touch),
              child: child,
            ),
          ),
        ),
      ),
    );
    // With manufacturer graphic: the coupler itself, with status LEDs and wires
    // that light up on telegrams across the line.
    final deviceArt = DeviceArtCatalog.instance.of(d);
    final artWidth = widget.horizontal ? 64.0 : 72.0;
    final art = deviceArt == null
        ? null
        : SizedBox(
            width: artWidth,
            height: compactArtHeight(deviceArt, artWidth),
            child: RepaintBoundary(
              child: ExcludeSemantics(
                child: ActuatorView(
                  address: d!.address,
                  log: widget.log,
                  compact: true,
                  cableReach: widget.horizontal ? (_Link.artWidth - artWidth) / 2 : null,
                ),
              ),
            ),
          );
    if (widget.horizontal && art != null) {
      // Without its own height: the line cards determine the row, the coupler
      // sits flush at the bottom and may overhang at the top. The graphic's
      // wires run all the way to the line boxes by themselves.
      return SizedBox(
        width: _Link.artWidth,
        height: 0,
        child: OverflowBox(
          minWidth: 0,
          minHeight: 0,
          maxHeight: compactArtHeight(deviceArt!, artWidth) + 2 * (HzSpace.s2 + HzLine.focus),
          alignment: Alignment.bottomCenter,
          child: button(art),
        ),
      );
    }
    if (widget.horizontal) {
      return SizedBox(
        width: HzSpace.s64,
        child: Column(
          children: [
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: Container(height: Lines.hairline, color: hz.lineStrong),
                ),
                button(Center(child: tile)),
                Expanded(
                  child: Container(height: Lines.hairline, color: hz.lineStrong),
                ),
              ],
            ),
            const Spacer(),
          ],
        ),
      );
    }
    // With a graphic and without a label (it is in the tooltip): hairline,
    // coupler and box then lie on one axis.
    if (art != null) {
      return Column(children: [line, button(art), line]);
    }
    return Column(
      children: [
        line,
        button(
          Padding(
            padding: const EdgeInsetsDirectional.only(end: HzSpace.s8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ?art,
                if (art == null) tile,
                const SizedBox(width: HzSpace.s8),
                Flexible(
                  child: Text(
                    label.isEmpty ? s.hzHCouplerOpen(address) : label,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: HzSpace.s4),
                Icon(AppIcons.next, size: HzIconSize.inline, color: hz.textMuted),
              ],
            ),
          ),
        ),
        line,
      ],
    );
  }
}

/// Key figures of a line as a green box, its history on the right.
class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.line,
    required this.bins,
    required this.gateway,
    this.tapPoint = false,
    this.showTitle = true,
  });

  /// A tap point measures in this line (issue #8): what stays in it is seen.
  final bool tapPoint;

  /// History of the line within the time span of the activity bar.
  final List<int> bins;

  final LineInfo line;
  final bool gateway;

  /// Whether to omit the title when the line choice above already names it.
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final unknown = _unknownOf(line);
    final active = line.devices.where((d) => line.activeSources.containsKey(d.address)).length;
    return SectionCard(
      soft: true,
      title: showTitle ? s.topoLine(formatLine(line.line)) : null,
      trailing: gateway
          ? HorizontBadge(HorizontStatus.info, label: s.topoGatewayHere)
          : tapPoint
          ? HorizontBadge(HorizontStatus.positive, label: s.topoTapPoint)
          : null,
      child: FigureRow(
        figures: [
          // Project and observed devices together, like the list below; active
          // are all that have sent (without a project only those).
          (s.topoDevices, formatInt(line.devices.length + unknown.length)),
          (s.topoActive, formatInt(active + unknown.length)),
          if (line.tunnels.isNotEmpty) (s.topoTunnels, formatInt(line.tunnels.length)),
          (s.topoTelegrams, formatInt(line.telegrams)),
          (s.topoCouplers, line.couplersToGateway?.toString() ?? '—'),
        ],
        trailing: _LineActivity(line: line.line, values: bins),
      ),
    );
  }
}

/// Devices of a line as a list, tunnels separately below (phone).
class _LineDevices extends StatelessWidget {
  const _LineDevices({super.key, required this.line, required this.telegrams, required this.onDevice});

  final LineInfo line;

  /// [_Live.deviceTelegrams].
  final Map<int, int> telegrams;
  final void Function(int address, int? hops) onDevice;

  @override
  Widget build(BuildContext context) {
    final store = CatalogStore.instance;
    final unknown = _unknownOf(line);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Devices expanded: they are the core of the topology.
        _Fold(
          title: s.topoDevices,
          count: line.devices.length + unknown.length,
          initiallyExpanded: true,
          children: [
            for (final d in line.devices)
              _DeviceRow(
                address: d.address,
                name: d.name,
                hops: line.activeSources[d.address],
                telegrams: telegrams[d.address],
                onTap: () => onDevice(d.address, line.activeSources[d.address]),
              ),
            for (final a in unknown)
              _DeviceRow(
                address: a,
                name: store.device(a)?.name ?? unknownDeviceName(a),
                hops: line.activeSources[a],
                telegrams: telegrams[a],
                unknown: true,
                onTap: () => onDevice(a, line.activeSources[a]),
              ),
          ],
        ),
        // Tunnels separately: additional addresses of the IP interfaces.
        if (line.tunnels.isNotEmpty)
          _Fold(
            title: s.topoTunnels,
            count: line.tunnels.length,
            children: [
              for (final d in line.tunnels)
                _DeviceRow(
                  address: d.address,
                  name: d.name,
                  hops: line.activeSources[d.address],
                  telegrams: telegrams[d.address],
                  onTap: () => onDevice(d.address, line.activeSources[d.address]),
                ),
            ],
          ),
      ],
    );
  }
}

/// Expandable section: title with counter and chevron, the rows below.
class _Fold extends StatefulWidget {
  const _Fold({
    required this.title,
    required this.count,
    required this.children,
    this.initiallyExpanded = false,
    this.badge,
  });

  final String title;
  final int count;
  final List<Widget> children;
  final bool initiallyExpanded;

  /// Badge in the header (gateway).
  final Widget? badge;

  @override
  State<_Fold> createState() => _FoldState();
}

class _FoldState extends State<_Fold> {
  late bool _collapsed = !widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        button: true,
        expanded: !_collapsed,
        child: InkWell(
          onTap: () => setState(() => _collapsed = !_collapsed),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: HzSize.touch),
            child: Row(
              spacing: HzSpace.s8,
              children: [
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SectionTitle(widget.title, count: widget.count),
                  ),
                ),
                ?widget.badge,
                Icon(_collapsed ? AppIcons.expand : AppIcons.collapse, color: context.hz.textMuted),
              ],
            ),
          ),
        ),
      ),
      AnimatedSize(
        duration: Motion.of(context),
        curve: Motion.curve,
        alignment: AlignmentDirectional.topStart,
        child: _collapsed
            ? const SizedBox(width: double.infinity)
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: widget.children),
      ),
    ],
  );
}

/// Subtitle of a device: product (if not already the name) and hop, or
/// "nicht gesehen" (not seen) as a word, never only as color.
String _deviceMeta(int address, String name, int? hops) {
  final product = CatalogStore.instance.device(address)?.product;
  return [
    if (product != null && product != name) product,
    hops != null ? 'Hop $hops' : s.topoSilent,
  ].join(metaSeparator);
}

/// Device row: address and name, product and hop small below, on the right the
/// telegrams in bold and the chevron.
class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.address,
    required this.name,
    required this.hops,
    this.telegrams,
    this.unknown = false,
    this.selected = false,
    this.onTap,
  });

  final VoidCallback? onTap;

  /// Whether it is opened in the detail area (device tree).
  final bool selected;

  final int address;
  final String name;
  final int? hops;

  /// Sent telegrams in the history.
  final int? telegrams;
  final bool unknown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: hz.line, width: Lines.hairline),
        ),
      ),
      child: HorizontSelectable(
        selected: selected,
        onTap: onTap,
        minHeight: HzSize.touch,
        padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
        child: Row(
          spacing: HzSpace.s8,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    spacing: HzSpace.s8,
                    children: [
                      Text(
                        formatIndividual(address),
                        style: context
                            .mono(theme.textTheme.bodyMedium)
                            .copyWith(color: hz.textMuted, fontWeight: FontWeight.w600),
                      ),
                      if (unknown) Icon(HorizontStatus.warning.icon, size: HzIconSize.inline, color: hz.warning),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(color: unknown ? hz.warning : hz.text),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _deviceMeta(address, name, hops),
                    style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint),
                  ),
                ],
              ),
            ),
            if (telegrams case final n?)
              Text(
                formatInt(n),
                style: context.figures(theme.textTheme.bodyLarge).copyWith(fontWeight: FontWeight.w700),
              ),
            Icon(AppIcons.next, size: HzIconSize.inline, color: hz.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Devices of a line as tiles in columns (iPad portrait): address, name in
/// bold, product and hop below.
class _DeviceGrid extends StatelessWidget {
  const _DeviceGrid({required this.devices, required this.line, required this.selected, required this.onTap});

  /// Address, name, not in the project.
  final List<(int, String, bool)> devices;
  final LineInfo line;
  final int? selected;
  final ValueChanged<int> onTap;

  /// Mindestbreite einer Kachel.
  static const _minWidth = 200.0;

  /// Height for three lines; grows with the font.
  static const _height = 80.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final height = MediaQuery.textScalerOf(context).scale(_height);
    return LayoutBuilder(
      builder: (context, box) {
        const gap = HzSpace.s8;
        final columns = ((box.maxWidth + gap) / (_minWidth + gap)).floor().clamp(1, 4);
        final width = (box.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (address, name, unknown) in devices)
              SizedBox(
                width: width,
                height: height,
                child: Semantics(
                  button: true,
                  selected: selected == address,
                  child: Material(
                    color: selected == address ? hz.accentTint : hz.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: Radii.card,
                      side: BorderSide(
                        color: selected == address ? hz.accent : hz.line,
                        width: selected == address ? Lines.selection : Lines.hairline,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onTap(address),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Gap.inner, vertical: HzSpace.s8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              spacing: HzSpace.s4,
                              children: [
                                Text(
                                  formatIndividual(address),
                                  style: context
                                      .mono(theme.textTheme.bodySmall)
                                      .copyWith(color: hz.textMuted, fontWeight: FontWeight.w600),
                                ),
                                if (unknown)
                                  Icon(HorizontStatus.warning.icon, size: HzIconSize.inline, color: hz.warning),
                              ],
                            ),
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              _deviceMeta(address, name, line.activeSources[address]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Row of the marked device: opens the device sheet.
class _SelectedDevice extends StatelessWidget {
  const _SelectedDevice({required this.address, required this.telegrams, required this.onTap});

  final int address;
  final int telegrams;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final store = CatalogStore.instance;
    final device = store.device(address);
    final groups = store.catalog.groups.values.where((g) => g.links.any((l) => l.device == address)).length;
    return Material(
      color: hz.surface,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.card,
        side: BorderSide(color: hz.line, width: Lines.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Gap.card),
          child: Row(
            spacing: HzSpace.s8,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AddressTitle('${formatIndividual(address)}  ${device?.name ?? unknownDeviceName(address)}'),
                    Text(
                      [
                        ?device?.product,
                        '${formatInt(telegrams)} ${s.topoTelegrams}',
                        '${formatInt(groups)} ${s.devGroups}',
                      ].join(metaSeparator),
                      style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint),
                    ),
                  ],
                ),
              ),
              Icon(AppIcons.next, color: hz.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _CrossRow extends StatelessWidget {
  const _CrossRow({required this.group, required this.topo, this.check, this.first = false, this.onTap});

  /// Opens the address (details, history, writing, devices).
  final VoidCallback? onTap;

  final CrossGroup group;
  final Topology topo;
  final CouplerCheckRun? check;

  /// Whether this is the first row: no hairline above it.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final g = group;
    String lines(Iterable<int> l) => l.isEmpty ? '—' : (l.toList()..sort()).map(formatLine).join(', ');
    final direction = '${s.topoSends(lines(g.senderLines))}  ·  ${s.topoListens(lines(g.lines))}';
    final fromOther = g.seenFrom.entries.where((e) => e.key != topo.gatewayLine).fold(0, (n, e) => n + e.value);
    final result = check?.results[g.address];
    final responder = check?.responders[g.address];
    final status = result == CouplerCheck.passed ? HorizontStatus.positive : HorizontStatus.warning;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
        decoration: BoxDecoration(
          border: first
              ? null
              : Border(
                  top: BorderSide(color: hz.line, width: Lines.hairline),
                ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Like the device rows: address and name, the direction small below.
                  AddressTitle('${formatGroup(g.address)}  ${g.info.name}'),
                  Text(
                    [direction, if (fromOther > 0) '$fromOther× ${s.topoTelegrams}'].join(metaSeparator),
                    style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint, fontFeatures: tabular),
                  ),
                  if (result != null)
                    Text(
                      result == CouplerCheck.passed
                          ? s.topoCheckPassed(responder == null ? '' : formatIndividual(responder))
                          : (fromOther > 0 ? s.topoCheckNoReadFlag : s.topoCheckNoAnswer),
                      style: theme.textTheme.labelSmall?.copyWith(color: status.color(hz), fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ),
            if (result != null) Icon(status.icon, color: status.color(hz)),
            if (onTap != null) Icon(AppIcons.next, size: HzIconSize.inline, color: hz.textFaint),
          ],
        ),
      ),
    );
  }
}

class _Issues extends StatelessWidget {
  const _Issues({required this.topo, this.coverage, this.flat = false, this.onGroup, this.onDevice});

  final Topology topo;

  /// Filter table findings from tap points in several lines.
  final TapCoverage? coverage;

  /// Opens the address or device of the anomaly.
  final ValueChanged<int>? onGroup;
  final ValueChanged<int>? onDevice;

  /// Flat in the sidebar.
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final store = CatalogStore.instance;
    final items = <(String, VoidCallback?)>[
      for (final m in topo.mismatches)
        (
          s.topoMismatch([formatIndividual(m.source), ?store.device(m.source)?.name].join(' '), m.observed, m.expected),
          onDevice == null ? null : () => onDevice!(m.source),
        ),
      for (final MapEntry(key: ga, value: count) in topo.unneeded.entries)
        (
          s.topoUnneeded(formatGroup(ga), store.info(ga)?.name ?? '', count),
          onGroup == null ? null : () => onGroup!(ga),
        ),
      for (final f in coverage?.blocked ?? const <FilterFinding>[])
        (
          s.topoFilterBlocked(
            formatGroup(f.group),
            store.info(f.group)?.name ?? '',
            formatLine(f.from),
            formatLine(f.to),
            f.count,
          ),
          onGroup == null ? null : () => onGroup!(f.group),
        ),
      for (final f in coverage?.leaked ?? const <FilterFinding>[])
        (
          s.topoFilterLeaked(
            formatGroup(f.group),
            store.info(f.group)?.name ?? '',
            formatLine(f.from),
            formatLine(f.to),
            f.count,
          ),
          onGroup == null ? null : () => onGroup!(f.group),
        ),
    ];
    return SectionCard(
      flat: flat,
      padding: flat ? _flatPadding : null,
      title: s.topoIssues,
      count: items.length,
      child: items.isEmpty
          ? Text(s.topoNoIssues, style: theme.textTheme.bodySmall)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (text, onTap) in items)
                  InkWell(
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: HzSpace.s4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(HorizontStatus.warning.icon, size: HzIconSize.inline, color: hz.warning),
                          const SizedBox(width: HzSpace.s8),
                          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
                          if (onTap != null) Icon(AppIcons.next, size: HzIconSize.inline, color: hz.textFaint),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// History of a line: bars within the time span of the activity bar. From 600
/// with a time span to tap through, otherwise just a narrow strip.
class _LineActivity extends StatelessWidget {
  const _LineActivity({required this.line, required this.values});

  final int line;

  /// Telegramme je Abschnitt ([lineActivity]).
  final List<int> values;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final phone = MediaQuery.sizeOf(context).width < Breakpoints.medium;
    return ValueListenableBuilder(
      valueListenable: ActivityRangeSetting.instance,
      builder: (context, range, _) {
        final label = switch (range) {
          ActivityRange.seconds => s.activityLast60s,
          ActivityRange.hour => s.activityLastHour,
          ActivityRange.today => s.activityToday,
        };
        final bars = SizedBox(
          height: phone ? HzSpace.s32 : HzSpace.s48,
          child: ActivityBars(values: values, label: '${s.topoLine(formatLine(line))} · ${s.activitySemantics(label)}'),
        );
        if (phone) return bars;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tooltip(
              message: s.activityRangeHint,
              child: InkWell(
                borderRadius: Radii.row,
                onTap: ActivityRangeSetting.instance.next,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Kennung(label, color: hz.accentText)),
                    const SizedBox(width: HzSpace.s2),
                    Icon(AppIcons.cycle, size: 14, color: hz.accentText),
                  ],
                ),
              ),
            ),
            const SizedBox(height: HzSpace.s4),
            bars,
          ],
        );
      },
    );
  }
}

/// Distribution board: the devices of each line with manufacturer graphics side
/// by side, at the same scale, with LEDs and live pulse. Tapping opens the device.
class _Rails extends StatefulWidget {
  const _Rails({required this.topo, required this.log, required this.onDevice});

  final Topology topo;
  final TelegramLog log;
  final ValueChanged<int> onDevice;

  /// Pixels per millimeter of device width.
  static const _scale = 1.5;

  /// Placeholder as tall as a DIN-rail device without cables (82 mm).
  static const _placeholderHeight = 82 * _scale;

  @override
  State<_Rails> createState() => _RailsState();
}

class _RailsState extends State<_Rails> {
  /// The page appears immediately; the device graphics follow one per frame.
  final _drawQueue = _DrawQueue();

  /// Lines whose devices without graphics are expanded.
  final _expanded = <int>{};

  Topology get topo => widget.topo;
  TelegramLog get log => widget.log;
  ValueChanged<int> get onDevice => widget.onDevice;
  static const _scale = _Rails._scale;
  static const _placeholderHeight = _Rails._placeholderHeight;

  /// A device is drawn with a front graphic (actuator) or with its own form
  /// factor (push button, detector, weather station …).
  static bool _drawable(DeviceInfo d, GroupCatalog catalog) =>
      artFor(d.address) != null || shapeOf(d.address, catalog) != DeviceShape.din;

  @override
  Widget build(BuildContext context) {
    final catalog = CatalogStore.instance.catalog;
    final sections = <Widget>[];
    for (final line in topo.lines) {
      // All devices of the line in address order; those without a drawing as
      // placeholders so the line is complete.
      final devices = [...line.devices]..sort((a, b) => a.address.compareTo(b.address));
      final hidden = [
        for (final d in devices)
          if (!_drawable(d, catalog)) d,
      ];
      if (hidden.length == devices.length) continue;
      // Distribution board: DIN-rail devices with front graphics; sensors: push
      // buttons, binary inputs, detectors, weather station. Devices without a
      // drawing hang collapsed on the board (mostly gateways, couplers, power supplies).
      final rail = [
        for (final d in devices)
          if (artFor(d.address) case final art?)
            _RailDevice(
              device: d,
              art: art,
              log: log,
              scale: _scale,
              queue: _drawQueue,
              onTap: () => onDevice(d.address),
            ),
        if (_expanded.contains(line.line))
          for (final d in hidden)
            _RailPlaceholder(
              device: d,
              height: _placeholderHeight,
              heard: line.activeSources.containsKey(d.address),
              onTap: () => onDevice(d.address),
            ),
        if (hidden.isNotEmpty)
          _RailMore(
            count: hidden.length,
            open: _expanded.contains(line.line),
            height: _placeholderHeight,
            onTap: () =>
                setState(() => _expanded.contains(line.line) ? _expanded.remove(line.line) : _expanded.add(line.line)),
          ),
      ];
      final sensors = [
        for (final d in devices)
          if (artFor(d.address) == null && _drawable(d, catalog))
            _RailDrawing(
              device: d,
              log: log,
              height: _placeholderHeight,
              queue: _drawQueue,
              onTap: () => onDevice(d.address),
            ),
      ];
      // White card per group, section title instead of a label.
      Widget box(String title, List<Widget> children) => SectionCard(
        title: title,
        count: children.whereType<_RailMore>().isEmpty ? children.length : null,
        child: Wrap(
          spacing: HzSpace.s4,
          runSpacing: Gap.inner,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: children,
        ),
      );
      sections.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Gap.inner,
          children: [
            Text(s.topoLine(formatLine(line.line)), style: Theme.of(context).textTheme.titleMedium),
            if (rail.isNotEmpty) box(s.topoRailActuators, rail),
            if (sensors.isNotEmpty) box(s.topoRailSensors, sensors),
          ],
        ),
      );
    }
    if (sections.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: Gap.section, children: sections);
  }
}

/// Queue for the device graphics: one gets its turn per frame, so a large
/// distribution board does not block the page all at once.
class _DrawQueue {
  final _waiting = <_OneByOneState>[];
  bool _scheduled = false;

  void add(_OneByOneState slot) {
    _waiting.add(slot);
    _schedule();
  }

  void remove(_OneByOneState slot) => _waiting.remove(slot);

  void _schedule() {
    if (_scheduled || _waiting.isEmpty) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_waiting.isEmpty) return;
      _waiting.removeAt(0).draw();
      _schedule();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }
}

/// Shows a quiet surface until [queue] gives this graphic its turn.
class _OneByOne extends StatefulWidget {
  const _OneByOne({required this.queue, required this.builder, this.placeholderWidth});

  final _DrawQueue queue;

  /// Width of the surface if the surroundings do not set one.
  final double? placeholderWidth;
  final WidgetBuilder builder;

  @override
  State<_OneByOne> createState() => _OneByOneState();
}

class _OneByOneState extends State<_OneByOne> {
  bool _drawn = false;

  @override
  void initState() {
    super.initState();
    widget.queue.add(this);
  }

  @override
  void dispose() {
    widget.queue.remove(this);
    super.dispose();
  }

  void draw() => setState(() => _drawn = true);

  @override
  Widget build(BuildContext context) {
    if (_drawn) return widget.builder(context);
    return SizedBox(
      width: widget.placeholderWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(color: context.hz.textMuted.withValues(alpha: 0.08), borderRadius: Radii.tile),
      ),
    );
  }
}

/// A device in the distribution board: compact front graphic, the address below.
class _RailDevice extends StatelessWidget {
  const _RailDevice({
    required this.device,
    required this.art,
    required this.log,
    required this.scale,
    required this.queue,
    required this.onTap,
  });

  final DeviceInfo device;
  final DeviceArt art;
  final TelegramLog log;
  final double scale;
  final _DrawQueue queue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final width = art.size.width * scale;
    final address = formatIndividual(device.address);
    return Semantics(
      button: true,
      label: '$address ${device.name}',
      excludeSemantics: true,
      child: Tooltip(
        message: '$address · ${device.name}',
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.tile,
          child: Padding(
            padding: const EdgeInsets.all(HzSpace.s2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: width,
                  height: compactArtHeight(art, width),
                  // The LEDs flash on every telegram: repaint only the graphic,
                  // not the whole page.
                  child: RepaintBoundary(
                    child: AbsorbPointer(
                      child: _OneByOne(
                        queue: queue,
                        builder: (_) => ActuatorView(address: device.address, log: log, compact: true),
                      ),
                    ),
                  ),
                ),
                Text(address, style: context.hzTheme.data.copyWith(color: hz.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Push button, detector or weather station in the distribution board: the
/// drawing from the device sheet without the object list, scaled down to the
/// height of the DIN-rail devices, with the address below.
class _RailDrawing extends StatelessWidget {
  const _RailDrawing({
    required this.device,
    required this.log,
    required this.height,
    required this.queue,
    required this.onTap,
  });

  final DeviceInfo device;
  final TelegramLog log;
  final double height;
  final _DrawQueue queue;
  final VoidCallback onTap;

  /// Width at which the drawing is painted and then scaled down: push buttons
  /// at scale 2, the others with room for the values on the left and right.
  static double _width(DeviceShape shape) => shape == DeviceShape.pushButton ? 184 : 360;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final address = formatIndividual(device.address);
    final shape = shapeOf(device.address, CatalogStore.instance.catalog);
    return Semantics(
      button: true,
      label: '$address ${device.name}',
      excludeSemantics: true,
      child: Tooltip(
        message: '$address · ${device.name}',
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.tile,
          child: Padding(
            padding: const EdgeInsets.all(HzSpace.s2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: height,
                  child: _OneByOne(
                    queue: queue,
                    placeholderWidth: height,
                    builder: (_) => FittedBox(
                      child: SizedBox(
                        width: _width(shape),
                        child: RepaintBoundary(
                          child: AbsorbPointer(child: deviceDrawing(device.address, log, compact: true)),
                        ),
                      ),
                    ),
                  ),
                ),
                // Room like the bus cable below the DIN-rail devices.
                SizedBox(height: height * 0.22),
                Text(address, style: context.hzTheme.data.copyWith(color: hz.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Traffic between the lines and the last telegrams via the couplers, side by
/// side as soon as two card columns fit.
class _Traffic extends StatelessWidget {
  const _Traffic({required this.topo, required this.live, required this.onGroup, required this.onCoupler});

  final Topology topo;
  final _Live live;
  final ValueChanged<int> onGroup;
  final void Function(int line, int partner) onCoupler;

  @override
  Widget build(BuildContext context) {
    if (topo.lines.length < 2) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        final flows = _Flows(flows: live.flows, onCoupler: onCoupler);
        final cross = _CrossLive(rows: live.crossRows, onGroup: onGroup);
        if (box.maxWidth < 2 * Widths.column + Gap.section) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: Gap.section, children: [flows, cross]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Gap.section,
          children: [
            Expanded(child: flows),
            Expanded(child: cross),
          ],
        );
      },
    );
  }
}

/// Direction across a coupler: the line behind it, the neighbouring line,
/// traffic and history within the time span of the activity bar.
typedef _Flow = (int line, int partner, CouplerFlow flow, List<int> bins);

/// Traffic of the topology, computed once per refresh. Every pass over the log
/// is noticeably expensive in the browser (without a time window it grows all
/// day); the view, by contrast, rebuilds on every selection.
class _Live {
  _Live._(this.lineBins, this.flows, this.crossRows, this.deviceTelegrams);

  /// Sent telegrams per device.
  final Map<int, int> deviceTelegrams;

  /// Verlauf je Linie.
  final Map<int, List<int>> lineBins;

  /// Directions across the couplers, the strongest first.
  final List<_Flow> flows;

  /// The last telegrams with receivers on a different line than the sender
  /// (telegram, line of the sender, receiver lines).
  final List<(Telegram, int, List<int>)> crossRows;

  static const _crossRows = 12;

  /// [live]: history until now; for recordings until the last telegram.
  factory _Live.build(
    Topology topo,
    GroupCatalog catalog,
    List<Telegram> log,
    ActivityRange range, {
    required bool live,
  }) {
    final wall = DateTime.now();
    final last = log.lastOrNull?.time;
    final lineNow = live || last == null ? wall : last;
    final lines = topo.lines;
    final lineBins = {
      for (final l in lines) l.line: lineActivity(log, l.line, range, lineNow, origin: topo.lineOfSource),
    };
    final deviceTelegrams = <int, int>{};
    for (final t in log) {
      deviceTelegrams[t.source] = (deviceTelegrams[t.source] ?? 0) + 1;
    }
    if (lines.length < 2) return _Live._(lineBins, const [], const [], deviceTelegrams);

    // Directions: recordings until the last telegram, live until now.
    final flowNow = last != null && wall.difference(last) > const Duration(minutes: 2) ? last : wall;
    final flows = <_Flow>[
      for (var i = 1; i < lines.length; i++)
        for (final f in CouplerTraffic.build(
          catalog,
          log,
          lines[i].line,
          gatewayLine: topo.gatewayLine,
          origin: topo.lineOfSource,
        ).flows)
          (
            lines[i].line,
            lines[i - 1].line,
            f,
            // Sender in [CouplerFlow.from], address with receivers in [CouplerFlow.to].
            lineActivity(_toGroups(log, {for (final g in f.groups) g.address}), f.from, range, flowNow),
          ),
    ]..sort((a, b) => b.$3.telegrams.compareTo(a.$3.telegrams));

    // Determine receiver lines per address only once; without a hit the search
    // runs back to the beginning of the log.
    final linkLines = <int, Set<int>>{};
    final crossRows = <(Telegram, int, List<int>)>[];
    for (var i = log.length - 1; i >= 0 && crossRows.length < _crossRows; i--) {
      final t = log[i];
      final from = topo.lineOfSource(t.source);
      final receivers = linkLines.putIfAbsent(t.destination, () {
        return {for (final l in catalog[t.destination]?.links ?? const <GroupLink>[]) lineOf(l.device)};
      });
      if (receivers.every((l) => l == from)) continue;
      crossRows.add((
        t,
        from,
        [
          for (final l in receivers)
            if (l != from) l,
        ]..sort(),
      ));
    }
    return _Live._(lineBins, flows, crossRows, deviceTelegrams);
  }

  static Iterable<Telegram> _toGroups(List<Telegram> log, Set<int> groups) =>
      log.where((t) => groups.contains(t.destination));
}

/// Telegrams per direction across each coupler, with bars by share.
class _Flows extends StatelessWidget {
  const _Flows({required this.flows, required this.onCoupler});

  /// [_Live.flows].
  final List<_Flow> flows;

  /// Opens the coupler of the direction.
  final void Function(int line, int partner) onCoupler;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final data = context.hzTheme.data;
    return SectionCard(
      title: s.topoFlows,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.topoFlowsHint, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
          const SizedBox(height: Gap.item),
          if (flows.isEmpty)
            Text(s.topoFlowsNone, style: theme.textTheme.bodySmall)
          else
            for (final (i, (coupler, partner, f, bins)) in flows.indexed)
              InkWell(
                onTap: () => onCoupler(coupler, partner),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
                  decoration: BoxDecoration(
                    border: i == 0
                        ? null
                        : Border(
                            top: BorderSide(color: hz.line, width: Lines.hairline),
                          ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${formatLine(f.from)} → ${formatLine(f.to)}',
                            style: data.copyWith(fontWeight: FontWeight.w600, color: hz.text),
                          ),
                          const Spacer(),
                          Text(
                            s.topoFlowRow(formatInt(f.telegrams), f.groups.length),
                            style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted, fontFeatures: tabular),
                          ),
                        ],
                      ),
                      const SizedBox(height: HzSpace.s4),
                      // History of this direction within the time span of the line boxes.
                      SizedBox(
                        height: HzSpace.s24,
                        child: ActivityBars(values: bins, label: '${formatLine(f.from)} → ${formatLine(f.to)}'),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// The last telegrams whose receivers, according to the project, are on a
/// different line than the sender; they pass through a coupler.
class _CrossLive extends StatelessWidget {
  const _CrossLive({required this.rows, required this.onGroup});

  /// [_Live.crossRows].
  final List<(Telegram, int, List<int>)> rows;

  /// Opens the address (details, history, writing, devices).
  final ValueChanged<int> onGroup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final data = context.hzTheme.data;
    final store = CatalogStore.instance;
    return SectionCard(
      title: s.topoLive,
      child: rows.isEmpty
          ? Text(s.topoLiveNone, style: theme.textTheme.bodySmall)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, (t, from, to)) in rows.indexed)
                  InkWell(
                    onTap: () => onGroup(t.destination),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
                      decoration: BoxDecoration(
                        border: i == 0
                            ? null
                            : Border(
                                top: BorderSide(color: hz.line, width: Lines.hairline),
                              ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(text: formatGroup(t.destination), style: data),
                                      if (store.info(t.destination)?.name case final n?) TextSpan(text: '  $n'),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(color: hz.text),
                                ),
                                Text(
                                  [
                                    formatTime(t.time),
                                    '${formatLine(from)} → ${to.map(formatLine).join(', ')}',
                                  ].join(metaSeparator),
                                  style: context.figures(theme.textTheme.bodySmall).copyWith(color: hz.textFaint),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: HzSpace.s8),
                          Text(
                            t.type == TelegramType.read ? '' : store.value(t),
                            style: context.figures(theme.textTheme.bodyMedium).copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Device without a front graphic in the distribution board: address, name and
/// product on a plain tile; dot as in the device tree (filled = heard).
class _RailPlaceholder extends StatelessWidget {
  const _RailPlaceholder({required this.device, required this.height, required this.heard, required this.onTap});

  final DeviceInfo device;
  final double height;
  final bool heard;
  final VoidCallback onTap;

  /// Width: like a 4-module device at the scale of the distribution board.
  static const width = 4 * 18 * _Rails._scale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final data = context.hzTheme.data;
    final address = formatIndividual(device.address);
    // Product only if it is not already the name (ETS often copies it).
    final product = device.product == null || device.name.startsWith(device.product!) ? null : device.product;
    return Semantics(
      button: true,
      label: '$address ${device.name}',
      excludeSemantics: true,
      child: Tooltip(
        message: [address, device.name, ?product].join(' · '),
        child: Padding(
          padding: const EdgeInsets.all(HzSpace.s2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: hz.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: Radii.tile,
                  side: BorderSide(color: hz.line, width: Lines.hairline),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: Padding(
                      padding: const EdgeInsets.all(HzSpace.s8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: HzSpace.s8,
                                height: HzSpace.s8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: heard ? hz.textMuted : null,
                                  border: heard ? null : Border.all(color: hz.line, width: Lines.hairline),
                                ),
                              ),
                              const Spacer(),
                              Icon(AppIcons.project, size: HzIconSize.inline, color: hz.textFaint),
                            ],
                          ),
                          const SizedBox(height: HzSpace.s8),
                          Text(
                            device.name,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(color: hz.text),
                          ),
                          const Spacer(),
                          if (product != null)
                            Text(
                              product,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(color: hz.textMuted),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // The address below the tile, as for devices with graphics.
              SizedBox(height: height * 0.22),
              Text(address, style: data.copyWith(color: hz.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tile for expanding and collapsing the devices without a front graphic.
class _RailMore extends StatelessWidget {
  const _RailMore({required this.count, required this.open, required this.height, required this.onTap});

  final int count;
  final bool open;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return Padding(
      padding: const EdgeInsets.all(HzSpace.s2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            expanded: open,
            child: Material(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: Radii.tile,
                side: BorderSide(color: hz.line, width: Lines.hairline),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: SizedBox(
                  width: _RailPlaceholder.width,
                  height: height,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: HzSpace.s4,
                    children: [
                      Icon(open ? AppIcons.collapse : AppIcons.expand, color: hz.accentText),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: HzSpace.s8),
                        child: Text(
                          open ? s.topoRailLess : s.topoRailMore(count),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(color: hz.accentText),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Room like cable and address below the devices.
          SizedBox(height: height * 0.22 + (context.hzTheme.data.fontSize ?? 14) * 1.4),
        ],
      ),
    );
  }
}

/// Group address in the topology: which lines, devices and channels it affects,
/// who sends and who listens, with value and last telegrams.
class _GroupView extends StatelessWidget {
  const _GroupView({
    super.key,
    required this.address,
    required this.log,
    required this.onDevice,
    required this.onDetails,
    required this.onMap,
    required this.onClose,
  });

  final int address;
  final TelegramLog log;
  final ValueChanged<int> onDevice;

  /// Detail sheet with value history and writing.
  final VoidCallback onDetails;
  final VoidCallback onMap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: liveUpdates(log), builder: (context, _) => _build(context));
  }

  bool _hasDrawing(int device) => hasDeviceDrawing(device, address);

  int? _channelOf(int device) => channelAt(device, address);

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final data = context.hzTheme.data;
    final store = CatalogStore.instance;
    final info = store.info(address);
    final links = store.catalog[address]?.links ?? const <GroupLink>[];
    final history = log.forAddress(address);
    final latest = log.latest[address];
    final dpt = store.dptOf(address);
    // Devices per line, per device all objects on the address; senders first.
    final byDevice = <int, List<GroupLink>>{};
    for (final l in links) {
      (byDevice[l.device] ??= []).add(l);
    }
    final byLine = <int, List<List<GroupLink>>>{};
    for (final list in byDevice.values) {
      (byLine[lineOf(list.first.device)] ??= []).add(list);
    }
    bool sends(List<GroupLink> l) => l.any((x) => x.sends);
    for (final list in byLine.values) {
      list.sort((a, b) => sends(a) != sends(b) ? (sends(a) ? -1 : 1) : a.first.device.compareTo(b.first.device));
    }
    final lines = byLine.keys.toList()..sort();
    // Observed senders (also without a link in the project).
    final heard = <int, int>{};
    for (final t in history) {
      heard[t.source] = (heard[t.source] ?? 0) + 1;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: HorizontTitle(
                kennung: [formatGroup(address), if (dpt != null) 'DPT $dpt'].join(metaSeparator),
                title: info?.name ?? formatGroup(address),
                below: switch (info?.path) {
                  final path? => Padding(
                    padding: const EdgeInsets.only(top: HzSpace.s2),
                    child: Text(path, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
                  ),
                  null => null,
                },
              ),
            ),
            CloseDetailButton(onPressed: onClose),
          ],
        ),
        const SizedBox(height: Gap.section),
        Row(
          spacing: HzSpace.s8,
          children: [
            Expanded(
              child: FigureBox(
                figures: [
                  (s.topoGroupValue, latest == null ? '—' : store.value(latest)),
                  (s.topoTelegrams, formatInt(history.length)),
                  (s.topoDevices, formatInt({for (final l in links) l.device}.length)),
                  (s.topoGroupLines, formatInt(lines.length)),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: onDetails,
              icon: const Icon(AppIcons.history, size: 18),
              label: Text(s.topoGroupDetails),
            ),
            OutlinedButton.icon(
              onPressed: onMap,
              icon: const Icon(AppIcons.communicationMap, size: 18),
              label: Text(s.mapTitle),
            ),
          ],
        ),
        const SizedBox(height: Gap.section),
        // Per line the devices with channel and object, senders first.
        for (final line in lines) ...[
          SectionTitle(s.topoLine(formatLine(line)), count: byLine[line]!.length),
          const SizedBox(height: HzSpace.s4),
          for (final (i, l) in byLine[line]!.indexed) ...[
            _GroupLinkRow(
              address: address,
              links: l,
              first: i == 0,
              heard: heard[l.first.device],
              onTap: () => onDevice(l.first.device),
            ),
            // The device itself as in its detail view, with the channel of this
            // address highlighted; devices without channels only as a row.
            if (_hasDrawing(l.first.device))
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.section),
                child: KeyedSubtree(
                  key: ValueKey('${l.first.device}-$address'),
                  child: deviceDrawing(
                    l.first.device,
                    log,
                    selected: _channelOf(l.first.device),
                    onSelected: (_) => onDevice(l.first.device),
                  ),
                ),
              ),
          ],
          const SizedBox(height: Gap.section),
        ],
        // Senders without a link in the project (visualization, tunnel …).
        if (heard.keys.where((a) => !links.any((l) => l.device == a)).toList() case final extra
            when extra.isNotEmpty) ...[
          SectionTitle(s.topoGroupUnlinked, count: extra.length),
          const SizedBox(height: HzSpace.s4),
          for (final (i, a) in extra.indexed)
            _GroupLinkRow(
              address: address,
              links: [GroupLink(device: a, sends: true)],
              first: i == 0,
              heard: heard[a],
              onTap: () => onDevice(a),
            ),
          const SizedBox(height: Gap.section),
        ],
        SectionTitle(s.topoGroupRecent, count: history.length),
        const SizedBox(height: HzSpace.s4),
        if (history.isEmpty)
          Text(s.devNothing, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted))
        else
          for (final (i, t) in history.reversed.take(12).indexed)
            Container(
              padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(
                        top: BorderSide(color: hz.line, width: Lines.hairline),
                      ),
              ),
              child: Row(
                children: [
                  TypeBadge(type: t.type, outgoing: t.outgoing, size: 22),
                  const SizedBox(width: Gap.inner),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: formatIndividual(t.source), style: data),
                          if (store.device(t.source)?.name case final n?) TextSpan(text: '  $n'),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: hz.text),
                    ),
                  ),
                  Text(
                    formatTime(t.time),
                    style: context.figures(theme.textTheme.bodySmall).copyWith(color: hz.textFaint),
                  ),
                  const SizedBox(width: Gap.inner),
                  Text(
                    t.type == TelegramType.read ? '' : store.value(t),
                    style: context.figures(theme.textTheme.bodyMedium).copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// A device on the address: address and name, channel and object text, whether
/// it sends or listens and how often it was heard. Tapping opens the device.
class _GroupLinkRow extends StatelessWidget {
  const _GroupLinkRow({
    required this.address,
    required this.links,
    required this.first,
    required this.onTap,
    this.heard,
  });

  /// Group address of the view.
  final int address;

  /// All objects of the device on this address.
  final List<GroupLink> links;
  final bool first;
  final int? heard;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final data = context.hzTheme.data;
    final store = CatalogStore.instance;
    final link = links.first;
    final device = store.device(link.device);
    // Channels containing the objects: exactly via address and object number.
    final channels = [
      for (final c in deviceChannels(link.device))
        if (c.label.isNotEmpty && c.objects.any((o) => o.address == address && links.any((l) => l.object == o.number)))
          c.label,
    ];
    final sends = links.any((l) => l.sends);
    final detail = [
      if (channels.length == 1) '${s.topoGroupChannel} ${channels.single}',
      if (channels.length > 1) '${s.topoGroupChannels} ${channels.join(', ')}',
      // Object text only for a single object and if it says more than the channel.
      if (links.length == 1 && link.text != null && channelLabel(link.text) == null) link.text!,
      if (heard case final n?) '$n× ${s.topoGroupHeard}',
    ].join(metaSeparator);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
        decoration: BoxDecoration(
          border: first
              ? null
              : Border(
                  top: BorderSide(color: hz.line, width: Lines.hairline),
                ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(formatIndividual(link.device), style: data.copyWith(color: hz.text)),
                      const SizedBox(width: HzSpace.s8),
                      Expanded(
                        child: Text(
                          device?.name ?? unknownDeviceName(link.device),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: hz.text),
                        ),
                      ),
                    ],
                  ),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: HzSpace.s8),
            // Role as a word, not only as color.
            HorizontBadge(
              sends ? HorizontStatus.positive : HorizontStatus.info,
              label: sends ? s.topoGroupSends : s.topoGroupListens,
            ),
            Icon(AppIcons.next, size: HzIconSize.inline, color: hz.textFaint),
          ],
        ),
      ),
    );
  }
}
