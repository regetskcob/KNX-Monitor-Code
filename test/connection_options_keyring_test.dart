import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/model/connection_options.dart';

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
      ..secureUserPassword = '';
  });

  Map<String, Object?> secure({required bool allowed}) =>
      options.toAddon(host: 'box', port: 3671, keyringAllowed: allowed)['secure']! as Map<String, Object?>;

  test('ohne Freigabe bleibt alles Secure auf der Box unverändert', () {
    final sent = secure(allowed: false);
    expect(sent.containsKey('userId'), isFalse);
    expect(sent['userPassword'], '');
    expect(sent['deviceAuthentication'], '');
  });

  test('selbst Eingegebenes geht auch ohne Freigabe mit', () {
    options.secureUserPassword = 'eingetippt';
    final sent = secure(allowed: false);
    expect(sent['userId'], 7);
    expect(sent['userPassword'], 'eingetippt');
  });

  test('mit Freigabe wie bisher', () {
    expect(secure(allowed: true)['userId'], 7);
  });
}
