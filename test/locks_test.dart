import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/device_channels.dart';
import 'package:knx_monitor/model/locks.dart';

int ga(String s) => parseGroup(s)!;
final t0 = DateTime(2026, 11, 13, 14);
final weather = parseIndividual('1.2.20')!;
final button = parseIndividual('1.1.30')!;
final blind = parseIndividual('1.1.12')!;

Telegram bit(int minutes, String dest, int value, {int? source, TelegramType type = TelegramType.write}) => Telegram(
  time: t0.add(Duration(minutes: minutes)),
  source: source ?? weather,
  destination: ga(dest),
  type: type,
  data: Uint8List.fromList([value]),
  isSmall: true,
);

void main() {
  late GroupCatalog catalog;

  setUp(() {
    GroupInfo g(String a, String name, Dpt dpt, {List<GroupLink> links = const []}) =>
        GroupInfo(address: ga(a), name: name, dpt: dpt, links: links);
    catalog = GroupCatalog({
      for (final x in [
        g(
          '3/3/0',
          'Küche Rollladen Sperre',
          const Dpt(1, 1),
          links: [
            GroupLink(device: blind, text: 'Kanal A – Sperren'),
            GroupLink(device: weather, sends: true),
          ],
        ),
        g('1/3/1', 'Flur PM Freigabe', const Dpt(1, 3)),
        g('1/3/2', 'Bad Licht Enable', const Dpt(1, 1)),
        g(
          '3/1/0',
          'Küche Rollladen Auf/Ab fahren',
          const Dpt(1, 8),
          links: [GroupLink(device: blind, text: 'Kanal A – Auf/Ab')],
        ),
        g('1/0/1', 'Küche Decke Schalten', const Dpt(1, 1)),
        g('2/0/1', 'Sperrzeit Minuten', const Dpt(5, 10)),
      ])
        x.address: x,
    });
    CatalogStore.instance.catalog = catalog;
  });

  test('Sperradressen am Namen und Typ; Sperre sperrt bei 1, Freigabe bei 0', () {
    LockSense? sense(String a) => lockSense(catalog[ga(a)]!, catalog[ga(a)]!.dpt);
    expect(sense('3/3/0'), LockSense.lockOnOne);
    expect(sense('1/3/1'), LockSense.lockOnZero);
    expect(sense('1/3/2'), LockSense.lockOnZero);
    expect(sense('1/0/1'), isNull);
    expect(sense('2/0/1'), isNull, reason: 'kein 1-Bit');
    expect(
      lockSense(catalog[ga('3/3/0')]!, const Dpt(1, 1), inverted: {ga('3/3/0')}),
      LockSense.lockOnZero,
      reason: 'von Hand umgedreht',
    );
  });

  test('Wer hat wann gesperrt, wer wann gelöst; zyklisches Wiederholen zählt nicht neu', () {
    final tracks = lockTracks(catalog, [
      bit(0, '3/3/0', 1),
      bit(5, '3/3/0', 1),
      bit(10, '3/3/0', 1),
      bit(29, '3/3/0', 0, source: button),
      bit(40, '3/3/0', 0),
      bit(60, '3/3/0', 1),
    ]);
    final t = tracks.firstWhere((t) => t.address == ga('3/3/0'));
    expect(t.targets, [blind], reason: 'wirkt auf den Jalousieaktor, die Wetterstation sendet nur');
    expect(t.spans, hasLength(2));
    final first = t.spans.first;
    expect((first.start.source, first.end!.source, first.repeats), (weather, button, 2));
    expect(first.length(t0), const Duration(minutes: 29));
    expect(t.locked, isTrue);
    expect(t.active!.length(t0.add(const Duration(minutes: 90))), const Duration(minutes: 30));
    expect(tracks.first.address, ga('3/3/0'), reason: 'Gesperrtes zuerst');
  });

  test('Freigabe: 0 sperrt, 1 löst; Leseanfragen sagen nichts, Antworten nur „seit mindestens“', () {
    final tracks = lockTracks(catalog, [
      bit(0, '1/3/1', 0, type: TelegramType.read),
      bit(1, '1/3/1', 0, type: TelegramType.response),
      bit(20, '1/3/1', 1),
    ]);
    final t = tracks.firstWhere((t) => t.address == ga('1/3/1'));
    expect(t.spans.single.sinceAtLeast, isTrue);
    expect(t.locked, isFalse);
    final idle = tracks.firstWhere((t) => t.address == ga('1/3/2'));
    expect(idle.locked, isNull, reason: 'nichts gehört');
  });

  test('Aktive Sperre eines Kanals über sein Sperrobjekt', () {
    final channel = channelsOf(blind, catalog).first;
    expect(activeLockOf(channel, lockTracks(catalog, [bit(0, '3/3/0', 1)]))!.address, ga('3/3/0'));
    expect(activeLockOf(channel, lockTracks(catalog, [bit(0, '3/3/0', 1), bit(1, '3/3/0', 0)])), isNull);
  });
}
