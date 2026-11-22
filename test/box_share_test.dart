import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/model/box_share.dart';
import 'package:knx_monitor/platform/addon.dart';
import 'package:knx_monitor/platform/box_link.dart';
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

  group('unverschlüsselte Box', () {
    setUp(() => Addon.box = BoxLink(url: Uri.parse('http://192.168.1.50/'), key: 'testzugang'));
    tearDown(() => Addon.box = null);

    test('geteilte Datei fehlt plötzlich: könnte ein fremdes Gerät sein, nichts geht hin', () async {
      await BoxShare.remember('a', 'catalog.json', 'v1');
      expect(await sync('v1'), BoxShareOutcome.boxDiffers);
      expect(writes, 0);
    });

    test('hält sie den letzten Stand, ist es die Box: Änderung wird nachgereicht', () async {
      onBox = utf8.encode('v1');
      await BoxShare.remember('a', 'catalog.json', 'v1');
      expect(await sync('v2'), BoxShareOutcome.pushed);
    });

    test('noch nie geteilt (frisch gekoppelt): bekommt die Datei', () async {
      expect(await sync('v1'), BoxShareOutcome.pushed);
    });
  });

  test('Box mit Zertifikat: fehlende Datei wird wie bisher ersetzt', () async {
    Addon.box = BoxLink(url: Uri.parse('http://192.168.1.50/'), key: 'testzugang', fp: 'A' * 43);
    addTearDown(() => Addon.box = null);
    await BoxShare.remember('a', 'catalog.json', 'v1');
    expect(await sync('v1'), BoxShareOutcome.pushed);
  });

  test('hier nichts: Box bleibt', () async {
    onBox = utf8.encode('v1');
    expect(await sync(null), BoxShareOutcome.same);
    expect(writes, 0);
  });
}
