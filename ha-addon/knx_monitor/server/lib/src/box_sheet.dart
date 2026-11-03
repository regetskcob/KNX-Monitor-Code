import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// What is printed on the KNX box sheet; firstboot.sh passes it on first start
/// (`server sheet <folder>`), and the box writes it as `knx-box-de.pdf` and
/// `knx-box-en.pdf` to the SD card.
class BoxSheet {
  const BoxSheet({
    required this.name,
    required this.ssid,
    required this.wifiPassword,
    required this.boxPassword,
    required this.link,
    this.lanAccess = false,
  });

  final String name;
  final String ssid;
  final String wifiPassword;
  final String boxPassword;

  /// Setup link for the app (`knxmonitor://box?…&pw=…`), as in the QR code.
  final String link;
  final bool lanAccess;

  /// Wi-Fi QR code for the camera (special characters escaped as in
  /// firstboot.sh). Without a password (changed, see secrets.sh) the camera
  /// asks for it.
  String get wifiQr => 'WIFI:T:WPA;S:${_escape(ssid)};${wifiPassword.isEmpty ? '' : 'P:${_escape(wifiPassword)};'};';

  static String _escape(String s) => s.replaceAllMapped(RegExp(r'[\\;,:"]'), (m) => '\\${m[0]}');
}

/// Size of both stickers (dashed frame) in pt, printed at actual size:
/// exactly 95.25 × 47.27 mm, corner radius 2.12 mm (rounded 95 × 47 mm, 2 mm;
/// 1 pt = 25.4/72 mm). **Do not change, not even to round millimetres:** the
/// box case has recesses for exactly this size (top and bottom). The content
/// may change as long as it fits within the frame.
const stickerWidth = 270.0;
const stickerHeight = 134.0;
const stickerRadius = 6.0;

