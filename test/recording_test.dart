import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/recording.dart';

void main() {
  final start = DateTime(2026, 10, 14, 15, 0);
  Telegram t(int sec, List<int> data, {bool small = false, TelegramType type = TelegramType.write}) => Telegram(
    time: start.add(Duration(seconds: sec, microseconds: 123)),
    source: parseIndividual('1.1.50')!,
    destination: parseGroup('2/0/0')!,
    type: type,
    data: Uint8List.fromList(data),
    isSmall: small,
    outgoing: sec == 3,
    raw: Uint8List.fromList([0x29, 0x00, 0xBC]),
  );

  test('Aufnahme übersteht JSON-Hin-und-Rückweg', () {
    final r = Recording(
      id: 'abc',
      name: 'Heizung EG',
      note: 'Fühler prüfen',
      started: start,
      ended: start.add(const Duration(minutes: 2)),
      gateway: 'Gira X1 · 192.168.1.22',
      telegrams: [
        t(0, [0x0C, 0x24]),
        t(3, [1], small: true),
        t(5, [0], small: true, type: TelegramType.read),
      ],
    );
    final back = Recording.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, Object?>);
    expect(back.name, 'Heizung EG');
    expect(back.note, 'Fühler prüfen');
    expect(back.duration, const Duration(minutes: 2));
    expect(back.telegrams.length, 3);
    final a = back.telegrams[1];
    expect(a.time, r.telegrams[1].time);
    expect(a.isSmall, isTrue);
    expect(a.outgoing, isTrue);
    expect(a.data, [1]);
    expect(back.telegrams.last.type, TelegramType.read);
    expect(back.telegrams.first.raw, [0x29, 0x00, 0xBC]);
  });

  test('RecordingLog leitet Sichten und Aktivität ab', () {
    final r = Recording(
      id: 'x',
      name: 'x',
      started: start,
      ended: start.add(const Duration(seconds: 60)),
      telegrams: [
        for (var i = 0; i < 6; i++) t(i * 10, [0x0C, 0x20 + i]),
      ],
    );
    final log = RecordingLog(r);
    expect(log.total, 6);
    expect(log.latest[parseGroup('2/0/0')]!.data, [0x0C, 0x25]);
    expect(log.forAddress(parseGroup('2/0/0')!).length, 6);
    expect(log.activityBins.fold(0, (a, b) => a + b), 6);
  });

  test('Wiedergabe: Springen baut den Stand bis zur Position auf', () {
    final r = Recording(
      id: 'p',
      name: 'p',
      started: start,
      ended: start.add(const Duration(seconds: 60)),
      telegrams: [
        for (var i = 0; i < 6; i++) t(i * 10, [0x0C, 0x20 + i]),
      ],
    );
    final log = RecordingLog(r);
    final player = RecordingPlayer(log);
    expect(player.position, const Duration(seconds: 60));
    expect(log.total, 6); // ohne Wiedergabe: komplette Aufnahme

    player.seek(const Duration(seconds: 25));
    expect(log.total, 3); // Telegramme bei 0, 10, 20 s
    expect(log.latest.values.single.data, [0x0C, 0x22]);
    expect(log.isFresh(log.log.last), isFalse); // Springen animiert nicht

    player.seek(const Duration(seconds: -5));
    expect(player.position, Duration.zero);
    expect(log.total, 0); // erstes Telegramm liegt 123 µs nach dem Start

    player.cycleSpeed();
    expect(player.speed, 2);
    player.dispose();
  });
}
