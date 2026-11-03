import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';
import 'package:share_plus/share_plus.dart';

import '../catalog_store.dart';
import '../export/diagnostics_bundle.dart';
import '../knx/knx_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/write_notice.dart';
import '../model/annotation.dart';
import '../model/export_history.dart';
import '../model/history_store.dart';
import '../model/installation.dart';
import '../model/recording.dart';
import '../model/send_scheduler.dart';
import '../model/telegram_log.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'annotation_editor.dart';
import 'common.dart';
import 'recordings_screen.dart';
import 'telegram_row.dart';

/// Opens "Diagnosepaket" (diagnostics package), from the menu (with a running
/// session) or directly from an error message ([error], [occurred]).
Future<void> showSupportPackage(
  BuildContext context, {
  KnxTunnel? tunnel,
  TelegramLog? log,
  List<Telegram>? session,
  String? error,
  DateTime? occurred,
  DateTime? since,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => SupportPackageScreen(
      tunnel: tunnel,
      log: log,
      session: session,
      error: error,
      occurred: occurred,
      since: since,
    ),
  ),
);

/// Time span of the recording around the error; `null` = everything.
const _ranges = <int?>[null, 5, 15, 60];

/// Diagnostics package for support: describe the problem, choose the recording
/// and time span, see what is inside (and remove names if needed), share.
class SupportPackageScreen extends StatefulWidget {
  const SupportPackageScreen({super.key, this.tunnel, this.log, this.session, this.error, this.occurred, this.since});

  /// From "Fehler melden" (report a fault): the session from this point until
  /// now instead of a time span around the error.
  final DateTime? since;

  final KnxTunnel? tunnel;

  /// Running session (counters for the technical details).
  final TelegramLog? log;

  /// All telegrams of the session; without them the (truncated) list of [log].
  final List<Telegram>? session;
  final String? error;
  final DateTime? occurred;

  @override
  State<SupportPackageScreen> createState() => _SupportPackageScreenState();
}

class _SupportPackageScreenState extends State<SupportPackageScreen> {
  final _problem = TextEditingController();
  final _expected = TextEditingController();
  late final DateTime _occurred = widget.occurred ?? DateTime.now();
  late final Future<Map<String, Object?>> _technical = collectTechnical(
    tunnel: widget.tunnel,
    log: widget.log,
    error: widget.error,
  );
  final _recordings = RecordingStore.instance;

  /// Days in the long-term history (a source even without a recording).
  List<HistoryDay> _days = const [];
  static const _historyPrefix = 'history:';

  /// Selected recording or history day ([_historyPrefix]); `null` = running session.
  String? _source;
  Recording? _recording;
  int? _minutes = 15;
  bool _keepNames = true;
  bool _busy = false;

  /// Screenshots are unfiltered: into the package only on explicit request.
  bool _includeShots = false;

  /// Screenshots of the problem (not attached to a comment); deleted again after
  /// sharing or leaving, as they are then in the package.
  List<String> _shots = [];

  /// Whether to include older comments (last [_olderDays] days) outside the time span.
  bool _older = true;
  static const _olderDays = 30;

  List<Telegram> get _sessionTelegrams => widget.session ?? widget.log?.log ?? const [];

  /// While the session keeps running, the preview grows with it, rebuilt at most
  /// every two seconds, not on every telegram.
  Timer? _grow;

  void _grew() {
    if (_grow?.isActive ?? false) return;
    _grow = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    widget.log?.addListener(_grew);
    _loadSources();
  }

  Future<void> _loadSources() async {
    await _recordings.load();
    List<HistoryDay> days;
    try {
      // Write buffered telegrams first, otherwise the last seconds are missing.
      await HistoryStore.instance.flush();
      days = await HistoryStore.instance.days();
    } on Object catch (e) {
      debugPrint('Verlauf nicht lesbar: $e');
      days = const [];
    }
    if (!mounted) return;
    setState(() => _days = days);
    // Without a session: suggest the more recent source, the newest recording or
    // the last history day; on the same day the recording (deliberately started).
    if (_sessionTelegrams.isNotEmpty) return;
    final recording = _recordings.summaries.firstOrNull;
    final day = days.firstOrNull;
    if (recording != null && (day == null || !DateUtils.dateOnly(day.date).isAfter(recording.ended))) {
      await _pick(recording.id);
    } else if (day != null) {
      await _pick('$_historyPrefix${day.path}');
    }
  }

