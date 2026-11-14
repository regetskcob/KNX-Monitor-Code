import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/channel_test.dart';
import 'package:knx_monitor/model/device_channels.dart';

void main() {
  final aktor = parseIndividual('1.1.10')!;

  ChannelTest build() {
    GroupInfo g(String a, String name, Dpt dpt, String text, {bool sends = false}) => GroupInfo(
      address: parseGroup(a)!,
      name: name,
      dpt: dpt,
      links: [GroupLink(device: aktor, text: text, sends: sends)],
    );
    final catalog = GroupCatalog({
      for (final x in [
        g('1/0/1', 'Küche Decke Schalten', const Dpt(1, 1), 'Kanal A – Schalten'),
        g('1/4/1', 'Küche Decke Status', const Dpt(1, 1), 'Kanal A – Status', sends: true),
        g('1/0/2', 'Flur Schalten', const Dpt(1, 1), 'Kanal B – Schalten'),
        g('3/1/0', 'Küche Rollladen Auf/Ab fahren', const Dpt(1, 8), 'Kanal C – Auf/Ab'),
        g('1/0/9', 'Garagentor Impuls', const Dpt(1, 1), 'Kanal D – Schalten'),
        g('0/0/1', 'Zentral aus', const Dpt(1, 1), 'Zentral Schalten'),
      ])
        x.address: x,
    });
    CatalogStore.instance.catalog = catalog;
    return ChannelTest.of(aktor, channelsOf(aktor, catalog));
  }

  test('Kanäle des Geräts, Allgemeines bleibt draußen; nur Schaltkanäle schaltet die App', () {
    final t = build();
    expect(t.items.map((i) => i.label), ['A', 'B', 'C', 'D']);
    expect(t.items.map((i) => i.automatic), [true, true, false, false], reason: 'Rollladen und Tor von Hand');
    expect(t.next!.label, 'A');
  });

  test('Bewerten, Zählen, nächster Kanal: erst die schaltbaren, dann die von Hand', () {
    final t = build();
    t.rate(t.items[0], ChannelResult.ok);
    t.items[1].feedback = false;
    t.rate(t.items[1], ChannelResult.wrongLoad, note: ' schaltet die Küche ');
    expect((t.done, t.issues), (2, 1));
    expect(t.items[1].note, 'schaltet die Küche');
    expect(t.next!.label, 'C');
    t.rate(t.items[1], ChannelResult.open);
    expect(t.items[1].feedback, isNull);
    expect(t.next!.label, 'B');
  });

  test('Ergebnisse überstehen Speichern und Laden nach Kanalbezeichnung', () {
    final t = build();
    t.items[0].feedback = true;
    t.rate(t.items[0], ChannelResult.ok, at: DateTime(2026, 11, 13, 9));
    t.rate(t.items[3], ChannelResult.noReaction, note: 'Tor reagiert nicht');
    final again = build()..restore(t.toJson());
    expect(again.items.map((i) => i.result), [
      ChannelResult.ok,
      ChannelResult.open,
      ChannelResult.open,
      ChannelResult.noReaction,
    ]);
    expect(again.items[0].feedback, isTrue);
    expect(again.items[3].note, 'Tor reagiert nicht');
  });

  test('Bericht: eine Zeile je Kanal mit Adresse, Ergebnis und Rückmeldung', () {
    final t = build();
    t.items[0].feedback = true;
    t.rate(t.items[0], ChannelResult.ok);
    final text = t.report(
      heading: 'Kanalprüfung',
      text: (r) => r.name,
      feedback: (f) => f ? 'Rückmeldung ja' : 'Rückmeldung nein',
    );
    expect(text.split('\n')[2], 'A · 1/0/1 · ok · Rückmeldung ja');
    expect(text, contains('C · 3/1/0 · open'));
  });
}
