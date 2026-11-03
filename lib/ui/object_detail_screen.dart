import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/alarms.dart';
import '../model/communication_map.dart';
import '../model/expert_mode.dart';
import '../model/object_groups.dart';
import '../model/telegram_log.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../theme/palette.dart';
import 'common.dart';
import 'communication_map_screen.dart';
import 'figure_box.dart';
import 'object_board.dart';
import 'telegram_row.dart';
import '../model/plan.dart';
import 'plan_screen.dart';

/// An object in the style of the communication map: commands on the left, the
/// object in the middle, feedback on the right, each with live value and last sender.
class ObjectDetailScreen extends StatelessWidget {
  const ObjectDetailScreen({
    super.key,
    required this.object,
    required this.data,
    required this.onFilter,
    this.onOpenAddress,
    this.onRead,
  });

  /// Reads addresses on the bus (only with a connection): "Rückmeldungen lesen" (read feedback).
  final Future<void> Function(List<int> addresses)? onRead;

  final ObjectGroup object;
  final TelegramLog data;
  final ValueChanged<String> onFilter;

  /// Details of an address (read, write, chart, map); without it, the map.
  final ValueChanged<int>? onOpenAddress;

  /// Tapping a member: details if a telegram has arrived already, otherwise the map.
  void _openMember(BuildContext context, int address) {
    if (onOpenAddress case final open? when data.latest[address] != null || data.forAddress(address).isNotEmpty) {
      open(address);
    } else {
      _openMap(context, address);
    }
  }

  Future<void> _openMap(BuildContext context, int address) async {
    if (!await unlock(context, Feature.communicationMap) || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunicationMapScreen(log: data, start: MapNode.group(address)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth >= Breakpoints.expanded;
      return Scaffold(
        appBar: AppBar(
          title: Text({?object.room, object.title}.join(' · ')),
          actions: [
            // The most common task on site: read all feedback at once.
            if (onRead != null && object.feedbacks.isNotEmpty)
              IconButton(
                tooltip: s.objectReadFeedbacks,
                onPressed: () => onRead!([for (final m in object.feedbacks) m.address]),
                icon: const Icon(AppIcons.read),
              ),
            IconButton(
              tooltip: s.objectFilter,
              onPressed: () {
                Navigator.pop(context);
                // Comma = OR: all addresses of the object.
                onFilter(object.members.map((m) => formatGroup(m.address)).join(', '));
              },
              icon: const Icon(AppIcons.filter),
            ),
            // Narrow without a fixed bar: the legend behind the info icon.
            if (!wide)
              IconButton(
                tooltip: s.hzFLegend,
                onPressed: () =>
                    showInfoDialog(context, title: s.hzFLegend, content: const _Legend(edges: false, inline: true)),
                icon: const Icon(AppIcons.info),
              ),
          ],
        ),
        body: ListenableBuilder(
          listenable: data,
          builder: (context, _) => wide
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _Wide(object: object, data: data, onTap: (a) => _openMember(context, a)),
                    ),
                    const _Legend(edges: true),
                  ],
                )
              : _Narrow(object: object, data: data, onTap: (a) => _openMember(context, a)),
        ),
      );
    },
  );
}

class _Wide extends StatefulWidget {
  const _Wide({required this.object, required this.data, required this.onTap});

  final ObjectGroup object;
  final TelegramLog data;
  final ValueChanged<int> onTap;

  @override
  State<_Wide> createState() => _WideState();
}

/// Columns at their natural height (names may wrap, values may move below the
/// names); the painter reads the edges from the laid-out cards.
class _WideState extends State<_Wide> {
  static const _gap = 60.0;
  static const _centerMinHeight = 120.0;

  final _canvas = GlobalKey();
  final _center = GlobalKey();
  final _cards = <int, GlobalKey>{};

