import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/cause_chain.dart';

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

  // Reaktionszeiten in the demo house: before, the initial state sent commands without their
  // status, and dim values, blinds and setpoints were never answered at all.
  group('Demo-Haus: jeder Befehl bekommt seine Rückmeldung', () {
    tearDown(() => DemoTunnel.clock = DateTime.now);

    test('zehn Minuten Verkehr und Befehle aus der App: keiner ohne Rückmeldung, keiner langsam', () {
      fakeAsync((async) {
        DemoTunnel.clock = () => async.getClock(DateTime(2026, 11, 11, 10)).now();
        final tunnel = DemoTunnel();
        final seen = <Telegram>[];
        tunnel.telegrams.listen(seen.add);
        tunnel.connect();
        async.elapse(const Duration(minutes: 10));
        // Light, dim value, blind up/down and stop, setpoint.
        tunnel.write(parseGroup('1/0/0')!, small: 1);
        tunnel.write(parseGroup('1/2/0')!, data: [128]);
        tunnel.write(parseGroup('3/1/0')!, small: 1);
        async.elapse(const Duration(seconds: 5));
        tunnel.write(parseGroup('3/2/0')!, small: 1);
        tunnel.write(parseGroup('2/1/0')!, data: [0x0C, 0x1A]);
        async.elapse(const Duration(seconds: 5));

        final stats = ReactionStats.of(seen, demoCatalog());
        // Lights, dimmers, blinds and rooms (setpoint) all appear.
        expect(stats.length, greaterThanOrEqualTo(4 * 8));
        expect([for (final r in stats) r.missing], everyElement(0));
        expect([for (final r in stats) r.max!], everyElement(lessThan(const Duration(seconds: 1))));
        // The blind reports the end position of the command.
        final position = seen.lastWhere((t) => t.destination == parseGroup('3/0/0'));
        expect(position.data, [255]);
        tunnel.disconnect();
        async.flushTimers();
        tunnel.dispose();
      });
    });

    test('simulate() für Bilder: ebenso', () {
      var now = DateTime(2026, 11, 11, 10);
      DemoTunnel.clock = () => now = now.add(const Duration(milliseconds: 400));
      final tunnel = DemoTunnel();
      addTearDown(tunnel.dispose);
      final stats = ReactionStats.of(tunnel.simulate(steps: 400), demoCatalog());
      expect(stats, isNotEmpty);
      expect([for (final r in stats) r.missing], everyElement(0));
    });

    test('gewollter Befund bleibt: DALI-Gruppe 2 meldet auf der Adresse von Gruppe 3', () {
      fakeAsync((async) {
        DemoTunnel.clock = () => async.getClock(DateTime(2026, 11, 11, 10)).now();
        final tunnel = DemoTunnel();
        final seen = <Telegram>[];
        tunnel.telegrams.listen(seen.add);
        tunnel.connect();
        async.elapse(const Duration(minutes: 1));
        tunnel.write(DemoDali.groupSwitch(2), small: 1);
        async.elapse(const Duration(seconds: 10));
        final stats = ReactionStats.of(seen, demoCatalog());
        expect(
          [
            for (final r in stats)
              if (r.missing > 0) r.object.key,
          ],
          ['DALI Gruppe 2'],
        );
        tunnel.disconnect();
        async.flushTimers();
        tunnel.dispose();
      });
    });
  });
}
