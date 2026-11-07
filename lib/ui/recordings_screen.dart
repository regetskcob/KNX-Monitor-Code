import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../export/diagnostics_bundle.dart';
import '../export/pdf_export.dart';
import '../export/telegram_files.dart';
import '../knx/knx_tunnel.dart';
import '../model/availability.dart';
import '../model/expert_mode.dart';
import '../model/send_scheduler.dart';
import '../model/history_store.dart';
import '../platform/addon.dart';
import '../model/recording.dart';
import '../theme/palette.dart';
import '../l10n/locale_controller.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'server_restarts.dart';
import 'log_view.dart';
import 'more_menu.dart';
import 'monitor_screen.dart' show SaveRecordingDialog;
import 'annotations.dart';
import 'findings_screen.dart';
import 'recording_timeline.dart';
import 'replay_sheet.dart';
import 'handover_screen.dart' show openPackageFile;
import 'support_package_screen.dart';
import 'telegram_row.dart';
import '../theme/app_icons.dart';
import '../model/installation.dart';
import '../model/plan.dart';
import 'plan_screen.dart';

/// Opens a saved recording.
Future<void> openRecording(BuildContext context, String id) async {
  final navigator = Navigator.of(context);
  final recording = await RecordingStore.instance.open(id);
  await navigator.push(MaterialPageRoute<void>(builder: (_) => RecordingScreen(recording: recording)));
}

String formatDuration(Duration d) {
  String two(int v) => v.toString().padLeft(2, '0');
  if (d.inHours > 0) return '${d.inHours} h ${two(d.inMinutes % 60)} min';
  if (d.inMinutes > 0) return '${d.inMinutes} min ${two(d.inSeconds % 60)} s';
  return '${d.inSeconds} s';
}

