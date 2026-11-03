import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/cause_chain.dart';

int _ga(String s) => parseGroup(s)!;
int _pa(String s) => parseIndividual(s)!;

final _t0 = DateTime(2026, 10, 29, 20);

Telegram _t(int ms, String source, String ga, {int value = 1, TelegramType type = TelegramType.write}) => Telegram(
  time: _t0.add(Duration(milliseconds: ms)),
  source: _pa(source),
  destination: _ga(ga),
  type: type,
  data: Uint8List.fromList([value]),
  isSmall: true,
);

GroupLink _send(String pa) => GroupLink(device: _pa(pa), sends: true);
GroupLink _hear(String pa) => GroupLink(device: _pa(pa));

/// Visualisierung 1.1.200 ruft Szene 3 ab; sechs Aktoren schalten und melden
/// zurück. Eine Logik (1.1.150) hört auf „Präsenz“ und schaltet das Flurlicht.
final _catalog = GroupCatalog(
  {
    for (final g in [
      GroupInfo(
        address: _ga('0/0/1'),
        name: 'Szene Abend',
        dpt: const Dpt(17, 1),
        links: [_send('1.1.200'), for (var i = 0; i < 6; i++) _hear('1.1.${10 + i}')],
      ),
      for (var i = 0; i < 6; i++) ...[
        GroupInfo(
          address: _ga('1/1/$i'),
          name: 'EG L0${i + 1} Schalten',
          dpt: const Dpt(1, 1),
          links: [_hear('1.1.${10 + i}')],
        ),
        GroupInfo(
          address: _ga('1/4/$i'),
          name: 'EG L0${i + 1} Rückmeldung Schalten',
          dpt: const Dpt(1, 1),
          links: [_send('1.1.${10 + i}')],
        ),
      ],
      GroupInfo(
        address: _ga('8/0/0'),
        name: 'Flur Präsenz',
        dpt: const Dpt(1, 18),
        links: [_send('1.1.60'), _hear('1.1.150')],
      ),
      GroupInfo(
        address: _ga('1/1/9'),
        name: 'EG FL L09 Schalten',
        dpt: const Dpt(1, 1),
        links: [_send('1.1.150'), _hear('1.1.19')],
      ),
      GroupInfo(
        address: _ga('1/4/9'),
        name: 'EG FL L09 Rückmeldung Schalten',
        dpt: const Dpt(1, 1),
        links: [_send('1.1.19')],
      ),
    ])
      g.address: g,
  },
  devices: {_pa('1.1.200'): DeviceInfo(address: _pa('1.1.200'), name: 'Visualisierung')},
);

