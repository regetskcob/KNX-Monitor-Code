import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/analysis.dart';
import 'package:knx_monitor/model/recording.dart';

void main() {
  final start = DateTime(2026, 10, 14, 12);
  final temp = parseGroup('2/0/0')!;
  final light = parseGroup('1/1/1')!;

  Telegram t(int ms, int ga, TelegramType type, List<int> data, {bool small = false, int src = 0x1132}) => Telegram(
    time: start.add(Duration(milliseconds: ms)),
    source: src,
    destination: ga,
    type: type,
    data: Uint8List.fromList(data),
    isSmall: small,
  );

  setUp(() {
    CatalogStore.instance.catalog = GroupCatalog(
      {
        temp: GroupInfo(address: temp, name: 'Temperatur', dpt: const Dpt(9, 1)),
        light: GroupInfo(address: light, name: 'Licht', dpt: const Dpt(1, 1)),
      },
      devices: {0x1132: const DeviceInfo(address: 0x1132, name: 'Aktor')},
    );
  });

  test('Leseanfragen mit und ohne Antwort', () {
    final answeredRead = t(0, temp, TelegramType.read, [0], small: true);
    final lonelyRead = t(5000, light, TelegramType.read, [0], small: true);
    final log = RecordingLog(
      Recording(
        id: 'a',
        name: 'a',
        started: start,
        ended: start.add(const Duration(seconds: 20)),
        telegrams: [
          answeredRead,
          t(400, temp, TelegramType.response, [0x0C, 0x24]),
          lonelyRead,
        ],
      ),
    );
    expect(log.isUnanswered(answeredRead), isFalse);
    expect(log.isUnanswered(lonelyRead), isTrue);
    expect(issuesOf(lonelyRead, log), contains(TelegramIssue.unanswered));
    expect(log.unansweredCount, 1);

    // Während der Wiedergabe ist die Frist noch nicht abgelaufen.
    log.playhead = start.add(const Duration(seconds: 6));
    expect(log.isUnanswered(lonelyRead), isFalse);
  });

  test('Datenlänge, unbekannte Adresse und unbekanntes Gerät', () {
    final log = RecordingLog(
      Recording(id: 'b', name: 'b', started: start, ended: start.add(const Duration(seconds: 1)), telegrams: []),
    );
    // DPT 9 erwartet 2 Byte, kommt mit 1 Byte
    expect(issuesOf(t(0, temp, TelegramType.write, [0x10]), log), [TelegramIssue.sizeMismatch]);
    expect(issuesOf(t(0, temp, TelegramType.write, [0x0C, 0x24]), log), isEmpty);
    expect(issuesOf(t(0, parseGroup('5/5/5')!, TelegramType.write, [1], small: true, src: 0x1199), log), [
      TelegramIssue.unknownAddress,
      TelegramIssue.unknownDevice,
    ]);
  });
}
