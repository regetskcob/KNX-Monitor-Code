import 'dart:async';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../export/pdf_export.dart';
import '../knx/knx_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/commissioning.dart';
import '../model/customer.dart';
import '../model/dali.dart';
import '../model/plan.dart';
import '../model/sound_ack.dart';
import '../model/telegram_log.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'acceptance_screen.dart';
import 'device_sheet.dart';
import 'dali_commissioning_screen.dart';
import 'figure_box.dart';
import 'plan_screen.dart';
import 'send_sheet.dart';
import 'sound_ack_screen.dart' show confirmAckSound;
import 'telegram_row.dart';

/// Which check items the list shows.
enum _Filter { all, open, noAnswer, issue, done }

/// Entries in the header menu.
enum _Menu { readAll, rollCall, daliGroups, acceptance, restart }

/// Commissioning checklist: reads status addresses, responses are checked off,
/// the rest is rated by hand; report as PDF.
class CommissioningScreen extends StatefulWidget {
  const CommissioningScreen({super.key, required this.tunnel, this.gateway, this.log, this.onFilter});

  final KnxTunnel tunnel;
  final String? gateway;

  /// Monitor traffic, used for the device drawings in the details.
  final TelegramLog? log;

  /// Sets the monitor's filter from a device sheet opened here ("Filter in monitor", its line).
  final ValueChanged<String>? onFilter;

  @override
  State<CommissioningScreen> createState() => _CommissioningScreenState();
}

class _CommissioningScreenState extends State<CommissioningScreen> {
  final _c = Commissioning.instance;
  _Filter _filter = _Filter.all;
  bool _allGroups = false;

  /// Check item in the right column (wide).
  int? _selected;

  /// From this width on, list and details side by side.
  static const _detailFrom = Breakpoints.large;

  /// Width of the detail column: room for the device drawing.
  static const _detailWidth = Widths.form + HzSpace.s32;

  @override
  void initState() {
    super.initState();
    _c.load();
  }

  /// Status addresses without a linked device cannot respond, so like the
  /// health check they are not included (only if the project contains links,
  /// i.e. not for a plain CSV import).
  List<int> _scopeAddresses() => commissioningScope(all: _allGroups);

  void _start() {
    unawaited(CustomerStore.instance.note(VisitKind.commissioning));
    _c.prepare(_scopeAddresses());
    _c.read(widget.tunnel, _c.items.keys.toList());
  }

  void _readOpen() => _c.read(widget.tunnel, [
    for (final i in _c.items.values)
      if (i.state == CheckState.open || i.state == CheckState.noAnswer) i.address,
  ]);

  Future<void> _restart() async {
    final ok = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(s.commRestart),
        content: Text(s.commRestartConfirm),
        actions: [
          horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context, false)),
          horizontDialogAction(
            context,
            label: s.commRestart,
            primary: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (ok == true) _c.restart(_scopeAddresses());
  }

