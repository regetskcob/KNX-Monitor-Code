import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../platform/storage.dart';
import 'plan.dart';

/// Letterhead of a PDF: data only, so it fits into the background isolate.
@immutable
class Letterhead {
  const Letterhead({
    required this.name,
    this.addressLines = const [],
    this.contactLine = '',
    this.registration = '',
    this.technician = '',
    this.logoPng,
  });

  final String name;

  /// Postal address, one line per entry.
  final List<String> addressLines;

  /// Phone, email and website on one line (footer, header).
  final String contactLine;

  /// VAT ID and registration (trade register …).
  final String registration;
  final String technician;

  /// Logo as PNG, already downscaled to [logoMaxHeight].
  final Uint8List? logoPng;

  /// Appears as the author in the PDF metadata.
  String get author => technician.isEmpty ? name : '$name, $technician';
}

/// Company details for the letterhead (settings page "Firma", company). Apply to
/// all installations on this device.
@immutable
class Company {
  const Company({
    this.name = '',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.website = '',
    this.vatId = '',
    this.registration = '',
    this.technician = '',
  });

  static const empty = Company();

  final String name;

  /// Multi-line.
  final String address;
  final String phone;
  final String email;
  final String website;

  /// VAT ID (optional).
  final String vatId;

  /// E.g. "Eingetragen in die Handwerksrolle …" (registered in the trade register; optional).
  final String registration;

  /// Who does the work; per device.
  final String technician;

  /// Without a company name there is no letterhead.
  bool get isSet => name.trim().isNotEmpty;

  /// Phone, email and website on one line.
  String get contactLine => [phone, email, website].map((v) => v.trim()).where((v) => v.isNotEmpty).join(' · ');

  Map<String, Object?> toJson() => {
    'name': name,
    'address': address,
    'phone': phone,
    'email': email,
    'website': website,
    'vatId': vatId,
    'registration': registration,
    'technician': technician,
  };

  /// Unknown or wrongly typed fields stay empty: the file must never break
  /// startup.
  factory Company.fromJson(Map<String, Object?> j) {
    String text(String key) => j[key] is String ? j[key]! as String : '';
    return Company(
      name: text('name'),
      address: text('address'),
      phone: text('phone'),
      email: text('email'),
      website: text('website'),
      vatId: text('vatId'),
      registration: text('registration'),
      technician: text('technician'),
    );
  }

  Letterhead letterhead({Uint8List? logo}) => Letterhead(
    name: name.trim(),
    addressLines: [
      for (final l in address.split('\n'))
        if (l.trim().isNotEmpty) l.trim(),
    ],
    contactLine: contactLine,
    registration: [vatId.trim(), registration.trim()].where((v) => v.isNotEmpty).join(' · '),
    technician: technician.trim(),
    logoPng: logo,
  );
}

/// Maximum logo height in pixels (enough for 48 pt in print, about 300 dpi).
const logoMaxHeight = 200;

/// Maximum logo width in pixels: very wide lettering stays readable, but small.
const logoMaxWidth = 1200;

/// Largest file accepted as a logo.
const logoMaxBytes = 20 * 1024 * 1024;

/// Normalizes a chosen image: PNG with transparency, upright (EXIF), at most
/// [logoMaxWidth] × [logoMaxHeight]; metadata is dropped. Throws
/// [FormatException] if it is not a readable image.
Uint8List normalizeLogoImage(Uint8List bytes) {
  if (bytes.length > logoMaxBytes) throw const FormatException('logo too large');
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object catch (e) {
    throw FormatException('$e');
  }
  if (decoded == null || decoded.width == 0 || decoded.height == 0) throw const FormatException('image');
  final upright = img.bakeOrientation(decoded);
  final factor = [1.0, logoMaxWidth / upright.width, logoMaxHeight / upright.height].reduce((a, b) => a < b ? a : b);
  final scaled = factor >= 1
      ? upright
      : img.copyResize(
          upright,
          width: (upright.width * factor).ceil().clamp(1, logoMaxWidth),
          height: (upright.height * factor).ceil().clamp(1, logoMaxHeight),
          interpolation: img.Interpolation.average,
        );
  // 16-bit, palette, CMYK JPEG: convert everything to 8-bit RGBA, which every viewer can handle.
  return img.encodePng(scaled.convert(format: img.Format.uint8, numChannels: 4));
}

