import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/alarms.dart';
import '../model/expert_mode.dart';
import '../model/object_groups.dart';
import '../model/pinned_sections.dart';
import '../model/telegram_log.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'horizon_rail.dart';
import 'object_detail_screen.dart';
import 'telegram_row.dart';
import 'tool_shell.dart';
import 'value_board.dart';

/// Icon of an object, derived from the datapoint types of its addresses.
IconData objectIcon(ObjectGroup o) {
  final dpts = [for (final m in o.members) CatalogStore.instance.dptOf(m.address)];
  bool has(int main, [int? sub]) => dpts.any((d) => d?.main == main && (sub == null || d?.sub == sub));
  if (has(1, 8) || has(1, 7) && has(5, 1)) return AppIcons.blinds;
  if (has(3, 7)) return AppIcons.light;
  if (has(9, 1) || has(20, 102)) return AppIcons.thermostat;
  if (has(1, 19) || o.members.every((m) => m.feedback)) return AppIcons.window;
  if (has(1, 1)) return AppIcons.light;
  return AppIcons.overview;
}

/// The "Objekte" (objects) view: related group addresses as cards, grouped by
/// room, with the current values of all functions.
class ObjectBoard extends StatefulWidget {
  const ObjectBoard({
    super.key,
    required this.data,
    required this.matches,
    required this.onFilter,
    this.onOpenAddress,
    this.onRead,
    this.empty,
  });

  /// Reads addresses on the bus (object details: "Rückmeldungen lesen", read feedback).
  final Future<void> Function(List<int> addresses)? onRead;

  /// Opens the details of a group address (from the object view).
  final ValueChanged<int>? onOpenAddress;

  /// Replacement for the empty hint (e.g. "Nichts passt zum Filter", nothing matches).
  final Widget? empty;

  final TelegramLog data;

  /// Filter of the monitor view; an object appears when one of its addresses matches.
  final bool Function(Telegram) matches;
  final ValueChanged<String> onFilter;

  @override
  State<ObjectBoard> createState() => _ObjectBoardState();
}

class _ObjectBoardState extends State<ObjectBoard> {
  final _scroll = ScrollController();

  /// Header per room, for the outline on the right.
  final _heads = <String, GlobalKey>{};