  /// Acceptance report (Pro) from the current state.
  Future<void> _openAcceptance() async {
    if (!await unlock(context, Feature.acceptance) || !mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => AcceptanceScreen(gateway: widget.gateway)));
  }

  /// Ring-through: adds addresses with a sending device to the list (without
  /// reading); existing items and results stay.
  void _setRollCall(bool on) {
    if (on) _c.prepare(rollCallScope());
    _c.setRollCall(on);
  }

  /// Sound on every telegram to an address in the list (audible
  /// acknowledgement, Pro).
  Future<void> _toggleTone() async {
    final ack = SoundAck.instance;
    if (ack.target is AckChecklist) return ack.stop();
    if (!await unlock(context, Feature.soundAck) || !mounted) return;
    if (!await confirmAckSound(context) || !mounted) return;
    ack.start(const AckChecklist());
  }

  bool _matches(CheckItem i) => switch (_filter) {
    _Filter.all => true,
    _Filter.open => i.state == CheckState.open,
    _Filter.noAnswer => i.state == CheckState.noAnswer,
    _Filter.issue => i.state == CheckState.issue,
    _Filter.done => i.state.done,
  };

  @override
  Widget build(BuildContext context) {
    final store = CatalogStore.instance;
    return Scaffold(
      appBar: AppBar(
        title: BarTitle(s.commTitle),
        actions: [
          ListenableBuilder(
            listenable: _c,
            builder: (context, _) => Builder(
              builder: (buttonContext) => IconButton(
                tooltip: s.commPdfTitle,
                onPressed: _c.items.isEmpty
                    ? null
                    : () => sharePdf(
                        context,
                        () async => CommissioningPdf(_c, gateway: widget.gateway),
                        pdfName(s.commPdfTitle),
                        origin: rectOf(buttonContext),
                      ),
                icon: const Icon(AppIcons.pdf),
              ),
            ),
          ),
          ListenableBuilder(listenable: _c, builder: (context, _) => _menu()),
          IconButton(
            tooltip: s.commTitle,
            onPressed: () => showInfoDialog(
              context,
              title: s.commTitle,
              content: Text('${s.commExplain}\n\n${s.commRollCallExplain}'),
            ),
            icon: const Icon(AppIcons.info),
          ),
        ],
      ),
      body: store.catalog.isEmpty
          ? HorizontEmptyHint(icon: AppIcons.projectCheck, text: s.commNoProject)
          : LayoutBuilder(
              builder: (context, box) {
                final wide = box.maxWidth >= _detailFrom;
                final selected = wide ? _selected : null;
                return ListenableBuilder(
                  listenable: _c,
                  builder: (context, _) => Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ListView(
                            padding: Gap.page,
                            children: [
                              _header(context),
                              ..._groups(context, wide: wide, selected: selected),
                            ],
                          ),
                        ),
                      ),
                      // Details on the right as soon as an item is selected.
                      if (selected != null && _c.items.containsKey(selected))
                        SizedBox(
                          width: _detailWidth,
                          child: ListView(
                            padding: Gap.page,
                            children: [
                              _ItemDetail(
                                key: ValueKey(selected),
                                address: selected,
                                tunnel: widget.tunnel,
                                log: widget.log,
                                onFilter: widget.onFilter,
                                // Rated: move on to the next open item.
                                onMarked: (state) {
                                  if (state == CheckState.open) return;
                                  setState(() => _selected = _nextOpen(selected) ?? selected);
                                },
                                onNext: _nextOpen(selected) == null
                                    ? null
                                    : () => setState(() => _selected = _nextOpen(selected)),
                                onClose: () => setState(() => _selected = null),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  /// Less frequent actions live in the menu: read all again, ring-through,
  /// acceptance report, start over.
  Widget _menu() => PopupMenuButton<_Menu>(
    tooltip: s.commonMore,
    icon: Icon(AppIcons.more),
    onSelected: (entry) => switch (entry) {
      _Menu.readAll => _start(),
      _Menu.rollCall => _setRollCall(!_c.rollCall),
      _Menu.daliGroups => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => DaliCommissioningScreen(tunnel: widget.tunnel))),
      _Menu.acceptance => _openAcceptance(),
      _Menu.restart => _restart(),
    },
    itemBuilder: (context) => [
      PopupMenuItem(value: _Menu.readAll, enabled: _c.items.isNotEmpty && !_c.running, child: Text(s.commReadAll)),
      CheckedPopupMenuItem(value: _Menu.rollCall, checked: _c.rollCall, child: Text(s.commRollCall)),
      // Switch the DALI groups one by one, where the project has a gateway with groups.
      if (DaliStore.instance.gateways.any(
        (g) => DaliStore.instance.groupsOf(g.address).any((x) => x.switchGroup != null),
      ))
        PopupMenuItem(value: _Menu.daliGroups, child: Text(s.daliCommOpen)),
      PopupMenuItem(value: _Menu.acceptance, enabled: _c.items.isNotEmpty, child: Text(s.acceptTitle)),
      PopupMenuItem(value: _Menu.restart, child: Text(s.commRestart)),
    ],
  );

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final empty = _c.items.isEmpty;
    final reopen = _c.count(CheckState.open) + _c.count(CheckState.noAnswer);
    final seen = _c.count(CheckState.seen);
    final noAnswer = _c.count(CheckState.noAnswer);
    final issue = _c.count(CheckState.issue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FigureBox(
          above: empty ? Text(s.commExplain, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)) : null,
          // Before creating the list there is nothing to count yet.
          figures: [
            if (!empty) ...[
              (label: s.commChecked, value: '${_c.checked} / ${_c.items.length}', status: null),
              (label: s.commAnswered, value: formatInt(_c.count(CheckState.answered)), status: null),
              (label: s.commOkManual, value: formatInt(_c.count(CheckState.ok)), status: null),
              (label: s.commOpen, value: formatInt(_c.count(CheckState.open)), status: null),
              // Only if there are any; otherwise keep the box quiet.
              if (seen > 0) (label: s.commSeen, value: formatInt(seen), status: null),
              if (noAnswer > 0) (label: s.commNoAnswer, value: formatInt(noAnswer), status: HorizontStatus.warning),
              if (issue > 0) (label: s.commIssue, value: formatInt(issue), status: HorizontStatus.critical),
            ],
          ],
          below: _boxOptions(empty: empty, reopen: reopen),
          action: _action(empty: empty, reopen: reopen),
        ),
        if (!empty) ...[
          const SizedBox(height: Gap.section),
          // One toggle, on a single line even on the phone (short words).
          FilterBar<_Filter>(
            segments: [
              ButtonSegment(value: _Filter.all, label: Text(s.commFilterAll)),
              ButtonSegment(value: _Filter.open, label: Text(s.commOpen)),
              ButtonSegment(value: _Filter.noAnswer, label: Text(s.commFilterNoAnswer), tooltip: s.commNoAnswer),
              ButtonSegment(value: _Filter.issue, label: Text(s.commIssue)),
              ButtonSegment(value: _Filter.done, label: Text(s.commDone)),
            ],
            selected: _filter,
            onChanged: (v) => setState(() => _filter = v),
          ),
        ],
      ],
    );
  }

  /// Main action of the box: start, cancel, read open items; during
  /// ring-through the sound, which is the main path there, reading only
  /// secondary.
  Widget _action({required bool empty, required int reopen}) {
    if (_c.running) return OutlinedButton(onPressed: _c.cancel, child: Text(s.commonCancel));
    if (empty) return FilledButton(onPressed: _start, child: Text(s.commStart(_scopeAddresses().length)));
    if (_c.rollCall) {
      return ListenableBuilder(
        listenable: SoundAck.instance,
        builder: (context, _) {
          final on = SoundAck.instance.target is AckChecklist;
          return FilledButton.icon(
            onPressed: _toggleTone,
            icon: Icon(on ? AppIcons.stop : AppIcons.ack, size: 18),
            label: Text(on ? s.commToneOff : s.commToneOn),
          );
        },
      );
    }
    return FilledButton(onPressed: reopen == 0 ? null : _readOpen, child: Text(s.commReadOpen(reopen)));
  }

  /// Below the numbers, only when needed: progress, scope before creating the
  /// list, and the ring-through switch (otherwise in the menu).
  Widget? _boxOptions({required bool empty, required int reopen}) {
    final showSwitch = empty || _c.rollCall;
    if (!_c.running && !empty && !showSwitch) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: HzSpace.s8,
      children: [
        if (_c.running)
          // Progress glides along instead of jumping.
          TweenAnimationBuilder<double>(
            tween: Tween(end: _c.progress),
            duration: Motion.calmOf(context),
            curve: Motion.settle,
            builder: (context, v, _) =>
                LinearProgressIndicator(value: v, minHeight: HzSpace.s4, borderRadius: Radii.row),
          ),
        // Ring-through: whatever is sent checks itself off.
        if (showSwitch)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(s.commRollCall),
            subtitle: SwitchHint(s.commRollCallExplain),
            value: _c.rollCall,
            onChanged: _setRollCall,
          ),
        if (empty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text(s.diagScopeStatus)),
                ButtonSegment(value: true, label: Text(s.selectAll)),
              ],
              selected: {_allGroups},
              onSelectionChanged: (v) => setState(() => _allGroups = v.first),
            ),
          ),
        if (!empty && _c.rollCall && !_c.running)
          OutlinedButton(onPressed: reopen == 0 ? null : _readOpen, child: Text(s.commReadOpen(reopen))),
      ],
    );
  }

  /// Check items by area (ETS path): title with progress, below it quiet rows
  /// (no card, no zebra stripes).
  List<Widget> _groups(BuildContext context, {required bool wide, int? selected}) {
    final store = CatalogStore.instance;
    final groups = <String, List<CheckItem>>{};
    for (final item in _c.items.values) {
      (groups[store.info(item.address)?.path ?? s.objectsOther] ??= []).add(item);
    }
    final blocks = [
      for (final MapEntry(key: path, value: all) in groups.entries)
        if (all.where(_matches).toList() case final visible when visible.isNotEmpty) (path, all, visible),
    ];
    if (blocks.isEmpty) return const [];
    // iPad landscape and Mac: areas in columns, each into the shortest one.
    return [
      const SizedBox(height: Gap.section),
      CardColumns(
        heights: [for (final (_, _, visible) in blocks) 2.0 + visible.length],
        children: [
          for (final (path, all, visible) in blocks)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Flexible(child: SectionTitle(path)),
                    const SizedBox(width: HzSpace.s8),
                    Text(
                      '${all.where((i) => i.state.done).length} / ${all.length}',
                      style: context
                          .figures(Theme.of(context).textTheme.bodyMedium)
                          .copyWith(color: context.hz.textFaint),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.item),
                for (final (i, item) in visible.indexed) ...[
                  if (i > 0) const Divider(height: Lines.hairline),
                  _CheckRow(
                    item: item,
                    selected: item.address == selected,
                    onTap: () => _openItem(item, wide: wide),
                  ),
                ],
              ],
            ),
        ],
      ),
    ];
  }

  /// Opens a check item: in the right column when wide, otherwise as a sheet.
  void _openItem(CheckItem item, {required bool wide}) {
    if (wide) {
      setState(() => _selected = item.address);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      // Wider than the default (640), which otherwise looks lost on an iPad in
      // landscape.
      constraints: const BoxConstraints(maxWidth: 860),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, Gap.bottom + MediaQuery.viewInsetsOf(sheet).bottom),
          child: ListenableBuilder(
            listenable: _c,
            builder: (context, _) => _ItemDetail(
              address: item.address,
              tunnel: widget.tunnel,
              log: widget.log,
              onFilter: widget.onFilter,
              onMarked: (_) => Navigator.pop(sheet),
            ),
          ),
        ),
      ),
    );
  }

  /// Visible check items in list order (areas, then address).
  List<CheckItem> _visibleInOrder() {
    final store = CatalogStore.instance;
    final groups = <String, List<CheckItem>>{};
    for (final item in _c.items.values) {
      (groups[store.info(item.address)?.path ?? s.objectsOther] ??= []).add(item);
    }
    return [for (final all in groups.values) ...all.where(_matches)];
  }

  /// Next open (or unanswered) item after [address].
  int? _nextOpen(int address) {
    final order = _visibleInOrder();
    final start = order.indexWhere((i) => i.address == address);
    for (var k = 1; k <= order.length; k++) {
      final item = order[(start + k) % order.length];
      if (item.address != address && (item.state == CheckState.open || item.state == CheckState.noAnswer)) {
        return item.address;
      }
    }
    return null;
  }
}

