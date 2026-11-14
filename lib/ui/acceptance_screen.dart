import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../catalog_store.dart';
import '../knx/demo_tunnel.dart';
import '../knx/telegram.dart' show formatGroup, formatIndividual;
import '../model/channel_test.dart';
import '../model/device_art.dart' show deviceChannels;
import '../export/pdf_export.dart';
import '../l10n/locale_controller.dart';
import '../model/acceptance.dart';
import '../model/betrieb/team.dart';
import '../model/commissioning.dart';
import '../model/company.dart';
import '../model/customer.dart';
import '../model/installation.dart';
import '../model/site_photos.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'figure_box.dart';
import 'photo_pick.dart';
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
  final _standard = TextEditingController();
  final _projectNumber = TextEditingController();
  DateTime? _warrantyStart;

  /// Photo per defect (address), already normalized; stored in the photo
  /// documentation only when the report is created.
  final _defectImages = <int, Uint8List>{};

  /// What is already stored, so a second report does not store it again.
  final _defectStored = <int, DefectPhoto>{};
  bool _busy = false;
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
    for (final c in [_customer, _site, _technician, _signer, _remarks, _followUps, _standard, _projectNumber]) {
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

  List<CheckItem> get _defects => [
    for (final i in _c.items.values)
      if (i.state == CheckState.issue) i,
  ];

  Future<void> _pickWarranty() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _warrantyStart ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (day != null && mounted) setState(() => _warrantyStart = day);
  }

  Future<void> _addDefectPhoto(int address) async {
    final jpeg = await pickSitePhoto(context);
    if (jpeg != null && mounted) setState(() => _defectImages[address] = jpeg);
  }

  /// Stores the photos of the current defects in the photo documentation and
  /// returns their references. Throws [SitePhotoQuotaExceeded].
  Future<Map<int, DefectPhoto>> _storeDefectPhotos() async {
    final result = <int, DefectPhoto>{};
    for (final item in _defects) {
      final jpeg = _defectImages[item.address];
      if (jpeg == null) continue;
      final known = _defectStored[item.address];
      if (known != null && known.matches(jpeg)) {
        result[item.address] = known;
        continue;
      }
      final name = CatalogStore.instance.info(item.address)?.name ?? '';
      final photo = await SitePhotoStore.instance.add(
        jpeg,
        caption: s.acceptDefectCaption(formatGroup(item.address), name),
      );
      result[item.address] = _defectStored[item.address] = DefectPhoto.of(photo.id, jpeg);
    }
    return result;
  }

  Future<void> _create(BuildContext buttonContext) async {
    setState(() => _busy = true);
    try {
      await _createAndShare(buttonContext);
    } on SitePhotoQuotaExceeded {
      if (mounted) showHorizontMessage(context, s.siteDocsQuota, status: HorizontStatus.critical);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createAndShare(BuildContext buttonContext) async {
    final photos = await _storeDefectPhotos();
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
      standard: _standard.text,
      projectNumber: _projectNumber.text,
      warrantyStart: _warrantyStart,
      defectPhotos: photos,
      projectProof: ProjectProof.of(CatalogStore.instance),
      channelChecks: [
        for (final t in await ChannelTestStore.instance.all(deviceChannels))
          if (t.done > 0)
            ChannelCheckRecord.of(t, CatalogStore.instance.device(t.device)?.name ?? formatIndividual(t.device)),
      ],
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

  Future<void> _share(BuildContext context, Acceptance a) => sharePdf(
    context,
    () async {
      final photos = <String, Uint8List>{};
      for (final p in a.defectPhotos.values) {
        try {
          if (await SitePhotoStore.instance.read(p.id) case final jpeg?) photos[p.id] = jpeg;
        } on Object catch (e) {
          debugPrint('Foto ${p.id}: $e');
        }
      }
      return AcceptancePdf(a, photos: photos);
    },
    _fileName(a),
    origin: rectOf(context),
  );

  String _fileName(Acceptance a) => pdfName([s.acceptPdfTitle, if (a.customer.isNotEmpty) a.customer].join(' '));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final open = _c.count(CheckState.open) + _c.count(CheckState.noAnswer);
    // Sections as in the service report: a head with the green bar, the fields in a card.
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
    final defects = _defects;
    // The form in three parts, so that a wide window can put them side by side.
    final head = <Widget>[
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
            HorizontMetric(label: s.commOpen, value: formatInt(open), status: open > 0 ? HorizontStatus.warning : null),
          ],
        ),
      ),
    ];
    final form = <Widget>[
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
      SectionHead(s.acceptDetailsSection),
      // Side by side where there is room, stacked on a phone.
      SectionCard(
        child: LayoutBuilder(
          builder: (context, box) {
            final narrow = box.maxWidth < _twoColumns;
            final standard = field(s.acceptStandard, _standard, hint: s.acceptStandardHint, last: !narrow);
            final number = field(s.acceptProjectNumber, _projectNumber, last: !narrow);
            final warranty = Padding(
              padding: EdgeInsets.zero,
              child: HorizontField(
                label: s.acceptWarrantyStart,
                child: Wrap(
                  spacing: HzSpace.s8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: _pickWarranty,
                      child: Text(_warrantyStart == null ? s.acceptWarrantyPick : formatDate(_warrantyStart!)),
                    ),
                    if (_warrantyStart != null)
                      IconButton(
                        tooltip: s.acceptWarrantyClear,
                        onPressed: () => setState(() => _warrantyStart = null),
                        icon: const Icon(AppIcons.close),
                      ),
                  ],
                ),
              ),
            );
            if (narrow) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [standard, number, warranty]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Gap.item,
              children: [
                Expanded(flex: 3, child: standard),
                Expanded(flex: 2, child: number),
                Expanded(flex: 2, child: warranty),
              ],
            );
          },
        ),
      ),
      SectionHead(s.acceptNotesSection),
      SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            field(s.acceptFollowUps, _followUps, maxLines: 5),
            field(s.acceptRemarks, _remarks, maxLines: 5, hint: s.acceptRemarksHint, last: true),
          ],
        ),
      ),
      // In the browser the PDF is rendered in the app's language (there
      // is no background isolate in which it could be set separately).
      if (!kIsWeb) ...[
        SectionHead(s.acceptLanguage),
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
    ];
    final proof = <Widget>[
      if (defects.isNotEmpty) ...[
        SectionHead(s.acceptDefects, count: defects.length),
        Text(s.acceptDefectsHint, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
        const SizedBox(height: Gap.item),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth < _twoColumns ? 1 : 2;
            final width = (box.maxWidth - (columns - 1) * Gap.item) / columns;
            return Wrap(
              spacing: Gap.item,
              runSpacing: Gap.item,
              children: [
                for (final item in defects)
                  SizedBox(
                    width: width,
                    child: _DefectTile(
                      item: item,
                      image: _defectImages[item.address],
                      onAdd: () => _addDefectPhoto(item.address),
                      onRemove: () => setState(() => _defectImages.remove(item.address)),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
      SectionHead(s.acceptSignatures),
      SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            field(s.acceptSigner, _signer),
            _SignatureTile(label: s.acceptSignCustomer, signature: _customerSig, onTap: () => _sign(customer: true)),
            const SizedBox(height: Gap.inner),
            _SignatureTile(
              label: s.acceptSignTechnician,
              signature: _technicianSig,
              onTap: () => _sign(customer: false),
            ),
          ],
        ),
      ),
      const SizedBox(height: Gap.section),
      Builder(
        builder: (buttonContext) => FilledButton(
          onPressed: _ready && !_busy ? () => _create(buttonContext) : null,
          child: Text(s.acceptCreate),
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
              SectionTitle(s.acceptEarlier, count: list.length),
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
    ];
    return Scaffold(
      appBar: AppBar(title: Text(s.acceptTitle)),
      // Phone and narrow windows: one column in reading width. From the expanded width on the
      // form uses the window: what is typed on the left, defects and signatures on the right.
      body: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth < Breakpoints.expanded) {
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Widths.reading),
                child: ListView(padding: Gap.page, children: [...head, ...form, ...proof]),
              ),
            );
          }
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Widths.wide),
              child: ListView(
                padding: Gap.page,
                children: [
                  ...head,
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: form),
                      ),
                      const SizedBox(width: Gap.section),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: proof),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// From this width of the form the optional details and the defects use two or
