import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter/services.dart';
import 'package:horizont/horizont.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../catalog_store.dart';
import '../knx/demo_tunnel.dart';
import '../knx/group_catalog.dart';
import '../knx/telegram.dart';
import '../model/betrieb_mode.dart';
import '../model/acceptance.dart';
import '../model/alarms.dart';
import '../model/commissioning.dart';
import '../model/company.dart';
import '../model/customer.dart';
import '../model/device_channels.dart';
import '../model/device_label.dart';
import '../model/ets_task_text.dart';
import '../model/ets_tasks.dart';
import '../model/health.dart';
import '../model/plant_report.dart';
import '../model/resident_manual.dart';
import '../model/service_report.dart';
import '../model/statistics.dart';
import '../l10n/locale_controller.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../ui/plant_report_screen.dart' show plantFindingStatus, plantFindingText, plantOutageText, plantPeriodText;
import '../ui/history_chart.dart' show ChartKind, chartLabel;

part 'pdf_customer_docs.dart';
part 'pdf_labels.dart';

// Same values as [Palette] in the app (Horizont, light; as constants for pdf widgets).
const pdfInk = PdfColor.fromInt(0xFF1B1C19); // Palette.ink
const pdfMuted = PdfColor.fromInt(0xFF5C5E57); // Palette.muted
const _line = PdfColor.fromInt(0xFFE3E3DC); // Palette.line
const _zebra = PdfColor.fromInt(0xFFF1F1EC); // Palette.zebra

PdfColor _pdf(Color c) => PdfColor.fromInt(c.toARGB32());

// State colours (light) taken directly from Horizont – in the PDF always together with a word.
final _hz = Palette.of(false);
final _positive = _pdf(_hz.positive);
final _warning = _pdf(_hz.warning);
final _critical = _pdf(_hz.critical);
final _criticalTint = _pdf(_hz.criticalTint);
final _info = _pdf(_hz.info);
final _infoTint = _pdf(_hz.infoTint);
final _warningTint = _pdf(_hz.warningTint);

// Radii as in Horizont: boxes 6, badges 2.
const _rBox = Radii.md;
const _rTag = Radii.sm;
pw.BorderRadius _radius(double r) => pw.BorderRadius.all(pw.Radius.circular(r));

// A hairline structures (slightly finer than 1 px on paper), 2 marks alarms.
const _hairline = Lines.hairline * 0.6;
const _mark = Lines.selection;

/// Font sizes for the PDF in pt: the Horizont steps, scaled down for A4.
abstract final class PdfPt {
  static const _print = 0.65;
  static final title = HzType.headline.size * _print;
  static final body = HzType.callout.size * _print;
  static final data = HzType.data.size * _print;
  static final small = HzType.caption.size * _print;
  static final kennung = HzType.kennung.size * _print;
}

pw.TextStyle pdfStyle(double size, {pw.Font? font, PdfColor color = pdfInk, double tracking = 0}) =>
    pw.TextStyle(font: font, fontSize: size, color: color, letterSpacing: size * tracking);

/// Creates a PDF log of the telegrams (chronological).
///
/// [gateway] e.g. "Gira X1 · 192.168.1.22"; [title]/[note] e.g. for recordings. [simple]: the free
/// version without note and legend, with all telegrams.
Future<Uint8List> buildTelegramPdf(
  List<Telegram> telegrams, {
  required CatalogStore store,
  String? gateway,
  String? title,
  String? note,
  bool simple = false,
}) async {
  final items = [...telegrams]..sort((a, b) => a.time.compareTo(b.time));
  final fonts = await PdfFonts.load();
  return pdfDocument(
    title: title ?? s.monitorExportTitle,
    project: store.catalog.projectName,
    fonts: fonts,
    content: [
      pdfSummary([
        (s.pdfPeriod, _range(items), 2),
        (s.labelTelegrams, '${items.length}', 1),
        (s.connectGateway, gateway ?? '—', 2),
      ], fonts),
      if (!simple) ...[
        if (note != null && note.trim().isNotEmpty) ...[pw.SizedBox(height: 12), pdfNote(note, fonts)],
        pw.SizedBox(height: 12),
        _legend(fonts),
      ],
      pw.SizedBox(height: 12),
      _table(items, store, fonts, showDate: pdfDate(items.first.time) != pdfDate(items.last.time)),
    ],
  );
}

/// Creates a PDF with a history chart and value list of a group address.
///
/// [chart] is the rendered chart (PNG), or `null` if the values cannot be shown graphically.
Future<Uint8List> buildChartPdf({
  required int address,
  required List<Telegram> telegrams,
  required CatalogStore store,
  Uint8List? chart,
  ({double min, double max, double avg})? stats,
  String Function(double)? format,
  String? gateway,
}) async {
  final items = [...telegrams]..sort((a, b) => a.time.compareTo(b.time));
  final info = store.info(address);
  final fonts = await PdfFonts.load();
  final values = items.where((t) => t.type != TelegramType.read).toList();
  return pdfDocument(
    title: info?.name ?? formatGroup(address),
    subtitle: [formatGroup(address), ?info?.path, if (info?.dpt != null) 'DPT ${info!.dpt}'].join(metaSeparator),
    project: store.catalog.projectName,
    fonts: fonts,
    content: [
      pdfSummary([
        (s.pdfPeriod, _range(items), 2),
        (s.pdfValues, '${values.length}', 1),
        if (stats != null && format != null) ...[
          (s.pdfMinimum, format(stats.min), 1),
          (s.pdfMaximum, format(stats.max), 1),
          (s.pdfAverage, format(stats.avg), 1),
        ] else
          (s.connectGateway, gateway ?? '—', 2),
      ], fonts),
      if (chart != null) ...[
        pw.SizedBox(height: 16),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            borderRadius: _radius(_rBox),
            border: pw.Border.all(color: _line, width: _hairline),
          ),
          child: pw.Image(pw.MemoryImage(chart)),
        ),
      ],
      pw.SizedBox(height: 16),
      _legend(fonts),
      pw.SizedBox(height: 12),
      _table(items, store, fonts, showDate: pdfDate(items.first.time) != pdfDate(items.last.time)),
    ],
  );
}

/// Statistics as PDF: key figures, top sources, top addresses, flapping, load peaks.
Future<Uint8List> buildStatisticsPdf(BusStatistics stats, {required CatalogStore store, String? gateway}) async {
  final fonts = await PdfFonts.load();
  String perMinute(double v) => localizeDecimal(v.toStringAsFixed(1));
  return pdfDocument(
    title: s.statsPdfTitle,
    project: store.catalog.projectName,
    fonts: fonts,
    content: [
      pdfSummary([
        (s.pdfPeriod, stats.start == null ? '—' : _range([_stub(stats.start!), _stub(stats.end!)]), 2),
        (s.labelTelegrams, '${stats.total}', 1),
        (s.statsPerMinute, perMinute(stats.perMinute), 1),
        (s.connectGateway, gateway ?? '—', 2),
      ], fonts),
      pw.SizedBox(height: 16),
      ..._simpleTable(s.statsSenders, fonts, [
        for (final x in stats.senders.take(20))
          [
            formatIndividual(x.address),
            store.device(x.address)?.name ?? '',
            '${x.count}',
            x.repeated == 0 ? '' : '${localizeDecimal((x.repeatRate * 100).toStringAsFixed(1))} %',
          ],
      ]),
      ..._simpleTable(s.statsGroups, fonts, [
        for (final g in stats.groups.take(20))
          [
            formatGroup(g.address),
            store.info(g.address)?.name ?? '',
            '${g.count}',
            '${perMinute(stats.groupPerMinute(g))}/min',
          ],
      ]),
      if (stats.flappers.isNotEmpty)
        ..._simpleTable(s.statsFlappers, fonts, [
          for (final g in stats.flappers)
            [
              formatGroup(g.address),
              store.info(g.address)?.name ?? '',
              '${g.count}',
              s.statsEvery(formatInterval(g.medianInterval!)),
            ],
        ]),
      ..._simpleTable(s.statsPeaks, fonts, [
        for (final p in stats.peaks) [pdfDate(p.time), _clock(p.time).substring(0, 8), '', s.statsPerSecond(p.count)],
      ]),
    ],
  );
}

