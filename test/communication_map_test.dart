import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/communication_map.dart';
import 'package:knx_monitor/model/telegram_log.dart';

void main() {
  final light = parseGroup('1/1/1')!;
  final button = parseIndividual('1.1.20')!;
  final actuator = parseIndividual('1.1.5')!;
  final stranger = parseIndividual('1.1.99')!;

  setUp(() {
    CatalogStore.instance.catalog = GroupCatalog(
      {
        light: GroupInfo(
          address: light,
          name: 'Licht Küche',
          dpt: const Dpt(1, 1),
          links: [
            GroupLink(device: button, sends: true),
            GroupLink(device: actuator),
          ],
        ),
      },
      devices: {
        button: DeviceInfo(address: button, name: 'Taster'),
        actuator: DeviceInfo(address: actuator, name: 'Aktor'),
      },
    );
  });

  Telegram t(int src) => Telegram(
    time: DateTime(2026),
    source: src,
    destination: light,
    type: TelegramType.write,
    data: Uint8List.fromList([1]),
    isSmall: true,
  );

  test('Gruppenadresse: Sender beobachtet und laut Projekt, Empfänger laut Projekt', () {
    final map = CommunicationMap.of(TelegramLog()..addAll([t(button), t(button), t(stranger)]));
    expect(map.busiest, const MapNode.group(0x0901));
    final senders = map.inputs(MapNode.group(light));
    expect(senders.map((n) => (formatIndividual(n.node.address), n.observed, n.inProject)), [
      ('1.1.20', 2, true),
      ('1.1.99', 1, false), // beobachtet, aber nicht verknüpft
    ]);
    expect(map.outputs(MapNode.group(light)).map((n) => n.node.address), [actuator]);
  });

  test('Gerät: hört auf und sendet auf', () {
    final map = CommunicationMap.of(TelegramLog()..addAll([t(button)]));
    expect(map.outputs(MapNode.device(button)).single.observed, 1);
    expect(map.inputs(MapNode.device(actuator)).single.node, MapNode.group(light));
  });
}
