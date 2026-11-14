import 'dart:async';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/plain_text.dart';
import '../model/telegram_log.dart';
import '../model/value_snapshot.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'figure_box.dart';
import 'locks_screen.dart' show lockTime;

/// Before and after: freeze the state of the installation, do what has to be
/// done (power off, swap a device, download from the ETS), and see what is
/// different afterwards and which devices have not come back.
class SnapshotScreen extends StatefulWidget {
  const SnapshotScreen({super.key, required this.log});

  final TelegramLog log;

  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  @override
  State<SnapshotScreen> createState() => _SnapshotScreenState();
}

class _SnapshotScreenState extends State<SnapshotScreen> {
  final _store = ValueSnapshotStore.instance;

  /// The comparison is not redrawn per telegram.
  late final _timer = Timer.periodic(const Duration(seconds: 3), (_) {
    if (mounted) setState(() {});
  });

  @override
  void initState() {
    super.initState();
    _timer;
    unawaited(_store.load());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  static String _text(Telegram t) => CatalogStore.instance.value(t);
  static String _name(int a) => CatalogStore.instance.info(a)?.name ?? formatGroup(a);
  static String _device(int a) => plainSender(a) ?? formatIndividual(a);

  Future<void> _take() => _store.save(ValueSnapshot.take(widget.log.latest, SnapshotScreen.clock(), text: _text));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.snapTitle),
        actions: [InfoAction(title: s.snapTitle, text: s.snapExplain)],
      ),
      body: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          final snap = _store.snapshot;
          final diff = snap?.compare(widget.log.latest, text: _text);
          return LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= Breakpoints.expanded;
              final changed = diff == null ? null : _changed(context, diff);
              final silent = diff == null ? null : _silent(context, diff);
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? Widths.wide : Widths.reading),
                  child: ListView(
                    padding: Gap.page,
                    children: [
                      if (snap == null || diff == null) ...[
                        Text(s.snapIntro, style: theme.textTheme.bodyMedium),
                        const SizedBox(height: Gap.section),
                        FilledButton(
                          onPressed: widget.log.latest.isEmpty ? null : _take,
                          child: Text(s.snapTake(widget.log.latest.length)),
                        ),
                      ] else ...[
                        FigureBox(
                          figures: [
                            (
                              label: s.snapChanged,
                              value: formatInt(diff.changed.length),
                              status: diff.changed.isEmpty ? null : HorizontStatus.info,
                            ),
                            (
                              label: s.snapSilentDevices,
                              value: formatInt(diff.silentDevices.length),
                              status: diff.silentDevices.isEmpty ? null : HorizontStatus.warning,
                            ),
                            (label: s.snapQuiet, value: formatInt(diff.quiet.length), status: null),
                            (label: s.snapSame, value: formatInt(diff.same.length), status: null),
                          ],
                        ),
                        const SizedBox(height: Gap.item),
                        Text(
                          s.snapTakenAt(lockTime(snap.taken, SnapshotScreen.clock()), snap.values.length),
                          style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                        ),
                        const SizedBox(height: Gap.item),
                        Wrap(
                          spacing: HzSpace.s8,
                          runSpacing: HzSpace.s8,
                          children: [
                            OutlinedButton(onPressed: _take, child: Text(s.snapRetake)),
                            TextButton(onPressed: () => _store.save(null), child: Text(s.snapDiscard)),
                          ],
                        ),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: Gap.section,
                            children: [
                              Expanded(child: changed!),
                              Expanded(child: silent!),
                            ],
                          )
                        else ...[
                          changed!,
                          silent!,
                        ],
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _changed(BuildContext context, SnapshotDiff diff) {
    final muted = Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.hz.textMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHead(s.snapChanged, count: diff.changed.length),
        if (diff.changed.isEmpty)
          Text(s.snapNothingChanged, style: muted)
        else
          RowCard(
            flat: true,
            children: [
              for (final c in diff.changed.take(80))
                CardRow(
                  address: formatGroup(c.address),
                  title: _name(c.address),
                  meta: s.snapBeforeAfter(c.before, c.after),
                ),
            ],
          ),
      ],
    );
  }

  Widget _silent(BuildContext context, SnapshotDiff diff) {
    final muted = Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.hz.textMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHead(s.snapSilentDevices, count: diff.silentDevices.length),
        if (diff.silentDevices.isEmpty)
          Text(s.snapAllBack, style: muted)
        else ...[
          Text(s.snapSilentHint, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.hz.textMuted)),
          const SizedBox(height: Gap.item),
          RowCard(
            flat: true,
            children: [
              for (final d in diff.silentDevices.take(80)) CardRow(address: formatIndividual(d), title: _device(d)),
            ],
          ),
        ],
        if (diff.fresh.isNotEmpty) ...[
          SectionHead(s.snapFresh, count: diff.fresh.length),
          RowCard(
            flat: true,
            children: [for (final a in diff.fresh.take(40)) CardRow(address: formatGroup(a), title: _name(a))],
          ),
        ],
      ],
    );
  }
}
