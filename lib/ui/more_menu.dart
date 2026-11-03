import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../l10n/locale_controller.dart';
import '../model/expert_mode.dart';
import '../model/plan.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'plan_screen.dart';
import 'tool_shell.dart';

/// Groups in the menu, in this order, from the most frequent occasion to the rarest.
enum ToolGroup {
  /// Is the installation OK? Health, commissioning, diagnostics.
  check,

  /// What happens on the bus and where? Bus monitor, topology, communication map.
  bus,

  /// Numbers and histories from the traffic: statistics, charts, response times.
  analyze,

  /// Capturing: recordings, trigger recording.
  record,

  /// Paperwork and customers: company, service report, customer file, handover.
  documents,

  /// Where the installation data comes from and where it goes; listed together
  /// with the menu actions under "Daten" (data).
  data,

  /// Learning content unrelated to the installation: its own entry without a heading.
  learn;

  String get title => switch (this) {
    check => s.menuGroupCheck,
    bus => s.menuGroupBus,
    analyze => s.menuGroupAnalyze,
    record => s.menuGroupRecord,
    documents => s.menuGroupDocuments,
    data => s.menuGroupData,
    learn => s.lessonsTitle,
  };

  /// Groups with their own heading, in the order of the enum.
  static const headed = [check, bus, analyze, record, documents];
}

/// A tool with a short explanation.
class ToolEntry {
  const ToolEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.open,
    required this.group,
    this.order = 0,
    this.expertOnly = false,
    this.feature,
  });

  /// Requires a tier: locked with a badge, tapping opens the paywall.
  final Feature? feature;

  /// Only in the menu in expert mode; otherwise only the everyday tools are shown.
  final bool expertOnly;

  /// Order within the group (smaller = higher up).
  final int order;

  final IconData icon;
  final String title;
  final String subtitle;
  final ToolGroup group;

  /// Opens the tool; [context] is the calling screen.
  final void Function(BuildContext context) open;
}

/// A simple action in the menu (export, project, clear, disconnect).
class MenuAction {
  const MenuAction({
    required this.icon,
    required this.title,
    required this.onTap,
    this.enabled = true,
    this.danger = false,
    this.selected = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool enabled;
  final bool danger;

  /// Whether it is currently shown (tinted in the sidebar).
  final bool selected;
}

/// A switch in the menu (expert mode, notifications …).
class MenuToggle {
  const MenuToggle({required this.icon, required this.title, required this.value, required this.onChanged});

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
}

/// Content of the "Mehr" (more) menu: tools by group, data, settings.
class MoreMenu {
  const MoreMenu({
    required this.tools,
    this.data = const [],
    this.toggles = const [],
    this.footer = const [],
    this.pinned,
    this.home,
  });

  /// First entry of the sidebar: the monitor's overview. On a tool page it
  /// closes the tool.
  final MenuAction? home;

  /// Switches in a fixed box at the bottom (expert mode): does not scroll and
  /// is always reachable.
  final MenuToggle? pinned;

  final List<ToolEntry> tools;
  final List<MenuAction> data;
  final List<MenuToggle> toggles;
  final List<MenuAction> footer;
}

/// Opens the menu: on the phone as its own page, on the tablet as a popover at
/// the button ([anchor] = its context). Popover following Horizont: surface with
/// hairline, radius 10, no shadow, fade-in only.
Future<void> showMoreMenu(BuildContext context, MoreMenu Function() menu, {required BuildContext anchor}) {
  final wide = MediaQuery.sizeOf(context).width >= Breakpoints.medium;
  if (!wide) {
    return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _MoreScreen(menu: menu)));
  }
  final rect = rectOf(anchor);
  final scrim = Theme.of(context).colorScheme.scrim;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: s.commonClose,
    // Quieter than a dialog: a quarter of the theme's scrim opacity.
    barrierColor: scrim.withValues(alpha: scrim.a / 4),
    transitionDuration: Motion.of(context),
    pageBuilder: (dialogContext, _, _) {
      final size = MediaQuery.sizeOf(dialogContext);
      final hz = dialogContext.hz;
      final top = (rect?.bottom ?? HzSpace.s64) + HzSpace.s8;
      final right = size.width - (rect?.right ?? size.width - HzSpace.s12);
      return Stack(
        children: [
          Positioned(
            top: top,
            right: right.clamp(HzSpace.s12, size.width),
            width: Widths.form,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: size.height - top - HzSpace.s24),
              child: Material(
                color: hz.surface,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: Radii.card,
                  side: BorderSide(color: hz.line, width: Lines.hairline),
                ),
                clipBehavior: Clip.antiAlias,
                child: _MoreList(menu: menu, mode: _MoreMode.popover),
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Motion.curve, reverseCurve: Motion.curveOut),
      child: child,
    ),
  );
}

