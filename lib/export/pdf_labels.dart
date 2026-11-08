part of 'pdf_export.dart';

/// A4 label sheet (70 × 37 mm, [labelColumns] × [labelRows], no margins): individual address in
/// large type, function, mounting location, QR code. `pdf` package only.
Future<Uint8List> buildDeviceLabelsPdf(List<DeviceLabel> labels) async {
  final fonts = await PdfFonts.load();
  final doc = pw.Document(title: s.siteDocsLabelsPdf, creator: 'Busclear');
  const perPage = labelColumns * labelRows;
  final width = PdfPageFormat.a4.width / labelColumns;
  final height = PdfPageFormat.a4.height / labelRows;
  pw.Widget label(DeviceLabel l) => pw.SizedBox(
    width: width,
    height: height,
    child: pw.Padding(
      padding: const pw.EdgeInsets.all(10),
      child: pw.Row(
        children: [
          pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: l.code, width: height - 28, height: height - 28),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(formatIndividual(l.address), style: pdfStyle(PdfPt.body * 1.2, font: fonts.semibold)),
                if (l.function.isNotEmpty) pw.Text(l.function, style: pdfStyle(PdfPt.small), maxLines: 2),
                if (l.place.isNotEmpty) pw.Text(l.place, style: pdfStyle(PdfPt.small, color: pdfMuted), maxLines: 2),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  for (var i = 0; i < labels.length; i += perPage) {
    final page = labels.sublist(i, i + perPage < labels.length ? i + perPage : labels.length);
    doc.addPage(
      pw.Page(
        theme: fonts.theme,
        pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 0, marginRight: 0, marginTop: 0, marginBottom: 0),
        build: (_) => pw.Wrap(children: [for (final l in page) label(l)]),
      ),
    );
  }
  return doc.save();
}
