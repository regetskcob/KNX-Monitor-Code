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
