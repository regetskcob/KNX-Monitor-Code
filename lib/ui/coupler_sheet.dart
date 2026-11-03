import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/telegram_log.dart';
import '../model/topology.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'live_updates.dart';
import 'statistics_screen.dart' show FigureBox;
import 'telegram_row.dart';

/// Traffic of a coupler in a sheet (phone, narrow windows).
Future<void> showCouplerSheet(
  BuildContext context, {
  required int line,
  required TelegramLog log,
  int? gatewayLine,
  int? partner,
  ValueChanged<String>? onFilter,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: Widths.reading),
  builder: (sheet) => SafeArea(
    top: false,
    child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) => CouplerTrafficView(
        line: line,
        log: log,
        gatewayLine: gatewayLine,
        partner: partner,
        scrollController: scroll,
        onFilter: onFilter == null
            ? null
            : (q) {
                Navigator.pop(sheet);
                onFilter(q);
              },
      ),
    ),
  ),
);

/// Coupler of a line: telegrams per direction, flow as arrows, and the group
/// addresses passing through the coupler.
class CouplerTrafficView extends StatefulWidget {
  const CouplerTrafficView({
    super.key,
    required this.line,
    required this.log,
    this.gatewayLine,
    this.partner,
    this.scrollController,
    this.onFilter,
    this.onClose,
    this.embedded = false,
  });

  /// Embedded in a scrolling page (topology below the lines).
  final bool embedded;

  /// Line behind the coupler (coupler = x.y.0).
  final int line;
  final TelegramLog log;
  final int? gatewayLine;

  /// Neighboring line in the view, in case the project defines no direction.
  final int? partner;
  final ScrollController? scrollController;

  /// Filters the monitor to a group address.
  final ValueChanged<String>? onFilter;

  /// Closes the inspector (wide layout only).
  final VoidCallback? onClose;

  @override
  State<CouplerTrafficView> createState() => _CouplerTrafficViewState();
}

class _CouplerTrafficViewState extends State<CouplerTrafficView> {
  /// Selected direction (from, to); `null` = all.
  (int, int)? _selected;
  (int, int)? _hovered;

  void _select((int, int) key) => setState(() => _selected = _selected == key ? null : key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return ListenableBuilder(
      listenable: liveUpdates(widget.log),
      builder: (context, _) {
        final traffic = CouplerTraffic.build(
          CatalogStore.instance.catalog,
          widget.log.log,
          widget.line,
          gatewayLine: widget.gatewayLine,
        );
        final partners = <int>{for (final f in traffic.flows) f.from == widget.line ? f.to : f.from}.toList();
        if (partners.isEmpty && widget.partner != null) partners.add(widget.partner!);
        final shown = [
          for (final f in traffic.flows)
            if (_selected == null || _selected == (f.from, f.to)) f,
        ];
        final gatewayOutside = traffic.gatewayLine != null && traffic.gatewayLine != widget.line;
        return ListView(
          controller: widget.scrollController,
          // Embedded (topology): scrolls with the page, no border of its own.
          shrinkWrap: widget.embedded,
          physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
          padding: widget.embedded
              ? EdgeInsets.zero
              : EdgeInsets.fromLTRB(Gap.gutter, widget.onClose == null ? 0 : Gap.item, Gap.gutter, Gap.bottom),
          children: [
            // Header: eyebrow label with coupler address and lines, the name
            // below.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: HorizontTitle(
                    kennung: s.hzHCouplerKennung(
                      formatIndividual(widget.line << 8),
                      s.hzHLinePair(
                        partners.isEmpty ? '—' : (partners.toList()..sort()).map(formatLine).join(', '),
                        formatLine(widget.line),
                      ),
                    ),
                    title: traffic.coupler?.name ?? s.hzHCouplerUnknown,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (widget.onClose != null) CloseDetailButton(onPressed: widget.onClose),
              ],
            ),
            const SizedBox(height: Gap.inner),
            if (traffic.flows.isNotEmpty || gatewayOutside)
              FigureBox(
                figures: [
                  // Telegrams per direction; the lists below count addresses.
                  for (final f in traffic.flows)
                    (s.hzHFlowTelegrams(formatLine(f.from), formatLine(f.to)), formatInt(f.telegrams)),
                  if (gatewayOutside) ...[
                    (s.hzHSeenAtGateway, formatInt(traffic.seenAtGateway)),
                    (s.hzHWithoutReceiver, formatInt(traffic.withoutReceiver)),
                  ],
                ],
              ),
            if (partners.isNotEmpty) ...[
              const SizedBox(height: Gap.inner),
              for (final p in partners)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.item),
                  child: _FlowDiagram(
                    partner: p,
                    line: widget.line,
                    gatewayLine: traffic.gatewayLine,
                    into: traffic.flows.where((f) => f.from == p && f.to == widget.line).firstOrNull,
                    out: traffic.flows.where((f) => f.from == widget.line && f.to == p).firstOrNull,
                    max: traffic.maxTelegrams,
                    selected: _selected,
                    hovered: _hovered,
                    onSelect: _select,
                    onHover: (key) => setState(() => _hovered = key),
                  ),
                ),
            ],
            const SizedBox(height: HzSpace.s4),
            Text(s.hzHFlowHint, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
            if (traffic.flows.isEmpty) ...[
              const SizedBox(height: Gap.section),
              Text(s.hzHFlowEmpty, style: theme.textTheme.bodySmall),
            ],
            if (_selected != null) ...[
              const SizedBox(height: Gap.item),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(onPressed: () => setState(() => _selected = null), child: Text(s.hzHAllDirections)),
              ),
            ],
            for (final f in shown) ...[
              const SizedBox(height: Gap.section),
              SectionTitle(s.hzHFlow(formatLine(f.from), formatLine(f.to)), count: f.groups.length),
              const SizedBox(height: HzSpace.s4),
              for (final g in f.groups)
                _FlowRow(
                  group: g,
                  onTap: widget.onFilter == null ? null : () => widget.onFilter!(formatGroup(g.address)),
                ),
            ],
          ],
        );
      },
    );
  }
}