  GlobalKey _card(int address) => _cards.putIfAbsent(address, GlobalKey.new);

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final object = widget.object;
    final latest = widget.data.latest;
    return SingleChildScrollView(
      padding: Gap.page,
      child: CustomPaint(
        key: _canvas,
        painter: _Edges(
          canvas: _canvas,
          center: _center,
          left: [for (final m in object.commands) (_card(m.address), latest[m.address] != null)],
          right: [for (final m in object.feedbacks) (_card(m.address), latest[m.address] != null)],
          color: hz.textMuted,
          dashed: hz.lineStrong,
        ),
        // Columns aligned at the top, the object centered over their height.
        child: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _column(s.objectCommands, object.commands)),
                const SizedBox(width: _gap),
                const Expanded(child: SizedBox(height: _centerMinHeight)),
                const SizedBox(width: _gap),
                Expanded(child: _column(s.objectFeedback, object.feedbacks)),
              ],
            ),
            Positioned.fill(
              child: Row(
                children: [
                  const Spacer(),
                  const SizedBox(width: _gap),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: _centerMinHeight),
                        child: KeyedSubtree(
                          key: _center,
                          child: _Center(object: object),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: _gap),
                  const Spacer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _column(String title, List<ObjectMember> members) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionTitle(title, count: members.length),
      const SizedBox(height: HzSpace.s8),
      if (members.isEmpty) Text(s.mapNone),
      for (final m in members)
        Padding(
          padding: const EdgeInsets.only(bottom: HzSpace.s8),
          child: KeyedSubtree(
            key: _card(m.address),
            child: _MemberCard(
              member: m,
              telegram: widget.data.latest[m.address],
              onTap: () => widget.onTap(m.address),
            ),
          ),
        ),
    ],
  );
}

class _Narrow extends StatelessWidget {
  const _Narrow({required this.object, required this.data, required this.onTap});

  final ObjectGroup object;
  final TelegramLog data;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget list(String title, List<ObjectMember> members) => Padding(
      padding: const EdgeInsets.only(top: HzSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(title, count: members.length),
          const SizedBox(height: HzSpace.s8),
          if (members.isEmpty)
            Text(s.mapNone)
          else
            SectionCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, m) in members.indexed) ...[
                    if (i > 0) const Divider(height: Lines.hairline, indent: HzSpace.s16, endIndent: HzSpace.s16),
                    _MemberLine(member: m, telegram: data.latest[m.address], onTap: () => onTap(m.address)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
    return ListView(
      padding: Gap.page,
      children: [
        Row(
          children: [
            Icon(objectIcon(object), size: HzIconSize.row, color: context.hz.textFaint),
            const SizedBox(width: HzSpace.s8),
            Expanded(
              child: Text(
                s.objectMembers(object.members.length),
                style: theme.textTheme.bodyMedium?.copyWith(color: context.hz.textMuted),
              ),
            ),
          ],
        ),
        list(s.objectFeedback, object.feedbacks),
        list(s.objectCommands, object.commands),
      ],
    );
  }
}

/// Row of a function: name, below it the address in Monaspace and, quietly,
/// time and sender (in expert mode the data type); on the right the value in
/// bold, without a value a quiet hint or, for commands, the arrow.
class _MemberLine extends StatelessWidget {
  const _MemberLine({required this.member, required this.telegram, required this.onTap});

  final ObjectMember member;
  final Telegram? telegram;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final store = CatalogStore.instance;
    final t = telegram;
    final alarm = t == null ? null : activeAlarm(t);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: HzSpace.s16, vertical: HzSpace.s8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.function, style: theme.textTheme.bodyLarge),
                  _MemberMeta(member: member, telegram: t),
                  if (expert)
                    Text(
                      _dptText(store.dptOf(member.address)),
                      style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint),
                    ),
                  if (alarm != null) ...[const SizedBox(height: HzSpace.s4), AlarmChip(kind: alarm)],
                ],
              ),
            ),
            const SizedBox(width: Gap.item),
            if (t != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.4),
                child: Text(
                  store.value(t),
                  textAlign: TextAlign.end,
                  style: context
                      .figures(theme.textTheme.bodyLarge)
                      .copyWith(fontWeight: FontWeight.w700, color: alarm != null ? hz.critical : hz.text),
                ),
              )
            else if (member.feedback)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.4),
                child: Text(
                  s.hzFNoTelegram,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyMedium?.copyWith(color: hz.textFaint),
                ),
              )
            else
              Icon(AppIcons.next, size: HzIconSize.row, color: hz.textFaint),
          ],
        ),
      ),
    );
  }
}

/// "2/0/3 · 12:00 · Absender" (sender): only the address in Monaspace.
class _MemberMeta extends StatelessWidget {
  const _MemberMeta({required this.member, required this.telegram, this.maxLines});

  final ObjectMember member;
  final Telegram? telegram;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final t = telegram;
    final rest = [
      if (t != null) formatTime(t.time, millis: false),
      if (t != null && !t.outgoing) CatalogStore.instance.device(t.source)?.name ?? t.sourceText,
    ];
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: formatGroup(member.address),
            style: context.mono(theme.textTheme.bodySmall).copyWith(color: hz.textMuted),
          ),
          if (rest.isNotEmpty) TextSpan(text: '$metaSeparator${rest.join(metaSeparator)}'),
        ],
      ),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint),
    );
  }
}

