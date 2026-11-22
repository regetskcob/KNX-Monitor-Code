import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/telegram_log.dart';

class _Log extends TelegramLog {
  _Log() : super(maxEntries: 3);

  void insertBefore(List<Telegram> older) => rebuild([...older, ...log], frozen: 0, added: older);
}

void main() {
  const ga = 0x0A03;
  final start = DateTime(2026, 11, 16, 8);

  Telegram t(int second, {TelegramType type = TelegramType.write}) => Telegram(
    time: start.add(Duration(seconds: second)),
    source: 0x1105,
    destination: ga,
    type: type,
    data: Uint8List.fromList([1]),
    isSmall: true,
  );

  test('Zähler je Adresse laufen beim Nachladen weiter statt auf das Fenster zurückzufallen', () {
    final log = _Log();
    for (var i = 10; i < 15; i++) {
      log.add(t(i));
    }
    expect(log.log, hasLength(3));
    expect(log.counts[ga], 5);

    log.insertBefore([t(1), t(2)]);
    expect(log.counts[ga], 7);
  });

  test('unbeantwortete Leseanfragen an eine tote Adresse sammeln sich nicht an', () {
    final log = TelegramLog(maxEntries: 5);
    for (var i = 0; i < 200; i++) {
      log.add(t(i * 10, type: TelegramType.read));
    }
    expect(log.openReadCount, 1);

    // Within the deadline several stay open and are answered together.
    final quick = TelegramLog();
    final a = t(0, type: TelegramType.read), b = t(1, type: TelegramType.read);
    quick
      ..add(a)
      ..add(b);
    expect(quick.openReadCount, 2);
    quick.add(t(2, type: TelegramType.response));
    expect(quick.openReadCount, 0);
  });
}
