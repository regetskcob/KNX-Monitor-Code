import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../export/pdf_export.dart';
import '../knx/knx_tunnel.dart';
import '../knx/read_sweep.dart';
import '../l10n/locale_controller.dart';
import '../model/commissioning.dart';
import '../model/communication_map.dart';
import '../model/health.dart';
import '../model/telegram_log.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'commissioning_screen.dart';
import 'communication_map_screen.dart';
import 'details_sheet.dart';
import 'device_sheet.dart';
import 'figure_box.dart';
import 'telegram_row.dart';
import '../model/plan.dart';
import 'plan_screen.dart';

/// Horizont status per severity: symbol and color come from it, the word from
/// [severityWord]; never color alone.
HorizontStatus severityStatus(Severity s) => switch (s) {
  Severity.ok => HorizontStatus.positive,
  Severity.info => HorizontStatus.info,
  Severity.warning => HorizontStatus.warning,
  Severity.error => HorizontStatus.critical,
};

/// Word for the severity (screen reader, badges).
String severityWord(Severity v) => switch (v) {
  Severity.ok => s.hzCSeverityOk,
  Severity.info => s.hzCSeverityInfo,
  Severity.warning => s.hzCSeverityWarning,
  Severity.error => s.hzCSeverityError,
};

String areaLabel(HealthArea a) => switch (a) {
  HealthArea.read => s.healthAreaRead,
  HealthArea.cycle => s.healthAreaCycle,
  HealthArea.readings => s.healthAreaValues,
  HealthArea.dpt => s.healthAreaDpt,
  HealthArea.bus => s.healthAreaBus,
};

