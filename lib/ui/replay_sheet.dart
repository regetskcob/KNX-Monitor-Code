import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import 'write_confirm.dart';

import '../catalog_store.dart';
import '../knx/dpt_codec.dart';
import '../knx/group_catalog.dart';
import '../knx/knx_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/bus_replay.dart';
import '../model/recording.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'address_picker.dart';
import 'common.dart';

/// Longest pause when replaying with shortened pauses.
const _shortGap = Duration(seconds: 1);

/// Replaying a recording onto the bus (expert mode): choose addresses, confirm
/// explicitly, then progress with stop.
Future<void> showReplaySheet(
  BuildContext context, {
  required Recording recording,
  required KnxTunnel tunnel,
  required String gateway,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  // While sending, close only via stop.
  isDismissible: false,
  enableDrag: false,
  constraints: const BoxConstraints(maxWidth: 640),
  builder: (_) => SafeArea(
    top: false,
    child: _ReplaySheet(recording: recording, tunnel: tunnel, gateway: gateway),
  ),
);

class _ReplaySheet extends StatefulWidget {
  const _ReplaySheet({required this.recording, required this.tunnel, required this.gateway});

  final Recording recording;
  final KnxTunnel tunnel;
  final String gateway;

  @override
  State<_ReplaySheet> createState() => _ReplaySheetState();
}

class _ReplaySheetState extends State<_ReplaySheet> {
  /// Working copy of the recording; the original stays unchanged.
  late List<Telegram> _work = List.of(widget.recording.telegrams);

  /// Changed telegrams (identity).
  final _edited = Set<Telegram>.identity();
  bool _dirty = false;

  /// Narrowing down with the monitor's filter language (address, name, value …).
  /// Selected group addresses; `null` = all.
  Set<int>? _addresses;

  bool _shorten = false;
  BusReplay? _replay;

  /// All addresses with write telegrams in the working copy.
  Set<int> get _writeAddresses => {for (final t in BusReplay.writesOf(_work)) t.destination};

  Future<void> _pickAddresses() async {
    final writes = BusReplay.writesOf(_work);
    final latest = <int, Telegram>{};
    final counts = <int, int>{};
    final history = <int, List<double>>{};
    final store = CatalogStore.instance;
    for (final t in writes) {
      latest[t.destination] = t;
      counts[t.destination] = (counts[t.destination] ?? 0) + 1;
      if (numericValue(store.dptOf(t.destination), t) case final v?) (history[t.destination] ??= []).add(v);
    }
    final all = latest.keys.toSet();
    final chosen = await pickAddresses(
      context,
      title: s.replayPickTitle,
      items: latest.values.toList(),
      initial: _addresses ?? all,
      counts: counts,
      history: history,
    );
    if (chosen == null || !mounted) return;
    setState(() => _addresses = chosen.length == all.length ? null : chosen);
  }

  bool get _hasWrites => BusReplay.writesOf(_work).isNotEmpty;

  List<Telegram> get _plan => [
    for (final t in BusReplay.writesOf(_work))
      if (_addresses?.contains(t.destination) ?? true) t,
  ];

  void _remove(Telegram t) => setState(() {
    _work.removeWhere((w) => identical(w, t));
    _dirty = true;
  });

  void _reset() => setState(() {
    _work = List.of(widget.recording.telegrams);
    _edited.clear();
    _dirty = false;
  });

  Future<void> _editValue(Telegram t) async {
    final changed = await showAdaptiveDialog<Telegram>(
      context: context,
      builder: (_) => _ValueDialog(telegram: t),
    );
    if (changed == null || !mounted) return;
    setState(() {
      _work[_work.indexWhere((w) => identical(w, t))] = changed;
      _edited.add(changed);
      _dirty = true;
    });
  }

  /// Saves the edited version as a new recording.
  Future<void> _saveCopy() async {
    final messenger = ScaffoldMessenger.of(context);
    final copy = widget.recording.copyWith(name: s.replayCopyName(widget.recording.name), telegrams: _work);
    await RecordingStore.instance.save(copy);
    if (!mounted) return;
    setState(() => _dirty = false);
    messenger.showSnackBar(SnackBar(content: Text(s.recordingSaved(copy.name, copy.telegrams.length))));
  }

  @override
  void dispose() {
    _replay?.stop();
    _replay?.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final plan = _plan;
    final ok = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(s.replayConfirmTitle),
        content: Text(s.replayConfirmText(plan.length, {for (final t in plan) t.destination}.length, widget.gateway)),
        actions: [
          horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context, false)),
          horizontDialogAction(
            context,
            label: s.replaySend(plan.length),
            primary: true,
            destructive: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (!await confirmReplay(context) || !mounted) return;
    final replay = BusReplay.overTunnel(widget.tunnel, plan, maxGap: _shorten ? _shortGap : null);
    setState(() => _replay = replay);
    replay.run();
  }

  @override
  Widget build(BuildContext context) {
    final replay = _replay;
    return PopScope(
      canPop: replay == null || !replay.running,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.gutter, Gap.section, Gap.gutter, Gap.gutter),
          child: replay == null ? _setup(context) : _progress(context, replay),
        ),
      ),
    );
  }

  Widget _setup(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final recorded = widget.recording.gateway;
    final otherGateway = recorded != null && recorded != widget.gateway;
    final plan = _plan;
    return SizedBox(
      // Fixed height: the list scrolls, send stays visible at the bottom.
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.replayTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: Gap.item),
          Expanded(
            child: ListView.builder(
              itemCount: plan.length + 1,
              itemBuilder: (context, i) {
                if (i > 0) {
                  final t = plan[i - 1];
                  return _EditRow(
                    telegram: t,
                    offset: t.time.difference(widget.recording.started),
                    edited: _edited.contains(t),
                    onEdit: () => _editValue(t),
                    onRemove: () => _remove(t),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    HorizontNotice(HorizontStatus.warning, child: Text(s.replayWarning)),
                    if (otherGateway) ...[
                      const SizedBox(height: Gap.item),
                      HorizontNotice(HorizontStatus.info, child: Text(s.replayOtherGateway(recorded, widget.gateway))),
                    ],
                    const SizedBox(height: Gap.section),
                    if (!_hasWrites)
                      Text(s.replayNoWrites, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted))
                    else ...[
                      // Selection as in the dashboard: sections, cards with values, check marks.
                      OutlinedButton.icon(
                        onPressed: _pickAddresses,
                        icon: const Icon(AppIcons.filter),
                        label: Text(
                          _addresses == null
                              ? s.replayAddressesAll(_writeAddresses.length)
                              : s.replayAddressesSome(_addresses!.length, _writeAddresses.length),
                        ),
                      ),
                      SwitchListTile.adaptive(
                        value: _shorten,
                        onChanged: (v) => setState(() => _shorten = v),
                        contentPadding: EdgeInsets.zero,
                        title: Text(s.replayShorten(_shortGap.inSeconds)),
                        subtitle: Text(
                          s.replayShortenHint,
                          style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                        ),
                      ),
                      HorizontSectionHeader(
                        s.replayTelegrams,
                        count: plan.length,
                        padding: const EdgeInsets.only(top: Gap.section, bottom: Gap.item),
                      ),
                      Text(s.replayEditHint, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
                      const SizedBox(height: Gap.item),
                      const Divider(height: Lines.hairline),
                    ],
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: Gap.item),
          Row(
            children: [
              if (_dirty) ...[
                TextButton(onPressed: _reset, child: Text(s.replayReset)),
                TextButton.icon(onPressed: _saveCopy, icon: const Icon(AppIcons.copy), label: Text(s.replaySaveCopy)),
              ],
              const Spacer(),
              FilledButton.icon(
                onPressed: plan.isEmpty ? null : _confirm,
                style: FilledButton.styleFrom(backgroundColor: hz.critical, foregroundColor: hz.onAccent),
                icon: const Icon(AppIcons.send),
                label: Text(s.replaySend(plan.length)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _progress(BuildContext context, BusReplay replay) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return ListenableBuilder(
      listenable: replay,
      builder: (context, _) {
        final (status, word) = switch (replay) {
          BusReplay(running: true) => (HorizontStatus.info, s.replayRunning),
          BusReplay(error: final e?) => (HorizontStatus.critical, s.replayFailed(e)),
          BusReplay(stopped: true) => (HorizontStatus.warning, s.replayStopped),
          _ => (HorizontStatus.positive, s.replayDone),
        };
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.replayTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: Gap.item),
            HorizontNotice(status, child: Text(word)),
            const SizedBox(height: Gap.section),
            LinearProgressIndicator(value: replay.progress, color: hz.accent, backgroundColor: hz.sunken),
            const SizedBox(height: Gap.section),
            HorizontMetricRow(
              children: [
                HorizontMetric(label: s.replaySent, value: formatInt(replay.sent)),
                HorizontMetric(
                  label: s.replayUnconfirmed,
                  value: formatInt(replay.failed),
                  status: replay.failed > 0 ? HorizontStatus.warning : null,
                ),
                HorizontMetric(label: s.replayTotal, value: formatInt(replay.telegrams.length)),
              ],
            ),
            const SizedBox(height: Gap.section),
            replay.running
                ? OutlinedButton.icon(
                    onPressed: replay.stop,
                    icon: const Icon(AppIcons.stop),
                    label: Text(s.replayStop),
                  )
                : FilledButton(onPressed: () => Navigator.pop(context), child: Text(s.commonClose)),
          ],
        );
      },
    );
  }
}

/// A write telegram in the replay: point in time in the recording, address with
/// name, value. Tapping changes the value, remove on the right.
class _EditRow extends StatelessWidget {
  const _EditRow({
    required this.telegram,
    required this.offset,
    required this.edited,
    required this.onEdit,
    required this.onRemove,
  });

  final Telegram telegram;
  final Duration offset;
  final bool edited;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final data = context.hzTheme.data;
    final store = CatalogStore.instance;
    final t = telegram;
    final seconds = (offset.inMilliseconds / 1000).toStringAsFixed(1);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: hz.line, width: Lines.hairline),
        ),
      ),
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: HzSpace.s4),
          child: Row(
            children: [
              SizedBox(
                width: HzSpace.s64,
                child: Text('+$seconds s', style: data.copyWith(color: hz.textMuted)),
              ),
              Expanded(
                child: AddressTitle(
                  '${formatGroup(t.destination)}  ${store.info(t.destination)?.name ?? ''}',
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: Gap.item),
              if (edited) ...[
                Icon(AppIcons.edit, size: 14, color: hz.textMuted, semanticLabel: s.replayEdited),
                const SizedBox(width: HzSpace.s4),
              ],
              Text(store.value(t), style: data.copyWith(color: edited ? hz.accentText : null)),
              IconButton(
                tooltip: s.replayRemove,
                onPressed: onRemove,
                icon: Icon(AppIcons.close, color: hz.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// New value for a write telegram: by DPT, without a DPT as hex bytes.
class _ValueDialog extends StatefulWidget {
  const _ValueDialog({required this.telegram});

  final Telegram telegram;

  @override
  State<_ValueDialog> createState() => _ValueDialogState();
}

class _ValueDialogState extends State<_ValueDialog> {
  late final Dpt? _dpt = () {
    final d = CatalogStore.instance.dptOf(widget.telegram.destination);
    return d != null && canEncodeDpt(d) ? d : null;
  }();

  // Fully selected: typing replaces the old value.
  late final _field = TextEditingController(text: _initial())
    ..selection = TextSelection(baseOffset: 0, extentOffset: _initial().length);
  String? _error;

  String _initial() {
    final t = widget.telegram;
    final d = _dpt;
    if (d == null) return hex(t.data);
    if (d.main == 1) return '${t.data.isEmpty ? 0 : t.data[0] & 1}';
    return CatalogStore.instance.value(t);
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _apply() {
    final t = widget.telegram;
    final d = _dpt;
    final encoded = d != null ? encodeForDpt(d, _field.text) : _parseHex(_field.text, small: t.isSmall);
    if (encoded == null) {
      setState(() => _error = s.replayInvalidValue);
      return;
    }
    final changed = t.withValue(small: encoded.small, data: encoded.data);
    // Same value: mark nothing as changed.
    final same = changed.isSmall == t.isSmall && listEquals(changed.data, t.data);
    Navigator.pop(context, same ? null : changed);
  }

  static ({int? small, List<int> data})? _parseHex(String input, {required bool small}) {
    final parts = input.trim().split(RegExp(r'[\s,]+')).where((p) => p.isNotEmpty);
    final bytes = [for (final p in parts) int.tryParse(p, radix: 16)];
    if (bytes.isEmpty || bytes.any((b) => b == null || b < 0 || b > 0xFF)) return null;
    if (small) return bytes.length == 1 && bytes[0]! <= 0x3F ? (small: bytes[0], data: const []) : null;
    return (small: null, data: [for (final b in bytes) b!]);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.telegram;
    final d = _dpt;
    final hint = d == null ? s.replayHexHint : (dptInputHint(d) ?? dptUnit(d));
    return AlertDialog.adaptive(
      title: Text(formatGroup(t.destination)),
      content: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.only(top: Gap.item),
          child: TextField(
            controller: _field,
            autofocus: true,
            autocorrect: false,
            style: context.hzTheme.data,
            onSubmitted: (_) => _apply(),
            decoration: InputDecoration(
              helperMaxLines: 2,
              helperText: [
                ?CatalogStore.instance.info(t.destination)?.name,
                if (d != null) 'DPT $d',
                if (hint.isNotEmpty) hint,
              ].join(metaSeparator),
              errorText: _error,
            ),
          ),
        ),
      ),
      actions: [
        horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context)),
        horizontDialogAction(context, label: s.commonSave, primary: true, onPressed: _apply),
      ],
    );
  }
}