/// Liste aller Aufnahmen, neueste zuerst.
class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  final _store = RecordingStore.instance;
  late final Future<void> _loading = _store.load();

  /// Installation shown (`''` = unassigned, `null` = all). Initially the active
  /// one, if it has recordings.
  String? _filter;
  bool _filterChosen = false;

  static String _installationOf(RecordingSummary r) =>
      InstallationStore.instance
          .forRecording(installation: r.installation, gateway: r.gateway, project: r.project)
          ?.id ??
      '';

  static String _installationName(String id) =>
      id.isEmpty ? s.installationUnassigned : InstallationStore.instance.byId(id)?.name ?? s.installationUnassigned;

  Widget _filterChips(List<String> groups) => Padding(
    padding: const EdgeInsets.only(top: HzSpace.s24),
    child: Wrap(
      spacing: HzSpace.s8,
      runSpacing: HzSpace.s8,
      children: [
        ChoiceChip(
          label: Text(s.installationAll),
          selected: _filter == null,
          onSelected: (_) => setState(() => _filter = null),
        ),
        for (final id in groups)
          ChoiceChip(
            label: Text(_installationName(id)),
            selected: _filter == id,
            onSelected: (_) => setState(() => _filter = id),
          ),
      ],
    ),
  );

  Future<void> _import() async {
    // An import counts like a recording: Free keeps one.
    final plan = Plan.instance;
    if (await _store.count() >= plan.maxRecordings) {
      if (!mounted) return;
      await showPlanScreen(context, reason: s.planMoreRecordings);
      if (!mounted || await _store.count() >= plan.maxRecordings) return;
    }
    if (!mounted) return;
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file == null) return;
    try {
      final bytes = await file.readAsBytes();
      // Diagnostics package (ZIP): open project and recording together.
      if (DiagnosticsPackage.looksLikeZip(bytes)) {
        if (mounted && await openPackageFile(context, bytes)) return;
        if (mounted) await openSupportPackage(context, bytes);
        return;
      }
      // A month of a busy bus as ETS file is several hundred MB: as a recording in
      // memory that would freeze or end the app (iPad, A14).
      if (bytes.length > _importMaxBytes) {
        if (mounted) {
          final mb = (bytes.length / (1024 * 1024)).round();
          showHorizontMessage(context, s.recordingsImportTooLarge(mb), status: HorizontStatus.critical);
        }
        return;
      }
      final name = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      // Parsing in the background, the UI keeps running.
      final recording = await compute(_parseRecording, (bytes: bytes, name: name));
      await _store.save(recording);
      if (!mounted) return;
      showHorizontMessage(
        context,
        s.recordingsImported(recording.name, recording.telegrams.length),
        status: HorizontStatus.positive,
      );
    } on FormatException catch (e) {
      if (mounted) showHorizontMessage(context, s.recordingsImportFailed(e.message), status: HorizontStatus.critical);
    } on Object catch (e) {
      debugPrint('Import: $e');
      if (mounted) showHorizontMessage(context, s.actionFailed, status: HorizontStatus.critical);
    }
  }

  /// Largest ETS file to import as a recording (about 400,000 telegrams).
  static const _importMaxBytes = 100 * 1024 * 1024;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(s.recordingsTitle),
        actions: [IconButton(tooltip: s.diagImportHint, onPressed: _import, icon: const Icon(AppIcons.import))],
      ),
      body: FutureBuilder(
        future: _loading,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          return ListenableBuilder(
            listenable: _store,
            builder: (context, _) {
              final all = _store.summaries;
              final of = {for (final r in all) r.id: _installationOf(r)};
              // Active first, then as in the installation list, "ohne Zuordnung" (unassigned) last.
              final present = of.values.toSet();
              final groups = [
                for (final i in InstallationStore.instance.list)
                  if (present.contains(i.id)) i.id,
                if (present.contains('')) '',
              ];
              if (!_filterChosen) {
                _filterChosen = true;
                final active = InstallationStore.instance.active.id;
                if (groups.length > 1 && groups.contains(active)) _filter = active;
              }
              if (_filter != null && !groups.contains(_filter)) _filter = null;
              final items = _filter == null
                  ? all
                  : [
                      for (final r in all)
                        if (of[r.id] == _filter) r,
                    ];
              // With several installations in the full list: installation in the key data.
              String? place(RecordingSummary r) =>
                  _filter == null && groups.length > 1 ? _installationName(of[r.id]!) : null;
              // Recordings as rows with hairlines, no card per row.
              final width = MediaQuery.sizeOf(context).width;
              final gutter = Gap.gutterFor(width);
              // Zwei Aufnahmen je Zeile, sobald zwei Kartenspalten passen (iPad quer, Mac).
              final columns = width.clamp(0, Widths.wide + 2 * gutter) - 2 * gutter >= 2 * Widths.column + Gap.section
                  ? 2
                  : 1;
              final rows = (items.length / columns).ceil();
              return ListView.builder(
                // Full width up to the page width, centered beyond that.
                padding: EdgeInsets.fromLTRB(
                  gutter + ((width - 2 * gutter - Widths.wide) / 2).clamp(0, double.infinity),
                  Gap.page.top,
                  gutter + ((width - 2 * gutter - Widths.wide) / 2).clamp(0, double.infinity),
                  Gap.page.bottom,
                ),
                itemCount: rows + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _HistoryCard(),
                        if (groups.length > 1) _filterChips(groups),
                        if (items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: HzSpace.s48),
                            child: HorizontEmptyHint(icon: AppIcons.recordings, text: s.recordingsEmpty),
                          )
                        else ...[
                          const SizedBox(height: HzSpace.s24),
                          SectionTitle(s.recordingsTitle, count: items.length),
                          const SizedBox(height: HzSpace.s4),
                        ],
                      ],
                    );
                  }
                  if (columns == 1) return _RecordingRow(summary: items[index - 1], place: place(items[index - 1]));
                  final first = (index - 1) * columns;
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: Gap.section,
                      children: [
                        for (var i = first; i < first + columns; i++)
                          Expanded(
                            child: i < items.length
                                ? _RecordingRow(summary: items[i], place: place(items[i]))
                                : const SizedBox(),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// A recording in the list: name, note, the key data small below it; a hairline
/// at the bottom.
class _RecordingRow extends StatelessWidget {
  const _RecordingRow({required this.summary, this.place});

  final RecordingSummary summary;

  /// Name of the installation (only in the full list of several installations).
  final String? place;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final r = summary;
    final meta = [
      '${formatDate(r.started)}  ${formatTime(r.started, seconds: false)}',
      formatDuration(r.duration),
      s.telegramCount(r.count),
      ?place,
      ?r.gateway,
    ].join(metaSeparator);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: hz.line, width: Lines.hairline),
        ),
      ),
      child: InkWell(
        onTap: () => openRecording(context, r.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: HzSpace.s4, vertical: HzSpace.s12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
                    if (r.note != null) ...[
                      const SizedBox(height: HzSpace.s4),
                      Text(
                        r.note!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted),
                      ),
                    ],
                    const SizedBox(height: HzSpace.s4),
                    Text(meta, style: context.figures(theme.textTheme.bodySmall).copyWith(color: hz.textFaint)),
                  ],
                ),
              ),
              Icon(AppIcons.next, color: hz.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// A recording with all views of the monitor, without reading/writing.
class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key, required this.recording, this.showFindings = false});

  final Recording recording;

  /// Whether to show the finding right away (freshly opened diagnostics package).
  final bool showFindings;

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  late final _log = RecordingLog(widget.recording);
  late final _player = RecordingPlayer(_log);

  Recording get _r => widget.recording;

  @override
  void initState() {
    super.initState();
    AnnotationScope.open(_r);
    if (widget.showFindings && _r.diagnostics != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _findings();
      });
    }
  }

  @override
  void dispose() {
    AnnotationScope.close(_r);
    _player.dispose();
    _log.dispose();
    super.dispose();
  }

  Future<void> _timeline({DateTime? focus}) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => RecordingTimelineScreen(recording: _r, player: _player, focus: focus),
    ),
  );

  Future<void> _findings() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => FindingsScreen(
        recording: _r,
        onShowTime: (t) => _timeline(focus: t),
      ),
    ),
  );

  Future<void> _edit() async {
    final result = await showAdaptiveDialog<({String name, String? note})>(
      context: context,
      builder: (_) => SaveRecordingDialog(initialName: _r.name, initialNote: _r.note, count: null),
    );
    if (result == null) return;
    setState(() {
      _r.name = result.name;
      _r.note = result.note;
    });
    await RecordingStore.instance.save(_r);
  }

  /// Connected tunnel of the monitor, otherwise `null`.
  KnxTunnel? get _replayTunnel {
    final t = SendScheduler.instance.tunnel;
    return t != null && t.state.value == TunnelState.connected ? t : null;
  }

  Future<void> _replay() async {
    final tunnel = _replayTunnel;
    if (tunnel == null || !await unlock(context, Feature.busReplay) || !mounted) return;
    _player.pause();
    await showReplaySheet(
      context,
      recording: _r,
      tunnel: tunnel,
      gateway: [?tunnel.deviceName.value, tunnel.host].join(metaSeparator),
    );
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    final ok = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(s.recordingDeleteTitle),
        content: Text(s.recordingDeleteText(_r.name)),
        actions: [
          horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context, false)),
          horizontDialogAction(
            context,
            label: s.commonDelete,
            primary: true,
            destructive: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await RecordingStore.instance.delete(_r.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return LogView(
      data: _log,
      exportTitle: _r.name,
      exportNote: _r.note,
      gateway: _r.gateway,
      floatingStart: _r.telegrams.isEmpty ? null : PlayerBar(player: _player),
      title: _RecordingTitle(recording: _r),
      actions: [
        if (_r.diagnostics != null)
          IconButton(tooltip: s.findingsTitle, onPressed: _findings, icon: const Icon(AppIcons.report)),
        IconButton(
          tooltip: s.timelineTitle,
          onPressed: _r.telegrams.isEmpty ? null : _timeline,
          icon: const Icon(AppIcons.annotation),
        ),
        Builder(
          builder: (buttonContext) => IconButton(
            tooltip: s.recordingPdf,
            onPressed: _r.telegrams.isEmpty
                ? null
                : () async {
                    final origin = rectOf(buttonContext);
                    final simple = !Plan.instance.allows(Feature.export);
                    await sharePdf(
                      this.context,
                      () async =>
                          TelegramPdf(_r.telegrams, gateway: _r.gateway, title: _r.name, note: _r.note, simple: simple),
                      pdfName(_r.name),
                      origin: origin,
                    );
                  },
            icon: Icon(AppIcons.share),
          ),
        ),
      ],
      menuFooter: () => [
        MenuAction(icon: AppIcons.edit, title: s.recordingEditMenu, onTap: _edit),
        // Real replay only in expert mode and with a connection.
        if (ExpertMode.instance.value)
          MenuAction(
            icon: AppIcons.send,
            title: s.replayMenu,
            danger: true,
            enabled: _replayTunnel != null,
            onTap: _replay,
          ),
        MenuAction(icon: AppIcons.delete, title: s.recordingDeleteMenu, danger: true, onTap: _delete),
      ],
    );
  }
}

