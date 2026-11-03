import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/communication_map.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// Devices as boxes with lines between them. Zoomed far out a box shows only
/// address and name; zooming in adds product and numbers.
class DeviceGraph extends StatefulWidget {
  const DeviceGraph({super.key, required this.map, required this.onOpen, this.query = '', this.focus});

  /// Only this node and its relations (coming from a device or object).
  final MapNode? focus;

  final CommunicationMap map;

  /// Search text: matches stay bold, the rest recedes.
  final String query;

  /// Opens the device in the explorer.
  final ValueChanged<MapNode> onOpen;

  @override
  State<DeviceGraph> createState() => _DeviceGraphState();
}

/// Level of detail of a box, by zoom.
enum _Detail { low, medium, high }

class _DeviceGraphState extends State<DeviceGraph> {
  static const _box = Size(190, 92);
  static const _gap = Size(56, 20);

  final _transform = TransformationController();
  final _detail = ValueNotifier(_Detail.low);

  /// Hides devices without connections (otherwise a column at the right edge).
  bool _hideUnlinked = false;

  /// If the node has no relations, the map would be just a single box: then
  /// show all devices and highlight it among them.
  late final _focusScope = widget.focus == null ? null : widget.map.scopeOf(widget.focus!);
  late final _scope = (_focusScope?.length ?? 0) < 2 ? null : _focusScope;
  late final _nodes = () {
    final all = widget.map.nodes(groups: false);
    final scope = _scope;
    if (scope == null) return all;
    final center = widget.focus!;
    return [
      if (!center.isGroup) center,
      for (final n in all)
        if (scope.contains(n.address) && n != center) n,
    ];
  }();
  late final _links = () {
    final scope = _scope;
    final all = widget.map.deviceLinks();
    if (scope == null) return all;
    final center = widget.focus!;
    return [
      for (final l in all)
        if (center.isGroup ? l.groups.contains(center.address) : l.a == center.address || l.b == center.address) l,
    ];
  }();
  Map<int, Offset> _positions = const {};
  Size _canvas = Size.zero;
  Size? _fittedTo;
  late int? _selected = widget.focus?.isGroup == false
      ? widget.focus!.address
      : (_focusScope?.length == 1 ? _focusScope!.first : null);

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onZoom);
  }

  @override
  void dispose() {
    _transform.dispose();
    _detail.dispose();
    super.dispose();
  }

  void _onZoom() {
    final scale = _transform.value.getMaxScaleOnAxis();
    _detail.value = scale < 0.85
        ? _Detail.low
        : scale < 1.4
        ? _Detail.medium
        : _Detail.high;
  }

  /// Arranged in three areas from left to right: devices that only send (push
  /// buttons, sensors), those that do both, and those that mainly listen
  /// (actuators). Each area is ordered by address; the column count follows the
  /// aspect ratio of the space.
  void _layout(Size view) {
    final layers = <List<MapNode>>[[], [], [], []];
    final linked = {
      for (final l in _links) ...[l.a, l.b],
    };
    final shown = [
      for (final n in _nodes)
        if (!_hideUnlinked || linked.contains(n.address) || n.address == _selected) n,
    ];
    for (final n in shown) {
      if (!linked.contains(n.address)) {
        layers[3].add(n);
        continue;
      }
      final sends = widget.map.outputs(n).length;
      final hears = widget.map.inputs(n).length;
      layers[hears == 0 ? 0 : (hears > sends ? 2 : 1)].add(n);
    }
    for (final l in layers) {
      l.sort((a, b) => a.address.compareTo(b.address));
    }
    final cell = Size(_box.width + _gap.width, _box.height + _gap.height);
    final ratio = view.width / view.height * cell.height / cell.width;
    final total = math.max(1, (math.sqrt(shown.length * ratio)).round());
    final used = layers.where((l) => l.isNotEmpty).length;
    final rows = math.max(1, (shown.length / math.max(total, used)).ceil());
    final out = <int, Offset>{};
    var x = 0.0;
    for (final l in layers) {
      if (l.isEmpty) continue;
      final columns = (l.length / rows).ceil();
      for (final (i, n) in l.indexed) {
        final inColumn = i ~/ rows;
        final count = inColumn < columns - 1 ? rows : l.length - rows * (columns - 1);
        // Columns centered so short areas do not stick to the top.
        final top = (rows - count) * cell.height / 2;
        out[n.address] = Offset(x + inColumn * cell.width, top + (i % rows) * cell.height);
      }
      x += columns * cell.width + _gap.width;
    }
    _positions = out;
    _canvas = Size(x - _gap.width * 2, rows * cell.height - _gap.height);
  }

  /// Fit everything once per size.
  void _fit(Size view) {
    if (_fittedTo == view || view.isEmpty) return;
    _fittedTo = view;
    _layout(view);
    final scale = math.min(view.width / _canvas.width, view.height / _canvas.height);
    _transform.value = Matrix4.identity()
      ..translateByDouble((view.width - _canvas.width * scale) / 2, (view.height - _canvas.height * scale) / 2, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
    _onZoom();
  }

  bool _matches(MapNode n) {
    final q = widget.query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final d = CatalogStore.instance.device(n.address);
    return '${formatIndividual(n.address)} ${d?.name ?? ''} ${d?.product ?? ''}'.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    if (_nodes.isEmpty) return HorizontEmptyHint(icon: AppIcons.communicationMap, text: s.mapEmpty);
    final selected = _selected;
    final related = selected == null
        ? const <DeviceLink>[]
        : (_links.where((l) => l.a == selected || l.b == selected).toList()
            ..sort((x, y) => y.observed.compareTo(x.observed)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.gutter),
            child: Material(
              color: hz.surface,
              shape: RoundedRectangleBorder(
                borderRadius: Radii.card,
                side: BorderSide(color: hz.line, width: Lines.hairline),
              ),
              clipBehavior: Clip.antiAlias,
              child: LayoutBuilder(
                builder: (context, c) {
                  _fit(c.biggest);
                  if (_canvas.isEmpty) return const SizedBox.shrink();
                  final fit = math.min(c.maxWidth / _canvas.width, c.maxHeight / _canvas.height);
                  return InteractiveViewer(
                    transformationController: _transform,
                    constrained: false,
                    minScale: math.min(fit, 1) * 0.8,
                    maxScale: 2.5,
                    boundaryMargin: const EdgeInsets.all(600),
                    child: SizedBox.fromSize(
                      size: _canvas,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _LinkPainter(
                                links: _links,
                                positions: _positions,
                                box: _box,
                                selected: selected,
                                line: hz.lineStrong,
                                accent: hz.accent,
                              ),
                            ),
                          ),
                          for (final n in _nodes)
                            if (_positions.containsKey(n.address))
                              Positioned(
                                left: _positions[n.address]!.dx,
                                top: _positions[n.address]!.dy,
                                width: _box.width,
                                height: _box.height,
                                child: Opacity(
                                  opacity: _matches(n) ? 1 : 0.25,
                                  child: ValueListenableBuilder(
                                    valueListenable: _detail,
                                    builder: (context, detail, _) => _DeviceBox(
                                      node: n,
                                      detail: detail,
                                      selected: n.address == selected,
                                      linked:
                                          selected != null && related.any((l) => l.a == n.address || l.b == n.address),
                                      telegrams: widget.map.traffic(n),
                                      addresses: widget.map.outputs(n).length + widget.map.inputs(n).length,
                                      onTap: () => setState(() => _selected = n.address == selected ? null : n.address),
                                    ),
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.gutter, Gap.inner, Gap.gutter, Gap.gutter),
          child: SizedBox(
            // Without a selection, just the single hint line.
            height: selected == null ? null : 132,
            child: selected == null
                ? Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.mapGraphHint,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: hz.textMuted),
                        ),
                      ),
                      Text(s.mapGraphUnlinked, style: Theme.of(context).textTheme.bodySmall),
                      Switch.adaptive(
                        value: !_hideUnlinked,
                        onChanged: (show) => setState(() {
                          _hideUnlinked = !show;
                          _fittedTo = null;
                        }),
                      ),
                    ],
                  )
                : _Selection(device: selected, links: related, onOpen: () => widget.onOpen(MapNode.device(selected))),
          ),
        ),
      ],
    );
  }
}

