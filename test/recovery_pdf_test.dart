import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/export/pdf_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Notfallschlüssel wird ein PDF, auch ohne Konto', () async {
    for (final email in [null, 'a@b.invalid']) {
      final bytes = await buildRecoveryKeyPdf('ABCD-EFGH', email: email);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    }
  });

  test('Anmeldeschlüssel der Authenticator-App wird ein PDF', () async {
    final bytes = await buildAuthenticatorKeyPdf(
      secret: 'JBSWY3DPEHPK3PXP',
      uri: 'otpauth://totp/KNX:a@b.invalid?secret=JBSWY3DPEHPK3PXP',
      email: 'a@b.invalid',
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
