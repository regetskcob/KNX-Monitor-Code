import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/group_catalog.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../theme/tokens.dart';

/// Corrects the name of a project group address (e.g. a typo) or reverts it to the project. The
/// correction goes back to the ETS with the group address import in "Tasks for the ETS".
Future<void> renameGroup(BuildContext context, int address) async {
  final store = CatalogStore.instance;
  final project = store.project[address];
  if (project == null) return;
  final result = await showDialog<_Rename>(
    context: context,
    builder: (_) => _RenameDialog(address: address, project: project.name, current: store.names[address]),
  );
  if (result == null) return;
  await store.setName(address, result.name);
}

/// Result of the rename dialog; `name == null` reverts to the project.
typedef _Rename = ({String? name});

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.address, required this.project, required this.current});

  final int address;
  final String project;
  final String? current;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _name = TextEditingController(text: widget.current ?? widget.project);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(s.groupRenameTitle(formatGroup(widget.address))),
    content: TextField(
      controller: _name,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: s.groupRenameField,
        helperText: s.groupRenameHelp(widget.project),
        helperMaxLines: 4,
      ),
      onSubmitted: (text) => Navigator.pop(context, (name: text)),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(s.commonCancel)),
      if (widget.current != null)
        TextButton(onPressed: () => Navigator.pop(context, (name: null)), child: Text(s.groupRenameRevert)),
      FilledButton(onPressed: () => Navigator.pop(context, (name: _name.text)), child: Text(s.commonSave)),
    ],
  );
}

/// Renames found in the project's group address names when [find] is replaced with [replace]:
/// address → new name, based on the names currently shown (including earlier corrections).
/// Case-sensitive, like the ETS. Only real changes: replacing a text with itself finds nothing.
Map<int, String> replaceInNames(GroupCatalog project, Map<int, String> names, String find, String replace) {
  if (find.isEmpty || find == replace) return const {};
  return {
    for (final g in project.groups.values)
      if ((names[g.address] ?? g.name) case final name when name.contains(find))
        g.address: name.replaceAll(find, replace),
  };
}

/// Search and replace across all group address names of the project, e.g. a typo repeated over
/// many addresses. Shows how many addresses change before saving.
Future<void> replaceGroupNames(BuildContext context) async {
  final store = CatalogStore.instance;
  final changes = await showDialog<Map<int, String>>(context: context, builder: (_) => const _ReplaceDialog());
  if (changes == null || changes.isEmpty) return;
  await store.setNames(changes);
  if (context.mounted) showHorizontMessage(context, s.groupReplaceDone(changes.length));
}

class _ReplaceDialog extends StatefulWidget {
  const _ReplaceDialog();

  @override
  State<_ReplaceDialog> createState() => _ReplaceDialogState();
}

class _ReplaceDialogState extends State<_ReplaceDialog> {
  final _find = TextEditingController();
  final _replace = TextEditingController();

  @override
  void dispose() {
    _find.dispose();
    _replace.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = CatalogStore.instance;
    final changes = replaceInNames(store.project, store.names, _find.text, _replace.text);
    final examples = (changes.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).take(3);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(s.groupReplaceTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.item,
        children: [
          TextField(
            controller: _find,
            autofocus: true,
            autocorrect: false,
            decoration: InputDecoration(labelText: s.groupReplaceFind),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            controller: _replace,
            autocorrect: false,
            decoration: InputDecoration(labelText: s.groupReplaceWith),
            onChanged: (_) => setState(() {}),
          ),
          Text(
            _find.text.isEmpty ? s.groupReplaceHint : s.groupReplaceCount(changes.length),
            style: theme.textTheme.bodySmall,
          ),
          for (final MapEntry(key: address, value: name) in examples)
            Text('${formatGroup(address)}  $name', style: theme.textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.commonCancel)),
        FilledButton(
          onPressed: changes.isEmpty ? null : () => Navigator.pop(context, changes),
          child: Text(s.groupReplaceApply),
        ),
      ],
    );
  }
}