/// Two line blocks with an arrow per direction between them: stroke width by
/// telegram count, the number in Monaspace above. Accent only for the selected
/// or hovered direction.
class _FlowDiagram extends StatelessWidget {
  const _FlowDiagram({
    required this.partner,
    required this.line,
    required this.gatewayLine,
    required this.into,
    required this.out,
    required this.max,
    required this.selected,
    required this.hovered,
    required this.onSelect,
    required this.onHover,
  });

  final int partner;
  final int line;
  final int? gatewayLine;
  final CouplerFlow? into;
  final CouplerFlow? out;
  final int max;
  final (int, int)? selected;
  final (int, int)? hovered;
  final ValueChanged<(int, int)> onSelect;
  final ValueChanged<(int, int)?> onHover;

  @override
  Widget build(BuildContext context) {
    Widget arrow((int, int) key, CouplerFlow? flow, {required bool toEnd}) => _FlowArrow(
      from: key.$1,
      to: key.$2,
      count: flow?.telegrams,
      max: max,
      toEnd: toEnd,
      active: selected == key || hovered == key,
      selected: selected == key,
      onTap: flow == null ? null : () => onSelect(key),
      onHover: (h) => onHover(h ? key : null),
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LineBlock(line: partner, gateway: partner == gatewayLine),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [arrow((partner, line), into, toEnd: true), arrow((line, partner), out, toEnd: false)],
            ),
          ),
          _LineBlock(line: line, gateway: line == gatewayLine),
        ],
      ),
    );
  }
}

class _LineBlock extends StatelessWidget {
  const _LineBlock({required this.line, required this.gateway});

  final int line;
  final bool gateway;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return Container(
      constraints: const BoxConstraints(minWidth: HzSpace.s64),
      padding: const EdgeInsets.symmetric(horizontal: HzSpace.s12, vertical: HzSpace.s8),
      decoration: BoxDecoration(
        color: hz.surface,
        borderRadius: Radii.tile,
        border: Border.all(color: hz.line, width: Lines.hairline),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(formatLine(line), style: context.mono(theme.textTheme.titleMedium).copyWith(color: hz.text)),
          if (gateway) Text(s.topoGatewayHere, style: theme.textTheme.labelSmall?.copyWith(color: hz.textMuted)),
        ],
      ),
    );
  }
}

