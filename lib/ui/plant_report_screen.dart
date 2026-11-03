import 'dart:async';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../export/pdf_export.dart';
import '../l10n/locale_controller.dart';
import '../model/customer.dart';
import '../model/installation.dart';
import '../model/plant_report.dart';
import '../platform/addon.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'telegram_row.dart' show formatDate, formatTime;

/// Text of a finding for screen and PDF.
String plantFindingText(Map<String, Object?> f) {
  final label = [f['label'], f['name']].whereType<String>().join(' ');
  final since = f['since'] is int ? formatDate(DateTime.fromMillisecondsSinceEpoch(f['since']! as int)) : '—';
  final rate = localizeDecimal((((f['rate'] as num?) ?? 0) * 100).toStringAsFixed(1));
  return switch (f['kind']) {
    'deviceSilent' => s.plantDeviceSilent(label, since),
    'cyclicSilent' => s.plantCyclicSilent(label, since),
    'stuck' => s.plantStuck(label, since),
    'repeats' => s.plantRepeats(label, rate),
    'busLoad' => s.plantBusLoad(rate),
    'busErrors' => s.plantBusErrors(rate),
    'outages' => s.plantOutages(rate),
    'restarts' => s.plantRestarts((f['count'] as int?) ?? 0),
    'alarmActive' => s.plantAlarmActive(label, since),
    'faultActive' => s.plantFaultActive(label, since),
    'batteryLow' => s.plantBatteryLow(label, since),
    _ => label,
  };
}

/// How a finding compares to the previous report.
String? plantFindingStatus(Object? status) => switch (status) {
  'new' => s.plantStatusNew,
  'unchanged' => s.plantStatusUnchanged,
  'resolved' => s.plantStatusResolved,
  _ => null,
};

/// Period as text, e.g. "01.10.2026 – 31.10.2026".
String plantPeriodText(DateTime from, DateTime to) =>
    '${formatDate(from)} – ${formatDate(to.subtract(const Duration(milliseconds: 1)))}';

/// Reason for a failure, for the user.
String plantNotifyError(String code) => switch (code) {
  'off' => s.plantNotifyErrorOff,
  'timeout' => s.plantNotifyErrorTimeout,
  'invalid' => s.plantNotifyErrorInvalid,
  'network' => s.plantNotifyErrorNetwork,
  _ => s.plantNotifyErrorHttp(code.replaceFirst('http', '')),
};

/// Installation report (Pro, free in the add-on): settings, notifications and
/// the reports from the box or add-on. Off by default; nothing leaves the server
/// as long as the user chooses no destination.
class PlantReportScreen extends StatefulWidget {
  const PlantReportScreen({super.key, this.client = const PlantReportClient()});

  final PlantReportClient client;

  @override
  State<PlantReportScreen> createState() => _PlantReportScreenState();
}