/// Commissioning log: summary, check items per area with result, value and device, notes and
/// signature field.
Future<Uint8List> buildCommissioningPdf(
  ({DateTime? started, List<CheckItem> items}) c, {
  required CatalogStore store,
  String? gateway,
}) async {
  final fonts = await PdfFonts.load();
  int count(CheckState state) => c.items.where((i) => i.state == state).length;
  final checked = c.items.where((i) => i.state != CheckState.open).length;
  final result = _checkResult;
  // Grouped by area (path), in address order.
  final groups = <String, List<CheckItem>>{};
  for (final item in c.items) {
    (groups[store.info(item.address)?.path ?? s.objectsOther] ??= []).add(item);
  }
  pw.Widget cell(String text, {pw.Font? font, PdfColor color = pdfInk}) => pdfPad(
    pw.Text(
      text,
      style: pdfStyle(PdfPt.body, color: color, font: font),
    ),
  );
  return pdfDocument(
    title: s.commPdfTitle,
    project: store.catalog.projectName,
    fonts: fonts,
    content: [
      pdfSummary([
        (s.commStarted, c.started == null ? '—' : '${pdfDate(c.started!)} ${_clock(c.started!).substring(0, 5)}', 2),
        (s.commChecked, '$checked / ${c.items.length}', 1),
        (s.commAnswered, '${count(CheckState.answered)}', 1),
        (s.commSeen, '${count(CheckState.seen)}', 1),
        (s.commOkManual, '${count(CheckState.ok)}', 1),
        (s.commNoAnswer, '${count(CheckState.noAnswer)}', 1),
        (s.commIssue, '${count(CheckState.issue)}', 1),
        (s.connectGateway, gateway ?? '—', 2),
      ], fonts),
      pw.SizedBox(height: 16),
      for (final MapEntry(key: path, value: list) in groups.entries)
        ...pdfSection(
          path,
          fonts,
          count: list.length,
          pw.Table(
            columnWidths: const {
              0: pw.FixedColumnWidth(48),
              1: pw.FlexColumnWidth(3),
              2: pw.FixedColumnWidth(72),
              3: pw.FlexColumnWidth(1.4),
              4: pw.FlexColumnWidth(2.2),
            },
            children: [
              for (final (i, item) in list.indexed)
                pw.TableRow(
                  decoration: pdfRowDecoration(i),
                  children: [
                    cell(formatGroup(item.address), font: fonts.data),
                    cell(store.info(item.address)?.name ?? ''),
                    cell(result(item.state).$1, font: fonts.semibold, color: result(item.state).$2),
                    cell(item.value ?? '', font: fonts.data),
                    _checkSource(item, fonts),
                  ],
                ),
            ],
          ),
        ),
      pw.SizedBox(height: 24),
      // Signature field for the acceptance report.
      pw.Row(
        children: [
          for (final label in [s.commSignedBy, s.commDate, s.commSignature]) ...[
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(height: 28),
                  pw.Container(height: _hairline, color: pdfInk),
                  pw.SizedBox(height: 4),
                  pw.Text(label, style: pdfStyle(PdfPt.small, color: pdfMuted)),
                ],
              ),
            ),
            if (label != s.commSignature) pw.SizedBox(width: 24),
          ],
        ],
      ),
    ],
  );
}

/// Result of a check item as word and colour (in the PDF always both).
(String, PdfColor) _checkResult(CheckState state) => switch (state) {
  CheckState.answered => (s.commAnswered, _positive),
  CheckState.seen => (s.commSeen, _positive),
  CheckState.ok => (s.commOk, _positive),
  CheckState.noAnswer => (s.commNoAnswer, _critical),
  CheckState.issue => (s.commIssue, _critical),
  CheckState.open => (s.commOpen, _warning),
};

HorizontStatus _checkStatus(CheckState state) => switch (state) {
  CheckState.answered || CheckState.seen || CheckState.ok => HorizontStatus.positive,
  CheckState.noAnswer || CheckState.issue => HorizontStatus.critical,
  CheckState.open => HorizontStatus.warning,
};

/// Source and note; a foreign source as a warning.
pw.Widget _checkSource(CheckItem item, PdfFonts fonts) => pdfPad(
  pw.Text(
    [if (item.source != null) formatIndividual(item.source!), if (item.foreign) s.commForeign, ?item.note].join(' · '),
    style: pdfStyle(
      PdfPt.body,
      color: item.foreign
          ? _warning
          : item.note != null
          ? pdfInk
          : pdfMuted,
    ),
  ),
);

/// Signature as vectors in the PDF: strokes relative to the field, y pointing down.
pw.Widget _signature(Signature sig, {double width = 180}) {
  final height = width / Signature.aspect;
  return pw.CustomPaint(
    size: PdfPoint(width, height),
    painter: (canvas, size) {
      canvas
        ..setStrokeColor(pdfInk)
        ..setLineWidth(1.1)
        ..setLineCap(PdfLineCap.round)
        ..setLineJoin(PdfLineJoin.round);
      for (final stroke in sig.strokes) {
        if (stroke.length < 2) continue;
        // PDF counts y from the bottom.
        canvas.moveTo(stroke.first.dx * size.x, (1 - stroke.first.dy) * size.y);
        for (final p in stroke.skip(1)) {
          canvas.lineTo(p.dx * size.x, (1 - p.dy) * size.y);
        }
        canvas.strokePath();
      }
    },
  );
}

/// Acceptance report: customer and site, commissioning result per area, problems and open points,
/// remarks, both signatures and the checksum over the content.
String _acceptDate(DateTime? d) {
  if (d == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}';
}

/// The optional details of an acceptance report as cells of the summary (label, value, width);
/// empty when none is filled in, so such a report looks as before.
List<(String, String, int)> acceptanceDetailCells(Acceptance a) => [
  if (a.standard.isNotEmpty) (s.acceptStandard, a.standard, 3),
  if (a.projectNumber.isNotEmpty) (s.acceptProjectNumber, a.projectNumber, 2),
  if (a.warrantyStart case final d?) (s.acceptWarrantyStart, pdfDate(d), 2),
];

