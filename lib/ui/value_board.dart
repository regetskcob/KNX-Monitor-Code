import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/dpt_codec.dart';
import '../model/telegram_log.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/expert_mode.dart';
import '../theme/tokens.dart';

import '../theme/palette.dart';
import '../model/alarms.dart';
import '../model/pinned_sections.dart';
import '../model/sections.dart';
import 'common.dart';
import 'telegram_row.dart';
import '../theme/app_icons.dart';

/// Last value per group address, grouped by measured quantity (e.g.
/// brightness) and ETS main group: narrow as rows with hairlines, wide as a
/// card grid. Sections can be collapsed; new values in collapsed sections only
/// briefly tint the header.
class ValueBoard extends StatefulWidget {
  const ValueBoard({
    super.key,
    required this.items,
    required this.counts,
    required this.history,
    required this.onTap,
    required this.onLongPress,
    this.log,
    this.selection,
    this.focused,
    this.onSelectGroup,
    this.leading = const [],
  });

  /// Selection mode: the check mark in the section header selects all or no cards.
  final ValueChanged<List<Telegram>>? onSelectGroup;

  /// Slivers before the sections (e.g. saved charts).
  final List<Widget> leading;

  /// Source for the time axis and average (optional).
  final TelegramLog? log;

  /// Letzte Telegramme, nach Adresse sortiert.
  final List<Telegram> items;
  final Map<int, int> counts;
  final Map<int, List<double>> history;
  final Set<Telegram>? selection;
  final Telegram? focused;
  final ValueChanged<Telegram> onTap;
  final ValueChanged<Telegram> onLongPress;

  @override
  State<ValueBoard> createState() => _ValueBoardState();
}

class _ValueBoardState extends State<ValueBoard> {
  CollapsedSections get _collapsed => CollapsedSections.instance;

  // --- Stable order -----------------------------------------------------------
  // Nothing jumps during interaction (tapping, scrolling, moving the mouse):
  // new cards and sections go to the end and are only sorted in once things are quiet.

  static const _favoritesId = 'favorites';
  static const _settleTime = Duration(milliseconds: 1500); // Logik, keine Animation
  List<int> _order = const [];
  List<String> _sectionOrder = const [];
  int _pointersDown = 0;

  /// Runs until the end of the quiet period after the last interaction.
  Timer? _settle;

  bool get _frozen => _pointersDown > 0 || (_settle?.isActive ?? false);

  void _interacted() {
    // After the quiet period, re-sort once.
    _settle?.cancel();
    _settle = Timer(_settleTime, () {
      if (mounted) setState(() {});
    });
  }

  /// Keeps the previous order, appends new items at the end.
  static List<T> _keepOrder<T, K>(List<T> sorted, List<K> previous, K Function(T) key) {
    final byKey = {for (final x in sorted) key(x): x};
    final known = previous.toSet();
    return [
      for (final k in previous) ?byKey[k],
      for (final x in sorted)
        if (!known.contains(key(x))) x,
    ];
  }

  void _onPins() {
    if (mounted) setState(() {});
  }

  // --- Keep the selected card in view -----------------------------------------
  // When the details open on the right, the grid gets narrower and the cards
  // reflow; the selected one often slides out of view. After the reflow the
  // list gently scrolls it back into the visible area.

  /// Key per card (GlobalKey: the card keeps its state while reflowing).
  final _cards = <int, GlobalKey>{};
  double? _lastWidth;
  Timer? _reveal;

  void _widthChanged(double width) {
    if (width == _lastWidth) return;
    final first = _lastWidth == null;
    _lastWidth = width;
    if (first || widget.focused == null) return;
    // The detail column slides in: scroll only after the last step.
    _reveal?.cancel();
    _reveal = Timer(const Duration(milliseconds: 120), _revealFocused);
  }

  /// Makes the selected card visible if it is not fully visible.
  void _revealFocused() {
    final focused = widget.focused;
    final context = focused == null ? null : _cards[focused.destination]?.currentContext;
    if (!mounted || context == null) return;
    final box = context.findRenderObject();
    final viewport = box == null ? null : RenderAbstractViewport.maybeOf(box);
    final scrollable = Scrollable.maybeOf(context);
    if (box == null || viewport == null || scrollable == null) return;
    final pixels = scrollable.position.pixels;
    final atTop = viewport.getOffsetToReveal(box, 0).offset;
    final atBottom = viewport.getOffsetToReveal(box, 1).offset;
    if (pixels >= atBottom && pixels <= atTop) return;
    Scrollable.ensureVisible(context, alignment: 0.3, duration: Motion.of(this.context), curve: Motion.curve);
  }

