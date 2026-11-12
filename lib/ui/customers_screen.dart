import 'package:flutter/foundation.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:horizont/horizont.dart';
import 'package:url_launcher/url_launcher.dart';

import '../export/pdf_export.dart';
import '../model/plan.dart';
import 'common.dart';
import 'plan_screen.dart' show unlock;
import '../l10n/locale_controller.dart';
import '../model/customer.dart';
import '../model/installation.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'company_screen.dart';
import 'customer_transfer_screen.dart';
import 'fault_reply_screen.dart';
import 'figure_box.dart';
import 'form_columns.dart';
import 'handover_screen.dart' show pickPackageFile;
import 'service_report_screen.dart';
import 'telegram_row.dart' show formatDate;

/// Installations as customer records (Pro): search, sort, "Wartung fällig"
/// (maintenance due). [onOpen]: switches to an installation; only possible
/// without an active connection, so only from the connect screen.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key, this.onOpen, this.actions = const []});

  final ValueChanged<Installation>? onOpen;

  /// Additional actions in the app bar (open file).
  final List<Widget> actions;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _search = TextEditingController();
  CustomerSort _sort = CustomerSort.name;

  /// Installation shown on the right (wide layout); `null` until one is chosen.
  String? _selected;

  /// From this width on, list and file side by side.
  static const _detailFrom = Breakpoints.expanded;

  /// Width of the list column next to the file.
  static const _listWidth = Widths.column - HzSpace.s32;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _sortLabel(CustomerSort v) => switch (v) {
    CustomerSort.name => s.customerSortName,
    CustomerSort.lastVisit => s.customerSortVisit,
    CustomerSort.maintenance => s.customerSortMaintenance,
  };

  Future<void> _export() async {
    if (!await unlock(context, Feature.customerRecords) || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CustomerExportScreen()));
  }

  String _meta(CustomerEntry e) => [
    if (e.record.customer.isNotEmpty && e.installation.name != e.record.customer) e.installation.name,
    if (e.record.site.isNotEmpty) e.record.site.split('\n').first,
    if (e.lastVisit != null) s.customerLastVisit(formatDate(e.lastVisit!)),
  ].join(metaSeparator);

  /// Search, sorting and the list. [selected]: wide layout, rows choose the file on the right.
  List<Widget> _listChildren(BuildContext context, List<CustomerEntry> list, {required bool wide, String? selected}) {
    final now = DateTime.now();
    return [
      TextField(
        controller: _search,
        style: context.hzTheme.field,
        decoration: InputDecoration(prefixIcon: const Icon(AppIcons.search), hintText: s.customerSearch),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: Gap.item),
      FilterBar<CustomerSort>(
        segments: [for (final v in CustomerSort.values) ButtonSegment(value: v, label: Text(_sortLabel(v)))],
        selected: _sort,
        onChanged: (v) => setState(() => _sort = v),
      ),
      const SizedBox(height: Gap.section),
      if (list.isEmpty)
        HorizontEmptyHint(text: s.customerNone, icon: AppIcons.customers)
      else if (wide)
        Semantics(
          container: true,
          label: s.customerListLabel,
          child: RowCard(
            flat: true,
            children: [
              for (final e in list)
                _CustomerRow(
                  key: ValueKey('customer-${e.installation.id}'),
                  title: e.title,
                  meta: _meta(e),
                  due: e.maintenanceDue(now),
                  selected: e.installation.id == selected,
                  onTap: () => setState(() => _selected = e.installation.id),
                ),
            ],
          ),
        )
      else
        RowCard(
          children: [
            for (final e in list)
              CardRow(
                title: e.title,
                meta: _meta(e),
                chevron: true,
                trailing: e.maintenanceDue(now) ? HorizontBadge(HorizontStatus.warning, label: s.customerDue) : null,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CustomerDetailScreen(installation: e.installation, onOpen: widget.onOpen),
                  ),
                ),
              ),
          ],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final store = CustomerStore.instance;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.customerTitle),
        actions: [
          ...widget.actions,
          IconButton(
            tooltip: s.companyTitle,
            icon: const Icon(AppIcons.company),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CompanyScreen())),
          ),
          PopupMenuButton<VoidCallback>(
            icon: Icon(AppIcons.more),
            tooltip: s.chartsMore,
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              PopupMenuItem(value: () => unawaited(_export()), child: Text(s.customerExportAll)),
              PopupMenuItem(value: () => unawaited(pickPackageFile(context)), child: Text(s.customerOpenFile)),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= _detailFrom;
          return ListenableBuilder(
            listenable: Listenable.merge([store, InstallationStore.instance]),
            builder: (context, _) {
              final list = filterCustomers(store.entries, query: _search.text, sort: _sort);
              if (!wide) {
                // Phone and narrow windows: one column in reading width, the file opens as a page.
                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: Widths.reading),
                    child: ListView(padding: Gap.page, children: _listChildren(context, list, wide: false)),
                  ),
                );
              }
              // The chosen one while it is in the list; otherwise the active installation, then
              // the first: the right side is never empty while there is a file to show.
              final active = InstallationStore.instance.active.id;
              final shown =
                  list.where((e) => e.installation.id == _selected).firstOrNull ??
                  list.where((e) => e.installation.id == active).firstOrNull ??
                  list.firstOrNull;
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: Widths.wide),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: _listWidth,
                        child: ListView(
                          padding: Gap.page,
                          children: _listChildren(context, list, wide: true, selected: shown?.installation.id),
                        ),
                      ),
                      const VerticalDivider(width: Lines.hairline),
                      Expanded(
                        child: shown == null
                            ? Center(
                                child: HorizontEmptyHint(text: s.customerSelectHint, icon: AppIcons.customers),
                              )
                            : CustomerDetailView(
                                key: ValueKey('file-${shown.installation.id}'),
                                installation: shown.installation,
                                onOpen: widget.onOpen,
                                embedded: true,
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Row of the list in the wide layout: chooses the file shown on the right. The chosen one is
/// tinted and announced as selected; Enter or Space on the focused row chooses it.
class _CustomerRow extends StatelessWidget {
  const _CustomerRow({
    super.key,
    required this.title,
    required this.meta,
    required this.due,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String meta;
  final bool due;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HorizontSelectable(
      selected: selected,
      onTap: onTap,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: HzSpace.s12, vertical: HzSpace.s8),
      child: Row(
        spacing: HzSpace.s8,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyLarge),
                if (meta.isNotEmpty)
                  Text(meta, style: theme.textTheme.bodySmall?.copyWith(color: context.hz.textFaint)),
              ],
            ),
          ),
          if (due) HorizontBadge(HorizontStatus.warning, label: s.customerDue),
        ],
      ),
    );
  }
}

