import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/teach_in.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

int ga(String s) => parseGroup(s)!;
int pa(String s) => parseIndividual(s)!;

final _t0 = DateTime(2026, 10, 29, 18);

Telegram tg(
  int ms,
  String dest,
  List<int> data, {
  String source = '1.1.30',
  bool small = false,
  TelegramType type = TelegramType.write,
  bool outgoing = false,
}) => Telegram(
  time: _t0.add(Duration(milliseconds: ms)),
  source: pa(source),
  destination: ga(dest),
  type: type,
  data: Uint8List.fromList(data),
  isSmall: small,
  outgoing: outgoing,
);

void main() {
  group('EventCapture', () {
    test('Tastendruck mit Rückmeldung wird ein Ereignis', () {
      final events = <BusEvent>[];
      final capture = EventCapture(onEvent: events.add)
        ..add(tg(0, '1/0/1', [1], small: true))
        ..add(tg(150, '1/1/1', [1], source: '1.1.10', small: true))
        ..add(tg(400, '1/2/1', [128], source: '1.1.11'));
      expect(events, isEmpty);
      capture.tick(_t0.add(const Duration(milliseconds: 900)));
      expect(events, isEmpty, reason: 'Fenster noch offen');
      capture.tick(_t0.add(const Duration(seconds: 3)));
      expect(events, hasLength(1));
      final e = events.single;
      expect(e.initiator, pa('1.1.30'));
      expect(e.commands, [ga('1/0/1')]);
      expect(e.feedback, [ga('1/1/1'), ga('1/2/1')]);
      expect(e.senderOf(ga('1/1/1')), pa('1.1.10'));
      expect(e.guess(ga('1/0/1'))!.dpt, const Dpt(1, 1));
    });

    test('Messwerte beginnen kein Ereignis, außer eingeschaltet', () {
      final events = <BusEvent>[];
      final capture = EventCapture(onEvent: events.add)..add(tg(0, '2/0/0', [0x0C, 0x1A]));
      expect(capture.collecting, isFalse);
      capture.measurements = true;
      capture.add(tg(10, '2/0/1', [0x0C, 0x1A], source: '1.1.40'));
      expect(capture.collecting, isTrue);
      capture.flush();
      expect(events.single.commands, [ga('2/0/1')]);
    });

    test('Eigene, gelesene und ignorierte Adressen beginnen keins', () {
      final events = <BusEvent>[];
      final capture = EventCapture(onEvent: events.add, ignore: {ga('1/0/5')})
        ..add(tg(0, '1/0/1', [1], small: true, outgoing: true))
        ..add(tg(0, '1/0/1', [0], small: true, type: TelegramType.read))
        ..add(tg(0, '1/0/5', [1], small: true));
      expect(capture.collecting, isFalse);
      capture
        ..own = true
        ..add(tg(10, '1/0/1', [1], small: true, outgoing: true))
        ..flush();
      expect(events.single.own, isTrue);
    });

    test('Lücke über dem Fenster trennt zwei Ereignisse', () {
      final events = <BusEvent>[];
      EventCapture(onEvent: events.add)
        ..add(tg(0, '1/0/1', [1], small: true))
        ..add(tg(3000, '1/0/2', [1], small: true))
        ..flush();
      expect([for (final e in events) e.commands.single], [ga('1/0/1'), ga('1/0/2')]);
    });

    test('Fenster zählt ab dem Befehl: Dauerverkehr verkettet nicht und beginnt kein weiteres', () {
      final events = <BusEvent>[];
      final capture = EventCapture(onEvent: events.add);
      for (var ms = 0; ms <= 6000; ms += 1000) {
        capture.add(tg(ms, '1/0/1', [ms ~/ 1000 & 1], small: true));
      }
      capture.flush();
      expect(events.single.end.difference(events.single.start), lessThanOrEqualTo(const Duration(seconds: 1)));
    });
  });

  group('Hintergrundverkehr', () {
    test('Demo-Haus ohne Tastendruck: kein Ereignis', () {
      var now = DateTime(2026, 10, 29, 18);
      DemoTunnel.clock = () => now = now.add(const Duration(milliseconds: 100));
      addTearDown(() => DemoTunnel.clock = DateTime.now);
      final burst = DemoTunnel().simulate(steps: 0).length;
      final tunnel = DemoTunnel()..autoPress = false;
      final traffic = tunnel.simulate(steps: 600);
      tunnel.dispose();
      final events = <BusEvent>[];
      final capture = EventCapture(onEvent: events.add, warmUp: const Duration(seconds: 15))
        // Mitschnitt der Sitzung: der Anfangszustand aller Adressen.
        ..seed(traffic.take(burst));
      for (final t in traffic.skip(burst)) {
        capture.add(t);
      }
      capture.flush();
      expect(traffic.last.time.difference(traffic[burst].time), greaterThan(const Duration(minutes: 2)));
      expect(events, isEmpty, reason: events.map((e) => formatGroup(e.commands.single)).join(', '));
    });

    test('Ohne Mitschnitt: Lernphase, danach fängt ein neuer Absender auf stiller Adresse', () {
      final events = <BusEvent>[];
      final capture = EventCapture(onEvent: events.add, warmUp: const Duration(seconds: 15))
        ..add(tg(0, '2/2/7', [40], source: '1.1.13'))
        ..add(tg(5000, '1/0/4', [1], small: true, source: '1.1.30'));
      expect(capture.learningAt(_t0.add(const Duration(seconds: 5))), isTrue);
      expect(capture.collecting, isFalse, reason: 'in der Lernphase fängt nichts');
      // Laufender Aktor auf einer neuen Adresse: Hintergrund.
      capture.add(tg(20000, '2/2/6', [30], source: '1.1.13'));
      expect(capture.collecting, isFalse);
      // Neuer, bisher stiller Absender: ein Tastendruck.
      capture
        ..add(tg(30000, '1/0/5', [1], small: true, source: '1.1.31'))
        ..flush();
      expect(events.single.commands, [ga('1/0/5')]);
      // Dieselbe Adresse gleich noch einmal: schon bekannt, kein neues Ereignis …
      capture.add(tg(40000, '1/0/5', [0], small: true, source: '1.1.31'));
      expect(capture.collecting, isFalse);
      // … aber die nächste Wippe desselben Tasters.
      capture
        ..add(tg(50000, '1/0/6', [1], small: true, source: '1.1.31'))
        ..flush();
      expect(events.last.commands, [ga('1/0/6')]);
    });

    test('Demo-Taster zählt auch in der Lernphase', () {
      final events = <BusEvent>[];
      EventCapture(onEvent: events.add, warmUp: const Duration(seconds: 15))
        ..add(tg(0, '1/0/1', [1], small: true))
        ..expectPress()
        ..add(tg(100, '1/0/1', [0], small: true))
        ..flush();
      expect(events.single.commands, [ga('1/0/1')]);
    });

    test('Zweimal ungenutzt: beginnt kein Ereignis mehr', () {
      final events = <BusEvent>[];
      final capture = EventCapture(onEvent: events.add);
      final valve = BusEvent([
        tg(0, '2/2/7', [25], source: '1.1.13'),
      ]);
      capture.passed(valve);
      expect(capture.ignore, isEmpty);
      capture.passed(valve);
      expect(capture.ignore, {ga('2/2/7')});
      capture.add(tg(10, '2/2/7', [30], source: '1.1.13'));
      expect(capture.collecting, isFalse);
      // Dritte Adresse desselben Aktors: das Gerät ist Hintergrund.
      capture.passed(
        BusEvent([
          tg(0, '2/2/6', [25], source: '1.1.13'),
        ]),
      );
      expect(capture.ignoreSources, {pa('1.1.13')});
      capture.add(tg(20, '2/2/5', [30], source: '1.1.13'));
      expect(capture.collecting, isFalse);
    });

    test('Messwerte aus: Sensorwerte nach einem Tastendruck fehlen im Ereignis', () {
      final events = <BusEvent>[];
      final capture = EventCapture(onEvent: events.add)
        ..add(tg(0, '1/0/1', [1], small: true))
        ..add(tg(150, '1/1/1', [1], source: '1.1.10', small: true))
        ..add(tg(300, '5/0/0', [0x0C, 0x1A], source: '1.2.1'))
        ..flush();
      expect(events.single.feedback, [ga('1/1/1')]);
      capture
        ..measurements = true
        ..add(tg(2000, '1/0/2', [0], small: true, source: '1.1.31'))
        ..add(tg(2300, '5/0/0', [0x0C, 0x1A], source: '1.2.1'))
        ..flush();
      expect(events.last.feedback, [ga('5/0/0')], reason: 'eingeschaltet bleibt alles drin');
    });

    test('Gedrückt ist nur das erste Telegramm; Rückmeldung nur bei passender Hauptgruppe', () {
      final e = BusEvent([
        tg(0, '1/0/4', [1], small: true),
        tg(80, '2/2/7', [40], source: '1.1.13'),
        tg(150, '1/1/4', [1], source: '1.1.10', small: true),
        tg(200, '2/3/7', [1], source: '1.1.13', small: true),
        tg(300, '1/0/5', [1], small: true),
      ]);
      expect(e.commands, [ga('1/0/4')]);
      expect(e.feedback, [ga('2/2/7'), ga('1/1/4'), ga('2/3/7'), ga('1/0/5')]);
      expect(likelyFeedback(e), {ga('1/1/4')}, reason: 'Ventile und eigenes Folgetelegramm nur „Auch gesehen“');
    });

    test('Ein Status laut Projekt beginnt kein Ereignis', () {
      final events = <BusEvent>[];
      final capture = EventCapture(onEvent: events.add, isStatus: (a) => a == ga('2/4/5'))
        ..add(tg(0, '2/4/5', [1], small: true));
      expect(capture.collecting, isFalse);
      capture.add(tg(10, '1/0/4', [1], small: true, source: '1.1.31'));
      expect(capture.collecting, isTrue);
    });

    test('Messwerte nach einem Schaltbefehl gehören vermutlich nicht dazu', () {
      final e = BusEvent([
        tg(0, '1/0/1', [1], small: true),
        tg(150, '1/1/1', [1], source: '1.1.10', small: true),
        tg(300, '4/0/2', [0x0C, 0x1A], source: '1.2.1'),
      ]);
      expect(unlikelyFeedback(e), {ga('4/0/2')});
      expect(
        unlikelyFeedback(
          BusEvent([
            tg(0, '2/0/0', [0x0C, 0x1A]),
            tg(10, '2/0/1', [0x0C, 0x1A]),
          ]),
        ),
        isEmpty,
      );
    });
  });

  group('teachIn', () {
    final event = BusEvent([
      tg(0, '1/0/1', [1], small: true),
      tg(150, '1/1/1', [1], source: '1.1.10', small: true),
      tg(200, '2/0/0', [0x0C, 0x1A], source: '1.1.40'),
    ]);

    test('Name, Raum, Typ, Status-Adresse und Gerät', () {
      final r = teachIn(
        event,
        TeachInEntry(room: 'Küche', name: 'Deckenlicht', device: 'Taster Küche', dpts: const {}, skip: {ga('2/0/0')}),
      );
      expect(
        [for (final g in r.groups) (formatGroup(g.address), g.name, g.path, g.dpt)],
        [('1/0/1', 'Deckenlicht', 'Küche', const Dpt(1, 1)), ('1/1/1', 'Deckenlicht Status', 'Küche', const Dpt(1, 1))],
      );
      expect(r.devices.single.name, 'Taster Küche');
      expect(r.devices.single.address, pa('1.1.30'));
      expect(r.devices.single.location, 'Küche');
    });

    test('Gewählter Typ gilt, mehrere Rückmeldungen nummeriert, ohne Gerät', () {
      final r = teachIn(event, TeachInEntry(room: '', name: 'Rollladen', dpts: {ga('2/0/0'): const Dpt(9, 1)}));
      expect(r.groups.first.dpt, const Dpt(1, 8), reason: 'Name „Rollladen“ verfeinert den Typ');
      expect(r.groups.first.path, isNull);
      expect([for (final g in r.groups.skip(1)) g.name], ['Rollladen Status 1', 'Rollladen Status 2']);
      expect(r.groups.last.dpt, const Dpt(9, 1));
      expect(r.devices, isEmpty);
    });
  });

  group('HeardAddresses', () {
    test('zählt Werte je Adresse, ohne Eigenes und Leseanfragen', () {
      final heard = HeardAddresses();
      expect(heard.observe(tg(0, '3/1/1', [0x0C, 0x1A], source: '1.1.5')), isTrue);
      expect(heard.observe(tg(100, '3/1/1', [0x0C, 0x1B], source: '1.1.5')), isFalse);
      expect(heard.observe(tg(200, '3/1/2', [], type: TelegramType.read)), isFalse);
      expect(heard.observe(tg(300, '3/1/3', [1], small: true, outgoing: true)), isFalse);
      expect(heard.length, 1);
      final h = heard[ga('3/1/1')]!;
      expect(h.count, 2);
      expect(h.senders, {pa('1.1.5')});
      expect(h.event.commands, [ga('3/1/1')]);
      expect(h.event.feedback, isEmpty);
    });

    test('behält nur die letzten Werte', () {
      final heard = HeardAddresses();
      for (var i = 0; i < 20; i++) {
        heard.observe(tg(i * 100, '3/1/1', [i]));
      }
      expect(heard[ga('3/1/1')]!.samples, hasLength(HeardAddress.maxSamples));
      expect(heard[ga('3/1/1')]!.last.data, [19]);
    });

    test('Länge widerspricht dem Typ im Projekt', () {
      final heard = HeardAddresses()..observe(tg(0, '3/1/1', [0x0C, 0x1A]));
      final h = heard[ga('3/1/1')]!;
      expect(h.contradicts(const Dpt(1, 1)), isTrue, reason: '2 Byte statt Schalten');
      expect(h.contradicts(const Dpt(9, 1)), isFalse);
      expect(h.contradicts(null), isFalse);
    });

    test('offene Adressen nach Adresse sortiert', () {
      final heard = HeardAddresses()
        ..observe(tg(0, '3/1/9', [1], small: true))
        ..observe(tg(1, '1/0/4', [1], small: true))
        ..observe(tg(2, '2/0/0', [1], small: true));
      expect(heard.where((h) => h.address != ga('2/0/0')).map((h) => h.address), [ga('1/0/4'), ga('3/1/9')]);
    });
  });

  test('relatedGroups: gleiche Hauptgruppe und Nummer in anderer Mittelgruppe', () {
    final c = GroupCatalog({
      ga('1/0/4'): GroupInfo(address: ga('1/0/4'), name: 'Deckenlicht', path: 'Küche'),
      ga('1/0/5'): GroupInfo(address: ga('1/0/5'), name: 'Spots'),
      ga('2/0/4'): GroupInfo(address: ga('2/0/4'), name: 'Rollladen'),
      ga('1/2/4'): GroupInfo(address: ga('1/2/4'), name: '1/2/4'),
    });
    expect(relatedGroups(ga('1/1/4'), c).map((g) => g.name), ['Deckenlicht']);
    expect(relatedGroups(ga('1/0/4'), c), isEmpty, reason: 'nicht sie selbst, keine ohne Namen');
  });

  group('mergeLearned', () {
    final project = GroupCatalog({
      ga('1/0/1'): GroupInfo(address: ga('1/0/1'), name: 'Projekt Licht', dpt: const Dpt(1, 1)),
      ga('1/0/2'): GroupInfo(address: ga('1/0/2'), name: 'Projekt ohne Typ'),
    }, projectName: 'Haus');
    final learned = GroupCatalog(
      {
        ga('1/0/1'): GroupInfo(address: ga('1/0/1'), name: 'Mein Licht', dpt: const Dpt(1, 1)),
        ga('1/0/2'): GroupInfo(address: ga('1/0/2'), name: 'Mein Rollladen', dpt: const Dpt(1, 8)),
        ga('1/0/3'): GroupInfo(address: ga('1/0/3'), name: 'Nur angelernt', path: 'Bad'),
      },
      devices: {pa('1.1.30'): DeviceInfo(address: pa('1.1.30'), name: 'Taster Bad')},
    );

    test('Projekt hat Vorrang, Angelerntes füllt Lücken', () {
      final m = mergeLearned(project, learned);
      expect(m.projectName, 'Haus');
      expect(m[ga('1/0/1')]!.name, 'Projekt Licht');
      expect(m[ga('1/0/2')]!.name, 'Projekt ohne Typ');
      expect(m[ga('1/0/2')]!.dpt, const Dpt(1, 8));
      expect(m[ga('1/0/3')]!.name, 'Nur angelernt');
      expect(m.devices[pa('1.1.30')]!.name, 'Taster Bad');
      expect(knownRooms(m), ['Bad']);
    });

    test('Im Projekt ohne Namen (ETS-Vorgabe): der angelernte Name gilt', () {
      final stale = GroupCatalog({
        ga('1/0/1'): GroupInfo(address: ga('1/0/1'), name: 'Neue Gruppenadresse', path: 'Licht', dpt: const Dpt(1, 1)),
        ga('1/0/2'): GroupInfo(address: ga('1/0/2'), name: '1/0/2'),
      });
      final m = mergeLearned(stale, learned);
      expect(m[ga('1/0/1')]!.name, 'Mein Licht');
      expect(m[ga('1/0/1')]!.path, 'Licht', reason: 'Pfad bleibt der des Projekts');
      expect(m[ga('1/0/2')]!.name, 'Mein Rollladen');
      expect(m[ga('1/0/2')]!.dpt, const Dpt(1, 8));
    });

    test('Vorgabe-Name im Stil des Projekts, nicht im zuletzt geladenen', () {
      // Zweistufiges Projekt: 1/0/2 heißt dort „1/2“. Der globale Stil ist noch dreistufig.
      final twoLevel = GroupCatalog({
        ga('1/0/2'): GroupInfo(address: ga('1/0/2'), name: '1/2'),
        ga('1/0/1'): GroupInfo(address: ga('1/0/1'), name: '1/0/1', dpt: const Dpt(1, 1)),
      }, style: GroupStyle.twoLevel);
      final m = mergeLearned(twoLevel, learned);
      expect(m[ga('1/0/2')]!.name, 'Mein Rollladen');
      expect(m[ga('1/0/1')]!.name, '1/0/1', reason: 'im zweistufigen Projekt ein gepflegter Name');
    });

    test('Ohne Angelerntes bleibt das Projekt dasselbe Objekt', () {
      expect(identical(mergeLearned(project, GroupCatalog.empty), project), isTrue);
      expect(identical(mergeLearned(GroupCatalog.empty, learned), learned), isTrue);
    });
  });

  group('CatalogStore', () {
    late Directory dir;
    final store = CatalogStore.instance;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('knx_learn');
      AppStorage.instance = IoStorage(dir);
      await store.reload();
    });

    tearDown(() async {
      await store.clearLearned();
      store.catalog = GroupCatalog.empty;
      await dir.delete(recursive: true);
    });

    test('Angelerntes bleibt über Projekt-Import, Entfernen und Neuladen', () async {
      await store.learn([GroupInfo(address: ga('1/0/3'), name: 'Bad Licht', dpt: const Dpt(1, 1))]);
      expect(store.catalog[ga('1/0/3')]!.name, 'Bad Licht');
      expect(store.project.isEmpty, isTrue);
      expect(store.dptOf(ga('1/0/3')), const Dpt(1, 1));

      await store.adopt(
        GroupCatalog({ga('1/0/1'): GroupInfo(address: ga('1/0/1'), name: 'Projekt')}),
        name: 'haus.knxproj',
      );
      expect(store.catalog.length, 2);
      await store.clear();
      expect(store.catalog[ga('1/0/3')]!.name, 'Bad Licht');

      await store.reload();
      expect(store.learned.length, 1);
      await store.forget(ga('1/0/3'));
      expect(store.catalog.isEmpty, isTrue);
    });

    test('Demo: eigenes Angelerntes ausgeblendet, Demo-Angelerntes verfällt', () async {
      await store.learn([GroupInfo(address: ga('9/0/0'), name: 'Eigenes')]);
      store.beginDemo(demoCatalog());
      expect(store.catalog[ga('9/0/0')], isNull);
      await store.learn([GroupInfo(address: ga('9/0/1'), name: 'In der Demo')]);
      // Verschachtelt (Einführung aus der Demo): erst das äußere Ende zählt.
      store.beginDemo(demoCatalog());
      store.endDemo();
      expect(store.catalog[ga('9/0/1')]!.name, 'In der Demo');
      store.endDemo();
      expect(store.catalog[ga('9/0/0')]!.name, 'Eigenes');
      expect(store.catalog[ga('9/0/1')], isNull);
      await store.reload();
      expect(store.learned.groups.keys, [ga('9/0/0')]);
    });
  });
}
