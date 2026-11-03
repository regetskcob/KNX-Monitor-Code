import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/telegram.dart';

void main() {
  test('Adressen mit Vorzeichen werden abgelehnt (würden auf eine andere Adresse umbrechen)', () {
    expect(parseGroup('1/2/3'), (1 << 11) | (2 << 8) | 3);
    expect(parseGroup('1/2/-3'), isNull);
    expect(parseGroup('-1/0/0'), isNull);
    expect(parseGroup('+1/0/0'), isNull);
    expect(parseIndividual('1.1.-1'), isNull);
    expect(parseIndividual('1.1.10'), 0x110A);
  });

  test('parst GroupValueWrite 1 bit', () {
    // L_Data.ind, 1.1.5 → 1/2/3, Write, Wert 1
    final t = Telegram.fromCemi(
      Uint8List.fromList([0x29, 0x00, 0xBC, 0xE0, 0x11, 0x05, 0x0A, 0x03, 0x01, 0x00, 0x81]),
    )!;
    expect(t.sourceText, '1.1.5');
    expect(t.destinationText, '1/2/3');
    expect(t.type, TelegramType.write);
    expect(t.valueText, '1 · Ein');
  });

  test('parst GroupValueResponse DPT 9', () {
    // 0C 1A = 21.0 (DPT 9)
    final t = Telegram.fromCemi(
      Uint8List.fromList([0x29, 0x00, 0xBC, 0xE0, 0x11, 0x05, 0x0A, 0x03, 0x03, 0x00, 0x40, 0x0C, 0x1A]),
    )!;
    expect(t.type, TelegramType.response);
    expect(t.data, [0x0C, 0x1A]);
    expect(decodeDpt9(t.data), closeTo(21.0, 0.001));
  });

  test('3 Byte ohne Projekt: Datum, wenn das Jahr passt, sonst Uhrzeit', () {
    Telegram three(List<int> d) => Telegram(
      time: DateTime(2026, 10, 21),
      source: 0x1105,
      destination: 0x0A03,
      type: TelegramType.write,
      data: Uint8List.fromList(d),
      isSmall: false,
    );
    expect(three([0x15, 0x0A, 0x1A]).valueText, '15 0A 1A · ≈ 21.10.2026');
    expect(three([0x6F, 0x28, 0x00]).valueText, '6F 28 00 · ≈ Mi 15:40:00');
    expect(three([0xFF, 0xFF, 0xFF]).valueText, 'FF FF FF');
    expect(
      three([0x7E, 0x0A, 0x15, 0x6F, 0x31, 0x00, 0x21, 0x00]).valueText,
      '7E 0A 15 6F 31 00 21 00 · ≈ 21.10.2026 15:49:00',
    );
    expect(three([0x10, 0x0A, 0x15, 0x6F, 0x31, 0x00, 0x21, 0x00]).valueText, '10 0A 15 6F 31 00 21 00');
  });

  test('ignoriert physikalisch adressierte Frames', () {
    final t = Telegram.fromCemi(Uint8List.fromList([0x29, 0x00, 0xBC, 0x60, 0x11, 0x05, 0x11, 0x06, 0x01, 0x00, 0x81]));
    expect(t, isNull);
  });

  test('liest Priorität, Wiederholung, Routingzähler und Bestätigung', () {
    // 0x9C: Standard, wiederholt (Bit 5 = 0), Priorität niedrig; 0xD0: Gruppe, Hop 5
    final rep = Telegram.fromCemi(
      Uint8List.fromList([0x29, 0x00, 0x9C, 0xD0, 0x11, 0x05, 0x0A, 0x03, 0x01, 0x00, 0x81]),
    )!;
    expect(rep.repeated, isTrue);
    expect(rep.hopCount, 5);
    expect(rep.unusualHop, isTrue);
    expect(rep.priority, TelegramPriority.low);

    final normal = Telegram.fromCemi(
      Uint8List.fromList([0x29, 0x00, 0xBC, 0xE0, 0x11, 0x05, 0x0A, 0x03, 0x01, 0x00, 0x81]),
    )!;
    expect(normal.repeated, isFalse);
    expect(normal.hopCount, 6);

    // L_Data.con mit Bestätigungsfehler (Bit 0)
    final con = Telegram.fromCemi(
      Uint8List.fromList([0x2E, 0x00, 0xBD, 0xE0, 0x11, 0x26, 0x0A, 0x03, 0x01, 0x00, 0x81]),
    )!;
    expect(con.outgoing, isTrue);
    expect(con.confirmError, isTrue);
    expect(con.repeated, isFalse);
  });
}