/// [photos]: the images of the defects by photo ID. An image that is missing or is not the one the
/// report was signed with (hash) is replaced by a note.
Future<Uint8List> buildAcceptancePdf(Acceptance a, {Map<String, Uint8List> photos = const {}}) async {
  final fonts = await PdfFonts.load();
  final open = [
    for (final i in a.items)
      if (i.state == CheckState.open || i.state == CheckState.noAnswer) i,
  ];
  final issues = [
    for (final i in a.items)
      if (i.state == CheckState.issue) i,
  ];
  String name(CheckItem i) => a.groups[i.address]?.name ?? '';
  final groups = <String, List<CheckItem>>{};
  for (final item in a.items) {
    (groups[a.groups[item.address]?.path ?? s.objectsOther] ??= []).add(item);
  }
  pw.Widget cell(String text, {pw.Font? font, PdfColor color = pdfInk}) => pdfPad(
    pw.Text(
      text,
      style: pdfStyle(PdfPt.body, color: color, font: font),
    ),
  );
  pw.Widget list(List<CheckItem> items) => pw.Table(
    columnWidths: const {0: pw.FixedColumnWidth(48), 1: pw.FlexColumnWidth(3), 2: pw.FlexColumnWidth(3)},
    children: [
      for (final (i, item) in items.indexed)
        pw.TableRow(
          decoration: pdfRowDecoration(i),
          children: [
            cell(formatGroup(item.address), font: fonts.data),
            cell(name(item)),
            cell(item.note ?? _checkResult(item.state).$1, color: item.note != null ? pdfInk : pdfMuted),
          ],
        ),
    ],
  );
  pw.Widget signer(String role, String person, Signature sig) => pw.Expanded(
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _signature(sig),
        pw.Container(height: _hairline, color: pdfInk),
        pw.SizedBox(height: 4),
        pw.Text(person.isEmpty ? role : '$role: $person', style: pdfStyle(PdfPt.small, color: pdfMuted)),
      ],
    ),
  );
  final created = '${pdfDate(a.created)} ${_clock(a.created).substring(0, 5)}';
  return pdfDocument(
    title: s.acceptPdfTitle,
    subtitle: a.customer,
    project: a.project,
    fonts: fonts,
    content: [
      pdfSummary([
        (s.acceptCustomer, a.customer, 2),
        (s.acceptSite, a.site.isEmpty ? '—' : a.site, 3),
        (s.commDate, created, 2),
        (s.acceptTechnician, a.technician, 2),
      ], fonts),
      pw.SizedBox(height: 8),
      pdfSummary([
        (s.commStarted, a.started == null ? '—' : pdfDate(a.started!), 2),
        (s.commChecked, '${a.done} / ${a.items.length}', 1),
        (s.commIssue, '${issues.length}', 1),
        (s.commOpen, '${open.length}', 1),
        (s.connectGateway, a.gateway ?? '—', 3),
      ], fonts),
      if (a.hasDetails) ...[pw.SizedBox(height: 8), pdfSummary(acceptanceDetailCells(a), fonts)],
      pw.SizedBox(height: 16),
      for (final MapEntry(key: path, value: items) in groups.entries)
        ...pdfSection(
          path,
          fonts,
          count: items.length,
          pw.Table(
            columnWidths: const {
              0: pw.FixedColumnWidth(48),
              1: pw.FlexColumnWidth(3),
              2: pw.FixedColumnWidth(72),
              3: pw.FlexColumnWidth(1.4),
              4: pw.FlexColumnWidth(2.2),
            },
            children: [
              for (final (i, item) in items.indexed)
                pw.TableRow(
                  decoration: pdfRowDecoration(i),
                  children: [
                    cell(formatGroup(item.address), font: fonts.data),
                    cell(name(item)),
                    pdfPad(
                      _statusLine(
                        _checkResult(item.state).$1,
                        _checkStatus(item.state),
                        _checkResult(item.state).$2,
                        fonts,
                      ),
                    ),
                    cell(item.value ?? '', font: fonts.data),
                    _checkSource(item, fonts),
                  ],
                ),
            ],
          ),
        ),
      if (issues.isNotEmpty) ...pdfSection(s.acceptIssues, fonts, count: issues.length, list(issues)),
      if (a.defectPhotos.isNotEmpty)
        ...pdfSection(
          s.acceptDefects,
          fonts,
          count: a.defectPhotos.length,
          pw.Wrap(
            children: [
              for (final item in issues)
                if (a.defectPhotos[item.address] case final photo?)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 8, right: 8),
                    child: pw.SizedBox(
                      width: 248,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            [formatGroup(item.address), name(item)].where((t) => t.isNotEmpty).join('  '),
                            style: pdfStyle(PdfPt.small, font: fonts.medium),
                          ),
                          if (item.note case final note?) pw.Text(note, style: pdfStyle(PdfPt.small, color: pdfMuted)),
                          switch (photos[photo.id]) {
                                final jpeg? when photo.matches(jpeg) => _commentShot(jpeg),
                                _ => null,
                              } ??
                              pw.Text(s.acceptDefectPhotoMissing, style: pdfStyle(PdfPt.small, color: pdfMuted)),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      if (open.isNotEmpty) ...pdfSection(s.acceptOpenPoints, fonts, count: open.length, list(open)),
      // Boxes and the closing part with signatures do not break across pages.
      if (a.followUps.isNotEmpty) ...[
        pw.Inseparable(child: pdfNote(a.followUps, fonts, label: s.acceptFollowUps)),
        pw.SizedBox(height: 12),
      ],
      if (a.remarks.isNotEmpty) ...[
        pw.Inseparable(child: pdfNote(a.remarks, fonts, label: s.acceptRemarks)),
        pw.SizedBox(height: 12),
      ],
      pw.SizedBox(height: 8),
      pw.Inseparable(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(s.acceptConfirmation, style: pdfStyle(PdfPt.body)),
            pw.SizedBox(height: 12),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                signer(
                  s.acceptRoleCustomer,
                  a.customerSigner.isEmpty ? a.customer : a.customerSigner,
                  a.customerSignature,
                ),
                pw.SizedBox(width: 32),
                signer(s.acceptRoleTechnician, a.technician, a.technicianSignature),
              ],
            ),
            if (a.fourEyes) ...[
              pw.SizedBox(height: 12),
              if (a.checkedBy != null)
                pw.Text(s.teamPdfChecked(a.checkedBy!, _acceptDate(a.checkedAt)), style: pdfStyle(PdfPt.body)),
              if (a.approvedBy != null)
                pw.Text(s.teamPdfApproved(a.approvedBy!, _acceptDate(a.approvedAt)), style: pdfStyle(PdfPt.body)),
            ],
            pw.SizedBox(height: 16),
            pw.Text(
              s.acceptChecksum(a.checksum),
              style: pdfStyle(PdfPt.small, color: pdfMuted, font: fonts.data),
            ),
            pw.SizedBox(height: 2),
            pw.Text(s.acceptSignatureNote, style: pdfStyle(PdfPt.small, color: pdfMuted)),
          ],
        ),
      ),
    ],
  );
}

/// Health check as PDF: traffic light per area, findings with a "new" badge.
Future<Uint8List> buildHealthPdf(HealthRun run, {required CatalogStore store, String? gateway}) async {
  final fonts = await PdfFonts.load();
  HorizontStatus severityStatus(Severity v) => switch (v) {
    Severity.ok => HorizontStatus.positive,
    Severity.info => HorizontStatus.info,
    Severity.warning => HorizontStatus.warning,
    Severity.error => HorizontStatus.critical,
  };
  (String, PdfColor) severity(Severity v) => switch (v) {
    Severity.ok => (s.hzCSeverityOk, _positive),
    Severity.info => (s.hzCSeverityInfo, _info),
    Severity.warning => (s.hzCSeverityWarning, _warning),
    Severity.error => (s.hzCSeverityError, _critical),
  };
  String area(HealthArea a) => switch (a) {
    HealthArea.read => s.healthAreaRead,
    HealthArea.cycle => s.healthAreaCycle,
    HealthArea.readings => s.healthAreaValues,
    HealthArea.dpt => s.healthAreaDpt,
    HealthArea.bus => s.healthAreaBus,
    HealthArea.lighting => s.daliHealthArea,
  };
  // Lighting only where there is DALI: the row of areas stays as it was for everyone else.
  final areas = [
    for (final a in HealthArea.values)
      if (a != HealthArea.lighting || run.countIn(a) > 0) a,
  ];
  pw.Widget cell(String text, {pw.Font? font, PdfColor color = pdfInk}) => pdfPad(
    pw.Text(
      text,
      style: pdfStyle(PdfPt.body, color: color, font: font),
    ),
  );
  return pdfDocument(
    title: s.healthPdfTitle,
    project: store.catalog.projectName,
    fonts: fonts,
    content: [
      pdfSummary([
        (s.pdfPeriod, '${pdfDate(run.time)} ${_clock(run.time).substring(0, 5)}', 2),
        if (run.asked > 0) (s.healthAreaRead, s.healthAnswered(run.answered, run.asked), 2),
        (s.healthNewSection, '${run.newKeys.length}', 1),
        (s.connectGateway, gateway ?? '—', 2),
      ], fonts),
      pw.SizedBox(height: 12),
      // Traffic light per area: name, count and state as a word in its colour.
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final a in areas) ...[
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _line, width: _hairline),
                  borderRadius: _radius(_rBox),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: pw.Text(area(a), style: pdfStyle(PdfPt.body, font: fonts.medium)),
                        ),
                        pw.Text('${run.countIn(a)}', style: pdfStyle(PdfPt.data, font: fonts.data)),
                      ],
                    ),
                    _statusLine(
                      severity(run.worst(a)).$1,
                      severityStatus(run.worst(a)),
                      severity(run.worst(a)).$2,
                      fonts,
                    ),
                  ],
                ),
              ),
            ),
            if (a != areas.last) pw.SizedBox(width: 8),
          ],
        ],
      ),
      pw.SizedBox(height: 16),
      for (final a in areas)
        if (run.findings.where((f) => f.kind.area == a).toList() case final list when list.isNotEmpty)
          ...pdfSection(
            area(a),
            fonts,
            count: list.length,
            pw.Table(
              columnWidths: const {0: pw.FlexColumnWidth(2.2), 1: pw.FlexColumnWidth(4), 2: pw.FixedColumnWidth(36)},
              children: [
                for (final (i, f) in list.indexed)
                  pw.TableRow(
                    decoration: pdfRowDecoration(i),
                    children: [
                      cell(findingTitle(f), font: fonts.medium, color: severity(f.kind.severity).$2),
                      cell(findingDetail(f)),
                      run.isNew(f) ? pdfPad(_tag(s.healthNew, _info, _infoTint, fonts)) : pw.SizedBox(),
                    ],
                  ),
              ],
            ),
          ),
      if (run.findings.isEmpty)
        pw.Text(
          s.healthAllGood,
          style: pdfStyle(PdfPt.body, font: fonts.semibold, color: _positive),
        ),
    ],
  );
}

