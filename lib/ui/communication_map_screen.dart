import 'device_graph.dart';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/communication_map.dart';
import '../model/telegram_log.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../theme/palette.dart';
import 'common.dart';

/// Who talks to whom, as an explorer around a node in the center.
class CommunicationMapScreen extends StatefulWidget {
  const CommunicationMapScreen({super.key, required this.log, this.start, this.onOpenAddress, this.onOpenDevice});

  final TelegramLog log;
  final MapNode? start;

  /// Tapping the center card: details of the group address or device sheet.
  final ValueChanged<int>? onOpenAddress;
  final ValueChanged<int>? onOpenDevice;

  @override
  State<CommunicationMapScreen> createState() => _CommunicationMapScreenState();
}

class _CommunicationMapScreenState extends State<CommunicationMapScreen> {
  bool _showAll = false;

  /// Selected overview mode; kept when coming back from the explorer.
  final _graphView = ValueNotifier(true);
  late final _map = CommunicationMap.of(widget.log);
  // Without a start node the map begins with the overview of all addresses and
  // devices.
  late final List<MapNode> _trail = [?widget.start];

  MapNode? get _focus => _trail.isEmpty ? null : _trail.last;

  /// Way out of the map: the center opens its details (if wired up).
  VoidCallback? _openFocus(MapNode focus) {
    final open = focus.isGroup ? widget.onOpenAddress : widget.onOpenDevice;
    return open == null ? null : () => open(focus.address);
  }

  void _go(MapNode node) => setState(() {
    final i = _trail.indexOf(node);
    if (i >= 0) {
      _trail.removeRange(i + 1, _trail.length);
    } else {
      _trail.add(node);
    }
  });

  /// Coming from the overview, "Zurück" (back) first returns to the overview.
  bool get _fromOverview => widget.start == null;

  @override
  Widget build(BuildContext context) {
    final gutter = Gap.gutterFor(MediaQuery.sizeOf(context).width);
    return PopScope(
      canPop: !_fromOverview || _trail.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_trail.clear);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(s.mapTitle)),
        body: LayoutBuilder(
          builder: (context, box) {
            final focus = _focus;
            // From a device or object: the map initially shows only its
            // relations.
            if (widget.start case final start?
                when !_showAll && _trail.length <= 1 && box.maxWidth >= Breakpoints.medium) {
              return _GraphHome(
                key: ValueKey(start),
                map: _map,
                onPick: (node) => node == start ? _openFocus(start)?.call() : _go(node),
                focus: start,
                onShowAll: () => setState(() {
                  _showAll = true;
                  _trail.clear();
                }),
              );
            }
            return focus == null
                ? box.maxWidth >= Breakpoints.medium
                      ? _GraphHome(key: const ValueKey('alle'), map: _map, onPick: _go, graph: _graphView)
                      : _Overview(map: _map, onPick: _go)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(gutter, HzSpace.s4, gutter, Gap.item),
                        child: _NodeSearch(onPick: _go, suggestions: _map.busiestGroups(8)),
                      ),
                      // History for jumping back.
                      if (_fromOverview || _trail.length > 1)
                        SizedBox(
                          height: HzSpace.s48,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.symmetric(horizontal: gutter),
                            children: [
                              if (_fromOverview)
                                TextButton.icon(
                                  onPressed: () => setState(_trail.clear),
                                  icon: Icon(AppIcons.overview, size: HzIconSize.inline, color: context.hz.accentText),
                                  label: Text(s.mapOverview),
                                ),
                              // The path only from two nodes on: one is already
                              // in the map.
                              if (_trail.length > 1)
                                for (final (i, node) in _trail.indexed) ...[
                                  if (i > 0) Icon(AppIcons.next, size: HzIconSize.inline, color: context.hz.textMuted),
                                  Center(
                                    child: ActionChip(
                                      visualDensity: VisualDensity.compact,
                                      label: _NodeTitle(node, maxLines: 1),
                                      onPressed: () => _go(node),
                                    ),
                                  ),
                                ],
                            ],
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(gutter, HzSpace.s4, gutter, Gap.item),
                        child: Text(
                          s.mapHint,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.hz.textMuted),
                        ),
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, c) => c.maxWidth >= Breakpoints.medium
                              ? _WideMap(map: _map, focus: focus, onTap: _go, onOpen: _openFocus(focus))
                              : _NarrowMap(map: _map, focus: focus, onTap: _go, onOpen: _openFocus(focus)),
                        ),
                      ),
                    ],
                  );
          },
        ),
      ),
    );
  }
}