  @override
  void dispose() {
    _settle?.cancel();
    _reveal?.cancel();
    PinnedSections.instance.removeListener(_onPins);
    _collapsed.removeListener(_onPins);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    PinnedSections.instance
      ..addListener(_onPins)
      ..load();
    _collapsed
      ..addListener(_onPins)
      ..load();
  }

  @override
  Widget build(BuildContext context) {
    final frozen = _frozen;
    final items = frozen ? _keepOrder(widget.items, _order, (Telegram t) => t.destination) : widget.items;
    _order = [for (final t in items) t.destination];
    if (items.isEmpty) return HorizontEmptyHint(icon: AppIcons.sensors, text: s.boardEmpty);

    final sections = <String, List<Telegram>>{};
    final titles = <String, String>{};
    // Quantity sections first, in a fixed order.
    for (final id in typeSectionIds) {
      sections[id] = [];
    }
    final favorites = PinnedSections.instance.favorites;
    for (final t in items) {
      // Favorites appear only in their own section at the very top.
      if (favorites.contains(t.destination)) {
        (sections[_favoritesId] ??= []).add(t);
        titles[_favoritesId] = s.favorites;
        continue;
      }
      final (:id, :title, icon: _) = sectionFor(t.destination);
      (sections[id] ??= []).add(t);
      titles[id] = title;
    }
    sections.removeWhere((_, group) => group.isEmpty);
    final unpinned = frozen
        ? _keepOrder(sections.keys.toList(), _sectionOrder, (String id) => id)
        : sections.keys.toList();
    _sectionOrder = unpinned;
    // Pinned sections first; takes effect immediately, even during interaction.
    final ordered = PinnedSections.instance.order([
      for (final id in unpinned)
        if (id != _favoritesId) id,
    ]);
    final sectionIds = [if (sections.containsKey(_favoritesId)) _favoritesId, ...ordered];

    return Listener(
      // Empty areas count too (mouse between the cards).
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        _pointersDown++;
        _interacted();
      },
      onPointerUp: (_) {
        _pointersDown = (_pointersDown - 1).clamp(0, 10);
        _interacted();
      },
      onPointerCancel: (_) {
        _pointersDown = (_pointersDown - 1).clamp(0, 10);
        _interacted();
      },
      onPointerHover: (_) => _interacted(),
      onPointerSignal: (_) => _interacted(), // Mausrad
      child: LayoutBuilder(
        builder: (context, constraints) {
          _widthChanged(constraints.maxWidth);
          final gutter = Gap.gutterFor(constraints.maxWidth);
          // Narrow: plain rows with hairlines; wide: cards in a grid.
          Widget header(String id, List<Telegram> group, {double inset = HzSpace.s8}) => SectionHeader(
            inset: inset,
            title: titles[id]!,
            icon: null,
            count: group.length,
            // Changes with every telegram of this section.
            activity: group.fold(0, (sum, t) => sum + (widget.counts[t.destination] ?? 0)),
            latest: group.reduce((a, b) => a.time.isAfter(b.time) ? a : b),
            activeAlarms: group.where((t) => activeAlarm(t) != null).length,
            collapsed: _collapsed.contains(id),
            onToggle: () => _collapsed.toggle(id),
            // Favorites are pinned via their addresses, not as a section.
            pinned: PinnedSections.instance.contains(id),
            onPin: id == _favoritesId || widget.onSelectGroup != null ? null : () => PinnedSections.instance.toggle(id),
            allSelected: widget.onSelectGroup == null
                ? null
                : group.every((t) => widget.selection?.contains(t) ?? false),
            onSelectAll: widget.onSelectGroup == null ? null : () => widget.onSelectGroup!(group),
          );

          List<Widget> section(String id, List<Telegram> group, {required bool first}) => [
            SliverPadding(
              // The first section connects directly to the activity bar.
              padding: EdgeInsets.fromLTRB(
                gutter - HzSpace.s8,
                first ? 0 : HzSpace.s16,
                gutter - HzSpace.s8,
                HzSpace.s4,
              ),
              sliver: SliverToBoxAdapter(child: header(id, group)),
            ),
            if (!_collapsed.contains(id))
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final columns = columnsFor(constraints.crossAxisExtent, phone: false);
                    final lines = (group.length / columns).ceil();
                    return SliverList.builder(
                      itemCount: lines,
                      // Rows of cards of equal height; the height grows with the font.
                      itemBuilder: (context, line) => Padding(
                        padding: const EdgeInsets.only(bottom: HzSpace.s12),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: HzSpace.s12,
                            children: [
                              for (var c = 0; c < columns; c++)
                                Expanded(
                                  child: line * columns + c < group.length
                                      ? _card(group[line * columns + c], framed: true)
                                      : const SizedBox.shrink(),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ];

          // Grid: small sections (fewer cards than columns) share a row as long
          // as their cards fit in together; otherwise a lot of space would stay
          // empty on the right.
          List<Widget> packed(List<String> ids, {required bool first}) {
            final inner = constraints.maxWidth - 2 * gutter;
            final columns = columnsFor(inner, phone: false);
            bool small(String id) => !_collapsed.contains(id) && sections[id]!.length < columns;
            // Does another section including [_sectionGap] still fit next to it?
            // Cards keep the grid width so columns stay aligned.
            final card = (inner - (columns - 1) * _cardGap) / columns;
            bool fits(int cards, int parts) =>
                cards * card + (cards - parts) * _cardGap + (parts - 1) * _sectionGap <= inner + 0.5;
            final out = <Widget>[];
            var i = 0;
            while (i < ids.length) {
              final id = ids[i];
              var used = sections[id]!.length;
              var j = i + 1;
              if (small(id)) {
                while (j < ids.length && small(ids[j]) && fits(used + sections[ids[j]]!.length, j - i + 1)) {
                  used += sections[ids[j]]!.length;
                  j++;
                }
              }
              if (j - i < 2) {
                out.addAll(section(id, sections[id]!, first: first && i == 0));
              } else {
                out.add(
                  _packedRow(
                    [for (final k in ids.sublist(i, j)) (id: k, group: sections[k]!)],
                    header,
                    columns,
                    gutter: gutter,
                    top: first && i == 0 ? 0 : HzSpace.s16,
                  ),
                );
              }
              i = j;
            }
            return out;
          }

          // Favorites and pinned sections at the top on their own background.
          bool top(String id) => id == _favoritesId || PinnedSections.instance.contains(id);
          final pinned = [
            for (final id in sectionIds)
              if (top(id)) id,
          ];
          final rest = [
            for (final id in sectionIds)
              if (!top(id)) id,
          ];
          return CustomScrollView(
            slivers: [
              ...widget.leading,
              if (pinned.isNotEmpty) PinnedBand(rows: false, slivers: packed(pinned, first: true)),
              ...packed(rest, first: pinned.isEmpty),
              const SliverToBoxAdapter(child: SizedBox(height: HzSpace.s96 + HzSpace.s16)),
            ],
          );
        },
      ),
    );
  }

  /// Abstand zwischen Karten.
  static const _cardGap = HzSpace.s12;

  /// Gap between sections in one row, roughly as between stacked sections
  /// (card row 12 + header 16), so they read as separate.
  static const _sectionGap = HzSpace.s32;

  /// Several small sections side by side: per section the header and its cards
  /// at the same card width as in the rest of the grid.
  Widget _packedRow(
    List<({String id, List<Telegram> group})> parts,
    Widget Function(String id, List<Telegram> group, {double inset}) header,
    int columns, {
    required double gutter,
    required double top,
  }) => SliverPadding(
    padding: EdgeInsets.fromLTRB(gutter, top, gutter, HzSpace.s12),
    sliver: SliverToBoxAdapter(
      child: LayoutBuilder(
        builder: (context, c) {
          const gap = _cardGap;
          final card = (c.maxWidth - (columns - 1) * gap) / columns;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: _sectionGap,
            children: [
              for (final p in parts)
                SizedBox(
                  width: p.group.length * card + (p.group.length - 1) * gap,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: HzSpace.s4),
                        child: header(p.id, p.group, inset: 0),
                      ),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: gap,
                          children: [for (final t in p.group) Expanded(child: _card(t, framed: true))],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );

  Widget _card(Telegram t, {required bool framed}) => ValueCard(
    key: _cards.putIfAbsent(t.destination, GlobalKey.new),
    telegram: t,
    framed: framed,
    count: widget.counts[t.destination] ?? 0,
    history: widget.history[t.destination],
    times: widget.log?.historyTimes[t.destination],
    average: widget.log?.average(t.destination),
    selected: widget.selection?.contains(t),
    focused: widget.focused?.destination == t.destination,
    onTap: () => widget.onTap(t),
    onLongPress: () => widget.onLongPress(t),
  );
}

/// Own background for favorites and pinned sections at the very top: sunken
/// across the full width, a hairline at the bottom, without shadow or radius,
/// so rows (phone) and cards (grid) sit flush on it.
class PinnedBand extends StatelessWidget {
  const PinnedBand({super.key, required this.slivers, required this.rows});

  final List<Widget> slivers;

  /// Rows with their own hairline: no extra spacing at the bottom.
  final bool rows;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    return DecoratedSliver(
      decoration: BoxDecoration(
        color: hz.sunken,
        border: Border(
          bottom: BorderSide(color: hz.line, width: Lines.hairline),
        ),
      ),
      sliver: SliverMainAxisGroup(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: HzSpace.s8)),
          ...slivers,
          SliverToBoxAdapter(child: SizedBox(height: rows ? HzSpace.s8 : HzSpace.s4)),
        ],
      ),
    );
  }
}

/// Header of a section as a label with counter ("HELLIGKEIT · 5"): tapping
/// collapses/expands it, the pin button pins it to the top. Collapsed, it shows
/// the most recently changed value and briefly tints in accent-tint on new telegrams.
class SectionHeader extends StatefulWidget {
  const SectionHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.count,
    required this.activity,
    required this.latest,
    required this.collapsed,
    this.activeAlarms = 0,
    required this.onToggle,
    this.pinned = false,
    this.onPin,
    this.onAdd,
    this.allSelected,
    this.onSelectAll,
    this.inset = HzSpace.s8,
  });

