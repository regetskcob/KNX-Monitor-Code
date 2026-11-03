import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/filter.dart';
import '../model/telegram_log.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'value_board.dart';

/// Picks group addresses, modelled on the dashboard: sections with cards (name,
/// value, history), a checkbox per card and per section, and a filter at the
/// top. Returns the selection, or `null` if cancelled.
Future<Set<int>?> pickAddresses(
  BuildContext context, {
  required String title,
  required List<Telegram> items,
  required Set<int> initial,
  Map<int, int> counts = const {},
  Map<int, List<double>> history = const {},
  TelegramLog? log,
  int? max,
}) => Navigator.of(context).push<Set<int>>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _AddressPicker(
      title: title,
      items: [...items]..sort((a, b) => a.destination.compareTo(b.destination)),
      initial: initial,
      counts: counts,
      history: history,
      log: log,
      max: max,
    ),
  ),
);

class _AddressPicker extends StatefulWidget {
  const _AddressPicker({
    required this.title,
    required this.items,
    required this.initial,
    required this.counts,
    required this.history,
    required this.log,
    required this.max,
  });

  final String title;
  final List<Telegram> items;
  final Set<int> initial;
  final Map<int, int> counts;
  final Map<int, List<double>> history;
  final TelegramLog? log;
  final int? max;

  @override
  State<_AddressPicker> createState() => _AddressPickerState();
}

class _AddressPickerState extends State<_AddressPicker> {
  late final Set<int> _chosen = {...widget.initial};
  TelegramFilter _filter = TelegramFilter.empty;
  late final TelegramLog _filterLog = widget.log ?? TelegramLog();

  @override
  void dispose() {
    if (widget.log == null) _filterLog.dispose();
    super.dispose();
  }

  bool get _full => widget.max != null && _chosen.length >= widget.max!;

  void _toggle(Telegram t) => setState(() {
    if (!_chosen.remove(t.destination) && !_full) _chosen.add(t.destination);
  });

  void _toggleGroup(List<Telegram> group) => setState(() {
    final all = group.every((t) => _chosen.contains(t.destination));
    for (final t in group) {
      if (all) {
        _chosen.remove(t.destination);
      } else if (!_full) {
        _chosen.add(t.destination);
      }
    }
  });

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final visible = [
      for (final t in widget.items)
        if (_filter.matches(t, _filterLog)) t,
    ];
    final selection = Set<Telegram>.identity()..addAll(widget.items.where((t) => _chosen.contains(t.destination)));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: s.commonCancel,
          onPressed: () => Navigator.pop(context),
          icon: const Icon(AppIcons.close),
        ),
        title: Text(widget.title),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context, _chosen), child: Text(s.pickerApply(_chosen.length))),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(HzSpace.s64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, HzSpace.s8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    style: context.hzTheme.data,
                    autocorrect: false,
                    onChanged: (q) => setState(() => _filter = TelegramFilter.parse(q)),
                    decoration: InputDecoration(prefixIcon: const Icon(AppIcons.search), hintText: s.filterHintProject),
                  ),
                ),
                const SizedBox(width: Gap.item),
                // Counter in Monaspace: selected / available (or maximum).
                Text(
                  '${_chosen.length} / ${widget.max ?? widget.items.length}',
                  style: context.hzTheme.data.copyWith(color: _full ? hz.warning : hz.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
      body: visible.isEmpty
          ? HorizontEmptyHint(icon: AppIcons.search, text: s.pickerEmpty)
          : ValueBoard(
              items: visible,
              counts: widget.counts,
              history: widget.history,
              log: widget.log,
              selection: selection,
              onTap: _toggle,
              onLongPress: _toggle,
              onSelectGroup: _toggleGroup,
            ),
    );
  }
}
