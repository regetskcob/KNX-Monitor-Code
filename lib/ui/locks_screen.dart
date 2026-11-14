import 'dart:async';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/availability.dart' show formatDuration;
import '../model/device_channels.dart';
import '../model/lock_prefs.dart';
import '../model/locks.dart';
import '../model/plain_text.dart';
import '../model/telegram_log.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'figure_box.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// Time of day of a lock telegram, with the date when it was not on the day of [now].
String lockTime(DateTime t, DateTime now) {
  final time = '${_two(t.hour)}:${_two(t.minute)}';
  final today = t.year == now.year && t.month == now.month && t.day == now.day;
  return today ? time : '${_two(t.day)}.${_two(t.month)}. $time';
}

/// Who sent a lock telegram: the device by name, otherwise its address.
String lockWho(Telegram t) => t.outgoing ? s.locksByApp : (plainSender(t.source) ?? formatIndividual(t.source));

/// The lock that is active on [channel] according to [log], as (since, who); `null` if none.
(String, String)? activeLockText(DeviceChannel channel, TelegramLog log) {
  final tracks = lockTracks(CatalogStore.instance.catalog, log.log, inverted: LockPrefs.instance.inverted);
  final span = activeLockOf(channel, tracks)?.active;
  return span == null ? null : (lockTime(span.start.time, LocksScreen.clock()), lockWho(span.start));
}

/// Locks: what is locked right now, who locked it and since when; the history
/// of every lock with who released it; and all lock addresses with how they
/// are read. Everything from the recording, nothing is sent.
class LocksScreen extends StatefulWidget {
  const LocksScreen({super.key, required this.log});

  final TelegramLog log;

  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  @override
  State<LocksScreen> createState() => _LocksScreenState();
}

class _LocksScreenState extends State<LocksScreen> {
  final _prefs = LockPrefs.instance;
  late List<LockTrack> _tracks = _read();

  /// Not per telegram: reading walks the whole recording.
  late final _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());

  /// At most this many past locks are listed.
  static const _historyShown = 60;

  List<LockTrack> _read() => lockTracks(CatalogStore.instance.catalog, widget.log.log, inverted: _prefs.inverted);

  void _refresh() {
    if (mounted) setState(() => _tracks = _read());
  }

  @override
  void initState() {
    super.initState();
    _timer;
    _prefs.addListener(_refresh);
    unawaited(_prefs.load());
  }

  @override
  void dispose() {
    _timer.cancel();
    _prefs.removeListener(_refresh);
    super.dispose();
  }

  String _when(DateTime t) => lockTime(t, LocksScreen.clock());

  static String _who(Telegram t) => lockWho(t);

  /// What the lock acts on: the devices that receive it.
  static String? _targets(LockTrack t) {
    final names = {for (final d in t.targets) plainSender(d) ?? formatIndividual(d)};
    return names.isEmpty ? null : names.take(3).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final now = LocksScreen.clock();
    final active = [
      for (final t in _tracks)
        if (t.active != null) t,
    ];
    final past = [
      for (final t in _tracks)
        for (final span in t.spans)
          if (span.end != null) (t, span),
    ]..sort((a, b) => b.$2.end!.time.compareTo(a.$2.end!.time));

    final current = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHead(s.locksNow, count: active.length),
        if (active.isEmpty)
          Text(s.locksNoneNow, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted))
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Gap.item,
            children: [for (final t in active) _activeCard(context, t, now)],
          ),
        SectionHead(s.locksHistory, count: past.length),
        if (past.isEmpty)
          Text(s.locksNoHistory, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted))
        else
          RowCard(
            flat: true,
            children: [
              for (final (t, span) in past.take(_historyShown))
                CardRow(
                  title: t.info.name,
                  meta: [
                    '${_when(span.start.time)} – ${_when(span.end!.time)}',
                    formatDuration(span.length(now)),
                    s.locksLockedBy(_who(span.start)),
                    s.locksReleasedBy(_who(span.end!)),
                  ].join(metaSeparator),
                ),
            ],
          ),
      ],
    );

    final addresses = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHead(s.locksAddresses, count: _tracks.length),
        Text(s.locksSenseHint, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
        const SizedBox(height: Gap.item),
        RowCard(
          flat: true,
          children: [
            for (final t in _tracks)
              CardRow(
                address: formatGroup(t.address),
                title: t.info.name,
                meta: [
                  switch (t.locked) {
                    true => s.locksStateLocked,
                    false => s.locksStateFree,
                    null => s.locksStateUnknown,
                  },
                  if (t.last case final last?) _when(last.time),
                  t.sense == LockSense.lockOnOne ? s.locksSenseOne : s.locksSenseZero,
                  ?_targets(t),
                ].join(metaSeparator),
                trailing: IconButton(
                  tooltip: s.locksFlip,
                  onPressed: () => unawaited(_prefs.toggle(t.address)),
                  icon: const Icon(AppIcons.cycle, size: HzIconSize.row),
                ),
              ),
          ],
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(s.locksTitle),
        actions: [InfoAction(title: s.locksTitle, text: s.locksExplain)],
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= Breakpoints.expanded;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? Widths.wide : Widths.reading),
              child: ListView(
                padding: Gap.page,
                children: [
                  FigureBox(
                    figures: [
                      (
                        label: s.locksNow,
                        value: formatInt(active.length),
                        status: active.isEmpty ? null : HorizontStatus.warning,
                      ),
                      (label: s.locksAddresses, value: formatInt(_tracks.length), status: null),
                      (label: s.locksHistory, value: formatInt(past.length), status: null),
                    ],
                  ),
                  if (_tracks.isEmpty) ...[
                    const SizedBox(height: Gap.item),
                    Text(s.locksNone, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
                  ] else if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: Gap.section,
                      children: [
                        Expanded(child: current),
                        Expanded(child: addresses),
                      ],
                    )
                  else ...[
                    current,
                    addresses,
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _activeCard(BuildContext context, LockTrack t, DateTime now) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final span = t.active!;
    final targets = _targets(t);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: HzSpace.s4,
        children: [
          Wrap(
            spacing: HzSpace.s8,
            runSpacing: HzSpace.s4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(t.info.name, style: theme.textTheme.titleMedium),
              HorizontBadge(HorizontStatus.warning, label: formatDuration(span.length(now))),
            ],
          ),
          Text(
            [
              span.sinceAtLeast ? s.locksSinceAtLeast(_when(span.start.time)) : s.locksSince(_when(span.start.time)),
              s.locksLockedBy(_who(span.start)),
            ].join(metaSeparator),
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            [formatGroup(t.address), if (targets != null) s.locksActsOn(targets)].join(metaSeparator),
            style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
          ),
        ],
      ),
    );
  }
}
