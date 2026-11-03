import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/model/box_share.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  List<int>? onBox;
  var writes = 0;
  Future<BoxShareOutcome> sync(String? local) => BoxShare.sync(
    'a',
    'catalog.json',
    local: local,
    readBox: () async => onBox,
    writeBox: (bytes) async {
      onBox = bytes;
      writes++;
    },
  );

  setUp(() {
    onBox = null;
    writes = 0;
  });

  test('Box verpasste eine Änderung (Senden ging ins Leere): wird nachgereicht', () async {
    onBox = utf8.encode('v1');
    await BoxShare.remember('a', 'catalog.json', 'v1');
    expect(await sync('v2'), BoxShareOutcome.pushed);
    expect(utf8.decode(onBox!), 'v2');
    expect(await sync('v2'), BoxShareOutcome.same, reason: 'danach ist nichts mehr zu tun');
    expect(writes, 1);
  });

  test('frische Box ohne Datei bekommt sie', () async {
    expect(await sync('v1'), BoxShareOutcome.pushed);
    expect(utf8.decode(onBox!), 'v1');
  });

  test('auf der Box geändert: nicht überschreiben', () async {
    await BoxShare.remember('a', 'catalog.json', 'v1');
    onBox = utf8.encode('im Browser geändert');
    expect(await sync('v1'), BoxShareOutcome.boxDiffers);
    expect(writes, 0);
  });

  test('nie geteilt und verschieden: nicht raten', () async {
    onBox = utf8.encode('anders');
    expect(await sync('v1'), BoxShareOutcome.boxDiffers);
    expect(writes, 0);
  });

  test('gleicher Inhalt zählt als gemeinsamer Stand für das nächste Mal', () async {
    onBox = utf8.encode('v1');
    expect(await sync('v1'), BoxShareOutcome.same);
    expect(await sync('v2'), BoxShareOutcome.pushed);
  });

  test('hier nichts: Box bleibt', () async {
    onBox = utf8.encode('v1');
    expect(await sync(null), BoxShareOutcome.same);
    expect(writes, 0);
  });
}