/// Entry from 600 on: devices as a map or all addresses as a list.
class _GraphHome extends StatefulWidget {
  const _GraphHome({super.key, required this.map, required this.onPick, this.focus, this.onShowAll, this.graph});

  /// Remembers the view across the explorer.
  final ValueNotifier<bool>? graph;

  final CommunicationMap map;
  final ValueChanged<MapNode> onPick;

  /// Restricts the map to this node and its relations.
  final MapNode? focus;
  final VoidCallback? onShowAll;

  @override
  State<_GraphHome> createState() => _GraphHomeState();
}

class _GraphHomeState extends State<_GraphHome> {
  final _query = TextEditingController();
  late bool _graph = widget.graph?.value ?? true;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.gutter, HzSpace.s4, Gap.gutter, Gap.inner),
          child: Row(
            spacing: Gap.item,
            children: [
              if (_graph)
                Expanded(
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
                )
              else
                const Spacer(),
              if (widget.onShowAll case final showAll?)
                TextButton(onPressed: showAll, child: Text(s.mapGraphAll))
              else
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: true,
                      label: Text('${s.mapDevices} · ${formatInt(widget.map.nodes(groups: false).length)}'),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('${s.mapGroups} · ${formatInt(widget.map.nodes(groups: true).length)}'),
                    ),
                  ],
                  selected: {_graph},
                  onSelectionChanged: (v) => setState(() {
                    _graph = v.first;
                    widget.graph?.value = v.first;
                  }),
                ),
            ],
          ),
        ),
        Expanded(
          child: _graph
              ? DeviceGraph(map: widget.map, query: _query.text, onOpen: widget.onPick, focus: widget.focus)
              : _Overview(map: widget.map, onPick: widget.onPick),
        ),
      ],
    );
  }
}

/// Entry: all group addresses and devices (project + observed), most active
/// first, searchable. Tapping opens the map around that node.
class _Overview extends StatefulWidget {
  const _Overview({required this.map, required this.onPick});

