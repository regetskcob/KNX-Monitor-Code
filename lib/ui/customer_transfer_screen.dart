import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../export/customer_file.dart';
import '../export/handover_package.dart';
import '../knx/secure/package_crypto.dart';
import '../l10n/locale_controller.dart';
import '../model/customer.dart';
import '../model/customer_transfer.dart';
import '../model/installation.dart';
import '../model/plan.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'figure_box.dart';
import 'form_columns.dart';
import 'handover_screen.dart' show PasswordCard;
import 'telegram_row.dart' show formatDate;

/// Exports the customer file of [installation], or of all installations, as one
/// password-protected file for a second own device (Pro). Never offered to the customer: it is
/// reached from the customer files only.
class CustomerExportScreen extends StatefulWidget {
  const CustomerExportScreen({super.key, this.installation});

  /// `null`: all installations that have a customer file.
  final Installation? installation;

  @override
  State<CustomerExportScreen> createState() => _CustomerExportScreenState();
}

class _CustomerExportScreenState extends State<CustomerExportScreen> {
  String _password = generatePackagePassword();
  bool _photos = false;
  bool _busy = false;
  int _photoCount = 0;

  /// Installations that go into the file. For "all": first those with a record or visits, then
  /// (read from storage) also those that only have documents or photos.
  late List<Installation> _scope = switch (widget.installation) {
    final one? => [one],
    null => [
      for (final e in CustomerStore.instance.entries)
        if (!e.record.isEmpty || e.visits.isNotEmpty) e.installation,
    ],
  };

  @override
  void initState() {
    super.initState();
    unawaited(_loadScope());
  }

  Future<void> _loadScope() async {
    if (widget.installation == null) {
      final all = await customerExportScope();
      if (!mounted) return;
      setState(() => _scope = all);
    }
    await _countPhotos();
  }

  Future<void> _countPhotos() async {
    try {
      final count = await customerPhotoCount([for (final i in _scope) i.id]);
      if (mounted) setState(() => _photoCount = count);
    } on Object catch (e) {
      debugPrint('Kundenakte: Fotos nicht gezählt: $e');
    }
  }

  Future<void> _create(BuildContext buttonContext) async {
    setState(() => _busy = true);
    try {
      final file = await buildCustomerFile(installations: _scope, includePhotos: _photos);
      if (file.entries.isEmpty) {
        if (mounted) showHorizontMessage(context, s.customerExportNothing, status: HorizontStatus.warning);
        return;
      }
      final bytes = await customerFileToBytes(file, password: _password);
      if (!mounted || !buttonContext.mounted) return;
      final name = fileName(
        widget.installation == null ? s.customerFilePrefix : '${s.customerFilePrefix} ${widget.installation!.name}',
        customerFileExtension,
      );
      await (kIsWeb
          ? saveBytes(buttonContext, bytes, name, mimeType: 'application/octet-stream')
          : shareFile(buttonContext, bytes, name, 'application/octet-stream', origin: rectOf(buttonContext)));
    } on PackageException catch (e) {
      debugPrint('Kundenakten-Datei: $e');
      if (mounted) {
        showHorizontMessage(
          context,
          e.problem == PackageProblem.tooLarge ? s.customerExportTooLarge : s.exportFailedGeneric,
          status: HorizontStatus.critical,
        );
      }
    } on Object catch (e) {
      debugPrint('Kundenakten-Datei: $e');
      if (mounted) showHorizontMessage(context, s.exportFailedGeneric, status: HorizontStatus.critical);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final one = widget.installation;
    return Scaffold(
      appBar: AppBar(title: Text(s.customerExportTitle)),
      // Phone and narrow windows: one column in reading width. From the expanded width on, what
      // goes into the file stands on the left, the password and the way out on the right.
      body: FormColumns(
        intro: [Text(s.customerExportShort, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted))],
        columns: [
          [
            SectionHead(s.handoverContents),
            RowCard(
              children: [
                if (one != null)
                  CardRow(
                    title: switch (CustomerStore.instance.record(one.id).customer) {
                      '' => one.name,
                      final customer => customer,
                    },
                    meta: s.customerVisits,
                    value: '${CustomerStore.instance.visits(one.id).length}',
                  )
                else
                  CardRow(title: s.customerExportScopeAll, meta: s.customerExportCount(_scope.length)),
                if (_photoCount > 0)
                  SwitchRow(
                    title: s.customerExportPhotos,
                    meta: s.customerExportPhotosHint(_photoCount),
                    value: _photos,
                    onChanged: (v) => setState(() => _photos = v),
                  ),
              ],
            ),
          ],
          [
            SectionHead(s.handoverPassword),
            PasswordCard(password: _password, onNew: () => setState(() => _password = generatePackagePassword())),
            const SizedBox(height: Gap.section),
            Builder(
              builder: (buttonContext) => FilledButton(
                onPressed: _busy || _scope.isEmpty ? null : () => _create(buttonContext),
                child: Text(s.customerExportCreate),
              ),
            ),
            if (_scope.isEmpty) ...[
              const SizedBox(height: Gap.item),
              Text(s.customerExportNothing, style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint)),
            ],
            const SizedBox(height: Gap.section),
            Text(s.customerExportOwn, style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint)),
          ],
        ],
      ),
    );
  }
}

/// Labels of the fields in which two records differ.
List<String> recordDifferences(CustomerRecord a, CustomerRecord b) => [
  if (a.customer != b.customer) s.customerName,
  if (a.site != b.site) s.customerAddress,
  if (a.contact != b.contact) s.customerContact,
  if (a.phone != b.phone) s.customerPhone,
  if (a.email != b.email) s.customerEmail,
  if (a.orderNumber != b.orderNumber) s.customerOrder,
  if (a.maintenanceMonths != b.maintenanceMonths || a.maintenanceSince != b.maintenanceSince) s.customerInterval,
  if (a.notes != b.notes) s.customerNotes,
];

