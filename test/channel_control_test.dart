import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/channel_control.dart';
import 'package:knx_monitor/model/device_channels.dart';
import 'package:knx_monitor/model/telegram_log.dart';

int ga(String s) => parseGroup(s)!;

Telegram bit(String dest, int value, {bool outgoing = false}) => Telegram(
  time: DateTime(2026, 11, 13, 12),
  source: parseIndividual('1.1.10')!,
  destination: ga(dest),
  type: TelegramType.write,
  data: Uint8List.fromList([value]),
  isSmall: true,
  outgoing: outgoing,
);

void main() {
  final aktor = parseIndividual('1.1.10')!;

  List<DeviceChannel> channels() {
    GroupInfo g(String a, String name, Dpt dpt, String text, {bool sends = false}) => GroupInfo(
      address: ga(a),
      name: name,
      dpt: dpt,
      links: [GroupLink(device: aktor, text: text, sends: sends)],
    );
    final catalog = GroupCatalog({
      for (final x in [
        g('1/0/1', 'Küche Decke Schalten', const Dpt(1, 1), 'Kanal A – Schalten'),
        g('1/4/1', 'Küche Decke Status', const Dpt(1, 1), 'Kanal A – Status', sends: true),
        g('3/1/0', 'Küche Rollladen Auf/Ab fahren', const Dpt(1, 8), 'Kanal B – Auf/Ab'),
        g('3/2/0', 'Küche Rollladen Stopp', const Dpt(1, 7), 'Kanal B – Stopp'),
        g('3/4/0', 'Küche Rollladen Aktuelle Position', const Dpt(5, 1), 'Kanal B – Position', sends: true),
        g('2/2/1', 'Küche Ventil Schalten', const Dpt(1, 1), 'Kanal C – Heizen Stellwert'),
        g('1/0/9', 'Garagentor Impuls', const Dpt(1, 1), 'Kanal D – Schalten'),
        g('1/4/5', 'Flur Status', const Dpt(1, 1), 'Kanal E – Status', sends: true),
      ])
        x.address: x,
    });
    CatalogStore.instance.catalog = catalog;
    return channelsOf(aktor, catalog);
  }

  test('Schaltkanal: Befehl und Rückmeldung, Umschalten nach dem Status', () {
    final a = controlOf(channels()[0])!;
    expect((a.kind, a.address, a.status, a.caution), (ControlKind.toggle, ga('1/0/1'), ga('1/4/1'), false));
    expect(toggleValue(a, {}), 1, reason: 'unbekannt: einschalten');
    expect(toggleValue(a, {ga('1/0/1'): bit('1/0/1', 1)}), 0, reason: 'ohne Status zählt der letzte Befehl');
    expect(
      toggleValue(a, {ga('1/0/1'): bit('1/0/1', 1), ga('1/4/1'): bit('1/4/1', 0)}),
      1,
      reason: 'der Status hat Vorrang vor dem Befehl',
    );
  });

  test('Rollladen: Fahren und Stopp, keine Rückmeldung zum Bestätigen', () {
    final b = controlOf(channels()[1])!;
    expect((b.kind, b.address, b.stop, b.status), (ControlKind.blind, ga('3/1/0'), ga('3/2/0'), null));
  });

  test('Heizventil und Kanal nur mit Status lassen sich nicht bedienen', () {
    final all = channels();
    expect(controlOf(all[2]), isNull, reason: 'Ventile gehören dem Regler');
    expect(controlOf(all[4]), isNull, reason: 'nur eine Rückmeldung');
  });

  test('Sperr- und Freigabeobjekte sind nie die Schaltadresse', () {
    GroupInfo g(String a, String name, Dpt dpt, String text) => GroupInfo(
      address: ga(a),
      name: name,
      dpt: dpt,
      links: [GroupLink(device: aktor, text: text)],
    );
    final catalog = GroupCatalog({
      for (final x in [
        g('1/3/1', 'Bad Licht Sperre', const Dpt(1, 1), 'Kanal A – Sperren'),
        g('1/0/1', 'Bad Licht Schalten', const Dpt(1, 1), 'Kanal A – Schalten'),
        g('1/3/2', 'Flur Licht Freigabe', const Dpt(1, 3), 'Kanal B – Freigabe'),
      ])
        x.address: x,
    });
    CatalogStore.instance.catalog = catalog;
    final all = channelsOf(aktor, catalog);
    expect(controlOf(all[0])!.address, ga('1/0/1'), reason: 'die Sperre steht im Projekt zuerst');
    expect(controlOf(all[1]), isNull, reason: 'nur ein Freigabeobjekt: nichts zu bedienen');
  });

  test('Tor, Tür, Alarm und Zentralfunktionen fragen nach', () {
    expect(controlOf(channels()[3])!.caution, isTrue);
  });

  test('awaitFeedback: bestätigt nur ein neues Telegramm mit dem erwarteten Wert', () async {
    final log = TelegramLog()..add(bit('1/4/1', 1));
    final stale = awaitFeedback(log, ga('1/4/1'), 1, timeout: const Duration(milliseconds: 50));
    expect(await stale, isFalse, reason: 'der alte Wert zählt nicht');

    final wrong = awaitFeedback(log, ga('1/4/1'), 1, timeout: const Duration(milliseconds: 50));
    log.add(bit('1/4/1', 0));
    expect(await wrong, isFalse);

    final ok = awaitFeedback(log, ga('1/4/1'), 1, timeout: const Duration(seconds: 1));
    log.add(bit('1/4/1', 1));
    expect(await ok, isTrue);
  });
}