class _PlantReportScreenState extends State<PlantReportScreen> {
  PlantReportOverview? _overview;
  String? _error;
  bool _busy = false;
  final _url = TextEditingController();
  final _topic = TextEditingController();
  final _token = TextEditingController();
  String _kind = 'off';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(MaintenanceSync.instance.push(force: true));
  }

  @override
  void dispose() {
    _url.dispose();
    _topic.dispose();
    _token.dispose();
    super.dispose();
  }

  void _apply(PlantReportOverview o) {
    _overview = o;
    _error = null;
    _kind = o.notifyKind;
    _url.text = o.notifyUrl;
    _topic.text = o.notifyTopic;
    _token.clear();
  }

  Future<void> _load() async {
    try {
      final o = await widget.client.overview();
      if (mounted) setState(() => _apply(o));
    } on AddonException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _configure(Map<String, Object?> changes) async {
    setState(() => _busy = true);
    try {
      final o = await widget.client.configure(changes);
      if (mounted) setState(() => _apply(o));
    } on AddonException catch (e) {
      if (mounted) setState(() => _error = e.message.startsWith('notify') ? s.plantNotifyErrorInvalid : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, Object?> get _target => {
    'notifyKind': _kind,
    'notifyUrl': _url.text.trim(),
    'notifyTopic': _topic.text.trim(),
    if (_token.text.isNotEmpty) 'notifyToken': _token.text,
  };

  Future<void> _test() async {
    final messenger = ScaffoldMessenger.of(context);
    await _configure(_target);
    if (_error != null) return;
    try {
      final error = await widget.client.sendTest();
      messenger.showSnackBar(
        SnackBar(content: Text(error == null ? s.plantTestSent : s.plantTestFailed(plantNotifyError(error)))),
      );
    } on AddonException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(s.plantTestFailed(e.message))));
    }
  }

  Future<void> _generate() async {
    setState(() => _busy = true);
    try {
      final report = await withProgress(context, s.plantGenerating, widget.client.generateNow);
      await _load();
      if (mounted) await _open(report);
    } on AddonException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(PlantReport report) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlantReportDetailScreen(report: report)));

  Future<void> _openEntry(PlantReportEntry entry) async {
    try {
      await _open(await widget.client.read(entry.id));
    } on AddonException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final o = _overview;
    final id = InstallationStore.instance.active.id;
    final store = CustomerStore.instance;
    final due = store.record(id).nextMaintenance(store.visits(id));
    return Scaffold(
      appBar: AppBar(title: Text(s.plantTitle)),
      body: o == null
          ? Center(child: _error == null ? const CircularProgressIndicator.adaptive() : Text(_error!))
          : ListView(
              padding: EdgeInsets.all(Gap.gutterFor(MediaQuery.sizeOf(context).width)),
              children: [
                Text(s.plantIntro, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
                const SizedBox(height: Gap.section),
                if (_error != null) ...[
                  HorizontBadge(HorizontStatus.critical, label: _error!),
                  const SizedBox(height: Gap.item),
                ],
                if (o.lastError != null) ...[
                  HorizontBadge(HorizontStatus.warning, label: s.plantLastError),
                  const SizedBox(height: Gap.item),
                ],
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.plantEnabled),
                  subtitle: Text(s.plantEnabledHint),
                  value: o.enabled,
                  onChanged: _busy ? null : (v) => _configure({'enabled': v}),
                ),
                const SizedBox(height: Gap.item),
                HorizontField(
                  label: s.plantPeriod,
                  child: DropdownButtonFormField<String>(
                    initialValue: o.quarterly ? 'quarterly' : 'monthly',
                    items: [
                      DropdownMenuItem(value: 'monthly', child: Text(s.plantPeriodMonthly)),
                      DropdownMenuItem(value: 'quarterly', child: Text(s.plantPeriodQuarterly)),
                    ],
                    onChanged: _busy || !o.enabled ? null : (v) => _configure({'period': v}),
                  ),
                ),
                const SizedBox(height: Gap.section),
                Kennung(s.plantMaintenance),
                const SizedBox(height: Gap.item),
                Row(
                  children: [
                    Expanded(
                      child: Text(due == null ? s.plantMaintenanceNone : s.customerNextMaintenance(formatDate(due))),
                    ),
                    if (store.maintenanceDue(id)) HorizontBadge(HorizontStatus.warning, label: s.customerDue),
                  ],
                ),
                const SizedBox(height: Gap.section),
                Kennung(s.plantNotify),
                const SizedBox(height: Gap.item),
                Text(s.plantNotifyHint, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
                const SizedBox(height: Gap.item),
                HorizontField(
                  label: s.plantNotifyTarget,
                  child: DropdownButtonFormField<String>(
                    initialValue: _kind,
                    isExpanded: true,
                    items: [
                      DropdownMenuItem(value: 'off', child: Text(s.plantNotifyOff)),
                      const DropdownMenuItem(value: 'ntfy', child: Text('ntfy')),
                      DropdownMenuItem(value: 'webhook', child: Text(s.plantNotifyWebhook)),
                      if (o.canHomeAssistant) DropdownMenuItem(value: 'homeassistant', child: Text(s.plantNotifyHa)),
                    ],
                    onChanged: _busy ? null : (v) => setState(() => _kind = v ?? 'off'),
                  ),
                ),
                if (_kind == 'ntfy' || _kind == 'webhook') ...[
                  const SizedBox(height: Gap.item),
                  HorizontField(
                    label: s.plantNotifyUrl,
                    child: TextField(
                      controller: _url,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: InputDecoration(hintText: _kind == 'ntfy' ? 'https://ntfy.sh' : 'https://'),
                    ),
                  ),
                  if (_kind == 'ntfy') ...[
                    const SizedBox(height: Gap.item),
                    HorizontField(
                      label: s.plantNotifyTopic,
                      child: TextField(controller: _topic, autocorrect: false),
                    ),
                  ],
                  const SizedBox(height: Gap.item),
                  HorizontField(
                    label: s.plantNotifyToken,
                    child: TextField(
                      controller: _token,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        hintText: o.hasToken ? s.plantNotifyTokenSet : s.plantNotifyTokenOptional,
                      ),
                    ),
                  ),
                ],
                if (_kind != 'off') ...[
                  CheckboxListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.plantNotifyReady),
                    value: o.notifyReady,
                    onChanged: _busy ? null : (v) => _configure({..._target, 'notifyReady': v == true}),
                  ),
                  CheckboxListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.plantNotifyUrgent),
                    value: o.notifyUrgent,
                    onChanged: _busy ? null : (v) => _configure({..._target, 'notifyUrgent': v == true}),
                  ),
                ],
                const SizedBox(height: Gap.item),
                Wrap(
                  spacing: Gap.item,
                  runSpacing: Gap.item,
                  children: [
                    FilledButton(onPressed: _busy ? null : () => _configure(_target), child: Text(s.plantNotifySave)),
                    if (_kind != 'off') OutlinedButton(onPressed: _busy ? null : _test, child: Text(s.plantNotifyTest)),
                  ],
                ),
                if (o.lastNotifyError case final code? when _kind != 'off') ...[
                  const SizedBox(height: Gap.item),
                  Text(
                    s.plantTestFailed(plantNotifyError(code)),
                    style: theme.textTheme.bodySmall?.copyWith(color: hz.critical),
                  ),
                ],
                const SizedBox(height: Gap.section),
                Kennung(s.plantReports, count: o.reports.length),
                const SizedBox(height: Gap.item),
                if (o.enabled)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton(onPressed: _busy ? null : _generate, child: Text(s.plantGenerateNow)),
                  ),
                if (o.reports.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Gap.item),
                    child: Text(s.plantNoReports, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
                  ),
                const SizedBox(height: Gap.item),
                for (final r in o.reports) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      r.critical > 0 ? HorizontStatus.critical.icon : AppIcons.report,
                      color: r.critical > 0 ? hz.critical : hz.textMuted,
                    ),
                    title: Text(plantPeriodText(r.from, r.to)),
                    subtitle: Text(
                      [
                        if (r.partial) s.plantPartial,
                        s.plantEntryFindings(r.findings),
                        if (r.fresh > 0) s.plantEntryNew(r.fresh),
                        if (r.resolved > 0) s.plantEntryResolved(r.resolved),
                      ].join(metaSeparator),
                    ),
                    trailing: const Icon(AppIcons.next),
                    onTap: () => _openEntry(r),
                  ),
                  const Divider(height: Lines.hairline),
                ],
              ],
            ),
    );
  }
}