/// Tasks for the ETS: overview with the changed datapoint types, then one page per device with a
/// drawing ([drawings], PNG per device, rendered beforehand by the app), the tasks to tick off and
/// the channel mapping from the project. Devices with real tasks first, those with only notes
/// after.
Future<Uint8List> buildEtsTasksPdf(
  EtsTasks tasks, {
  required CatalogStore store,
  Map<int, Uint8List> drawings = const {},
}) async {
  final fonts = await PdfFonts.load();
  final catalog = store.catalog;
  final body = pdfStyle(PdfPt.body);
  final small = pdfStyle(PdfPt.small, color: pdfMuted);
  final data = pdfStyle(PdfPt.data, font: fonts.data);
  final strong = pdfStyle(PdfPt.body, font: fonts.semibold);
  String groupText(int a) => [formatGroup(a), ?catalog[a]?.name].join('  ');
  String deviceText(int a) => [formatIndividual(a), ?catalog.devices[a]?.name].join('  ');
  String dptText(Dpt? d) => d == null ? '—' : '$d';

  String title(EtsTask t) => etsTaskTitle(t);
  String todo(EtsTask t) => etsTaskTodo(t);
  String why(EtsTask t) => switch (t.kind) {
    EtsTaskKind.statusWithoutTransmit => s.checkStatusNoTransmitHint,
    EtsTaskKind.readWithoutReadFlag => s.checkReadNoReadFlagHint,
    EtsTaskKind.multipleReadAnswers => s.checkMultipleReadAnswersHint,
    EtsTaskKind.objectWithoutCommunication => s.checkObjectsNoCommHint,
    EtsTaskKind.multipleSenders => s.checkMultipleSendersHint,
    EtsTaskKind.deviceWithoutLinks => s.checkDevicesNoLinksHint,
    EtsTaskKind.withoutSender => s.checkWithoutSenderHint,
    EtsTaskKind.withoutReceiver => s.checkWithoutReceiverHint,
    EtsTaskKind.mainGroup1415 => s.checkMainGroup1415Hint,
    EtsTaskKind.filterNotForwarded || EtsTaskKind.filterCrossLine => s.checkFilterHint,
    EtsTaskKind.noName || EtsTaskKind.noDpt => s.checkIncompleteHint,
    EtsTaskKind.dpt ||
    EtsTaskKind.learnedName ||
    EtsTaskKind.learnedNew ||
    EtsTaskKind.rename ||
    EtsTaskKind.notInProject ||
    EtsTaskKind.serialMismatch ||
    EtsTaskKind.missingOnBus ||
    EtsTaskKind.crowdedLine ||
    EtsTaskKind.standardDeviation => '',
  };

  // Checkbox for ticking off, hairline like the tables.
  pw.Widget checkbox() => pw.Container(
    width: 8,
    height: 8,
    margin: const pw.EdgeInsets.only(top: 2, right: 8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: pdfInk, width: 0.6),
      borderRadius: _radius(1),
    ),
  );

  String objectText(int? number, String? text) =>
      [if (number != null) s.etsObject(number), if (text case final t? when t.isNotEmpty) '„$t“'].join(' ');
  String otherText(EtsObject o, int device) => [
    if (o.device != device) deviceText(o.device),
    if (objectText(o.number, o.text) case final t when t.isNotEmpty) t,
  ].join(', ');

  pw.Widget taskRow(EtsTask t, int i) {
    final object = objectText(t.object, t.objectText);
    final where = [if (object.isNotEmpty) object, if (t.group != null) groupText(t.group!)].join(metaSeparator);
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: pdfRowDecoration(i),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          checkbox(),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Text(
                      title(t),
                      style: pdfStyle(PdfPt.body, font: fonts.semibold, color: t.hint ? _info : _warning),
                    ),
                    if (t.hint) ...[pw.SizedBox(width: 6), _tag(s.etsHint, _info, _infoTint, fonts)],
                  ],
                ),
                if (where.isNotEmpty) pw.Text(where, style: data),
                if (t.others.isNotEmpty && t.kind == EtsTaskKind.multipleSenders)
                  pw.Text(s.etsAlsoSends(t.others.map((o) => otherText(o, t.device!)).join('; ')), style: small),
                pw.SizedBox(height: 2),
                pw.Text(todo(t), style: body),
                if (why(t).isNotEmpty) pw.Text(why(t), style: small),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget channelTable(int device, List<EtsTask> list) {
    final flagged = {for (final t in list) (t.group, t.object)};
    final channels = channelsOf(device, catalog);
    if (channels.isEmpty) return pw.Text(s.etsNoChannels, style: small);
    String flags(DeviceObject o) {
      for (final l in catalog[o.address]?.links ?? const <GroupLink>[]) {
        if (l.device == device && (o.number == null || l.object == o.number)) return l.flags?.code ?? '';
      }
      return '';
    }

    final head = pdfStyle(PdfPt.kennung, font: fonts.semibold, color: pdfMuted, tracking: HzType.kennung.tracking);
    var row = 0;
    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(1.6),
        1: pw.FlexColumnWidth(3),
        2: pw.FlexColumnWidth(3.4),
        3: pw.FixedColumnWidth(52),
      },
      children: [
        pw.TableRow(
          children: [
            for (final h in [s.etsColumnChannel, s.etsColumnObject, s.etsColumnGroup, s.etsColumnFlags])
              pdfPad(pw.Text(h.toUpperCase(), style: head)),
          ],
        ),
        for (final c in channels)
          for (final (k, o) in c.objects.indexed)
            pw.TableRow(
              decoration: flagged.contains((o.address, o.number)) || flagged.contains((o.address, null))
                  ? pw.BoxDecoration(
                      color: _warningTint,
                      border: const pw.Border(
                        bottom: pw.BorderSide(color: _line, width: _hairline),
                      ),
                    )
                  : pdfRowDecoration(row++),
              children: [
                pdfPad(
                  pw.Text(
                    k > 0 ? '' : [c.label.isEmpty ? s.deviceGeneral : c.label, ?c.title].join(' · '),
                    style: k > 0 ? small : strong,
                  ),
                ),
                pdfPad(pw.Text([if (o.number != null) '${o.number}', ?o.text].join('  '), style: body)),
                pdfPad(pw.Text(groupText(o.address), style: data)),
                pdfPad(pw.Text(flags(o), style: data)),
              ],
            ),
      ],
    );
  }

  final ordered = tasks.devices.entries.toList()
    ..sort((a, b) {
      final hintsOnly = (a.value.every((t) => t.hint) ? 1 : 0).compareTo(b.value.every((t) => t.hint) ? 1 : 0);
      return hintsOnly != 0 ? hintsOnly : a.key.compareTo(b.key);
    });
  final all = [...tasks.groups, ...tasks.project, for (final l in tasks.devices.values) ...l];
  final importable = tasks.importable;
  final manual = tasks.manual;
  // What is in the project today and what the import makes of it. The previous state comes from the
  // tasks themselves: in the background the catalog only knows project and learned data combined.
  String importBefore(EtsTask t) => switch (t.kind) {
    EtsTaskKind.dpt => dptText(t.beforeDpt),
    EtsTaskKind.learnedName || EtsTaskKind.rename => t.beforeName ?? '—',
    _ => '—',
  };
  String importAfter(EtsTask t) => switch (t.kind) {
    EtsTaskKind.dpt => dptText(t.dpt),
    _ => [?t.name, if (t.dpt != null) '${t.dpt}'].join(metaSeparator),
  };
  final hints = all.where((t) => t.hint).length;

  return pdfDocument(
    title: s.etsTasks,
    project: catalog.projectName,
    fonts: fonts,
    content: [
      pdfSummary([
        (s.etsSummaryDevices, '${tasks.devices.length}', 1),
        (s.etsSummaryTasks, '${all.length - hints}', 1),
        (s.etsSummaryHints, '$hints', 1),
        (s.etsSummaryImport, '${tasks.imports.length}', 1),
      ], fonts),
      pw.SizedBox(height: 12),
      pw.Text(s.etsHowTo, style: body),
      if (!tasks.hasFlags) ...[
        pw.SizedBox(height: 8),
        pw.Text(DemoTunnel.active ? s.checkDemoNoFlags : s.checkReimport, style: pdfStyle(PdfPt.body, color: _warning)),
      ],
      pw.SizedBox(height: 16),
      if (tasks.isEmpty)
        pw.Text(
          s.etsTasksNone,
          style: pdfStyle(PdfPt.body, font: fonts.semibold, color: _positive),
        ),
      if (importable.isNotEmpty) ...[
        ...pdfSection(
          s.etsImportSection,
          fonts,
          count: importable.length,
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Table(
                columnWidths: const {
                  0: pw.FixedColumnWidth(22),
                  1: pw.FlexColumnWidth(4),
                  2: pw.FlexColumnWidth(2.2),
                  3: pw.FlexColumnWidth(3),
                },
                children: [
                  pw.TableRow(
                    children: [
                      pw.SizedBox(),
                      for (final h in [s.etsColumnGroup, s.etsInProject, s.etsNew])
                        pdfPad(
                          pw.Text(
                            h.toUpperCase(),
                            style: pdfStyle(
                              PdfPt.kennung,
                              font: fonts.semibold,
                              color: pdfMuted,
                              tracking: HzType.kennung.tracking,
                            ),
                          ),
                        ),
                    ],
                  ),
                  for (final (i, t) in importable.indexed)
                    pw.TableRow(
                      decoration: pdfRowDecoration(i),
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.only(left: 6, top: 4), child: checkbox()),
                        pdfPad(
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(groupText(t.group!), style: data),
                              pw.Text(title(t), style: small),
                            ],
                          ),
                        ),
                        pdfPad(
                          pw.Text(
                            importBefore(t),
                            style: pdfStyle(PdfPt.data, font: fonts.data, color: pdfMuted),
                          ),
                        ),
                        pdfPad(pw.Text(importAfter(t), style: strong)),
                      ],
                    ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Text(s.etsImportNote, style: small),
            ],
          ),
        ),
      ],
      if (manual.isNotEmpty)
        ...pdfSection(
          s.etsGroupsSection,
          fonts,
          count: manual.length,
          pw.Column(children: [for (final (i, t) in manual.indexed) taskRow(t, i)]),
        ),
      if (tasks.project.isNotEmpty)
        ...pdfSection(
          s.etsProjectSection,
          fonts,
          count: tasks.project.length,
          pw.Column(children: [for (final (i, t) in tasks.project.indexed) taskRow(t, i)]),
        ),
      if (ordered.isNotEmpty)
        ...pdfSection(
          s.etsOverview,
          fonts,
          count: ordered.length,
          pw.Table(
            columnWidths: const {0: pw.FlexColumnWidth(5), 1: pw.FlexColumnWidth(2)},
            children: [
              for (final (i, e) in ordered.indexed)
                pw.TableRow(
                  decoration: pdfRowDecoration(i),
                  children: [
                    pdfPad(pw.Text(deviceText(e.key), style: body)),
                    pdfPad(
                      pw.RichText(
                        textAlign: pw.TextAlign.right,
                        text: pw.TextSpan(
                          children: [
                            if (e.value.where((t) => !t.hint).length case final n when n > 0)
                              pw.TextSpan(
                                text: s.etsTaskCount(n),
                                style: pdfStyle(PdfPt.body, font: fonts.semibold, color: _warning),
                              ),
                            if (e.value.where((t) => t.hint).length case final n when n > 0) ...[
                              if (e.value.any((t) => !t.hint)) pw.TextSpan(text: ', ', style: body),
                              pw.TextSpan(
                                text: s.etsHintCount(n),
                                style: pdfStyle(PdfPt.body, color: _info),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      // A new page per device.
      for (final MapEntry(key: device, value: list) in ordered) ...[
        pw.NewPage(),
        _kennung(s.etsDevice(formatIndividual(device)), fonts),
        pw.SizedBox(height: 4),
        pw.Text(
          catalog.devices[device]?.name ?? formatIndividual(device),
          style: pdfStyle(PdfPt.title * 0.8, font: fonts.title),
        ),
        if ([
              ?catalog.devices[device]?.product,
              ?catalog.devices[device]?.manufacturer,
              ?catalog.devices[device]?.location,
            ]
            case final meta when meta.isNotEmpty)
          pw.Text(meta.join(metaSeparator), style: small),
        pw.SizedBox(height: 10),
        if (drawings[device] case final png?) ...[_drawing(png), pw.SizedBox(height: 12)],
        ...pdfSection(
          s.etsTasksOnPage,
          fonts,
          count: list.length,
          pw.Column(children: [for (final (i, t) in list.indexed) taskRow(t, i)]),
        ),
        ...pdfSection(s.etsChannels, fonts, channelTable(device, list)),
      ],
    ],
  );
}

/// Device drawing as large as possible, but at most 300 pt high and as wide as the page; the size
/// follows the aspect ratio of the image.
pw.Widget _drawing(Uint8List png) {
  final pw.MemoryImage image;
  try {
    image = pw.MemoryImage(png);
  } on Object catch (e) {
    // Broken image: page without a drawing rather than no PDF at all.
    debugPrint('Gerätezeichnung unlesbar: $e');
    return pw.SizedBox();
  }
  const maxWidth = 595 - 72.0, maxHeight = 300.0;
  final aspect = (image.width ?? 1) / (image.height ?? 1);
  final width = aspect * maxHeight > maxWidth ? maxWidth : aspect * maxHeight;
  return pw.Center(
    child: pw.SizedBox(width: width, height: width / aspect, child: pw.Image(image)),
  );
}

/// Placeholder telegram to use [_range] with plain timestamps.
Telegram _stub(DateTime time) =>
    Telegram(time: time, source: 0, destination: 0, type: TelegramType.write, data: Uint8List(0), isSmall: false);

/// Cell padding of all tables.
pw.Widget pdfPad(pw.Widget child) =>
    pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: child);

/// Rows separated by hairlines, every second one sunken.
pw.BoxDecoration pdfRowDecoration(int i) => pw.BoxDecoration(
  color: i.isOdd ? _zebra : null,
  border: const pw.Border(
    bottom: pw.BorderSide(color: _line, width: _hairline),
  ),
);

/// Section heading as a label ("TOP-SENDER · 12"): capitals, letter-spaced, muted.
pw.Widget _kennung(String text, PdfFonts fonts, {int? count}) => pw.Text(
  (count == null ? text : '$text · $count').toUpperCase(),
  style: pdfStyle(PdfPt.kennung, font: fonts.semibold, color: pdfMuted, tracking: HzType.kennung.tracking),
);

/// Label above a block, with spacing below. As separate widgets in the page flow (not in a column):
/// only then does a long table break onto the next page instead of failing at the page boundary.
List<pw.Widget> pdfSection(String title, PdfFonts fonts, pw.Widget child, {int? count}) => [
  _kennung(title, fonts, count: count),
  pw.SizedBox(height: 4),
  child,
  pw.SizedBox(height: 16),
];

/// Small badge (radius 2) like HorizontBadge: word in state colour on a tint.
pw.Widget _tag(
  String text,
  PdfColor color,
  PdfColor tint,
  PdfFonts fonts, {
  HorizontStatus status = HorizontStatus.info,
}) => pw.Container(
  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
  decoration: pw.BoxDecoration(color: tint, borderRadius: _radius(_rTag)),
  child: _statusLine(text, status, color, fonts),
);

/// Status in the PDF as in the app: word, symbol and colour.
pw.Widget _statusLine(String text, HorizontStatus status, PdfColor color, PdfFonts fonts, {pw.Font? font}) => pw.Row(
  mainAxisSize: pw.MainAxisSize.min,
  children: [
    pw.Icon(pw.IconData(status.icon.codePoint), font: fonts.symbols, size: PdfPt.small + 1, color: color),
    pw.SizedBox(width: 2),
    pw.Flexible(
      child: pw.Text(
        text,
        style: pdfStyle(PdfPt.small, font: font ?? fonts.semibold, color: color),
      ),
    ),
  ],
);

/// Compact table with a label: four columns, zebra rows.
List<pw.Widget> _simpleTable(String title, PdfFonts fonts, List<List<String>> rows) => pdfSection(
  title,
  fonts,
  count: rows.length,
  pw.Table(
    columnWidths: const {
      0: pw.FixedColumnWidth(72),
      1: pw.FlexColumnWidth(3),
      2: pw.FixedColumnWidth(48),
      3: pw.FixedColumnWidth(92),
    },
    children: [
      for (final (i, r) in rows.indexed)
        pw.TableRow(
          decoration: pdfRowDecoration(i),
          children: [
            for (final (c, cell) in r.indexed)
              pdfPad(
                pw.Text(
                  cell,
                  textAlign: c >= 2 ? pw.TextAlign.right : pw.TextAlign.left,
                  // Column 1 is text (name), the others are values.
                  style: c == 1 ? pdfStyle(PdfPt.body) : pdfStyle(PdfPt.data, font: fonts.data),
                ),
              ),
          ],
        ),
    ],
  ),
);

/// Fonts from Horizont: Mona Sans for text, Literata for the title.
class PdfFonts {
  const PdfFonts({
    required this.regular,
    required this.medium,
    required this.semibold,
    required this.title,
    required this.symbols,
    required this.data,
  });
  final pw.Font regular;
  final pw.Font medium;
  final pw.Font semibold;
  final pw.Font title;
  final pw.Font symbols;

  /// Values, addresses and times.
  final pw.Font data;

  pw.ThemeData get theme => pw.ThemeData.withFont(base: regular, bold: semibold);

  static const _files = [
    'MonaSans-Regular.ttf',
    'MonaSans-Medium.ttf',
    'MonaSans-SemiBold.ttf',
    'Literata-Light.ttf',
    'MaterialSymbolsSharp-300.ttf',
    'MonaspaceArgon-Regular.ttf',
  ];

  /// Fonts from the app bundle, preloaded: a background isolate cannot read [rootBundle] and gets
  /// them passed in.
  static Map<String, ByteData>? preloaded;

  static Future<Map<String, ByteData>> bytes() async => {
    for (final file in _files) file: await rootBundle.load('packages/horizont/fonts/$file'),
  };

  static Future<PdfFonts> load() async {
    final data = preloaded ?? await bytes();
    pw.Font font(String file) => pw.Font.ttf(data[file]!);
    return PdfFonts(
      regular: font('MonaSans-Regular.ttf'),
      medium: font('MonaSans-Medium.ttf'),
      semibold: font('MonaSans-SemiBold.ttf'),
      title: font('Literata-Light.ttf'),
      symbols: font('MaterialSymbolsSharp-300.ttf'),
      data: font('MonaspaceArgon-Regular.ttf'),
    );
  }
}

/// Letterhead for the PDF currently being created; `null` = as usual. Module-wide like
/// [PdfFonts.preloaded] so that not every document type has to pass it through.
Letterhead? _letterhead;

/// Logo within [maxWidth] × [maxHeight], aspect ratio preserved. An unreadable image is dropped:
/// better a PDF without a logo than none at all.
pw.Widget? _logo(Uint8List? png, {required double maxWidth, required double maxHeight}) {
  if (png == null) return null;
  try {
    final image = pw.MemoryImage(png);
    final aspect = (image.width ?? 1) / (image.height ?? 1);
    final width = aspect * maxHeight > maxWidth ? maxWidth : aspect * maxHeight;
    return pw.SizedBox(
      width: width,
      height: width / aspect,
      child: pw.Image(image, fit: pw.BoxFit.contain),
    );
  } on Object catch (e) {
    debugPrint('Firmenlogo unlesbar: $e');
    return null;
  }
}

/// Header of the first page: logo on the left, company on the right.
pw.Widget _letterheadBlock(Letterhead head, PdfFonts fonts) {
  final small = pdfStyle(PdfPt.small, color: pdfMuted);
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 20),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        _logo(head.logoPng, maxWidth: 170, maxHeight: 54) ?? pw.SizedBox(),
        pw.SizedBox(width: 16),
        pw.Flexible(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                head.name,
                textAlign: pw.TextAlign.right,
                style: pdfStyle(PdfPt.body, font: fonts.semibold),
              ),
              for (final line in head.addressLines) pw.Text(line, textAlign: pw.TextAlign.right, style: small),
              if (head.contactLine.isNotEmpty) pw.Text(head.contactLine, textAlign: pw.TextAlign.right, style: small),
              if (head.registration.isNotEmpty) pw.Text(head.registration, textAlign: pw.TextAlign.right, style: small),
              if (head.technician.isNotEmpty)
                pw.Text(s.pdfTechnicianLine(head.technician), textAlign: pw.TextAlign.right, style: small),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Shared page frame: title, header from page 2, footer with page number. With a letterhead
/// ([_letterhead]): company above the title, logo and company name in the header of following
/// pages, contact line in the footer.
Future<Uint8List> pdfDocument({
  required String title,
  String? subtitle,
  String? project,
  required PdfFonts fonts,
  required List<pw.Widget> content,
}) {
  final now = DateTime.now();
  final head = _letterhead;
  final doc = pw.Document(title: title, author: head?.author ?? 'Busclear', creator: 'Busclear');
  doc.addPage(
    pw.MultiPage(
      // Long exports (telegrams, findings) need more than the default 20 pages; beyond that the
      // package aborts with an exception.
      maxPages: 2000,
      theme: fonts.theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 32),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 12),
              padding: const pw.EdgeInsets.only(bottom: 4),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: _line, width: _hairline),
                ),
              ),
              child: pw.Row(
                children: [
                  if (head != null) ...[
                    if (_logo(head.logoPng, maxWidth: 60, maxHeight: 14) case final logo?) ...[
                      logo,
                      pw.SizedBox(width: 6),
                    ],
                    pw.Text('${head.name}$metaSeparator', style: pdfStyle(PdfPt.small, color: pdfMuted)),
                  ],
                  pw.Flexible(
                    child: pw.Text(title, style: pdfStyle(PdfPt.small, font: fonts.medium), maxLines: 1),
                  ),
                  if (project != null)
                    pw.Flexible(
                      child: pw.Text(
                        '$metaSeparator$project',
                        style: pdfStyle(PdfPt.small, color: pdfMuted),
                        maxLines: 1,
                      ),
                    ),
                ],
              ),
            ),
      footer: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 12),
        padding: const pw.EdgeInsets.only(top: 4),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(color: _line, width: _hairline),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Flexible(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (head != null && head.contactLine.isNotEmpty)
                    pw.Text(
                      '${head.name}$metaSeparator${head.contactLine}',
                      style: pdfStyle(PdfPt.small, color: pdfMuted),
                    ),
                  // "Erstellt mit Busclear" (created with Busclear) stays, even under the
                  // letterhead.
                  pw.Text(
                    s.pdfFooterCreated(pdfDate(now), _clock(now).substring(0, 5)),
                    style: pdfStyle(head == null ? PdfPt.small : PdfPt.small * 0.85, color: pdfMuted),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Text(s.pdfPage(context.pageNumber, context.pagesCount), style: pdfStyle(PdfPt.small, color: pdfMuted)),
          ],
        ),
      ),
      build: (context) => [
        if (head != null) _letterheadBlock(head, fonts),
        // Label above the title (project), then the title in Literata.
        if (project != null) ...[_kennung(project, fonts), pw.SizedBox(height: 4)],
        pw.Text(title, style: pdfStyle(PdfPt.title, font: fonts.title)),
        if (subtitle != null) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            subtitle,
            style: pdfStyle(PdfPt.data, font: fonts.data, color: pdfMuted),
          ),
        ],
        pw.SizedBox(height: 16),
        ...content,
      ],
    ),
  );
  return doc.save();
}

