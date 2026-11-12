import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../catalog_store.dart';
import '../knx/dali_text.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/dali.dart';
import '../model/dali_labels.dart';
import '../model/dali_log.dart';
import '../theme/palette.dart';
import 'pdf_export.dart';
import 'telegram_files.dart';

/// A luminaire of the emergency lighting log, with everything as text: built in the app, printed
/// in the background.
@immutable
class EmergencyLogLuminaire {
  const EmergencyLogLuminaire({
    required this.name,
    required this.where,
    required this.function,
    required this.duration,
    required this.note,
    required this.attention,
  });

  final String name;

  /// "Adr. 18 · Treppenhaus · 1.1.40 EG › Flur".
  final String where;

  /// Last function and duration test in words, "—" without a result.
  final String function;
  final String duration;

  /// What needs a look, with its reason ("Funktionstest überfällig: kein neues Ergebnis seit
  /// 41 Tagen"), or empty.
  final String note;
  final bool attention;
}

/// One entry of the log as a row: the same columns in PDF and CSV.
@immutable
class EmergencyLogRow {
  const EmergencyLogRow({
    required this.time,
    required this.luminaire,
    required this.room,
    required this.gateway,
    required this.address,
    required this.group,
    required this.kind,
    required this.start,
    required this.result,
    required this.reasons,
    required this.minutes,
    required this.charge,
    required this.raw,
    required this.failed,
    this.source = '',
    this.note = '',
    this.first = false,
    this.foreign = false,
  });

  /// When the result arrived (not when the test ran).
  final DateTime time;
  final String luminaire;
  final String room;
  final String gateway;
  final String address;
  final String group;
  final String kind;
  final String start;
  final String result;
  final String reasons;
  final String minutes;
  final String charge;
  final String raw;
  final bool failed;

  /// Sender of the telegram.
  final String source;

  /// "erstmals gesehen, Testzeitpunkt unbekannt", "fremder Absender 1.1.99", "Data Secure".
  final String note;
  final bool first;
  final bool foreign;
}

/// The emergency lighting log of a period, ready for PDF and CSV.
@immutable
class EmergencyLogData {
  const EmergencyLogData({
    required this.from,
    required this.to,
    required this.functionDays,
    required this.durationDays,
    required this.luminaires,
    required this.rows,
    this.gaps = const [],
    this.limitedYears = const {},
  });

  final DateTime? from;
  final DateTime to;
  final int functionDays;
  final int durationDays;
  final List<EmergencyLogLuminaire> luminaires;

  /// All entries of the period, oldest first.
  final List<EmergencyLogRow> rows;

  /// Days without a recording: results from then are missing.
  final List<({DateTime from, DateTime to})> gaps;

  /// Years whose file reached its limit or was read in part: entries may be missing.
  final Set<int> limitedYears;

  /// Collects the log of the active installation from the stores, in the app's language.
  factory EmergencyLogData.collect({
    required DateTime? from,
    required DateTime to,
    List<({DateTime from, DateTime to})> gaps = const [],
  }) {
    final dali = DaliStore.instance;
    final log = DaliTestLog.instance;
    String test(EmergencyTest? e) => e == null
        ? '—'
        : [
            '${pdfDate(e.time)} ${daliResultText(e.result)}',
            for (final r in e.reasons) daliReasonText(r),
            if (e.minutes case final m?) daliMinutesText(m),
            if (e.first) s.daliFirstSeen,
          ].join(', ');
    String gatewayText(int? pa) {
      if (pa == null) return '';
      final location = dali.gateway(pa)?.location;
      return [formatIndividual(pa), ?location].join(' ');
    }

    return EmergencyLogData(
      from: from,
      to: to,
      functionDays: dali.settings.functionDays,
      durationDays: dali.settings.durationDays,
      gaps: gaps,
      limitedYears: {...log.limitedYears},
      luminaires: [
        for (final row in log.overview(to))
          EmergencyLogLuminaire(
            name: row.gear == null ? s.daliEmergencyAt(formatGroup(row.group)) : daliGearLabel(row.gear!),
            where: [
              if (row.gear?.address case final a?) s.daliAddressShort(a),
              ?row.gear?.room,
              gatewayText(row.gateway),
            ].where((p) => p.isNotEmpty).join(' · '),
            function: test(row.lastFunction),
            duration: test(row.lastDuration),
            note: daliOverviewNotes(row, to).join('; '),
            attention: row.failed || row.overdue,
          ),
      ],
      rows: [
        for (final e in log.between(from, to))
          () {
            final gear =
                dali.gearOfResult(e.group) ??
                (e.gateway != null && e.address != null ? dali.gear(e.gateway!, e.address!) : null);
            return EmergencyLogRow(
              time: e.time,
              luminaire: gear == null ? s.daliEmergencyAt(formatGroup(e.group)) : daliGearLabel(gear),
              room: gear?.room ?? '',
              gateway: gatewayText(e.gateway ?? gear?.gateway),
              address: '${e.address ?? gear?.address ?? ''}',
              group: formatGroup(e.group),
              kind: daliTestKindText(e.kind),
              start: e.start == ConverterTestStart.unknown ? '' : daliStartText(e.start),
              result: daliResultText(e.result),
              reasons: e.reasons.map(daliReasonText).join(', '),
              minutes: e.minutes == null ? '' : '${e.minutes}',
              charge: e.charge == null ? '' : daliChargeText(e.charge!),
              raw: e.raw,
              failed: e.result == EmergencyResult.failed && !e.foreign,
              source: e.source == null ? '' : formatIndividual(e.source!),
              note: daliEntryNotes(e).join('; '),
              first: e.first,
              foreign: e.foreign,
            );
          }(),
      ],
    );
  }
}

