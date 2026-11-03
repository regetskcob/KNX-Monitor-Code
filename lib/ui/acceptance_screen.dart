import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../knx/demo_tunnel.dart';
import '../export/pdf_export.dart';
import '../l10n/locale_controller.dart';
import '../model/acceptance.dart';
import '../model/betrieb/team.dart';
import '../model/commissioning.dart';
import '../model/company.dart';
import '../model/customer.dart';
import '../model/installation.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'signature_pad.dart';
import 'telegram_row.dart' show formatDate, formatTime;

/// Acceptance report (Pro): customer and site details, remarks, and signatures
/// of customer and technician on the device. Creating it freezes the
/// commissioning state and shares the PDF; earlier reports of the installation
/// are listed below.
class AcceptanceScreen extends StatefulWidget {
  const AcceptanceScreen({super.key, this.gateway});

  final String? gateway;

  @override
  State<AcceptanceScreen> createState() => _AcceptanceScreenState();
}

class _AcceptanceScreenState extends State<AcceptanceScreen> {
  static const _technicianKey = 'acceptance.technician';

  final _c = Commissioning.instance;
  final _customer = TextEditingController();
  final _site = TextEditingController();
  final _technician = TextEditingController();
  final _signer = TextEditingController();
  final _remarks = TextEditingController();
  final _followUps = TextEditingController();
  late String _language = s.localeName.startsWith('de') ? 'de' : 'en';
  Signature _customerSig = Signature.empty;
  Signature _technicianSig = Signature.empty;
  late Future<List<Acceptance>> _earlier = AcceptanceStore.instance.list();

  @override
  void initState() {
    super.initState();
    // Prefill from the customer record, but not in the demo house.
    if (!DemoTunnel.active) {
      final r = CustomerStore.instance.record(InstallationStore.instance.active.id);
      _customer.text = r.customer;
      _site.text = r.site;
    }
    // The technician is usually the same: suggest the last name entered.
    SharedPreferences.getInstance().then((p) {
      if (mounted && _technician.text.isEmpty) {
        _technician.text = p.getString(_technicianKey) ?? CompanyStore.instance.company.technician;
      }
    });
  }