/// The menu as a sidebar (from 600, collapsible): the same groups, actions take
/// effect directly without closing anything.
class MoreSidebar extends StatelessWidget {
  const MoreSidebar({super.key, required this.menu, this.active});

  final MoreMenu Function() menu;

  /// Title of the open tool: tinted in the bar.
  final String? active;

  @override
  Widget build(BuildContext context) => _MoreList(menu: menu, mode: _MoreMode.sidebar, active: active);
}

enum _MoreMode { page, popover, sidebar }

class _MoreScreen extends StatelessWidget {
  const _MoreScreen({required this.menu});

  final MoreMenu Function() menu;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(s.menuTitle)),
    body: _MoreList(menu: menu, mode: _MoreMode.page),
  );
}

/// List with groups; rebuilds on switches (values come fresh from [menu]).
class _MoreList extends StatefulWidget {
  const _MoreList({required this.menu, required this.mode, this.active});

  final MoreMenu Function() menu;
  final _MoreMode mode;
  final String? active;

  /// Compact: in the popover and in the sidebar.
  bool get popover => mode != _MoreMode.page;

  @override
  State<_MoreList> createState() => _MoreListState();
}

class _MoreListState extends State<_MoreList> {
  /// Closes the menu first (popover or page), then runs the action.
  void _run(VoidCallback action) {
    if (widget.mode != _MoreMode.sidebar) Navigator.of(context).pop();
    action();
  }

  Future<void> _open(ToolEntry t) async {
    // Phone: replace the menu page so that "Back" leads to the monitor.
    final ctx = context;
    final navigator = Navigator.of(ctx);
    if (t.feature case final f? when !await unlock(ctx, f)) return;
    if (widget.mode != _MoreMode.sidebar) navigator.pop();
    ToolShell.instance.opening = t.title;
    if (ctx.mounted) t.open(ctx);
  }

