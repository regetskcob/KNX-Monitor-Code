import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/active_tunnel.dart';
import '../knx/knx_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/channel_control.dart';
import '../model/channel_test.dart';
import '../model/commissioning.dart';
import '../model/device_art.dart';
import '../model/lock_prefs.dart';
import '../model/plan.dart';
import '../model/telegram_log.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'figure_box.dart';
import 'locks_screen.dart';
import 'plan_screen.dart';
import 'tool_shell.dart';
import 'write_confirm.dart';

/// Opens the channel check of [device] (Pro, like commissioning).
Future<void> openChannelTest(BuildContext context, int device, TelegramLog log) async {
  if (!await unlock(context, Feature.commissioning) || !context.mounted) return;
  await pushTool<void>(context, (_) => ChannelTestScreen(device: device, log: log));
}

/// Channel check: the app switches one channel on, the installer says what
/// reacted, the app switches it off again and goes on. Blinds, gates and
/// channels without a switching address are triggered by hand and only rated.
class ChannelTestScreen extends StatefulWidget {
  const ChannelTestScreen({super.key, required this.device, required this.log});

  final int device;
  final TelegramLog log;

  @override
  State<ChannelTestScreen> createState() => _ChannelTestScreenState();
}

class _ChannelTestScreenState extends State<ChannelTestScreen> {
  late final _channels = deviceChannels(widget.device);
  late final _test = ChannelTest.of(widget.device, _channels);
  final _note = TextEditingController();

  /// Channel being checked.
  ChannelCheck? _current;

  /// Whether the app has switched [_current] on and waits for the answer.
  bool _on = false;

