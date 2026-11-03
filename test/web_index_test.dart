import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Das Passkeys-Plugin registriert sich im Web und ruft dabei
// PasskeyAuthenticator.init() aus seinem bundle.js auf. Fehlt das, startet die
// Web-App (und damit das Add-on) gar nicht – nur ein leerer Bildschirm.
void main() {
  test('index.html stellt PasskeyAuthenticator vor dem Start bereit', () {
    final html = File('web/index.html').readAsStringSync();
    // Das ausführbare Skript, nicht die Erwähnung im Kommentar davor.
    final stub = html.indexOf('<script>window.PasskeyAuthenticator');
    expect(stub, isNonNegative);
    expect(stub, lessThan(html.indexOf('<script src="flutter_bootstrap.js"')));
  });
}