String _range(List<Telegram> items) {
  final first = items.first.time;
  final last = items.last.time;
  return pdfDate(first) == pdfDate(last)
      ? '${pdfDate(first)}, ${_clock(first)} – ${_clock(last)}'
      : '${pdfDate(first)} ${_clock(first)} – ${pdfDate(last)} ${_clock(last)}';
}

/// Summary as a box with a hairline: (label, value, width).
pw.Widget pdfSummary(List<(String, String, int)> cells, PdfFonts fonts) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _line, width: _hairline),
      borderRadius: _radius(_rBox),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final (i, (label, value, flex)) in cells.indexed) ...[
          if (i > 0) pw.SizedBox(width: 12),
          pw.Expanded(
            flex: flex,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _kennung(label, fonts),
                pw.SizedBox(height: 4),
                pw.Text(value, style: pdfStyle(PdfPt.data, font: fonts.data)),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

pw.Widget pdfNote(String note, PdfFonts fonts, {String? label}) => pw.Container(
  width: double.infinity,
  padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  decoration: pw.BoxDecoration(
    borderRadius: _radius(_rBox),
    border: pw.Border.all(color: _line, width: _hairline),
  ),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _kennung(label ?? s.pdfNote, fonts),
      pw.SizedBox(height: 4),
      pw.Text(note, style: pdfStyle(PdfPt.body)),
    ],
  ),
);

