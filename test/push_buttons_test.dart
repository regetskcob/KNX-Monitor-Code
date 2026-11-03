import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/device_channels.dart';
import 'package:knx_monitor/model/push_buttons.dart';

void main() {
  final glass = parseIndividual('1.1.50')!;
  final smart = parseIndividual('1.1.51')!;
  final light = parseIndividual('1.1.52')!;
  final input = parseIndividual('1.1.53')!;
  final actuator = parseIndividual('1.1.5')!;

  // Wie im Projekt mit MDT Glastaster II Smart, Taster Smart 55 und Light 55.
  GroupCatalog catalog() {
    final groups = <int, GroupInfo>{};
    void ga(String a, String name, Dpt dpt, List<GroupLink> links) =>
        groups[parseGroup(a)!] = GroupInfo(address: parseGroup(a)!, name: name, dpt: dpt, links: links);
    GroupLink k(int d, int o, String? text, {bool sends = false}) =>
        GroupLink(device: d, object: o, text: text, sends: sends);
    ga('1/1/1', 'EG FL L02 Schalten', const Dpt(1, 1), [k(glass, 0, 'T1: L01 An/Aus', sends: true)]);
    ga('1/4/1', 'EG FL L02 Rückmeldung Schalten', const Dpt(1, 1), [
      k(actuator, 3, null, sends: true),
      k(glass, 1, 'T1: L01 An/Aus'),
    ]);
    ga('1/1/0', 'EG FL L01 Schalten', const Dpt(1, 1), [k(glass, 5, 'T2: Garderobe Dimmen', sends: true)]);
    ga('1/2/0', 'EG FL L01 Dimmen', const Dpt(3, 7), [k(glass, 6, 'T2: Garderobe Dimmen', sends: true)]);
    ga('1/5/0', 'EG FL L01 Rückmeldung Wert', const Dpt(5, 1), [k(glass, 8, 'T2: Garderobe Dimmen')]);
    ga('3/1/0', 'EG FL F01 Auf/Ab fahren', const Dpt(1, 8), [k(glass, 20, 'T5/6: Rollladen', sends: true)]);
    ga('3/4/0', 'EG FL F01 Aktuelle Position', const Dpt(5, 1), [k(glass, 23, 'T5/6: Rollladen')]);
    ga('2/3/0', 'EG FL Basis-Komfort Sollwert', const Dpt(9, 1), [k(glass, 30, 'T7/8: Heizung', sends: true)]);
    // Im Projekt mit DPT 1.002 statt 1.008 – Rollladen am Namen erkennen.
    ga('3/1/6', 'EG KÜ F01 Auf/Ab fahren', const Dpt(1, 2), [k(glass, 40, 'T9/10: Sitzbank', sends: true)]);
    ga('3/4/6', 'EG KÜ F01 Aktuelle Position', const Dpt(5, 1), [k(glass, 43, 'T9/10: Sitzbank')]);
    ga('2/0/0', 'EG FL Ist-Temperatur', const Dpt(9, 1), [k(glass, 108, null, sends: true)]);
    ga('8/1/2', 'Außentemperatur', const Dpt(9, 1), [k(glass, 122, null), k(smart, 68, null)]);
    // Smart 55: Rückmeldung als sendend exportiert, aber so benannt.
    ga('1/1/2', 'EG WC L01 Schalten', const Dpt(1, 1), [k(smart, 2, 'T1: WC Licht An/Aus', sends: true)]);
    ga('1/4/2', 'EG WC L01 Rückmeldung Schalten', const Dpt(1, 1), [k(smart, 2, 'T1: WC Licht An/Aus', sends: true)]);
    ga('3/0/9', 'Rollladen WC/TE Auf/Ab fahren', const Dpt(1, 8), [k(smart, 2, 'T3/4: ROL Auf/Ab', sends: true)]);
    // Light 55: Wippe schaltet ohne Rückmeldung.
    ga('1/1/27', 'GA L01 Schalten', const Dpt(1, 1), [k(light, 0, 'T1/2: Licht GA', sends: true)]);
    ga('3/0/30', 'Garagentor Impuls senden', const Dpt(1, 1), [
      k(light, 20, 'T3: Tor', sends: true),
      k(light, 30, 'T4: Tor', sends: true),
    ]);
    ga('4/1/2', 'EG WC F01 Geöffnet', const Dpt(1, 19), [k(input, 0, 'Eingang 1', sends: true)]);
    DeviceInfo dev(int a, String product) => DeviceInfo(address: a, name: product, product: product);
    return GroupCatalog(
      groups,
      devices: {
        glass: dev(glass, 'BE-GT2Tx.01 Glastaster II Smart mit Temperatursensor'),
        smart: dev(smart, 'BE-TAS55T4.01 Taster Smart 55 4-fach mit Temperatursensor'),
        light: dev(light, 'BE-TAL55T2.01 Taster Light 55 2-fach mit Temperatursensor'),
        input: dev(input, 'BE-04001.02 Tasterinterface 4-fach, UP, Ausführung potentialfrei'),
        actuator: dev(actuator, 'AKS-2016.03 Schaltaktor 20-fach, 12TE, 16A'),
      },
    );
  }

  late GroupCatalog c;
  setUp(() => CatalogStore.instance.catalog = c = catalog());

  Telegram tg(String ga, List<int> data, {int? from, bool small = true, int second = 0}) => Telegram(
    time: DateTime(2026, 10, 21, 12, 0, second),
    source: from ?? glass,
    destination: parseGroup(ga)!,
    type: TelegramType.write,
    data: Uint8List.fromList(data),
    isSmall: small,
  );

  test('Tasten aus Objekttexten', () {
    expect(keysOf('T1: L01 An/Aus'), (1, null));
    expect(keysOf('T5/6: Rollladen'), (5, 6));
    expect(keysOf('T11/12: Rollladen zentral'), (11, 12));
    expect(keysOf('Taste 3 kurz'), (3, null));
    expect(keysOf('Wippe 2: Licht'), (3, 4));
    expect(keysOf('Tag / Nacht'), isNull);
    expect(keysOf('Temperatur'), isNull);
    expect(keysOf(null), isNull);
  });

  test('Glastaster: Bauform, Ebenen, Funktionen, Temperatur', () {
    final b = pushButtonOf(glass, c)!;
    expect(b.style, PanelStyle.glass);
    expect(b.keysPerPage, 6);
    expect(b.pages, 2);
    expect(b.functions.map((f) => f.label), ['T1', 'T2', 'T5/6', 'T7/8', 'T9/10']);
    expect(b.functions.first.channel.title, 'L01 An/Aus');
    expect(b.slotOf(8), (1, 1));
    expect(b.temperature, parseGroup('2/0/0'));
    // Status: Rückmeldung (empfangen), beim Dimmen auch der Wert; nicht die Position.
    expect(b.functions[0].status, [parseGroup('1/4/1')]);
    expect(b.functions[1].status, [parseGroup('1/5/0')]);
    expect(b.functions[2].status, isEmpty);
  });

  test('Rahmen 55: Tastenzahl aus Produkt und Belegung, Rückmeldung am Namen', () {
    final s55 = pushButtonOf(smart, c)!;
    expect(s55.style, PanelStyle.frame55);
    expect(s55.keysPerPage, 4);
    expect(s55.functions[0].status, [parseGroup('1/4/2')]);
    final l55 = pushButtonOf(light, c)!;
    expect(l55.keysPerPage, 4);
    expect(l55.functions.map((f) => f.label), ['T1/2', 'T3', 'T4']);
    expect(l55.functions[0].status, isEmpty);
    // Tasterinterface und Aktor bleiben Reiheneinbau-Zeichnung.
    expect(pushButtonOf(input, c), isNull);
    expect(pushButtonOf(actuator, c), isNull);
  });

  test('Gedrückte Taste aus dem Telegramm', () {
    final b = pushButtonOf(glass, c)!;
    final [t1, t2, blind, heat, bench] = b.functions;
    expect(pressedKey(t1, glass, tg('1/1/1', [1])), 0);
    // Rückmeldung vom Aktor ist kein Tastendruck.
    expect(pressedKey(t1, glass, tg('1/4/1', [1], from: actuator)), isNull);
    expect(pressedKey(blind, glass, tg('3/1/0', [0])), 5);
    expect(pressedKey(blind, glass, tg('3/1/0', [1])), 6);
    expect(bench.channel.kind, ChannelKind.blind);
    expect(bench.status, isEmpty);
    expect(pressedKey(bench, glass, tg('3/1/6', [0])), 9);
    expect(pressedKey(bench, glass, tg('3/1/6', [1])), 10);
    // Dimmen: heller → erste Taste, Stopp → kein Druck.
    expect(pressedKey(t2, glass, tg('1/2/0', [0x0B], small: false)), 0);
    expect(pressedKey(t2, glass, tg('1/2/0', [0x00], small: false)), isNull);
    final l55 = pushButtonOf(light, c)!;
    expect(pressedKey(l55.functions[0], light, tg('1/1/27', [1], from: light)), 1);
    expect(pressedKey(l55.functions[0], light, tg('1/1/27', [0], from: light)), 2);
    // Sollwert: höher → erste Taste.
    final before = tg('2/3/0', encodeDpt9(21)!, small: false);
    expect(pressedKey(heat, glass, tg('2/3/0', encodeDpt9(21.5)!, small: false), previous: before), 7);
    expect(pressedKey(heat, glass, tg('2/3/0', encodeDpt9(20.5)!, small: false), previous: before), 8);
  });

  test('Dimmen als Tastenpaar: heller oben, dunkler unten, Stopp kein Druck', () {
    final f = ButtonFunction(first: 1, second: 2, channel: pushButtonOf(glass, c)!.functions[1].channel, status: []);
    expect(pressedKey(f, glass, tg('1/2/0', [0x0B], small: false)), 1);
    expect(pressedKey(f, glass, tg('1/2/0', [0x03], small: false)), 2);
    expect(pressedKey(f, glass, tg('1/2/0', [0x08], small: false)), isNull);
  });

  test('Status aus der Rückmeldung', () {
    final t1 = pushButtonOf(glass, c)!.functions.first;
    expect(statusOf(t1, {}), isNull);
    expect(
      statusOf(t1, {
        parseGroup('1/4/1')!: tg('1/4/1', [1], from: actuator),
      }),
      isTrue,
    );
    expect(
      statusOf(t1, {
        parseGroup('1/4/1')!: tg('1/4/1', [0], from: actuator),
      }),
      isFalse,
    );
  });

  test('LED: 1,5 s nach Druck an, dann kurz aus und dauerhaft an, solange Rückmeldung an', () {
    Duration ms(int v) => Duration(milliseconds: v);
    expect(ledLevel(sincePress: ms(500), status: false), 1);
    expect(ledLevel(sincePress: ms(1499), status: true), 1);
    expect(ledLevel(sincePress: ms(1600), status: true), 0);
    expect(ledLevel(sincePress: ms(1900), status: true), 1);
    // Licht bleibt aus: LED blendet aus und bleibt aus.
    expect(ledLevel(sincePress: ms(1650), status: false), closeTo(0.5, 0.01));
    expect(ledLevel(sincePress: ms(1900), status: false), 0);
    // Ohne Bewegung: hart aus.
    expect(ledLevel(sincePress: ms(1650), status: false, fade: false), 0);
    // Ohne Druck folgt die LED der Rückmeldung.
    expect(ledLevel(status: true), 1);
    expect(ledLevel(status: false), 0);
  });
}