class _Center extends StatelessWidget {
  const _Center({required this.object});

  final ObjectGroup object;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return Container(
      padding: const EdgeInsets.all(Gap.card),
      decoration: BoxDecoration(
        color: hz.surface,
        borderRadius: Radii.card,
        border: Border.all(color: hz.line, width: Lines.hairline),
      ),
      child: Row(
        children: [
          Icon(objectIcon(object), size: 32, color: hz.textMuted),
          const SizedBox(width: HzSpace.s12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(object.key, style: theme.textTheme.titleMedium),
                Text(
                  s.objectMembers(object.members.length),
                  style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Function with address, time and sender, the value on the right (wide card).
/// An alarm draws 2 px critical and a badge, no red surface.
class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member, required this.telegram, required this.onTap});

  final ObjectMember member;
  final Telegram? telegram;
  final VoidCallback onTap;

  /// Room an alarm badge needs next to the value (before text scaling).
  static const _alarmReserve = HzSpace.s96;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final store = CatalogStore.instance;
    final t = telegram;
    final alarm = t == null ? null : activeAlarm(t);
    final nameStyle = theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500);
    final valueStyle = context
        .figures(theme.textTheme.titleSmall)
        .copyWith(
          fontWeight: FontWeight.w700,
          color: alarm != null ? hz.critical : (t == null ? hz.textMuted : hz.text),
        );
    final dptStyle = theme.textTheme.labelSmall?.copyWith(color: hz.textFaint);
    final value = t == null ? '–' : store.value(t);
    final dpt = _dptText(store.dptOf(member.address));
    final name = Text(member.function, style: nameStyle);
    // Value and below it the data type; even without a value it is clear what comes.
    Widget reading(CrossAxisAlignment align) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align,
      children: [
        Text(value, style: valueStyle),
        Text(dpt, style: dptStyle),
      ],
    );
    return Material(
      color: hz.surface,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.tile,
        side: BorderSide(
          color: alarm != null ? hz.critical : hz.lineStrong,
          width: alarm != null ? Lines.selection : Lines.hairline,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: HzSpace.s12, vertical: HzSpace.s8),
          child: LayoutBuilder(
            builder: (context, c) {
              // If name and value do not fit side by side, the value moves below
              // the name; the name is never cut off.
              final scaler = MediaQuery.textScalerOf(context);
              final direction = Directionality.of(context);
              double width(String text, TextStyle? style) {
                final painter = TextPainter(
                  text: TextSpan(text: text, style: style),
                  textDirection: direction,
                  textScaler: scaler,
                  maxLines: 1,
                )..layout();
                final w = painter.width;
                painter.dispose();
                return w;
              }

              final side =
                  [width(value, valueStyle), width(dpt, dptStyle)].reduce((a, b) => a > b ? a : b) +
                  (alarm != null ? scaler.scale(_alarmReserve) : 0);
              final fits = width(member.function, nameStyle) + HzSpace.s8 + side <= c.maxWidth;
              if (fits) {
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          name,
                          // The sender can be long; single line as before.
                          _MemberMeta(member: member, telegram: t, maxLines: 1),
                        ],
                      ),
                    ),
                    const SizedBox(width: HzSpace.s8),
                    if (alarm != null) ...[AlarmChip(kind: alarm), const SizedBox(width: HzSpace.s8)],
                    reading(CrossAxisAlignment.end),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  name,
                  _MemberMeta(member: member, telegram: t),
                  const SizedBox(height: HzSpace.s4),
                  if (alarm != null) ...[AlarmChip(kind: alarm), const SizedBox(height: HzSpace.s4)],
                  reading(CrossAxisAlignment.start),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// "DPT 9.001", without a known type "DPT –". The unit is already shown with the value.
String _dptText(Dpt? dpt) => dpt == null ? 'DPT –' : 'DPT $dpt';

/// Legend as a quiet bar at the bottom: drawn samples of the edges or the empty
/// value and the alarm frame, each with a word, plus the source.
class _Legend extends StatelessWidget {
  const _Legend({required this.edges, this.inline = false});

  /// Wide view with edges; narrow layouts only have cards.
  final bool edges;

  /// In the dialog: without its own surface, border and heading.
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final gutter = inline ? 0.0 : Gap.gutterFor(MediaQuery.sizeOf(context).width);
    final label = theme.textTheme.bodySmall?.copyWith(color: hz.textMuted);
    Widget item(Widget sample, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: sample),
        const SizedBox(width: HzSpace.s8),
        Flexible(child: Text(text, style: label)),
      ],
    );
    // Samples grow with the font so they stay readable next to the word.
    final scaler = MediaQuery.textScalerOf(context);
    final line = Size(scaler.scale(HzSpace.s32), scaler.scale(HzSpace.s12));
    final items = Wrap(
      spacing: HzSpace.s24,
      runSpacing: HzSpace.s8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!inline) Kennung(s.hzFLegend),
        if (edges) ...[
          item(
            CustomPaint(
              size: line,
              painter: _Sample(color: hz.textMuted, seen: true),
            ),
            s.hzFReceived,
          ),
          item(
            CustomPaint(
              size: line,
              painter: _Sample(color: hz.lineStrong, seen: false),
            ),
            s.hzFNoTelegram,
          ),
        ] else
          item(Text('–', style: context.figures(theme.textTheme.titleSmall)), s.hzFNoTelegram),
        item(
          Container(
            width: scaler.scale(HzSpace.s24),
            height: scaler.scale(HzSpace.s12),
            decoration: BoxDecoration(
              borderRadius: Radii.row,
              border: Border.all(color: hz.critical, width: Lines.selection),
            ),
          ),
          s.alarmLabel,
        ),
        item(Icon(AppIcons.info, size: scaler.scale(HzSpace.s16), color: hz.textMuted), s.hzFDetected),
      ],
    );
    if (inline) return items;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hz.bg,
        border: Border(
          top: BorderSide(color: hz.line, width: Lines.hairline),
        ),
      ),
      child: SafeArea(top: false, minimum: EdgeInsets.fromLTRB(gutter, HzSpace.s12, gutter, HzSpace.s12), child: items),
    );
  }
}