  TelegramLog get data => widget.data;
  bool Function(Telegram) get matches => widget.matches;
  ValueChanged<String> get onFilter => widget.onFilter;
  ValueChanged<int>? get onOpenAddress => widget.onOpenAddress;
  Future<void> Function(List<int> addresses)? get onRead => widget.onRead;
  Widget? get empty => widget.empty;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pins = PinnedSections.instance..load();
    final collapsed = CollapsedSections.instance..load();
    return ListenableBuilder(
      listenable: Listenable.merge([pins, collapsed]),
      builder: (context, _) => _board(context, pins, collapsed),
    );
  }

  Widget _board(BuildContext context, PinnedSections pins, CollapsedSections collapsed) {
    final index = ObjectIndex.forCatalog(CatalogStore.instance.catalog);
    final rooms = <String, List<ObjectGroup>>{};
    for (final o in index.objects) {
      final seen = [for (final m in o.members) ?data.latest[m.address]];
      if (seen.isEmpty || !seen.any(matches)) continue;
      (rooms[o.room ?? s.objectsOther] ??= []).add(o);
    }
    if (rooms.isEmpty) return empty ?? HorizontEmptyHint(icon: AppIcons.overview, text: s.objectsEmpty);
    final sorted = rooms.keys.toList()
      ..sort((a, b) => a == s.objectsOther ? 1 : (b == s.objectsOther ? -1 : a.compareTo(b)));
    // Pinned rooms first.
    final keys = [
      for (final id in pins.order([for (final r in sorted) 'room:$r'])) id.substring(5),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = Gap.gutterFor(constraints.maxWidth);
        // Outline from 1200 and only when there are several rooms.
        final outline = constraints.maxWidth >= Breakpoints.large && keys.length > 1;
        List<Widget> room(String room, {required bool first}) => [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(gutter - HzSpace.s8, first ? 0 : HzSpace.s16, gutter - HzSpace.s8, HzSpace.s4),
            sliver: SliverToBoxAdapter(
              key: _heads.putIfAbsent(room, GlobalKey.new),
              child: _roomHeader(room, rooms[room]!, pins, collapsed),
            ),
          ),
          // One column: build cards only when they come into view (noticeable on
          // weak phones with many objects).
          if (!collapsed.contains('room:$room') && constraints.maxWidth < Breakpoints.medium)
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              sliver: SliverList.builder(
                itemCount: rooms[room]!.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: HzSpace.s12),
                  child: ObjectCard(
                    object: rooms[room]![i],
                    data: data,
                    onFilter: onFilter,
                    onOpenAddress: onOpenAddress,
                    onRead: onRead,
                  ),
                ),
              ),
            )
          else if (!collapsed.contains('room:$room'))
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              sliver: SliverToBoxAdapter(
                child: LayoutBuilder(
                  builder: (context, c) => _Masonry(
                    // Few objects use the width instead of leaving space free on the right.
                    columns: math.min(
                      objectColumnsFor(c.maxWidth, phone: constraints.maxWidth < Breakpoints.medium),
                      math.max(rooms[room]!.length, 2),
                    ),
                    heights: [for (final o in rooms[room]!) _estimatedHeight(o)],
                    children: [
                      for (final o in rooms[room]!)
                        ObjectCard(
                          object: o,
                          data: data,
                          onFilter: onFilter,
                          onOpenAddress: onOpenAddress,
                          onRead: onRead,
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ];

        // Pinned rooms at the top on their own background, as in the overview.
        final pinned = [
          for (final r in keys)
            if (pins.contains('room:$r')) r,
        ];
        final rest = [
          for (final r in keys)
            if (!pins.contains('room:$r')) r,
        ];
        final list = CustomScrollView(
          controller: _scroll,
          // All rooms built so the outline knows their position.
          scrollCacheExtent: outline ? const ScrollCacheExtent.pixels(100000) : null,
          slivers: [
            if (pinned.isNotEmpty)
              PinnedBand(
                rows: false,
                slivers: [
                  for (final r in pinned) ...[
                    ...room(r, first: r == pinned.first),
                    const SliverToBoxAdapter(child: SizedBox(height: HzSpace.s12)),
                  ],
                ],
              ),
            for (final r in rest) ...room(r, first: false),
            const SliverToBoxAdapter(child: SizedBox(height: HzSpace.s96 + HzSpace.s16)),
          ],
        );
        if (!outline) return list;
        // Wide: outline of the rooms at the right edge.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The outline shows the position; the system scrollbar is dropped,
            // otherwise two would sit side by side.
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: list,
              ),
            ),
            HorizonRail(
              controller: _scroll,
              marks: [
                for (final r in [...pinned, ...rest]) (r, _heads[r]!),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Room header as a label ("EG ARBEITSZIMMER · 4") – the same building block as
  /// the overview sections: collapsible, pinnable, tinted on new values while
  /// collapsed.
  Widget _roomHeader(String room, List<ObjectGroup> objects, PinnedSections pins, CollapsedSections collapsed) {
    final id = 'room:$room';
    final telegrams = [
      for (final o in objects)
        for (final m in o.members) ?data.latest[m.address],
    ];
    return SectionHeader(
      title: room,
      icon: null,
      count: objects.length,
      activity: [
        for (final o in objects)
          for (final m in o.members) data.counts[m.address] ?? 0,
      ].fold(0, (a, b) => a + b),
      latest: telegrams.isEmpty ? null : telegrams.reduce((a, b) => a.time.isAfter(b.time) ? a : b),
      activeAlarms: telegrams.where((t) => activeAlarm(t) != null).length,
      collapsed: collapsed.contains(id),
      onToggle: () => collapsed.toggle(id),
      pinned: pins.contains(id),
      onPin: () => pins.toggle(id),
    );
  }
}

/// Columns of objects: one on the phone, otherwise one per started 320 pt,
/// 2 to 4 (iPad 11″: 3 portrait, 4 landscape), so every card is wider than
/// [Widths.gridCard].
int objectColumnsFor(double width, {required bool phone}) => phone ? 1 : (width / 320).ceil().clamp(2, 4);

/// Approximate card height for distributing across columns (header + one row per function).
double _estimatedHeight(ObjectGroup o) => 56 + 44.0 * o.members.length;

/// Cards column by column, each into the currently shortest column; no gaps as
/// with a row-wise layout of cards of different heights.
class _Masonry extends StatelessWidget {
  const _Masonry({required this.columns, required this.heights, required this.children});

  final int columns;
  final List<double> heights;
  final List<Widget> children;

  static const _gap = HzSpace.s12;

  @override
  Widget build(BuildContext context) {
    final lanes = [for (var i = 0; i < columns; i++) <Widget>[]];
    final filled = List.filled(columns, 0.0);
    for (final (i, child) in children.indexed) {
      var lane = 0;
      for (var c = 1; c < columns; c++) {
        if (filled[c] < filled[lane]) lane = c;
      }
      if (lanes[lane].isNotEmpty) lanes[lane].add(const SizedBox(height: _gap));
      lanes[lane].add(child);
      filled[lane] += heights[i] + _gap;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: _gap,
      children: [
        for (final lane in lanes)
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: lane),
          ),
      ],
    );
  }
}

/// Card of an object with all functions: surface, hairline; header with name
/// and number of addresses, below it per function "Rückmeldung  Aus" (feedback
/// off). New values tint it briefly in accent-tint, an alarm draws 2 px critical
/// and a badge.
class ObjectCard extends StatefulWidget {
  const ObjectCard({
    super.key,
    required this.object,
    required this.data,
    required this.onFilter,
    this.onOpenAddress,
    this.onRead,
    this.selected = false,
  });

  final ObjectGroup object;
  final TelegramLog data;
  final ValueChanged<String> onFilter;
  final ValueChanged<int>? onOpenAddress;
  final Future<void> Function(List<int> addresses)? onRead;

  /// Selected (inspector): 2 px accent and accent-tint.
  final bool selected;

  @override
  State<ObjectCard> createState() => _ObjectCardState();
}

class _ObjectCardState extends State<ObjectCard> with SingleTickerProviderStateMixin {
  late final _flash = AnimationController(vsync: this, duration: Motion.slow, value: 1);
  DateTime? _last;

  DateTime? get _latestTime {
    DateTime? latest;
    for (final m in widget.object.members) {
      final t = widget.data.latest[m.address]?.time;
      if (t != null && (latest == null || t.isAfter(latest))) latest = t;
    }
    return latest;
  }

  @override
  void didUpdateWidget(ObjectCard old) {
    super.didUpdateWidget(old);
    final latest = _latestTime;
    if (_last != null && latest != _last && !MediaQuery.disableAnimationsOf(context)) _flash.forward(from: 0);
    _last = latest;
  }

  @override
  void initState() {
    super.initState();
    _last = _latestTime;
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final store = CatalogStore.instance;
    final o = widget.object;
    final alarms = [
      for (final m in o.members)
        if (widget.data.latest[m.address] case final t? when activeAlarm(t) != null) activeAlarm(t)!,
    ];
    final alarm = alarms.isNotEmpty;
    final selected = widget.selected;
    final base = selected ? hz.accentTint : hz.surface;

    return AnimatedBuilder(
      animation: _flash,
      builder: (context, child) => Material(
        color: Color.lerp(hz.accentTint, base, Motion.curve.transform(_flash.value)),
        shape: RoundedRectangleBorder(
          borderRadius: Radii.card,
          side: BorderSide(
            color: alarm ? hz.critical : (selected ? hz.accent : hz.line),
            width: alarm || selected ? Lines.selection : Lines.hairline,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
      child: InkWell(
        // Like the tools: the sidebar stays in place.
        onTap: () => pushTool<void>(
          context,
          (_) => ObjectDetailScreen(
            object: o,
            data: widget.data,
            onFilter: widget.onFilter,
            onOpenAddress: widget.onOpenAddress,
            onRead: widget.onRead,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(HzSpace.s16, HzSpace.s12, HzSpace.s16, HzSpace.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      o.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: HzSpace.s8),
                  Text(
                    s.objectMembers(o.members.length),
                    style: context.figures(theme.textTheme.bodySmall).copyWith(color: hz.textFaint),
                  ),
                ],
              ),
              if (alarm) ...[
                const SizedBox(height: HzSpace.s4),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AlarmChip(kind: alarms.first),
                ),
              ],
              const SizedBox(height: HzSpace.s4),
              for (final (i, m) in [...o.feedbacks, ...o.commands].indexed) ...[
                if (i > 0) const Divider(height: Lines.hairline),
                _MemberRow(member: m, telegram: widget.data.latest[m.address], store: store),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "Rückmeldung  Aus" (feedback off): function and the value on the right, feedback
/// in bold, commands quiet; the direction as an arrow only in expert mode.
class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.telegram, required this.store});

  final ObjectMember member;
  final Telegram? telegram;
  final CatalogStore store;

  /// How long a new value stays highlighted (logic, not animation).
  static const _fresh = Duration(seconds: 2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final t = telegram;
    final alarm = t != null && activeAlarm(t) != null;
    final fresh = t != null && DateTime.now().difference(t.time) < _fresh;
    // Function on the left as wide as possible, value right-aligned and only as
    // wide as needed (at most a good half); previously both shared the row 1:1
    // and the function was truncated early.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            if (expert) ...[
              Icon(member.feedback ? AppIcons.receives : AppIcons.sends, size: 14, color: hz.textFaint),
              const SizedBox(width: HzSpace.s4),
            ],
            Expanded(
              child: Text(
                member.function,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: HzSpace.s8),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.55),
              child: Text(
                t == null ? '–' : store.value(t),
                textAlign: TextAlign.end,
                style: context
                    .figures(theme.textTheme.bodyMedium)
                    .copyWith(
                      fontWeight: fresh || alarm || (member.feedback && t != null) ? FontWeight.w700 : FontWeight.w400,
                      color: alarm
                          ? hz.critical
                          : (fresh ? hz.accentText : (member.feedback && t != null ? hz.text : hz.textMuted)),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