/// Customer file of an installation as a page (phone, or opened from elsewhere).
class CustomerDetailScreen extends StatelessWidget {
  const CustomerDetailScreen({super.key, required this.installation, this.onOpen});

  final Installation installation;
  final ValueChanged<Installation>? onOpen;

  @override
  Widget build(BuildContext context) => CustomerDetailView(installation: installation, onOpen: onOpen);
}

/// Customer file of an installation: customer data, call/mail/map, visit history, documents.
/// [embedded]: the right column of the wide list, without a page frame of its own; its menu
/// then sits next to the name.
class CustomerDetailView extends StatelessWidget {
  const CustomerDetailView({super.key, required this.installation, this.onOpen, this.embedded = false});

  final Installation installation;
  final ValueChanged<Installation>? onOpen;
  final bool embedded;

  Future<void> _launch(BuildContext context, Uri? uri) async {
    if (uri == null) return;
    final colors = context.hz;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
    } on Object catch (e) {
      debugPrint('Link nicht geöffnet: $e');
    }
    messenger.showSnackBar(horizontMessageSnackBar(colors, s.customerLinkFailed, status: HorizontStatus.warning));
  }

  String _kindText(VisitKind k) => switch (k) {
    VisitKind.connection => s.visitConnection,
    VisitKind.commissioning => s.visitCommissioning,
    VisitKind.acceptance => s.visitAcceptance,
    VisitKind.serviceReport => s.visitServiceReport,
    VisitKind.faultReport => s.visitFaultReport,
    VisitKind.handover => s.visitHandover,
    VisitKind.report => s.visitReport,
    VisitKind.faultReply => s.replyTitle,
    VisitKind.manual => s.visitManual,
  };

  @override
  Widget build(BuildContext context) {
    final store = CustomerStore.instance;
    final id = installation.id;
    final theme = Theme.of(context);
    final hz = context.hz;
    return ListenableBuilder(
      listenable: Listenable.merge([store, InstallationStore.instance]),
      builder: (context, _) {
        final r = store.record(id);
        final visits = store.visits(id);
        final next = r.nextMaintenance(visits);
        final due = store.maintenanceDue(id);
        final active = InstallationStore.instance.active.id == id;
        final phone = phoneUri(r.phone);
        final mail = mailUri(r.email);
        final maps = mapsUri(r.site, defaultTargetPlatform, web: kIsWeb);
        Future<void> edit() async {
          if (!await unlock(context, Feature.customerRecords) || !context.mounted) return;
          await Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => CustomerEditScreen(installationId: id)));
        }

        Future<void> pdf() async {
          final bytes = await buildCustomerRecordPdf(installation.name, r, store.visits(id));
          if (!context.mounted) return;
          await saveBytes(context, bytes, pdfName(s.customerTitle), mimeType: 'application/pdf');
        }

        Future<void> export() async {
          if (!await unlock(context, Feature.customerRecords) || !context.mounted) return;
          await Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => CustomerExportScreen(installation: installation)));
        }

        void copy(String value) => unawaited(Clipboard.setData(ClipboardData(text: value)));
        final menu = PopupMenuButton<VoidCallback>(
          icon: Icon(AppIcons.more),
          tooltip: s.chartsMore,
          onSelected: (action) => action(),
          itemBuilder: (_) => [
            PopupMenuItem(value: () => unawaited(edit()), child: Text(s.customerEdit)),
            PopupMenuItem(value: () => unawaited(pdf()), child: Text(s.customerPdf)),
            PopupMenuItem(value: () => unawaited(export()), child: Text(s.customerExport)),
          ],
        );
        final title = r.customer.isNotEmpty ? r.customer : installation.name;
        final content = Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Widths.reading),
            child: ListView(
              padding: Gap.page,
              children: [
                if (embedded) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(header: true, child: Text(title, style: theme.textTheme.titleLarge)),
                      ),
                      menu,
                    ],
                  ),
                  const SizedBox(height: Gap.item),
                ],
                RowCard(
                  children: [
                    CardRow(
                      title: title,
                      meta: r.site.isNotEmpty ? r.site : (r.isEmpty ? s.customerEmpty : null),
                      onTap: () => unawaited(edit()),
                      onLongPress: r.site.isEmpty ? null : () => copy(r.site),
                    ),
                    if (r.phone.isNotEmpty)
                      CardRow(
                        title: s.customerPhone,
                        value: r.phone,
                        chevron: false,
                        onTap: phone == null ? null : () => _launch(context, phone),
                        onLongPress: () => copy(r.phone),
                      ),
                    if (r.email.isNotEmpty)
                      CardRow(
                        title: s.customerEmail,
                        value: r.email,
                        chevron: false,
                        onTap: mail == null ? null : () => _launch(context, mail),
                        onLongPress: () => copy(r.email),
                      ),
                    if (r.contact.isNotEmpty)
                      CardRow(title: s.customerContact, value: r.contact, onLongPress: () => copy(r.contact)),
                    if (r.orderNumber.isNotEmpty)
                      CardRow(title: s.customerOrder, value: r.orderNumber, onLongPress: () => copy(r.orderNumber)),
                    if (r.notes.isNotEmpty)
                      CardRow(title: s.customerNotes, meta: r.notes, onLongPress: () => copy(r.notes)),
                    if (maps != null) CardRow(title: s.customerMap, onTap: () => _launch(context, maps)),
                    if (next != null)
                      CardRow(
                        title: s.customerMaintenance,
                        meta: r.maintenanceMonths == null
                            ? formatDate(next)
                            : '${s.customerMaintEvery(r.maintenanceMonths!)}$metaSeparator${formatDate(next)}',
                        trailing: due
                            ? HorizontBadge(HorizontStatus.warning, label: s.customerDue)
                            : HorizontBadge(
                                HorizontStatus.positive,
                                label: s.customerMaintIn(_monthsUntil(DateTime.now(), next)),
                              ),
                      ),
                  ],
                ),
                const SizedBox(height: Gap.item),
                FilledButton(onPressed: () => editVisit(context, id), child: Text(s.customerVisitAdd)),
                if (onOpen != null && !active) ...[
                  const SizedBox(height: Gap.item),
                  OutlinedButton(
                    onPressed: () {
                      onOpen!(installation);
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    child: Text(s.customerSwitch),
                  ),
                ],
                SectionHead(s.customerVisits, count: visits.length),
                if (visits.isEmpty)
                  Text(s.visitNone, style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint))
                else
                  RowCard(
                    flat: true,
                    children: [
                      for (final v in visits)
                        CardRow(
                          title: formatDate(v.time),
                          meta: [
                            if (v.minutes != null) s.visitMinutes(v.minutes!),
                            if (v.text.isNotEmpty) v.text else _kindText(v.kind),
                            // Custom entries speak through their text;
                            // everything else names its kind.
                            if (v.text.isNotEmpty && v.kind != VisitKind.manual) _kindText(v.kind),
                          ].join(metaSeparator),
                          onTap: switch (v.kind) {
                            VisitKind.manual => () => editVisit(context, id, visit: v),
                            // Ready for the service report as soon as the
                            // installation is active.
                            VisitKind.faultReport when active && v.ref != null => () => Navigator.of(
                              context,
                            ).push(MaterialPageRoute<void>(builder: (_) => ServiceReportScreen(recordingId: v.ref))),
                            VisitKind.faultReply when active && v.ref != null => () => unawaited(
                              shareFaultReply(context, v),
                            ),
                            _ => null,
                          },
                          // Short status for the customer, from the report itself.
                          trailing: v.kind == VisitKind.faultReport && active
                              ? IconButton(
                                  tooltip: s.replyTitle,
                                  icon: const Icon(AppIcons.reply),
                                  onPressed: () =>
                                      Navigator.of(context)
                                          .push(MaterialPageRoute<void>(builder: (_) => FaultReplyScreen(report: v))),
                                )
                              : null,
                        ),
                    ],
                  ),
                SectionHead(s.customerDocuments),
                RowCard(
                  children: [
                    CardRow(title: s.customerPdf, value: 'PDF', onTap: () => unawaited(pdf())),
                    // Reports belong to the active installation.
                    if (active)
                      CardRow(
                        title: s.srTitle,
                        value: 'PDF',
                        onTap: () =>
                            Navigator.of(context)
                                .push(MaterialPageRoute<void>(builder: (_) => const ServiceReportScreen())),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
        if (embedded) return content;
        return Scaffold(
          appBar: AppBar(title: Text(s.customerTitle), actions: [menu]),
          body: content,
        );
      },
    );
  }

  /// Whole months until [date], at least 0.
  static int _monthsUntil(DateTime now, DateTime date) {
    final months = (date.year - now.year) * 12 + date.month - now.month;
    return months < 0 ? 0 : months;
  }
}

