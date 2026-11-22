import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/model/box_keyring_consent.dart';
import 'package:knx_monitor/model/full_backup.dart';
import 'package:knx_monitor/platform/box_link.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Adresse', () {
    for (final host in [
      '10.42.0.1',
      '172.16.0.1',
      '172.31.255.1',
      '192.168.1.5',
      '169.254.3.4',
      '127.0.0.1',
      'knx-box.local',
      'KNX-BOX.LOCAL',
      'localhost',
    ]) {
      test('$host ist lokal', () => expect(BoxLink.isLocalHost(host), isTrue));
    }
    for (final host in [
      'evil.example',
      '8.8.8.8',
      '172.32.0.1',
      '172.15.0.1',
      '192.169.0.1',
      '10.0.0.1.evil.example',
      'knx-box.local.evil.example',
      '2130706433',
      '0x7f.0.0.1',
      '10.0.0.256',
      '100.64.0.1',
      '2001:db8::1',
      '',
    ]) {
      test('„$host“ ist nicht lokal', () => expect(BoxLink.isLocalHost(host), isFalse));
    }

    test('IPv6: Loopback, Link-Local, ULA, abgebildetes IPv4', () {
      expect(BoxLink.isLocalHost('::1'), isTrue);
      expect(BoxLink.isLocalHost('fe80::1'), isTrue);
      expect(BoxLink.isLocalHost('fd00::1'), isTrue);
      expect(BoxLink.isLocalHost('::ffff:192.168.0.1'), isTrue);
      expect(BoxLink.isLocalHost('::ffff:8.8.8.8'), isFalse);
    });

    test('aus dem Link: fremde Adresse fällt auf, private nicht', () {
      expect(BoxLink.parse('knxmonitor://box?url=https://evil.example')!.isLocal, isFalse);
      expect(BoxLink.parse('knxmonitor://box?url=http://10.42.0.1/&key=abc')!.isLocal, isTrue);
      expect(BoxLink.parse('knxmonitor://box?url=http://knx-box.local/')!.isLocal, isTrue);
    });
  });

  group('Keyring-Freigabe', () {
    final fp = 'A' * 43;
    final box = BoxLink(url: Uri.parse('http://10.42.0.1/'), fp: fp);
    final other = BoxLink(url: Uri.parse('http://10.42.0.2/'), fp: fp);
    tearDown(() {
      BoxKeyringConsent.ask = null;
      BoxKeyringConsent.tellPlain = null;
    });

    test('unverschlüsselt: nie, ohne Frage, auch nicht mit früherem Ja; einmal gesagt', () async {
      final plain = BoxLink(url: Uri.parse('http://192.168.1.50/'), key: 'testzugang');
      // An earlier yes for the same address (stored before this rule existed).
      SharedPreferences.setMockInitialValues({'box_keyring_consent:http://192.168.1.50/': true});
      var asked = 0;
      final told = <BoxLink>[];
      BoxKeyringConsent.ask = (_) async {
        asked++;
        return true;
      };
      BoxKeyringConsent.tellPlain = told.add;
      expect(plain.plainOverNetwork, isTrue);
      expect(await BoxKeyringConsent.allowed(plain), isFalse);
      expect(await BoxKeyringConsent.allowed(plain), isFalse);
      expect(asked, 0);
      expect(told, [plain], reason: 'der Hinweis kommt je Box einmal');
      await BoxKeyringConsent.forget(plain);
    });

    test('Loopback bleibt auf dem Gerät und zählt nicht als Klartext im Netz', () {
      expect(BoxLink(url: Uri.parse('http://127.0.0.1:8765/')).plainOverNetwork, isFalse);
      expect(BoxLink(url: Uri.parse('http://localhost:8765/')).plainOverNetwork, isFalse);
      expect(BoxLink(url: Uri.parse('http://knx-box.local/')).plainOverNetwork, isTrue);
      expect(BoxLink(url: Uri.parse('http://10.42.0.1/')).plainOverNetwork, isTrue);
      expect(box.plainOverNetwork, isFalse);
    });

    test('ohne Oberfläche keine Freigabe, und nichts wird gemerkt', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await BoxKeyringConsent.allowed(box), isFalse);
      BoxKeyringConsent.ask = (_) async => true;
      expect(await BoxKeyringConsent.allowed(box), isTrue);
    });

    test('fragt je Box einmal und merkt sich die Antwort', () async {
      SharedPreferences.setMockInitialValues({});
      final asked = <BoxLink>[];
      BoxKeyringConsent.ask = (b) async {
        asked.add(b);
        return b == box;
      };
      expect(await BoxKeyringConsent.allowed(box), isTrue);
      expect(await BoxKeyringConsent.allowed(box), isTrue);
      expect(await BoxKeyringConsent.allowed(other), isFalse);
      expect(await BoxKeyringConsent.allowed(other), isFalse);
      expect(asked, [box, other]);
      await BoxKeyringConsent.forget(box);
      expect(await BoxKeyringConsent.allowed(box), isTrue);
      expect(asked, [box, other, box]);
    });

    test('gleichzeitig nur eine Frage', () async {
      SharedPreferences.setMockInitialValues({});
      var asked = 0;
      BoxKeyringConsent.ask = (_) async {
        asked++;
        return true;
      };
      await Future.wait([BoxKeyringConsent.allowed(box), BoxKeyringConsent.allowed(box)]);
      expect(asked, 1);
    });

    test('kommt nicht aus einer Sicherung', () async {
      expect(FullBackup.keepsOut('box_keyring_consent:http://evil/'), isTrue);
    });
  });
}
