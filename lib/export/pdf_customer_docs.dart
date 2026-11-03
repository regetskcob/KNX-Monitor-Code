part of 'pdf_export.dart';

/// How a point counts for the customer: word and colour (in the PDF always both).
(String, PdfColor) _serviceLevel(ServiceLevel level) => switch (level) {
  ServiceLevel.fix => (s.srLevelFix, _critical),
  ServiceLevel.watch => (s.srLevelWatch, _warning),
  ServiceLevel.info => (s.srLevelInfo, _info),
};

/// Table of notes: rating in words, title, explanation.
pw.Widget _serviceLines(List<ServiceLine> lines, PdfFonts fonts) => pw.Table(
  columnWidths: const {0: pw.FixedColumnWidth(64), 1: pw.FlexColumnWidth(5)},
  children: [
    for (final (i, l) in lines.indexed)
      pw.TableRow(
        decoration: pdfRowDecoration(i),
        children: [
          pdfPad(
            pw.Text(
              _serviceLevel(l.level).$1,
              style: pdfStyle(PdfPt.body, font: fonts.semibold, color: _serviceLevel(l.level).$2),
            ),
          ),
          pdfPad(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(l.title, style: pdfStyle(PdfPt.body)),
                if (l.detail.isNotEmpty) pw.Text(l.detail, style: pdfStyle(PdfPt.small, color: pdfMuted)),
              ],
            ),
          ),
        ],
      ),
  ],
);

/// Screenshot of a comment, small enough for several per page.
pw.Widget? _commentShot(Uint8List jpeg) {
  try {
    final image = pw.MemoryImage(jpeg);
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4, right: 8),
      child: pw.ConstrainedBox(
        constraints: const pw.BoxConstraints(maxWidth: 240, maxHeight: 160),
        child: pw.Image(image, fit: pw.BoxFit.contain),
      ),
    );
  } on Object catch (e) {
    debugPrint('Screenshot unlesbar: $e');
    return null;
  }
}

