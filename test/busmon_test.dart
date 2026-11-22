import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/busmon.dart';
import 'package:knx_monitor/knx/telegram.dart';

/// Frames wie vom Gira X1 im Busmonitor-Tunnel aufgezeichnet.
void main() {
  Uint8List bytes(String hexText) => Uint8List.fromList(parseHex(hexText)!);

  test('Datentelegramm mit Status, Zeitstempel und Prüfsumme', () {
    final f = BusmonFrame.parse(bytes('2B 09 03 01 04 06 04 93 D8 4C AE BC 12 14 41 04 D3 00 80 04 4C 1B'))!;
    expect(f.kind, BusmonKind.data);
    expect(f.status & 0x07, 4); // Sequenznummer
    expect(f.timestamp, 0x93D84CAE);
    expect(f.checksumOk, isTrue);
    expect(f.hasError, isFalse);
    expect(formatIndividual(f.source!), '1.2.20');
    expect(formatGroup(f.destination!), '8/1/4');
    expect(f.repeated, isFalse);
    expect(f.telegram!.type, TelegramType.write);
    expect(f.telegram!.data, [0x04, 0x4C]);
  });

  test('Extended Frame (lange Nutzdaten): Adressen, Länge, Prüfsumme und Wert', () {
    // Control 0x3C (extended, not repeated), CTRLE 0xE0 (group, hop count 6), 1.1.5 → 1/2/3,
    // length 15: GroupValueWrite with 14 bytes (DPT 16).
    final body = [0x3C, 0xE0, 0x11, 0x05, 0x0A, 0x03, 0x0F, 0x00, 0x80, ...'Hallo KNX'.codeUnits, 0, 0, 0, 0, 0];
    final checksum = ~body.fold(0, (a, b) => a ^ b) & 0xFF;
    final f = BusmonFrame.fromRaw(Uint8List.fromList([...body, checksum]), time: DateTime(2026));
    expect(f.kind, BusmonKind.data);
    expect(f.checksumOk, isTrue);
    expect(f.groupAddressed, isTrue);
    expect(f.repeated, isFalse);
    expect(formatIndividual(f.source!), '1.1.5');
    expect(formatGroup(f.destination!), '1/2/3');
    expect(f.telegram!.type, TelegramType.write);
    expect(f.telegram!.data, hasLength(14));
    expect(String.fromCharCodes(f.telegram!.data.take(9)), 'Hallo KNX');

    // Cut off: unknown, no crash.
    expect(BusmonFrame.fromRaw(Uint8List.fromList(body.sublist(0, 10)), time: DateTime(2026)).kind, BusmonKind.unknown);
  });

  test('Quittungen', () {
    expect(BusmonFrame.parse(bytes('2B 09 03 01 05 06 04 93 D8 AB C7 CC'))!.kind, BusmonKind.ack);
    expect(BusmonFrame.fromRaw(bytes('0C'), time: DateTime(2026)).kind, BusmonKind.nak);
    expect(BusmonFrame.fromRaw(bytes('C0'), time: DateTime(2026)).isNegative, isTrue);
  });

  test('Lesen und Antwort (1 Byte), Wiederholung und falsche Prüfsumme', () {
    final read = BusmonFrame.parse(bytes('2B 09 03 01 04 06 04 95 08 A2 D0 BC 11 26 43 02 E1 00 00 D4'))!;
    expect(read.telegram!.type, TelegramType.read);
    expect(formatGroup(read.destination!), '8/3/2');
    expect(read.checksumOk, isTrue);

    final repeated = BusmonFrame.fromRaw(bytes('9C 11 26 43 02 E1 00 00 F4'), time: DateTime(2026));
    expect(repeated.repeated, isTrue);
    expect(repeated.checksumOk, isTrue);

    final broken = BusmonFrame.fromRaw(bytes('BC 11 26 43 02 E1 00 00 00'), time: DateTime(2026));
    expect(broken.checksumOk, isFalse);
    expect(broken.hasError, isTrue);
  });

  test('Fehlerbits im Status', () {
    final f = BusmonFrame.parse(bytes('2B 03 03 01 C1 CC'))!;
    expect(f.frameError, isTrue);
    expect(f.bitError, isTrue);
    expect(f.hasError, isTrue);
  });

  test('Buslast: Telegramm + Quittung je Sekunde', () {
    final load = BusLoad();
    final now = DateTime(2026, 10, 15, 8, 0, 0, 500);
    // 11-Byte-Telegramm: (50 + 13·11) / 9600 s; Quittung: 28 / 9600 s.
    final data = BusmonFrame.fromRaw(bytes('BC 12 14 41 04 D3 00 80 04 4C 1B'), time: now);
    final ack = BusmonFrame.fromRaw(bytes('CC'), time: now);
    for (var i = 0; i < 10; i++) {
      load
        ..add(data)
        ..add(ack);
    }
    final perSecond = 10 * (193 + 28) / 9600;
    expect(load.history(seconds: 1, now: now).single, closeTo(perSecond, 1e-9));
    expect(load.average(seconds: 10, now: now), closeTo(perSecond / 10, 1e-9));
    expect(load.history(seconds: 60, now: now), hasLength(60));
  });
}
