import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../l10n/locale_controller.dart';
import '../model/expert_mode.dart';
import '../model/plan.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'figure_box.dart';
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

/// A page that gathers entries of one kind, so the menu shows one row instead of many
/// (the checks, everything around a fault, the customer papers, the setup).
enum ToolHub {
  /// Checks of single aspects of the installation: rooms, locks, heating, DALI, security …
  checks(ToolGroup.check, 1),

  /// When something is wrong: diagnostics, fault hunt, reporting, the diagnostics package.
  troubleshooting(ToolGroup.check, 5),

  /// What the customer gets on paper: file, reports, handover, manual.
  papers(ToolGroup.documents, 0),

  /// What is set up once: project, teach-in, Home Assistant, company, backup, app lock.
  setup(ToolGroup.data, 0);

  const ToolHub(this.group, this.order);

  /// Where the hub's row stands in the menu.
  final ToolGroup group;
  final int order;

  String get title => switch (this) {
    checks => s.menuHubChecks,
    troubleshooting => s.menuHubTroubleshooting,
    papers => s.menuHubPapers,
    setup => s.menuHubSetup,
  };

  String get subtitle => switch (this) {
    checks => s.menuHubChecksHint,
    troubleshooting => s.menuHubTroubleshootingHint,
    papers => s.menuHubPapersHint,
    setup => s.menuHubSetupHint,
  };

  IconData get icon => switch (this) {
    checks => AppIcons.projectCheck,
    troubleshooting => AppIcons.diagnostics,
    papers => AppIcons.customers,
    setup => AppIcons.tools,
  };
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
    this.hub,
  });

  /// The page this tool is listed on instead of the menu itself ([ToolHub]); `null`: in the menu.
  final ToolHub? hub;

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
    this.feature,
    this.hub,
    this.subtitle,
  });

  /// The page this action is listed on instead of the menu itself ([ToolHub]); `null`: in the menu.
  final ToolHub? hub;

  /// One line on what it does, on the hub page.
  final String? subtitle;

  /// Requires a tier: shown with its badge while locked ([onTap] opens the paywall itself).
  final Feature? feature;

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

  /// The tools of [hub] that the current mode shows, in their order.
  List<ToolEntry> hubTools(ToolHub hub) => [
    for (final t in tools)
      if (t.hub == hub && (expert || !t.expertOnly)) t,
  ]..sort((a, b) => a.order - b.order);

  /// The actions of [hub] (from [data] and [footer]).
  List<MenuAction> hubActions(ToolHub hub) => [
    for (final a in [...data, ...footer])
      if (a.hub == hub) a,
  ];

  /// Hubs with at least two entries: they get a row of their own and their entries leave the
  /// menu. A hub with a single entry would only add a tap, so that entry stays where it was.
  Set<ToolHub> get shownHubs => {
    for (final hub in ToolHub.values)
      if (hubTools(hub).length + hubActions(hub).length >= 2) hub,
  };

  /// The tools as the menu lists them: one row per shown hub, the rest as they are.
  List<ToolEntry> menuTools(BuildContext context) {
    final hubs = shownHubs;
    return [
      for (final hub in hubs)
        ToolEntry(
          icon: hub.icon,
          title: hub.title,
          subtitle: hub.subtitle,
          group: hub.group,
          order: hub.order,
          open: (context) => pushTool<void>(context, (_) => ToolHubScreen(hub: hub), hub: true),
        ),
      for (final t in tools)
        if ((expert || !t.expertOnly) && !hubs.contains(t.hub)) t,
    ];
  }

  /// [actions] without those a shown hub lists.
  List<MenuAction> menuActions(List<MenuAction> actions) {
    final hubs = shownHubs;
    return [
      for (final a in actions)
        if (!hubs.contains(a.hub)) a,
    ];
  }
}

/// The page of a [ToolHub]: its tools and actions as rows, each with one line on what it does.
/// Reads the monitor's menu afresh on every build, so locks and availability stay current.
class ToolHubScreen extends StatelessWidget {
  const ToolHubScreen({super.key, required this.hub});

  final ToolHub hub;

