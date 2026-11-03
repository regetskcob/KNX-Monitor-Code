import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../export/pdf_export.dart';
import '../knx/demo_tunnel.dart';
import '../l10n/locale_controller.dart';
import '../model/acceptance.dart';
import '../model/annotation.dart';
import '../model/company.dart';
import '../model/customer.dart';
import '../model/health.dart';
import '../model/installation.dart';
import '../model/recording.dart';
import '../model/service_report.dart';
import '../model/site_photos.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'figure_box.dart';
import 'signature_pad.dart';
import 'telegram_row.dart' show formatDate, formatTime;

/// Service report (Pro): fill in occasion, observation, work done and
/// recommendation, choose a recording and health check as evidence, optionally
/// have it signed. Creating it freezes the state and shares the PDF.
class ServiceReportScreen extends StatefulWidget {
  const ServiceReportScreen({super.key, this.gateway, this.recordingId});

  final String? gateway;

  /// Preselected recording (from an incoming fault report).
  final String? recordingId;

  @override
  State<ServiceReportScreen> createState() => _ServiceReportScreenState();
}

class _ServiceReportScreenState extends State<ServiceReportScreen> {
  final _customer = TextEditingController();
  final _site = TextEditingController();
  final _technician = TextEditingController(text: CompanyStore.instance.company.technician);
  final _occasion = TextEditingController();
  final _observed = TextEditingController();
  final _done = TextEditingController();
  final _recommendation = TextEditingController();
  final _signer = TextEditingController();
  late String _language = s.localeName.startsWith('de') ? 'de' : 'en';
  late String? _recordingId = widget.recordingId;
  bool _useHealth = HealthCheck.instance.last != null;
  Signature _signature = Signature.empty;
  bool _busy = false;

  /// Photos chosen for the report; none without a selection.
  final _photos = <String>{};
  late Future<List<ServiceReport>> _earlier = ServiceReportStore.instance.list();

  List<RecordingSummary> get _recordings {
    final active = InstallationStore.instance.active.id;
    return [
      for (final r in RecordingStore.instance.summaries)
        if (r.installation == null || r.installation == active) r,
    ];
  }

  @override
  void initState() {
    super.initState();
    // Prefill from the customer file, not in the demo house.
    if (!DemoTunnel.active) {
      final r = CustomerStore.instance.record(InstallationStore.instance.active.id);
      _customer.text = r.customer;
      _site.text = r.site;
    }
    RecordingStore.instance.load().then((_) {
      if (mounted) setState(() {});
    });
    SitePhotoStore.instance.load().then((_) {
      if (mounted) setState(() {});
    });
    if (widget.recordingId != null) _prefill(widget.recordingId!);
  }