/// three columns.
const _twoColumns = 560.0;

/// A defect (item rated "Problem") with its optional photo or screenshot.
class _DefectTile extends StatelessWidget {
  const _DefectTile({required this.item, required this.image, required this.onAdd, required this.onRemove});

  final CheckItem item;
  final Uint8List? image;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final name = CatalogStore.instance.info(item.address)?.name ?? '';
    final title = [formatGroup(item.address), name].where((t) => t.isNotEmpty).join(' ');
    return Container(
      padding: const EdgeInsets.all(HzSpace.s12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: hz.line, width: Lines.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: formatGroup(item.address), style: context.mono(theme.textTheme.bodyMedium)),
                if (name.isNotEmpty) TextSpan(text: ' $name'),
              ],
            ),
            style: theme.textTheme.bodyMedium,
          ),
          if (item.note case final note?) Text(note, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
          const SizedBox(height: HzSpace.s8),
          if (image case final jpeg?)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ClipRRect(
                      borderRadius: Radii.row,
                      child: Image.memory(
                        jpeg,
                        height: 120,
                        fit: BoxFit.contain,
                        semanticLabel: title,
                        errorBuilder: (_, _, _) => const Icon(AppIcons.image),
                      ),
                    ),
                  ),
                ),
                IconButton(tooltip: s.acceptDefectPhotoRemove, onPressed: onRemove, icon: const Icon(AppIcons.delete)),
              ],
            )
          else
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(AppIcons.image, size: 18),
              label: Text(s.acceptDefectPhotoAdd),
            ),
        ],
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
          // At least as tall as a signature needs; taller when large text wraps the label.
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.symmetric(horizontal: HzSpace.s8),
          alignment: Alignment.center,
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
                      Flexible(
                        child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
                      ),
                    ],
                  ),
                )
              : SizedBox(
                  height: 96,
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