/// The "Gesundheit" (health) tool: recurring check compared with the last run.
class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key, required this.tunnel, required this.log, this.gateway});

  final KnxTunnel tunnel;
  final TelegramLog log;
  final String? gateway;

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  final _h = HealthCheck.instance;

  /// Run being shown (default: the latest).
  HealthRun? _shown;

  @override
  void initState() {
    super.initState();
    _h.load();
    HealthAutoRun.instance.load();
  }

  Future<void> _run({bool readTest = true}) async {
    final run = await _h.run(widget.tunnel, widget.log, readTest: readTest);
    if (mounted && run != null) setState(() => _shown = null);
  }

  /// Add conspicuous addresses to the checklist and open commissioning right
  /// away.
  Future<void> _toCommissioning(HealthRun run) async {
    final addresses = {
      for (final f in run.findings)
        if (!f.kind.device && f.kind.severity.index >= Severity.warning.index) f.address,
    };
    if (!await unlock(context, Feature.commissioning) || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await Commissioning.instance.load();
    Commissioning.instance.prepare(addresses);
    messenger.showSnackBar(SnackBar(content: Text(s.healthAddedToCommissioning(addresses.length))));
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => CommissioningScreen(tunnel: widget.tunnel, gateway: widget.gateway, log: widget.log),
      ),
    );
  }

  /// Opens a finding: a device in the device sheet, an address in the details
  /// (which lead on to map, chart and reading). Without a telegram, the map.
  Future<void> _open(HealthFinding f) async {
    final log = widget.log;
    if (f.kind.device) {
      return showDeviceSheet(context, address: f.address, log: log);
    }
    final history = log.forAddress(f.address);
    final telegram = log.latest[f.address] ?? (history.isEmpty ? null : history.last);
    if (telegram != null) {
      return showDetailsSheet(
        context,
        telegram,
        tunnel: widget.tunnel,
        history: history,
        gateway: widget.gateway,
        onOpenDevice: (pa) => showDeviceSheet(context, address: pa, log: log),
        onOpenMap: _openMap,
        log: log,
      );
    }
    await _openMap(f.address);
  }

  Future<void> _openMap(int ga) async {
    if (!await unlock(context, Feature.communicationMap) || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunicationMapScreen(log: widget.log, start: MapNode.group(ga)),
      ),
    );
  }

  /// Selected area; `null` = the first one with findings.
  HealthArea? _area;

  HealthArea _areaOf(HealthRun? run) =>
      _area ??
      (run == null
          ? HealthArea.read
          : HealthArea.values.firstWhere((a) => run.countIn(a) > 0, orElse: () => HealthArea.read));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_h, HealthAutoRun.instance]),
      builder: (context, _) {
        final run = _shown ?? _h.last;
        return Scaffold(
          appBar: AppBar(
            title: Text(s.healthTitle),
            actions: [
              Builder(
                builder: (buttonContext) => IconButton(
                  tooltip: s.healthPdfTitle,
                  onPressed: run == null
                      ? null
                      : () => sharePdf(
                          context,
                          () async => HealthPdf(run, gateway: widget.gateway),
                          pdfName(s.healthPdfTitle),
                          origin: rectOf(buttonContext),
                        ),
                  icon: const Icon(AppIcons.pdf),
                ),
              ),
              IconButton(
                tooltip: s.healthTitle,
                onPressed: () => showInfoDialog(context, title: s.healthTitle, content: Text(s.healthExplain)),
                icon: const Icon(AppIcons.info),
              ),
            ],
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ListView(
              padding: Gap.page,
              children: [
                _header(context, run),
                if (run != null) ..._findings(context, run),
                const SizedBox(height: Gap.section),
                _quietOptions(context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, HealthRun? run) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final count = _h.addressesToRead().length;
    final meta = theme.textTheme.bodySmall?.copyWith(color: hz.accentText);
    final Widget action;
    if (_h.running) {
      action = OutlinedButton(onPressed: _h.cancel, child: Text(s.commonCancel));
    } else if (count == 0) {
      // Nothing to read: "Jetzt prüfen (0 Adressen)" would only evaluate.
      action = FilledButton(onPressed: () => _run(readTest: false), child: Text(s.healthPassive));
    } else {
      action = FilledButton(
        onPressed: () => _run(),
        // The duration belongs to reading, not evaluating: shown right in the
        // button.
        child: Text('${s.healthRunNow(count)} · ≈ ${ReadSweep.estimate(count).inSeconds} s'),
      );
    }
    return FigureBox(
      above: run == null && !_h.running
          ? Text(s.healthExplain, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted))
          : null,
      figures: [
        if (run != null && run.asked > 0)
          (label: s.commAnswered, value: '${run.answered} / ${run.asked}', status: null),
        if (run != null) (label: s.healthAreaRead, value: formatInt(run.countIn(HealthArea.read)), status: null),
      ],
      footer: Row(
        children: [
          Expanded(
            child: Text(
              _h.running && _h.toSend > 0
                  ? s.healthRunning(_h.sent, _h.toSend)
                  : run == null
                  ? s.healthNever
                  : s.healthLastRun('${formatDate(run.time)} ${formatTime(run.time, millis: false)}'),
              style: meta,
            ),
          ),
          if (_h.runs.length > 1)
            TextButton(
              onPressed: () => _showHistory(context),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.healthHistory),
                  const SizedBox(width: HzSpace.s2),
                  const Icon(AppIcons.next, size: 14),
                ],
              ),
            ),
        ],
      ),
      below: _h.running
          ? LinearProgressIndicator(
              value: _h.toSend == 0 ? null : _h.progress,
              minHeight: HzSpace.s4,
              borderRadius: Radii.row,
            )
          : !_h.running && count == 0
          ? Text(s.healthNothingToRead, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted))
          : null,
      action: action,
    );
  }

  /// What the design does not show but stays reachable: evaluate only and the
  /// automatic switch, kept close to the text (on wide pages it would otherwise
  /// sit at the far end).
  Widget _quietOptions(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Widths.column),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_h.running && _h.addressesToRead().isNotEmpty)
            TextButton(onPressed: () => _run(readTest: false), child: Text(s.healthPassive)),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(s.healthAuto),
            value: HealthAutoRun.instance.value,
            onChanged: HealthAutoRun.instance.set,
          ),
        ],
      ),
    ),
  );

  /// Short word per area for the segmented toggle.
  String _areaShort(HealthArea area) => area == HealthArea.dpt ? s.haTypes : areaLabel(area);

  List<Widget> _findings(BuildContext context, HealthRun run) {
    if (run.findings.isEmpty) {
      return [const SizedBox(height: Gap.section), HorizontEmptyHint(icon: AppIcons.success, text: s.healthAllGood)];
    }
    final area = _areaOf(run);
    final inArea = [
      for (final f in run.findings)
        if (f.kind.area == area) f,
    ];
    return [
      const SizedBox(height: Gap.section),
      FilterBar<HealthArea>(
        segments: [
          for (final a in HealthArea.values)
            // Bus only with findings: otherwise the segments don't fit on a
            // phone.
            if (a != HealthArea.bus || run.countIn(a) > 0 || a == area)
              ButtonSegment(
                value: a,
                label: Text('${_areaShort(a)} · ${formatInt(run.countIn(a))}'),
                tooltip: '${areaLabel(a)} · ${severityWord(run.worst(a))}',
              ),
        ],
        selected: area,
        onChanged: (a) => setState(() => _area = a),
      ),
      const SizedBox(height: Gap.inner),
      if (inArea.isEmpty)
        HorizontEmptyHint(icon: AppIcons.success, text: s.healthAllGood)
      else
        _areaList(context, area, inArea, run),
      if (run.findings.any((f) => f.kind.severity.index >= Severity.warning.index && !f.kind.device)) ...[
        const SizedBox(height: Gap.section),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: () => _toCommissioning(run),
            icon: const Icon(AppIcons.projectCheck, size: 18),
            label: Text(s.healthToCommissioning),
          ),
        ),
      ],
    ];
  }

  /// Findings of an area: new ones first under their own title, two columns
  /// when wide. Plain hints (info, not new) collapse so warnings and errors
  /// don't get lost in a long list.
  Widget _areaList(BuildContext context, HealthArea area, List<HealthFinding> findings, HealthRun run) {
    bool minor(HealthFinding f) => f.kind.severity.index < Severity.warning.index;
    final fresh = [
      for (final f in findings)
        if (run.isNew(f)) f,
    ];
    final main = [
      for (final f in findings)
        if (!run.isNew(f) && !minor(f)) f,
    ];
    final rest = [
      for (final f in findings)
        if (!run.isNew(f) && minor(f)) f,
    ];
    final open = _openMinor.contains(area) || (main.isEmpty && fresh.isEmpty);
    Widget rows(List<HealthFinding> list) => _FindingColumns(
      children: [for (final f in list) _FindingRow(finding: f, isNew: run.isNew(f), onTap: () => _open(f))],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fresh.isNotEmpty) ...[
          SectionTitle(s.healthNewSection, count: fresh.length),
          const SizedBox(height: Gap.item),
          rows(fresh),
          if (main.isNotEmpty) const SizedBox(height: Gap.inner),
        ],
        if (main.isNotEmpty) rows(main),
        if (rest.isNotEmpty && (main.isNotEmpty || fresh.isNotEmpty))
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() => open ? _openMinor.remove(area) : _openMinor.add(area)),
              icon: AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: Motion.of(context),
                curve: Motion.curve,
                child: const Icon(AppIcons.expand, size: 18),
              ),
              label: Text(open ? s.healthHideNotes : s.healthShowNotes(rest.length)),
            ),
          ),
        AnimatedSize(
          duration: Motion.calmOf(context),
          curve: Motion.settle,
          alignment: Alignment.topCenter,
          child: open && rest.isNotEmpty ? rows(rest) : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  /// Areas whose hints are expanded.
  final _openMinor = <HealthArea>{};

  /// Earlier runs in a sheet; tapping one shows that run on the page.
  Future<void> _showHistory(BuildContext context) {
    final current = _shown ?? _h.last;
    final shown = _h.runs.take(14).toList();
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (sheet) {
        final theme = Theme.of(sheet);
        final hz = sheet.hz;
        return SafeArea(
          top: false,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, Gap.gutter),
            children: [
              SectionTitle(s.healthHistory, count: shown.length),
              const SizedBox(height: Gap.item),
              for (final r in shown)
                Builder(
                  builder: (_) {
                    final worst = HealthArea.values.map(r.worst).fold(Severity.ok, (a, b) => b.index > a.index ? b : a);
                    final status = severityStatus(worst);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      selected: identical(r, current),
                      leading: Icon(status.icon, color: status.color(hz), semanticLabel: severityWord(worst)),
                      title: Text(
                        '${formatDate(r.time)} ${formatTime(r.time, millis: false)}',
                        style: sheet.figures(theme.textTheme.bodyLarge),
                      ),
                      trailing: Text(
                        formatInt(r.findings.length),
                        style: sheet.figures(theme.textTheme.bodyLarge).copyWith(fontWeight: FontWeight.w600),
                      ),
                      onTap: () {
                        setState(() => _shown = r);
                        Navigator.pop(sheet);
                      },
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Befundzeilen untereinander, breit in zwei gleich langen Spalten.
class _FindingColumns extends StatelessWidget {
  const _FindingColumns({required this.children});

  final List<Widget> children;

  static Widget _column(List<Widget> rows) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, row) in rows.indexed) ...[if (i > 0) const Divider(height: Lines.hairline), row],
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxWidth < Breakpoints.expanded || children.length < 2) return _column(children);
      final half = (children.length + 1) ~/ 2;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Gap.section,
        children: [
          Expanded(child: _column(children.sublist(0, half))),
          Expanded(child: _column(children.sublist(half))),
        ],
      );
    },
  );
}

/// Address and name with the finding quietly below; on the right the symbol
/// only for warnings and errors (with the severity read aloud), then the
/// chevron.
class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.finding, required this.isNew, required this.onTap});

  final HealthFinding finding;
  final bool isNew;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final severity = finding.kind.severity;
    final status = severityStatus(severity);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: HzSpace.s4, vertical: HzSpace.s12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: AddressTitle(findingTitle(finding))),
                      if (isNew) ...[
                        const SizedBox(width: Gap.item),
                        HorizontBadge(HorizontStatus.info, label: s.healthNew),
                      ],
                    ],
                  ),
                  Text(
                    findingDetail(finding),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Gap.item),
            if (severity.index >= Severity.warning.index) ...[
              Icon(status.icon, size: HzIconSize.row, color: status.color(hz), semanticLabel: severityWord(severity)),
              const SizedBox(width: HzSpace.s4),
            ],
            Icon(AppIcons.next, size: HzIconSize.row, color: hz.textFaint),
          ],
        ),
      ),
    );
  }
}
