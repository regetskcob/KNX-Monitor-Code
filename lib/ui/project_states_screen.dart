import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/project_states.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'telegram_row.dart' show formatDate;

/// First and last day the start of a state may be set to, given the starts of the states around
/// it ([CatalogStore.projectStateDateRange]) and the current time; `null` if no day is free.
({DateTime first, DateTime last})? projectStateDays(({DateTime? after, DateTime? before}) range, DateTime now) {
  final after = range.after;
  // Midnight of the day after the state before: always later than its start.
  final first = after == null ? DateTime(2000) : DateTime(after.year, after.month, after.day + 1);
  final upper = range.before != null && range.before!.isBefore(now) ? range.before! : now;
  var last = DateTime(upper.year, upper.month, upper.day);
  // The next state begins at midnight sharp: the day before is the last free one.
  if (range.before != null && !last.isBefore(range.before!)) last = DateTime(last.year, last.month, last.day - 1);
  return first.isAfter(last) ? null : (first: first, last: last);
}

/// The project states of the installation (issue #5): since when each one is valid, what it
/// changed against the one before; the date can be corrected, a state removed.
class ProjectStatesScreen extends StatefulWidget {
  const ProjectStatesScreen({super.key});

  @override
  State<ProjectStatesScreen> createState() => _ProjectStatesScreenState();
}

class _ProjectStatesScreenState extends State<ProjectStatesScreen> {
  final _store = CatalogStore.instance;

  /// Changes per state, computed when first shown (two states are rebuilt for it).
  final _changes = <int, ProjectChanges>{};

  /// State whose changes the detail side shows (wide screens).
  int? _selected;

  @override
  void initState() {
    super.initState();
    _store.addListener(_changed);
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {
    _changes.clear();
    _selected = null;
  });

  ProjectChanges _changesOf(int index) => _changes[index] ??= _store.projectChanges(index);

  static String _dateOf(ProjectState state) =>
      state.from == null ? s.projectStateFromStart : s.projectStateSince(formatDate(state.from!));

  String _summary(int index) {
    if (index == 0) return s.projectStateFirst;
    final c = _changesOf(index);
    if (c.isEmpty) return s.projectStateNoChanges;
    return [
      if (c.added.isNotEmpty) s.projectStateAdded(c.added.length),
      if (c.removed.isNotEmpty) s.projectStateRemoved(c.removed.length),
      if (c.renamed.isNotEmpty) s.projectStateRenamed(c.renamed.length),
      if (c.retyped.isNotEmpty) s.projectStateRetyped(c.retyped.length),
    ].join(metaSeparator);
  }

  Future<void> _setDate(int index) async {
    final range = _store.projectStateDateRange(index);
    if (range == null) return;
    final days = projectStateDays(range, DateTime.now());
    if (days == null) {
      showHorizontMessage(context, s.projectStateDateNoRoom, status: HorizontStatus.warning);
      return;
    }
    final from = _store.projectStates[index].from!;
    final day = DateTime(from.year, from.month, from.day);
    final picked = await showDatePicker(
      context: context,
      helpText: s.projectStateDateHelp,
      initialDate: day.isBefore(days.first) ? days.first : (day.isAfter(days.last) ? days.last : day),
      firstDate: days.first,
      lastDate: days.last,
    );
    if (picked == null || !mounted) return;
    if (!await _store.setProjectStateFrom(index, picked) && mounted) {
      showHorizontMessage(context, s.projectStateDateNoRoom, status: HorizontStatus.warning);
    }
  }

  Future<void> _remove(int index) async {
    final count = _store.projectStates.length;
    final ok = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(s.projectStateRemove),
        content: Text(
          index == count - 1
              ? s.projectStateRemoveCurrent
              : (index == 0 ? s.projectStateRemoveOldest : s.projectStateRemovePast),
        ),
        actions: [
          horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context, false)),
          horizontDialogAction(
            context,
            label: s.projectStateRemove,
            primary: true,
            destructive: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (ok == true) await _store.removeProjectState(index);
  }

  void _open(int index, {required bool wide}) {
    if (wide) {
      setState(() => _selected = index);
      return;
    }
    final state = _store.projectStates[index];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(_dateOf(state))),
          body: _ChangesList(changes: _changesOf(index), padding: Gap.page),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final states = _store.projectStates;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= Breakpoints.expanded;
    final gutter = Gap.gutterFor(width);
    // Newest first: the current project is what one looks for.
    final order = [for (var i = states.length - 1; i >= 0; i--) i];
    final selected = wide && states.length > 1 ? (_selected ?? states.length - 1) : null;