/// Second device: shows what an opened customer file would add, asks where the records differ,
/// then merges. Nothing is written before "Take over".
class CustomerImportScreen extends StatefulWidget {
  const CustomerImportScreen({super.key, required this.file, required this.items});

  final CustomerFile file;
  final List<CustomerImportItem> items;

  @override
  State<CustomerImportScreen> createState() => _CustomerImportScreenState();
}

class _CustomerImportScreenState extends State<CustomerImportScreen> {
  /// Installations (ids here) whose record is taken from the file although one is here.
  final _take = <String>{};
  bool _create = false;
  bool _busy = false;

  List<CustomerImportItem> get _here => [
    for (final i in widget.items)
      if (i.installation != null) i,
  ];
  List<CustomerImportItem> get _missing => [
    for (final i in widget.items)
      if (i.installation == null) i,
  ];

  /// Creating the missing ones must fit into the tier's number of installations.
  bool get _mayCreate {
    final installations = InstallationStore.instance;
    return installations.switchable && installations.list.length + _missing.length <= Plan.instance.maxInstallations;
  }

  bool get _nothing => _here.every((i) => i.upToDate) && (_missing.isEmpty || !_mayCreate);

  String _title(CustomerImportItem i) =>
      i.entry.record.customer.isNotEmpty ? i.entry.record.customer : (i.installation?.name ?? i.entry.name);

  Future<void> _apply() async {
    setState(() => _busy = true);
    final colors = context.hz;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final result = await withProgress(
        context,
        s.customerImportOpening,
        () => applyCustomerImport(widget.items, takeRecordFor: _take, createMissing: _create && _mayCreate),
      );
      messenger.showSnackBar(
        horizontMessageSnackBar(
          colors,
          [
            s.customerImportDone(result.installations, result.visits, result.documents),
            if (result.photosSkipped > 0) s.customerImportPhotosSkipped(result.photosSkipped),
          ].join(' '),
          status: result.photosSkipped > 0 ? HorizontStatus.warning : HorizontStatus.positive,
        ),
      );
      navigator.pop();
    } on Object catch (e) {
      debugPrint('Kundenakten übernehmen: $e');
      messenger.showSnackBar(horizontMessageSnackBar(colors, s.actionFailed, status: HorizontStatus.critical));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final store = CustomerStore.instance;
    final company = widget.file.company.isEmpty ? s.handoverUnknownCompany : widget.file.company;
    final conflicts = [
      for (final i in _here)
        if (i.recordDiffers) i,
    ];
    // Below the last section: take over, or say that there is nothing to take.
    final action = [
      const SizedBox(height: Gap.section),
      if (_nothing && !_create && _take.isEmpty)
        Text(s.customerImportNothing, style: theme.textTheme.bodyMedium)
      else
        FilledButton(onPressed: _busy ? null : _apply, child: Text(s.customerImportApply)),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(s.customerImportTitle)),
      // Phone and narrow windows: one column in reading width. From the expanded width on, what
      // the file adds stands on the left and what needs a decision on the right. A file without
      // anything to decide stays one column.
      body: FormColumns(
        intro: [
          Text(
            s.customerImportFrom(company, formatDate(widget.file.created)),
            style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted),
          ),
        ],
        columns: [
          if (_here.isNotEmpty)
            [
              SectionHead(s.customerImportHere, count: _here.length),
              RowCard(
                children: [
                  for (final i in _here)
                    CardRow(
                      title: _title(i),
                      meta: [
                        if (i.takesRecord) s.customerImportRecordNew,
                        if (i.newVisits + i.newDocuments + i.newPhotos > 0)
                          s.customerImportNew(i.newVisits, i.newDocuments, i.newPhotos),
                        if (i.upToDate) s.customerImportUpToDate,
                      ].join(metaSeparator),
                    ),
                ],
              ),
              if (conflicts.isEmpty && _missing.isEmpty) ...action,
            ],
          if (conflicts.isNotEmpty || _missing.isNotEmpty || _here.isEmpty)
            [
              if (conflicts.isNotEmpty) ...[
                SectionHead(s.customerImportConflicts, count: conflicts.length),
                Text(s.customerImportConflictHint, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
                const SizedBox(height: Gap.item),
                RowCard(
                  children: [
                    for (final i in conflicts)
                      SwitchRow(
                        title: _title(i),
                        meta: s.customerImportTakeRecord(
                          recordDifferences(store.record(i.installation!.id), i.entry.record).join(', '),
                        ),
                        value: _take.contains(i.installation!.id),
                        onChanged: (v) => setState(() {
                          v ? _take.add(i.installation!.id) : _take.remove(i.installation!.id);
                        }),
                      ),
                  ],
                ),
              ],
              if (_missing.isNotEmpty) ...[
                SectionHead(s.customerImportMissing, count: _missing.length),
                Text(s.customerImportMissingHint, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
                const SizedBox(height: Gap.item),
                RowCard(
                  children: [
                    for (final i in _missing)
                      CardRow(title: _title(i), meta: i.entry.name == _title(i) ? null : i.entry.name),
                    if (_mayCreate)
                      SwitchRow(
                        title: s.customerImportCreate,
                        meta: s.customerImportCreateHint,
                        value: _create,
                        onChanged: (v) => setState(() => _create = v),
                      ),
                  ],
                ),
              ],
              ...action,
            ],
        ],
      ),
    );
  }
}