  @override
  void dispose() {
    widget.log?.removeListener(_grew);
    _grow?.cancel();
    for (final id in _shots) {
      ShotStore.instance.delete(id);
    }
    _problem.dispose();
    _expected.dispose();
    super.dispose();
  }

  /// From "Fehler melden" (report a fault) and with the running session: from the start.
  bool get _sinceStart => widget.since != null && _source == null;

  // Exactly from the start, as displayed: earlier telegrams of the session do
  // not belong to the reported fault.
  DateTime? get _from =>
      _sinceStart ? widget.since! : (_minutes == null ? null : _anchor.subtract(Duration(minutes: _minutes!)));
  DateTime? get _to => _sinceStart ? null : (_minutes == null ? null : _anchor.add(const Duration(minutes: 1)));

  /// Comments in the time span: those of the recording (foreign package) or of the installation.
  List<Annotation> get _inRange {
    final r = _recording;
    final all = r != null && r.diagnostics != null ? r.annotations : AnnotationStore.instance.all;
    return [
      for (final a in all)
        if ((_from == null || !a.time.isBefore(_from!)) && (_to == null || !a.time.isAfter(_to!))) a,
    ];
  }

  /// Older comments of the installation outside the time span.
  List<Annotation> get _olderNotes {
    if (_from == null) return const [];
    final since = DateTime.now().subtract(const Duration(days: _olderDays));
    final inRange = {for (final a in _inRange) a.id};
    return [
      for (final a in AnnotationStore.instance.inRange(since, null))
        if (!inRange.contains(a.id)) a,
    ];
  }

  /// All screenshots available for selection (comments and problem description).
  Set<String> get _shotIds => {
    ..._shots,
    for (final a in [..._inRange, if (_older) ..._olderNotes]) ...a.shots,
  };

  /// The screenshots for the package; none without consent.
  Future<Map<String, Uint8List>> _shotBytes() async {
    final result = <String, Uint8List>{};
    if (!_includeShots) return result;
    for (final id in _shotIds.take(maxShotsPerPackage)) {
      final bytes = await ShotStore.instance.read(id);
      if (bytes != null) result[id] = bytes;
    }
    return result;
  }

  Future<void> _pick(String? id) async {
    setState(() {
      _source = id;
      _recording = null;
    });
    if (id == null) return;
    final Recording r;
    if (id.startsWith(_historyPrefix)) {
      final day = _days.firstWhere((d) => '$_historyPrefix${d.path}' == id);
      await HistoryStore.instance.flush();
      r = await HistoryStore.instance.open(day, name: s.diagSourceHistory(formatDate(day.date)));
    } else {
      r = await _recordings.open(id);
    }
    if (mounted && _source == id) setState(() => _recording = r);
  }

  List<Telegram> get _telegrams => _source == null ? _sessionTelegrams : (_recording?.telegrams ?? const []);

  /// Time of the error for the time span: for a recording, its end.
  DateTime get _anchor => _source == null ? _occurred : (_recording?.ended ?? _occurred);

  /// Preview without free text, rebuilt only when the selection changes, not on
  /// every keystroke (the session can have 200 000 telegrams).
  DiagnosticsPackage? _preview;
  Object? _previewKey;

  DiagnosticsPackage _previewOf(Map<String, Object?> technical) {
    final key = (
      _source,
      _recording,
      _minutes,
      _keepNames,
      _telegrams.length,
      technical,
      _older,
      AnnotationStore.instance.all.length,
    );
    if (_preview == null || _previewKey != key) {
      _previewKey = key;
      _preview = _build(technical, withText: false);
    }
    return _preview!;
  }

  DiagnosticsPackage _build(
    Map<String, Object?> technical, {
    bool withText = true,
    Map<String, Uint8List> shots = const {},
  }) {
    final store = CatalogStore.instance;
    return buildDiagnosticsPackage(
      annotations: _inRange,
      olderAnnotations: _older ? _olderNotes : const [],
      shots: shots,
      packageShots: _shots,
      includeShots: _includeShots,
      telegrams: _telegrams,
      catalog: store.catalog,
      overrides: store.overrides,
      secureAddresses: secureGroupAddresses(),
      occurred: _occurred,
      from: _from,
      to: _to,
      problem: withText ? _problem.text : '',
      expected: withText ? _expected.text : null,
      keepNames: _keepNames,
      technical: technical,
      log: appLogLines(),
      knownNames: knownPrivateNames(tunnel: widget.tunnel),
    );
  }