  /// Sidebar: a calm list of headings and rows, always by group; expert mode
  /// only shows more entries.
  Widget _sidebar(MoreMenu menu) {
    final tool = ModalRoute.of(context) is ToolRoute;
    final visible = [
      for (final t in menu.tools)
        if (expert || !t.expertOnly) t,
    ]..sort((a, b) => a.order - b.order);
    final hidden = expert ? 0 : menu.tools.where((t) => t.expertOnly).length;
    Widget toolRow(ToolEntry t) => _SideRow(
      icon: t.icon,
      title: t.title,
      tooltip: t.subtitle,
      selected: t.title == widget.active,
      onTap: () => _open(t),
      trailing: switch (t.feature) {
        final f? when !Plan.instance.allows(f) => TierBadge(f.tier),
        _ => null,
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(HzSpace.s8, HzSpace.s12, HzSpace.s8, HzSpace.s16),
            children: [
              if (menu.home case final home?)
                _SideRow(
                  icon: home.icon,
                  title: home.title,
                  selected: home.selected && !tool,
                  onTap: () {
                    if (tool) Navigator.of(context).pop();
                    home.onTap();
                  },
                ),
              for (final g in ToolGroup.headed)
                if (visible.any((t) => t.group == g)) ...[
                  _SideLabel(g.title),
                  for (final t in visible)
                    if (t.group == g) toolRow(t),
                ],
              if (menu.data.isNotEmpty || visible.any((t) => t.group == ToolGroup.data)) ...[
                _SideLabel(s.menuGroupData),
                for (final t in visible)
                  if (t.group == ToolGroup.data) toolRow(t),
                for (final a in menu.data)
                  _SideRow(icon: a.icon, title: a.title, enabled: a.enabled, onTap: () => _run(a.onTap)),
              ],
              if (menu.toggles.isNotEmpty) ...[
                _SideLabel(s.menuGroupSettings),
                for (final t in menu.toggles)
                  _SideRow(
                    icon: t.icon,
                    title: t.title,
                    onTap: () => setState(() {
                      t.onChanged(!t.value);
                    }),
                    trailing: Switch.adaptive(
                      value: t.value,
                      onChanged: (v) => setState(() {
                        t.onChanged(v);
                      }),
                    ),
                  ),
              ],
              if (visible.any((t) => t.group == ToolGroup.learn)) ...[
                const SizedBox(height: HzSpace.s24),
                for (final t in visible)
                  if (t.group == ToolGroup.learn) toolRow(t),
              ],
              if (menu.footer.isNotEmpty) ...[
                const SizedBox(height: HzSpace.s24),
                for (final a in menu.footer)
                  _SideRow(
                    icon: a.icon,
                    title: a.title,
                    enabled: a.enabled,
                    danger: a.danger,
                    onTap: () => _run(a.onTap),
                  ),
              ],
              // Without expert mode: say that there is more, and lead there with a tap.
              if (hidden > 0 && menu.pinned != null) ...[
                const SizedBox(height: HzSpace.s24),
                _SideRow(
                  icon: AppIcons.expert,
                  title: s.menuMoreTools(hidden),
                  muted: true,
                  onTap: () => setState(() {
                    menu.pinned!.onChanged(true);
                  }),
                ),
              ],
              const Padding(
                padding: EdgeInsets.fromLTRB(HzSpace.s8, HzSpace.s16, HzSpace.s8, HzSpace.s4),
                child: Align(alignment: AlignmentDirectional.centerStart, child: SenderLine()),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: HzSpace.s8),
                child: Align(alignment: AlignmentDirectional.centerStart, child: VersionLine()),
              ),
            ],
          ),
        ),
        // Fixed at the bottom, without its own surface like the other rows.
        if (menu.pinned case final p?)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(HzSpace.s8, 0, HzSpace.s8, HzSpace.s8),
              child: _SideRow(
                icon: p.icon,
                title: p.title,
                onTap: () => setState(() {
                  p.onChanged(!p.value);
                }),
                trailing: Switch.adaptive(
                  value: p.value,
                  onChanged: (v) => setState(() {
                    p.onChanged(v);
                  }),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final menu = widget.menu();
    if (widget.mode == _MoreMode.sidebar) return _sidebar(menu);
    final visible = [
      for (final t in menu.tools)
        if (expert || !t.expertOnly) t,
    ]..sort((a, b) => a.group.index != b.group.index ? a.group.index - b.group.index : a.order - b.order);
    // Without expert mode only a few tools remain: one "Werkzeuge" (tools) group
    // instead of several groups with one entry each.
    final groups = expert
        ? {
            for (final g in ToolGroup.headed)
              g.title: [
                for (final t in visible)
                  if (t.group == g) t,
              ],
          }
        : {s.toolsTitle: visible};
    // Without expert mode they are already under "Werkzeuge" (tools).
    final dataTools = expert ? visible.where((t) => t.group == ToolGroup.data).toList() : const <ToolEntry>[];
    final learnTools = expert ? visible.where((t) => t.group == ToolGroup.learn).toList() : const <ToolEntry>[];
    Widget toolTile(ToolEntry t) => _Tile(
      dense: widget.popover,
      icon: t.icon,
      title: t.title,
      subtitle: widget.popover ? null : t.subtitle,
      tooltip: t.subtitle,
      selected: t.title == widget.active,
      onTap: () => _open(t),
      trailing: switch (t.feature) {
        final f? when !Plan.instance.allows(f) => TierBadge(f.tier),
        _ => null,
      },
      chevron: true,
    );
    // Tools that only expert mode shows.
    final hidden = expert ? 0 : menu.tools.where((t) => t.expertOnly).length;
    final pad = switch (widget.mode) {
      _MoreMode.page => Gap.page,
      _MoreMode.popover => const EdgeInsets.fromLTRB(HzSpace.s4, HzSpace.s12, HzSpace.s4, HzSpace.s8),
      _MoreMode.sidebar => EdgeInsets.zero,
    };
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Widths.reading),
        child: Column(
          mainAxisSize: widget.mode == _MoreMode.popover ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              fit: widget.mode == _MoreMode.popover ? FlexFit.loose : FlexFit.tight,
              child: ListView(
                shrinkWrap: widget.mode == _MoreMode.popover,
                padding: pad,
                children: [
                  for (final MapEntry(key: title, value: tools) in groups.entries)
                    if (tools.isNotEmpty)
                      _Section(
                        title: title,
                        count: tools.length,
                        dense: widget.popover,
                        children: [
                          for (final t in tools) toolTile(t),
                          // Without expert mode: say that there is more, and lead there with a tap.
                          if (title == s.toolsTitle && hidden > 0 && menu.pinned != null)
                            _Tile(
                              dense: widget.popover,
                              icon: AppIcons.expert,
                              title: s.menuMoreTools(hidden),
                              subtitle: widget.popover ? null : s.menuMoreToolsHint,
                              onTap: () => setState(() {
                                menu.pinned!.onChanged(true);
                              }),
                              chevron: true,
                            ),
                        ],
                      ),
                  if (menu.data.isNotEmpty || dataTools.isNotEmpty)
                    _Section(
                      title: s.menuGroupData,
                      dense: widget.popover,
                      children: [
                        for (final t in dataTools) toolTile(t),
                        for (final a in menu.data)
                          _Tile(
                            dense: widget.popover,
                            icon: a.icon,
                            title: a.title,
                            enabled: a.enabled,
                            onTap: () => _run(a.onTap),
                            chevron: true,
                          ),
                      ],
                    ),
                  if (menu.toggles.isNotEmpty)
                    _Section(
                      title: s.menuGroupSettings,
                      dense: widget.popover,
                      children: [
                        for (final t in menu.toggles)
                          _Tile(
                            dense: widget.popover,
                            icon: t.icon,
                            title: t.title,
                            onTap: () => setState(() {
                              t.onChanged(!t.value);
                            }),
                            trailing: Switch.adaptive(
                              value: t.value,
                              onChanged: (v) => setState(() {
                                t.onChanged(v);
                              }),
                            ),
                          ),
                      ],
                    ),
                  if (learnTools.isNotEmpty)
                    _Section(dense: widget.popover, children: [for (final t in learnTools) toolTile(t)]),
                  if (menu.footer.isNotEmpty)
                    _Section(
                      dense: widget.popover,
                      children: [
                        for (final a in menu.footer)
                          _Tile(
                            dense: widget.popover,
                            icon: a.icon,
                            title: a.title,
                            enabled: a.enabled,
                            danger: a.danger,
                            onTap: () => _run(a.onTap),
                          ),
                      ],
                    ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(Gap.gutter, HzSpace.s16, Gap.gutter, HzSpace.s4),
                    child: Align(alignment: AlignmentDirectional.centerStart, child: SenderLine()),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, HzSpace.s16),
                    child: Align(alignment: AlignmentDirectional.centerStart, child: VersionLine()),
                  ),
                ],
              ),
            ),
            if (menu.pinned case final p?)
              _PinnedToggle(
                toggle: p,
                // Block body: onChanged may be an arrow that returns a Future,
                // which setState rejects.
                onChanged: (v) => setState(() {
                  p.onChanged(v);
                }),
              ),
          ],
        ),
      ),
    );
  }
}