  /// Left/right padding; 0 when the header sits flush above cards.
  final double inset;

  /// "+" in the header (e.g. new chart); `null` = no button.
  final VoidCallback? onAdd;

  /// Selection mode: all cards selected (check mark), `null` = no check mark.
  final bool? allSelected;
  final VoidCallback? onSelectAll;

  /// Whether it is pinned to the top (pin button selected).
  final bool pinned;

  /// Pins/unpins via the pin button in the header (right-click: menu);
  /// `null` = not pinnable, no button.
  final VoidCallback? onPin;

  final String title;

  /// Kept for callers; the label does without an icon.
  final IconData? icon;
  final int count;
  final int activity;

  /// Newest telegram (summary in the collapsed header); `null` = none.
  final Telegram? latest;
  final bool collapsed;

  /// Active alarms/faults in the section, visible as a badge even when collapsed.
  final int activeAlarms;
  final VoidCallback onToggle;

  @override
  State<SectionHeader> createState() => _SectionHeaderState();
}

class _SectionHeaderState extends State<SectionHeader> with SingleTickerProviderStateMixin {
  late final _blink = AnimationController(vsync: this, duration: Motion.calm, value: 1);

  @override
  void didUpdateWidget(SectionHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.collapsed && widget.activity != oldWidget.activity && !MediaQuery.disableAnimationsOf(context)) {
      _blink.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  Future<void> _pinMenu(BuildContext context, [Offset? at]) async {
    if (await showPinMenu(context, pinned: widget.pinned, at: at)) widget.onPin?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final store = CatalogStore.instance;
    final latest = widget.latest;
    return Semantics(
      button: true,
      expanded: !widget.collapsed,
      label: s.boardSectionSemantics(widget.title, widget.count),
      child: AnimatedBuilder(
        animation: _blink,
        builder: (context, child) => Material(
          color: Color.lerp(Colors.transparent, hz.accentTint, 1 - Motion.settle.transform(_blink.value)),
          borderRadius: Radii.tile,
          child: child,
        ),
        child: InkWell(
          borderRadius: Radii.tile,
          onTap: widget.onToggle,
          onSecondaryTapUp: widget.onPin == null ? null : (d) => _pinMenu(context, d.globalPosition),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: context.hzTheme.controlHeight),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.inset),
              child: Row(
                children: [
                  // With large text, label and badge wrap instead of overflowing.
                  Expanded(
                    child: Wrap(
                      spacing: HzSpace.s8,
                      runSpacing: HzSpace.s4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ExcludeSemantics(
                          child: SectionTitle(widget.title, count: widget.count, maxLines: widget.inset == 0 ? 1 : 2),
                        ),
                        if (widget.activeAlarms > 0)
                          HorizontBadge(
                            HorizontStatus.critical,
                            label: '${s.activityAlarms} · ${formatInt(widget.activeAlarms)}',
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: HzSpace.s16),
                  // Collapsed: newest value on the right, at most half the row.
                  // Expanded, it takes no space and the label gets the row.
                  // Fixed at half the row: a short value would otherwise leave the
                  // rest of the row empty, and pin and arrow would move to the left.
                  if (widget.collapsed && latest != null)
                    Expanded(
                      child: Text(
                        '${store.title(latest)}$metaSeparator${store.value(latest)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: context.mono(theme.textTheme.bodySmall).copyWith(color: hz.textMuted),
                      ),
                    ),
                  if (widget.onAdd case final onAdd?)
                    IconButton(
                      tooltip: s.chartNew,
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(shape: const RoundedRectangleBorder(borderRadius: Radii.tile)),
                      onPressed: onAdd,
                      icon: Icon(AppIcons.add, size: 18, color: hz.textMuted),
                    ),
                  if (widget.allSelected case final all?)
                    IconButton(
                      tooltip: all ? s.selectNone : s.selectAll,
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onSelectAll,
                      icon: Icon(
                        all ? AppIcons.selected : AppIcons.unselected,
                        size: HzIconSize.row,
                        color: all ? hz.accent : hz.lineStrong,
                      ),
                    ),
                  if (widget.onPin case final onPin?)
                    // Pinned: accent-text on accent-tint, otherwise quiet.
                    IconButton(
                      tooltip: widget.pinned ? s.sectionUnpin : s.sectionPin,
                      isSelected: widget.pinned,
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        shape: const RoundedRectangleBorder(borderRadius: Radii.tile),
                        backgroundColor: widget.pinned ? hz.accentTint : Colors.transparent,
                      ),
                      onPressed: onPin,
                      icon: Icon(AppIcons.pinOutline, size: 18, color: hz.textMuted),
                      selectedIcon: Icon(AppIcons.pin, size: 18, color: hz.accentText),
                    ),
                  // Chevron like HorizontSectionHeader: down when collapsed, up when open.
                  AnimatedRotation(
                    turns: widget.collapsed ? 0 : 0.5,
                    duration: Motion.of(context),
                    curve: Motion.curve,
                    child: Icon(AppIcons.expand, size: HzIconSize.row, color: hz.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Value of a group address: name, large value in Monaspace with history and
/// average, below it address, DPT, time and sender. [framed]: card in the grid
/// (wide), otherwise a plain row with hairline (phone). New values briefly tint
/// it in accent-tint.
class ValueCard extends StatefulWidget {
  const ValueCard({
    super.key,
    required this.telegram,
    required this.count,
    required this.onTap,
    required this.onLongPress,
    this.history,
    this.times,
    this.average,
    this.selected,
    this.focused = false,
    this.framed = true,
  });

  final Telegram telegram;
  final int count;
  final List<double>? history;

  /// Points in time for [history]; switching states on a real time axis.
  final List<DateTime>? times;

  /// Average since the start (small below the history for measured values).
  final double? average;
  final bool? selected;
  final bool focused;

  /// Karte (Raster) statt Zeile (Liste).
  final bool framed;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<ValueCard> createState() => _ValueCardState();
}

class _ValueCardState extends State<ValueCard> with SingleTickerProviderStateMixin {
  // Afterglow on a new value: calm, fades out softly.
  late final _flash = AnimationController(vsync: this, duration: Motion.calm, value: 1);

  @override
  void didUpdateWidget(ValueCard old) {
    super.didUpdateWidget(old);
    if (!identical(old.telegram, widget.telegram) && !MediaQuery.disableAnimationsOf(context)) {
      _flash.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  /// "Ø 3,2 m/s" for measured values (not for counters, switching states, texts).
  String? _averageText(Dpt? dpt) {
    final avg = widget.average;
    if (avg == null || dpt == null) return null;
    final h = widget.history;
    if (h == null || !h.any((v) => v != h.first)) return null;
    final measured = switch (dpt.main) {
      9 || 8 || 7 => true,
      14 => true,
      5 => dpt.sub == 1,
      _ => false,
    };
    if (!measured) return null;
    final unit = dptUnit(dpt);
    return 'Ø ${formatWithUnit(avg, unit.isEmpty ? '' : ' $unit')}';
  }

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final t = widget.telegram;
    final highlighted = widget.selected == true || widget.focused;
    final alarm = activeAlarm(t) != null;
    final framed = widget.framed;
    // Selection = 2 px accent, alarm = 2 px critical (with badge), otherwise a hairline.
    final line = alarm ? hz.critical : (highlighted ? hz.accent : (framed ? hz.line : Colors.transparent));
    final width = alarm || highlighted ? Lines.selection : Lines.hairline;
    final base = highlighted ? hz.accentTint : (framed ? hz.surface : Colors.transparent);

    return AnimatedBuilder(
      animation: _flash,
      builder: (context, child) {
        final color = Color.lerp(hz.accentTint, base, Motion.settle.transform(_flash.value));
        return framed
            ? Material(
                color: color,
                shape: RoundedRectangleBorder(
                  borderRadius: Radii.card,
                  side: BorderSide(color: line, width: width),
                ),
                clipBehavior: Clip.antiAlias,
                child: child,
              )
            : Material(color: color, child: child);
      },
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: framed
            ? _framed(context)
            : DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: line, width: Lines.selection),
                    bottom: BorderSide(color: hz.line, width: Lines.hairline),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Gap.gutter - Lines.selection,
                    HzSpace.s12,
                    Gap.gutter,
                    HzSpace.s12,
                  ),
                  child: _content(context, framed: false),
                ),
              ),
      ),
    );
  }

  /// Card in the grid: content with padding, the history runs to the bottom edge.
  /// For every value that has a history at all ([numericValue]: measured values,
  /// counters, percentages and switching states); switching states as a step
  /// line on a time axis. Texts, times and scenes have none.
  Widget _framed(BuildContext context) {
    final hz = context.hz;
    final t = widget.telegram;
    final dpt = CatalogStore.instance.info(t.destination)?.dpt;
    final history = widget.history;
    final trend = history != null && history.length >= 2 && history.any((v) => v != history.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(HzSpace.s12, HzSpace.s12, HzSpace.s12, HzSpace.s8),
            child: _content(context, framed: true),
          ),
        ),
        if (trend)
          SizedBox(
            height: 22,
            child: Sparkline(
              values: history,
              times: widget.times,
              color: hz.accent,
              fill: hz.accentTint,
              step: isStepDpt(dpt, t),
              expand: true,
            ),
          ),
      ],
    );
  }

  Widget _content(BuildContext context, {required bool framed}) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final store = CatalogStore.instance;
    final t = widget.telegram;
    final info = store.info(t.destination);
    final device = store.device(t.source);
    final alarm = activeAlarm(t);
    final meta = context.mono(theme.textTheme.bodySmall).copyWith(color: hz.textMuted);
    final average = _averageText(info?.dpt);
    final history = widget.history;
    final trend = history != null && history.length >= 2 && history.any((v) => v != history.first);

    final text = store.value(t);
    final guessAt = framed ? text.indexOf('$metaSeparator≈ ') : -1;
    final valueStyle = context
        .figures(theme.textTheme.titleLarge)
        .copyWith(fontWeight: FontWeight.w600, color: alarm != null ? hz.critical : hz.text);
    // New value like a ticker: slides in a bit from below, the old one out
    // downwards (calm/settle, immediately under reduced motion).
    final value = AnimatedSwitcher(
      duration: Motion.calmOf(context),
      switchInCurve: Motion.settle,
      switchOutCurve: Motion.curveOut,
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.bottomLeft, children: [...previous, ?current]),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: guessAt < 0
          ? Text(text, key: ValueKey(t), softWrap: !framed, style: valueStyle)
          // Card without a project: the interpretation large, the raw data small
          // below; together in one row the card would shrink both to tiny.
          : Column(
              key: ValueKey(t),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(text.substring(guessAt + metaSeparator.length), softWrap: false, style: valueStyle),
                Text(text.substring(0, guessAt), softWrap: false, style: meta),
              ],
            ),
    );
    // On/off, open/closed …: step line between 0 and 1.
    final sparkline = !trend
        ? null
        : Sparkline(
            values: history,
            times: widget.times,
            color: hz.accent,
            averageColor: hz.lineStrong,
            step: isStepDpt(info?.dpt, t),
            average: average == null ? null : widget.average,
          );
    // "4/0/2 · DPT 9.004 · Wetterstation"
    final address = Text(
      [
        if (info != null) t.destinationText,
        if (info?.dpt != null) 'DPT ${info!.dpt}',
        if (info?.path case final path? when path.contains(' › ')) path.split(' › ').skip(1).join(' › '),
      ].join(metaSeparator),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: meta,
    );
    final origin = Text(
      // Time and count kept together at the front, the (long) device name may
      // wrap, so a single dot never hangs at the end of the line.
      // Without a telegram (project address in the selection): say only that.
      widget.count == 0
          ? s.boardNoTelegramYet
          : [
              '${formatTime(t.time, millis: false)}\u00a0·\u00a0${formatInt(widget.count)}×',
              if (t.outgoing) s.detailsSentLower else device?.name ?? t.sourceText,
            ].join(metaSeparator),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: meta,
    );