pw.Widget _table(List<Telegram> items, CatalogStore store, PdfFonts fonts, {required bool showDate}) {
  final small = pdfStyle(PdfPt.small, color: pdfMuted);
  final smallData = pdfStyle(PdfPt.small, font: fonts.data, color: pdfMuted);
  final body = pdfStyle(PdfPt.body);
  final data = pdfStyle(PdfPt.data, font: fonts.data);
  final strong = pdfStyle(PdfPt.body, font: fonts.medium);

  pw.Widget twoLines(String top, String? bottom, {required pw.TextStyle topStyle, pw.TextStyle? bottomStyle}) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(top, style: topStyle),
          if (bottom != null && bottom.isNotEmpty) pw.Text(bottom, style: bottomStyle ?? small),
        ],
      );

  return pw.Table(
    columnWidths: const {
      0: pw.FixedColumnWidth(68),
      1: pw.FixedColumnWidth(28),
      2: pw.FlexColumnWidth(3),
      3: pw.FlexColumnWidth(2.2),
      4: pw.FlexColumnWidth(2),
    },
    children: [
      // Header row: sunken with a hairline, column names as labels.
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(
          color: _zebra,
          border: pw.Border(
            bottom: pw.BorderSide(color: _line, width: _hairline),
          ),
        ),
        children: [
          for (final h in [s.columnTime, s.columnType, s.sendGroupAddress, s.columnSender, s.columnValue])
            pdfPad(_kennung(h, fonts)),
        ],
      ),
      for (final t in items)
        if (activeAlarm(t) case final alarm)
          pw.TableRow(
            // Alarm/fault: critical tint, 2 pt line on the left and the word next to the value.
            decoration: pw.BoxDecoration(
              color: alarm != null ? _criticalTint : null,
              border: pw.Border(
                left: alarm != null ? pw.BorderSide(color: _critical, width: _mark) : pw.BorderSide.none,
                bottom: const pw.BorderSide(color: _line, width: _hairline),
              ),
            ),
            children: [
              pdfPad(
                twoLines(_clock(t.time), showDate ? pdfDate(t.time) : null, topStyle: data, bottomStyle: smallData),
              ),
              pdfPad(_typeBadge(t, fonts)),
              pdfPad(
                twoLines(
                  store.infoOf(t)?.name ?? t.destinationText,
                  store.infoOf(t) == null
                      ? null
                      : [t.destinationText, store.infoOf(t)!.path].whereType<String>().join(' · '),
                  topStyle: store.infoOf(t) == null ? data : strong,
                ),
              ),
              pdfPad(
                t.outgoing
                    ? twoLines(s.rowSent, s.pdfThisDevice, topStyle: body)
                    : twoLines(t.sourceText, store.deviceOf(t)?.name, topStyle: data),
              ),
              pdfPad(
                twoLines(
                  alarm == null
                      ? store.value(t)
                      : '${store.value(t)} · ${alarm == AlarmKind.alarm ? s.alarmLabel : s.faultLabel}',
                  t.type == TelegramType.read
                      ? null
                      : [
                          if (store.dptFor(t) case final dpt?) 'DPT $dpt',
                          t.isSmall ? '${t.data[0]}' : hex(t.data),
                        ].join(' · '),
                  topStyle: alarm != null ? data.copyWith(font: fonts.semibold, color: _critical) : data,
                  bottomStyle: smallData,
                ),
              ),
            ],
          ),
    ],
  );
}

