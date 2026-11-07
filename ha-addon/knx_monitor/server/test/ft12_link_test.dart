import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:knx_monitor_server/box.dart';
import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

import 'fake_gateway.dart' show until;
import 'fake_kberry.dart';

/// L_Data.req: GroupValueWrite an 1/2/3, Wert 0, Absender 0.0.0.
final requestOff = Uint8List.fromList([0x11, 0x00, 0xBC, 0xE0, 0x00, 0x00, 0x0A, 0x03, 0x01, 0x00, 0x80]);

/// L_Busmon.ind mit Status und Zeitstempel: 1.1.5 → 1/1/1 schreibt 1, Prüfsumme stimmt.
final busmonWrite = [
  0x2B, 0x07, 0x03, 0x01, 0x00, 0x04, 0x02, 0x12, 0x34, //
  0xBC, 0x11, 0x05, 0x09, 0x01, 0xE1, 0x00, 0x81, 0x3F,
];

void main() {
  late FakeKberry module;
  Ft12CemiLink link({bool busmonitor = false, int? address, FakeKberry? fake}) => Ft12CemiLink(
    open: (baud) async => module = fake ?? FakeKberry(lineBaud: baud),
    busmonitor: busmonitor,
    requestedAddress: address,
    keepalive: const Duration(milliseconds: 100),
    confirmTimeout: const Duration(milliseconds: 300),
  );

  group('Ft12CemiLink', () {
    test('Link Layer: liefert L_Data.ind, sendet mit eigener Adresse, stellt beim Trennen zurück', () async {
      final l = link();
      final frames = <Uint8List>[];
      l.frames.listen(frames.add);
      await l.connect();
      expect(module.commMode, 0x00);
      expect(l.baud, 19200);
      expect(l.address, 0xFFFF);
      expect(l.label, 'KNX-HAT Link Layer 15.15.255');
      await until(() => frames.isNotEmpty);
      expect(frames.first, module.linkFrames.first);

      await l.send(requestOff);
      final sent = module.requests.single;
      expect(sent.sublist(4, 6), [0xFF, 0xFF], reason: 'Absender = eigene Adresse');
      await until(() => frames.length == 2);
      expect(frames.last[0], 0x2E, reason: 'Bestätigung geht wie beim Tunnel an die Ansichten');

      await l.close();
      expect(module.commMode, 0xF0, reason: 'zurück im BAOS-Modus');
      expect(module.closed, isTrue);
      expect(await l.lost, 'Getrennt');
    });

    test('negative confirmation (NCON) fails the send', () async {
      final l = link();
      await l.connect();
      module.negativeConfirm = true;
      await expectLater(
        l.send(requestOff),
        throwsA(isA<LinkException>().having((e) => e.message, 'message', contains('NCON'))),
      );
      module.negativeConfirm = false;
      await l.send(requestOff);
      await l.close();
    });

    test('setzt die gewünschte Adresse im Geräteobjekt', () async {
      final l = link(address: 0x11FA);
      await l.connect();
      expect(module.address, 0x11FA);
      expect(l.address, 0x11FA);
      await l.close();
    });

    test('Busmonitor: rohe Frames mit Quittungen, Senden abgelehnt', () async {
      final l = link(busmonitor: true);
      final frames = <Uint8List>[];
      l.frames.listen(frames.add);
      await l.connect();
      expect(module.commMode, 0x01);
      await until(() => frames.length == module.busmonFrames.length);
      expect(frames.every((f) => f[0] == 0x2B), isTrue);
      await expectLater(l.send(requestOff), throwsA(isA<LinkException>()));
      await l.close();
      expect(module.commMode, 0xF0);
    });

    test('ohne Busmonitor im Modul: verständlicher Fehler, Modul bleibt im BAOS-Modus', () async {
      final l = link(busmonitor: true, fake: FakeKberry(modes: 0x0001));
      await expectLater(
        l.connect(),
        throwsA(isA<LinkException>().having((e) => e.message, 'message', contains('Busmonitor'))),
      );
      expect(module.commMode, 0xF0);
      expect(module.closed, isTrue);
    });

    test('Modul stumm: probiert beide Baudraten, dann Fehler', () async {
      final tried = <int>[];
      final l = Ft12CemiLink(
        open: (baud) async {
          tried.add(baud);
          return FakeKberry(baud: 9600, lineBaud: baud);
        },
      );
      await expectLater(l.connect(), throwsA(isA<LinkException>()));
      expect(tried, [19200, 115200]);
    });

    test('findet 115200 Baud', () async {
      final l = Ft12CemiLink(open: (baud) async => module = FakeKberry(baud: 115200, lineBaud: baud));
      await l.connect();
      expect(l.baud, 115200);
      await l.close();
    });

    test('M_Reset.ind: Verbindung gilt als verloren, Leitung wird freigegeben', () async {
      final l = link();
      await l.connect();
      module.restart();
      expect(await l.lost.timeout(const Duration(seconds: 2)), 'KNX-HAT neu gestartet');
      await until(() => module.closed);
    });

    test('Modul antwortet nicht mehr: Lebenszeichen schlägt fehl', () async {
      final l = link();
      await l.connect();
      module.mute = true;
      expect(await l.lost.timeout(const Duration(seconds: 5)), contains('antwortet nicht'));
      await until(() => module.closed);
    });

    test('Lesefehler: Verbindung verloren', () async {
      final fake = _BreakingKberry();
      final l = link(fake: fake);
      await l.connect();
      fake.broken = true;
      expect(await l.lost.timeout(const Duration(seconds: 2)), contains('Lesefehler'));
    });

    test('wiederholter Rahmen (Quittung verloren) kommt nur einmal', () async {
      final l = link();
      final frames = <Uint8List>[];
      l.frames.listen(frames.add);
      await l.connect();
      await until(() => frames.length == 1);
      module
        ..push([0x29, 0x00, 0xBC, 0xE0, 0x11, 0x06, 0x09, 0x02, 0x01, 0x00, 0x80])
        ..repeatLast();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(frames, hasLength(2));
      await l.close();
    });

    test('ohne Bestätigung: Senden schlägt fehl, Verbindung bleibt', () async {
      final l = link();
      await l.connect();
      module.confirmRequests = false;
      await expectLater(l.send(requestOff), throwsA(isA<LinkException>()));
      expect(module.requests, hasLength(1));
      await l.close();
    });

    test('neuer Link wartet, bis der alte die Leitung freigegeben hat', () async {
      final first = link();
      await first.connect();
      final old = module;
      unawaited(first.close());
      final second = link();
      await second.connect();
      expect(old.closed, isTrue);
      expect(old.commMode, 0xF0);
      await second.close();
    });
  });

  test('Link wartet, bis eine laufende HAT-Prüfung den UART freigibt', () async {
    final probe = KberryService(
      device: '/dev/ttyTEST',
      open: (baud) async => FakeKberry(lineBaud: baud),
    );
    expect(probe.start(const Duration(milliseconds: 80)), isTrue);
    final l = Ft12CemiLink(
      device: '/dev/ttyTEST',
      open: (baud) async => module = FakeKberry(lineBaud: baud),
    );
    await l.connect();
    expect(probe.running, isFalse, reason: 'erst nach der Prüfung verbunden');
    expect(probe.report?['steps'], hasLength(kberrySteps.length));
    await l.close();
  });

  group('busmonToLData', () {
    test('Datentelegramm wird zu L_Data.ind wie vom Tunnel', () {
      expect(busmonToLData(Uint8List.fromList(busmonWrite)), [
        0x29, 0x00, 0xBC, 0xE0, 0x11, 0x05, 0x09, 0x01, 0x01, 0x00, 0x81, //
      ]);
      // Wiederholung (Bit 5 gelöscht) bleibt erkennbar.
      final repeated = List.of(busmonWrite)
        ..[9] = 0x9C
        ..[17] = 0x1F;
      final cemi = busmonToLData(Uint8List.fromList(repeated))!;
      expect(telegramJson(cemi, DateTime(2026))!['rp'], true);
    });

    test('Quittungen, gestörte und abgeschnittene Frames: nichts', () {
      expect(busmonToLData(Uint8List.fromList([0x2B, 0x00, 0xCC])), isNull);
      expect(busmonToLData(Uint8List.fromList(List.of(busmonWrite)..[17] = 0x3A)), isNull, reason: 'Prüfsumme');
      expect(busmonToLData(Uint8List.fromList(List.of(busmonWrite)..[4] = 0x80)), isNull, reason: 'Frame-Fehler');
      expect(busmonToLData(Uint8List.fromList(busmonWrite.sublist(0, 15))), isNull);
      expect(busmonToLData(Uint8List.fromList([0x29, 0x00, 0xBC])), isNull);
    });
  });

  group('BusService mit KNX-HAT', () {
    late Directory data;
    late BusService bus;
    setUp(() async {
      data = await Directory.systemTemp.createTemp('knx_hat');
      bus = BusService(
        data,
        hatDevice: '/dev/null',
        describe: (_, _) async => fail('kein Gateway zu beschreiben'),
        link: (c) => c.mode == 'hat'
            ? Ft12CemiLink(
                open: (baud) async => module = FakeKberry(lineBaud: baud)..busmonFrames.add(busmonWrite),
                busmonitor: c.hatBusmonitor,
                requestedAddress: parseIndividual(c.hatAddress),
              )
            : defaultLink(c),
      );
      await bus.start();
    });
    tearDown(() async {
      await bus.shutdown();
      await data.delete(recursive: true);
    });

    test('Busmonitor: zeichnet Datentelegramme auf, Quittungen gehen nur an die Ansichten', () async {
      expect((bus.status()['hat']! as Map)['present'], true);
      await bus.update({'enabled': true, 'mode': 'hat', 'hatBusmonitor': true, 'flushSeconds': 0});
      await until(() => bus.state == 'connected');
      expect(bus.status()['link'], 'KNX-HAT Busmonitor 15.15.255');
      expect(module.commMode, 0x01);
      await until(() => bus.today == 1);
      await bus.recorder.flush();
      final day = File('${data.path}/history/${Recorder.dayName(DateTime.now())}.ndjson');
      final line = jsonDecode((await day.readAsLines()).single) as Map<String, Object?>;
      expect(line['s'], 0x1105);
      expect(line['d'], 0x0901);
      expect(line['x'], '01');
    });

    test('Wechsel zurück auf UDP stellt das Modul zurück', () async {
      await bus.update({'enabled': true, 'mode': 'hat', 'hatAddress': '1.1.250'});
      await until(() => bus.state == 'connected');
      expect(module.commMode, 0x00);
      expect(module.address, 0x11FA);
      await bus.update({'mode': 'udp', 'host': ''});
      await until(() => module.closed);
      expect(module.commMode, 0xF0);
    });
  });

  test('Wiederanlauf nach Busspannungsausfall: Modul kommt mit anderer Baudrate zurück', () async {
    // Feldtest 7.11.2026: Nach einem Neustart meldet der kBerry M_Reset.ind, der
    // Server verbindet in 2 s neu. Ob das Modul danach bei 19200 oder bei der
    // eingestellten Rate antwortet, hängt am Modul; der Server findet beide.
    final data = await Directory.systemTemp.createTemp('knx_hat_restart');
    var moduleBaud = 115200;
    FakeKberry? current;
    final bus = BusService(
      data,
      hatDevice: '/dev/null',
      describe: (_, _) async => fail('kein Gateway zu beschreiben'),
      link: (c) => Ft12CemiLink(
        open: (baud) async => current = FakeKberry(baud: moduleBaud, lineBaud: baud),
        busmonitor: c.hatBusmonitor,
      ),
    );
    await bus.start();
    try {
      await bus.update({'enabled': true, 'mode': 'hat'});
      await until(() => bus.state == 'connected');
      final before = current!;
      expect(before.lineBaud, 115200);
      expect(before.commMode, 0x00);

      moduleBaud = 19200;
      before.restart();
      await until(() => before.closed);
      await until(() => bus.state == 'connected' && !identical(current, before) && current!.commMode == 0x00);
      expect(current!.lineBaud, 19200);
      expect(bus.status()['link'], 'KNX-HAT Link Layer 15.15.255');
    } finally {
      await bus.shutdown();
      await data.delete(recursive: true);
    }
  });

  test('BusConfig: nur serielle Geräte, Adresse geprüft', () {
    expect(BusConfig.fromJson({'mode': 'hat', 'device': '/etc/passwd'}).device, '/dev/ttyAMA0');
    expect(BusConfig.fromJson({'mode': 'hat', 'device': '/dev/ttyUSB0'}).device, '/dev/ttyUSB0');
    expect(BusConfig.fromJson({'mode': 'hat', 'device': '/dev/../etc/x'}).device, '/dev/ttyAMA0');
    expect(BusConfig.fromJson({'hatAddress': 'x'}).hatAddress, isNull);
    final c = BusConfig.fromJson({'mode': 'hat', 'hatAddress': '1.1.250', 'hatBusmonitor': true});
    expect(c.mode, 'hat');
    expect(BusConfig.fromJson(c.toJson()).toJson(), c.toJson());
  });
}

/// Modul, dessen Leitung auf Wunsch beim Lesen scheitert (abgezogen).
class _BreakingKberry extends FakeKberry {
  bool broken = false;
  @override
  Future<Uint8List> read() async {
    if (broken) throw const FileSystemException('Eingabe/Ausgabe-Fehler');
    return super.read();
  }
}