  @override
  void dispose() {
    for (final c in [_customer, _site, _technician, _signer, _remarks, _followUps]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _ready =>
      _customer.text.trim().isNotEmpty &&
      _technician.text.trim().isNotEmpty &&
      !_customerSig.isEmpty &&
      !_technicianSig.isEmpty;

  Future<void> _sign({required bool customer}) async {
    final sig = await captureSignature(context, title: customer ? s.acceptSignCustomer : s.acceptSignTechnician);
    if (sig == null || !mounted) return;
    setState(() => customer ? _customerSig = sig : _technicianSig = sig);
  }

  Future<void> _create(BuildContext buttonContext) async {
    final draft = Acceptance.fromCommissioning(
      _c,
      customer: _customer.text,
      site: _site.text,
      technician: _technician.text,
      customerSigner: _signer.text,
      remarks: _remarks.text,
      followUps: _followUps.text,
      language: _language,
      customerSignature: _customerSig,
      technicianSignature: _technicianSig,
      gateway: widget.gateway,
    );
    // Pro team: fill in "checked by" and submit to the supervisor. Otherwise
    // unchanged.
    final a = Team.instance.stampChecked(draft);
    await AcceptanceStore.instance.save(a);
    unawaited(Team.instance.submitReview(a));
    unawaited(CustomerStore.instance.note(VisitKind.acceptance, text: a.customer));
    // Do not carry anything from the demo house into the real settings.
    if (!DemoTunnel.active) {
      (await SharedPreferences.getInstance()).setString(_technicianKey, a.technician).ignore();
    }
    if (!mounted) return;
    // Frozen: signatures apply only to this state.
    setState(() {
      _customerSig = Signature.empty;
      _technicianSig = Signature.empty;
      _earlier = AcceptanceStore.instance.list();
    });
    if (!buttonContext.mounted) return;
    await _share(buttonContext, a);
  }

  Future<void> _share(BuildContext context, Acceptance a) =>
      sharePdf(context, () async => AcceptancePdf(a), _fileName(a), origin: rectOf(context));

  String _fileName(Acceptance a) => pdfName([s.acceptPdfTitle, if (a.customer.isNotEmpty) a.customer].join(' '));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final open = _c.count(CheckState.open) + _c.count(CheckState.noAnswer);
    Widget field(String label, TextEditingController c, {int maxLines = 1, String? hint}) => Padding(
      padding: const EdgeInsets.only(bottom: Gap.inner),
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
    return Scaffold(
      appBar: AppBar(title: Text(s.acceptTitle)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Widths.reading),
          child: ListView(
            padding: Gap.page,
            children: [
              Text(s.acceptExplain, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
              const SizedBox(height: Gap.section),
              SectionCard(
                soft: true,
                child: HorizontMetricRow(
                  children: [
                    HorizontMetric(label: s.commChecked, value: '${_c.checked} / ${_c.items.length}'),
                    HorizontMetric(
                      label: s.commIssue,
                      value: formatInt(_c.count(CheckState.issue)),
                      status: _c.count(CheckState.issue) > 0 ? HorizontStatus.critical : null,
                    ),
                    HorizontMetric(
                      label: s.commOpen,
                      value: formatInt(open),
                      status: open > 0 ? HorizontStatus.warning : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.section),
              Kennung(s.acceptCustomerSection),
              const SizedBox(height: Gap.item),
              field(s.acceptCustomer, _customer),
              field(s.acceptSite, _site, maxLines: 3),
              field(s.acceptTechnician, _technician),
              const SizedBox(height: Gap.item),
              Kennung(s.acceptNotesSection),
              const SizedBox(height: Gap.item),
              field(s.acceptFollowUps, _followUps, maxLines: 5),
              field(s.acceptRemarks, _remarks, maxLines: 5, hint: s.acceptRemarksHint),
              const SizedBox(height: Gap.item),
              // In the browser the PDF is rendered in the app's language (there
              // is no background isolate in which it could be set separately).
              if (!kIsWeb) ...[
                Kennung(s.acceptLanguage),
                const SizedBox(height: Gap.item),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'de', label: Text('Deutsch')),
                      ButtonSegment(value: 'en', label: Text('English')),
                    ],
                    selected: {_language},
                    onSelectionChanged: (v) => setState(() => _language = v.first),
                  ),
                ),
              ],
              const SizedBox(height: Gap.section),
              Kennung(s.acceptSignatures),
              const SizedBox(height: Gap.item),
              field(s.acceptSigner, _signer),
              _SignatureTile(label: s.acceptSignCustomer, signature: _customerSig, onTap: () => _sign(customer: true)),
              const SizedBox(height: Gap.inner),
              _SignatureTile(
                label: s.acceptSignTechnician,
                signature: _technicianSig,
                onTap: () => _sign(customer: false),
              ),
              const SizedBox(height: Gap.section),
              Builder(
                builder: (buttonContext) => Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.icon(
                    onPressed: _ready ? () => _create(buttonContext) : null,
                    icon: const Icon(AppIcons.pdf, size: 18),
                    label: Text(s.acceptCreate),
                  ),
                ),
              ),
              if (!_ready) ...[
                const SizedBox(height: Gap.item),
                Text(s.acceptMissing, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
              ],
              FutureBuilder(
                future: _earlier,
                builder: (context, snap) {
                  final list = snap.data ?? const <Acceptance>[];
                  if (list.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: Gap.section),
                      Kennung(s.acceptEarlier, count: list.length),
                      const SizedBox(height: Gap.item),
                      const Divider(height: Lines.hairline),
                      for (final a in list) ...[
                        Builder(
                          builder: (rowContext) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(AppIcons.pdf),
                            title: Text(a.customer),
                            subtitle: Text(
                              [
                                '${formatDate(a.created)} ${formatTime(a.created, seconds: false)}',
                                '${a.done} / ${a.items.length}',
                                a.technician,
                              ].join(metaSeparator),
                            ),
                            onTap: () => _share(rowContext, a),
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

/// Signature field in the list: preview or prompt; tapping opens the drawing
/// canvas full screen.
class _SignatureTile extends StatelessWidget {
  const _SignatureTile({required this.label, required this.signature, required this.onTap});

  final String label;
  final Signature signature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          height: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: hz.line, width: Lines.hairline),
          ),
          child: signature.isEmpty
              ? Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.acceptance, size: 18, color: hz.textMuted),
                      const SizedBox(width: HzSpace.s8),
                      Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
                    ],
                  ),
                )
              : Center(
                  child: AspectRatio(
                    aspectRatio: Signature.aspect,
                    child: CustomPaint(
                      painter: SignaturePainter(signature, color: hz.text, line: hz.line),
                      size: Size.infinite,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
