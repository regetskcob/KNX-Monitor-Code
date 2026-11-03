import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../knx/group_catalog.dart';
import '../model/plan.dart';
import '../model/trigger.dart';
import '../model/watch_rules.dart';
import '../platform/addon.dart';
import '../platform/notify.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'plan_screen.dart';
import 'statistics_screen.dart' show FigureBox;

/// Turns a watcher for [address] on or off (bell in the detail sheet). Plus.
Future<void> toggleWatch(BuildContext context, int address) async {
  final rules = WatchRules.instance;
  final existing = rules.forAddress(address);
  if (existing != null) return rules.remove(existing.id);
  if (!await unlock(context, Feature.watcher) || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final rule = WatchRule(id: DateTime.now().microsecondsSinceEpoch.toRadixString(36), address: address);
  await rules.add(rule);
  await requestNotificationPermission();
  messenger.showSnackBar(SnackBar(content: Text(s.watchAdded(rule.describe()))));
}

/// All watchers: on/off, with or without sound, delete, create new.
class WatchScreen extends StatelessWidget {
  const WatchScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final rule = await showDialog<WatchRule>(context: context, builder: (_) => const _NewWatchDialog());
    if (rule == null) return;
    await WatchRules.instance.add(rule);
    await requestNotificationPermission();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final explain = Addon.embedded ? s.watchExplainServer : s.watchExplain;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.watchTitle),
        actions: [
          IconButton(tooltip: s.watchNew, onPressed: () => _add(context), icon: const Icon(AppIcons.add)),
          // With watchers the explanation sits behind the info button; the list is on top.
          ValueListenableBuilder(
            valueListenable: WatchRules.instance,
            builder: (context, rules, _) => rules.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: s.watchTitle,
                    icon: const Icon(AppIcons.info),
                    onPressed: () => showAdaptiveDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog.adaptive(
                        title: Text(s.watchTitle),
                        content: Text(explain),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(MaterialLocalizations.of(context).okButtonLabel),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: WatchRules.instance,
        builder: (context, rules, _) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Widths.reading),
            child: ListView(
              padding: Gap.page,
              children: [
                if (rules.isEmpty) ...[
                  Text(explain, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
                  const SizedBox(height: Gap.section),
                  HorizontEmptyHint(
                    icon: AppIcons.watch,
                    text: s.watchEmpty,
                    action: (label: s.watchNew, onPressed: () => _add(context)),
                  ),
                ] else ...[
                  FigureBox(
                    figures: [
                      (s.watchActive, formatInt(rules.where((r) => r.enabled).length)),
                      (s.watchTitle, formatInt(rules.length)),
                    ],
                  ),
                  const SizedBox(height: Gap.section),
                  SectionTitle(s.watchTitle, count: rules.length),
                  const SizedBox(height: HzSpace.s4),
                  for (final (i, r) in rules.indexed) ...[
                    if (i > 0) const Divider(height: Lines.hairline),
                    _RuleRow(rule: r),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.rule});

  final WatchRule rule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final rules = WatchRules.instance;
    final name = CatalogStore.instance.info(rule.address)?.name;
    final meta = theme.textTheme.bodySmall?.copyWith(color: hz.textFaint);
    final details = [
      ?rule.condition.valueText,
      // Name the sound explicitly: many do not read the bell alone as a switch;
      // the switch next to it is "active".
      rule.sound ? s.watchWithSound : s.watchSilent,
    ].join(metaSeparator);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (name != null) Text(name, style: theme.textTheme.bodyLarge),
                // Only the address in Monaspace, condition and sound in the text font.
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: formatGroup(rule.address),
                        style: context.mono(meta).copyWith(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: '$metaSeparator$details'),
                    ],
                  ),
                  style: meta,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: s.watchSound,
            isSelected: rule.sound,
            onPressed: () => rules.replace(rule.copyWith(sound: !rule.sound)),
            icon: Icon(rule.sound ? AppIcons.soundOn : AppIcons.soundOff, color: rule.sound ? hz.text : hz.textFaint),
          ),
          Tooltip(
            message: s.watchActive,
            child: Switch.adaptive(
              value: rule.enabled,
              onChanged: (v) => rules.replace(rule.copyWith(enabled: v)),
            ),
          ),
          IconButton(
            tooltip: s.watchRemove,
            onPressed: () => rules.remove(rule.id),
            icon: Icon(AppIcons.clear, color: hz.textMuted),
          ),
        ],
      ),
    );
  }
}

