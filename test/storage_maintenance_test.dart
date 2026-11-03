import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/platform/file_cipher.dart';
import 'package:knx_monitor/platform/storage_io.dart';

class _Key implements FileKeySource {
  _Key(this.key);
  final Uint8List key;
  @override
  Future<Uint8List?> load(Future<void> Function() onCreated) async => key;
}

/// Schlüssel fehlt: Beim Laden entsteht ein neuer und legt alles beiseite.
class _NewKey implements FileKeySource {
  @override
  Future<Uint8List?> load(Future<void> Function() onCreated) async {
    await onCreated();
    return Uint8List(32);
  }
}

void main() {
  late Directory dir;
  final key = Uint8List.fromList(List.generate(32, (i) => 255 - i));

  setUp(() async => dir = await Directory.systemTemp.createTemp('maintenance'));
  tearDown(() => dir.delete(recursive: true));

  group('Schlüssel', () {
    test('wirft das Lesen, entsteht kein neuer und nichts wird beiseitegelegt', () async {
      var created = 0;
      final source = KeychainFileKey(
        read: (_) => throw StateError('Keystore kaputt'),
        write: (_, _) async => fail('kein neuer Schlüssel'),
        recheck: Duration.zero,
      );
      expect(await source.load(() async => created++), isNull);
      expect(created, 0);
    });

    test('wirft das Lesen beim zweiten Blick, bleibt es ebenso', () async {
      var reads = 0;
      var created = 0;
      final source = KeychainFileKey(
        read: (_) async => reads++ == 0 ? null : throw StateError('weg'),
        write: (_, _) async => fail('kein neuer Schlüssel'),
        recheck: Duration.zero,
      );
      expect(await source.load(() async => created++), isNull);
      expect(created, 0);
    });

    test('taucht er beim zweiten Blick auf, wird er benutzt', () async {
      var reads = 0;
      final stored = base64Encode(key);
      final source = KeychainFileKey(
        read: (_) async => reads++ == 0 ? null : stored,
        write: (_, _) async => fail('kein neuer Schlüssel'),
        recheck: Duration.zero,
      );
      expect(await source.load(() async => fail('nichts beiseitelegen')), key);
    });

    test('nur wenn er wirklich fehlt: neuer Schlüssel und beiseitelegen', () async {
      String? stored;
      var created = 0;
      final source = KeychainFileKey(
        read: (_) async => stored,
        write: (_, v) async => stored = v,
        recheck: Duration.zero,
      );
      expect(await source.load(() async => created++), isNotNull);
      expect(created, 1);
    });

    test('Beiseitegelegtes wird gezählt und lässt sich löschen', () async {
      final old = IoStorage(dir, _Key(key));
      await old.write('installations/a/catalog.json', 'eins');
      await old.write('installations/a/catalog.json', 'zwei');
      final s = IoStorage(dir, _NewKey());
      expect(await s.read('installations/a/catalog.json'), isNull);
      final extras = await s.extras();
      expect(extras.quarantinedFiles, 2, reason: 'samt voriger Fassung');
      expect(extras.quarantinedBytes, greaterThan(0));
      await s.deleteQuarantined();
      expect((await s.extras()).quarantinedFiles, 0);
    });
  });

  group('Neben den Daten', () {
    test('große Dateien behalten keine vorige Fassung', () async {
      final limit = IoStorage.maxPrevBytes;
      addTearDown(() => IoStorage.maxPrevBytes = limit);
      IoStorage.maxPrevBytes = 100;
      final s = IoStorage(dir);
      await s.write('klein.json', 'a');
      await s.write('klein.json', 'b');
      expect(File('${dir.path}/klein.json.prev').readAsStringSync(), 'a');
      await s.write('gross.json', 'a');
      await s.write('gross.json', 'x' * 200);
      expect(File('${dir.path}/gross.json.prev').readAsStringSync(), 'a');
      await s.write('gross.json', 'y' * 200);
      expect(File('${dir.path}/gross.json.prev').existsSync(), isFalse, reason: 'auch die alte weg');
      expect(await s.read('gross.json'), 'y' * 200);
    });

    test('.corrupt-* taucht in list() nicht auf, ihre Größe in extras()', () async {
      final s = IoStorage(dir);
      await s.write('d/a.json', 'gut');
      await s.write('d/a.json.corrupt-1', 'kaputt');
      expect((await s.list('d')).map((f) => f.name), ['a.json']);
      final extras = await s.extras();
      expect(extras.corruptBytes, 6);
    });

    test('alte .corrupt-* verschwinden, die jüngste je Datei bleibt', () async {
      final s = IoStorage(dir);
      final now = DateTime(2026, 10, 31);
      File stamp(String name, int daysAgo) {
        final f = File('${dir.path}/$name')..writeAsStringSync('x');
        f.setLastModifiedSync(now.subtract(Duration(days: daysAgo)));
        return f;
      }

      final oldest = stamp('a.json.corrupt-1', 90);
      final old = stamp('a.json.corrupt-2', 60);
      final recent = stamp('a.json.corrupt-3', 5);
      final alone = stamp('b.json.corrupt-1', 90);
      final staleTmp = stamp('c.json.1-1.tmp', 3);
      final freshTmp = stamp('c.json.1-2.tmp', 0);
      await s.cleanSideFiles(now: now);
      expect(oldest.existsSync(), isFalse);
      expect(old.existsSync(), isFalse);
      expect(recent.existsSync(), isTrue);
      expect(alone.existsSync(), isTrue, reason: 'die einzige, also die jüngste');
      expect(staleTmp.existsSync(), isFalse);
      expect(freshTmp.existsSync(), isTrue);
    });
  });

  group('Verschlüsseln im Bestand', () {
    test('macht nach einem Abbruch weiter und fasst Fertiges nicht an', () async {
      File('${dir.path}/fertig.json').writeAsStringSync('$encryptedHeader${encryptRecord(key, 'schon')}');
      final done = File('${dir.path}/fertig.json').readAsStringSync();
      File('${dir.path}/offen.json').writeAsStringSync('klartext');
      final s = IoStorage(dir, _Key(key));
      expect(await s.encryptExisting(pause: (_) async {}), 1);
      expect(File('${dir.path}/fertig.json').readAsStringSync(), done);
      expect(File('${dir.path}/offen.json').readAsStringSync(), startsWith(encryptedHeader));
      expect(await s.read('offen.json'), 'klartext');
      expect(await IoStorage(dir, _Key(key)).encryptExisting(pause: (_) async {}), 0);
    });

    test('pausiert nach jeder Datei mindestens so lange, wie sie gedauert hat', () async {
      for (var i = 0; i < 3; i++) {
        File('${dir.path}/f$i.json').writeAsStringSync('x' * 1000);
      }
      final pauses = <Duration>[];
      await IoStorage(dir, _Key(key)).encryptExisting(pause: (d) async => pauses.add(d));
      expect(pauses, hasLength(3));
      expect(pauses.every((d) => d >= const Duration(milliseconds: 20)), isTrue);
    });
  });
}
