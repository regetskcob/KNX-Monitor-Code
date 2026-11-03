import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/fault_hunt.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/model/recording.dart';
import 'package:knx_monitor/model/watch_rules.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';

void main() {
  late Directory dir;
  final blind = parseGroup('1/2/3')!;
  final now = DateTime(2026, 10, 27, 23);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fault_hunt');
    AppStorage.instance = IoStorage(dir);
    CatalogStore.instance.catalog = GroupCatalog({
      blind: GroupInfo(address: blind, name: 'Rollladen Wohnzimmer Auf/Ab', dpt: const Dpt(1, 8)),
    });
  });

  tearDown(() async {
    CatalogStore.instance.catalog = GroupCatalog.empty;
    await dir.delete(recursive: true);
  });

  test('Aus Wächtern: nur prüfbare Regeln, Zeitfenster, JSON und Beenden', () {
    final hunt = FaultHuntDef.fromWatchers(
      [WatchRule(id: 'w1', address: blind)],
      name: 'Rollladen nachts',
      duration: const Duration(days: 7),
      from: 22 * 60,
      to: 6 * 60,
      now: now,
    );
    expect(hunt.rules, hasLength(1));
    expect(hunt.rules.single['check'], isNotNull);
    expect(hunt.rules.single['address'], blind);
    final json = hunt.toJson();
    expect(json['window'], [1320, 360]);
    final back = FaultHuntDef.fromJson(jsonDecode(jsonEncode(json)) as Map<String, Object?>);
    expect(back.until, now.add(const Duration(days: 7)));
    expect(back.activeAt(now.add(const Duration(days: 1))), isTrue);
    expect(back.stopped(now).activeAt(now.add(const Duration(minutes: 1))), isFalse);
  });

  test('Treffer lesen, Absender zählen, Fenster als Aufnahme mit Kommentaren', () async {
    const client = FaultHuntClient();
    final hunt = FaultHuntDef.fromWatchers(
      [WatchRule(id: 'w1', address: blind)],
      name: 'Rollladen nachts',
      duration: const Duration(days: 7),
      now: now,
    );
    await client.start(hunt);
    expect((await client.current())?.id, hunt.id);

    final storage = InstallationStore.instance.storage;
    Map<String, Object?> line(DateTime t, int source) => {
      't': t.microsecondsSinceEpoch,
      's': source,
      'd': blind,
      'y': 2,
      'x': '01',
      'm': true,
    };
    final first = now.add(const Duration(minutes: 5));
    await storage.write(
      'hunts/${hunt.id}/a.ndjson',
      [line(first.subtract(const Duration(seconds: 30)), 0x1105), line(first, 0x1107)].map(jsonEncode).join('\n'),
    );
    Map<String, Object?> hit(DateTime t, int source) => {
      't': t.microsecondsSinceEpoch,
      'label': '1/2/3 = Auf',
      'd': blind,
      's': source,
      'x': '01',
    };
    await storage.write(
      'hunts/${hunt.id}/hits.ndjson',
      '${jsonEncode({
        'file': 'a.ndjson',
        'hits': [hit(first, 0x1107)],
      })}\n${jsonEncode({
        'file': 'b.ndjson',
        'hits': [hit(first.add(const Duration(days: 1)), 0x1107), hit(first.add(const Duration(days: 1)), 0x1105)],
      })}\n',
    );

    final windows = await client.windows(hunt.id);
    expect(windows.map((w) => w.file), ['b.ndjson', 'a.ndjson'], reason: 'neueste zuerst');
    expect(huntSenders(windows).first, (0x1107, 2));

    final recording = await client.save(hunt, windows.last);
    expect(recording.telegrams, hasLength(2));
    expect(recording.annotations.single.note, '1/2/3 = Auf');
    expect(recording.annotations.single.time, first);
    final stored = await RecordingStore.instance.open(recording.id);
    expect(stored.telegrams.last.source, 0x1107);
  });
}
