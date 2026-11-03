import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/diagnostics.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/device_inventory.dart';

import 'fake_gateway.dart';

int _pa(String s) => parseIndividual(s)!;

void main() {
  group('Fake-Gateway', () {
    late FakeGateway gateway;
    late KnxTunnel tunnel;

    setUp(() async {
      gateway = await FakeGateway.start();
      tunnel = KnxTunnel('127.0.0.1', port: gateway.port);
      await tunnel.connect();
    });

    tearDown(() async {
      await tunnel.disconnect();
      gateway.close();
    });

    test('Inventar liest Geräte und gleicht mit dem Projekt ab', () async {
      final same = _pa('1.1.3');
      final swapped = _pa('1.1.5');
      final foreign = _pa('1.1.7');
      final oldSystem = _pa('1.1.8');
      for (final pa in [same, swapped, foreign]) {
        gateway.devices[pa] = 0x07B0;
        gateway.properties[pa] = {
          (0, 12): [0x00, 0x08],
          (0, 11): [0x00, 0x08, 0x00, 0x00, 0x00, pa & 0xFF],
          (0, 15): '2096 00'.codeUnits,
          (0, 9): [0x23],
          (3, 13): [0x00, 0x08, 0xA0, 0x12, 0x05],
        };
      }
      gateway.devices[oldSystem] = 0x0012; // System 1: keine Properties
      final catalog = GroupCatalog(
        const {},
        devices: {
          same: DeviceInfo(address: same, name: 'Schaltaktor', serial: '000800000003'),
          swapped: DeviceInfo(address: swapped, name: 'Dimmaktor', serial: '0008AAAAAAAA'),
          oldSystem: DeviceInfo(address: oldSystem, name: 'Alter Taster'),
          _pa('1.1.9'): DeviceInfo(address: _pa('1.1.9'), name: 'Wetterstation'),
          _pa('1.1.40'): DeviceInfo(address: _pa('1.1.40'), name: 'Außerhalb'),
        },
        manufacturers: const {8: 'GIRA'},
      );
      final run = DeviceInventory(
        tunnel,
        area: 1,
        line: 1,
        from: 0,
        to: 10,
        catalog: catalog,
        pause: const Duration(milliseconds: 5),
      );
      await run.start();
      expect(run.checked, 11);
      final byAddress = {for (final e in run.entries) formatIndividual(e.address): e};
      expect(byAddress.keys, ['1.1.3', '1.1.5', '1.1.7', '1.1.8', '1.1.9']);
      expect(byAddress['1.1.3']!.status, InventoryStatus.match);
      expect(byAddress['1.1.3']!.details!.serial, '000800000003');
      expect(byAddress['1.1.5']!.status, InventoryStatus.serialMismatch);
      expect(byAddress['1.1.7']!.status, InventoryStatus.notInProject);
      expect(byAddress['1.1.8']!.status, InventoryStatus.match);
      expect(byAddress['1.1.8']!.details, isNull); // System 1 nicht gefragt
      expect(byAddress['1.1.8']!.maskVersion, 0x0012);
      expect(byAddress['1.1.9']!.status, InventoryStatus.missing);
      expect(run.count(InventoryStatus.missing), 1); // 1.1.40 liegt außerhalb des Bereichs

      // Nur lesend: keine A_*_Write-Dienste auf dem Bus.
      for (final r in gateway.requests) {
        final apci = r.length > 10 ? ((r[9] & 0x03) << 8) | r[10] : 0;
        expect(const {0x0C0, 0x3D7, 0x2C0, 0x3C0}.contains(apci & 0x3FF), isFalse);
      }

      // Namen für andere Werkzeuge: Projekt, sonst Hersteller + Bestellnummer.
      final names = run.names();
      expect(names[same], 'Schaltaktor');
      expect(names[foreign], 'GIRA · 2096 00');

      final csv = run.toCsv(statusText: (s) => s.name);
      expect(csv.split('\n').first, startsWith('"Address";"Status"'));
      expect(
        csv,
        contains('"1.1.5";"serialMismatch";"Dimmaktor";"GIRA";"2096 00";"000800000005";"0008AAAAAAAA";"2.3"'),
      );
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('Abbrechen hält den Lauf an', () async {
      final run = DeviceInventory(tunnel, area: 1, line: 1, from: 0, to: 255, pause: const Duration(milliseconds: 5));
      final done = run.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      run.cancel();
      await done;
      expect(run.checked, lessThan(256));
      expect(run.done, isTrue);
    });
  });

  test('Demo-Haus antwortet wie echte Geräte (Inventar im Demo)', () async {
    final tunnel = DemoTunnel();
    await tunnel.connect();
    addTearDown(tunnel.disconnect);
    final run = DeviceInventory(
      tunnel,
      area: 1,
      line: 1,
      from: 9,
      to: 12,
      catalog: demoCatalog(),
      pause: Duration.zero,
    );
    await run.start();
    final byAddress = {for (final e in run.entries) formatIndividual(e.address): e};
    expect(byAddress.keys, ['1.1.10', '1.1.11', '1.1.12']);
    expect(byAddress['1.1.10']!.status, InventoryStatus.match);
    expect(byAddress['1.1.10']!.details!.orderInfo, 'SA 8');
    expect(byAddress['1.1.11']!.status, InventoryStatus.serialMismatch);

    final foreign = DeviceInventory(
      tunnel,
      area: 1,
      line: 1,
      from: 44,
      to: 44,
      catalog: demoCatalog(),
      pause: Duration.zero,
    );
    await foreign.start();
    expect(foreign.entries.single.status, InventoryStatus.notInProject);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('Status ohne Projekt und für Tunneladressen', () {
    final entry = InventoryEntry(_pa('1.1.39'), InventoryStatus.match);
    expect(DeviceInventory.classify(entry, tunnels: {_pa('1.1.39')}, hasProject: true), InventoryStatus.tunnel);
    // Ohne Projekt nichts zu vergleichen: neutral „Gefunden“, nicht „Passt zum Projekt“.
    expect(DeviceInventory.classify(entry, tunnels: const {}, hasProject: false), InventoryStatus.present);
    // Im Projekt gepflegte Tunneladresse (zusätzliche Adresse der Schnittstelle).
    final listed = InventoryEntry(
      _pa('1.1.39'),
      InventoryStatus.match,
      project: DeviceInfo(address: _pa('1.1.39'), name: 'IP-Schnittstelle · Tunnel 2', tunnelOf: _pa('1.1.38')),
    );
    expect(DeviceInventory.classify(listed, tunnels: {_pa('1.1.39')}, hasProject: true), InventoryStatus.tunnel);
    expect(DeviceInventory.hasProperties(0x0012), isFalse);
    expect(DeviceInventory.hasProperties(0x07B0), isTrue);
  });

  test('Firmware 0 oder unlesbar als „–“, Bestellnummer als Text', () {
    expect(firmwareText(null), '–');
    expect(firmwareText(0), '–');
    expect(firmwareText(0x12), '1.2');
    // MDT am A14: „G1280“, danach Füllbytes und Kennung.
    expect(Diagnostics.printableOrder([0x47, 0x31, 0x32, 0x38, 0x30, 0xFF, 0xFF, 0x01, 0x0F, 0x24]), 'G1280');
    expect(Diagnostics.printableOrder('2CDG110146R0011'.codeUnits), '2CDG110146R0011');
    expect(Diagnostics.printableOrder([0x00, 0x01, 0x0F, 0x24]), '00010F24');
  });

  test('letztes Inventar gilt nur für seine Installation', () async {
    DeviceInventory.debugResetLast();
    addTearDown(DeviceInventory.debugResetLast);
    final tunnel = DemoTunnel();
    await tunnel.connect();
    addTearDown(tunnel.disconnect);
    final run = DeviceInventory(
      tunnel,
      area: 1,
      line: 1,
      from: 1,
      to: 2,
      pause: Duration.zero,
      installation: 'anlage-a',
    );
    await run.start();
    expect(identical(DeviceInventory.lastFor('anlage-a'), const <InventoryEntry>[]), isFalse);
    expect(DeviceInventory.lastFor('anlage-b'), isEmpty);
  });
}
