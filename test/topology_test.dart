import 'package:knx_monitor/model/activity_range.dart';

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/topology.dart';

void main() {
  int pa(String s) => parseIndividual(s)!;
  int ga(String s) => parseGroup(s)!;

  // Zwei Linien wie in der Testanlage: 1.1 (Gateway), 1.2 hinter Koppler 1.2.0.
  final catalog = GroupCatalog(
    {
      ga('1/1/72'): GroupInfo(
        address: ga('1/1/72'),
        name: 'Außenleuchte Terrasse Schalten',
        links: [
          GroupLink(device: pa('1.1.10'), sends: true),
          GroupLink(device: pa('1.2.5')),
        ],
      ),
      ga('1/4/72'): GroupInfo(
        address: ga('1/4/72'),
        name: 'Außenleuchte Terrasse Rückmeldung',
        links: [
          GroupLink(device: pa('1.2.5'), sends: true),
          GroupLink(device: pa('1.1.10')),
        ],
      ),
      ga('8/1/0'): GroupInfo(
        address: ga('8/1/0'),
        name: 'Regen (nur in 1.2 verwendet)',
        links: [
          GroupLink(device: pa('1.2.20'), sends: true),
          GroupLink(device: pa('1.2.5')),
        ],
      ),
    },
    devices: {
      for (final (a, n) in [('1.1.10', 'Taster'), ('1.2.0', 'Linienkoppler'), ('1.2.5', 'Aktor'), ('1.2.20', 'Wetter')])
        pa(a): DeviceInfo(address: pa(a), name: n),
    },
  );

  Telegram t(String src, String dst, int hops) => Telegram(
    time: DateTime(2026),
    source: pa(src),
    destination: ga(dst),
    type: TelegramType.write,
    data: Uint8List.fromList([1]),
    isSmall: true,
    hopCount: hops,
  );

  test('Linien, Koppler, linienübergreifende Adressen', () {
    final topo = Topology.build(catalog, [t('1.1.10', '1/1/72', 6), t('1.2.5', '1/4/72', 5)], gatewayLine: 0x11);
    expect(topo.lines.map((l) => formatLine(l.line)), ['1.1', '1.2']);
    final l2 = topo.line(0x12)!;
    expect(l2.coupler!.name, 'Linienkoppler');
    expect(l2.devices.map((d) => d.name), ['Aktor', 'Wetter']);
    expect(l2.couplersToGateway, 1);
    expect(topo.cross.map((c) => formatGroup(c.address)), ['1/1/72', '1/4/72']);
    final fb = topo.cross.last;
    expect(fb.senderLines, {0x12});
    expect(fb.seenFrom, {0x12: 1});
    expect(topo.mismatches, isEmpty);
    expect(topo.unneeded, isEmpty);
  });

  test('Gerät mit unpassendem Hop-Count und unnötig weitergeleitete Telegramme', () {
    final topo = Topology.build(catalog, [
      t('1.2.5', '1/4/72', 5),
      t('1.2.20', '8/1/0', 5), // nur 1.2 hört zu → Koppler leitet unnötig weiter
      t('1.2.21', '8/1/0', 6), // Adresse 1.2, kommt aber ohne Koppler → sitzt in 1.1
    ], gatewayLine: 0x11);
    expect(topo.unneeded, {ga('8/1/0'): 2});
    final m = topo.mismatches.single;
    expect(formatIndividual(m.source), '1.2.21');
    expect(m.observed, 6);
    expect(m.expected, 5);
  });

  test('Gateway-Linie ohne Tunneladresse geschätzt', () {
    final topo = Topology.build(catalog, [t('1.1.10', '1/1/72', 6), t('1.2.5', '1/4/72', 5)]);
    expect(topo.gatewayLine, 0x11);
  });

  test('Koppler-Prüfung: Antwort nur aus der anderen Linie zählt', () async {
    final answers = StreamController<Telegram>.broadcast();
    Telegram response(String src, String dst) => Telegram(
      time: DateTime(2026),
      source: pa(src),
      destination: ga(dst),
      type: TelegramType.response,
      data: Uint8List.fromList([1]),
      isSmall: true,
      hopCount: 5,
    );
    final run = CouplerCheckRun(
      candidates: [ga('1/4/72'), ga('1/4/73'), ga('1/4/74')],
      gatewayLine: 0x11,
      answers: answers.stream,
      read: (a) async {
        if (a == ga('1/4/72')) answers.add(response('1.2.5', '1/4/72'));
        if (a == ga('1/4/74')) answers.add(response('1.1.7', '1/4/74')); // aus der eigenen Linie
      },
    );
    await run.run();
    expect(run.results[ga('1/4/72')], CouplerCheck.passed);
    expect(formatIndividual(run.responders[ga('1/4/72')]!), '1.2.5');
    expect(run.results[ga('1/4/73')], CouplerCheck.noAnswer);
    expect(run.results[ga('1/4/74')], CouplerCheck.noAnswer);
    await answers.close();
  }, timeout: const Timeout(Duration(seconds: 15)));

  test('Tunnel zählen nicht als Geräte; alte Kataloge werden erkannt', () {
    // Katalog im alten Format: Tunnel nur am Namen erkennbar.
    final json = {
      'groups': <Object>[],
      'devices': [
        {'a': pa('1.1.35'), 'n': 'Gira X1', 'p': 'X1'},
        {'a': pa('1.1.36'), 'n': 'Gira X1 · Tunnel 1', 'p': 'X1'},
        {'a': pa('1.1.37'), 'n': 'Gira X1 · Tunnel 2', 'p': 'X1'},
        {'a': pa('1.1.50'), 'n': 'Glastaster · Flur', 'p': 'GT2'},
      ],
    };
    final topo = Topology.build(GroupCatalog.fromJson(json), const []);
    final line = topo.line(0x11)!;
    expect(line.devices.map((d) => formatIndividual(d.address)), ['1.1.35', '1.1.50']);
    expect(line.tunnels.map((d) => formatIndividual(d.address)), ['1.1.36', '1.1.37']);
  });

  test('Koppler-Verkehr: Richtungen aus Quelladresse und Empfängern laut Projekt', () {
    Telegram at(String src, String dst, int minute) => Telegram(
      time: DateTime(2026, 1, 1, 12, minute),
      source: pa(src),
      destination: ga(dst),
      type: TelegramType.write,
      data: Uint8List.fromList([1]),
      isSmall: true,
      hopCount: src.startsWith('1.2') ? 5 : 6,
    );
    final traffic = CouplerTraffic.build(
      catalog,
      [
        at('1.1.10', '1/1/72', 1),
        at('1.1.10', '1/1/72', 2),
        at('1.2.5', '1/4/72', 3),
        at('1.2.20', '8/1/0', 4), // nur 1.2 hört zu: kam trotzdem am Gateway an
        at('1.2.9', '1/4/72', 5), // zweiter Absender, seltener
      ],
      0x12,
      gatewayLine: 0x11,
    );

    expect(traffic.coupler!.name, 'Linienkoppler');
    // Hinaus zuerst (1.2 → 1.1), dann hinein (1.1 → 1.2).
    expect(traffic.flows.map((f) => '${formatLine(f.from)}>${formatLine(f.to)}'), ['1.2>1.1', '1.1>1.2']);
    final out = traffic.flows.first;
    expect(out.telegrams, 2);
    final fb = out.groups.single;
    expect(formatGroup(fb.address), '1/4/72');
    expect(fb.count, 2);
    expect(fb.last, DateTime(2026, 1, 1, 12, 5));
    expect(fb.senders, {pa('1.2.5'): 1, pa('1.2.9'): 1});
    final into = traffic.flows.last;
    expect(into.telegrams, 2);
    expect(formatIndividual(into.groups.single.sender!), '1.1.10');
    expect(traffic.maxTelegrams, 2);
    // Drei Telegramme aus 1.2 am Gateway gesehen, eins davon ohne Empfänger außerhalb.
    expect(traffic.seenAtGateway, 3);
    expect(traffic.withoutReceiver, 1);
  });

  test('Koppler-Verkehr: Adressen laut Projekt auch ohne Telegramme, Absender aus dem Projekt', () {
    final traffic = CouplerTraffic.build(catalog, const [], 0x12, gatewayLine: 0x11);
    expect(traffic.flows.length, 2);
    for (final f in traffic.flows) {
      expect(f.telegrams, 0);
      expect(f.groups.single.last, isNull);
    }
    expect(formatIndividual(traffic.flows.first.groups.single.sender!), '1.2.5');
    expect(traffic.seenAtGateway, 0);
  });

  test('Koppler-Verkehr: dritte Linie nur über ihren eigenen Koppler', () {
    final three = GroupCatalog({
      ga('3/0/1'): GroupInfo(
        address: ga('3/0/1'),
        name: 'Zentral Aus',
        links: [
          GroupLink(device: pa('1.1.10'), sends: true),
          GroupLink(device: pa('1.2.5')),
          GroupLink(device: pa('1.3.5')),
        ],
      ),
    }, devices: const {});
    final t13 = CouplerTraffic.build(three, [t('1.1.10', '3/0/1', 6)], 0x13, gatewayLine: 0x11);
    // 1.1 → 1.2 läuft nicht über 1.3.0.
    expect(t13.flows.map((f) => '${formatLine(f.from)}>${formatLine(f.to)}'), ['1.1>1.3']);
    expect(t13.flows.single.telegrams, 1);
    expect(t13.coupler, isNull);
  });

  test('Verlauf je Linie: nur Absender der Linie, Abschnitte im gewählten Zeitraum', () {
    final now = DateTime(2026, 10, 21, 12);
    Telegram at(int source, Duration ago) => Telegram(
      time: now.subtract(ago),
      source: source,
      destination: 0x0801,
      type: TelegramType.write,
      data: Uint8List.fromList([1]),
      isSmall: true,
    );
    final log = [
      at(0x1105, const Duration(milliseconds: 500)),
      at(0x1107, const Duration(milliseconds: 700)),
      at(0x120A, const Duration(milliseconds: 500)),
      at(0x1105, const Duration(seconds: 30)),
      at(0x1105, const Duration(minutes: 5)),
    ];
    final seconds = lineActivity(log, 0x11, ActivityRange.seconds, now);
    expect(seconds.length, 60);
    expect(seconds.last, 2);
    expect(seconds[30], 1);
    expect(seconds.fold(0, (a, b) => a + b), 3);
    final hour = lineActivity(log, 0x11, ActivityRange.hour, now);
    expect(hour.fold(0, (a, b) => a + b), 4);
    expect(hour[55], 1);
    expect(lineActivity(log, 0x12, ActivityRange.today, now).fold(0, (a, b) => a + b), 1);
  });

  test('Fremde Adresse ohne Koppler gehört zur Gateway-Linie, keine erfundene Linie', () {
    // 15.15.255 (Werksadresse, z. B. KNX-HAT einer Box) fragt 1/1/72 ab und
    // kommt mit Hop 6 an: Linie 15.15 gibt es im Projekt nicht.
    final topo = Topology.build(catalog, [
      t('1.1.10', '1/1/72', 6),
      t('1.2.5', '1/4/72', 5),
      t('15.15.255', '1/1/72', 6),
      t('15.15.255', '1/1/72', 6),
    ]);
    expect(topo.gatewayLine, 0x11);
    expect(topo.lines.map((l) => l.line), [0x11, 0x12]);
    expect(topo.strays, {factoryAddress});
    expect(topo.lineOfSource(factoryAddress), 0x11);
    expect(topo.line(0x11)!.activeSources[factoryAddress], 6);
    expect(topo.line(0x11)!.telegrams, 3);
    expect(topo.mismatches, isEmpty);
    expect(topo.unneeded, isEmpty);
  });

  test('Fremde Linie hinter einem Koppler bleibt eine Linie', () {
    final topo = Topology.build(catalog, [t('1.1.10', '1/1/72', 6), t('1.3.4', '1/1/72', 5)]);
    expect(topo.strays, isEmpty);
    expect(topo.lines.map((l) => l.line), containsAll([0x11, 0x13]));
  });

  test('Eigene Adresse auf einer Linie außerhalb des Projekts zeigt nicht die Gateway-Linie', () {
    // Box mit KNX-HAT auf Werksadresse: Gateway-Linie wird geschätzt.
    final topo = Topology.build(catalog, [t('1.1.10', '1/1/72', 6), t('15.15.255', '1/1/72', 6)], gatewayLine: 0xFF);
    expect(topo.gatewayLine, 0x11);
    expect(topo.strays, {factoryAddress});
  });

  test('Koppler-Verkehr: fremde Adresse auf der Gateway-Linie zählt als Gateway-Linie', () {
    // 15.15.255 schreibt auf 1/1/72 (Empfänger in 1.2): Richtung 1.1 → 1.2, nicht 15.15 → 1.2.
    final log = [t('1.1.10', '1/1/72', 6), t('15.15.255', '1/1/72', 6)];
    final topo = Topology.build(catalog, log);
    final traffic = CouplerTraffic.build(catalog, log, 0x12, gatewayLine: topo.gatewayLine, origin: topo.lineOfSource);
    expect(traffic.flows.map((f) => (f.from, f.to)), isNot(contains((0xFF, 0x12))));
    expect(traffic.flows.firstWhere((f) => f.from == 0x11 && f.to == 0x12).telegrams, 2);
  });
}
