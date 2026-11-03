import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/health.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';

import 'fake_gateway.dart';

int ga(String s) => parseGroup(s)!;
int pa(String s) => parseIndividual(s)!;

Telegram t(int dest, List<int> data, DateTime time, {int? source, bool small = false}) => Telegram(
  time: time,
  source: source ?? pa('1.1.50'),
  destination: dest,
  type: TelegramType.write,
  data: Uint8List.fromList(data),
  isSmall: small,
);

void main() {
  final now = DateTime(2026, 10, 17, 12);
  final temp = ga('2/0/0');
  final hum = ga('2/1/0');
  final wind = ga('8/1/1');
  final noDpt = ga('9/0/0');
  final presence = ga('8/3/0');

  setUp(() {
    CatalogStore.instance.catalog = GroupCatalog({
      temp: GroupInfo(address: temp, name: 'EG FL Ist-Temperatur', dpt: const Dpt(9, 1)),
      hum: GroupInfo(address: hum, name: 'EG FL Feuchte', dpt: const Dpt(9, 7)),
      wind: GroupInfo(address: wind, name: 'Wind', dpt: const Dpt(9, 5)),
      noDpt: GroupInfo(address: noDpt, name: 'Ohne DPT Status'),
      presence: GroupInfo(address: presence, name: 'Präsenz', dpt: const Dpt(1, 18)),
    });
  });
  tearDown(() => CatalogStore.instance.catalog = GroupCatalog.empty);

  test('Lesetest: neu stumm vs. schon immer stumm', () {
    final f = readFindings(
      asked: [temp, hum, wind],
      answers: {temp: t(temp, encodeDpt9(21)!, now)},
      readable: {hum},
      lastAnswer: {hum: now.subtract(const Duration(days: 1))},
    );
    expect(f.map((x) => (x.kind, x.address)), [(FindingKind.newSilent, hum), (FindingKind.alwaysSilent, wind)]);
  });

  test('Zyklus-Wächter: regelmäßig sendend und überfällig, Ereignisse nicht', () {
    final telegrams = [
      // Temperatur alle 10 min bis vor 1 h.
      for (var i = 0; i < 10; i++) t(temp, encodeDpt9(21)!, now.subtract(Duration(minutes: 60 + i * 10))),
      // Wind alle 10 min bis gerade eben.
      for (var i = 0; i < 10; i++) t(wind, encodeDpt9(2)!, now.subtract(Duration(minutes: i * 10))),
      // Präsenz: nur drei Ereignisse.
      for (var i = 0; i < 3; i++) t(presence, [1], now.subtract(Duration(hours: 5 + i)), small: true),
    ];
    final f = cycleFindings(telegrams, now);
    expect(f.single.kind, FindingKind.overdue);
    expect(f.single.address, temp);
    expect(f.single.interval, const Duration(minutes: 10));
  });

  test('Werte: unplausibel und hängend', () {
    final telegrams = [
      t(temp, encodeDpt9(85)!, now),
      for (var i = 0; i < 14; i++) t(hum, encodeDpt9(45)!, now.subtract(Duration(hours: i))),
    ];
    final f = valueFindings(telegrams, now);
    expect(
      f.map((x) => (x.kind, x.address)),
      unorderedEquals([(FindingKind.outOfRange, temp), (FindingKind.stuck, hum)]),
    );
  });

  test('Datentypen: Länge und Wert je Sender, uneinheitlich ohne DPT', () {
    final telegrams = [
      t(temp, encodeDpt9(21)!, now),
      t(temp, [21], now, source: pa('1.1.7')), // 1 Byte statt 2
      t(temp, [21], now, source: pa('1.1.7')),
      t(wind, [0x7F, 0xFF], now, source: pa('1.2.20')), // „ungültig“
      t(noDpt, [1], now, small: true),
      t(noDpt, [0, 1], now, source: pa('1.1.8')),
    ];
    final f = dptFindings(telegrams);
    final size = f.firstWhere((x) => x.kind == FindingKind.dptSize);
    expect((size.address, size.source, size.actual, size.expected, size.count), (temp, pa('1.1.7'), 1, 2, 2));
    expect(f.any((x) => x.kind == FindingKind.dptValue && x.address == wind), isTrue);
    expect(f.any((x) => x.kind == FindingKind.mixedSizes && x.address == noDpt), isTrue);
    expect(findingDetail(size), contains('DPT 9.001'));
  });

  test('Status ohne verknüpftes Gerät wird nicht gelesen, sondern gemeldet', () {
    CatalogStore.instance.catalog = GroupCatalog({
      temp: GroupInfo(
        address: temp,
        name: 'EG FL Ist-Temperatur',
        links: [GroupLink(device: pa('1.1.50'), sends: true)],
      ),
      hum: GroupInfo(address: hum, name: 'DG Ist-Temperatur'),
    });
    final h = HealthCheck.instance..debugReset();
    expect(h.addressesToRead(), [temp]);
    expect(h.unlinkedStatus(), [hum]);
  });

  group('Lauf am Gateway', () {
    late FakeGateway gateway;
    late KnxTunnel tunnel;
    late Directory dir;
    final h = HealthCheck.instance;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('health');
      AppStorage.instance = IoStorage(dir);
      h.debugReset();
      gateway = await FakeGateway.start();
      tunnel = KnxTunnel('127.0.0.1', port: gateway.port);
      await tunnel.connect();
    });

    tearDown(() async {
      await tunnel.disconnect();
      gateway.close();
      await dir.delete(recursive: true);
    });

    test('lernt antwortende Adressen; Ausfall erscheint als neu', () async {
      // Ohne Status-Namen im Projekt: nur gelernte Adressen werden gelesen.
      h.readable.add(temp);
      gateway.responders[temp] = (pa('1.1.50'), [0x0C, 0x24]);
      final first = (await h.run(tunnel, TelegramLog()))!;
      expect((first.asked, first.answered), (2, 1)); // gelernte Temperatur + Status-Adresse ohne DPT
      expect(first.findings.where((f) => f.address == temp), isEmpty);

      gateway.responders.remove(temp); // Gerät fällt aus
      final second = (await h.run(tunnel, TelegramLog()))!;
      final silent = second.findings.firstWhere((f) => f.address == temp);
      expect(silent.kind, FindingKind.newSilent);
      expect(second.isNew(silent), isTrue);
      expect(h.runs.length, 2);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