    final short = Text(
      widget.count == 0
          ? s.boardNoTelegramYet
          : [
              formatTime(t.time, seconds: false),
              if (expert) '${formatInt(widget.count)}×',
              if (t.outgoing) s.detailsSentLower else device?.name ?? t.sourceText,
            ].join(metaSeparator),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                info?.name ?? t.destinationText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500, color: hz.text),
              ),
            ),
            const SizedBox(width: HzSpace.s8),
            if (widget.selected != null)
              Icon(
                widget.selected! ? AppIcons.selected : AppIcons.unselected,
                size: 22,
                color: widget.selected! ? hz.accent : hz.lineStrong,
              )
            else if (alarm != null)
              AlarmChip(kind: alarm)
            else if (expert)
              TypeBadge(type: t.type, outgoing: t.outgoing),
          ],
        ),
        const SizedBox(height: HzSpace.s4),
        // Wide enough (row): history next to the value, Ø below the history as
        // in the design. Card: value across the full width, history next to the metadata.
        if (framed) ...[
          // Exception in the fixed card: shrink long raw data instead of
          // cutting it off (the row on the phone wraps instead).
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.bottomLeft, child: value),
          const SizedBox(height: HzSpace.s2),
          // Everyday: time and sender; address, DPT and Ø in expert mode.
          if (expert) address,
          short,
          if (expert && average != null) Text(average, style: meta),
        ] else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: value),
              if (trend) ...[const SizedBox(width: HzSpace.s8), ?sparkline],
            ],
          ),
          const SizedBox(height: HzSpace.s4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: address),
              if (trend && average != null) ...[const SizedBox(width: HzSpace.s8), Text(average, style: meta)],
            ],
          ),
          origin,
        ],
      ],
    );
  }
}

