import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/demo_tunnel.dart';
import '../l10n/locale_controller.dart';
import '../model/company.dart';
import '../model/customer.dart';
import '../model/installation.dart';
import '../model/service_report.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'figure_box.dart';
import 'service_report_screen.dart';
import 'telegram_row.dart' show formatDate;

/// Shares the stored reply a history entry ([VisitKind.faultReply]) points to.
Future<void> shareFaultReply(BuildContext context, Visit visit) async {
  final created = int.tryParse(visit.ref ?? '');
  final report = created == null ? null : await ServiceReportStore.instance.byCreated(created);
  if (!context.mounted) return;
  if (report == null) return showHorizontMessage(context, s.replyGone, status: HorizontStatus.warning);
  await shareServiceReport(context, report);
}

/// Reply to the customer after a fault report (Pro): what was reported and
/// when, what was found, what happens next, as a short PDF on the letterhead.
/// Only the electrician's own words go in; nothing is taken from the recording.
/// Stored with the service reports ([ServiceKind.reply]) and noted in the
/// visit history.
class FaultReplyScreen extends StatefulWidget {
  const FaultReplyScreen({super.key, required this.report});

  /// The history entry of the received fault report.
  final Visit report;

  @override
  State<FaultReplyScreen> createState() => _FaultReplyScreenState();
}

class _FaultReplyScreenState extends State<FaultReplyScreen> {
  late final _reported = TextEditingController(text: widget.report.text);
  final _found = TextEditingController();
  final _next = TextEditingController();
  final _customer = TextEditingController();
  final _technician = TextEditingController(text: CompanyStore.instance.company.technician);
  late String _language = s.localeName.startsWith('de') ? 'de' : 'en';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (!DemoTunnel.active) {
      _customer.text = CustomerStore.instance.record(InstallationStore.instance.active.id).customer;
    }
  }

  @override
  void dispose() {
    for (final c in [_reported, _found, _next, _customer, _technician]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _ready => _found.text.trim().isNotEmpty || _next.text.trim().isNotEmpty;

  Future<void> _create(BuildContext buttonContext) async {
    setState(() => _busy = true);
    try {
      final report = ServiceReport(
        created: DateTime.now(),
        project: CatalogStore.instance.catalog.projectName,
        customer: _customer.text.trim(),
        // No address: the reply goes to the customer, who knows where they live.
        site: '',
        technician: _technician.text.trim(),
        language: _language,
        occasion: _reported.text.trim(),
        observed: _found.text.trim(),
        done: '',
        recommendation: _next.text.trim(),
        kind: ServiceKind.reply,
        reportedAt: widget.report.time,
      );
      await ServiceReportStore.instance.save(report);
      final summary = report.recommendation.isNotEmpty ? report.recommendation : report.observed;
      unawaited(
        CustomerStore.instance.note(
          VisitKind.faultReply,
          text: summary.split('\n').first,
          ref: '${report.created.millisecondsSinceEpoch}',
        ),
      );
      if (buttonContext.mounted) await shareServiceReport(buttonContext, report);
    } on Object catch (e) {
      debugPrint('Rückmeldung: $e');
      if (mounted) showHorizontMessage(context, s.pdfExportFailedGeneric, status: HorizontStatus.critical);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
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
    final reported = <Widget>[
      SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.replyReportedOn(formatDate(widget.report.time)),
              style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
            ),
            const SizedBox(height: Gap.item),
            field(s.replyReportedLabel, _reported, maxLines: 6, last: true),
          ],
        ),
      ),
      SectionHead(s.acceptCustomerSection),
      SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [field(s.acceptCustomer, _customer), field(s.acceptTechnician, _technician, last: true)],
        ),
      ),
      // In the browser in the app's language (no isolate, see acceptance).
      if (!kIsWeb) ...[
        SectionHead(s.acceptLanguage),
        ChoiceBar<String>(
          segments: const [
            ButtonSegment(value: 'de', label: Text('Deutsch')),
            ButtonSegment(value: 'en', label: Text('English')),
          ],
          selected: _language,
          onChanged: (v) => setState(() => _language = v),
        ),
      ],
    ];
    final answer = <Widget>[
      SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            field(s.replyFoundLabel, _found, maxLines: 8, hint: s.replyFoundHint),
            field(s.replyNext, _next, maxLines: 6, hint: s.replyNextHint, last: true),
          ],
        ),
      ),
      const SizedBox(height: Gap.section),
      Builder(
        builder: (buttonContext) =>
            FilledButton(onPressed: _ready && !_busy ? () => _create(buttonContext) : null, child: Text(s.replyCreate)),
      ),
      if (!_ready) ...[
        const SizedBox(height: Gap.item),
        Text(s.replyMissing, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
      ],
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(s.replyTitle),
        actions: [InfoAction(title: s.replyTitle, text: s.replyExplain)],
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          // Wide: the report on the left, the answer next to it.
          final wide = box.maxWidth >= _twoColumns;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? Widths.dashboard : Widths.reading),
              child: SingleChildScrollView(
                padding: Gap.page,
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: Gap.section,
                        children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: reported),
                          ),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: answer),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ...reported,
                          const SizedBox(height: Gap.section),
                          ...answer,
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// From this width the page shows the report and the answer side by side.
const _twoColumns = 840.0;
