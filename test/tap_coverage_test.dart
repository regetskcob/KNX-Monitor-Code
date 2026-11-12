import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/model/coupler_filter.dart';
import 'package:knx_monitor/model/tap_coverage.dart';
import 'package:knx_monitor/model/tap_points.dart';

void main() {
  int pa(String s) => parseIndividual(s)!;
  int ga(String s) => parseGroup(s)!;

  // 1.1 (tap point 0) and 1.2 (tap point 1) behind coupler 1.2.0.
  final catalog = GroupCatalog({
    // Switched in 1.1, actuator in 1.2: must pass the coupler.
    ga('1/1/72'): GroupInfo(
      address: ga('1/1/72'),
      name: 'Terrasse',
      links: [
        GroupLink(device: pa('1.1.10'), sends: true),
        GroupLink(device: pa('1.2.5')),
      ],
    ),
    // Only in 1.1: nobody in 1.2 listens.
    ga('2/0/1'): GroupInfo(
      address: ga('2/0/1'),
      name: 'Flur',
      links: [
        GroupLink(device: pa('1.1.10'), sends: true),
        GroupLink(device: pa('1.1.20')),
      ],
    ),
  }, devices: {});
  final t0 = DateTime(2026, 11, 9, 12);

  Telegram tg(String dst, int sec, {int tap = 0, List<Sighting> seen = const [], String src = '1.1.10'}) => Telegram(
    time: t0.add(Duration(seconds: sec)),
    source: pa(src),
    destination: ga(dst),
    type: TelegramType.write,
    data: Uint8List.fromList([1]),
    isSmall: true,
    tap: tap,
    sightings: seen,
  );
  const at1 = [Sighting(1, Duration(milliseconds: 2), 5)];
  // Keeps the tap point in 1.2 "up": telegrams of its own line, on an address outside the project.
  final alive = [for (var i = 0; i < 6; i++) tg('9/1/9', i * 60, tap: 1, src: '1.2.30')];

  test('fewer than two lines with a tap point: nothing to say', () {
    expect(TapCoverage.build(catalog, [tg('1/1/72', 0)], ['1.1']), isNull);
    expect(TapCoverage.build(catalog, [tg('1/1/72', 0)], ['1.1', 'Ferienhaus']), isNull);
  });

  test('blocked although 1.2 listens, passed although nobody there listens', () {
    final c = TapCoverage.build(
      catalog,
      [...alive, tg('1/1/72', 10), tg('1/1/72', 70), tg('2/0/1', 20, seen: at1), tg('2/0/1', 80, seen: at1)],
      ['1.1', '1.2'],
    )!;
    expect(c.lines, {0x11, 0x12});
    expect([for (final f in c.blocked) (f.group, f.from, f.to, f.count)], [(ga('1/1/72'), 0x11, 0x12, 2)]);
    expect([for (final f in c.leaked) (f.group, f.from, f.to, f.count)], [(ga('2/0/1'), 0x11, 0x12, 2)]);
  });

  test('passing as it should, or one telegram alone, is no finding', () {
    final c = TapCoverage.build(
      catalog,
      [...alive, tg('1/1/72', 10, seen: at1), tg('1/1/72', 70, seen: at1), tg('2/0/1', 20), tg('2/0/1', 80, seen: at1)],
      ['1.1', '1.2'],
    )!;
    expect(c.isEmpty, isTrue);
  });

  test('while the tap point in 1.2 is down, a missing sighting says nothing', () {
    final c = TapCoverage.build(catalog, [tg('1/1/72', 10), tg('1/1/72', 70), tg('1/1/72', 130)], ['1.1', '1.2'])!;
    expect(c.blocked, isEmpty);
  });

  test('a gap of the tap point in 1.2 is not held against the coupler, whatever it heard around it', () {
    TapStatus p(int i, {bool up = true}) => TapStatus(
      index: i,
      name: '$i',
      label: '1.${i + 1}',
      state: up ? TunnelState.connected : TunnelState.disconnected,
    );
    final gaps = TapGaps()
      ..update([p(0), p(1)], t0)
      ..update([p(0), p(1, up: false)], t0.add(const Duration(seconds: 5)))
      ..update([p(0), p(1)], t0.add(const Duration(seconds: 100)));
    final log = [...alive, tg('1/1/72', 10), tg('1/1/72', 70)];
    // Without knowing the gap the tap point looks alive (it heard its own line around that time).
    expect(TapCoverage.build(catalog, log, ['1.1', '1.2'])!.blocked, hasLength(1));
    expect(TapCoverage.build(catalog, log, ['1.1', '1.2'], gaps: gaps)!.blocked, isEmpty);
    // After the gap the same finding counts again.
    final later = [...alive, tg('1/1/72', 150), tg('1/1/72', 170)];
    expect(TapCoverage.build(catalog, later, ['1.1', '1.2'], gaps: gaps)!.blocked, hasLength(1));
  });

  test('tap points as observation points of the filter table check, each with what it saw', () {
    final log = [
      tg('1/1/72', 10, seen: at1),
      tg('2/0/1', 20),
      tg('9/1/9', 30, tap: 1, src: '1.2.30'),
      tg('1/1/72', 40),
    ];
    final points = tapObservations(log, {0: 0x11, 1: 0x12}, name: (tap) => 'T$tap');
    expect([for (final o in points) (o.name, o.line, o.telegrams.length)], [('T0', 0x11, 3), ('T1', 0x12, 2)]);
    expect(points[1].telegrams.first.hopCount, 5);
    expect(points.every((o) => o.from == log.first.time && o.to == log.last.time), isTrue);
    // A telegram from a time when one of them was away is left out everywhere.
    final without = tapObservations(
      log,
      {0: 0x11, 1: 0x12},
      name: (tap) => 'T$tap',
      away: (tap, time) => tap == 1 && time == log.last.time,
    );
    expect([for (final o in without) o.telegrams.length], [2, 2]);
    // One line only, or tap points without a line: the single live observation as before.
    expect(tapObservations(log, {0: 0x11, 1: 0x11}, name: (tap) => 'T$tap'), isEmpty);
    expect(tapObservations(log, {0: 0x11}, name: (tap) => 'T$tap'), isEmpty);
  });
}
