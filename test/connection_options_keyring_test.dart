import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/model/box_keyring_consent.dart';
import 'package:knx_monitor/model/connection_options.dart';
import 'package:knx_monitor/platform/addon.dart';
import 'package:knx_monitor/platform/box_link.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final options = ConnectionOptions.instance;

  setUp(() {
    options
      ..mode = ConnectionMode.secure
      ..secureUserId = 7
      ..secureUserPassword = '';
  });
  tearDown(() {
    options
      ..mode = ConnectionMode.udp
      ..secureUserId = 2
      ..secureUserPassword = ''
      ..secureDeviceAuthentication = '';
  });

  Map<String, Object?> secure({required bool allowed}) =>
      options.toAddon(host: 'box', port: 3671, secretsAllowed: allowed)['secure']! as Map<String, Object?>;

  test('ohne Freigabe bleibt alles Secure auf der Box unverändert', () {
    final sent = secure(allowed: false);
    expect(sent.containsKey('userId'), isFalse);
    expect(sent['userPassword'], '');
    expect(sent['deviceAuthentication'], '');
  });

  test('auch selbst Eingegebenes geht nur mit Freigabe mit', () {
    options
      ..secureUserPassword = 'eingetippt'
      ..secureDeviceAuthentication = 'geraet';
    final sent = secure(allowed: false);
    expect(sent.containsKey('userId'), isFalse);
    expect(sent['userPassword'], '');
    expect(sent['deviceAuthentication'], '');
    final allowed = secure(allowed: true);
    expect(allowed['userId'], 7);
    expect(allowed['userPassword'], 'eingetippt');
    expect(allowed['deviceAuthentication'], 'geraet');
  });

  test('am Box-Gerät fragt auch Eingetipptes erst nach der Freigabe', () async {
    SharedPreferences.setMockInitialValues({});
    options.secureUserPassword = 'eingetippt';
    final asked = <BoxLink>[];
    BoxKeyringConsent.ask = (box) async {
      asked.add(box);
      return false;
    };
    Addon.box = BoxLink(url: Uri.parse('http://10.42.0.9/'));
    addTearDown(() {
      Addon.box = null;
      BoxKeyringConsent.ask = null;
    });
    final sent = (await options.toAddonAsked(host: 'gw', port: 3671))['secure']! as Map<String, Object?>;
    expect(asked, hasLength(1));
    expect(sent['userPassword'], '');
  });

  test('mit Freigabe wie bisher', () {
    expect(secure(allowed: true)['userId'], 7);
  });
}
