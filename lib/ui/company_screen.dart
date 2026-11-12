import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../l10n/locale_controller.dart';
import '../model/company.dart';
import '../model/plan.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'figure_box.dart';
import 'form_columns.dart';
import 'plan_screen.dart';

/// Settings page "Firma" (company, Pro): details and logo for the letterhead on
/// all PDFs. Preview at the top; without Pro everything stays readable but has
/// no effect.
class CompanyScreen extends StatefulWidget {
  const CompanyScreen({super.key});

  @override
  State<CompanyScreen> createState() => _CompanyScreenState();
}

class _CompanyScreenState extends State<CompanyScreen> {
  final _store = CompanyStore.instance;
  late final _c = _store.company;
  late final _name = TextEditingController(text: _c.name);
  late final _address = TextEditingController(text: _c.address);
  late final _phone = TextEditingController(text: _c.phone);
  late final _email = TextEditingController(text: _c.email);
  late final _website = TextEditingController(text: _c.website);
  late final _vat = TextEditingController(text: _c.vatId);
  late final _registration = TextEditingController(text: _c.registration);
  late final _technician = TextEditingController(text: _c.technician);
  bool _busy = false;

  List<TextEditingController> get _all => [_name, _address, _phone, _email, _website, _vat, _registration, _technician];

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  Company get _current => Company(
    name: _name.text.trim(),
    address: _address.text.trim(),
    phone: _phone.text.trim(),
    email: _email.text.trim(),
    website: _website.text.trim(),
    vatId: _vat.text.trim(),
    registration: _registration.text.trim(),
    technician: _technician.text.trim(),
  );

  Future<void> _save() async {
    await _store.save(_current);
    if (mounted) showHorizontMessage(context, s.companySaved, status: HorizontStatus.positive);
  }

  Future<void> _pickLogo() async {
    final colors = context.hz;
    final messenger = ScaffoldMessenger.of(context);
    // FileType.any: otherwise iOS greys out .svg files with custom filters.
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      await _store.setLogo(await normalizeLogo(await file.readAsBytes(), file.name));
    } on Object catch (e) {
      debugPrint('Logo: $e');
      messenger.showSnackBar(horizontMessageSnackBar(colors, s.companyLogoFailed, status: HorizontStatus.critical));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    Widget field(
      String label,
      TextEditingController c, {
      int maxLines = 1,
      TextInputType? keyboard,
      bool last = false,
    }) => Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : Gap.inner),
      child: HorizontField(
        label: label,
        child: TextField(
          controller: c,
          style: context.hzTheme.field,
          minLines: 1,
          maxLines: maxLines,
          keyboardType: keyboard,
          onChanged: (_) => setState(() {}),
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(s.companyTitle),
        actions: [TextButton(onPressed: _save, child: Text(s.commonSave))],
      ),
      // Phone and narrow windows: one column in reading width, the preview first. From the
      // expanded width on, name, address and contact stand on the left; the preview stands beside
      // them and changes while typing, with the logo and the remaining details below it.
      body: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          final preview = [
            SectionHead(s.companyPreview),
            _Preview(company: _current, logo: _store.logo),
            SectionHead(s.companyLogo),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: Gap.inner,
                    runSpacing: Gap.item,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _pickLogo,
                        icon: const Icon(AppIcons.image, size: 18),
                        label: Text(_store.logo == null ? s.companyLogoPick : s.companyLogoReplace),
                      ),
                      if (_store.logo != null)
                        TextButton(onPressed: _busy ? null : () => _store.setLogo(null), child: Text(s.commonDelete)),
                    ],
                  ),
                  const SizedBox(height: Gap.item),
                  Text(s.companyLogoHint, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
                ],
              ),
            ),
          ];
          final details = [
            SectionHead(s.companyDetails),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  field(s.companyName, _name),
                  field(s.companyAddress, _address, maxLines: 4, keyboard: TextInputType.multiline),
                  field(s.companyPhone, _phone, keyboard: TextInputType.phone),
                  field(s.companyEmail, _email, keyboard: TextInputType.emailAddress),
                  field(s.companyWebsite, _website, keyboard: TextInputType.url, last: true),
                ],
              ),
            ),
          ];
          final more = [
            SectionHead(s.companyMore),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  field(s.companyVatId, _vat),
                  field(s.companyRegistration, _registration, maxLines: 2),
                  field(s.companyTechnician, _technician, last: true),
                ],
              ),
            ),
          ];
          return FormColumns(
            intro: [
              Text(s.companyExplain, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
              if (!Plan.instance.allows(Feature.letterhead)) ...[
                const SizedBox(height: Gap.item),
                const Align(alignment: AlignmentDirectional.centerStart, child: TierBadge(Tier.pro)),
              ],
            ],
            columns: [
              details,
              [...preview, ...more],
            ],
            narrow: [...preview, ...details, ...more],
          );
        },
      ),
    );
  }
}

/// The header of the first PDF page: logo on the left, company block on the
/// right. Always on a light background, because paper is light.
class _Preview extends StatelessWidget {
  const _Preview({required this.company, required this.logo});

  final Company company;
  final Uint8List? logo;

  @override
  Widget build(BuildContext context) {
    final paper = Palette.of(false);
    final text = Theme.of(context).textTheme;
    final small = text.bodySmall?.copyWith(color: paper.textMuted);
    return Semantics(
      label: s.companyPreview,
      child: Container(
        padding: const EdgeInsets.all(Gap.card),
        decoration: BoxDecoration(
          color: paper.surface,
          borderRadius: Radii.card,
          border: Border.all(color: paper.lineStrong, width: Lines.hairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (logo != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140, maxHeight: 48),
                child: Image.memory(logo!, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink()),
              ),
            const Spacer(),
            Flexible(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    company.isSet ? company.name : s.companyPreviewEmpty,
                    textAlign: TextAlign.end,
                    style: text.titleSmall?.copyWith(color: paper.text),
                  ),
                  if (company.address.isNotEmpty) Text(company.address, textAlign: TextAlign.end, style: small),
                  if (company.contactLine.isNotEmpty) Text(company.contactLine, textAlign: TextAlign.end, style: small),
                  if (company.technician.isNotEmpty)
                    Text(s.pdfTechnicianLine(company.technician), textAlign: TextAlign.end, style: small),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