/// "1.1.50 Glastaster · 14:02:11": sender and time.
String _origin(CheckItem item) {
  final store = CatalogStore.instance;
  return [
    if (item.source != null) [formatIndividual(item.source!), ?store.device(item.source!)?.name].join(' '),
    if (item.time != null) formatTime(item.time!, millis: false),
    if (item.foreign) s.commForeign,
  ].join(metaSeparator);
}

/// "21,5 °C · 1.1.50 Glastaster · 14:02:11"; the state "Beantwortet" (answered)
/// is already shown by the icon on the right, all others also in the text.
String _detail(CheckItem item) => [
  if (item.state != CheckState.answered) _label(item.state),
  ?item.value,
  if (_origin(item) case final origin when origin.isNotEmpty) origin,
].join(metaSeparator);

String _label(CheckState state) => switch (state) {
  CheckState.open => s.commOpen,
  CheckState.answered => s.commAnswered,
  CheckState.seen => s.commSeen,
  CheckState.noAnswer => s.commNoAnswer,
  CheckState.ok => s.commOk,
  CheckState.issue => s.commIssue,
};

/// State of a check item as a Horizont state (icon + color).
HorizontStatus _status(CheckState state) => switch (state) {
  CheckState.answered || CheckState.seen || CheckState.ok => HorizontStatus.positive,
  CheckState.noAnswer => HorizontStatus.warning,
  CheckState.issue => HorizontStatus.critical,
  CheckState.open => HorizontStatus.neutral,
};

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.item, required this.onTap, this.selected = false});

  final CheckItem item;
  final VoidCallback onTap;

  /// Open in the detail column: tinted.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final store = CatalogStore.instance;
    final status = item.foreign && item.state.done ? HorizontStatus.warning : _status(item.state);
    final detail = [if (item.state != CheckState.open) _detail(item), ?item.note].join(metaSeparator);
    return HorizontSelectable(
      selected: selected,
      onTap: onTap,
      // In the standard style the leading line counts as part of the edge: icons stay at 4.
      padding: EdgeInsetsDirectional.fromSTEB(
        HzSpace.s4 - (context.hzTheme.soft ? 0 : Lines.selection),
        HzSpace.s12,
        HzSpace.s4,
        HzSpace.s12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AddressTitle('${formatGroup(item.address)}  ${store.info(item.address)?.name ?? ''}'),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Gap.item),
          // A response checks off the item: the icon changes calmly with a
          // slight spring.
          AnimatedSwitcher(
            duration: Motion.calmOf(context),
            switchInCurve: Motion.settle,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(scale: Tween(begin: 0.6, end: 1.0).animate(a), child: child),
            ),
            child: Icon(
              status.icon,
              key: ValueKey(item.state),
              size: HzIconSize.row,
              color: status.color(hz),
              semanticLabel: _label(item.state),
            ),
          ),
          const SizedBox(width: HzSpace.s4),
          Icon(AppIcons.next, size: HzIconSize.row, color: hz.textFaint),
        ],
      ),
    );
  }
}