/// One arrow of a direction; target for tapping and hovering.
class _FlowArrow extends StatelessWidget {
  const _FlowArrow({
    required this.from,
    required this.to,
    required this.count,
    required this.max,
    required this.toEnd,
    required this.active,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final int from;
  final int to;

  /// Telegrams; `null` if the direction does not exist according to the
  /// project.
  final int? count;
  final int max;

  /// Spitze am Ende (rechts in LTR).
  final bool toEnd;
  final bool active;
  final bool selected;
  final VoidCallback? onTap;
  final ValueChanged<bool> onHover;

  /// Strongest arrow, in addition to the hairline.
  static const _extra = HzSpace.s4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final n = count ?? 0;
    final stroke = Lines.hairline + (max == 0 ? 0 : _extra * n / max);
    final color = active ? hz.accentText : (count == null || n == 0 ? hz.lineStrong : hz.textMuted);
    final label = count == null ? '—' : formatInt(n);
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: '${s.hzHFlow(formatLine(from), formatLine(to))}, $label ${s.topoTelegrams}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        onHover: onHover,
        borderRadius: Radii.tile,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: HzSize.touch),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: HzSpace.s8, vertical: HzSpace.s4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: context
                      .mono(theme.textTheme.labelMedium)
                      .copyWith(color: active ? hz.accentText : hz.text, fontWeight: active ? FontWeight.w600 : null),
                ),
                const SizedBox(height: HzSpace.s2),
                SizedBox(
                  height: HzSpace.s12,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _ArrowPainter(
                      color: color,
                      stroke: stroke,
                      toEnd: toEnd == (Directionality.of(context) == TextDirection.ltr),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal line with a filled arrowhead, no gradient.
class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({required this.color, required this.stroke, required this.toEnd});

  final Color color;
  final double stroke;

  /// Arrowhead on the right (otherwise left).
  final bool toEnd;

  static const _head = HzSpace.s8;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final paint = Paint()..color = color;
    final half = (stroke + _head) / 2;
    if (toEnd) {
      canvas.drawRect(Rect.fromLTRB(0, y - stroke / 2, size.width - _head, y + stroke / 2), paint);
      canvas.drawPath(
        Path()
          ..moveTo(size.width - _head, y - half)
          ..lineTo(size.width, y)
          ..lineTo(size.width - _head, y + half)
          ..close(),
        paint,
      );
    } else {
      canvas.drawRect(Rect.fromLTRB(_head, y - stroke / 2, size.width, y + stroke / 2), paint);
      canvas.drawPath(
        Path()
          ..moveTo(_head, y - half)
          ..lineTo(0, y)
          ..lineTo(_head, y + half)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.color != color || old.stroke != stroke || old.toEnd != toEnd;
}

/// Group address of one direction: address, name, sender, count, last time.
class _FlowRow extends StatelessWidget {
  const _FlowRow({required this.group, this.onTap});

  final FlowGroup group;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final mono = context.mono(theme.textTheme.bodyMedium).copyWith(color: hz.text);
    final muted = context.mono(theme.textTheme.bodySmall).copyWith(color: hz.textMuted);
    final g = group;
    final sender = g.sender;
    final senderName = sender == null ? null : CatalogStore.instance.device(sender)?.name;
    return Semantics(
      button: onTap != null,
      hint: onTap == null ? null : s.hzHFilterHint,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: hz.line, width: Lines.hairline),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: HzSpace.s64 + HzSpace.s8),
                child: Text(formatGroup(g.address), style: mono.copyWith(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: HzSpace.s8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.info?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (sender != null)
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: formatIndividual(sender), style: muted),
                            if (senderName != null) TextSpan(text: '$metaSeparator$senderName'),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: HzSpace.s8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${formatInt(g.count)}×', style: mono),
                  Text(
                    g.last == null ? s.topoSilent : formatTime(g.last!, millis: false),
                    style: g.last == null ? theme.textTheme.bodySmall?.copyWith(color: hz.textMuted) : muted,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