/// Small line history without fill. [step]: sharp jumps for switching states
/// (0/1), scale fixed from 0 to 1.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.step = false,
    this.times,
    this.average,
    this.averageColor,
    this.fill,
    this.expand = false,
  });

  /// Fill below the line down to the bottom edge.
  final Color? fill;

  /// Fills the given space and runs over the edge at the sides.
  final bool expand;

  /// Average as a dashed hairline (the scale includes it).
  final double? average;

  /// Color of the average line (default: line-strong).
  final Color? averageColor;

  final List<double> values;

  /// Points in time for [values]: with [step] a real time axis up to now, so
  /// the line shows how long a state lasted (e.g. valve cycling).
  final List<DateTime>? times;
  final Color color;
  final bool step;

  /// Resolution of the time axis' right edge ("now"): the step line grows in
  /// steps of this size instead of a repaint on every rebuild of the board.
  static const nowResolution = Duration(seconds: 10);

  @override
  Widget build(BuildContext context) {
    final axis = step && times != null && times!.length == values.length ? List.of(times!) : null;
    final ms = DateTime.now().millisecondsSinceEpoch;
    // Only a time axis depends on the current time; without one, `now` stays
    // fixed so unchanged values are not painted again.
    final now = axis == null
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime.fromMillisecondsSinceEpoch(ms - ms % nowResolution.inMilliseconds + nowResolution.inMilliseconds);
    // Own layer: the card's afterglow and neighbouring cards repaint without it.
    return RepaintBoundary(
      child: ExcludeSemantics(
        child: SizedBox(
          width: expand ? double.infinity : 72,
          height: expand ? double.infinity : 28,
          child: CustomPaint(
            painter: _SparklinePainter(
              List.of(values),
              color,
              averageColor ?? context.hz.lineStrong,
              step: step,
              times: axis,
              now: now,
              average: step ? null : average,
              fill: fill,
              bleed: expand,
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether a history is a switching state (step line from 0 to 1): DPT 1 and 2
/// and short telegrams without a known type.
bool isStepDpt(Dpt? dpt, Telegram t) => dpt?.main == 1 || dpt?.main == 2 || t.isSmall;

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(
    this.values,
    this.color,
    this.averageColor, {
    this.step = false,
    this.times,
    required this.now,
    this.average,
    this.fill,
    this.bleed = false,
  });

  final Color? fill;
  final bool bleed;
  final double? average;
  final Color averageColor;

  final List<double> values;
  final Color color;
  final bool step;
  final List<DateTime>? times;
  final DateTime now;

  @override
  void paint(Canvas canvas, Size size) {
    var lo = step ? 0.0 : values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (step && hi < 1) hi = 1;
    final avg = average;
    if (avg != null) {
      if (avg < lo) lo = avg;
      if (avg > hi) hi = avg;
    }
    if (hi - lo < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    final times = this.times;
    final span = times == null ? 0 : now.difference(times.first).inMilliseconds;
    // Over the edge: the line ends at the card's edge, not before it.
    final over = bleed ? 2.0 : 0.0;
    double x(int i) => times != null && span > 0
        ? size.width * times[i].difference(times.first).inMilliseconds / span
        : -over + (size.width + 2 * over) * i / (values.length - 1);
    double y(double v) => size.height - 2 - (size.height - 4) * (v - lo) / (hi - lo);
    Offset at(int i) => Offset(x(i), y(values[i]));

    // Average first, dashed 2/2; the line lies on top.
    if (avg != null) {
      // One path instead of a draw call per dash (about 60 per card).
      final dashes = Path();
      for (var dx = 0.0; dx < size.width; dx += 4) {
        dashes
          ..moveTo(dx, y(avg))
          ..lineTo((dx + 2).clamp(0, size.width), y(avg));
      }
      canvas.drawPath(
        dashes,
        Paint()
          ..color = averageColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = Lines.hairline,
      );
    }
    // Switching state on the card: only the "on" stretches, as filled blocks
    // with an edge on top (like the rows in the charts); "off" stays empty.
    if (step && fill != null) {
      final timed = times != null && span > 0;
      // Without times every value gets a slot of its own, so the last one is
      // visible too instead of ending at the edge.
      double from(int i) => timed ? x(i) : size.width * i / values.length;
      double to(int i) =>
          timed ? (i + 1 < values.length ? x(i + 1) : size.width) : size.width * (i + 1) / values.length;
      final block = Paint()..color = fill!;
      final edge = Paint()
        ..color = color
        ..strokeWidth = bleed ? 1.5 : Lines.data;
      for (var i = 0; i < values.length; i++) {
        if (values[i] <= lo) continue;
        final left = from(i);
        final right = to(i);
        if (right <= left) continue;
        final top = y(values[i]);
        canvas
          ..drawRect(Rect.fromLTRB(left, top, right, size.height + over), block)
          ..drawLine(Offset(left, top), Offset(right, top), edge);
      }
      return;
    }
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      if (step) line.lineTo(at(i).dx, at(i - 1).dy);
      line.lineTo(at(i).dx, at(i).dy);
    }
    // Time axis: extend the last state up to now.
    if (times != null && span > 0) line.lineTo(size.width, at(values.length - 1).dy);
    if (fill case final fill?) {
      final area = Path.from(line)
        ..lineTo(size.width + over, size.height + over)
        ..lineTo(-over, size.height + over)
        ..close();
      canvas.drawPath(area, Paint()..color = fill);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = bleed ? 1.5 : Lines.data
        ..strokeJoin = StrokeJoin.miter,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.color != color ||
      old.averageColor != averageColor ||
      old.step != step ||
      old.now != now ||
      old.average != average ||
      old.fill != fill ||
      !listEquals(old.values, values) ||
      !listEquals(old.times, times);
}

/// Columns of the overview: on the phone one card per row, otherwise one column
/// per started 240 pt, at most 5 (iPad 11″: 4 portrait, 5 landscape, 3 with the detail column).
/// Columns of the overview: as many as keep every card at least
/// [Widths.gridCard] wide (rounded down), two to eight; on 21:9 there would
/// otherwise be 600 px wide cards with the history far away from the value.
int columnsFor(double width, {required bool phone}) => phone ? 1 : (width / Widths.gridCard).floor().clamp(2, 8);
