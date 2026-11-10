import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/plain_text.dart';

int ga(String s) => parseGroup(s)!;
int pa(String s) => parseIndividual(s)!;

Telegram tg(
  String dest,
  List<int> data, {
  bool small = false,
  TelegramType type = TelegramType.write,
  String source = '1.1.30',
  bool outgoing = false,
}) => Telegram(
  time: DateTime(2026, 10, 29, 12),
  source: pa(source),
  destination: ga(dest),
  type: type,
  data: Uint8List.fromList(data),
  isSmall: small,
  outgoing: outgoing,
);

void main() {
  final controller = LocaleController.instance;
  tearDown(() => controller.debugSetLocale(const Locale('de')));

  group('guessDpt', () {
    test('1 Bit → 1.001, mit Namen genauer', () {
      expect(
        guessDpt([
          tg('1/0/0', [1], small: true),
        ])!.dpt,
        const Dpt(1, 1),
      );
      expect(
        guessDpt([
          tg('1/0/0', [1], small: true),
        ], name: 'Rollladen Küche')!.dpt,
        const Dpt(1, 8),
      );
      expect(
        guessDpt([
          tg('1/0/0', [0], small: true),
        ], name: 'Fensterkontakt Bad')!.dpt,
        const Dpt(1, 19),
      );
      expect(
        guessDpt([
          tg('1/0/0', [9], small: true),
        ])!.dpt,
        const Dpt(3, 7),
      );
    });

    test('1 Byte → 5.001, Szene am Namen', () {
      expect(
        guessDpt([
          tg('1/2/0', [128]),
        ])!.dpt,
        const Dpt(5, 1),
      );
      expect(
        guessDpt([
          tg('1/2/0', [3]),
        ], name: 'Szene Abend')!.dpt,
        const Dpt(17, 1),
      );
    });

    test('2 Byte → 9.xxx, Untertyp nur mit Namen', () {
      final t = tg('2/0/0', [0x0C, 0x1A]);
      expect(guessDpt([t])!.dpt, const Dpt(9));
      final named = guessDpt([t], name: 'Temperatur Wohnzimmer')!;
      expect(named.dpt, const Dpt(9, 1));
      expect(named.fromName, isTrue);
      expect(guessDpt([t], name: 'Luftfeuchte')!.dpt, const Dpt(9, 7));
    });

    test('3, 4, 8 und 14 Byte', () {
      expect(
        guessDpt([
          tg('7/0/0', [0x6E, 0x2F, 0x00]),
        ])!.dpt,
        const Dpt(10, 1),
      );
      expect(
        guessDpt([
          tg('7/0/1', [29, 10, 26]),
        ])!.dpt,
        const Dpt(11, 1),
      );
      expect(
        guessDpt([
          tg('5/0/0', [0x44, 0x9A, 0x80, 0x00]),
        ])!.dpt,
        const Dpt(14),
      );
      expect(
        guessDpt([
          tg('5/0/0', [0x44, 0x9A, 0x80, 0x00]),
        ], name: 'Leistung')!.dpt,
        const Dpt(14, 56),
      );
      expect(
        guessDpt([
          tg('5/0/1', [0, 0, 0x48, 0x14]),
        ], name: 'Energiezähler')!.dpt,
        const Dpt(13, 13),
      );
      expect(guessDpt([tg('7/0/2', List.filled(8, 0))])!.dpt, const Dpt(19, 1));
      expect(guessDpt([tg('7/0/3', List.filled(14, 65))])!.dpt, const Dpt(16, 0));
    });

    test('Nur Leseanfragen: nichts zu raten', () {
      expect(
        guessDpt([
          tg('1/0/0', [0], small: true, type: TelegramType.read),
        ]),
        isNull,
      );
    });

    test('Kandidaten passen zur Länge, geratener Typ ist dabei', () {
      for (final t in [
        tg('1/0/0', [1], small: true),
        tg('1/2/0', [3]),
        tg('2/0/0', [0x0C, 0x1A]),
      ]) {
        expect(dptCandidates(payloadLength(t)), contains(guessDpt([t], name: 'Temperatur')!.dpt));
      }
    });
  });

  group('plainSentence', () {
    test('Schalten mit Namen', () {
      final t = tg('1/0/1', [1], small: true);
      expect(
        plainSentence(t, sender: 'Taster Flur', target: 'Küchenlicht', dpt: const Dpt(1, 1)),
        'Taster Flur hat Küchenlicht eingeschaltet',
      );
      controller.debugSetLocale(const Locale('en'));
      expect(
        plainSentence(t, sender: 'Hall button', target: 'kitchen light', dpt: const Dpt(1, 1)),
        'Hall button switched on kitchen light',
      );
    });

    test('Rollladen, ohne Namen, ohne Typ', () {
      expect(
        plainSentence(tg('3/1/0', [1], small: true), target: 'Rollladen Bad', dpt: const Dpt(1, 8)),
        'Gerät 1.1.30 hat Rollladen Bad heruntergefahren',
      );
      // Ohne Projekt: 1 Bit wird als Schalten gelesen.
      expect(plainSentence(tg('1/0/1', [0], small: true)), 'Gerät 1.1.30 hat Adresse 1/0/1 ausgeschaltet');
    });

    test('Werte, Rückmeldungen und Lesen', () {
      expect(
        plainSentence(tg('1/2/0', [128]), sender: 'Glastaster', target: 'Dimmer', dpt: const Dpt(5, 1)),
        'Glastaster hat Dimmer auf 50 % gesetzt',
      );
      expect(
        plainSentence(tg('1/1/1', [1], small: true), target: 'Küchenlicht Status', dpt: const Dpt(1, 1), status: true),
        'Gerät 1.1.30 meldet Küchenlicht Status: Ein',
      );
      expect(
        plainSentence(
          tg('2/0/0', [0x0C, 0x1A], type: TelegramType.response),
          target: 'Temperatur',
          dpt: const Dpt(9, 1),
        ),
        'Gerät 1.1.30 meldet Temperatur: 21 °C',
      );
      expect(
        plainSentence(tg('2/0/0', [0], small: true, type: TelegramType.read, outgoing: true), target: 'Temperatur'),
        'Diese App fragt Temperatur ab',
      );
    });

    test('Messwerte werden gemeldet', () {
      expect(
        plainSentence(
          tg('4/0/2', [0x0C, 0x1A]),
          sender: 'Wetterstation',
          target: 'Außentemperatur',
          dpt: const Dpt(9, 1),
        ),
        'Wetterstation meldet Außentemperatur: 21 °C',
      );
      expect(plainSentence(tg('4/0/2', [0x0C, 0x1A])), 'Gerät 1.1.30 meldet Adresse 4/0/2: 21');
    });

    test('telegramSentence nimmt Namen und Typ aus dem Projekt', () {
      final store = CatalogStore.instance;
      store.catalog = GroupCatalog(
        {
          ga('1/0/1'): GroupInfo(address: ga('1/0/1'), name: 'Küchenlicht', dpt: const Dpt(1, 1)),
          ga('1/1/1'): GroupInfo(address: ga('1/1/1'), name: 'Küchenlicht Rückmeldung', dpt: const Dpt(1, 1)),
        },
        devices: {pa('1.1.30'): DeviceInfo(address: pa('1.1.30'), name: 'Taster Flur')},
      );
      addTearDown(() => store.catalog = GroupCatalog.empty);
      expect(telegramSentence(tg('1/0/1', [1], small: true)), 'Taster Flur hat Küchenlicht eingeschaltet');
      expect(
        telegramSentence(tg('1/1/1', [0], small: true, source: '1.1.10')),
        'Gerät 1.1.10 meldet Küchenlicht Rückmeldung: Aus',
      );
    });
  });
}