/// One A4 page: two stickers to cut out (1 top: app, 2 bottom: Wi-Fi), access
/// data, a link to paste and the next steps. [lang] is `de` or `en`.
///
/// Only the PDF standard fonts: umlauts, ß and · work; typographic quotation
/// marks, dashes, arrows and check marks show up as boxes.
///
/// [compress] off only for tests: then the geometry is readable.
Future<Uint8List> boxSheetPdf(BoxSheet sheet, {String lang = 'de', bool compress = true}) {
  final t = lang == 'en' ? _en : _de;
  final regular = pw.Font.helvetica();
  final bold = pw.Font.helveticaBold();
  final mono = pw.Font.courier();
  const ink = PdfColor.fromInt(0xFF1B1F1D);
  const muted = PdfColor.fromInt(0xFF5B6560);
  const line = PdfColor.fromInt(0xFFD5DBD8);
  const accent = PdfColor.fromInt(0xFF2E7D32);

  pw.Widget kennung(String text) => pw.Text(
    text.toUpperCase(),
    style: pw.TextStyle(font: bold, fontSize: 7.5, letterSpacing: 0.8, color: muted),
  );

  pw.Widget qr(String data, double size) => pw.BarcodeWidget(
    barcode: pw.Barcode.qrCode(errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium),
    data: data,
    width: size,
    height: size,
    drawText: false,
  );

  pw.Widget row(String term, String value, {bool code = false}) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 3.5),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: line, width: 0.5)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 120,
          child: pw.Text(
            term,
            style: pw.TextStyle(font: regular, fontSize: 9.5, color: muted),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: code
                ? pw.TextStyle(font: mono, fontSize: 11, color: ink)
                : pw.TextStyle(font: bold, fontSize: 10, color: ink),
          ),
        ),
      ],
    ),
  );

  pw.Widget step(int n, String head, String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 16,
          child: pw.Text(
            '$n',
            style: pw.TextStyle(font: bold, fontSize: 10, color: accent),
          ),
        ),
        pw.Expanded(
          child: pw.RichText(
            text: pw.TextSpan(
              style: pw.TextStyle(font: regular, fontSize: 9.5, color: ink, lineSpacing: 1),
              children: [
                pw.TextSpan(
                  text: '$head ',
                  style: pw.TextStyle(font: bold),
                ),
                pw.TextSpan(text: text),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  final small = pw.TextStyle(font: regular, fontSize: 8, color: ink, lineSpacing: 1.5);

  /// A sticker in the fixed size: number and position at the top, then its
  /// purpose, the code on the left.
  pw.Widget sticker({
    required String tag,
    required PdfColor tagColor,
    required String title,
    required String code,
    required List<pw.Widget> lines,
  }) => pw.Container(
    width: stickerWidth,
    height: stickerHeight,
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: muted, width: 0.8, style: pw.BorderStyle.dashed),
      borderRadius: pw.BorderRadius.circular(stickerRadius),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        qr(code, 110),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                tag.toUpperCase(),
                style: pw.TextStyle(font: bold, fontSize: 7, letterSpacing: 0.6, color: tagColor),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                title,
                style: pw.TextStyle(font: bold, fontSize: 12, color: ink),
              ),
              pw.SizedBox(height: 5),
              ...lines,
            ],
          ),
        ),
      ],
    ),
  );

  pw.Widget stickerRow({
    required String number,
    required pw.Widget sticker,
    required String place,
    required String where,
  }) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      sticker,
      pw.SizedBox(width: 18),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              number,
              style: pw.TextStyle(font: bold, fontSize: 28, color: accent),
            ),
            pw.Text(
              place,
              style: pw.TextStyle(font: bold, fontSize: 12, color: ink),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              where,
              style: pw.TextStyle(font: regular, fontSize: 8.5, color: muted, lineSpacing: 1.5),
            ),
          ],
        ),
      ),
    ],
  );

  final doc = pw.Document(
    title: '${t.title} ${sheet.name}',
    author: 'KNX Monitor',
    creator: 'KNX Monitor Box',
    compress: compress,
  );
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(48, 44, 48, 40),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // Header: identifier, name, line in the accent colour.
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    kennung('KNX Monitor · ${t.title}'),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      sheet.name,
                      style: pw.TextStyle(font: bold, fontSize: 22, color: ink),
                    ),
                  ],
                ),
              ),
              pw.Text(
                t.site,
                style: pw.TextStyle(font: regular, fontSize: 9, color: muted),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Container(height: 1.5, color: accent),
          pw.SizedBox(height: 14),
          // Two stickers of the same size stacked, next to them in large type
          // where they go: 1 on top (app), 2 on the bottom (Wi-Fi).
          kennung(t.stickersLabel),
          pw.SizedBox(height: 6),
          stickerRow(
            number: '1',
            sticker: sticker(
              tag: t.appTag,
              tagColor: accent,
              title: t.appTitle,
              code: sheet.link,
              lines: [pw.Text(t.appText, style: small)],
            ),
            place: t.appPlace,
            where: t.appWhere,
          ),
          pw.SizedBox(height: 10),
          stickerRow(
            number: '2',
            sticker: sticker(
              tag: t.wifiTag,
              tagColor: ink,
              title: t.wifiTitle,
              code: sheet.wifiQr,
              lines: [
                pw.Text(t.wifiText, style: small),
                pw.SizedBox(height: 4),
                pw.Text(
                  '${t.wifi}: ${sheet.ssid}',
                  style: pw.TextStyle(font: bold, fontSize: 8.5, color: ink),
                ),
                pw.Text(
                  '${t.password}: ${sheet.wifiPassword.isEmpty ? t.ownPassword : sheet.wifiPassword}',
                  style: pw.TextStyle(font: mono, fontSize: 8.5, color: ink),
                ),
              ],
            ),
            place: t.wifiPlace,
            where: t.wifiWhere,
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            t.cutHint,
            style: pw.TextStyle(font: regular, fontSize: 7.5, color: muted),
          ),
          pw.SizedBox(height: 14),
          kennung(t.accessLabel),
          pw.SizedBox(height: 3),
          // About the access data: whoever has the sheet can pair.
          pw.Text(
            t.keepSafe,
            style: pw.TextStyle(font: bold, fontSize: 8.5, color: ink),
          ),
          pw.SizedBox(height: 2),
          row(t.wifi, sheet.ssid),
          row(
            t.wifiPassword,
            sheet.wifiPassword.isEmpty ? t.ownPassword : sheet.wifiPassword,
            code: sheet.wifiPassword.isNotEmpty,
          ),
          row(
            t.boxPassword,
            sheet.boxPassword.isEmpty ? t.ownPassword : sheet.boxPassword,
            code: sheet.boxPassword.isNotEmpty,
          ),
          row(t.address, '10.42.0.1 · knx-box.local'),
          row(t.cable, sheet.lanAccess ? t.cableOn : t.cableOff),
          pw.SizedBox(height: 12),
          kennung(t.linkLabel),
          pw.SizedBox(height: 4),
          pw.Text(
            t.linkText,
            style: pw.TextStyle(font: regular, fontSize: 8.5, color: muted),
          ),
          pw.SizedBox(height: 4),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFF2F4F3),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              _breakable(sheet.link),
              style: pw.TextStyle(font: mono, fontSize: 7.5, color: ink),
            ),
          ),
          pw.SizedBox(height: 12),
          kennung(t.stepsLabel),
          pw.SizedBox(height: 6),
          for (final (i, (head, text)) in t.steps.indexed) step(i + 1, head, text),
        ],
      ),
    ),
  );
  return doc.save();
}