/// What needs a look at a luminaire, each with its reason.
List<String> daliOverviewNotes(EmergencyOverview row, DateTime now) {
  String overdue(String kind, EmergencyTest? last) =>
      s.daliOverdueReason(kind, last == null ? 0 : now.difference(last.time).inDays);
  return [
    if (row.failed) s.daliTestFailedChip,
    if (row.functionDue == TestDue.overdue) overdue(s.daliTestFunction, row.lastFunction),
    if (row.durationDue == TestDue.overdue) overdue(s.daliTestDuration, row.lastDuration),
    if (row.functionDue == TestDue.unknownAge || row.durationDue == TestDue.unknownAge) s.daliFirstSeen,
    if (row.foreign > 0) s.daliForeignCount(row.foreign),
  ];
}

/// What to know about one entry: first seen, from another sender, Data Secure.
List<String> daliEntryNotes(EmergencyTest e) => [
  if (e.first) s.daliFirstSeen,
  if (e.foreign) s.daliForeignSender(e.source == null ? '—' : formatIndividual(e.source!)),
  if (e.secure) s.daliDataSecure,
];

/// The log as CSV (RFC 4180, with header), one line per entry, the same columns as the PDF.
String buildEmergencyCsv(EmergencyLogData data) {
  const cell = csvCell;
  final lines = [
    [
      s.daliColTime,
      s.daliColLuminaire,
      s.daliFieldRoom,
      s.daliGateway,
      s.daliRowAddress,
      s.daliColGroupAddress,
      s.daliColTest,
      s.daliColStart,
      s.daliColResult,
      s.daliColReasons,
      s.daliColMinutes,
      s.daliColCharge,
      s.daliRaw,
      s.daliColSource,
      s.daliColNote,
    ].map(cell).join(','),
    for (final r in data.rows)
      [
        isoWithOffset(r.time),
        r.luminaire,
        r.room,
        r.gateway,
        r.address,
        r.group,
        r.kind,
        r.start,
        r.result,
        r.reasons,
        r.minutes,
        r.charge,
        r.raw,
        r.source,
        r.note,
      ].map(cell).join(','),
  ];
  return '${lines.join('\r\n')}\r\n';
}

/// The emergency lighting log as a PDF: installation and period, one row per luminaire with its
/// last function and duration test, then every entry in order, and a field for the inspector's
/// name and signature.
class EmergencyLogPdf extends ExtensionPdfJob {
  const EmergencyLogPdf(this.data);

  final EmergencyLogData data;