/// Service report for laypeople: the result in one sentence at the top, then occasion, observation,
/// work done and recommendation; measurement, comments and notes as evidence after that, and at the
/// end the signature and the checksum.
Future<Uint8List> buildServiceReportPdf(
  ServiceReport r, {
  Map<String, Uint8List> shots = const {},
  Map<String, Uint8List> photos = const {},
}) async {
  final fonts = await PdfFonts.load();
  String when(DateTime t) => '${pdfDate(t)} ${_clock(t).substring(0, 5)}';
  final summary = r.attention == 0 ? s.srResultGood : s.srResultAttention(r.attention);
  return pdfDocument(
    title: s.srPdfTitle,
    subtitle: r.customer.isEmpty ? null : r.customer,
    project: r.project,
    fonts: fonts,
    content: [
      pdfSummary([
        (s.acceptCustomer, r.customer.isEmpty ? '—' : r.customer, 2),
        (s.acceptSite, r.site.isEmpty ? '—' : r.site, 3),
        (s.commDate, when(r.created), 2),
        (s.acceptTechnician, r.technician.isEmpty ? '—' : r.technician, 2),
      ], fonts),
      pw.SizedBox(height: 12),
      pw.Text(
        summary,
        style: pdfStyle(PdfPt.body, font: fonts.semibold, color: r.attention == 0 ? _positive : _warning),
      ),
      pw.SizedBox(height: 12),
      for (final (label, text) in [
        (s.srOccasion, r.occasion),
        (s.srObserved, r.observed),
        (s.srDone, r.done),
        (s.srRecommendation, r.recommendation),
      ])
        if (text.isNotEmpty) ...[pdfNote(text, fonts, label: label), pw.SizedBox(height: 8)],
      pw.SizedBox(height: 8),
      if (r.recordingStart != null && r.recordingEnd != null) ...[
        ...pdfSection(
          s.srMeasurement,
          fonts,
          pw.Text(
            s.srMeasurementText(
              when(r.recordingStart!),
              r.recordingEnd!.difference(r.recordingStart!).inMinutes,
              r.telegrams,
            ),
            style: pdfStyle(PdfPt.body),
          ),
        ),
      ],
      if (r.comments.isNotEmpty)
        ...pdfSection(
          s.srComments,
          fonts,
          count: r.comments.length,
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final c in r.comments)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 8),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        when(c.time),
                        style: pdfStyle(PdfPt.small, color: pdfMuted, font: fonts.data),
                      ),
                      if (c.note.isNotEmpty) pw.Text(c.note, style: pdfStyle(PdfPt.body)),
                      pw.Wrap(
                        children: [
                          for (final id in c.shots)
                            if (shots[id] case final jpeg?) ?_commentShot(jpeg),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      if (r.photos.isNotEmpty)
        ...pdfSection(
          s.srPhotos,
          fonts,
          count: r.photos.length,
          pw.Wrap(
            children: [
              for (final p in r.photos)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 8, right: 8),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (photos[p.id] case final jpeg?) ?_commentShot(jpeg),
                      if (p.caption.isNotEmpty) pw.Text(p.caption, style: pdfStyle(PdfPt.small, color: pdfMuted)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      if (r.findings.isNotEmpty)
        ...pdfSection(s.srFindings, fonts, count: r.findings.length, _serviceLines(r.findings, fonts)),
      if (r.healthTime != null)
        ...pdfSection(
          s.srHealth(when(r.healthTime!)),
          fonts,
          count: r.health.length,
          r.health.isEmpty
              ? pw.Text(
                  s.healthAllGood,
                  style: pdfStyle(PdfPt.body, font: fonts.semibold, color: _positive),
                )
              : _serviceLines(r.health, fonts),
        ),
      pw.Inseparable(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (!r.signature.isEmpty) ...[
              pw.Text(s.srConfirmation, style: pdfStyle(PdfPt.body)),
              pw.SizedBox(height: 12),
              pw.SizedBox(
                width: 220,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _signature(r.signature),
                    pw.Container(height: _hairline, color: pdfInk),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      r.signer.isEmpty ? s.acceptRoleCustomer : '${s.acceptRoleCustomer}: ${r.signer}',
                      style: pdfStyle(PdfPt.small, color: pdfMuted),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
            ],
            pw.Text(
              s.acceptChecksum(r.checksum),
              style: pdfStyle(PdfPt.small, color: pdfMuted, font: fonts.data),
            ),
          ],
        ),
      ),
    ],
  );
}

String _manualKind(ManualKind kind) => switch (kind) {
  ManualKind.onOff => s.manualKindOnOff,
  ManualKind.dim => s.manualKindDim,
  ManualKind.percent => s.manualKindPercent,
  ManualKind.blinds => s.manualKindBlinds,
  ManualKind.openClose => s.manualKindOpenClose,
  ManualKind.scene => s.manualKindScene,
  ManualKind.temperature => s.manualKindTemperature,
  ManualKind.setpoint => s.manualKindSetpoint,
  ManualKind.measure => s.manualKindMeasure,
  ManualKind.other => s.manualKindOther,
};

/// Resident handbook: introduction, the functions of each room in everyday words, and at the end
/// what to do in case of a fault and who can help.
/// Customer file as PDF, in every tier: the data belongs to the business.
Future<Uint8List> buildCustomerRecordPdf(String installation, CustomerRecord r, List<Visit> visits) async {
  final fonts = await PdfFonts.load();
  final lines = [
    r.customer,
    r.site,
    r.contact,
    r.phone,
    r.email,
    r.orderNumber,
    r.notes,
  ].whereType<String>().where((t) => t.trim().isNotEmpty);
  return pdfDocument(
    title: s.customerTitle,
    subtitle: r.customer.isEmpty ? installation : r.customer,
    project: installation,
    fonts: fonts,
    content: [
      for (final line in lines) pw.Text(line, style: pdfStyle(PdfPt.body)),
      pw.SizedBox(height: 16),
      ...pdfSection(
        s.customerHistory,
        fonts,
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (final v in visits)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Text('${v.time.day}.${v.time.month}.${v.time.year}  ${v.text}', style: pdfStyle(PdfPt.body)),
              ),
          ],
        ),
        count: visits.length,
      ),
    ],
  );
}

/// Emergency key of the app lock, to be kept outside the device.
Future<Uint8List> buildRecoveryKeyPdf(String code, {String? email}) async {
  final fonts = await PdfFonts.load();
  return pdfDocument(
    title: s.recoveryTitle,
    project: 'KNX Monitor',
    fonts: fonts,
    content: [
      pw.Text(s.recoveryPdfIntro, style: pdfStyle(PdfPt.body)),
      pw.SizedBox(height: 16),
      pw.Text(code, style: pw.TextStyle(font: fonts.semibold, fontSize: 16)),
      pw.SizedBox(height: 16),
      if (email != null) ...[
        pw.Text(s.recoveryPdfAccount(email), style: pdfStyle(PdfPt.body)),
        pw.SizedBox(height: 16),
      ],
      pw.Text(s.recoveryPdfUse, style: pdfStyle(PdfPt.body)),
      pw.SizedBox(height: 8),
      pw.Text(Betrieb.enabled ? s.recoveryPdfLimitsTeam : s.recoveryPdfLimits, style: pdfStyle(PdfPt.body)),
      pw.SizedBox(height: 8),
      pw.Text(s.recoveryPdfKeep, style: pdfStyle(PdfPt.body)),
    ],
  );
}

