import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/model/box_connection.dart';
import 'package:knx_monitor/platform/addon.dart';
import 'package:knx_monitor/platform/box_link.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('langsamer Schlüsselbund beim Start überschreibt keine neue Kopplung', () async {
    SharedPreferences.setMockInitialValues({});
    final slowRead = Completer<String?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'read' ? slowRead.future : null,
    );
    addTearDown(() async {
      await BoxConnection.instance.forget();
      Addon.box = null;
    });

    final loading = BoxConnection.instance.load();
    await pumpEventQueue();
    final link = BoxLink(url: Uri.parse('http://192.168.1.83/'), name: 'Box', key: 'schluessel');
    await BoxConnection.instance.use(link);

    slowRead.complete(null);
    await loading;

    expect(Addon.box, same(link));
    expect(BoxConnection.instance.saved, same(link));
  });
}
