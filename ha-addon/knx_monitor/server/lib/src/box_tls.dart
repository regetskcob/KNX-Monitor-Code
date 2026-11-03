import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

/// HTTPS of the box with its own self-signed certificate.
///
/// `box/files/tls-cert.sh` creates it on first start (a separate key per box,
/// never in the image). The browser warns about it; the app checks the
/// fingerprint from the QR code (`fp`) and trusts nothing else. A certificate
/// authority cannot issue anything for `10.42.0.1` or `knx-box.local` anyway.
class BoxTls {
  BoxTls._(this.context, this.fingerprint);

  final SecurityContext context;

  /// SHA-256 of the certificate (DER), base64url without padding.
  final String fingerprint;

  /// Loads certificate and key. `null` if they are missing or unreadable:
  /// the box then stays reachable over HTTP and says so in the log.
  static Future<BoxTls?> load(String? certPath, String? keyPath) async {
    if (certPath == null || keyPath == null || certPath.isEmpty || keyPath.isEmpty) return null;
    if (!await File(certPath).exists() || !await File(keyPath).exists()) return null;
    try {
      final pem = await File(certPath).readAsString();
      final context = SecurityContext()
        ..useCertificateChain(certPath)
        ..usePrivateKey(keyPath);
      return BoxTls._(context, certificateFingerprint(pem));
    } on Object catch (e) {
      stderr.writeln('Zertifikat nicht lesbar: $e');
      return null;
    }
  }
}

/// Fingerprint of the first certificate in [pem], computed like `tls-cert.sh` does.
String certificateFingerprint(String pem) {
  final match = RegExp(r'-----BEGIN CERTIFICATE-----([A-Za-z0-9+/=\s]+)-----END CERTIFICATE-----').firstMatch(pem);
  if (match == null) throw const FormatException('kein Zertifikat');
  final der = base64.decode(match[1]!.replaceAll(RegExp(r'\s'), ''));
  return derFingerprint(der);
}

/// SHA-256 of [der], base64url without padding.
String derFingerprint(List<int> der) =>
    base64Url.encode(SHA256Digest().process(Uint8List.fromList(der))).replaceAll('=', '');
