import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../l10n/locale_controller.dart';
import '../model/availability.dart' show formatDuration;
import '../platform/addon.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'recordings_screen.dart' show RecordingsScreen;
import 'support_package_screen.dart';
import 'telegram_row.dart' show formatDate, formatTime;

/// Reasons the server knows (`crash_watch.dart`), for the legend. Anything else
/// is shown as "reason unknown": a newer server may send new values.
const restartReasons = ['error', 'host', 'oom', 'signal', 'watchdog', 'unknown'];

/// Words for the `reason` of a server restart, with the signal name if systemd
/// reported one (`KILL` → `SIGKILL`).
String restartReasonText(Object? reason, {Object? signal}) => switch (reason) {
  'error' => s.restartReasonError,
  'host' => s.restartReasonHost,
  'oom' => s.restartReasonOom,
  'signal' when signal is String && signal.isNotEmpty => s.restartReasonSignalNamed(
    signal.startsWith('SIG') ? signal : 'SIG$signal',
  ),
  'signal' => s.restartReasonSignal,
  'watchdog' => s.restartReasonWatchdog,
  _ => s.restartReasonUnknown,
};

/// How serious a reason looks: a device restart is plain information, an
/// unknown reason says nothing.
HorizontStatus restartReasonStatus(Object? reason) => switch (reason) {
  'host' => HorizontStatus.info,
  'error' || 'oom' || 'signal' || 'watchdog' => HorizontStatus.warning,
  _ => HorizontStatus.neutral,
};

/// Unexpected restarts of the box or add-on, from the server status
/// (`restarts`: `{count, last: {t, lastSeen, reason, signal?}}`). A tap opens
/// the list of the last restarts ([showServerRestarts]).
class ServerRestartsLine extends StatelessWidget {
  const ServerRestartsLine(this.restarts, {super.key, this.box, this.showHistory = true});

  final Map<String, Object?> restarts;

  /// Whether the server runs on the KNX box (systemd restarts it); `null` if
  /// not known (e.g. in the browser).
  final bool? box;

  /// Offer "Im Verlauf zeigen" (show in history); not in the history itself.
  final bool showHistory;