  @override
  void dispose() {
    for (final c in [_customer, _site, _technician, _occasion, _observed, _done, _recommendation, _signer]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The recording's comments as a suggestion for "Was beobachtet wurde" (what
  /// was observed); a fault report brings its description along as the occasion.
  Future<void> _prefill(String id) async {
    try {
      final r = await RecordingStore.instance.open(id);
      if (!mounted) return;
      final lines = [for (final c in collectServiceComments(r, AnnotationStore.instance.all)) c.note];
      if (_observed.text.trim().isEmpty && lines.isNotEmpty) _observed.text = lines.join('\n');
      if (r.diagnostics?['problem'] case final String problem when _occasion.text.trim().isEmpty) {
        _occasion.text = problem;
      }
      setState(() {});
    } on Object catch (e) {
      debugPrint('Aufnahme nicht lesbar: $e');
    }
  }

  Future<void> _sign() async {
    final sig = await captureSignature(context, title: s.acceptSignCustomer);
    if (sig != null && mounted) setState(() => _signature = sig);
  }

  Future<void> _create(BuildContext buttonContext) async {
    setState(() => _busy = true);
    try {
      final recording = _recordingId == null ? null : await RecordingStore.instance.open(_recordingId!);
      final run = _useHealth ? HealthCheck.instance.last : null;
      final evidence = await collectServiceEvidence(language: _language, recording: recording, run: run);
      final report = ServiceReport(
        created: DateTime.now(),
        project: CatalogStore.instance.catalog.projectName,
        customer: _customer.text.trim(),
        site: _site.text.trim(),
        technician: _technician.text.trim(),
        language: _language,
        occasion: _occasion.text.trim(),
        observed: _observed.text.trim(),
        done: _done.text.trim(),
        recommendation: _recommendation.text.trim(),
        recordingName: recording?.name,
        recordingStart: recording?.started,
        recordingEnd: recording?.ended,
        telegrams: recording?.telegrams.length ?? 0,
        comments: collectServiceComments(recording, AnnotationStore.instance.all),
        photos: [
          for (final p in SitePhotoStore.instance.photos)
            if (_photos.contains(p.id)) ServicePhoto(p.id, p.caption),
        ],
        findings: evidence.findings,
        health: evidence.health,
        healthTime: run?.time,
        signer: _signer.text.trim(),
        signature: _signature,
        gateway: widget.gateway,
      );
      await ServiceReportStore.instance.save(report);
      unawaited(CustomerStore.instance.note(VisitKind.serviceReport, text: report.occasion));
      if (!mounted) return;
      setState(() {
        _signature = Signature.empty;
        _earlier = ServiceReportStore.instance.list();
      });
      if (buttonContext.mounted) await _share(buttonContext, report);
    } on Object catch (e) {
      debugPrint('Servicebericht: $e');
      if (mounted) showHorizontMessage(context, s.pdfExportFailed('$e'), status: HorizontStatus.critical);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(BuildContext context, ServiceReport r) => sharePdf(
    context,
    () async {
      final shots = <String, Uint8List>{};
      for (final id in {for (final c in r.comments) ...c.shots}) {
        try {
          if (await ShotStore.instance.read(id) case final jpeg?) shots[id] = jpeg;
        } on Object catch (e) {
          debugPrint('Screenshot $id: $e');
        }
      }
      final photos = <String, Uint8List>{};
      for (final p in r.photos) {
        try {
          if (await SitePhotoStore.instance.read(p.id) case final jpeg?) photos[p.id] = jpeg;
        } on Object catch (e) {
          debugPrint('Foto ${p.id}: $e');
        }
      }
      return ServiceReportPdf(r, shots: shots, photos: photos);
    },
    pdfName([s.srPdfTitle, if (r.customer.isNotEmpty) r.customer].join(' ')),
    origin: rectOf(context),
  );

  /// Tick photos for the report.
  Future<void> _pickPhotos(List<SitePhoto> photos) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => StatefulBuilder(
      builder: (sheet, update) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, Gap.gutter),
          children: [
            Text(s.srPhotos, style: Theme.of(sheet).textTheme.titleLarge),
            const SizedBox(height: Gap.item),
            Text(s.srPhotosHint, style: Theme.of(sheet).textTheme.bodySmall?.copyWith(color: sheet.hz.textFaint)),
            for (final p in photos)
              CheckboxListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _photos.contains(p.id),
                title: Text(p.caption.isEmpty ? s.siteDocsNoCaption : p.caption),
                subtitle: Text(formatDate(p.at)),
                onChanged: (v) {
                  update(() => v == true ? _photos.add(p.id) : _photos.remove(p.id));
                  setState(() {});
                },
              ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    Widget field(String label, TextEditingController c, {int maxLines = 1, String? hint, bool last = false}) => Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : Gap.inner),
      child: HorizontField(
        label: label,
        child: TextField(
          controller: c,
          style: context.hzTheme.field,
          minLines: 1,
          maxLines: maxLines,
          decoration: InputDecoration(hintText: hint),
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
        ),
      ),
    );
    final recordings = _recordings;
    final health = HealthCheck.instance.last;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.srTitle),
        actions: [InfoAction(title: s.srTitle, text: s.srExplain)],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Widths.reading),
          child: ListView(
            padding: Gap.page,
            children: [
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    field(s.srOccasion, _occasion, maxLines: 4, hint: s.srOccasionHint),
                    field(s.srObserved, _observed, maxLines: 6, hint: s.srObservedHint),
                    field(s.srDone, _done, maxLines: 6, hint: s.srDoneHint),
                    field(s.srRecommendation, _recommendation, maxLines: 4, hint: s.srRecommendationHint, last: true),
                  ],
                ),
              ),
              SectionHead(s.srIncludes),
              RowCard(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: HzSpace.s12),
                    child: HorizontField(
                      label: s.srRecording,
                      child: DropdownButton<String?>(
                        icon: const Icon(AppIcons.expand),
                        isExpanded: true,
                        value: recordings.any((r) => r.id == _recordingId) ? _recordingId : null,
                        items: [
                          DropdownMenuItem(value: null, child: Text(s.srRecordingNone)),
                          for (final r in recordings)
                            DropdownMenuItem(
                              value: r.id,
                              child: Text(
                                '${r.name}$metaSeparator${formatDate(r.started)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (id) {
                          setState(() => _recordingId = id);
                          if (id != null) _prefill(id);
                        },
                      ),
                    ),
                  ),
                  if (health != null)
                    SwitchRow(
                      title: s.srUseHealth,
                      meta: '${formatDate(health.time)} ${formatTime(health.time, seconds: false)}',
                      value: _useHealth,
                      onChanged: (v) => setState(() => _useHealth = v),
                    ),
                  // Photos only if there are any, and only the ticked ones.
                  if (SitePhotoStore.instance.photos case final photos when photos.isNotEmpty)
                    CardRow(title: s.srPhotos, value: formatInt(_photos.length), onTap: () => _pickPhotos(photos)),
                ],
              ),
              SectionHead(s.acceptCustomerSection),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    field(s.acceptCustomer, _customer),
                    field(s.acceptSite, _site, maxLines: 3),
                    field(s.acceptTechnician, _technician, last: true),
                  ],
                ),
              ),
              // In the browser in the app's language (no isolate, see acceptance).
              if (!kIsWeb) ...[
                SectionHead(s.acceptLanguage),
                FilterBar<String>(
                  segments: const [
                    ButtonSegment(value: 'de', label: Text('Deutsch')),
                    ButtonSegment(value: 'en', label: Text('English')),
                  ],
                  selected: _language,
                  onChanged: (v) => setState(() => _language = v),
                ),
              ],
              SectionHead(s.srSignatureOptional),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    field(s.acceptSigner, _signer),
                    OutlinedButton.icon(
                      onPressed: _sign,
                      icon: Icon(_signature.isEmpty ? AppIcons.acceptance : AppIcons.success, size: 18),
                      label: Text(_signature.isEmpty ? s.acceptSignCustomer : s.srSigned),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.section),
              Builder(
                builder: (buttonContext) =>
                    FilledButton(onPressed: _busy ? null : () => _create(buttonContext), child: Text(s.srCreate)),
              ),
              FutureBuilder(
                future: _earlier,
                builder: (context, snap) {
                  final list = snap.data ?? const <ServiceReport>[];
                  if (list.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: Gap.section),
                      SectionTitle(s.srEarlier, count: list.length),
                      const SizedBox(height: Gap.item),
                      const Divider(height: Lines.hairline),
                      for (final r in list) ...[
                        Builder(
                          builder: (rowContext) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(AppIcons.pdf),
                            title: Text(r.customer.isEmpty ? s.srPdfTitle : r.customer),
                            subtitle: Text(
                              [
                                '${formatDate(r.created)} ${formatTime(r.created, seconds: false)}',
                                if (r.technician.isNotEmpty) r.technician,
                              ].join(metaSeparator),
                            ),
                            onTap: () => _share(rowContext, r),
                          ),
                        ),
                        const Divider(height: Lines.hairline),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
