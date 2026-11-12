import 'dart:async';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/knx_tunnel.dart';
import '../knx/shared_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/commissioning.dart';
import '../model/dali.dart';
import '../model/dali_commissioning.dart';
import '../model/dali_labels.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'figure_box.dart';
import 'write_confirm.dart';

/// Commissioning of the DALI groups: switch one group after the other and rate what the room
/// shows. If the feedback comes from another group's status address, the assignment in the gateway
/// does not match the project, and the screen says so. Results go to the commissioning checklist
/// (and with it into its protocol).
///
/// Switching sends on the bus through the normal write path: with the notice before the first
/// write, the confirmation of the company edition, and never on a server in read-only mode.
class DaliCommissioningScreen extends StatefulWidget {
  const DaliCommissioningScreen({super.key, required this.tunnel, this.window = daliFeedbackWindow});

  final KnxTunnel tunnel;

  /// How long to wait for the feedback (tests shorten it).
  final Duration window;

  @override
  State<DaliCommissioningScreen> createState() => _DaliCommissioningScreenState();
}

class _DaliCommissioningScreenState extends State<DaliCommissioningScreen> {
  final _store = DaliStore.instance;
  final _c = Commissioning.instance;

  /// Last result per group id, and the value to send next.
  final _results = <String, DaliSwitchResult>{};
  String? _busy;

  @override
  void initState() {
    super.initState();
    unawaited(_c.load());
  }

  bool get _readOnly => widget.tunnel is SharedTunnel && (widget.tunnel as SharedTunnel).readOnly;

  Future<void> _switch(DaliGroup group) async {
    final address = group.switchGroup;
    if (address == null || _busy != null) return;
    final on = !(_results[group.id]?.on ?? false);
    final messenger = ScaffoldMessenger.of(context);
    final colors = context.hz;
    if (!await confirmWrite(context, address, small: on ? 1 : 0) || !mounted) return;
    setState(() => _busy = group.id);
    try {
      final result = await switchDaliGroup(widget.tunnel, group, on: on, window: widget.window);
      recordDaliSwitch(result);
      if (mounted) setState(() => _results[group.id] = result);
    } on KnxException catch (e) {
      messenger.showSnackBar(horizontMessageSnackBar(colors, e.message, status: HorizontStatus.critical));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _rate(DaliGroup group, CheckState state, {String? note}) {
    final address = group.switchGroup;
    if (address == null) return;
    if (!_c.items.containsKey(address)) _c.record(address, state: CheckState.open);
    _c.mark(address, state);
    if (note != null) _c.setNote(address, note);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_store, _c]),
    builder: (context, _) {
      final theme = Theme.of(context);
      final hz = context.hz;
      final gateways = [
        for (final gw in _store.gateways)
          if (_store.groupsOf(gw.address).any((g) => g.switchGroup != null)) gw,
      ];
      return Scaffold(
        appBar: AppBar(
          title: Text(s.daliCommTitle),
          actions: [InfoAction(title: s.daliCommTitle, text: s.daliCommExplain)],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Widths.wide),
            child: ListView(
              padding: Gap.page,
              children: [
                if (_readOnly) ...[
                  HorizontNotice(HorizontStatus.info, child: Text(s.daliCommReadOnly)),
                  const SizedBox(height: Gap.section),
                ],
                if (gateways.isEmpty)
                  HorizontEmptyHint(status: HorizontStatus.info, text: s.daliCommEmpty, detail: s.daliCommEmptyDetail),
                for (final gw in gateways) ...[
                  SectionHead('${daliGatewayLabel(gw)} ${formatIndividual(gw.address)}', detail: gw.location),
                  // Wide: groups in columns.
                  CardColumns(
                    gap: Gap.item,
                    children: [
                      for (final group in _store.groupsOf(gw.address))
                        if (group.switchGroup != null) _groupCard(context, group, theme, hz),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _groupCard(BuildContext context, DaliGroup group, ThemeData theme, HorizontColors hz) {
    final result = _results[group.id];
    final item = _c.items[group.switchGroup];
    final busy = _busy == group.id;
    final rated = item?.state == CheckState.ok || item?.state == CheckState.issue;
    final feedback = result?.feedback;
    final status = switch (item?.state) {
      CheckState.ok => s.daliCommRatedOk,
      CheckState.issue => item?.note ?? s.daliCommRatedIssue,
      _ => null,
    };
    final line = busy
        ? s.daliCommWaiting
        : result == null
        ? (item?.foreign ?? false ? item?.note : null) ?? s.daliCommNotSwitched(formatGroup(group.switchGroup!))
        : [
            s.daliCommSwitched(result.on ? s.dpt1On : s.dpt1Off),
            feedback == null
                ? (group.statusGroup == null && group.valueStatusGroup == null
                      ? s.daliCommNoStatusObject
                      : s.daliCommNoFeedback)
                : s.daliCommFeedback(CatalogStore.instance.value(feedback)),
          ].join(metaSeparator);
    final foreign = result?.foreign ?? (item?.foreign ?? false);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            spacing: HzSpace.s12,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      daliGroupLabel(group),
                      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(line, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: _readOnly || _busy != null ? null : () => _switch(group),
                // What the button sends next.
                child: Text((result?.on ?? false) ? s.daliCommOff : s.daliCommOn),
              ),
            ],
          ),
          if (busy) ...[const SizedBox(height: Gap.item), const LinearProgressIndicator(minHeight: HzSpace.s4)],
          if (foreign) ...[
            const SizedBox(height: Gap.item),
            HorizontNotice(
              HorizontStatus.warning,
              child: Text(result == null ? (item?.note ?? s.daliCommRatedIssue) : daliForeignText(result)),
            ),
          ],
          if (status != null && !foreign) ...[
            const SizedBox(height: Gap.item),
            HorizontStatusLine(item?.state == CheckState.ok ? HorizontStatus.positive : HorizontStatus.warning, status),
          ],
          if (result != null || rated || item != null) ...[
            const SizedBox(height: Gap.item),
            EvenRow(
              children: [
                _rateButton(s.daliCommOk, item?.state == CheckState.ok, () => _rate(group, CheckState.ok)),
                _rateButton(
                  s.daliCommWrong,
                  item?.state == CheckState.issue && item?.note == s.daliCommWrong,
                  () => _rate(group, CheckState.issue, note: s.daliCommWrong),
                ),
                _rateButton(
                  s.daliCommNoReaction,
                  item?.state == CheckState.issue && item?.note == s.daliCommNoReaction,
                  () => _rate(group, CheckState.issue, note: s.daliCommNoReaction),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _rateButton(String label, bool selected, VoidCallback onPressed) => Builder(
    builder: (context) {
      final hz = context.hz;
      return Semantics(
        selected: selected,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: selected ? hz.accentTint : null,
            foregroundColor: selected ? hz.accentText : null,
            side: selected ? BorderSide(color: hz.accent, width: Lines.selection) : null,
          ),
          child: Text(label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
        ),
      );
    },
  );
}