/// Fixed box at the end of the menu (expert mode): lowered surface with a
/// hairline on top, does not scroll.
class _PinnedToggle extends StatelessWidget {
  const _PinnedToggle({required this.toggle, required this.onChanged});

  final MenuToggle toggle;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hz.sunken,
        border: Border(
          top: BorderSide(color: hz.line, width: Lines.hairline),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: HzSpace.s4, vertical: HzSpace.s4),
          child: _Tile(
            icon: toggle.icon,
            title: toggle.title,
            onTap: () => onChanged(!toggle.value),
            trailing: Switch.adaptive(value: toggle.value, onChanged: onChanged),
          ),
        ),
      ),
    );
  }
}

/// Heading of a group in the sidebar.
class _SideLabel extends StatelessWidget {
  const _SideLabel(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(HzSpace.s8, HzSpace.s24, HzSpace.s8, HzSpace.s4),
    child: Semantics(
      header: true,
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: context.hz.text, fontWeight: FontWeight.w600, letterSpacing: 0.5),
      ),
    ),
  );
}

/// Row of the sidebar: icon and text, the selection as a tinted surface.
class _SideRow extends StatelessWidget {
  const _SideRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.tooltip,
    this.trailing,
    this.selected = false,
    this.enabled = true,
    this.danger = false,
    this.muted = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? tooltip;
  final Widget? trailing;
  final bool selected;
  final bool enabled;
  final bool danger;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final color = danger ? hz.critical : (selected ? hz.accentText : (muted ? hz.textFaint : hz.textMuted));
    final row = Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? hz.accentTint : Colors.transparent,
        borderRadius: const BorderRadius.all(Radius.circular(HzSpace.s8)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            // Dense with a pointer, a bit taller on touch: wide rows are hit reliably
            // even below 44 points, and the menu stays readable as a whole.
            constraints: BoxConstraints(minHeight: context.hzTheme.density == HorizontDensity.touch ? 38 : 32),
            child: Opacity(
              opacity: enabled ? 1 : 0.4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: HzSpace.s8, vertical: HzSpace.s4),
                child: Row(
                  spacing: HzSpace.s8,
                  children: [
                    Icon(icon, size: 18, color: color),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: color, fontWeight: selected ? FontWeight.w600 : null),
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? row : Tooltip(message: tooltip!, child: row);
  }
}

/// Group: label with a counter, rows with hairlines below. No tile: the lines
/// provide the structure.
class _Section extends StatelessWidget {
  const _Section({this.title, required this.children, required this.dense, this.count});