/// The PDF does not wrap long links without spaces: break before each `&`
/// as long as the line would otherwise be too long.
String _breakable(String s, {int width = 86}) {
  final lines = <String>[];
  var current = '';
  for (final part in s.split('&')) {
    final piece = current.isEmpty ? part : '&$part';
    if (current.isNotEmpty && current.length + piece.length > width) {
      lines.add(current);
      current = '&$part';
    } else {
      current += piece;
    }
  }
  lines.add(current);
  return lines.join('\n');
}

class _Texts {
  const _Texts({
    required this.title,
    required this.site,
    required this.stickersLabel,
    required this.cutHint,
    required this.appTag,
    required this.appTitle,
    required this.appText,
    required this.appPlace,
    required this.appWhere,
    required this.wifiTag,
    required this.wifiTitle,
    required this.wifiText,
    required this.wifiPlace,
    required this.wifiWhere,
    required this.accessLabel,
    required this.password,
    required this.wifi,
    required this.wifiPassword,
    required this.boxPassword,
    required this.ownPassword,
    required this.address,
    required this.cable,
    required this.cableOn,
    required this.cableOff,
    required this.linkLabel,
    required this.linkText,
    required this.stepsLabel,
    required this.steps,
    required this.keepSafe,
  });

  final String title, site, stickersLabel, cutHint;
  final String appTag, appTitle, appText, appPlace, appWhere;
  final String wifiTag, wifiTitle, wifiText, wifiPlace, wifiWhere;
  final String accessLabel, password, wifi, wifiPassword, boxPassword, ownPassword, address, cable, cableOn, cableOff;
  final String linkLabel, linkText, stepsLabel, keepSafe;
  final List<(String, String)> steps;
}