  Future<void> _open(BuildContext context, ToolEntry t) async {
    if (t.feature case final f? when !await unlock(context, f)) return;
    if (!context.mounted) return;
    // On top of this page, so that "Back" returns here; the bar keeps the hub marked.
    ToolShell.instance
      ..opening = hub.title
      ..fromHub = true;
    t.open(context);
    ToolShell.instance.fromHub = false;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([Plan.instance, ExpertMode.instance]),
    builder: (context, _) {
      final menu = ToolShell.instance.menu?.call();
      final tools = menu?.hubTools(hub) ?? const <ToolEntry>[];
      final actions = menu?.hubActions(hub) ?? const <MenuAction>[];
      return Scaffold(
        appBar: AppBar(title: Text(hub.title)),
        body: ListView(
          padding: Gap.page,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Widths.reading),
                child: RowCard(
                  children: [
                    for (final t in tools)
                      CardRow(
                        title: t.title,
                        meta: t.subtitle,
                        badge: switch (t.feature) {
                          final f? => lockBadge(f),
                          null => null,
                        },
                        chevron: true,
                        onTap: () => _open(context, t),
                      ),
                    for (final a in actions)
                      CardRow(
                        title: a.title,
                        meta: a.subtitle,
                        enabled: a.enabled,
                        badge: switch (a.feature) {
                          final f? => lockBadge(f),
                          null => null,
                        },
                        chevron: true,
                        onTap: a.enabled ? a.onTap : null,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
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
  /// only shows more entries. Expert mode stays fixed at the foot.
  Widget _sidebar(MoreMenu menu) {
    final tool = ModalRoute.of(context) is ToolRoute;
    final visible = menu.menuTools(context)..sort((a, b) => a.order - b.order);
    final data = menu.menuActions(menu.data);
    final footer = menu.menuActions(menu.footer);
    final hidden = expert ? 0 : menu.tools.where((t) => t.expertOnly).length;
    Widget toolRow(ToolEntry t) => HorizontSidebarItem(
      icon: t.icon,
      label: t.title,
      tooltip: t.subtitle,
      selected: t.title == widget.active,
      onTap: () => _open(t),
      trailing: switch (t.feature) {
        final f? when !Plan.instance.allows(f) => TierBadge(f.tier),
        _ => null,
      },
    );
    Widget toggleRow(MenuToggle t) => HorizontSidebarItem(
      icon: t.icon,
      label: t.title,
      onTap: () => setState(() {
        t.onChanged(!t.value);
      }),
      trailing: Switch.adaptive(
        value: t.value,
        onChanged: (v) => setState(() {
          t.onChanged(v);
        }),
      ),
    );
    return HorizontSidebar(
      width: Widths.sidebar,
      footer: switch (menu.pinned) {
        final p? => toggleRow(p),
        null => null,
      },
      children: [
        if (menu.home case final home?)
          HorizontSidebarItem(
            icon: home.icon,
            label: home.title,
            selected: home.selected && !tool,
            onTap: () {
              if (tool) Navigator.of(context).pop();
              home.onTap();
            },
          ),
        for (final g in ToolGroup.headed)
          if (visible.any((t) => t.group == g)) ...[
            HorizontSidebarLabel(g.title),
            for (final t in visible)
              if (t.group == g) toolRow(t),
          ],
        if (data.isNotEmpty || visible.any((t) => t.group == ToolGroup.data)) ...[
          HorizontSidebarLabel(s.menuGroupData),
          for (final t in visible)
            if (t.group == ToolGroup.data) toolRow(t),
          for (final a in data)
            HorizontSidebarItem(icon: a.icon, label: a.title, onTap: a.enabled ? () => _run(a.onTap) : null),
        ],
        if (menu.toggles.isNotEmpty) ...[
          HorizontSidebarLabel(s.menuGroupSettings),
          for (final t in menu.toggles) toggleRow(t),
        ],
        if (visible.any((t) => t.group == ToolGroup.learn)) ...[
          const SizedBox(height: HzSpace.s24),
          for (final t in visible)
            if (t.group == ToolGroup.learn) toolRow(t),
        ],
        if (footer.isNotEmpty) ...[
          const SizedBox(height: HzSpace.s24),
          for (final a in footer)
            HorizontSidebarItem(
              icon: a.icon,
              label: a.title,
              tone: a.danger ? HorizontSidebarTone.critical : HorizontSidebarTone.normal,
              onTap: a.enabled ? () => _run(a.onTap) : null,
              trailing: switch (a.feature) {
                final f? => lockBadge(f),
                _ => null,
              },
            ),
        ],
        // Without expert mode: say that there is more, and lead there with a tap.
        if (hidden > 0 && menu.pinned != null) ...[
          const SizedBox(height: HzSpace.s24),
          HorizontSidebarItem(
            icon: AppIcons.expert,
            label: s.menuMoreTools(hidden),
            tone: HorizontSidebarTone.muted,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final menu = widget.menu();
    if (widget.mode == _MoreMode.sidebar) return _sidebar(menu);
    final data = menu.menuActions(menu.data);
    final footer = menu.menuActions(menu.footer);
    final visible = menu.menuTools(context)
      ..sort((a, b) => a.group.index != b.group.index ? a.group.index - b.group.index : a.order - b.order);
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
                  if (data.isNotEmpty || dataTools.isNotEmpty)
                    _Section(
                      title: s.menuGroupData,
                      dense: widget.popover,
                      children: [
                        for (final t in dataTools) toolTile(t),
                        for (final a in data)
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
                  if (footer.isNotEmpty)
                    _Section(
                      dense: widget.popover,
                      children: [
                        for (final a in footer)
                          _Tile(
                            dense: widget.popover,
                            icon: a.icon,
                            title: a.title,
                            enabled: a.enabled,
                            danger: a.danger,
                            trailing: switch (a.feature) {
                              final f? => lockBadge(f),
                              _ => null,
                            },
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

  /// Open tool: tinted (with a line in the standard style).
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
          // In the standard style the selection line at the start counts towards [inset].
          padding: EdgeInsetsDirectional.fromSTEB(
            inset - (context.hzTheme.soft ? 0 : Lines.selection),
            HzSpace.s8,
            HzSpace.s8,
            HzSpace.s8,
          ),
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