  /// Lock on [_current] found when its feedback stayed away: since when, by whom.
  (String, String)? _lock;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _current = _test.next;
    // The saved reading of lock addresses, for the lock note when feedback stays away.
    unawaited(LockPrefs.instance.load());
    unawaited(
      ChannelTestStore.instance.restore(_test).then((_) {
        if (mounted) setState(() => _current = _test.next);
      }),
    );
  }

  @override
  void dispose() {
    // Never leave a channel on that the check switched on.
    if (_on) unawaited(_send(_current, 0));
    _note.dispose();
    super.dispose();
  }

  KnxTunnel? get _tunnel => switch (activeTunnel.value) {
    final t? when t.state.value == TunnelState.connected => t,
    _ => null,
  };

  Future<bool> _send(ChannelCheck? item, int value) async {
    final control = item?.control;
    final tunnel = _tunnel;
    if (control == null || tunnel == null) return false;
    // `false` = rejected, `null` = no confirmation in time: neither was sent.
    return await tunnel.write(control.address, small: value) == true;
  }

  String _name(ChannelCheck i) => [i.label, ?i.title].join(' ');

  Future<void> _switchOn() async {
    final item = _current;
    final control = item?.control;
    if (item == null || control == null || _busy) return;
    if (!await confirmWrite(context, control.address, small: 1) || !mounted) return;
    setState(() => _busy = true);
    final status = control.status;
    final confirmed = status == null ? null : awaitFeedback(widget.log, status, 1);
    final sent = await _send(item, 1);
    final feedback = sent ? await confirmed : null;
    if (!mounted) return;
    final channel = _channels.where((c) => c.label == item.label).firstOrNull;
    setState(() {
      _busy = false;
      _on = sent;
      item.feedback = feedback;
      // No feedback: a set lock object explains it.
      _lock = feedback == false && channel != null ? activeLockText(channel, widget.log) : null;
    });
    if (!sent) _say(_tunnel == null ? s.operateOffline : s.operateNotSent(_name(item)));
  }

  Future<void> _rate(ChannelResult result) async {
    final item = _current;
    if (item == null) return;
    if (_on) await _send(item, 0);
    _test.rate(item, result, note: _note.text);
    // The commissioning list ticks the same address off, where it has it.
    if (item.control?.status case final status? when result != ChannelResult.skipped) {
      Commissioning.instance.mark(status, result == ChannelResult.ok ? CheckState.ok : CheckState.issue);
    }
    await ChannelTestStore.instance.save(_test);
    if (!mounted) return;
    setState(() {
      _on = false;
      _lock = null;
      _note.clear();
      _current = _test.next;
    });
  }

  void _pick(ChannelCheck item) {
    if (_on || _busy) return;
    setState(() {
      _current = item;
      _note.text = item.note ?? '';
    });
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(horizontMessageSnackBar(context.hz, text));

  String _resultText(ChannelResult r) => switch (r) {
    ChannelResult.open => s.channelTestOpen,
    ChannelResult.ok => s.channelTestOk,
    ChannelResult.wrongLoad => s.channelTestWrong,
    ChannelResult.noReaction => s.channelTestNothing,
    ChannelResult.skipped => s.channelTestSkipped,
  };

  HorizontStatus _status(ChannelCheck i) => switch (i.result) {
    ChannelResult.ok => i.feedback == false ? HorizontStatus.warning : HorizontStatus.positive,
    ChannelResult.wrongLoad || ChannelResult.noReaction => HorizontStatus.critical,
    _ => HorizontStatus.neutral,
  };

  Future<void> _share(Rect? origin) async {
    final device = CatalogStore.instance.device(widget.device);
    final text = _test.report(
      heading: s.channelTestReport(device?.name ?? formatIndividual(widget.device), formatIndividual(widget.device)),
      text: _resultText,
      feedback: (f) => f ? s.channelTestFeedbackYes : s.channelTestFeedbackNo,
    );
    await shareFile(
      context,
      Uint8List.fromList(utf8.encode(text)),
      fileName(s.channelTestTitle, 'txt'),
      'text/plain',
      origin: origin,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final device = CatalogStore.instance.device(widget.device);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.channelTestTitle),
        actions: [InfoAction(title: s.channelTestTitle, text: s.channelTestExplain)],
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= Breakpoints.expanded;
          final step = _current == null ? _finished(context) : _step(context, _current!);
          final list = _list(context);
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? Widths.wide : Widths.reading),
              child: ListView(
                padding: Gap.page,
                children: [
                  Text(
                    [
                      device?.name ?? '',
                      formatIndividual(widget.device),
                    ].where((e) => e.isNotEmpty).join(metaSeparator),
                    style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted),
                  ),
                  const SizedBox(height: Gap.item),
                  FigureBox(
                    figures: [
                      (label: s.channelTestChecked, value: '${_test.done}/${_test.items.length}', status: null),
                      (
                        label: s.channelTestIssues,
                        value: formatInt(_test.issues),
                        status: _test.issues > 0 ? HorizontStatus.critical : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.section),
                  if (_test.items.isEmpty)
                    Text(s.channelTestNone, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted))
                  else if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: Gap.section,
                      children: [
                        Expanded(child: step),
                        Expanded(child: list),
                      ],
                    )
                  else ...[
                    step,
                    const SizedBox(height: Gap.section),
                    list,
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _finished(BuildContext context) => SectionCard(
    soft: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.item,
      children: [
        Text(s.channelTestDone, style: Theme.of(context).textTheme.titleMedium),
        Text(s.channelTestDoneHint(_test.issues)),
        Builder(
          builder: (context) => FilledButton(onPressed: () => _share(rectOf(context)), child: Text(s.channelTestShare)),
        ),
      ],
    ),
  );

  Widget _step(BuildContext context, ChannelCheck item) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final control = item.control;
    final asked = _on || !item.automatic;
    return SectionCard(
      title: _name(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.item,
        children: [
          if (control != null)
            Text(
              [
                formatGroup(control.address),
                CatalogStore.instance.info(control.address)?.name ?? '',
              ].join(metaSeparator),
              style: context.mono(theme.textTheme.bodySmall).copyWith(color: hz.textMuted),
            ),
          if (!item.automatic)
            Text(s.channelTestByHand, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted))
          else if (!_on)
            FilledButton(
              onPressed: _busy || _tunnel == null ? null : _switchOn,
              child: Text(_busy ? s.channelTestSwitching : s.channelTestSwitchOn),
            )
          else
            Row(
              spacing: HzSpace.s8,
              children: [
                HorizontBadge(
                  switch (item.feedback) {
                    true => HorizontStatus.positive,
                    false => HorizontStatus.warning,
                    null => HorizontStatus.neutral,
                  },
                  label: switch (item.feedback) {
                    true => s.channelTestFeedbackYes,
                    false => s.channelTestFeedbackNo,
                    null => s.channelTestFeedbackNone,
                  },
                ),
              ],
            ),
          if (_lock case (final since, final who))
            Text(s.channelTestLocked(since, who), style: theme.textTheme.bodyMedium?.copyWith(color: hz.warning)),
          if (item.automatic && _tunnel == null)
            Text(s.operateOffline, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
          if (asked) ...[
            Text(s.channelTestQuestion, style: theme.textTheme.titleMedium),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: s.channelTestNote),
            ),
            FilledButton(onPressed: () => _rate(ChannelResult.ok), child: Text(s.channelTestOk)),
            OutlinedButton(onPressed: () => _rate(ChannelResult.wrongLoad), child: Text(s.channelTestWrong)),
            OutlinedButton(onPressed: () => _rate(ChannelResult.noReaction), child: Text(s.channelTestNothing)),
          ],
          TextButton(onPressed: _busy ? null : () => _rate(ChannelResult.skipped), child: Text(s.channelTestSkip)),
        ],
      ),
    );
  }

  Widget _list(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionHead(
        s.channelTestChannels,
        count: _test.items.length,
        trailing: _test.done == 0
            ? null
            : Builder(
                builder: (context) =>
                    TextButton(onPressed: () => _share(rectOf(context)), child: Text(s.channelTestShare)),
              ),
      ),
      RowCard(
        flat: true,
        children: [
          for (final i in _test.items)
            CardRow(
              title: _name(i),
              meta: [
                if (i.control case final c?) formatGroup(c.address),
                if (i.feedback == false) s.channelTestFeedbackNo,
                ?i.note,
              ].join(metaSeparator),
              trailing: HorizontBadge(_status(i), label: _resultText(i.result)),
              onTap: () => _pick(i),
              chevron: false,
            ),
        ],
      ),
    ],
  );
}