String _deviceName(int address) {
  final d = CatalogStore.instance.device(address);
  return d?.name ?? formatIndividual(address);
}

class _DeviceBox extends StatelessWidget {
  const _DeviceBox({
    required this.node,
    required this.detail,
    required this.selected,
    required this.linked,
    required this.telegrams,
    required this.addresses,
    required this.onTap,
  });

  final MapNode node;
  final _Detail detail;
  final bool selected;

  /// At the other end of a line of the selected device.
  final bool linked;
  final int telegrams;
  final int addresses;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final device = CatalogStore.instance.device(node.address);
    final address = formatIndividual(node.address);
    final name = device?.name ?? address;
    return Semantics(
      button: true,
      selected: selected,
      label: '$address $name',
      excludeSemantics: true,
      child: Material(
        color: selected ? hz.accentTint : hz.surface,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.card,
          side: BorderSide(
            color: selected
                ? hz.accent
                : linked
                ? hz.accent.withValues(alpha: 0.6)
                : hz.line,
            width: selected || linked ? Lines.selection : Lines.hairline,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: HzSpace.s12, vertical: HzSpace.s8),
            child: switch (detail) {
              // Zoomed out: address and full name, large enough to read.
              _Detail.low => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    address,
                    maxLines: 1,
                    style: context.mono(theme.textTheme.bodyMedium).copyWith(fontSize: 17, color: hz.textMuted),
                  ),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 17,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              _ => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    address,
                    maxLines: 1,
                    style: context.mono(theme.textTheme.labelSmall).copyWith(color: hz.textMuted),
                  ),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    detail == _Detail.high
                        ? [?device?.product, '${s.mapGroups} $addresses'].join(metaSeparator)
                        : device?.product ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: hz.textFaint),
                  ),
                  if (detail == _Detail.high)
                    Text(
                      '${formatInt(telegrams)}×',
                      style: context.figures(theme.textTheme.labelSmall).copyWith(fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            },
          ),
        ),
      ),
    );
  }
}

