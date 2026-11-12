import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/group_catalog.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// Picks group addresses from the project or the taught-in names: the picked ones on top, then
/// [suggested] ones, then the rest. An address the catalog does not know can be typed. [subject]
/// says what the addresses are for. Returns the selection in the order picked, or `null` if
/// cancelled.
Future<List<int>?> pickGroupAddresses(
  BuildContext context, {
  required String title,
  List<int> initial = const [],
  List<int> suggested = const [],
  int max = 12,
}) => Navigator.of(context).push<List<int>>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _GroupAddressPicker(subject: title, initial: initial, suggested: suggested, max: max),
  ),
);

class _GroupAddressPicker extends StatefulWidget {
  const _GroupAddressPicker({required this.subject, required this.initial, required this.suggested, required this.max});

  final String subject;
  final List<int> initial;
  final List<int> suggested;
  final int max;

  @override
  State<_GroupAddressPicker> createState() => _GroupAddressPickerState();
}

class _GroupAddressPickerState extends State<_GroupAddressPicker> {
  late final _picked = [...widget.initial];
  String _query = '';

  /// The catalog in address order, sorted once: the list is rebuilt on every keystroke.
  late final _sorted = CatalogStore.instance.catalog.groups.values.toList()
    ..sort((a, b) => a.address.compareTo(b.address));

  bool get _changed => !listEquals(_picked, widget.initial);
  bool get _full => _picked.length >= widget.max;

  void _toggle(int address) => setState(() {
    if (!_picked.remove(address) && !_full) _picked.add(address);
  });

  /// Leaving with a changed selection asks first; saving does not.
  Future<void> _leave() async {
    final navigator = Navigator.of(context);
    if (_changed) {
      final discard = await showAdaptiveDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog.adaptive(
          title: Text(s.floorPickDiscardTitle),
          actions: [
            horizontDialogAction(dialog, label: s.commonCancel, onPressed: () => Navigator.pop(dialog, false)),
            horizontDialogAction(
              dialog,
              label: s.floorPickDiscard,
              destructive: true,
              onPressed: () => Navigator.pop(dialog, true),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    navigator.pop();
  }

  Widget _row(int address, GroupInfo? info, {bool hint = false}) {
    final on = _picked.contains(address);
    return CheckboxListTile.adaptive(
      key: ValueKey(address),
      value: on,
      enabled: on || !_full,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(info?.name ?? formatGroup(address)),
      subtitle: Text(
        [formatGroup(address), ?info?.path, if (hint && !on) s.floorPickSuggested].join(' · '),
        style: TextStyle(color: context.hz.textMuted),
      ),
      onChanged: (_) => _toggle(address),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = CatalogStore.instance.catalog;
    final query = _query.trim().toLowerCase();
    bool matches(GroupInfo g) =>
        query.isEmpty ||
        g.name.toLowerCase().contains(query) ||
        (g.path ?? '').toLowerCase().contains(query) ||
        formatGroup(g.address).startsWith(query);
    final picked = {..._picked};
    final hinted = {
      for (final a in widget.suggested)
        if (catalog[a] != null) a,
    };
    final typed = parseGroup(_query.trim());
    // Picked first (always, whatever the search says), then a typed unknown address, then
    // suggestions, then the rest in address order. Built lazily: projects have thousands.
    final rows = <({int address, GroupInfo? info, bool hint})>[
      for (final a in _picked) (address: a, info: catalog[a], hint: hinted.contains(a)),
      if (typed != null && typed > 0 && typed <= 0xFFFF && catalog[typed] == null && !picked.contains(typed))
        (address: typed, info: null, hint: false),
      for (final a in hinted)
        if (!picked.contains(a) && matches(catalog[a]!)) (address: a, info: catalog[a], hint: true),
      for (final g in _sorted)
        if (!picked.contains(g.address) && !hinted.contains(g.address) && matches(g))
          (address: g.address, info: g, hint: false),
    ];
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: context.hz.textMuted);
    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: BarTitle(s.floorPickTitle),
          actions: [TextButton(onPressed: () => Navigator.pop(context, _picked), child: Text(s.commonSave))],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Widths.reading),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.gutter, Gap.inner, Gap.gutter, HzSpace.s4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: HzSpace.s8,
                    children: [
                      Text(widget.subject, style: theme.textTheme.titleMedium),
                      TextField(
                        decoration: InputDecoration(labelText: s.floorPickSearch, hintText: '1/2/3'),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          [s.floorPickCount(_picked.length, widget.max), if (_full) s.floorPickMax].join(' · '),
                          style: _full ? muted?.copyWith(color: context.hz.text) : muted,
                        ),
                      ),
                      if (catalog.isEmpty) Text(s.floorPickNoCatalog, style: muted),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, i) => _row(rows[i].address, rows[i].info, hint: rows[i].hint),
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