/// A check item in detail, in the sheet (narrow) and in the right column
/// (wide): state and response, rating, read and write, note, and the linked
/// devices with the channel of this address.
class _ItemDetail extends StatefulWidget {
  const _ItemDetail({
    super.key,
    required this.address,
    required this.tunnel,
    required this.log,
    required this.onMarked,
    this.onFilter,
    this.onNext,
    this.onClose,
  });

  final int address;
  final KnxTunnel tunnel;
  final TelegramLog? log;
  final ValueChanged<String>? onFilter;

  /// After "In Ordnung" (OK), "Problem" or "Zurücksetzen" (reset): close the
  /// sheet or move to the next open item.
  final ValueChanged<CheckState> onMarked;

  /// Next open item; `null` in the sheet or when none is open anymore.
  final VoidCallback? onNext;

  /// Closes the column; `null` in the sheet.
  final VoidCallback? onClose;

  @override
  State<_ItemDetail> createState() => _ItemDetailState();
}

class _ItemDetailState extends State<_ItemDetail> {
  final _c = Commissioning.instance;
  late final _note = TextEditingController(text: _c.items[widget.address]?.note ?? '');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _mark(CheckState state) {
    _c.setNote(widget.address, _note.text);
    _c.mark(widget.address, state);
    widget.onMarked(state);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final store = CatalogStore.instance;
    final item = _c.items[widget.address];
    if (item == null) return const SizedBox.shrink();
    final log = widget.log;
    // Each device once, sender (sending object) first.
    final links = [...?store.catalog[widget.address]?.links]..sort((a, b) => (b.sends ? 1 : 0) - (a.sends ? 1 : 0));
    final devices = <int>{for (final l in links) l.device}.toList();
    final status = _status(item.state);
    final origin = _origin(item);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      store.info(item.address)?.name ?? '',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: Gap.item),
                  Text(formatGroup(item.address), style: context.mono(theme.textTheme.bodySmall)),
                  if (widget.onClose case final close?)
                    IconButton(tooltip: s.commonClose, onPressed: close, icon: const Icon(AppIcons.close)),
                ],
              ),
              const SizedBox(height: HzSpace.s8),
              Row(
                children: [
                  Icon(status.icon, size: 18, color: status.color(hz)),
                  const SizedBox(width: HzSpace.s8),
                  Expanded(child: Text(_label(item.state), style: theme.textTheme.bodyMedium)),
                  if (item.value case final value?)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: Widths.form / 2),
                      child: Text(
                        value,
                        textAlign: TextAlign.end,
                        style: context.figures(theme.textTheme.bodyMedium).copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
              if (origin.isNotEmpty) ...[
                const SizedBox(height: HzSpace.s2),
                // The sender opens its device sheet, as in the live list.
                switch ((item.source, log)) {
                  (final source?, final log?) => DeviceLink(
                    address: source,
                    log: log,
                    onFilter: widget.onFilter,
                    child: Text(origin, style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint)),
                  ),
                  _ => Text(origin, style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint)),
                },
              ],
            ],
          ),
        ),
        const SizedBox(height: HzSpace.s12),
        SegmentedButton<CheckState>(
          showSelectedIcon: false,
          emptySelectionAllowed: true,
          segments: [
            ButtonSegment(value: CheckState.ok, label: Text(s.commOk)),
            ButtonSegment(value: CheckState.issue, label: Text(s.commIssue)),
          ],
          selected: {if (item.state == CheckState.ok || item.state == CheckState.issue) item.state},
          // "Zurücksetzen" (reset) undoes the chosen rating.
          onSelectionChanged: (v) {
            if (v.isNotEmpty) _mark(v.first);
          },
        ),
        const SizedBox(height: HzSpace.s8),
        EvenRow(
          children: [
            OutlinedButton(
              onPressed: _c.running ? null : () => _c.read(widget.tunnel, [item.address]),
              child: Text(s.commReadOne),
            ),
            OutlinedButton(
              onPressed: () => showSendSheet(context, widget.tunnel, address: item.address),
              child: Text(s.writeButton),
            ),
          ],
        ),
        Wrap(
          spacing: Gap.item,
          children: [
            TextButton(onPressed: () => _mark(CheckState.open), child: Text(s.commReset)),
            if (widget.onNext case final next?)
              TextButton.icon(onPressed: next, icon: const Icon(AppIcons.next, size: 18), label: Text(s.commNextOpen)),
          ],
        ),
        const SizedBox(height: HzSpace.s8),
        HorizontField(
          label: s.commNote,
          child: TextField(
            style: context.hzTheme.field,
            controller: _note,
            minLines: 1,
            maxLines: 4,
            onChanged: (v) => _c.setNote(widget.address, v),
          ),
        ),
        // Who is attached to the address: as in the topology's address view,
        // the device drawn and the channel of this address highlighted.
        if (log != null && devices.isNotEmpty) ...[
          const SizedBox(height: Gap.section),
          SectionTitle(s.commLinked, count: devices.length),
          const SizedBox(height: Gap.item),
          for (final d in devices) ...[
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: formatIndividual(d), style: context.mono(theme.textTheme.bodySmall)),
                  if (store.device(d)?.name case final name?) TextSpan(text: '  $name'),
                ],
              ),
              style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
            ),
            const SizedBox(height: HzSpace.s4),
            if (hasDeviceDrawing(d, widget.address))
              KeyedSubtree(
                key: ValueKey('$d-${widget.address}'),
                child: deviceDrawing(d, log, selected: channelAt(d, widget.address), onSelected: (_) {}),
              ),
            const SizedBox(height: Gap.section),
          ],
        ],
      ],
    );
  }
}