  @override
  Widget build(BuildContext context) {
    final last = (restarts['last'] as Map?)?.cast<String, Object?>() ?? const {};
    final time = DateTime.fromMillisecondsSinceEpoch((last['t'] as int?) ?? 0);
    final line = HorizontStatusLine(
      HorizontStatus.warning,
      s.serverRestarts(
        (restarts['count'] as int?) ?? 0,
        '${formatDate(time)} ${formatTime(time, seconds: false)}',
        restartReasonText(last['reason'], signal: last['signal']),
      ),
    );
    return Semantics(
      button: true,
      hint: s.restartsShow,
      child: InkWell(
        borderRadius: Radii.tile,
        onTap: () => showServerRestarts(context, box: box ?? Addon.box != null, showHistory: showHistory),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: HzSpace.s2),
          child: Row(
            children: [
              Flexible(child: line),
              const SizedBox(width: HzSpace.s4),
              ExcludeSemantics(
                child: Icon(AppIcons.next, size: HzIconSize.inline, color: context.hz.warning),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// List of the server's unexpected restarts in the last 30 days (`GET
/// /api/restarts`): bottom sheet, at reading width on wide layouts. The error
/// text comes only for admins.
Future<void> showServerRestarts(
  BuildContext context, {
  bool box = false,
  bool showHistory = true,
  Future<List<Object?>> Function()? load,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: Widths.reading),
  builder: (sheet) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.7,
    maxChildSize: 0.95,
    builder: (context, controller) => ServerRestartsPanel(
      load: load ?? Addon.restarts,
      box: box,
      scrollController: controller,
      onHistory: showHistory
          ? () {
              Navigator.pop(sheet);
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RecordingsScreen()));
            }
          : null,
      onDiagnostics: () {
        Navigator.pop(sheet);
        showSupportPackage(context);
      },
    ),
  ),
);

/// Content of [showServerRestarts].
class ServerRestartsPanel extends StatefulWidget {
  const ServerRestartsPanel({
    super.key,
    required this.load,
    this.box = false,
    this.scrollController,
    this.onHistory,
    this.onDiagnostics,
  });

  final Future<List<Object?>> Function() load;
  final bool box;
  final ScrollController? scrollController;
  final VoidCallback? onHistory;
  final VoidCallback? onDiagnostics;

  @override
  State<ServerRestartsPanel> createState() => _ServerRestartsPanelState();
}

class _ServerRestartsPanelState extends State<ServerRestartsPanel> {
  late final Future<List<Map<String, Object?>>> _entries = _load();

  /// Newest first; a failed request or an older server gives `null`.
  Future<List<Map<String, Object?>>> _load() async {
    final list = await widget.load();
    return [
      for (final e in list.reversed)
        if (e is Map && e['t'] is int) e.cast<String, Object?>(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final muted = theme.textTheme.bodySmall?.copyWith(color: hz.textMuted);
    return Column(
      children: [
        Expanded(
          child: FutureBuilder(
            future: _entries,
            builder: (context, snapshot) => ListView(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, Gap.section),
              children: [
                Text(s.restartsTitle, style: theme.textTheme.titleMedium),
                const SizedBox(height: HzSpace.s4),
                Text(widget.box ? s.restartsIntroBox : s.restartsIntro, style: muted),
                const SizedBox(height: Gap.section),
                if (snapshot.connectionState != ConnectionState.done)
                  const Center(child: CircularProgressIndicator.adaptive())
                else if (snapshot.hasError)
                  Text(s.restartsUnavailable, style: muted)
                else if (snapshot.data!.isEmpty)
                  Text(s.restartsEmpty, style: muted)
                else
                  for (final (i, e) in snapshot.data!.indexed) ...[
                    if (i > 0) Divider(height: Gap.section * 2, color: hz.line),
                    RestartEntry(e),
                  ],
                const SizedBox(height: Gap.section * 2),
                Kennung(s.restartsReasons),
                const SizedBox(height: HzSpace.s8),
                Wrap(
                  spacing: HzSpace.s8,
                  runSpacing: HzSpace.s8,
                  children: [
                    for (final r in restartReasons) HorizontBadge(restartReasonStatus(r), label: restartReasonText(r)),
                  ],
                ),
                const SizedBox(height: Gap.inner),
                Text(s.restartsLegend, style: muted),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.gutter, HzSpace.s8, Gap.gutter, Gap.section),
            child: Row(
              spacing: Gap.item,
              children: [
                if (widget.onHistory case final onHistory?)
                  Expanded(
                    child: OutlinedButton(onPressed: onHistory, child: Text(s.restartsShowHistory)),
                  ),
                Expanded(
                  child: FilledButton(onPressed: widget.onDiagnostics, child: Text(s.diagTitle)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One restart: time, reason, last sign of life, version and the gap.
class RestartEntry extends StatelessWidget {
  const RestartEntry(this.entry, {super.key});

  final Map<String, Object?> entry;

  /// Time without the server; `null` if the entry's own clock was wrong (box
  /// without an RTC: restart time before the last sign of life).
  static Duration? gapOf(Map<String, Object?> entry) {
    final t = entry['t'];
    final seen = entry['lastSeen'];
    if (t is! int || seen is! int || t < seen) return null;
    return Duration(milliseconds: t - seen);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final muted = theme.textTheme.bodySmall?.copyWith(color: hz.textMuted);
    final time = DateTime.fromMillisecondsSinceEpoch(entry['t']! as int);
    final seen = entry['lastSeen'] is int ? DateTime.fromMillisecondsSinceEpoch(entry['lastSeen']! as int) : null;
    final gap = gapOf(entry);
    final reason = entry['reason'];
    final error = entry['error'];
    final details = [
      if (seen != null) s.restartsLastSeen(formatTime(seen, seconds: false)),
      if (entry['version'] case final String version) s.restartsVersion(version),
      gap == null ? s.restartsGapUnknown : s.restartsGap(formatDuration(gap)),
    ].join(metaSeparator);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                '${formatDate(time)} ${formatTime(time, seconds: false)}',
                style: context.mono(theme.textTheme.titleSmall),
              ),
            ),
            const SizedBox(width: HzSpace.s8),
            Flexible(
              child: HorizontBadge(
                restartReasonStatus(reason),
                label: restartReasonText(reason, signal: entry['signal']),
              ),
            ),
          ],
        ),
        const SizedBox(height: HzSpace.s4),
        Text(details, style: muted),
        if (error is String && error.isNotEmpty) ...[
          const SizedBox(height: HzSpace.s8),
          DecoratedBox(
            decoration: BoxDecoration(color: hz.sunken, borderRadius: Radii.tile),
            child: Padding(
              padding: const EdgeInsets.all(HzSpace.s8),
              child: SelectableText(
                // The first lines say what happened; the stack is in the package.
                error.split('\n').take(4).join('\n'),
                style: context.mono(theme.textTheme.bodySmall),
              ),
            ),
          ),
        ] else if (reason == 'error') ...[
          const SizedBox(height: HzSpace.s4),
          Text(s.restartsErrorAdminOnly, style: muted),
        ],
      ],
    );
  }
}