/// Setup key of the authenticator app: it allows setting the app up again on a new phone. Shown
/// only during setup; afterwards not even the app knows it.
Future<Uint8List> buildAuthenticatorKeyPdf({required String secret, required String uri, String? email}) async {
  final fonts = await PdfFonts.load();
  return pdfDocument(
    title: s.accountMfaPdfTitle,
    project: 'KNX Monitor',
    fonts: fonts,
    content: [
      pw.Text(s.accountMfaPdfIntro, style: pdfStyle(PdfPt.body)),
      pw.SizedBox(height: 16),
      pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: uri, width: 140, height: 140),
      pw.SizedBox(height: 16),
      pw.Text(secret, style: pw.TextStyle(font: fonts.semibold, fontSize: 14)),
      pw.SizedBox(height: 16),
      if (email != null) ...[
        pw.Text(s.recoveryPdfAccount(email), style: pdfStyle(PdfPt.body)),
        pw.SizedBox(height: 16),
      ],
      pw.Text(s.accountMfaPdfUse, style: pdfStyle(PdfPt.body)),
      pw.SizedBox(height: 8),
      pw.Text(s.accountMfaPdfWarning, style: pw.TextStyle(font: fonts.semibold, fontSize: 11)),
    ],
  );
}

Future<Uint8List> buildResidentManualPdf(ResidentManual m) async {
  final fonts = await PdfFonts.load();
  final contact = [
    if (m.contactName.isNotEmpty) m.contactName,
    if (m.contactPhone.isNotEmpty) m.contactPhone,
    if (m.contactEmail.isNotEmpty) m.contactEmail,
  ];
  return pdfDocument(
    title: s.manualPdfTitle,
    subtitle: m.customer.isEmpty ? null : m.customer,
    project: m.project,
    fonts: fonts,
    content: [
      pw.Text(s.manualIntro, style: pdfStyle(PdfPt.body)),
      pw.SizedBox(height: 16),
      if (m.note.isNotEmpty) ...[
        pw.Inseparable(child: pdfNote(m.note, fonts, label: s.manualNoteLabel)),
        pw.SizedBox(height: 16),
      ],
      for (final room in m.rooms)
        ...pdfSection(
          room.title.isEmpty ? s.manualOther : room.title,
          fonts,
          count: room.entries.length,
          pw.Table(
            columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(3)},
            children: [
              for (final (i, e) in room.entries.indexed)
                pw.TableRow(
                  decoration: pdfRowDecoration(i),
                  children: [
                    pdfPad(pw.Text(e.name, style: pdfStyle(PdfPt.body, font: fonts.medium))),
                    pdfPad(pw.Text(_manualKind(e.kind), style: pdfStyle(PdfPt.body, color: pdfMuted))),
                  ],
                ),
            ],
          ),
        ),
      pw.Inseparable(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _kennung(s.manualTroubleTitle, fonts),
            pw.SizedBox(height: 4),
            for (final (i, step) in [s.manualTrouble1, s.manualTrouble2, s.manualTrouble3].indexed)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Text('${i + 1}. $step', style: pdfStyle(PdfPt.body)),
              ),
            if (contact.isNotEmpty) ...[
              pw.SizedBox(height: 12),
              _kennung(s.manualContact, fonts),
              pw.SizedBox(height: 4),
              for (final line in contact) pw.Text(line, style: pdfStyle(PdfPt.body)),
            ],
          ],
        ),
      ),
    ],
  );
}

