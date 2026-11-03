import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/diagnostics.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';

import 'fake_gateway.dart';

void main() {
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

  test('Schreiben wird vom Bus bestätigt', () async {
    expect(tunnel.tunnelAddress, 0x1126);
    expect(await tunnel.write(parseGroup('1/1/1')!, small: 1), isTrue);
    expect(gateway.requests.single.last, 0x81); // GroupValueWrite 1
  });

  test('Gateway-Info aus der Selbstbeschreibung', () async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final info = tunnel.gatewayInfo.value!;
    expect(info.name, 'Fake X1');
    expect(tunnel.deviceName.value, 'Fake X1');
    expect(info.mediumText, 'TP1');
    expect(info.addressText, '1.1.250');
    expect(info.serial, '000812345678');
    expect(info.mac, '00:0A:B3:01:02:03');
    expect(info.multicast, '224.0.23.12');
    expect(info.services, {0x02: 2, 0x03: 1, 0x04: 2});
    expect(info.slots.map((s) => (formatIndividual(s.address), s.free)), [('1.1.38', false), ('1.1.39', true)]);
  });

  test('Programmiermodus-Suche findet das Gerät mit gedrückter Taste', () async {
    gateway.programmingMode.add(parseIndividual('1.1.99')!);
    final found = await Diagnostics(tunnel).findProgrammingMode(listen: const Duration(milliseconds: 300));
    expect(found.map(formatIndividual), ['1.1.99']);
  });

  test('Adressprüfung: belegt mit Maskenversion, frei', () async {
    gateway.devices[parseIndividual('1.1.18')!] = 0x07B0;
    final d = Diagnostics(tunnel);

    final present = await d.checkAddress(parseIndividual('1.1.18')!);
    expect(present.state, AddressState.present);
    expect(present.maskText, '07B0');
    // T_Connect, Deskriptor lesen, T_ACK, T_Disconnect
    expect(gateway.requests.map((r) => r[9]), containsAllInOrder([0x80, 0x43, 0xC2, 0x81]));

    final free = await d.checkAddress(parseIndividual('1.1.200')!);
    expect(free.state, AddressState.free);
  });

  test('Adressprüfung: Gateway bestätigt alles, nur Antwort zählt', () async {
    gateway.confirmAll = true;
    gateway.devices[parseIndividual('1.1.18')!] = 0x07B0;
    final d = Diagnostics(tunnel);
    expect((await d.checkAddress(parseIndividual('1.1.18')!)).state, AddressState.present);
    expect((await d.checkAddress(parseIndividual('1.1.250')!)).state, AddressState.free);
    expect(await d.readDeviceInfo(parseIndividual('1.1.250')!), isNull);
  });

  test('Linienscan findet belegte Adressen', () async {
    gateway.devices[parseIndividual('1.1.3')!] = 0x07B0;
    gateway.devices[parseIndividual('1.1.7')!] = 0x0701;
    final run = LineScanRun(tunnel, area: 1, line: 1, from: 0, to: 10);
    await run.start();
    expect(run.checked, 11);
    expect(run.present.map((r) => formatIndividual(r.address)), ['1.1.3', '1.1.7']);
    expect(run.present.last.maskText, '0701');
    run.dispose();
  });

  test('Geräteinfo über Properties', () async {
    final pa = parseIndividual('1.1.18')!;
    gateway.devices[pa] = 0x07B0;
    gateway.properties[pa] = {
      (0, 12): [0x00, 0x08], // Hersteller GIRA
      (0, 11): [0x00, 0x08, 0x12, 0x34, 0x56, 0x78], // Seriennummer
      (0, 15): '2096 00'.codeUnits, // Bestellnummer
      (0, 9): [0x23], // Firmware
      (0, 54): [0x00], // Programmiermodus aus
      (3, 13): [0x00, 0x08, 0xA0, 0x12, 0x05], // Applikation
    };
    final info = (await Diagnostics(tunnel).readDeviceInfo(pa))!;
    expect(info.maskVersion, 0x07B0);
    expect(info.manufacturerId, 8);
    expect(info.serial, '000812345678');
    expect(info.orderInfo, '2096 00');
    expect(info.firmware, 0x23);
    expect(info.programmingMode, isFalse);
    expect(info.hardwareType, isNull); // nicht vorhanden
    expect(info.program, (manufacturer: 8, deviceType: 0xA012, version: 5));
    expect(await Diagnostics(tunnel).readDeviceInfo(parseIndividual('1.1.200')!), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
