import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../export/pdf_export.dart';
import '../knx/demo_tunnel.dart';
import '../l10n/locale_controller.dart';
import '../model/company.dart';
import '../model/customer.dart';
import '../model/handover.dart';
import '../model/installation.dart';
import '../model/resident_manual.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// Resident manual (Pro): a booklet by room from the project and taught-in names,
/// in everyday words, with own notes and the company's contact.
class ResidentManualScreen extends StatefulWidget {
  const ResidentManualScreen({super.key});

  @override
  State<ResidentManualScreen> createState() => _ResidentManualScreenState();
}

class _ResidentManualScreenState extends State<ResidentManualScreen> {
  final _note = TextEditingController();
  late String _language = s.localeName.startsWith('de') ? 'de' : 'en';

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  ResidentManual _manual() {
    final company = CompanyStore.instance.company;
    // On the customer's device, the company from the handover package.
    final origin = HandoverStore.instance.origin?.contact;
    return buildResidentManual(
      catalog: CatalogStore.instance.catalog,
      language: _language,
      customer: DemoTunnel.active
          ? CustomerRecord.empty
          : CustomerStore.instance.record(InstallationStore.instance.active.id),
      note: _note.text,
      contactName: company.isSet ? company.name : (origin?.name ?? ''),
      contactPhone: company.isSet ? company.phone : (origin?.phone ?? ''),
      contactEmail: company.isSet ? company.email : (origin?.email ?? ''),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final rooms = buildManualRooms(CatalogStore.instance.catalog);
    final count = rooms.fold<int>(0, (n, r) => n + r.entries.length);
    return Scaffold(
      appBar: AppBar(title: Text(s.manualTitle)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Widths.reading),
          child: ListView(
            padding: Gap.page,
            children: [
              Text(s.manualExplain, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
              const SizedBox(height: Gap.section),
              Text(s.manualSummary(rooms.length, count)),
              const SizedBox(height: Gap.section),
              HorizontField(
                label: s.manualNote,
                child: TextField(
                  controller: _note,
                  style: context.hzTheme.field,
                  minLines: 2,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: s.manualNoteHint),
                ),
              ),
              const SizedBox(height: Gap.section),
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
                const SizedBox(height: Gap.section),
              ],
              Builder(
                builder: (buttonContext) => Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.icon(
                    onPressed: count == 0
                        ? null
                        : () => sharePdf(
                            buttonContext,
                            () async => ResidentManualPdf(_manual()),
                            pdfName(s.manualPdfTitle),
                            origin: rectOf(buttonContext),
                          ),
                    icon: const Icon(AppIcons.pdf, size: 18),
                    label: Text(s.manualCreate),
                  ),
                ),
              ),
              if (count == 0) ...[
                const SizedBox(height: Gap.item),
                Text(s.manualEmpty, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