pw.Widget _legend(PdfFonts fonts) {
  pw.Widget entry(TelegramType type, String label, {bool outgoing = false}) => pw.Padding(
    padding: const pw.EdgeInsets.only(right: 16),
    child: pw.Row(
      children: [
        _badge(type, outgoing, fonts, size: 11),
        pw.SizedBox(width: 4),
        pw.Text(label, style: pdfStyle(PdfPt.small, color: pdfMuted)),
      ],
    ),
  );
  return pw.Row(
    children: [
      for (final type in Palette.order) entry(type, Palette.label(type)),
      entry(TelegramType.write, s.legendOutlinedSent, outgoing: true),
    ],
  );
}

pw.Widget _typeBadge(Telegram t, PdfFonts fonts) => _badge(t.type, t.outgoing, fonts);

/// Symbol of the telegram type in its colour on a tint, radius 2; sent telegrams only outlined.
pw.Widget _badge(TelegramType type, bool outgoing, PdfFonts fonts, {double size = 14}) {
  final color = _pdf(Palette.forType(type));
  return pw.Container(
    width: size,
    height: size,
    alignment: pw.Alignment.center,
    decoration: pw.BoxDecoration(
      color: outgoing ? null : _pdf(Palette.tintForType(type)),
      border: outgoing ? pw.Border.all(color: color, width: Lines.hairline) : null,
      borderRadius: _radius(_rTag),
    ),
    child: pw.Icon(pw.IconData(Palette.icon(type).codePoint), font: fonts.symbols, size: size * 0.7, color: color),
  );
}

