import 'dart:convert';

import 'package:knx_monitor_server/box.dart';
import 'package:test/test.dart';

void main() {
  const sheet = BoxSheet(
    name: 'KNX-Box-1A2B',
    ssid: 'Baustelle;Süd',
    wifiPassword: 'Geheim:1,"x"',
    boxPassword: 'hz4wn8bcfe',
    link: 'knxmonitor://box?url=http%3A%2F%2F10.42.0.1%2F&name=KNX-Box-1A2B&pw=hz4wn8bcfe',
  );

  test('WLAN-Code maskiert Sonderzeichen wie firstboot.sh', () {
    expect(sheet.wifiQr, r'WIFI:T:WPA;S:Baustelle\;Süd;P:Geheim\:1\,\"x\";;');
  });

  test('Aufkleber bleibt 95,25 × 47,27 mm, Radius 2,12 mm (Gehäuse ist darauf gebaut)', () {
    double mm(double pt) => pt * 25.4 / 72;
    expect(mm(stickerWidth), closeTo(95.25, 0.01));
    expect(mm(stickerHeight), closeTo(47.27, 0.01));
    expect(mm(stickerRadius), closeTo(2.12, 0.01));
  });

  test('beide Aufkleber im PDF: genau 270 × 134 pt, Ecken 6 pt', () async {
    for (final lang in ['de', 'en']) {
      final text = latin1.decode(await boxSheetPdf(sheet, lang: lang, compress: false), allowInvalid: true);
      // Die Aufkleber sind die einzigen gestrichelten Pfade: [3 3] 0 d … S.
      final paths = RegExp(r'\[3 3\] 0 d.*? w (.*?) S').allMatches(text).toList();
      expect(paths, hasLength(2), reason: lang);
      for (final p in paths) {
        final n = RegExp(r'-?\d+(?:\.\d+)?').allMatches(p[1]!).map((m) => double.parse(m[0]!)).toList();
        final xs = [for (var i = 0; i < n.length; i += 2) n[i]];
        final ys = [for (var i = 1; i < n.length; i += 2) n[i]];
        expect(xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b), stickerWidth, reason: lang);
        expect(ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b), stickerHeight, reason: lang);
        // Der Pfad beginnt eine Eckrundung über der unteren Kante.
        expect(n[1] - ys.reduce((a, b) => a < b ? a : b), stickerRadius, reason: lang);
      }
    }
  });

  test('je Sprache ein PDF mit einer Seite', () async {
    for (final lang in ['de', 'en']) {
      final bytes = await boxSheetPdf(sheet, lang: lang);
      final text = latin1.decode(bytes, allowInvalid: true);
      expect(text, startsWith('%PDF'), reason: lang);
      expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, 1, reason: lang);
    }
  });

  test('Nach dem Ändern: keine Passwörter mehr auf dem Blatt', () async {
    const clean = BoxSheet(
      name: 'KNX-Box-1A2B',
      ssid: 'KNX-Box-1A2B',
      wifiPassword: '',
      boxPassword: '',
      link: 'knxmonitor://box?url=http%3A%2F%2F10.42.0.1%2F&name=KNX-Box-1A2B',
    );
    expect(clean.wifiQr, 'WIFI:T:WPA;S:KNX-Box-1A2B;;');
    for (final lang in ['de', 'en']) {
      expect(await boxSheetPdf(clean, lang: lang), isNotEmpty, reason: lang);
    }
  });
}