  /// Share menu (iOS, iPadOS, Android), otherwise a save dialog or download.
  Future<void> _export(Rect? origin) async {
    setState(() => _busy = true);
    try {
      final package = _build(await _technical, shots: await _shotBytes());
      final bytes = package.toZip();
      final name = fileName('KNX-Diagnose', 'zip');
      if (!mounted) return;
      // Large packages often do not fit into an email as an attachment.
      if (bytes.length > 20 * 1024 * 1024) {
        showHorizontMessage(context, s.diagLarge((bytes.length / 1024 / 1024).round()), status: HorizontStatus.warning);
      }
      if (_shares) {
        unawaited(ExportHistory.instance.add(name, bytes, 'application/zip'));
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile.fromData(bytes, mimeType: 'application/zip', name: name)],
            fileNameOverrides: [name],
            sharePositionOrigin: origin,
          ),
        );
      } else {
        await saveBytes(context, bytes, name, mimeType: 'application/zip');
      }
    } on Exception catch (e) {
      if (mounted) showHorizontMessage(context, s.exportFailed('$e'), status: HorizontStatus.critical);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static bool get _shares =>
      !kIsWeb && const {TargetPlatform.iOS, TargetPlatform.android}.contains(defaultTargetPlatform);

  Future<void> _showFile() async {
    final text = const JsonEncoder.withIndent('  ').convert(_build(await _technical).manifest);
    if (!mounted) return;
    await showAdaptiveDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog.adaptive(
        title: Text('diagnostics.json'),
        content: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            width: Widths.reading,
            height: MediaQuery.sizeOf(dialog).height * 0.6,
            child: SingleChildScrollView(
              child: SelectableText(text, style: dialog.mono(Theme.of(dialog).textTheme.bodySmall)),
            ),
          ),
        ),
        actions: [
          horizontDialogAction(dialog, label: s.commonClose, primary: true, onPressed: () => Navigator.pop(dialog)),
        ],
      ),
    );
  }

  /// A few names from the project as an example for the switch.
  static List<String> _exampleNames() {
    final catalog = CatalogStore.instance.catalog;
    return [
      ...catalog.groups.values.map((g) => g.name).where((n) => n.isNotEmpty).take(2),
      ...catalog.devices.values.where((d) => !d.isTunnel).map((d) => d.name).take(1),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: hz.textMuted);
    final examples = _exampleNames();
    final width = MediaQuery.sizeOf(context).width;
    final gutter = Gap.gutterFor(width);
    // Two columns as soon as two card columns fit (iPad landscape, Mac): the
    // description on the left, recording, content and sharing on the right.
    final columns = width.clamp(0, Widths.wide + 2 * gutter) - 2 * gutter >= 2 * Widths.column + Gap.section * 2;
    final side =
        gutter + ((width - 2 * gutter - (columns ? Widths.wide : Widths.reading)) / 2).clamp(0, double.infinity);
    return Scaffold(
      appBar: AppBar(title: Text(s.diagTitle)),
      body: FutureBuilder(
        future: _technical,
        builder: (context, snapshot) {
          final package = snapshot.data == null ? null : _previewOf(snapshot.data!);
          final describe = <Widget>[
            HorizontField(
              label: s.diagProblemLabel,
              child: TextField(
                style: context.hzTheme.field,
                controller: _problem,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: s.diagProblemHint),
              ),
            ),
            const SizedBox(height: HzSpace.s12),
            HorizontField(
              label: s.diagExpectedLabel,
              child: TextField(
                style: context.hzTheme.field,
                controller: _expected,
                minLines: 2,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(),
              ),
            ),
            const SizedBox(height: Gap.item),
            Text(s.diagOccurred(_dateTime(_occurred)), style: muted),
            const SizedBox(height: HzSpace.s16),
            ShotPicker(shots: _shots, onChanged: (v) => setState(() => _shots = v)),
            if (_shotIds.isNotEmpty) ...[
              const SizedBox(height: HzSpace.s8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(s.diagShotsTitle),
                subtitle: Text(s.diagShotsHint),
                value: _includeShots,
                onChanged: (v) => setState(() => _includeShots = v),
              ),
            ],
          ];
          final data = <Widget>[
            Kennung(s.diagSourceLabel),
            const SizedBox(height: HzSpace.s8),
            ListenableBuilder(
              listenable: _recordings,
              builder: (context, _) => DropdownButtonFormField<String?>(
                // Rebuild when the source changes by itself (suggestion on opening).
                key: ValueKey((_source, _days.length, _recordings.summaries.length)),
                initialValue: _source,
                isExpanded: true,
                items: [
                  DropdownMenuItem(value: null, child: Text(s.diagSourceSession(_sessionTelegrams.length))),
                  for (final r in _recordings.summaries)
                    DropdownMenuItem(
                      value: r.id,
                      child: Text('${r.name}$metaSeparator${r.count}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  for (final d in _days)
                    DropdownMenuItem(
                      value: '$_historyPrefix${d.path}',
                      child: Text(
                        s.diagSourceHistory(formatDate(d.date)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _pick,
              ),
            ),
            const SizedBox(height: Gap.inner),
            if (_sinceStart)
              Text(s.diagRangeSince(formatTime(widget.since!, millis: false)), style: muted)
            else ...[
              Kennung(s.diagRangeLabel),
              const SizedBox(height: HzSpace.s8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<int?>(
                  showSelectedIcon: false,
                  segments: [
                    for (final m in _ranges)
                      ButtonSegment(value: m, label: Text(m == null ? s.diagRangeAll : s.diagRangeMinutes(m))),
                  ],
                  selected: {_minutes},
                  onSelectionChanged: (v) => setState(() => _minutes = v.first),
                ),
              ),
              const SizedBox(height: HzSpace.s4),
              Text(s.diagRangeHint, style: muted),
            ],
            const SizedBox(height: HzSpace.s16),
            ListenableBuilder(
              listenable: AnnotationStore.instance,
              builder: (context, _) {
                final older = _olderNotes.length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(s.diagAnnotationsInRange(_inRange.length), style: muted),
                    if (older > 0)
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(s.diagOlderAnnotations(older)),
                        subtitle: SwitchHint(s.diagOlderAnnotationsHint(_olderDays)),
                        value: _older,
                        onChanged: (v) => setState(() => _older = v),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: HzSpace.s8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(s.diagNamesTitle),
              subtitle: Text(
                examples.isEmpty ? s.diagNamesHintEmpty : s.diagNamesHint(examples.map((n) => '„$n“').join(', ')),
              ),
              value: _keepNames,
              onChanged: (v) => setState(() => _keepNames = v),
            ),
            const SizedBox(height: Gap.section),
            SectionCard(
              title: s.diagContents,
              soft: true,
              child: package == null
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : _Contents(
                      package: package,
                      // From the comments themselves: the preview carries no image data,
                      // so its comments carry no image references either.
                      shots: _includeShots ? _shotIds.length.clamp(0, maxShotsPerPackage) : 0,
                      shotsLeftOut: _includeShots ? 0 : _shotIds.length,
                    ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(onPressed: package == null ? null : _showFile, child: Text(s.diagShowFile)),
            ),
            const SizedBox(height: Gap.section),
            Builder(
              builder: (buttonContext) => FilledButton.icon(
                onPressed: package == null || _busy ? null : () => _export(rectOf(buttonContext)),
                icon: Icon(_shares ? AppIcons.share : AppIcons.save),
                label: Text(_shares ? s.diagShare : (kIsWeb ? s.diagDownload : s.diagSave)),
              ),
            ),
          ];
          return ListView(
            padding: EdgeInsets.fromLTRB(side, Gap.page.top, side, Gap.page.bottom),
            children: [
              Text(s.diagIntro, style: theme.textTheme.bodyMedium),
              if (widget.error case final error?) ...[
                const SizedBox(height: Gap.section),
                HorizontNotice(HorizontStatus.critical, child: Text(error)),
              ],
              const SizedBox(height: Gap.section),
              if (columns)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Gap.section * 2,
                  children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: describe),
                    ),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: data),
                    ),
                  ],
                )
              else ...[
                ...describe,
                const SizedBox(height: HzSpace.s24),
                ...data,
              ],
            ],
          );
        },
      ),
    );
  }
}