/// New watcher: group address (with suggestions from the project), optionally
/// a comparison with a value, with or without sound. As a normal form window,
/// also on macOS and iOS (no system alert with fields).
class _NewWatchDialog extends StatefulWidget {
  const _NewWatchDialog();

  @override
  State<_NewWatchDialog> createState() => _NewWatchDialogState();
}

class _NewWatchDialogState extends State<_NewWatchDialog> {
  final _value = TextEditingController();
  TextEditingController? _address;

  /// `null` = beliebiger Wert.
  ValueCompare? _compare;
  bool _sound = true;
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _save() {
    final address = parseGroup(_address?.text.trim() ?? '');
    if (address == null) {
      setState(() => _error = s.watchInvalid);
      return;
    }
    final value = _value.text.trim();
    Navigator.pop(
      context,
      WatchRule(
        id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
        address: address,
        value: _compare == null || value.isEmpty ? null : value,
        compare: _compare ?? ValueCompare.contains,
        sound: _sound,
      ),
    );
  }

  /// Addresses from the project whose address or name contains the input.
  Iterable<GroupInfo> _options(TextEditingValue v) {
    final q = v.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return CatalogStore.instance.catalog.groups.values
        .where((g) => formatGroup(g.address).startsWith(q) || g.name.toLowerCase().contains(q))
        .take(8);
  }

  @override
  Widget build(BuildContext context) {
    final data = context.hzTheme.data;
    final any = _compare == null;
    // Deliberately no AlertDialog.adaptive: the form with suggestion list and
    // comparison does not fit into the 270 pt wide Cupertino alert.
    return AlertDialog(
      title: Text(s.watchNew),
      content: SizedBox(
        width: Widths.form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HorizontField(
              label: s.sendGroupAddress,
              child: Autocomplete<GroupInfo>(
                optionsBuilder: _options,
                displayStringForOption: (g) => formatGroup(g.address),
                fieldViewBuilder: (context, controller, focus, submit) {
                  _address = controller;
                  return TextField(
                    controller: controller,
                    focusNode: focus,
                    autofocus: true,
                    autocorrect: false,
                    style: data,
                    decoration: InputDecoration(hintText: s.watchAddressHint, errorText: _error),
                    onSubmitted: (_) => _save(),
                  );
                },
                optionsViewBuilder: (context, select, options) => Align(
                  alignment: AlignmentDirectional.topStart,
                  // Line instead of shadow: surface with a hairline outline.
                  child: Material(
                    color: context.hz.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: Radii.tile,
                      side: BorderSide(color: context.hz.line, width: Lines.hairline),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: Widths.form, maxHeight: 280),
                      child: ListView(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        children: [
                          for (final g in options)
                            ListTile(
                              dense: true,
                              title: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(formatGroup(g.address), style: data),
                              onTap: () => select(g),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Gap.inner),
            HorizontField(
              label: s.watchCondition,
              child: Row(
                spacing: HzSpace.s8,
                children: [
                  Expanded(
                    child: HorizontFieldDropdown<ValueCompare?>(
                      value: _compare,
                      onChanged: (v) => setState(() => _compare = v),
                      items: [(null, s.watchAnyValue), for (final c in ValueCompare.values) (c, c.symbol)],
                    ),
                  ),
                  // Value only with a comparison; "beliebiger Wert" (any value) reports every telegram.
                  // Hidden instead of disabled: a disabled field looked like an empty one.
                  if (!any)
                    Expanded(
                      child: TextField(
                        controller: _value,
                        autocorrect: false,
                        style: data,
                        decoration: InputDecoration(hintText: s.watchValueExample),
                        onSubmitted: (_) => _save(),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Gap.item),
            Row(
              children: [
                Expanded(child: Text(s.watchSound)),
                Switch.adaptive(value: _sound, onChanged: (v) => setState(() => _sound = v)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.commonCancel)),
        FilledButton(onPressed: _save, child: Text(s.watchCreate)),
      ],
    );
  }
}
