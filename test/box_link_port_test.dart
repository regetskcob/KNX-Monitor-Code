import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/platform/box_link.dart';
import 'package:knx_monitor/model/box_keyring_consent.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Fingerabdruck wechselt auf HTTPS und behält einen eigenen Port', () {
    final link = BoxLink(url: Uri.parse('http://nas:8765/x/'), fp: 'abc');
    expect('${link.url}', 'https://nas:8765/x/');
    expect('${BoxLink(url: Uri.parse('http://box:80/'), fp: 'abc').url}', 'https://box/');
  });

  test('anderes Zertifikat an derselben Adresse fragt neu nach dem Keyring', () async {
    SharedPreferences.setMockInitialValues({});
    var asked = 0;
    BoxKeyringConsent.ask = (_) async {
      asked++;
      return true;
    };
    addTearDown(() => BoxKeyringConsent.ask = null);
    final first = BoxLink(url: Uri.parse('https://box/'), fp: 'eins');
    expect(await BoxKeyringConsent.allowed(first), isTrue);
    expect(await BoxKeyringConsent.allowed(first), isTrue);
    expect(asked, 1);
    expect(await BoxKeyringConsent.allowed(BoxLink(url: Uri.parse('https://box/'), fp: 'zwei')), isTrue);
    expect(asked, 2);
  });
}