/// Label line above the tab name: recording symbol, name, date (if not already
/// in the name) and duration, e.g. "AUFNAHME 14.10.2026 15:20 · 12 MIN".
class _RecordingTitle extends StatelessWidget {
  const _RecordingTitle({required this.recording});

  final Recording recording;

  @override
  Widget build(BuildContext context) {
    final r = recording;
    final date = formatDate(r.started);
    final text = [r.name, if (!r.name.contains(date)) date, formatDuration(r.duration)].join(' · ');
    return Semantics(
      label: '$text · ${s.telegramCount(r.telegrams.length)}',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.record, size: HzIconSize.badge, color: context.hz.textMuted),
            const SizedBox(width: HzSpace.s4),
            Flexible(child: Kennung(text)),
          ],
        ),
      ),
    );
  }
}

/// Wiedergabe einer Aufnahme: Play/Pause, Zeitleiste, Geschwindigkeit.
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key, required this.player});

  final RecordingPlayer player;

  static String _clock(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}'
        : '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final data = context.hzTheme.data;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final total = player.duration.inMilliseconds;
        final pos = player.position.inMilliseconds.clamp(0, total);
        final speed = player.speed;
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          // Line instead of shadow: surface with hairline, card radius.
          child: Material(
            color: hz.surface,
            shape: RoundedRectangleBorder(
              borderRadius: Radii.card,
              side: BorderSide(color: hz.line, width: Lines.hairline),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(HzSpace.s8, HzSpace.s8, HzSpace.s12, HzSpace.s8),
              child: Row(
                children: [
                  FloatingActionButton(
                    heroTag: 'player',
                    elevation: 0,
                    tooltip: player.playing ? s.playerPause : s.playerPlay,
                    onPressed: player.toggle,
                    child: AnimatedSwitcher(
                      duration: Motion.fastOf(context),
                      switchInCurve: Motion.curve,
                      switchOutCurve: Motion.curveOut,
                      transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
                      child: Icon(
                        player.playing ? AppIcons.pause : AppIcons.play,
                        key: ValueKey(player.playing),
                        size: 28,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: s.playerRestart,
                    onPressed: () => player.seek(Duration.zero),
                    icon: const Icon(AppIcons.restart),
                  ),
                  Text(_clock(player.position), style: data),
                  // History bar above the time axis: when how many telegrams
                  // arrived; the part already played in the accent color.
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: HzSpace.s16),
                          child: ExcludeSemantics(
                            child: SizedBox(
                              height: HzSpace.s16,
                              width: double.infinity,
                              child: CustomPaint(
                                painter: _DensityPainter(
                                  counts: player.density(_densityBins),
                                  played: total == 0 ? 1 : pos / total,
                                  color: hz.accent,
                                  rest: hz.lineStrong,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // On iOS and macOS the system slider; its track starts after the
                        // thumb (14), plus 2, like the 16 of the Material slider above the density.
                        switch (Theme.of(context).platform) {
                          TargetPlatform.iOS || TargetPlatform.macOS => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: HzSpace.s2),
                            child: CupertinoSlider(
                              value: total == 0 ? 0 : pos / total,
                              onChanged: total == 0
                                  ? null
                                  : (v) => player.seek(Duration(milliseconds: (v * total).round())),
                            ),
                          ),
                          _ => Slider(
                            padding: const EdgeInsets.symmetric(horizontal: HzSpace.s16),
                            value: total == 0 ? 0 : pos / total,
                            onChanged: total == 0
                                ? null
                                : (v) => player.seek(Duration(milliseconds: (v * total).round())),
                            semanticFormatterCallback: (v) => _clock(Duration(milliseconds: (v * total).round())),
                          ),
                        },
                      ],
                    ),
                  ),
                  Text(_clock(player.duration), style: data.copyWith(color: hz.textMuted)),
                  const SizedBox(width: Gap.item),
                  Tooltip(
                    message: s.playerSpeed,
                    child: ActionChip(
                      onPressed: player.cycleSpeed,
                      avatar: const Icon(AppIcons.forward, size: 18),
                      label: Text('${speed == speed.roundToDouble() ? speed.toInt() : speed}×', style: data),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Sections of the history bar in the player.
const _densityBins = 80;

/// Bar per section of the recording, height relative to the fullest section;
/// in the accent color up to the playback position, neutral after it.
class _DensityPainter extends CustomPainter {
  _DensityPainter({required this.counts, required this.played, required this.color, required this.rest});

  final List<int> counts;
  final double played;
  final Color color;
  final Color rest;

  @override
  void paint(Canvas canvas, Size size) {
    final max = counts.fold(0, (a, b) => a > b ? a : b);
    if (max == 0) return;
    final slot = size.width / counts.length;
    final bar = (slot * 0.7).clamp(1.0, 6.0);
    for (var i = 0; i < counts.length; i++) {
      if (counts[i] == 0) continue;
      final h = 2 + (size.height - 2) * counts[i] / max;
      final x = i * slot + (slot - bar) / 2;
      final paint = Paint()..color = (i + 0.5) / counts.length <= played ? color : rest;
      canvas.drawRect(Rect.fromLTWH(x, size.height - h, bar, h), paint);
    }
  }

  @override
  bool shouldRepaint(_DensityPainter old) =>
      old.played != played || old.color != color || old.rest != rest || old.counts.length != counts.length;
}

/// Long-term history: set the retention, open days.
class _HistoryCard extends StatefulWidget {
  const _HistoryCard();

  @override
  State<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<_HistoryCard> {
  final _history = HistoryStore.instance;

  /// History of another installation (`null` = the active one), e.g. the week
  /// at the previous customer, without switching the box.
  String? _installation;
  late Future<List<HistoryDay>> _days = _history.days(installation: _installation);
  late Future<List<HistoryDay>> _withoutTime = _history.withoutTime(installation: _installation);

  /// Installations whose history can be shown: via the box its list, otherwise
  /// those on this device. Only in expert mode and when there are several.
  List<({String id, String name})> get _choices {
    final store = InstallationStore.instance;
    if (!expert || !store.switchable) return const [];
    final list = Addon.box != null
        ? [for (final MapEntry(:key, :value) in store.boxList.entries) (id: key, name: value)]
        : [for (final i in store.list) (id: i.id, name: i.name)];
    return list.length > 1 ? list : const [];
  }

  /// Add-on: recording outages per day (connection lost / add-on off).
  late Future<Map<DateTime, List<Outage>>> _outages = _loadOutages();

  /// Unexpected restarts of the server, if there were any.
  late Future<Map<String, Object?>?> _serverRestarts = _loadServerRestarts();

  void _reload() => setState(() {
    _days = _history.days(installation: _installation);
    _withoutTime = _history.withoutTime(installation: _installation);
    _outages = _loadOutages();
    _serverRestarts = _loadServerRestarts();
  });

  Future<Map<String, Object?>?> _loadServerRestarts() async {
    if (!HistoryStore.serverManaged) return null;
    try {
      return ((await Addon.status())['restarts'] as Map?)?.cast<String, Object?>();
    } on Object {
      return null;
    }
  }

  Future<Map<DateTime, List<Outage>>> _loadOutages() async {
    if (!HistoryStore.serverManaged) return const {};
    try {
      final days = await _days;
      if (days.isEmpty) return const {};
      // The server keeps outages for about three months and answers at most
      // 400 days per request.
      final now = DateTime.now();
      final earliest = now.subtract(const Duration(days: 399));
      final from = days.last.date.isBefore(earliest) ? earliest : days.last.date;
      final list = await Addon.outages(from, now, installation: _installation);
      return outagesByDay([for (final o in list) Outage.fromJson((o! as Map).cast<String, Object?>())]);
    } on Object {
      return const {};
    }
  }

  Future<bool> _confirmOff() async =>
      await showAdaptiveDialog<bool>(
        context: context,
        builder: (context) => AlertDialog.adaptive(
          title: Text(s.historyOffConfirmTitle),
          content: Text(s.historyOffHint),
          actions: [
            horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context, false)),
            horizontDialogAction(
              context,
              label: s.historyOffConfirm,
              primary: true,
              destructive: true,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _deleteDay(HistoryDay day) async {
    final ok = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        content: Text(s.historyDeleteDayConfirm(formatDate(day.date))),
        actions: [
          horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context, false)),
          horizontDialogAction(
            context,
            label: s.commonDelete,
            primary: true,
            destructive: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _history.delete(day);
    _reload();
  }

  static String _size(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).ceil()} KB'
      : '${localizeDecimal((bytes / 1024 / 1024).toStringAsFixed(1))} MB';

  Future<void> _open(HistoryDay day) async {
    final navigator = Navigator.of(context);
    await _history.flush();
    final recording = await _history.open(
      day,
      name: day.withoutTime ? s.historyWithoutTime : s.historyDayName(formatDate(day.date)),
    );
    await navigator.push(MaterialPageRoute<void>(builder: (_) => RecordingScreen(recording: recording)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final dayStyle = context.figures(theme.textTheme.bodyMedium).copyWith(fontWeight: FontWeight.w600);
    return SectionCard(
      title: s.historyTitle,
      // The explanation sits behind the info button; the card shows the choice.
      trailing: IconButton(
        tooltip: s.historyTitle,
        icon: Icon(AppIcons.info, color: hz.textMuted),
        onPressed: () => showAdaptiveDialog<void>(
          context: context,
          builder: (context) => AlertDialog.adaptive(
            title: Text(s.historyTitle),
            content: Text(s.historyExplain),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(MaterialLocalizations.of(context).okButtonLabel),
              ),
            ],
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_choices case final choices when choices.isNotEmpty) ...[
            Text(s.installationHistoryOf, style: theme.textTheme.labelLarge),
            const SizedBox(height: HzSpace.s8),
            Wrap(
              spacing: HzSpace.s8,
              runSpacing: HzSpace.s8,
              children: [
                for (final c in choices)
                  ChoiceChip(
                    label: Text(c.name),
                    selected: (_installation ?? InstallationStore.instance.active.id) == c.id,
                    onSelected: (_) {
                      _installation = c.id == InstallationStore.instance.active.id ? null : c.id;
                      _reload();
                    },
                  ),
              ],
            ),
          ],
          if (_choices.isNotEmpty) const SizedBox(height: Gap.inner),
          // Chips instead of a segmented bar: they wrap on the phone instead of being cut off.
          Wrap(
            spacing: HzSpace.s8,
            runSpacing: HzSpace.s8,
            children: [
              for (final d in HistoryStore.choices)
                ChoiceChip(
                  showCheckmark: false,
                  label: Text(d == 0 ? s.historyOff : s.historyDays(d)),
                  // Longer periods belong to Plus: a lock instead of hiding them.
                  avatar: d > Plan.instance.maxHistoryDays ? const Icon(AppIcons.locked, size: 16) : null,
                  selected: _history.retentionDays == d,
                  onSelected: (_) async {
                    final plan = Plan.instance;
                    if (d > plan.maxHistoryDays) {
                      await showPlanScreen(context, reason: s.planLongHistory);
                      if (d > plan.maxHistoryDays) return;
                    }
                    // Off deletes everything recorded: one tap on a chip must not do that.
                    if (d == 0 && _history.enabled && !await _confirmOff()) return;
                    await _history.setRetention(d);
                    _reload();
                  },
                ),
            ],
          ),
          if (!_history.enabled) ...[
            const SizedBox(height: HzSpace.s8),
            Text(s.historyOffHint, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
          ],
          if (_history.paused) ...[
            const SizedBox(height: HzSpace.s8),
            Text(s.historyPausedPlan, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
          ],
          if (HistoryStore.serverManaged && _history.enabled) ...[
            const SizedBox(height: Gap.inner),
            Text(s.historyMaxSize, style: theme.textTheme.labelLarge),
            const SizedBox(height: HzSpace.s8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  for (final mb in HistoryStore.sizeChoices)
                    ButtonSegment(value: mb, label: Text(mb >= 1000 ? '${mb ~/ 1000} GB' : '$mb MB')),
                ],
                selected: {HistoryStore.sizeChoices.contains(_history.maxMegabytes) ? _history.maxMegabytes : 1000},
                onSelectionChanged: (v) async {
                  await _history.configureServer(maxMegabytes: v.first);
                  _reload();
                },
              ),
            ),
            const SizedBox(height: Gap.inner),
            Text(s.historyWriteInterval, style: theme.textTheme.labelLarge),
            const SizedBox(height: HzSpace.s8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  for (final sec in HistoryStore.flushChoices)
                    ButtonSegment(
                      value: sec,
                      label: Text(switch (sec) {
                        0 => s.historyWriteNow,
                        < 60 => '$sec s',
                        _ => '${sec ~/ 60} min',
                      }),
                    ),
                ],
                selected: {HistoryStore.flushChoices.contains(_history.flushSeconds) ? _history.flushSeconds : 5},
                onSelectionChanged: (v) async {
                  await _history.configureServer(flushSeconds: v.first);
                  if (mounted) setState(() {});
                },
              ),
            ),
            const SizedBox(height: 4),
            Text(s.historyWriteHint, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
          ],
          FutureBuilder(
            future: _days,
            builder: (context, snapshot) {
              final days = snapshot.data ?? const <HistoryDay>[];
              if (!_history.enabled) return const SizedBox.shrink();
              final total = days.fold(0, (sum, d) => sum + d.bytes);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: Gap.inner),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          days.isEmpty ? s.historyEmpty : s.historyUsage(_size(total)),
                          style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                        ),
                      ),
                      if (days.isNotEmpty && _history.canDelete)
                        TextButton(
                          onPressed: () async {
                            final ok = await showAdaptiveDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog.adaptive(
                                content: Text(s.historyDeleteConfirm),
                                actions: [
                                  horizontDialogAction(
                                    context,
                                    label: s.commonCancel,
                                    onPressed: () => Navigator.pop(context, false),
                                  ),
                                  horizontDialogAction(
                                    context,
                                    label: s.historyDeleteAll,
                                    primary: true,
                                    destructive: true,
                                    onPressed: () => Navigator.pop(context, true),
                                  ),
                                ],
                              ),
                            );
                            if (ok != true) return;
                            await _history.deleteAll(installation: _installation);
                            _reload();
                          },
                          child: Text(s.historyDeleteAll),
                        ),
                    ],
                  ),
                  // Restarts next to the explained gaps in the history.
                  FutureBuilder(
                    future: _serverRestarts,
                    builder: (context, snapshot) => switch (snapshot.data) {
                      final restarts? => Padding(
                        padding: const EdgeInsets.only(bottom: HzSpace.s8),
                        child: ServerRestartsLine(restarts, showHistory: false),
                      ),
                      null => const SizedBox.shrink(),
                    },
                  ),
                  FutureBuilder(
                    future: _outages,
                    builder: (context, outageSnapshot) {
                      final outages = outageSnapshot.data ?? const {};
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Days as rows with hairlines; outages with a symbol.
                          if (days.isNotEmpty) const Divider(height: Lines.hairline),
                          for (final d in days)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: hz.line, width: Lines.hairline),
                                ),
                              ),
                              child: ListTile(
                                dense: true,
                                leading: Icon(AppIcons.history, color: hz.textMuted),
                                title: Text(formatDate(d.date), style: dayStyle),
                                subtitle: switch (outages[DateUtils.dateOnly(d.date)]) {
                                  final list? when list.isNotEmpty => Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(HorizontStatus.critical.icon, size: 14, color: hz.critical),
                                      const SizedBox(width: HzSpace.s4),
                                      Expanded(
                                        child: Text(
                                          outageSummary(list),
                                          style: theme.textTheme.bodySmall?.copyWith(color: hz.critical),
                                        ),
                                      ),
                                    ],
                                  ),
                                  _ => null,
                                },
                                trailing: Text(_size(d.bytes), style: dayStyle),
                                onTap: () => _open(d),
                                onLongPress: _history.canDelete ? () => _deleteDay(d) : null,
                              ),
                            ),
                          // If the box ran without a clock: no date that would be wrong.
                          FutureBuilder(
                            future: _withoutTime,
                            builder: (context, snapshot) => Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final d in snapshot.data ?? const <HistoryDay>[])
                                  ListTile(
                                    dense: true,
                                    leading: Icon(AppIcons.history, color: hz.textMuted),
                                    title: Text(s.historyWithoutTime, style: dayStyle),
                                    subtitle: Text(
                                      s.historyWithoutTimeHint,
                                      style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                                    ),
                                    trailing: Text(_size(d.bytes), style: dayStyle),
                                    onTap: () => _open(d),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

Recording _parseRecording(({Uint8List bytes, String name}) input) =>
    parseEtsXml(utf8.decode(input.bytes, allowMalformed: true), name: input.name);
