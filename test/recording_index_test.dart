import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/recording.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';

/// Counts which files are read.
class _Counting implements AppStorage {
  _Counting(this.inner);
  final AppStorage inner;
  final read_ = <String>[];

  @override
  Future<String?> read(String path) {
    read_.add(path);
    return inner.read(path);
  }

  @override
  Future<void> write(String path, String text) => inner.write(path, text);
  @override
  Future<void> append(String path, String text) => inner.append(path, text);
  @override
  Future<List<StoredFile>> list(String dir) => inner.list(dir);
  @override
  Future<void> delete(String path) => inner.delete(path);
}

void main() {
  late Directory dir;
  late _Counting storage;
  final store = RecordingStore.instance;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('knx_recordings');
    AppStorage.instance = storage = _Counting(IoStorage(dir));
    await store.load();
  });
  tearDown(() => dir.delete(recursive: true));

  Recording recording(String id, int telegrams, {String name = 'Aufnahme'}) => Recording(
    id: id,
    name: name,
    started: DateTime(2026, 11, 16, 8),
    ended: DateTime(2026, 11, 16, 9),
    telegrams: [
      for (var i = 0; i < telegrams; i++)
        Telegram(
          time: DateTime(2026, 11, 16, 8, 0, i),
          source: 0x1105,
          destination: 0x0A03,
          type: TelegramType.write,
          data: Uint8List.fromList([1]),
          isSmall: true,
        ),
    ],
  );

  List<String> recordingsRead() => storage.read_.where((p) => p.endsWith('.json')).toList();

  test('Liste kommt aus dem Index, ohne die Aufnahmen zu lesen', () async {
    await store.save(recording('a', 3, name: 'Erste'));
    await store.save(recording('b', 5, name: 'Zweite'));
    storage.read_.clear();

    await store.load();
    expect(recordingsRead(), isEmpty);
    expect({for (final s in store.summaries) s.name: s.count}, {'Erste': 3, 'Zweite': 5});
    expect(await store.count(), 2);
  });

  test('geänderte, neue und gelöschte Dateien am Index vorbei werden bemerkt', () async {
    await store.save(recording('a', 3));
    await store.save(recording('b', 5));
    // As a restore or import writes: straight into the storage.
    await storage.write('recordings/a.json', jsonEncode(recording('a', 40, name: 'Ersetzt').toJson()));
    await storage.write('recordings/c.json', jsonEncode(recording('c', 1, name: 'Neu').toJson()));
    await storage.delete('recordings/b.json');
    storage.read_.clear();

    await store.load();
    expect(recordingsRead(), unorderedEquals(['recordings/a.json', 'recordings/c.json']));
    expect({for (final s in store.summaries) s.name: s.count}, {'Ersetzt': 40, 'Neu': 1});

    storage.read_.clear();
    await store.load();
    expect(recordingsRead(), isEmpty);
  });

  test('kaputter Index: die Aufnahmen werden einmal neu gelesen', () async {
    await store.save(recording('a', 3));
    await storage.write('recordings/index', '{kaputt');
    await store.load();
    expect(store.summaries.single.count, 3);
    await store.delete('a');
    await store.load();
    expect(store.summaries, isEmpty);
  });
}