  final String? title;

  /// Counter next to the label when not every row counts.
  final int? count;
  final List<Widget> children;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final line = context.hz.line;
    return Padding(
      padding: EdgeInsets.only(bottom: dense ? Gap.inner : Gap.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: EdgeInsetsDirectional.only(start: _Tile.inset, bottom: dense ? HzSpace.s4 : HzSpace.s8),
              child: Kennung(title!, count: count ?? children.length),
            ),
          Divider(height: Lines.hairline, thickness: Lines.hairline, color: line),
          for (final (i, c) in children.indexed) ...[
            if (i > 0) Divider(height: Lines.hairline, thickness: Lines.hairline, indent: _Tile.textStart, color: line),
            c,
          ],
          Divider(height: Lines.hairline, thickness: Lines.hairline, color: line),
        ],
      ),
    );
  }
}

/// Row: muted icon, title, optional subtitle. Dangerous actions (disconnect,
/// clear) carry symbol and word in critical.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.tooltip,
    this.trailing,
    this.chevron = false,
    this.enabled = true,
    this.danger = false,
    this.dense = false,
    this.selected = false,
  });

  /// Open tool (sidebar on tool pages): tint with a line.
  final bool selected;

  /// Compact (popover, sidebar): title one step smaller.
  final bool dense;

  /// Left padding; the labels align with it too.
  static const inset = HzSpace.s12;
  static const _iconSize = 20.0;

  /// Start of the text: the divider begins here.
  static const textStart = inset + _iconSize + HzSpace.s12;

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? tooltip;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool chevron;
  final bool enabled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final row = Opacity(
      opacity: enabled ? 1 : 0.4,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: context.hzTheme.rowHeight),
        child: Padding(
          // The selection line at the start counts towards [inset].
          padding: const EdgeInsetsDirectional.fromSTEB(inset - Lines.selection, HzSpace.s8, HzSpace.s8, HzSpace.s8),
          child: Row(
            children: [
              Icon(icon, size: _iconSize, color: danger ? hz.critical : hz.textMuted),
              const SizedBox(width: HzSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: (dense ? theme.textTheme.bodyMedium : theme.textTheme.bodyLarge)?.copyWith(
                        color: danger ? hz.critical : hz.text,
                      ),
                    ),
                    if (subtitle != null)
                      Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
                  ],
                ),
              ),
              ?trailing,
              if (chevron) Icon(AppIcons.next, color: hz.textFaint),
            ],
          ),
        ),
      ),
    );
    return HorizontSelectable(
      selected: selected,
      onTap: enabled ? onTap : null,
      padding: EdgeInsets.zero,
      minHeight: 0,
      child: tooltip == null ? row : Tooltip(message: tooltip!, child: row),
    );
  }
}