/// Single-page PDF showing exactly the SVG; the raster is made from it. Throws
/// [FormatException] if the text is not a readable SVG.
Future<Uint8List> svgLogoAsPdf(String svg) async {
  try {
    final image = pw.SvgImage(svg: svg, fit: pw.BoxFit.contain);
    final doc = pw.Document();
    // Wide sheet at logo height; contain keeps the SVG's aspect ratio.
    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(600, 200),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Align(alignment: pw.Alignment.centerLeft, child: image),
      ),
    );
    return await doc.save();
  } on Object catch (e) {
    throw FormatException('$e');
  }
}

/// PDF → PNG. Natively with PDFium, in the browser with pdf.js (both from `printing`).
Future<Uint8List> _rasterPdf(Uint8List pdf) async {
  await for (final page in Printing.raster(pdf, pages: const [0], dpi: 144)) {
    return page.toPng();
  }
  throw const FormatException('svg');
}

/// Turns the chosen file into the stored logo. SVG is rasterized, then treated
/// like any image; [raster] is for tests.
Future<Uint8List> normalizeLogo(
  Uint8List bytes,
  String fileName, {
  Future<Uint8List> Function(Uint8List pdf) raster = _rasterPdf,
}) async {
  if (bytes.length > logoMaxBytes) throw const FormatException('logo too large');
  final isSvg = fileName.toLowerCase().endsWith('.svg');
  if (!isSvg) return compute(normalizeLogoImage, bytes);
  final text = utf8.decode(bytes);
  if (!text.contains('<svg')) throw const FormatException('svg');
  final png = await raster(await svgLogoAsPdf(text));
  return compute(_trimmedLogo, png);
}

/// The raster has the sheet size: remove empty margins, otherwise a narrow logo
/// would sit in the header with lots of space around it.
Uint8List _trimmedLogo(Uint8List png) {
  final image = img.decodePng(png);
  if (image == null) throw const FormatException('svg');
  final trimmed = img.trim(image.convert(numChannels: 4), mode: img.TrimMode.transparent);
  // Rasterized on white (PDFium without alpha): then trim by the corner colors.
  final result = trimmed.width == image.width && trimmed.height == image.height
      ? img.trim(trimmed, mode: img.TrimMode.topLeftColor)
      : trimmed;
  return normalizeLogoImage(img.encodePng(result));
}

/// Company details and logo of this device: `company.json` and
/// `company_logo.png.b64` in the main storage, outside the installations.
class CompanyStore extends ChangeNotifier {
  CompanyStore._();

  static final instance = CompanyStore._();

  static const _path = 'company.json';
  static const _logoPath = 'company_logo.png.b64';

  AppStorage get _storage => AppStorage.instance;

  Company company = Company.empty;
  Uint8List? logo;

  Future<void> load() async {
    company =
        await readStored(
          _storage,
          _path,
          (text) => Company.fromJson((jsonDecode(text) as Map).cast<String, Object?>()),
        ) ??
        Company.empty;
    logo = await readStored(_storage, _logoPath, base64Decode);
    notifyListeners();
  }

  Future<void> save(Company value) async {
    company = value;
    await _storage.write(_path, jsonEncode(value.toJson()));
    notifyListeners();
  }

  /// Stores an already downscaled logo ([normalizeLogo]); `null` removes it.
  Future<void> setLogo(Uint8List? png) async {
    logo = png;
    if (png == null) {
      await _storage.delete(_logoPath);
    } else {
      await _storage.write(_logoPath, base64Encode(png));
    }
    notifyListeners();
  }

  /// Letterhead for the next PDF; `null` without Pro or without a company name –
  /// then the PDF looks as usual.
  Letterhead? get letterhead =>
      Plan.instance.allows(Feature.letterhead) && company.isSet ? company.letterhead(logo: logo) : null;

  @visibleForTesting
  void debugReset() {
    company = Company.empty;
    logo = null;
  }
}