const _de = _Texts(
  title: 'KNX-Box',
  site: 'knx-monitor.de/box',
  stickersLabel: 'Zwei Aufkleber für die Box',
  cutHint: 'Beide entlang der gestrichelten Linie ausschneiden. Gleiche Größe, aber nicht vertauschen: Nummer und Platz stehen auf jedem Aufkleber.',
  appTag: 'Aufkleber 1 · oben',
  appTitle: 'In der App scannen',
  appText: 'KNX Monitor öffnen, "KNX-Box hinzufügen" wählen und diesen Code scannen. Nicht mit der Kamera-App.',
  appPlace: 'Oben auf die Box',
  appWhere: 'Für die App: Er richtet die Box mit einem Scan ein (WLAN, Kopplung, Uhr, Gateway). Enthält das Box-Passwort, bis du ein eigenes setzt.',
  wifiTag: 'Aufkleber 2 · Boden',
  wifiTitle: 'WLAN der Box',
  wifiText: 'Mit der Kamera scannen, um dem WLAN beizutreten.',
  wifiPlace: 'Auf den Boden der Box',
  wifiWhere: 'Nur das WLAN, zum Beispiel für den Browser oder die Linux-App. Koppeln kann man damit nicht: Dafür braucht es Aufkleber 1 oder das Box-Passwort.',
  accessLabel: 'Zugangsdaten',
  password: 'Passwort',
  wifi: 'WLAN',
  wifiPassword: 'WLAN-Passwort',
  boxPassword: 'Box-Passwort',
  ownPassword: 'eigenes, hier nicht hinterlegt',
  address: 'Adresse im WLAN',
  cable: 'Zugriff über das Kabel',
  cableOn: 'an (auch aus dem Netz am Kabel erreichbar)',
  cableOff: 'aus (nur im WLAN der Box erreichbar)',
  linkLabel: 'Link zum Einfügen',
  linkText: 'Für Rechner ohne Kamera, etwa die Linux-App. Steht auch als knx-box-link.txt auf der SD-Karte.',
  stepsLabel: 'So geht es weiter',
  steps: [
    (
      'Anschließen.',
      'Netzwerkkabel zum Router oder Switch am KNX-IP-Gateway, dann Strom. Nach etwa einer Minute ist die Box bereit.',
    ),
    (
      'Mit Handy oder Tablet.',
      'In der App "KNX-Box hinzufügen" und Aufkleber 1 scannen. Die App tritt dem WLAN bei, koppelt sich, stellt die Uhr und sucht das Gateway.',
    ),
    (
      'Mit Linux.',
      'Am Rechner ins WLAN der Box wechseln (Name und Passwort oben). In der App "KNX-Box hinzufügen" und den Link von oben einfügen.',
    ),
    (
      'Ohne App.',
      'Aufkleber 2 mit der Kamera scannen, im Browser http://knx-box.local öffnen und mit dem Box-Passwort anmelden (Benutzername beliebig).',
    ),
    (
      'Eigenes Passwort.',
      'Nach dem Koppeln schlägt die App ein eigenes Box-Passwort vor. Danach koppeln dieses Blatt und Aufkleber 1 keine neuen Geräte mehr.',
    ),
  ],
  keepSafe:
      'Dieses Blatt enthält die Zugangsdaten der Box. Sicher aufbewahren und nicht an der Box lassen: '
      'Wer es hat, kann sich mit der Box koppeln, bis du das Box-Passwort änderst.',
);

const _en = _Texts(
  title: 'KNX box',
  site: 'knx-monitor.de/en/box',
  stickersLabel: 'Two labels for the box',
  cutHint:
      'Cut both out along the dashed line. Same size, but do not swap them: each label shows its number and place.',
  appTag: 'Label 1 · top',
  appTitle: 'Scan in the app',
  appText: 'Open KNX Monitor, choose "Add KNX box" and scan this code. Not with the camera app.',
  appPlace: 'On top of the box',
  appWhere: 'For the app: one scan sets up the box (Wi-Fi, pairing, clock, gateway). Holds the box password until you set your own.',
  wifiTag: 'Label 2 · bottom',
  wifiTitle: "The box's Wi-Fi",
  wifiText: 'Scan with the camera to join the Wi-Fi.',
  wifiPlace: 'On the bottom of the box',
  wifiWhere: 'Only the Wi-Fi, for example for the browser or the Linux app. It cannot pair: that takes label 1 or the box password.',
  accessLabel: 'Access details',
  password: 'Password',
  wifi: 'Wi-Fi',
  wifiPassword: 'Wi-Fi password',
  boxPassword: 'Box password',
  ownPassword: 'your own, not stored here',
  address: 'Address in the Wi-Fi',
  cable: 'Access via cable',
  cableOn: 'on (also reachable from the wired network)',
  cableOff: "off (only reachable in the box's Wi-Fi)",
  linkLabel: 'Link to paste',
  linkText: 'For computers without a camera, such as the Linux app. Also on the SD card as knx-box-link.txt.',
  stepsLabel: 'Next steps',
  steps: [
    (
      'Connect.',
      'Network cable to the router or switch at the KNX IP gateway, then power. After about a minute the box is ready.',
    ),
    (
      'With a phone or tablet.',
      'In the app, "Add KNX box" and scan label 1. The app joins the Wi-Fi, pairs, sets the clock and looks for the gateway.',
    ),
    (
      'With Linux.',
      "On the computer, switch to the box's Wi-Fi (name and password above). In the app, \"Add KNX box\" and paste the link above.",
    ),
    (
      'Without the app.',
      'Scan label 2 with the camera, open http://knx-box.local in a browser and sign in with the box password (any user name).',
    ),
    (
      'Your own password.',
      'After pairing, the app suggests setting your own box password. After that neither this sheet nor label 1 pairs new devices.',
    ),
  ],
  keepSafe:
      'This sheet holds the access details of the box. Keep it safe and do not leave it at the box: '
      'whoever has it can pair with the box until you change the box password.',
);