/// A report: result on top, evidence below, PDF with letterhead.
class PlantReportDetailScreen extends StatelessWidget {
  const PlantReportDetailScreen({super.key, required this.report});

  final PlantReport report;

  static String _percent(double v) => localizeDecimal((v * 100).toStringAsFixed(v < 0.1 ? 1 : 0));

  Future<void> _pdf(BuildContext context) async {
    final button = context;
    final store = CustomerStore.instance;
    final id = InstallationStore.instance.active.id;
    final record = store.record(id);
    await sharePdf(
      button,
      () async => PlantReportPdf(
        report,
        customer: record.customer,
        site: record.site,
        project: InstallationStore.instance.active.name,
        nextMaintenance: record.nextMaintenance(store.visits(id)) ?? report.maintenanceDue,
      ),
      pdfName(s.plantPdfName),
      origin: rectOf(button),
    );
    unawaited(store.note(VisitKind.report, text: plantPeriodText(report.from, report.to)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final availability = report.availability;
    return Scaffold(
      appBar: AppBar(title: Text(plantPeriodText(report.from, report.to))),
      body: ListView(
        padding: EdgeInsets.all(Gap.gutterFor(MediaQuery.sizeOf(context).width)),
        children: [
          if (report.partial) ...[
            HorizontBadge(HorizontStatus.info, label: s.plantPartial),
            const SizedBox(height: Gap.item),
          ],
          Text(
            report.attention == 0 ? s.plantResultGood : s.plantResultAttention(report.attention),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: Gap.item),
          Text(
            [
              s.plantCoverage(report.coveredDays, report.totalDays),
              if (availability != null) s.plantAvailability(_percent(availability)),
              s.plantTelegrams(report.telegrams),
              s.plantLoad(_percent(report.averageLoad), _percent(report.peakLoad)),
            ].join(metaSeparator),
            style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
          ),
          const SizedBox(height: Gap.item),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Builder(
              builder: (button) => FilledButton.icon(
                onPressed: () => _pdf(button),
                icon: const Icon(AppIcons.report, size: 18),
                label: Text(s.plantPdf),
              ),
            ),
          ),
          const SizedBox(height: Gap.section),
          Kennung(s.plantFindings, count: report.findings.length),
          const SizedBox(height: Gap.item),
          if (report.findings.isEmpty) Text(s.plantFindingsNone),
          for (final f in report.findings)
            _line(context, plantFindingText(f), plantFindingStatus(f['status']), critical: f['level'] == 'critical'),
          if (report.resolved.isNotEmpty) ...[
            const SizedBox(height: Gap.section),
            Kennung(s.plantResolved, count: report.resolved.length),
            const SizedBox(height: Gap.item),
            for (final f in report.resolved) _line(context, plantFindingText(f), s.plantStatusResolved),
          ],
          if (report.safety.isNotEmpty) ...[
            const SizedBox(height: Gap.section),
            Kennung(s.plantSafety, count: report.safety.length),
            const SizedBox(height: Gap.item),
            Text(s.plantSafetyHint, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
            const SizedBox(height: Gap.item),
            for (final x in report.safety)
              _line(context, [x['label'], x['name']].whereType<String>().join(' '), switch (x['state']) {
                'active' => s.plantSafetyActive,
                'ok' => s.plantSafetyOk,
                _ => s.plantSafetyUnknown,
              }, critical: x['state'] == 'active'),
          ],
          if (report.outages.isNotEmpty) ...[
            const SizedBox(height: Gap.section),
            Kennung(s.plantOutageList, count: report.outages.length),
            const SizedBox(height: Gap.item),
            for (final o in report.outages.take(30))
              _line(
                context,
                plantOutageText(o),
                o['kind'] == 'offline' ? s.plantOutageOffline : s.plantOutageDisconnected,
              ),
          ],
          if (report.topSenders.isNotEmpty) ...[
            const SizedBox(height: Gap.section),
            Kennung(s.plantTopSenders, count: report.topSenders.length),
            const SizedBox(height: Gap.item),
            for (final x in report.topSenders) _line(context, '${x['label']}', s.plantTelegrams(x['count']! as int)),
          ],
          if (report.lines.isNotEmpty) ...[
            const SizedBox(height: Gap.section),
            Kennung(s.plantLines, count: report.lines.length),
            const SizedBox(height: Gap.item),
            for (final l in report.lines)
              _line(
                context,
                '${l['line']}',
                s.plantLoad(_percent((l['average']! as num).toDouble()), _percent((l['peak']! as num).toDouble())),
              ),
          ],
        ],
      ),
    );
  }

  Widget _line(BuildContext context, String text, String? trailing, {bool critical = false}) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HzSpace.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (critical) ...[
            Icon(HorizontStatus.critical.icon, size: 16, color: hz.critical),
            const SizedBox(width: HzSpace.s4),
          ],
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          if (trailing != null) ...[
            const SizedBox(width: Gap.item),
            Text(trailing, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
          ],
        ],
      ),
    );
  }
}

/// Outage as a time span.
String plantOutageText(Map<String, Object?> o) {
  final from = DateTime.fromMillisecondsSinceEpoch(o['from']! as int);
  final to = DateTime.fromMillisecondsSinceEpoch(o['to']! as int);
  return '${formatDate(from)} ${formatTime(from, seconds: false)} – ${formatDate(to)} ${formatTime(to, seconds: false)}';
}
