import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/heating_check.dart';

int ga(String s) => parseGroup(s)!;
final now = DateTime(2026, 11, 13, 20);

Telegram temp(String dest, double value, {Duration ago = Duration.zero}) => Telegram(
  time: now.subtract(ago),
  source: parseIndividual('1.1.30')!,
  destination: ga(dest),
  type: TelegramType.write,
  data: Uint8List.fromList(encodeDpt9(value)!),
  isSmall: false,
);

Telegram percent(String dest, int value, {Duration ago = Duration.zero}) => Telegram(
  time: now.subtract(ago),
  source: parseIndividual('1.1.13')!,
  destination: ga(dest),
  type: TelegramType.write,
  data: Uint8List.fromList([(value * 255 / 100).round()]),
  isSmall: false,
);

void main() {
  late GroupCatalog catalog;

  setUp(() {
    GroupInfo g(String a, String name, Dpt dpt) => GroupInfo(address: ga(a), name: name, dpt: dpt);
    catalog = GroupCatalog({
      for (final x in [
        g('2/0/1', 'OG Bad Ist-Temperatur', const Dpt(9, 1)),
        g('2/1/1', 'OG Bad Soll-Temperatur', const Dpt(9, 1)),
        g('2/2/1', 'OG Bad Stellwert Heizen (%)', const Dpt(5, 1)),
        g('2/0/2', 'OG Kind Ist-Temperatur', const Dpt(9, 1)),
        g('2/1/2', 'OG Kind Soll-Temperatur', const Dpt(9, 1)),
        g('2/2/2', 'OG Kind Stellwert Heizen (%)', const Dpt(5, 1)),
        g('4/0/0', 'Außentemperatur', const Dpt(9, 1)),
        g('4/0/1', 'Vorlauf Temperatur', const Dpt(9, 1)),
        g('1/0/1', 'OG Bad Licht Schalten', const Dpt(1, 1)),
      ])
        x.address: x,
    });
    CatalogStore.instance.catalog = catalog;
  });

  List<HeatingRoom> check(List<Telegram> history) =>
      checkHeating(catalog, {for (final t in history) t.destination: t}, history, now: now);

  test('Rollen nach Typ und Name; Außen- und Anlagentemperaturen zählen nicht', () {
    Dpt? d(String a) => catalog[ga(a)]!.dpt;
    expect(heatingRole(catalog[ga('2/0/1')]!, d('2/0/1')), HeatingRole.actual);
    expect(heatingRole(catalog[ga('2/1/1')]!, d('2/1/1')), HeatingRole.setpoint);
    expect(heatingRole(catalog[ga('2/2/1')]!, d('2/2/1')), HeatingRole.valve);
    expect(heatingRole(catalog[ga('4/0/0')]!, d('4/0/0')), isNull);
    expect(heatingRole(catalog[ga('4/0/1')]!, d('4/0/1')), isNull);
    expect(heatingRole(catalog[ga('1/0/1')]!, d('1/0/1')), isNull);
  });

  test('Räume mit ihren drei Werten; ohne Telegramme „noch nichts gehört“', () {
    final rooms = check([]);
    expect(rooms.map((r) => r.room), ['OG Bad', 'OG Kind']);
    expect(rooms.every((r) => r.verdict == HeatingVerdict.noData), isTrue);
  });

  test('In Ordnung, heizt gerade, fordert nicht an, überheizt', () {
    HeatingVerdict bad(double ist, double soll, int valve) =>
        check([temp('2/0/1', ist), temp('2/1/1', soll), percent('2/2/1', valve)]).first.verdict;
    expect(bad(21.3, 21.5, 20), HeatingVerdict.ok);
    expect(bad(19.0, 21.5, 80), HeatingVerdict.heating);
    expect(bad(19.0, 21.5, 0), HeatingVerdict.notCalling);
    expect(bad(24.0, 21.5, 60), HeatingVerdict.overheating);
    expect(bad(24.0, 21.5, 0), HeatingVerdict.ok, reason: 'warm, Ventil zu: Sonne oder Nachbarraum');
  });

  test('Ventil lange offen, Raum wird nicht wärmer: Antrieb oder Hydraulik', () {
    final flat = check([
      temp('2/0/1', 18.9, ago: const Duration(hours: 2)),
      percent('2/2/1', 100, ago: const Duration(hours: 2)),
      temp('2/1/1', 21.5, ago: const Duration(hours: 2)),
      percent('2/2/1', 100, ago: const Duration(minutes: 30)),
      temp('2/0/1', 19.0),
    ]);
    expect(flat.first.verdict, HeatingVerdict.notWarming);

    final rising = check([
      temp('2/0/1', 17.5, ago: const Duration(hours: 2)),
      temp('2/1/1', 21.5, ago: const Duration(hours: 2)),
      percent('2/2/1', 100, ago: const Duration(minutes: 30)),
      temp('2/0/1', 19.0),
    ]);
    expect(rising.first.verdict, HeatingVerdict.heating);

    final short = check([temp('2/0/1', 19.0), temp('2/1/1', 21.5), percent('2/2/1', 100)]);
    expect(short.first.verdict, HeatingVerdict.heating, reason: 'Aufzeichnung reicht nicht weit genug zurück');
  });

  test('Ist-Temperatur seit Stunden nicht gesendet: der Regler ist blind', () {
    final rooms = check([
      temp('2/0/1', 20.0, ago: const Duration(hours: 5)),
      temp('2/1/1', 21.5),
      percent('2/2/1', 100),
    ]);
    expect(rooms.first.verdict, HeatingVerdict.staleActual);
    expect(rooms.first.verdict.issue, isTrue);
  });

  test('Soll fehlt: Werte ja, Urteil nein', () {
    expect(check([temp('2/0/2', 20.0), percent('2/2/2', 40)]).last.verdict, HeatingVerdict.incomplete);
  });
}