/// Edits the customer data.
class CustomerEditScreen extends StatefulWidget {
  const CustomerEditScreen({super.key, required this.installationId});

  final String installationId;

  @override
  State<CustomerEditScreen> createState() => _CustomerEditScreenState();
}

class _CustomerEditScreenState extends State<CustomerEditScreen> {
  late final CustomerRecord _r = CustomerStore.instance.record(widget.installationId);
  late final _customer = TextEditingController(text: _r.customer);
  late final _site = TextEditingController(text: _r.site);
  late final _contact = TextEditingController(text: _r.contact);
  late final _phone = TextEditingController(text: _r.phone);
  late final _email = TextEditingController(text: _r.email);
  late final _notes = TextEditingController(text: _r.notes);
  late final _order = TextEditingController(text: _r.orderNumber);
  late final _months = TextEditingController(text: _r.maintenanceMonths?.toString() ?? '');

  @override
  void dispose() {
    for (final c in [_customer, _site, _contact, _phone, _email, _notes, _order, _months]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final months = int.tryParse(_months.text.trim());
    final interval = months != null && months > 0 ? months : null;
    final navigator = Navigator.of(context);
    await CustomerStore.instance.saveRecord(
      widget.installationId,
      CustomerRecord(
        customer: _customer.text.trim(),
        site: _site.text.trim(),
        contact: _contact.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        notes: _notes.text.trim(),
        orderNumber: _order.text.trim(),
        maintenanceMonths: interval,
        // The interval counts from the day it is first set.
        maintenanceSince: interval == null ? null : (_r.maintenanceSince ?? DateTime.now()),
      ),
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
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
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(s.customerEdit),
        actions: [TextButton(onPressed: _save, child: Text(s.commonSave))],
      ),
      // Phone and narrow windows: one column in reading width. From the expanded width on, the
      // customer and the site stand on the left, maintenance and notes on the right. Every field
      // carries its own label.
      body: FormColumns(
        columns: [
          [
            SectionHead(s.acceptCustomerSection),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  field(s.customerName, _customer),
                  field(s.customerAddress, _site, maxLines: 3, keyboard: TextInputType.multiline),
                  field(s.customerContact, _contact),
                  field(s.customerPhone, _phone, keyboard: TextInputType.phone),
                  field(s.customerEmail, _email, keyboard: TextInputType.emailAddress),
                  field(s.customerOrder, _order, last: true),
                ],
              ),
            ),
          ],
          [
            SectionHead(s.customerMaintenanceNotes),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  field(s.customerInterval, _months, keyboard: TextInputType.number),
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.inner),
                    child: HorizontField(
                      label: s.customerNotes,
                      child: TextField(
                        controller: _notes,
                        style: context.hzTheme.field,
                        minLines: 3,
                        maxLines: 8,
                        keyboardType: TextInputType.multiline,
                      ),
                    ),
                  ),
                  Text(
                    s.customerPrivate,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.hz.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Custom history entry: date, duration, text; existing ones can be deleted.
Future<void> editVisit(BuildContext context, String installationId, {Visit? visit}) async {
  // Reading stays free after the subscription ends; editing requires Pro.
  if (!await unlock(context, Feature.customerRecords) || !context.mounted) return;
  await showAdaptiveDialog<void>(
    context: context,
    builder: (_) => _VisitDialog(installationId: installationId, visit: visit),
  );
}

class _VisitDialog extends StatefulWidget {
  const _VisitDialog({required this.installationId, this.visit});

  final String installationId;
  final Visit? visit;

  @override
  State<_VisitDialog> createState() => _VisitDialogState();
}

class _VisitDialogState extends State<_VisitDialog> {
  late DateTime _date = widget.visit?.time ?? DateTime.now();
  late final _minutes = TextEditingController(text: widget.visit?.minutes?.toString() ?? '');
  late final _text = TextEditingController(text: widget.visit?.text ?? '');

  @override
  void dispose() {
    _minutes.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 366)),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    await CustomerStore.instance.saveVisit(
      widget.installationId,
      Visit(
        id: widget.visit?.id ?? Visit.newId(),
        time: _date,
        kind: VisitKind.manual,
        text: _text.text.trim(),
        minutes: int.tryParse(_minutes.text.trim()),
      ),
    );
    navigator.pop();
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    final ok = await showAdaptiveDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog.adaptive(
        title: Text(s.visitDeleteTitle),
        actions: [
          horizontDialogAction(dialog, label: s.commonCancel, onPressed: () => Navigator.pop(dialog, false)),
          horizontDialogAction(
            dialog,
            label: s.commonDelete,
            primary: true,
            destructive: true,
            onPressed: () => Navigator.pop(dialog, true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await CustomerStore.instance.deleteVisit(widget.installationId, widget.visit!.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) => AlertDialog.adaptive(
    title: Text(s.visitManual),
    content: Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.item,
        children: [
          OutlinedButton(onPressed: _pickDate, child: Text(formatDate(_date))),
          TextField(
            controller: _minutes,
            keyboardType: TextInputType.number,
            style: context.hzTheme.field,
            decoration: InputDecoration(labelText: s.visitDuration),
          ),
          TextField(
            controller: _text,
            minLines: 2,
            maxLines: 4,
            style: context.hzTheme.field,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: s.visitText),
          ),
        ],
      ),
    ),
    actions: [
      horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context)),
      if (widget.visit != null)
        horizontDialogAction(context, label: s.commonDelete, destructive: true, onPressed: _delete),
      horizontDialogAction(context, label: s.commonSave, primary: true, onPressed: _save),
    ],
  );
}