/// Below the map: connections of the selected device.
class _Selection extends StatelessWidget {
  const _Selection({required this.device, required this.links, required this.onOpen});

  final int device;
  final List<DeviceLink> links;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: SectionTitle(s.mapGraphSelected, count: links.length, maxLines: 1)),
            TextButton(
              onPressed: onOpen,
              child: Text(_deviceName(device), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (final l in links)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: HzSpace.s4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_deviceName(device)} → ${_deviceName(l.a == device ? l.b : l.a)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                            Text(
                              l.groups.take(5).map(formatGroup).join(metaSeparator),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.mono(theme.textTheme.labelSmall).copyWith(color: hz.textFaint),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${formatInt(l.observed)}×',
                        style: context.figures(theme.textTheme.bodyMedium).copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LinkPainter extends CustomPainter {
  _LinkPainter({
    required this.links,
    required this.positions,
    required this.box,
    required this.selected,
    required this.line,
    required this.accent,
  });

  final List<DeviceLink> links;
  final Map<int, Offset> positions;
  final Size box;
  final int? selected;
  final Color line;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    for (final active in [false, true]) {
      for (final l in links) {
        final on = selected != null && (l.a == selected || l.b == selected);
        if (on != active) continue;
        final a = positions[l.a];
        final b = positions[l.b];
        if (a == null || b == null) continue;
        // Edge to edge, gently curved; sideways within the same column.
        final (left, right) = a.dx <= b.dx ? (a, b) : (b, a);
        final from = left + Offset(box.width, box.height / 2);
        final to = left.dx == right.dx ? right + Offset(box.width, box.height / 2) : right + Offset(0, box.height / 2);
        final bend = left.dx == right.dx ? 40.0 : (to.dx - from.dx) / 2;
        canvas.drawPath(
          Path()
            ..moveTo(from.dx, from.dy)
            ..cubicTo(from.dx + bend, from.dy, to.dx - (left.dx == right.dx ? -bend : bend), to.dy, to.dx, to.dy),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = on ? accent : line.withValues(alpha: selected == null ? 0.55 : 0.2)
            ..strokeWidth = (on ? 2.5 : 1) + math.min(3, math.log(1 + l.observed) / 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LinkPainter old) =>
      old.positions != positions || old.selected != selected || old.line != line || old.accent != accent;
}