/// What is in the package, and what is not.
class _Contents extends StatelessWidget {
  const _Contents({required this.package, this.shots = 0, this.shotsLeftOut = 0});

  final DiagnosticsPackage package;

  /// Screenshots in the package (the preview carries no image data yet).
  final int shots;

  /// Screenshots left out for lack of consent.
  final int shotsLeftOut;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final theme = Theme.of(context);
    final r = package.recording;
    Widget line(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: HzSpace.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: hz.textMuted),
          const SizedBox(width: HzSpace.s8),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        line(AppIcons.recordings, s.diagContentRecording(r.telegrams.length, _dateTime(r.started), _dateTime(r.ended))),
        if (package.secureTelegrams.isNotEmpty)
          line(AppIcons.secure, s.diagContentSecure(package.secureTelegrams.length)),
        line(AppIcons.projectCheck, s.diagContentProject(package.catalog.length, package.catalog.devices.length)),
        line(AppIcons.edit, package.namesIncluded ? s.diagContentNamesIn : s.diagContentNamesOut),
        line(AppIcons.info, s.diagContentTechnical),
        if (WriteNotice.instance.dismissedAt case final at?)
          line(AppIcons.info, s.diagContentWriteNotice(at.toLocal().toIso8601String().substring(0, 10))),
        if (package.log.isNotEmpty) line(AppIcons.diagnostics, s.diagContentLog(package.log.length)),
        if (package.recording.annotations.isNotEmpty || shots > 0)
          line(AppIcons.annotation, s.diagContentAnnotations(package.recording.annotations.length, shots)),
        if (shotsLeftOut > 0) line(AppIcons.annotation, s.diagContentShotsOut(shotsLeftOut)),
        const SizedBox(height: HzSpace.s4),
        Text(s.diagExcluded, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
        const SizedBox(height: HzSpace.s4),
        Text(s.diagNotFiltered, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
      ],
    );
  }
}