    final list = ListView(
      padding: EdgeInsets.fromLTRB(gutter, Gap.page.top, wide ? Gap.section : gutter, Gap.page.bottom),
      children: [
        Text(s.projectStatesIntro, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
        const SizedBox(height: Gap.section),
        for (final i in order)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.item),
            child: _StateTile(
              state: states[i],
              date: _dateOf(states[i]),
              summary: _summary(i),
              current: i == states.length - 1,
              selected: selected == i,
              // The oldest state has nothing before it to compare with.
              onTap: i == 0 ? null : () => _open(i, wide: wide),
              onSetDate: i == 0 ? null : () => _setDate(i),
              onRemove: states.length > 1 ? () => _remove(i) : null,
            ),
          ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text(s.projectStatesTitle)),
      body: !wide
          ? list
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Widths.wide),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: Widths.column + gutter, child: list),
                    VerticalDivider(width: Lines.hairline, thickness: Lines.hairline, color: hz.line),
                    Expanded(
                      child: selected == null || selected == 0
                          ? Center(
                              child: HorizontEmptyHint(icon: AppIcons.history, text: s.projectStateSelect),
                            )
                          : _ChangesList(
                              key: ValueKey(selected),
                              title: '${_dateOf(states[selected])}$metaSeparator${s.projectStateChanges}',
                              changes: _changesOf(selected),
                              padding: EdgeInsets.fromLTRB(Gap.section, Gap.page.top, gutter, Gap.page.bottom),
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// One state in the list: since when, which project, what changed, and its two actions.
class _StateTile extends StatelessWidget {
  const _StateTile({
    required this.state,
    required this.date,
    required this.summary,
    required this.current,
    required this.selected,
    this.onTap,
    this.onSetDate,
    this.onRemove,
  });

  final ProjectState state;
  final String date;
  final String summary;
  final bool current;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onSetDate;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final muted = theme.textTheme.bodySmall?.copyWith(color: hz.textMuted);
    final name = [state.project, state.name].whereType<String>().where((n) => n.trim().isNotEmpty).toSet();
    return Material(
      color: selected ? hz.accentTint : hz.surface,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.tile,
        side: BorderSide(color: selected ? hz.accent : hz.line, width: Lines.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.card, Gap.inner, HzSpace.s8, HzSpace.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Wrap, not Row: at large type the mark moves below the date.
              Wrap(
                spacing: HzSpace.s8,
                runSpacing: HzSpace.s4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(date, style: context.figures(theme.textTheme.titleSmall)),
                  if (current) HorizontBadge(HorizontStatus.positive, label: s.projectStateCurrent),
                ],
              ),
              const SizedBox(height: HzSpace.s4),
              Text(
                [
                  name.isEmpty ? s.projectStateUnnamed : name.join(metaSeparator),
                  s.groupAddressCount(state.count),
                ].join(metaSeparator),
                style: muted,
              ),
              const SizedBox(height: HzSpace.s2),
              Text(summary, style: context.figures(theme.textTheme.bodySmall)),
              if (onSetDate != null || onRemove != null)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    children: [
                      if (onSetDate != null) TextButton(onPressed: onSetDate, child: Text(s.projectStateSetDate)),
                      if (onRemove != null) TextButton(onPressed: onRemove, child: Text(s.projectStateRemove)),
                    ],
                  ),
                )
              else
                const SizedBox(height: HzSpace.s8),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a state changed, in four sections; built row by row (a renumbered project has thousands).
class _ChangesList extends StatelessWidget {
  const _ChangesList({super.key, required this.changes, required this.padding, this.title});

  final ProjectChanges changes;
  final EdgeInsets padding;

  /// Heading above the sections (detail side; the pushed page has it in its bar).
  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final c = changes;
    String type(Dpt? dpt) => dpt == null ? s.projectStateNoType : 'DPT $dpt';
    final muted = theme.textTheme.bodySmall?.copyWith(color: hz.textMuted);

    Widget row(int address, String name, String? below) => DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: hz.line, width: Lines.hairline),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${formatGroup(address)}  ',
                    style: context.mono(theme.textTheme.bodySmall).copyWith(color: hz.textMuted),
                  ),
                  TextSpan(text: name),
                ],
              ),
              style: theme.textTheme.bodyMedium,
            ),
            if (below != null) Text(below, style: muted),
          ],
        ),
      ),
    );

    // Flattened: a heading per section, then its rows.
    final sections = <(String, int, Widget Function(int))>[
      if (c.added.isNotEmpty)
        (
          s.projectStateAddedTitle,
          c.added.length,
          (i) => row(c.added[i].address, c.added[i].name, c.added[i].dpt == null ? null : type(c.added[i].dpt)),
        ),
      if (c.removed.isNotEmpty)
        (
          s.projectStateRemovedTitle,
          c.removed.length,
          (i) => row(c.removed[i].address, c.removed[i].name, c.removed[i].dpt == null ? null : type(c.removed[i].dpt)),
        ),
      if (c.renamed.isNotEmpty)
        (
          s.projectStateRenamedTitle,
          c.renamed.length,
          (i) => row(c.renamed[i].after.address, c.renamed[i].after.name, '← ${c.renamed[i].before.name}'),
        ),
      if (c.retyped.isNotEmpty)
        (
          s.projectStateRetypedTitle,
          c.retyped.length,
          (i) => row(
            c.retyped[i].after.address,
            c.retyped[i].after.name,
            '${type(c.retyped[i].before.dpt)} → ${type(c.retyped[i].after.dpt)}',
          ),
        ),
    ];
    final starts = <int>[];
    var total = title == null ? 0 : 1;
    for (final (_, count, _) in sections) {
      starts.add(total);
      total += count + 1;
    }
    if (sections.isEmpty) {
      return Center(
        child: HorizontEmptyHint(icon: AppIcons.history, text: s.projectStateNoChanges),
      );
    }
    return ListView.builder(
      padding: padding,
      itemCount: total,
      itemBuilder: (context, index) {
        if (title != null && index == 0) return Text(title!, style: theme.textTheme.titleMedium);
        var section = sections.length - 1;
        while (starts[section] > index) {
          section--;
        }
        final (heading, count, build) = sections[section];
        final offset = index - starts[section];
        if (offset == 0) {
          return Padding(
            padding: const EdgeInsets.only(top: Gap.section, bottom: HzSpace.s4),
            child: SectionTitle(heading, count: count),
          );
        }
        return build(offset - 1);
      },
    );
  }
}