/// Sample of an edge for the legend, same stroke as [_Edges].
class _Sample extends CustomPainter {
  const _Sample({required this.color, required this.seen});

  final Color color;
  final bool seen;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = seen ? Lines.selection : Lines.hairline
      ..color = color;
    if (seen) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    } else {
      for (var d = 0.0; d < size.width; d += _Edges.dashGap) {
        canvas.drawLine(Offset(d, y), Offset((d + _Edges.dash).clamp(0, size.width), y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Sample old) => old.color != color || old.seen != seen;
}

/// Lines from the columns to the object: solid = value received, dashed = none
/// yet.
class _Edges extends CustomPainter {
  _Edges({
    required this.canvas,
    required this.center,
    required this.left,
    required this.right,
    required this.color,
    required this.dashed,
  });

  /// Reference for the coordinates: the CustomPaint itself.
  final GlobalKey canvas;
  final GlobalKey center;

  /// Card per address and whether a value has arrived yet.
  final List<(GlobalKey, bool)> left;
  final List<(GlobalKey, bool)> right;
  final Color color;
  final Color dashed;

  /// Dash length and gap of the dashed edge.
  static const dash = 5.0;
  static const dashGap = 9.0;

  /// Position of a card in the CustomPaint; painted after layout.
  Rect? _rect(GlobalKey key) {
    final origin = canvas.currentContext?.findRenderObject();
    final box = key.currentContext?.findRenderObject();
    if (origin is! RenderBox || box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero, ancestor: origin) & box.size;
  }

  @override
  void paint(Canvas canvas, Size size) {
    void edge(Offset a, Offset b, bool seen) {
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo((a.dx + b.dx) / 2, a.dy, (a.dx + b.dx) / 2, b.dy, b.dx, b.dy);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = seen ? Lines.selection : Lines.hairline
        ..color = seen ? color : dashed;
      if (seen) {
        canvas.drawPath(path, paint);
      } else {
        for (final metric in path.computeMetrics()) {
          for (var d = 0.0; d < metric.length; d += dashGap) {
            canvas.drawPath(metric.extractPath(d, d + dash), paint);
          }
        }
      }
    }

    final mid = _rect(center);
    if (mid == null) return;
    for (final (key, seen) in left) {
      if (_rect(key) case final r?) edge(r.centerRight, mid.centerLeft, seen);
    }
    for (final (key, seen) in right) {
      if (_rect(key) case final r?) edge(mid.centerRight, r.centerLeft, seen);
    }
  }

  @override
  bool shouldRepaint(_Edges old) => true;
}
