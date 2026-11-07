import 'dart:io';
import 'dart:typed_data';

import 'package:knx_monitor_server/box.dart';
import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

void main() {
  group('Busmonitor-Zähler', () {
    Uint8List frame(List<int> raw, {int status = 0}) => Uint8List.fromList([0x2B, 3, 0x03, 1, status, ...raw]);
    // Standard-Frame 1.1.5 → 1/2/3 mit stimmiger Prüfsumme.
    final data = () {
      final body = [0xBC, 0x11, 0x05, 0x0A, 0x03, 0xE1, 0x00, 0x81];
      return [...body, ~body.fold<int>(0, (a, b) => a ^ b) & 0xFF];
    }();

    test('zählt Daten, Quittungen, Ablehnungen und gestörte Frames', () {
      final c = BusmonCounters()
        ..add(frame(data))
        ..add(frame([0xCC]))
        ..add(frame(data))
        ..add(frame([0x0C]))
        ..add(frame([0xC0]))
        ..add(frame(data, status: 0x80))
        ..add(frame([...data.sublist(0, 8), 0x00]));
      expect(c.toJson(), {'data': 2, 'acks': 1, 'naks': 1, 'busy': 1, 'damaged': 2, 'orphanAcks': 0, 'seqGaps': 0});
    });

    test('Quittung ohne Datenrahmen davor fällt auf (Issue #1)', () {
      final c = BusmonCounters()
        ..add(frame([0xCC]))
        ..add(frame(data))
        ..add(frame([0xCC]))
        ..add(frame([0xCC]));
      expect(c.orphanAcks, 2);
      expect(c.acks, 3);
    });

    test('Lücken in der Folgenummer, wie am kBerry gemessen (7.11.2026)', () {
      // Datenrahmen 0, ACK 1, Datenrahmen 2 fehlt, ACK 3, …, über den Überlauf 7 → 0.
      final c = BusmonCounters()
        ..add(frame(data, status: 0))
        ..add(frame([0xCC], status: 1))
        ..add(frame([0xCC], status: 3))
        ..add(frame(data, status: 6))
        ..add(frame([0xCC], status: 7))
        ..add(frame([0xCC], status: 1));
      expect(c.seqGaps, 4, reason: '2, 4, 5 und 0 fehlen');
      expect(c.orphanAcks, 2);
      expect(c.data, 2);
    });

    test('nach dem Neuverbinden zählt die Folgenummer von vorn', () {
      final c = BusmonCounters()
        ..add(frame(data, status: 5))
        ..resync()
        ..add(frame([0xCC], status: 0));
      expect(c.seqGaps, 0);
      expect(c.orphanAcks, 1, reason: 'kein Datenrahmen aus der alten Verbindung');
    });

    test('Schnittstellen ohne Nummerierung (immer 0) haben keine Lücken', () {
      final c = BusmonCounters();
      for (var i = 0; i < 5; i++) {
        c.add(frame(data));
      }
      expect(c.seqGaps, 0);
    });
  });

  group('Add-on ohne HAT', () {
    late Directory data;
    setUp(() async => data = await Directory.systemTemp.createTemp('knx_nohat'));
    tearDown(() => data.delete(recursive: true));

    test('lehnt die Verbindungsart ab und bietet sie nicht an', () async {
      final bus = BusService(data, link: (_) => throw StateError('darf nicht verbinden'));
      await bus.start();
      expect(bus.status().containsKey('hat'), isFalse);
      await expectLater(bus.update({'enabled': true, 'mode': 'hat'}), throwsA(isA<BusProbeException>()));
      expect(bus.config.mode, 'udp');
      expect(bus.config.enabled, isFalse);
      await bus.shutdown();
    });

    test('das Image kann den HAT auch nicht: kein stty, kein UART', () async {
      expect(await File('../Dockerfile').readAsString(), contains('FROM scratch'));
      expect(await File('../config.yaml').readAsString(), isNot(contains('uart:')));
    });
  });
}
