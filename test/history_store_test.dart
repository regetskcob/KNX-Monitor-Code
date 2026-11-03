import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/history_store.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;
  final store = HistoryStore.instance;

  setUp(() async {
    HistoryStore.recordingAllowed = () => true;
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('knx_history');
    AppStorage.instance = IoStorage(dir);
    await store.load();
  });

  tearDown(() => dir.delete(recursive: true));

  Telegram t(DateTime time, int value) => Telegram(
    time: time,
    source: 0x1105,
    destination: 0x1001,
    type: TelegramType.write,
    data: Uint8List.fromList([value]),
    isSmall: true,
  );

  group('Stufe ohne Langzeitverlauf', () {
    test('pausiert: nichts Neues, Vorhandenes bleibt', () async {
      await store.setRetention(7);
      store.add(t(DateTime.now(), 1));
      await store.flush();
      expect(await store.days(), hasLength(1));

      HistoryStore.recordingAllowed = () => false;
      expect(store.paused, isTrue);
      store.add(t(DateTime.now(), 0));
      await store.flush();
      await store.load();
      final days = await store.days();
      expect(days, hasLength(1), reason: 'bleibt auch über das Aufräumen beim Laden');
      expect(days.single.bytes, greaterThan(0));
      final before = days.single.bytes;

      HistoryStore.recordingAllowed = () => true;
      expect(store.paused, isFalse);
      store.add(t(DateTime.now(), 0));
      await store.flush();
      expect((await store.days()).single.bytes, greaterThan(before));
    });

    test('ohne Aufbewahrung gilt nicht als pausiert', () async {
      HistoryStore.recordingAllowed = () => false;
      await store.setRetention(0);
      expect(store.paused, isFalse);
    });
  });

  test('aus: nichts wird geschrieben', () async {
    store.add(t(DateTime.now(), 1));
    await store.flush();
    expect(await store.days(), isEmpty);
  });

  test('schreibt je Tag, öffnet als Aufnahme, löscht außerhalb der Aufbewahrung', () async {
    await store.setRetention(3);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 12);
    store
      ..add(t(today, 1))
      ..add(t(today.add(const Duration(seconds: 1)), 0))
      ..add(t(today.subtract(const Duration(days: 1)), 1))
      ..add(t(today.subtract(const Duration(days: 5)), 1)); // außerhalb
    await store.flush();
    var days = await store.days();
    expect(days, hasLength(3));

    // Abgebrochene Zeile am Ende (App beendet) wird übersprungen.
    await AppStorage.instance.append(days.first.path, '{"t": 1');
    final r = await store.open(days.first, name: 'Heute');
    expect(r.telegrams, hasLength(2));
    expect(r.telegrams.last.data, [0]);

    await store.load(); // Aufräumen beim Start
    days = await store.days();
    expect(days.map((d) => d.date.day), [today.day, today.subtract(const Duration(days: 1)).day]);

    await store.setRetention(0); // aus = löschen
    expect(await store.days(), isEmpty);
  });

  test('Abschnitt ohne Uhr: eigene Liste, Abstände aus dem Monotonzähler, kein erfundenes Datum', () async {
    final history = Directory('${dir.path}/installations/default/history')..createSync(recursive: true);
    File('${history.path}/unsynced-100-200.ndjson').writeAsStringSync(
      '{"t":5000000,"mono":1000000,"s":1,"d":2,"y":2,"x":"01"}\n'
      '{"t":1000,"mono":3000000,"s":1,"d":2,"y":2,"x":"00"}\n',
    );
    expect(await store.days(), isEmpty, reason: 'gehört in keinen Tag');
    final found = await store.withoutTime();
    expect(found.single.withoutTime, isTrue);
    final recording = await store.open(found.single, name: 'x');
    expect(recording.telegrams, hasLength(2));
    expect(
      recording.telegrams[1].time.difference(recording.telegrams[0].time),
      const Duration(seconds: 2),
      reason: 'Systemzeit sprang rückwärts',
    );
  });
}