void main() {
  test('Szene: Absender und Rückmeldungen mit Abstand', () {
    final scene = _t(0, '1.1.200', '0/0/1', value: 2);
    final log = [
      _t(-5000, '1.1.60', '8/0/0'),
      scene,
      for (var i = 0; i < 6; i++) _t(60 + i * 24, '1.1.${10 + i}', '1/4/$i'),
      _t(900, '1.1.99', '5/0/0'),
    ];
    final chain = CauseChain.of(scene, log, _catalog);
    expect(chain.kind, ChainKind.scene);
    expect(chain.cause, isNull);
    expect(chain.feedbacks, hasLength(6));
    expect(chain.reactingDevices, hasLength(6));
    expect(chain.after.last.role, ChainRole.coincident); // fremdes Telegramm ohne Bezug
    expect(chain.reactions.last.offset, const Duration(milliseconds: 180));
    final text = chain.describe(
      title: (t) => _catalog[t.destination]?.name ?? t.destinationText,
      device: (pa) => '${formatIndividual(pa)} ${_catalog.devices[pa]?.name ?? ''}'.trim(),
    );
    expect(text, 'Szene „Szene Abend“ kam von 1.1.200 Visualisierung, 180 ms später meldeten 6 Geräte zurück.');
  });

  test('Logik: Präsenz löst Flurlicht aus, Rückmeldung zeigt auf den Befehl', () {
    final presence = _t(0, '1.1.60', '8/0/0');
    final command = _t(120, '1.1.150', '1/1/9');
    final feedback = _t(310, '1.1.19', '1/4/9');
    final log = [presence, command, feedback];

    final chain = CauseChain.of(command, log, _catalog);
    expect(chain.cause?.telegram, same(presence));
    expect(chain.cause?.offset, const Duration(milliseconds: -120));
    expect(chain.feedbacks.single.telegram, same(feedback));

    // Von der Rückmeldung aus: der Befehl desselben Objekts ist der Auslöser.
    final back = CauseChain.of(feedback, log, _catalog);
    expect(back.kind, ChainKind.feedback);
    expect(back.cause?.telegram, same(command));
    expect(back.reactions, isEmpty);
  });

  test('Messwert hat keinen Auslöser, auch wenn der Sensor auf die Adresse davor hört', () {
    // Wetterstation 1.1.70 hört (laut Projekt) auf die Ventil-Rückmeldung –
    // ihre Helligkeit sendet sie trotzdem nicht deswegen.
    final catalog = GroupCatalog({
      _ga('3/4/0'): GroupInfo(
        address: _ga('3/4/0'),
        name: 'Heizung Bad Ventil Status',
        dpt: const Dpt(1, 1),
        links: [_send('1.1.40'), _hear('1.1.70')],
      ),
      _ga('4/0/1'): GroupInfo(
        address: _ga('4/0/1'),
        name: 'Außenhelligkeit',
        dpt: const Dpt(9, 4),
        links: [_send('1.1.70')],
      ),
    });
    final valve = _t(-300, '1.1.40', '3/4/0');
    final lux = Telegram(
      time: _t0,
      source: _pa('1.1.70'),
      destination: _ga('4/0/1'),
      type: TelegramType.write,
      data: Uint8List.fromList([0x2c, 0x00]),
      isSmall: false,
    );
    final chain = CauseChain.of(lux, [valve, lux], catalog);
    expect(chain.cause, isNull);
    expect(chain.before.single.role, ChainRole.coincident);
  });

  test('Ohne Projekt nur Zeitnähe', () {
    final a = _t(0, '1.1.1', '1/1/1');
    final b = _t(100, '1.1.2', '1/1/2');
    final chain = CauseChain.of(a, [a, b], GroupCatalog.empty);
    expect(chain.after.single.role, ChainRole.coincident);
    expect(chain.reactions, isEmpty);
  });

  test('Reaktionszeiten je Kanal: Median, 90 %, fehlende Rückmeldungen', () {
    final log = <Telegram>[
      for (final (i, ms) in [100, 120, 140, 160, 900].indexed) ...[
        _t(i * 10000, '1.1.200', '1/1/0'),
        _t(i * 10000 + ms, '1.1.10', '1/4/0'),
      ],
      // Kanal 2: einmal ohne Rückmeldung, einmal schnell.
      _t(60000, '1.1.200', '1/1/1'),
      _t(70000, '1.1.200', '1/1/1'),
      _t(70050, '1.1.11', '1/4/1'),
      // Kanal 3: antwortet nie – bleibt mit „ohne Rückmeldung“ in der Liste.
      _t(75000, '1.1.200', '1/1/2'),
      _t(80000, '1.1.200', '5/5/5'),
    ];
    final all = ReactionStats.of(log, _catalog);
    expect(all, hasLength(3));
    final silent = all.first;
    expect(silent.object.title, contains('L03'));
    expect(silent.measured, isFalse);
    expect(silent.missing, 1);
    expect(silent.median, isNull);
    final stats = all.skip(1).toList();
    final slow = stats.first;
    expect(slow.object.title, contains('L01'));
    expect(slow.count, 5);
    expect(slow.median, const Duration(milliseconds: 140));
    expect(slow.p90, const Duration(milliseconds: 900));
    expect(slow.max, const Duration(milliseconds: 900));
    expect(slow.missing, 0);
    expect(stats.last.median, const Duration(milliseconds: 50));
    expect(stats.last.missing, 1);
  });

  test('Demo-Haus: Taster schaltet, Aktor meldet nach 150 ms zurück', () {
    DemoTunnel.clock = () => _t0;
    addTearDown(() => DemoTunnel.clock = DateTime.now);
    final catalog = demoCatalog();
    final command = Telegram(
      time: _t0,
      source: _pa('1.1.30'),
      destination: _ga('1/0/0'),
      type: TelegramType.write,
      data: Uint8List.fromList([1]),
      isSmall: true,
    );
    final feedback = Telegram(
      time: _t0.add(const Duration(milliseconds: 150)),
      source: _pa('1.1.10'),
      destination: _ga('1/1/0'),
      type: TelegramType.write,
      data: Uint8List.fromList([1]),
      isSmall: true,
    );
    final chain = CauseChain.of(command, [command, feedback], catalog);
    expect(chain.feedbacks.single.offset, const Duration(milliseconds: 150));
    expect(ReactionStats.of([command, feedback], catalog).single.median, const Duration(milliseconds: 150));
  });

  test('formatMs', () {
    expect(formatMs(const Duration(milliseconds: 180)), '180 ms');
    expect(formatMs(const Duration(milliseconds: -1250)), '1,3 s');
  });
}
