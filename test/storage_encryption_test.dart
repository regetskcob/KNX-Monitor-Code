import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/platform/file_cipher.dart';
import 'package:knx_monitor/platform/storage_io.dart';

class _Key implements FileKeySource {
  _Key({this.value, this.fresh = false});
  Uint8List? value;
  bool fresh;
  @override
  Future<Uint8List?> load(Future<void> Function() onCreated) async {
    if (fresh) await onCreated();
    return value;
  }
}

void main() {
  late Directory dir;
  final key = Uint8List.fromList(List.filled(32, 7));

  setUp(() => dir = Directory.systemTemp.createTempSync('enc'));
  tearDown(() => dir.deleteSync(recursive: true));

  IoStorage store([Uint8List? k]) => IoStorage(dir, _Key(value: k ?? key));
  String raw(String p) => File('${dir.path}/$p').readAsStringSync();

  test('schreibt verschlüsselt und liest im Klartext', () async {
    await store().write('a/kunde.json', '{"name":"Müller"}');
    expect(raw('a/kunde.json'), isNot(contains('Müller')));
    expect(raw('a/kunde.json'), startsWith(encryptedHeader));
    expect(await store().read('a/kunde.json'), '{"name":"Müller"}');
  });

  test('alte unverschlüsselte Datei bleibt lesbar und wird beim Schreiben verschlüsselt', () async {
    File('${dir.path}/alt.json').writeAsStringSync('alt');
    final s = store();
    expect(await s.read('alt.json'), 'alt');
    await s.write('alt.json', 'neu');
    expect(raw('alt.json'), isNot(contains('neu')));
    expect(File('${dir.path}/alt.json.prev').existsSync(), isFalse, reason: 'kein Klartext als vorige Fassung');
  });

  test('Anhängen, auch an eine alte Datei', () async {
    File('${dir.path}/h.ndjson').writeAsStringSync('1\n');
    final s = store();
    await s.append('h.ndjson', '2\n');
    await s.append('h.ndjson', '3\n');
    expect(await s.read('h.ndjson'), '1\n2\n3\n');
    expect(raw('h.ndjson'), isNot(contains('2\n3')));
  });

  test('abgerissenes Anhängen kostet nur den letzten Eintrag', () async {
    final s = store();
    await s.append('h.ndjson', 'a\n');
    await s.append('h.ndjson', 'b\n');
    File('${dir.path}/h.ndjson').writeAsStringSync('QUJD', mode: FileMode.append);
    expect(await s.read('h.ndjson'), 'a\nb\n');
  });

  test('beschädigte Datei: vorige Fassung statt Verlust', () async {
    final s = store();
    await s.write('k.json', 'eins');
    await s.write('k.json', 'zwei');
    File('${dir.path}/k.json').writeAsStringSync('${encryptedHeader}kaputt\n');
    expect(await s.read('k.json'), 'eins');
  });

  test('beschädigt ohne vorige Fassung meldet einen Fehler statt leer', () async {
    File('${dir.path}/k.json').writeAsStringSync('${encryptedHeader}kaputt\n');
    expect(() => store().read('k.json'), throwsA(isA<StorageCorruptException>()));
  });

  test('ohne Schlüsselbund wird Verschlüsseltes weder gelesen noch überschrieben', () async {
    await store().write('k.json', 'wichtig');
    final locked = IoStorage(dir, _Key());
    expect(() => locked.read('k.json'), throwsA(isA<StorageLockedException>()));
    await expectLater(locked.write('k.json', 'leer'), throwsA(isA<StorageLockedException>()));
    await expectLater(locked.append('k.json', 'x'), throwsA(isA<StorageLockedException>()));
    expect(await store().read('k.json'), 'wichtig');
  });

  test('ohne Schlüsselbund funktionieren neue Dateien unverschlüsselt', () async {
    final s = IoStorage(dir, _Key());
    await s.write('n.json', 'x');
    expect(await s.read('n.json'), 'x');
    expect(raw('n.json'), 'x');
  });

  test('bestehende Dateien werden verschlüsselt, Einstellungen nicht', () async {
    File('${dir.path}/installations').createSync();
    File('${dir.path}/installations').deleteSync();
    Directory('${dir.path}/installations/a').createSync(recursive: true);
    File('${dir.path}/installations/a/catalog.json').writeAsStringSync('geheim');
    File('${dir.path}/installations.json.bak').writeAsStringSync('geheim2');
    File('${dir.path}/shared_preferences.json').writeAsStringSync('{"x":1}');
    final s = store();
    expect(await s.encryptExisting(), 2);
    expect(await s.encryptExisting(), 0);
    expect(raw('installations/a/catalog.json'), isNot(contains('geheim')));
    expect(raw('shared_preferences.json'), '{"x":1}');
    expect(await s.read('installations/a/catalog.json'), 'geheim');
  });

  test('neuer Schlüssel: alte Dateien liegen beiseite, nichts wird überschrieben', () async {
    await store().write('a/k.json', 'alt');
    final other = Uint8List.fromList(List.filled(32, 9));
    final s = IoStorage(dir, _Key(value: other, fresh: true));
    expect(await s.read('a/k.json'), isNull);
    expect(File('${dir.path}/${IoStorage.quarantineDir}/a/k.json').existsSync(), isTrue);
    await s.write('a/k.json', 'neu');
    expect(await s.read('a/k.json'), 'neu');
  });

  test('große Datei und list ohne Hilfsdateien', () async {
    final s = store();
    final big = 'x' * 400000;
    await s.write('d/g.json', big);
    await s.write('d/g.json', big);
    expect(await s.read('d/g.json'), big);
    expect((await s.list('d')).map((f) => f.name), ['g.json']);
    await s.delete('d/g.json');
    expect(File('${dir.path}/d/g.json.prev').existsSync(), isFalse);
  });

  test('ohne Schlüsselquelle unverändert, aber mit voriger Fassung', () async {
    final s = IoStorage(dir);
    await s.write('p.json', 'a');
    await s.write('p.json', 'b');
    expect(raw('p.json'), 'b');
    expect(raw('p.json.prev'), 'a');
  });

  test('überlappendes Schreiben auf dieselbe Datei wirft nicht', () async {
    final s = store();
    await s.write('r.json', 'start');
    await Future.wait([for (var i = 0; i < 40; i++) s.write('r.json', 'neu')]);
    expect(await s.read('r.json'), 'neu');
  });

  test('gleichzeitiges Schreiben und Verschlüsseln verliert nichts', () async {
    File('${dir.path}/r.json').writeAsStringSync('alt');
    final s = store();
    await Future.wait([s.encryptExisting(), s.write('r.json', 'neu')]);
    expect(await s.read('r.json'), 'neu');
  });

  test('Schreiben trifft das Verschlüsseln an jeder Stelle: Neues gewinnt', () async {
    for (var round = 0; round < 30; round++) {
      File('${dir.path}/w$round.json').writeAsStringSync('alt');
      final s = store();
      final encrypting = s.encryptExisting(pause: (_) async {});
      // Jedes Mal etwas später, damit das Schreiben alle Lücken des Ablaufs trifft.
      await Future<void>.delayed(Duration(microseconds: round * 300));
      await s.write('w$round.json', 'neu');
      await encrypting;
      expect(await s.read('w$round.json'), 'neu', reason: 'Runde $round');
    }
  });
}
