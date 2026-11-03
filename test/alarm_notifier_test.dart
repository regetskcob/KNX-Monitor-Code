import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/alarm_notifier.dart';

void main() {
  final ga = parseGroup('5/0/0')!;
  setUp(() {
    CatalogStore.instance.catalog = GroupCatalog({
      ga: GroupInfo(address: ga, name: 'Rauchmelder EG', dpt: const Dpt(1, 5)),
    });
  });
  tearDown(() => CatalogStore.instance.catalog = GroupCatalog.empty);

  Telegram t(int value, DateTime time) => Telegram(
    time: time,
    source: 0x1101,
    destination: ga,
    type: TelegramType.write,
    data: Uint8List.fromList([value]),
    isSmall: true,
  );

  test('meldet den Wechsel in den Alarm, gedrosselt, abschaltbar', () async {
    final sent = <String>[];
    final enabled = ValueNotifier(true);
    final stream = StreamController<Telegram>();
    final n = AlarmNotifier(
      stream.stream,
      enabled: enabled,
      send: ({required id, required title, required body}) async => sent.add(title),
    );
    final t0 = DateTime(2026, 10, 15, 8);
    stream
      ..add(t(1, t0)) // Alarm → Mitteilung
      ..add(t(1, t0.add(const Duration(seconds: 10)))) // bleibt aktiv → nichts
      ..add(t(0, t0.add(const Duration(minutes: 1)))) // zurück → nichts
      ..add(t(1, t0.add(const Duration(minutes: 2)))) // erneut, aber gedrosselt
      ..add(t(0, t0.add(const Duration(minutes: 3))))
      ..add(t(1, t0.add(const Duration(minutes: 10)))); // nach Drosselzeit → Mitteilung
    await Future<void>.delayed(Duration.zero);
    expect(sent, ['Alarm: Rauchmelder EG', 'Alarm: Rauchmelder EG']);

    enabled.value = false;
    stream
      ..add(t(0, t0.add(const Duration(minutes: 20))))
      ..add(t(1, t0.add(const Duration(minutes: 30))));
    await Future<void>.delayed(Duration.zero);
    expect(sent, hasLength(2));
    await n.dispose();
    await stream.close();
  });
}
