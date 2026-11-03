import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/device_channels.dart';

void main() {
  test('Kanal aus Objekttexten', () {
    expect(channelLabel('Kanal A – Schalten'), 'A');
    expect(channelLabel('Ausgang 3: Status'), '3');
    expect(channelLabel('Channel 12 Switch'), '12');
    expect(channelLabel('A1 - Schalten'), 'A1');
    expect(channelLabel('K4 Dimmen'), '4');
    expect(channelLabel('Zentral Schalten'), isNull);
    expect(channelLabel(null), isNull);
  });

  test('Kanäle eines Aktors in natürlicher Reihenfolge, Allgemeines zuletzt', () {
    final aktor = parseIndividual('1.1.10')!;
    GroupInfo ga(String a, String name, Dpt dpt, String text, {bool sends = false, int? object}) => GroupInfo(
      address: parseGroup(a)!,
      name: name,
      dpt: dpt,
      links: [GroupLink(device: aktor, object: object, text: text, sends: sends)],
    );
    final catalog = GroupCatalog({
      for (final g in [
        ga('1/0/10', 'Licht Bad', const Dpt(1, 1), 'Kanal B – Schalten', object: 10),
        ga('1/4/10', 'Licht Bad Status', const Dpt(1, 1), 'Kanal B – Status', sends: true, object: 12),
        ga('1/0/1', 'Licht Flur', const Dpt(1, 1), 'Kanal A – Schalten', object: 0),
        ga('1/0/12', 'Licht Keller', const Dpt(1, 1), 'Kanal A10 – Schalten', object: 90),
        ga('0/0/1', 'Zentral aus', const Dpt(1, 1), 'Zentral Schalten', object: 200),
      ])
        g.address: g,
    });
    CatalogStore.instance.catalog = catalog;
    final channels = channelsOf(aktor, catalog);
    expect(channels.map((c) => c.label), ['A', 'A10', 'B', '']);
    expect(channels[2].objects.map((o) => o.number), [10, 12]);
    expect(channels[2].kind, ChannelKind.switching);
  });
}
