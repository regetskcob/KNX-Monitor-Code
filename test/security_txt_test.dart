import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// security.txt (RFC 9116) on knx-monitor.de: where to report a vulnerability. Expires
// must not pass unnoticed, so this test turns red a month before; then move the date
// on by at most a year and deploy the site.
void main() {
  test('security.txt nennt Meldewege und läuft nicht bald ab', () {
    final lines = File('site/static/.well-known/security.txt').readAsLinesSync();
    String? field(String name) =>
        lines.where((l) => l.startsWith('$name: ')).map((l) => l.substring(name.length + 2)).firstOrNull;

    expect(
      lines.where((l) => l.startsWith('Contact: ')),
      containsAll([
        'Contact: https://github.com/regetskcob/KNX-Monitor/security/advisories/new',
        'Contact: mailto:support@knx-monitor.de',
      ]),
    );
    expect(field('Canonical'), 'https://knx-monitor.de/.well-known/security.txt');
    final expires = DateTime.parse(field('Expires')!);
    final now = DateTime.now().toUtc();
    expect(expires.isAfter(now.add(const Duration(days: 30))), isTrue, reason: 'Expires $expires: bald erneuern');
    expect(expires.isBefore(now.add(const Duration(days: 366))), isTrue, reason: 'RFC 9116: höchstens ein Jahr');
  });
}
