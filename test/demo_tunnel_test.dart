import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';

void main() {
  test('Verbindungsart heißt Demo-Haus, nicht UDP (Forenpaket)', () {
    final tunnel = DemoTunnel();
    addTearDown(tunnel.dispose);
    expect(tunnel.kind, 'Demo-Haus');
  });

  test('Demo: Musterhaus mit Projekt, Werten, Lesen und Schalten', () async {
    final catalog = demoCatalog();
    expect(catalog.groups.length, greaterThan(30));
    expect(catalog.devices, isNotEmpty);
    CatalogStore.instance.catalog = catalog;

    final tunnel = DemoTunnel();
    final seen = <Telegram>[];
    final sub = tunnel.telegrams.listen(seen.add);
    await tunnel.connect();
    expect(tunnel.state.value, TunnelState.connected);
    expect(DemoTunnel.active, isTrue);
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(seen.where((t) => t.type == TelegramType.write), isNotEmpty);
    // Werte sind für ihren DPT lesbar (z. B. Temperatur in °C).
    final temp = seen.firstWhere((t) => CatalogStore.instance.info(t.destination)?.dpt?.main == 9);
    expect(CatalogStore.instance.value(temp), isNot(contains('?')));

    final light = parseGroup('1/0/0')!;
    final feedback = parseGroup('1/1/0')!;
    seen.clear();
    await tunnel.read(light);
    await Future<void>.delayed(const Duration(milliseconds: 50)); // Stream liefert asynchron
    expect(seen.map((t) => t.type), containsAllInOrder([TelegramType.read, TelegramType.response]));
    await tunnel.write(light, small: 1);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(seen.any((t) => t.destination == feedback && t.type == TelegramType.write), isTrue);

    await tunnel.disconnect();
    expect(DemoTunnel.active, isFalse);
    await sub.cancel();
    tunnel.dispose();
  });
}