String _two(int v) => v.toString().padLeft(2, '0');
String pdfDate(DateTime t) => s.localeName.startsWith('de')
    ? '${_two(t.day)}.${_two(t.month)}.${t.year}'
    : '${t.year}-${_two(t.month)}-${_two(t.day)}';
String _clock(DateTime t) =>
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';

/// What should be produced as a PDF – data only, no functions or widgets, so it can be built in a
/// background isolate.
sealed class PdfJob {
  const PdfJob();
}

class TelegramPdf extends PdfJob {
  const TelegramPdf(this.telegrams, {this.gateway, this.title, this.note, this.simple = false});
  final List<Telegram> telegrams;
  final String? gateway;
  final String? title;
  final String? note;
  final bool simple;
}

/// History of a group address; the app renders the chart image ([chart]) beforehand.
class ChartPdf extends PdfJob {
  const ChartPdf({
    required this.address,
    required this.telegrams,
    required this.kind,
    this.dpt,
    this.chart,
    this.stats,
    this.gateway,
  });
  final int address;
  final List<Telegram> telegrams;
  final ChartKind kind;
  final Dpt? dpt;
  final Uint8List? chart;
  final ({double min, double max, double avg})? stats;
  final String? gateway;
}

class StatisticsPdf extends PdfJob {
  const StatisticsPdf(this.stats, {this.gateway});
  final BusStatistics stats;
  final String? gateway;
}

class CommissioningPdf extends PdfJob {
  CommissioningPdf(Commissioning c, {this.gateway}) : started = c.started, items = [...c.items.values];
  final DateTime? started;
  final List<CheckItem> items;
  final String? gateway;
}

class AcceptancePdf extends PdfJob {
  const AcceptancePdf(this.acceptance, {this.photos = const {}});
  final Acceptance acceptance;

  /// Images of the defects by photo ID; the app reads them beforehand.
  final Map<String, Uint8List> photos;
}

class HealthPdf extends PdfJob {
  const HealthPdf(this.run, {this.gateway});
  final HealthRun run;
  final String? gateway;
}

/// Tasks for the ETS; the app renders the drawings ([drawings], PNG per device) beforehand.
class EtsTasksPdf extends PdfJob {
  const EtsTasksPdf(this.tasks, {this.drawings = const {}});
  final EtsTasks tasks;
  final Map<int, Uint8List> drawings;
}

/// Service report; the app reads the screenshots ([shots]) beforehand.
class ServiceReportPdf extends PdfJob {
  const ServiceReportPdf(this.report, {this.shots = const {}, this.photos = const {}});
  final ServiceReport report;
  final Map<String, Uint8List> shots;

  /// Selected photos of the photo documentation.
  final Map<String, Uint8List> photos;
}

/// Label sheet for the distribution board.
class DeviceLabelsPdf extends PdfJob {
  const DeviceLabelsPdf(this.labels);
  final List<DeviceLabel> labels;
}

class ResidentManualPdf extends PdfJob {
  const ResidentManualPdf(this.manual);
  final ResidentManual manual;
}

/// Installation report of box and add-on for the customer.
class PlantReportPdf extends PdfJob {
  const PlantReportPdf(this.report, {this.customer = '', this.site = '', this.project, this.nextMaintenance});
  final PlantReport report;
  final String customer;
  final String site;
  final String? project;
  final DateTime? nextMaintenance;
}

/// Job of an extension (Bauherren-Paket, company edition) that builds its PDF itself with the
/// building blocks of this file.
abstract class ExtensionPdfJob extends PdfJob {
  const ExtensionPdfJob();

  Future<Uint8List> build();
}

/// Creates the PDF of a job (in the calling isolate), with [letterhead] as letterhead if set.
Future<Uint8List> buildPdf(PdfJob job, {Letterhead? letterhead}) async {
  _letterhead = letterhead;
  try {
    return await _buildJob(job);
  } finally {
    _letterhead = null;
  }
}

Future<Uint8List> _buildJob(PdfJob job) {
  final store = CatalogStore.instance;
  return switch (job) {
    TelegramPdf j => buildTelegramPdf(
      j.telegrams,
      store: store,
      gateway: j.gateway,
      title: j.title,
      note: j.note,
      simple: j.simple,
    ),
    ChartPdf j => buildChartPdf(
      address: j.address,
      telegrams: j.telegrams,
      store: store,
      chart: j.chart,
      stats: j.stats,
      format: (v) => chartLabel(j.dpt, j.kind, v),
      gateway: j.gateway,
    ),
    StatisticsPdf j => buildStatisticsPdf(j.stats, store: store, gateway: j.gateway),
    CommissioningPdf j => buildCommissioningPdf((started: j.started, items: j.items), store: store, gateway: j.gateway),
    HealthPdf j => buildHealthPdf(j.run, store: store, gateway: j.gateway),
    AcceptancePdf j => buildAcceptancePdf(j.acceptance, photos: j.photos),
    EtsTasksPdf j => buildEtsTasksPdf(j.tasks, store: store, drawings: j.drawings),
    ServiceReportPdf j => buildServiceReportPdf(j.report, shots: j.shots, photos: j.photos),
    DeviceLabelsPdf j => buildDeviceLabelsPdf(j.labels),
    ResidentManualPdf j => buildResidentManualPdf(j.manual),
    PlantReportPdf j => buildPlantReportPdf(
      j.report,
      customer: j.customer,
      site: j.site,
      project: j.project,
      nextMaintenance: j.nextMaintenance,
    ),
    ExtensionPdfJob j => j.build(),
  };
}

/// Creates the PDF in a background isolate so the UI stays responsive even with thousands of rows.
/// Language, project, changed datapoint types and fonts are passed along. In the browser (no
/// isolates) in the same one.
Future<Uint8List> buildPdfInBackground(PdfJob job) async {
  // The letterhead (with logo bytes) is passed as data: the isolate knows no stores.
  final head = CompanyStore.instance.letterhead;
  if (kIsWeb) return buildPdf(job, letterhead: head);
  final store = CatalogStore.instance;
  // Acceptance report and service report have their own language (the customer's).
  final locale = switch (job) {
    AcceptancePdf j => Locale(j.acceptance.language),
    ServiceReportPdf j => Locale(j.report.language),
    ResidentManualPdf j => Locale(j.manual.language),
    _ => LocaleController.instance.locale,
  };
  // Telegrams of an older project state keep its names: the isolate gets those states too.
  final past = job is TelegramPdf ? store.pastFor(job.telegrams) : null;
  return Isolate.run(_pdfTask(job, await PdfFonts.bytes(), locale, store.catalog, Map.of(store.overrides), head, past));
}

/// A separate function so the task only captures its arguments (nothing from the UI that cannot be
/// sent to an isolate).
Future<Uint8List> Function() _pdfTask(
  PdfJob job,
  Map<String, ByteData> fonts,
  Locale locale,
  GroupCatalog catalog,
  Map<int, Dpt> overrides,
  Letterhead? letterhead,
  ({List<int?> from, List<GroupCatalog> catalogs})? past,
) => () {
  PdfFonts.preloaded = fonts;
  LocaleController.instance.debugSetLocale(locale);
  CatalogStore.instance
    ..catalog = catalog
    ..overrides = overrides
    ..adoptPast(past);
  return buildPdf(job, letterhead: letterhead);
};