/// "14.10.2026 15:20" or "2026-10-14 15:20".
String _dateTime(DateTime t) => '${formatDate(t)} ${formatTime(t, seconds: false)}';

/// Opens a diagnostics package: the project as a new installation, the recording
/// with it, then the recording with the player. In the add-on (one installation)
/// only the recording, so the installation keeps its project. Throws [FormatException].
Future<void> openSupportPackage(BuildContext context, Uint8List bytes) async {
  final package = DiagnosticsPackage.fromZip(bytes);
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final colors = context.hz;
  final installations = InstallationStore.instance;
  final tunnel = SendScheduler.instance.tunnel;
  if (installations.switchable && tunnel != null && tunnel.state.value != TunnelState.disconnected) {
    messenger.showSnackBar(horizontMessageSnackBar(colors, s.diagImportDisconnect, status: HorizontStatus.warning));
    return;
  }
  final note = [
    if (package.problem.isNotEmpty) s.diagNoteProblem(package.problem),
    if (package.expected case final expected?) s.diagNoteExpected(expected),
  ].join('\n');
  String? installation;
  if (installations.switchable) {
    final i = await installations.create(s.diagInstallationName(_dateTime(package.occurred)));
    await installations.switchTo(i.id);
    await CatalogStore.instance.adopt(package.catalog, name: 'diagnostics.zip', overrides: package.overrides);
    installation = i.id;
    messenger.showSnackBar(horizontMessageSnackBar(colors, s.diagImported(i.name), status: HorizontStatus.positive));
  } else {
    messenger.showSnackBar(
      horizontMessageSnackBar(colors, s.diagImportedRecordingOnly, status: HorizontStatus.positive),
    );
  }
  // Screenshots under new IDs into our own storage: a package from this
  // installation would otherwise carry the IDs of its own comments, and
  // deleting the recording would take their images with it.
  final ids = <String, String>{};
  for (final (i, MapEntry(key: id, value: jpeg)) in package.shots.entries.indexed) {
    ids[id] = await ShotStore.instance.put(jpeg, id: '${Annotation.newId()}${i.toRadixString(36)}', checkQuota: false);
  }
  List<String> remap(List<String> shots) => [for (final id in shots) ?ids[id]];
  final p = package.recording;
  final recording = Recording(
    id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
    name: p.name,
    note: note.isEmpty ? null : note,
    started: p.started,
    ended: p.ended,
    project: p.project,
    installation: installation,
    telegrams: p.telegrams,
    annotations: [for (final a in p.annotations) a.copyWith(shots: remap(a.shots))],
    // For the finding: problem description, technical details, log and the screenshots.
    diagnostics: {
      'created': package.created.toIso8601String(),
      'occurred': package.occurred.toIso8601String(),
      'problem': package.problem,
      'expected': ?package.expected,
      'namesIncluded': package.namesIncluded,
      'technical': package.technical,
      'log': package.log,
      'shots': remap(package.packageShots),
      'secureTelegrams': package.secureTelegrams.length,
    },
  );
  await RecordingStore.instance.save(recording);
  await navigator.push(
    MaterialPageRoute<void>(builder: (_) => RecordingScreen(recording: recording, showFindings: true)),
  );
}