/// Installation report for the customer: the result in one sentence at the top, then the findings
/// compared to the previous report, with the evidence after that. Built so the business can pass it
/// on without rework.
Future<Uint8List> buildPlantReportPdf(
  PlantReport r, {
  String customer = '',
  String site = '',
  String? project,
  DateTime? nextMaintenance,
}) async {
  final fonts = await PdfFonts.load();
  String percent(double v) => localizeDecimal((v * 100).toStringAsFixed(v < 0.1 ? 1 : 0));
  final availability = r.availability;
  ServiceLevel level(Object? l) => switch (l) {
    'critical' => ServiceLevel.fix,
    'warning' => ServiceLevel.watch,
    _ => ServiceLevel.info,
  };
  ServiceLine line(Map<String, Object?> f) =>
      ServiceLine(level(f['level']), plantFindingText(f), plantFindingStatus(f['status']) ?? '');
  return pdfDocument(
    title: s.plantPdfTitle,
    subtitle: plantPeriodText(r.from, r.to),
    project: project,
    fonts: fonts,
    content: [
      pdfSummary([
        (s.acceptCustomer, customer.isEmpty ? '—' : customer, 2),
        (s.acceptSite, site.isEmpty ? '—' : site.replaceAll('\n', ', '), 3),
        (s.plantPeriod, plantPeriodText(r.from, r.to), 3),
      ], fonts),
      pw.SizedBox(height: 12),
      pw.Text(
        r.attention == 0 ? s.plantResultGood : s.plantResultAttention(r.attention),
        style: pdfStyle(PdfPt.body, font: fonts.semibold, color: r.attention == 0 ? _positive : _warning),
      ),
      if (r.partial) ...[
        pw.SizedBox(height: 4),
        pw.Text(s.plantPartial, style: pdfStyle(PdfPt.small, color: pdfMuted)),
      ],
      pw.SizedBox(height: 12),
      pdfSummary([
        (s.plantAvailabilityLabel, availability == null ? '—' : '${percent(availability)} %', 2),
        (s.plantTelegramsLabel, '${r.telegrams}', 2),
        (s.plantLoadLabel, '${percent(r.averageLoad)} / ${percent(r.peakLoad)} %', 2),
        (s.plantCoverageLabel, '${r.coveredDays} / ${r.totalDays}', 2),
      ], fonts),
      pw.SizedBox(height: 16),
      if (nextMaintenance != null) ...[
        pdfNote(s.customerNextMaintenance(pdfDate(nextMaintenance)), fonts, label: s.plantMaintenance),
        pw.SizedBox(height: 16),
      ],
      ...pdfSection(
        s.plantFindings,
        fonts,
        count: r.findings.length,
        r.findings.isEmpty
            ? pw.Text(s.plantFindingsNone, style: pdfStyle(PdfPt.body))
            : _serviceLines([for (final f in r.findings) line(f)], fonts),
      ),
      if (r.resolved.isNotEmpty)
        ...pdfSection(
          s.plantResolved,
          fonts,
          count: r.resolved.length,
          _serviceLines([
            for (final f in r.resolved) ServiceLine(ServiceLevel.info, plantFindingText(f), s.plantStatusResolved),
          ], fonts),
        ),
      if (r.safety.isNotEmpty)
        ..._simpleTable(s.plantSafety, fonts, [
          for (final x in r.safety)
            [
              '${x['label']}',
              '${x['name'] ?? ''}',
              switch (x['state']) {
                'active' => s.plantSafetyActive,
                'ok' => s.plantSafetyOk,
                _ => s.plantSafetyUnknown,
              },
              x['last'] is int ? pdfDate(DateTime.fromMillisecondsSinceEpoch(x['last']! as int)) : '—',
            ],
        ]),
      if (r.outages.isNotEmpty)
        ..._simpleTable(s.plantOutageList, fonts, [
          for (final o in r.outages.take(50))
            [plantOutageText(o), '', o['kind'] == 'offline' ? s.plantOutageOffline : s.plantOutageDisconnected, ''],
        ]),
      if (r.topSenders.isNotEmpty)
        ..._simpleTable(s.plantTopSenders, fonts, [
          for (final x in r.topSenders) ['${x['label']}', '', s.plantTelegrams(x['count']! as int), ''],
        ]),
      if (r.lines.isNotEmpty)
        ..._simpleTable(s.plantLines, fonts, [
          for (final l in r.lines)
            [
              '${l['line']}',
              '',
              s.plantLoad(percent((l['average']! as num).toDouble()), percent((l['peak']! as num).toDouble())),
              '',
            ],
        ]),
      if (r.repeats.isNotEmpty)
        ..._simpleTable(s.plantRepeatList, fonts, [
          for (final x in r.repeats)
            [
              '${x['label']}',
              '',
              s.plantTelegrams(x['count']! as int),
              '${localizeDecimal(((x['rate']! as num) * 100).toStringAsFixed(1))} %',
            ],
        ]),
      pw.Text(s.plantPdfNote, style: pdfStyle(PdfPt.small, color: pdfMuted)),
    ],
  );
}
