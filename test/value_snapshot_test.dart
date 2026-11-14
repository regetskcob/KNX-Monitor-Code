import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/channel_test.dart';
import 'package:knx_monitor/model/handover_check.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/model/lock_prefs.dart';
import 'package:knx_monitor/model/value_snapshot.dart';

final t0 = DateTime(2026, 11, 14, 8);
int ga(String s) => parseGroup(s)!;
int pa(String s) => parseIndividual(s)!;

Telegram bit(int minutes, String dest, int value, {String source = '1.1.10', TelegramType type = TelegramType.write}) =>
    Telegram(
      time: t0.add(Duration(minutes: minutes)),
      source: pa(source),
      destination: ga(dest),
      type: type,
      data: Uint8List.fromList([value]),
      isSmall: true,
    );

String text(Telegram t) => t.data[0] == 1 ? 'Ein' : 'Aus';
Map<int, Telegram> latest(List<Telegram> ts) => {for (final t in ts) t.destination: t};

void main() {
  test('Stand festhalten und vergleichen: geändert, gleich, still, neu, stumme Geräte', () {
    final before = latest([
      bit(0, '1/4/1', 1),
      bit(0, '1/4/2', 0),
      bit(0, '1/4/3', 1, source: '1.1.11'),
      bit(0, '1/4/9', 1, type: TelegramType.read),
    ]);
    final snap = ValueSnapshot.take(before, t0.add(const Duration(minutes: 5)), text: text);
    expect(snap.values.keys, [ga('1/4/1'), ga('1/4/2'), ga('1/4/3')], reason: 'Leseanfragen sind kein Wert');
    expect(snap.devices, {pa('1.1.10'), pa('1.1.11')});

    // Strom war weg: 1.1.10 meldet sich wieder (Kanal 1 jetzt aus), 1.1.11 bleibt stumm.
    final after = latest([
      bit(30, '1/4/1', 0),
      bit(30, '1/4/2', 0),
      bit(0, '1/4/3', 1, source: '1.1.11'),
      bit(31, '1/4/7', 1),
    ]);
    final diff = snap.compare(after, text: text);
    expect(diff.changed.single, (address: ga('1/4/1'), before: 'Ein', after: 'Aus'));
    expect(diff.same, [ga('1/4/2')]);
    expect(diff.quiet, [ga('1/4/3')]);
    expect(diff.fresh, [ga('1/4/7')]);
    expect(diff.silentDevices, [pa('1.1.11')]);
  });

  test('Stand übersteht Speichern und Laden', () {
    final snap = ValueSnapshot.take(latest([bit(0, '1/4/1', 1)]), t0, text: text);
    final again = ValueSnapshot.fromJson((jsonDecode(jsonEncode(snap.toJson())) as Map).cast());
    expect(again.taken, snap.taken);
    expect(again.values[ga('1/4/1')], (raw: 's01', text: 'Ein'));
    expect(again.devices, snap.devices);
  });

  test('Dateien der neuen Werkzeuge gehören zur Anlage: sie ziehen mit um und werden mit ihr gelöscht', () {
    expect(
      InstallationStore.files,
      containsAll([ValueSnapshotStore.path, ChannelTestStore.path, HandoverCheckStore.path, LockPrefs.path]),
    );
  });
}