  final CommunicationMap map;
  final ValueChanged<MapNode> onPick;

  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  final _query = TextEditingController();
  bool _devices = false;
  late final _groups = widget.map.nodes(groups: true);
  late final _allDevices = widget.map.nodes(groups: false);

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<MapNode> _filter(List<MapNode> nodes) {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return nodes;
    return [
      for (final n in nodes)
        if ('${_nodeTitle(n)} ${_nodeSubtitle(n) ?? ''}'.toLowerCase().contains(q)) n,
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_groups.isEmpty && _allDevices.isEmpty) {
      return HorizontEmptyHint(icon: AppIcons.communicationMap, text: s.mapEmpty);
    }
    final groups = _filter(_groups);
    final devices = _filter(_allDevices);
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= Breakpoints.expanded;
        final search = TextField(
          style: context.hzTheme.field,
          controller: _query,
          autocorrect: false,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            isDense: true,
            // Filled field without label: omit the label space on top,
            // otherwise the text sits too low.
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            prefixIcon: const Icon(AppIcons.search),
            hintText: s.mapSearch,
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(Gap.gutter, HzSpace.s4, Gap.gutter, Gap.item), child: search),
            if (!wide)
              Padding(
                padding: EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, Gap.item),
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: false, label: Text('${s.mapGroups} · ${formatInt(groups.length)}')),
                    ButtonSegment(value: true, label: Text('${s.mapDevices} · ${formatInt(devices.length)}')),
                  ],
                  selected: {_devices},
                  onSelectionChanged: (v) => setState(() => _devices = v.first),
                ),
              ),
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _list(s.mapGroups, groups, right: Gap.section / 2)),
                        Expanded(child: _list(s.mapDevices, devices, left: Gap.section / 2)),
                      ],
                    )
                  : _list(null, _devices ? devices : groups),
            ),
          ],
        );
      },
    );
  }

  /// Quiet list: rows separated by hairlines and with an arrow to make clear
  /// that tapping opens the map.
  Widget _list(String? title, List<MapNode> nodes, {double left = Gap.gutter, double right = Gap.gutter}) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return Padding(
      padding: EdgeInsets.fromLTRB(left, 0, right, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(top: HzSpace.s4, bottom: Gap.item),
              child: SectionTitle(title, count: nodes.length),
            ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: Gap.bottom),
              itemCount: nodes.length,
              separatorBuilder: (_, _) => const Divider(height: Lines.hairline),
              itemBuilder: (context, i) {
                final node = nodes[i];
                final traffic = widget.map.traffic(node);
                final subtitle = _nodeSubtitle(node);
                return InkWell(
                  onTap: () => widget.onPick(node),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: HzSpace.s12),
                    child: Row(
                      spacing: HzSpace.s8,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _NodeTitle(node, style: theme.textTheme.bodyLarge),
                              if (subtitle != null && subtitle.isNotEmpty)
                                Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          traffic > 0 ? '${formatInt(traffic)}×' : '—',
                          style: context
                              .figures(theme.textTheme.bodyMedium)
                              .copyWith(fontWeight: FontWeight.w700, color: traffic > 0 ? hz.text : hz.textMuted),
                        ),
                        Icon(AppIcons.next, size: HzIconSize.inline, color: hz.textMuted),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _nodeTitle(MapNode node) {
  final store = CatalogStore.instance;
  return node.isGroup
      ? '${formatGroup(node.address)}  ${store.info(node.address)?.name ?? ''}'.trim()
      : '${formatIndividual(node.address)}  ${store.device(node.address)?.name ?? ''}'.trim();
}

/// Title of a node: address in Monaspace, name in the UI font.
class _NodeTitle extends StatelessWidget {
  const _NodeTitle(this.node, {this.style, this.maxLines = 2});

  final MapNode node;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final data = context.hzTheme.data;
    final store = CatalogStore.instance;
    final address = node.isGroup ? formatGroup(node.address) : formatIndividual(node.address);
    final name = node.isGroup ? store.info(node.address)?.name : store.device(node.address)?.name;
    return Text.rich(
      TextSpan(
        children: [
          // Only family and figures from `data`, size from the surrounding
          // style.
          TextSpan(
            text: address,
            style: TextStyle(fontFamily: data.fontFamily, fontFeatures: data.fontFeatures, color: context.hz.textMuted),
          ),
          if (name != null && name.isNotEmpty) TextSpan(text: '  $name'),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

String? _nodeSubtitle(MapNode node) {
  final store = CatalogStore.instance;
  if (node.isGroup) return store.info(node.address)?.path;
  final d = store.device(node.address);
  return d == null ? null : [if (d.product != d.name) ?d.product, ?d.location].join(' · ');
}

String _edgeText(MapNeighbor n, {required bool projectKnown}) => n.observed > 0
    ? [s.mapObserved(n.observed), if (projectKnown && !n.inProject) s.mapNotInProject].join(' · ')
    : s.mapProjectOnly;

// --- iPad portrait and up: boxes with connecting lines, fills the height ---

class _WideMap extends StatelessWidget {
  const _WideMap({required this.map, required this.focus, required this.onTap, this.onOpen});

  final CommunicationMap map;
  final MapNode focus;
  final ValueChanged<MapNode> onTap;
  final VoidCallback? onOpen;

  // Room for two-line titles and subtitles; grows with the text size.
  static const _card = 88.0;
  static const _rowGap = HzSpace.s8;
  static const _centerCard = 120.0;

  /// Padding of the white surface.
  static const _inset = HzSpace.s16;

  /// Height of the section title above each column.
  static const _header = HzSpace.s32;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final inputs = map.inputs(focus);
    final outputs = map.outputs(focus);
    final projectKnown = CatalogStore.instance.catalog.groups.values.any((g) => g.links.isNotEmpty);
    final scale = MediaQuery.textScalerOf(context);
    final card = scale.scale(_card);
    final centerCard = scale.scale(_centerCard);
    final center = map.traffic(focus);

    return LayoutBuilder(
      builder: (context, c) {
        final inner = c.maxWidth - Gap.page.horizontal - 2 * _inset;
        // Gap between the columns (where the lines run): tighter when narrow.
        final gap = c.maxWidth >= Breakpoints.expanded ? HzSpace.s64 : HzSpace.s32;
        final colWidth = (inner - 2 * gap) / 3;
        // If all boxes fit, each column spreads them over the full height;
        // otherwise the map gets taller than the window and scrolls.
        final free = c.maxHeight - Gap.page.vertical - 2 * _inset;
        final rows = [inputs.length, outputs.length, 2].reduce((a, b) => a > b ? a : b);
        final height = [free, rows * (card + _rowGap) + _header].reduce((a, b) => a > b ? a : b);
        // The center stays on the first screen even if the columns are longer.
        final middle = (free > 0 ? free : height) / 2;
        double rowOf(List<MapNeighbor> items) => (height - _header) / (items.isEmpty ? 1 : items.length);
        return SingleChildScrollView(
          padding: Gap.page,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: hz.surface,
              borderRadius: Radii.card,
              border: Border.all(color: hz.line, width: Lines.hairline),
            ),
            child: Padding(
              padding: const EdgeInsets.all(_inset),
              child: SizedBox(
                height: height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _EdgePainter(
                          left: inputs,
                          right: outputs,
                          colWidth: colWidth,
                          gap: gap,
                          leftRow: rowOf(inputs),
                          rightRow: rowOf(outputs),
                          top: _header,
                          centerY: middle,
                          colors: hz,
                          projectKnown: projectKnown,
                        ),
                      ),
                    ),
                    _column(
                      context,
                      left: 0,
                      width: colWidth,
                      title: focus.isGroup ? s.mapSenders : s.mapListens,
                      items: inputs,
                      projectKnown: projectKnown,
                      row: rowOf(inputs),
                      card: card,
                    ),
                    Positioned(
                      left: colWidth + gap,
                      top: middle - centerCard / 2,
                      width: colWidth,
                      height: centerCard,
                      child: _NodeCard(
                        node: focus,
                        center: true,
                        edge: center > 0 ? s.mapObserved(center) : null,
                        onTap: onOpen,
                      ),
                    ),
                    _column(
                      context,
                      left: colWidth * 2 + 2 * gap,
                      width: colWidth,
                      title: focus.isGroup ? s.mapReceivers : s.mapSends,
                      items: outputs,
                      projectKnown: projectKnown,
                      row: rowOf(outputs),
                      card: card,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _column(
    BuildContext context, {
    required double left,
    required double width,
    required String title,
    required List<MapNeighbor> items,
    required bool projectKnown,
    required double row,
    required double card,
  }) {
    return Positioned(
      left: left,
      top: 0,
      width: width,
      bottom: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _header,
            child: Align(alignment: AlignmentDirectional.topStart, child: SectionTitle(title, maxLines: 1)),
          ),
          if (items.isEmpty) Text(s.mapNone),
          for (final n in items)
            SizedBox(
              height: row,
              child: Center(
                child: SizedBox(
                  height: card,
                  child: _NodeCard(
                    node: n.node,
                    edge: _edgeText(n, projectKnown: projectKnown),
                    onTap: () => onTap(n.node),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Draws lines from the columns to the center: neutral, thicker for more
/// traffic, the strongest in the accent; dashed if only from the project;
/// observed but not in the project in warning color (the word is shown in the
/// box).
class _EdgePainter extends CustomPainter {
  _EdgePainter({
    required this.left,
    required this.right,
    required this.colWidth,
    required this.gap,
    required this.leftRow,
    required this.rightRow,
    required this.top,
    required this.centerY,
    required this.colors,
    required this.projectKnown,
  });

  final List<MapNeighbor> left;
  final List<MapNeighbor> right;
  final double colWidth;
  final double gap;

  /// Height of a row per column; the line hits its center.
  final double leftRow;
  final double rightRow;

  /// Top edge of the first row (below the section title).
  final double top;
  final double centerY;
  final HorizontColors colors;
  final bool projectKnown;

  @override
  void paint(Canvas canvas, Size size) {
    final maxObserved = [...left, ...right].fold(0, (m, n) => n.observed > m ? n.observed : m);
    void edge(Offset a, Offset b, MapNeighbor n) {
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo((a.dx + b.dx) / 2, a.dy, (a.dx + b.dx) / 2, b.dy, b.dx, b.dy);
      final foreign = projectKnown && !n.inProject;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = n.observed > 0 ? Lines.hairline + Lines.selection * n.observed / maxObserved : Lines.hairline
        ..color = n.observed == 0
            ? colors.lineStrong
            : (foreign ? colors.warning : (n.observed == maxObserved ? colors.accent : colors.textFaint));
      if (n.observed > 0) {
        canvas.drawPath(path, paint);
      } else {
        for (final metric in path.computeMetrics()) {
          for (var d = 0.0; d < metric.length; d += HzSpace.s8) {
            canvas.drawPath(metric.extractPath(d, d + HzSpace.s4), paint);
          }
        }
      }
    }

    for (final (i, n) in left.indexed) {
      edge(Offset(colWidth, top + (i + 0.5) * leftRow), Offset(colWidth + gap, centerY), n);
    }
    for (final (i, n) in right.indexed) {
      edge(Offset(colWidth * 2 + gap, centerY), Offset(colWidth * 2 + gap * 2, top + (i + 0.5) * rightRow), n);
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) => true;
}

// --- Schmal: Listen untereinander ------------------------------------------------

class _NarrowMap extends StatelessWidget {
  const _NarrowMap({required this.map, required this.focus, required this.onTap, this.onOpen});

  final CommunicationMap map;
  final MapNode focus;
  final ValueChanged<MapNode> onTap;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final projectKnown = CatalogStore.instance.catalog.groups.values.any((g) => g.links.isNotEmpty);
    Widget list(String title, List<MapNeighbor> items) => Padding(
      padding: const EdgeInsets.only(top: Gap.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(title, count: items.length),
          const SizedBox(height: Gap.item),
          if (items.isEmpty) Text(s.mapNone),
          for (final n in items)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.item),
              child: _NodeCard(
                node: n.node,
                edge: _edgeText(n, projectKnown: projectKnown),
                onTap: () => onTap(n.node),
              ),
            ),
        ],
      ),
    );
    return ListView(
      padding: Gap.page,
      children: [
        list(focus.isGroup ? s.mapSenders : s.mapListens, map.inputs(focus)),
        const SizedBox(height: Gap.section),
        _NodeCard(node: focus, center: true, onTap: onOpen),
        list(focus.isGroup ? s.mapReceivers : s.mapSends, map.outputs(focus)),
      ],
    );
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({required this.node, this.edge, this.onTap, this.center = false});

  final MapNode node;
  final String? edge;
  final VoidCallback? onTap;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final subtitle = [?_nodeSubtitle(node), ?edge].join(' · ');
    // Box with hairline; the node in focus carries the selection: 2 px line in
    // the accent on an accent tint.
    return Material(
      color: center ? hz.accentTint : hz.surface,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.card,
        side: BorderSide(color: center ? hz.accent : hz.line, width: center ? Lines.selection : Lines.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.inner, vertical: HzSpace.s8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _NodeTitle(node, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                      ),
                  ],
                ),
              ),
              // The center leads out of the map (details, device sheet).
              if (center && onTap != null) Icon(AppIcons.next, color: hz.accentText),
            ],
          ),
        ),
      ),
    );
  }
}

/// Search by group address or device (name or address).
class _NodeSearch extends StatelessWidget {
  const _NodeSearch({required this.onPick, this.suggestions = const []});

  final ValueChanged<MapNode> onPick;

  /// Suggestions for an empty field (most active addresses).
  final List<MapNode> suggestions;

  @override
  Widget build(BuildContext context) {
    final store = CatalogStore.instance;
    return Autocomplete<MapNode>(
      displayStringForOption: _nodeTitle,
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return suggestions;
        if (q.length < 2) return const [];
        return [
          for (final g in store.catalog.groups.values)
            if (g.name.toLowerCase().contains(q) || formatGroup(g.address).startsWith(q)) MapNode.group(g.address),
          for (final d in store.catalog.devices.values)
            if (d.name.toLowerCase().contains(q) || formatIndividual(d.address).startsWith(q))
              MapNode.device(d.address),
          if (parseGroup(q) case final ga?) MapNode.group(ga),
          if (parseIndividual(q) case final pa?) MapNode.device(pa),
        ].take(30);
      },
      onSelected: (node) {
        FocusManager.instance.primaryFocus?.unfocus();
        onPick(node);
      },
      // The result list stays above the keyboard and as wide as the field.
      optionsViewBuilder: (context, onSelected, options) {
        final theme = Theme.of(context);
        final view = MediaQuery.of(context);
        final available = view.size.height - view.viewInsets.bottom - 200;
        return Align(
          alignment: Alignment.topLeft,
          // Line instead of shadow.
          child: Material(
            color: context.hz.surface,
            shape: RoundedRectangleBorder(
              borderRadius: Radii.tile,
              side: BorderSide(color: context.hz.line, width: Lines.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: available.clamp(120, 420), maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: HzSpace.s4),
                shrinkWrap: true,
                children: [
                  for (final node in options)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        node.isGroup ? AppIcons.overview : AppIcons.sensors,
                        size: HzIconSize.inline,
                        color: context.hz.textMuted,
                      ),
                      title: _NodeTitle(node),
                      subtitle: _nodeSubtitle(node) == null
                          ? null
                          : Text(
                              _nodeSubtitle(node)!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                      onTap: () => onSelected(node),
                    ),
                ],
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
        style: context.hzTheme.field,
        controller: controller,
        focusNode: focus,
        autocorrect: false,
        decoration: InputDecoration(
          isDense: true,
          // Filled field without label: omit the label space on top, otherwise
          // the text sits too low.
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          prefixIcon: const Icon(AppIcons.search),
          hintText: s.mapSearch,
        ),
      ),
    );
  }
}