  @override
  Future<Uint8List> build() async {
    final fonts = await PdfFonts.load();
    final critical = PdfColor.fromInt(Palette.of(false).critical.toARGB32());
    pw.Widget cell(String text, {pw.Font? font, PdfColor color = pdfInk, bool data = false, double? size}) => pdfPad(
      pw.Text(
        text,
        style: data
            ? pdfStyle(size ?? PdfPt.data, font: font ?? fonts.data, color: color)
            : pdfStyle(size ?? PdfPt.body, font: font, color: color),
      ),
    );
    pw.Widget head(String text) => pdfPad(
      pw.Text(
        text,
        style: pdfStyle(PdfPt.small, font: fonts.semibold, color: pdfMuted),
      ),
    );
    final d = data;
    final period = d.from == null ? s.daliPeriodUntil(pdfDate(d.to)) : '${pdfDate(d.from!)} – ${pdfDate(d.to)}';
    return pdfDocument(
      title: s.daliLogTitle,
      project: CatalogStore.instance.catalog.projectName,
      fonts: fonts,
      content: [
        pdfSummary([
          (s.pdfPeriod, period, 3),
          (s.daliEmergencyLuminaires, '${d.luminaires.length}', 2),
          (s.daliLogEntries, '${d.rows.length}', 2),
          (s.daliIntervals, s.daliIntervalsText(_interval(d.functionDays), _interval(d.durationDays)), 4),
        ], fonts),
        pw.SizedBox(height: 12),
        pdfNote('${s.daliLogLimit}\n${s.daliLogTrust}\n${s.daliLogRepeats}', fonts),
        for (final year in d.limitedYears.toList()..sort()) ...[
          pw.SizedBox(height: 6),
          pw.Text(
            s.daliLogLimited('$year'),
            style: pdfStyle(PdfPt.small, font: fonts.semibold, color: critical),
          ),
        ],
        for (final gap in d.gaps.take(20)) ...[
          pw.SizedBox(height: 6),
          pw.Text(s.daliLogGap(pdfDate(gap.from), pdfDate(gap.to)), style: pdfStyle(PdfPt.small, color: pdfMuted)),
        ],
        pw.SizedBox(height: 16),
        ...pdfSection(
          s.daliEmergencyLuminaires,
          fonts,
          count: d.luminaires.length,
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(2.6),
              2: pw.FlexColumnWidth(2.6),
              3: pw.FlexColumnWidth(2.4),
            },
            children: [
              pw.TableRow(
                children: [
                  head(s.daliColLuminaire),
                  head(s.daliTestFunction),
                  head(s.daliTestDuration),
                  head(s.daliColNote),
                ],
              ),
              for (final (i, l) in d.luminaires.indexed)
                pw.TableRow(
                  decoration: pdfRowDecoration(i),
                  children: [
                    pdfPad(
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(l.name, style: pdfStyle(PdfPt.body, font: fonts.medium)),
                          if (l.where.isNotEmpty) pw.Text(l.where, style: pdfStyle(PdfPt.small, color: pdfMuted)),
                        ],
                      ),
                    ),
                    cell(l.function),
                    cell(l.duration),
                    cell(l.note, font: fonts.semibold, color: l.attention ? critical : pdfInk, size: PdfPt.small),
                  ],
                ),
            ],
          ),
        ),
        if (d.rows.isNotEmpty) ...[
          ...pdfSection(
            s.daliLogEntries,
            fonts,
            count: d.rows.length,
            pw.Table(
              columnWidths: const {
                0: pw.FixedColumnWidth(70),
                1: pw.FlexColumnWidth(3),
                2: pw.FlexColumnWidth(1.8),
                3: pw.FlexColumnWidth(2.6),
                4: pw.FixedColumnWidth(84),
              },
              children: [
                pw.TableRow(
                  children: [
                    head('${s.daliColTime} ¹'),
                    head(s.daliColLuminaire),
                    head(s.daliColTest),
                    head(s.daliColResult),
                    head(s.daliRaw),
                  ],
                ),
                for (final (i, r) in d.rows.indexed)
                  pw.TableRow(
                    decoration: pdfRowDecoration(i),
                    children: [
                      cell('${pdfDate(r.time)} ${_two(r.time.hour)}:${_two(r.time.minute)}', data: true),
                      cell(
                        [
                          r.luminaire,
                          if (r.address.isNotEmpty) s.daliAddressShort(int.parse(r.address)),
                          if (r.room.isNotEmpty) r.room,
                        ].join(' · '),
                      ),
                      cell([r.kind, if (r.start.isNotEmpty) r.start].join(', ')),
                      cell(
                        [
                          r.result,
                          if (r.reasons.isNotEmpty) r.reasons,
                          if (r.minutes.isNotEmpty) s.daliMinutes(int.parse(r.minutes)),
                          if (r.charge.isNotEmpty) r.charge,
                          if (r.note.isNotEmpty) r.note,
                        ].join(', '),
                        font: r.failed ? fonts.semibold : null,
                        color: r.failed ? critical : (r.foreign ? pdfMuted : pdfInk),
                      ),
                      cell(r.raw, data: true, color: pdfMuted, size: PdfPt.small),
                    ],
                  ),
              ],
            ),
          ),
          pw.Text('¹ ${s.daliTimeFootnote}', style: pdfStyle(PdfPt.small, color: pdfMuted)),
        ] else
          pw.Text(s.daliLogEmpty, style: pdfStyle(PdfPt.body, color: pdfMuted)),
        pw.SizedBox(height: 28),
        // Inspector and signature: two lines to fill in by hand.
        pw.Row(
          children: [
            for (final label in [s.daliInspector, s.daliSignature]) ...[
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      height: 28,
                      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.6))),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(label, style: pdfStyle(PdfPt.small, color: pdfMuted)),
                  ],
                ),
              ),
              if (label == s.daliInspector) pw.SizedBox(width: 24),
            ],
          ],
        ),
      ],
    );
  }
}

/// A test interval in words: "30 Tage", "12 Monate".
String _interval(int days) => days >= 730
    ? s.daliYears(days ~/ 365)
    : days >= 180
    ? s.daliMonths((days / 30.4).round())
    : s.daliDays(days);

String _two(int v) => v.toString().padLeft(2, '0');
