import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/commissioning.dart';
import 'package:knx_monitor/model/sound_ack.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';

final _light = parseGroup('1/1/0')!;
final _rm = parseGroup('1/4/0')!;
final _button = parseIndividual('1.1.20')!;
final _actuator = parseIndividual('1.1.5')!;
final _other = parseIndividual('1.2.7')!;

Telegram _t(int ms, int destination, {int? source, TelegramType type = TelegramType.write, bool outgoing = false}) =>
    Telegram(
      time: DateTime(2026, 10, 27, 9).add(Duration(milliseconds: ms)),
      source: source ?? _button,
      destination: destination,
      type: type,
      data: Uint8List.fromList([1]),
      isSmall: true,
      outgoing: outgoing,
    );

void main() {
  final ack = SoundAck.instance;
  final c = Commissioning.instance;
  late List<AckSound> played;
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sound_ack');
    AppStorage.instance = IoStorage(dir);
    c.debugReset();
    ack.debugReset();
    played = [];
    ack.play = played.add;
    CatalogStore.instance.catalog = GroupCatalog(
      {
        _light: GroupInfo(
          address: _light,
          name: 'Licht Flur',
          links: [
            GroupLink(device: _button, sends: true),
            GroupLink(device: _actuator),
          ],
        ),
        _rm: GroupInfo(
          address: _rm,
          name: 'Licht Flur RM',
          links: [GroupLink(device: _actuator, sends: true)],
        ),
      },
      devices: {
        _button: DeviceInfo(address: _button, name: 'Taster Flur'),
        _actuator: DeviceInfo(address: _actuator, name: 'Schaltaktor'),
      },
    );
  });

  tearDown(() async {
    // Ungewartete Speichervorgänge erst beenden, dann den Ordner löschen.
    await c.flush();
    ack.debugReset();
    CatalogStore.instance.catalog = GroupCatalog.empty;
    await dir.delete(recursive: true);
  });

  test('Ziele: Linie, Gerät, Adresse, Checkliste', () {
    expect(const AckLine(1, 1).matches(_t(0, _light)), isTrue);
    expect(const AckLine(1, 2).matches(_t(0, _light)), isFalse);
    expect(AckDevice(_button).matches(_t(0, _light)), isTrue);
    expect(AckDevice(_actuator).matches(_t(0, _light)), isFalse);
    expect(AckGroup(_rm).matches(_t(0, _rm)), isTrue);
    expect(const AckChecklist().matches(_t(0, _rm)), isFalse);
    c.prepare([_rm]);
    expect(const AckChecklist().matches(_t(0, _rm)), isTrue);
  });

  test('Gleiche Ziele sind gleich (Knöpfe erkennen die laufende Quittung)', () {
    expect(const AckLine(1, 1), const AckLine(1, 1));
    expect(const AckLine(1, 1), isNot(const AckLine(1, 2)));
    expect(AckDevice(_button), AckDevice(_button));
    expect(AckGroup(_rm), isNot(AckDevice(_rm)));
    ack.start(AckGroup(_rm));
    expect(ack.target == AckGroup(_rm), isTrue);
  });

  test('Ton je Telegramm, Lesen und Eigenes stumm, schnelle Folgen gedrosselt', () {
    ack.check(_t(0, _light)); // läuft noch nicht
    ack.start(const AckLine(1, 1));
    ack.check(_t(0, _light));
    ack.check(_t(50, _light)); // zu schnell: gezählt, aber still
    ack.check(_t(300, _light, type: TelegramType.read));
    ack.check(_t(400, _light, outgoing: true));
    ack.check(_t(500, _rm, source: _actuator, type: TelegramType.response));
    expect(ack.count, 2 + 1);
    expect(played, [AckSound.write, AckSound.response]);
    ack.stop();
    ack.check(_t(900, _light));
    expect(played, hasLength(2));
  });

  test('Fremder oder unbekannter Absender klingt anders', () {
    expect(SoundAck.soundFor(_t(0, _light)), AckSound.write);
    // Aktor sendet an die Schaltadresse, laut Projekt sendet dort der Taster.
    expect(SoundAck.soundFor(_t(0, _light, source: _actuator)), AckSound.foreign);
    expect(SoundAck.soundFor(_t(0, _rm, source: _other)), AckSound.foreign);
  });

  test('Durchklingeln hakt Gesendetes ab und markiert fremde Absender', () {
    expect(rollCallScope(), [_light, _rm]..sort(), reason: 'beide haben ein sendendes Gerät');
    c.prepare([_light, _rm]);
    c.observe(_t(0, _light));
    expect(c.items[_light]!.state, CheckState.open, reason: 'Durchklingeln ist aus');
    c.setRollCall(true);
    expect(c.observe(_t(0, _light, type: TelegramType.read)), isNull);
    expect(c.observe(_t(0, _light, outgoing: true)), isNull);
    expect(c.observe(_t(10, _light))?.address, _light);
    expect(c.items[_light]!.state, CheckState.seen);
    expect(c.items[_light]!.foreign, isFalse);
    expect(c.items[_light]!.source, _button);
    // Schon abgehakt: zweites Telegramm ändert nichts.
    expect(c.observe(_t(20, _light, source: _other)), isNull);

    c.mark(_rm, CheckState.issue);
    expect(c.observe(_t(30, _rm, source: _actuator)), isNull, reason: 'von Hand bewertet bleibt');
    c.mark(_rm, CheckState.open);
    c.observe(_t(40, _rm, source: _other));
    expect(c.items[_rm]!.state, CheckState.seen);
    expect(c.items[_rm]!.foreign, isTrue);
    expect(c.items[_rm]!.state.done, isTrue);

    // Gespeichert (fremd, Durchklingeln an) und wieder gelesen.
    final back = CheckItem.fromJson(c.items[_rm]!.toJson());
    expect(back.foreign, isTrue);
    expect(back.state, CheckState.seen);
    c.mark(_rm, CheckState.open);
    expect(c.items[_rm]!.foreign, isFalse);
  });
}
