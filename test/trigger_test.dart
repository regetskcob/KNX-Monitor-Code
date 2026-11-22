import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/recording.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/model/trigger.dart';
import 'package:knx_monitor/monitor_model.dart';

void main() {
  final rain = parseGroup('8/1/0')!;
  final temp = parseGroup('2/0/0')!;

  setUp(() {
    CatalogStore.instance.catalog = GroupCatalog({
      rain: GroupInfo(address: rain, name: 'Regen', dpt: const Dpt(1, 1)),
      temp: GroupInfo(address: temp, name: 'Temperatur', dpt: const Dpt(9, 1)),
    });
  });

  Telegram t(int ga, List<int> data, {bool small = false}) => Telegram(
    time: DateTime.now(),
    source: 0x1105,
    destination: ga,
    type: TelegramType.write,
    data: Uint8List.fromList(data),
    isSmall: small,
  );

  test('Gruppenadresse mit Wert: Vorlauf, Nachlauf, Aufnahme und erneut scharf', () async {
    final tunnel = KnxTunnel('test');
    final model = MonitorModel(tunnel);
    final done = <Recording>[];
    final sub = model.triggeredRecordings.listen(done.add);
    model.armTrigger(
      TriggerConfig(kind: TriggerKind.address, address: rain, value: 'ein', pre: 3, post: 2, rearm: true),
    );

    for (var i = 0; i < 5; i++) {
      tunnel.inject(t(temp, [0x0C, 0x20 + i]));
    }
    tunnel.inject(t(rain, [0], small: true)); // Aus – löst nicht aus
    await Future<void>.delayed(Duration.zero);
    expect(model.recording, isFalse);

    tunnel.inject(t(rain, [1], small: true)); // Ein – löst aus
    await Future<void>.delayed(Duration.zero);
    expect(model.triggerRecording, isTrue);

    tunnel.inject(t(temp, [0x0C, 0x30]));
    tunnel.inject(t(temp, [0x0C, 0x31]));
    await Future<void>.delayed(Duration.zero);

    expect(done, hasLength(1));
    final r = done.single;
    // 3 Telegramme Vorlauf + auslösendes + 2 Nachlauf
    expect(r.telegrams, hasLength(6));
    expect(r.telegrams[3].destination, rain);
    expect(r.name, contains('8/1/0'));
    expect(model.recording, isFalse);
    expect(model.trigger, isNotNull); // erneut scharf

    await sub.cancel();
    model.dispose();
    tunnel.dispose();
  });

  test('Entschärfen im Nachlauf: Aufnahme endet trotzdem, weitere Telegramme laufen durch', () async {
    final tunnel = KnxTunnel('test');
    final model = MonitorModel(tunnel);
    final done = <Recording>[];
    final sub = model.triggeredRecordings.listen(done.add);
    model.armTrigger(TriggerConfig(kind: TriggerKind.address, address: rain, value: 'ein', pre: 1, post: 2));

    tunnel.inject(t(rain, [1], small: true));
    await Future<void>.delayed(Duration.zero);
    expect(model.triggerRecording, isTrue);

    model.armTrigger(null); // Expertenmodus aus
    tunnel.inject(t(temp, [0x0C, 0x30]));
    tunnel.inject(t(temp, [0x0C, 0x31]));
    tunnel.inject(t(temp, [0x0C, 0x32]));
    await Future<void>.delayed(Duration.zero);

    expect(done, hasLength(1));
    expect(done.single.telegrams, hasLength(3));
    expect(model.triggerRecording, isFalse);
    expect(model.recording, isFalse);
    expect(model.trigger, isNull);
    expect(model.log, hasLength(4));

    await sub.cancel();
    model.dispose();
    tunnel.dispose();
  });

  test('Monitor verlassen: laufende Aufnahme wird herausgegeben, auch im Nachlauf', () async {
    final tunnel = KnxTunnel('test');
    final model = MonitorModel(tunnel);
    expect(model.finishRunningRecording(name: 'x'), isNull);

    model.startRecording();
    tunnel.inject(t(temp, [0x0C, 0x30]));
    await Future<void>.delayed(Duration.zero);
    final copy = model.snapshotRecording(name: 'Kopie')!;
    expect(copy.telegrams, hasLength(1));
    expect(model.recording, isTrue);
    final manual = model.finishRunningRecording(name: 'Hand')!;
    expect(manual.id, copy.id);
    expect(model.recording, isFalse);

    model.armTrigger(TriggerConfig(kind: TriggerKind.address, address: rain, value: 'ein', pre: 0, post: 5));
    tunnel.inject(t(rain, [1], small: true));
    await Future<void>.delayed(Duration.zero);
    final fired = model.finishRunningRecording(name: 'Trigger')!;
    expect(fired.telegrams, hasLength(1));
    expect(model.triggerRecording, isFalse);
    tunnel.inject(t(temp, [0x0C, 0x31]));
    await Future<void>.delayed(Duration.zero);
    expect(model.recording, isFalse);

    model.dispose();
    tunnel.dispose();
  });

  test('Vergleich mit dem Wert: Zahl, Text, enthält', () {
    final log = TelegramLog();
    bool hit(ValueCompare c, String value, Telegram x) =>
        TriggerConfig(kind: TriggerKind.address, address: x.destination, value: value, compare: c).matches(x, log);
    final warm = t(temp, [0x0C, 0x20]); // 21,12 °C
    expect(hit(ValueCompare.greater, '20', warm), isTrue);
    expect(hit(ValueCompare.less, '20', warm), isFalse);
    expect(hit(ValueCompare.less, '21,5', warm), isTrue);
    expect(hit(ValueCompare.equals, '21.12', warm), isTrue);
    expect(hit(ValueCompare.notEquals, '21.12', warm), isFalse);
    final on = t(rain, [1], small: true);
    expect(hit(ValueCompare.equals, 'Ein', on), isTrue);
    expect(hit(ValueCompare.notEquals, 'Aus', on), isTrue);
    expect(hit(ValueCompare.greater, 'Aus', on), isFalse);
    expect(hit(ValueCompare.contains, 'in', on), isTrue);
  });

  test('Aufnahme an der Obergrenze endet und wird gemeldet, statt weiter zu wachsen', () async {
    final limit = MonitorModel.recordingLimit;
    MonitorModel.recordingLimit = 3;
    addTearDown(() => MonitorModel.recordingLimit = limit);
    final tunnel = KnxTunnel('test');
    final model = MonitorModel(tunnel);
    final full = <Recording>[];
    final sub = model.fullRecordings.listen(full.add);
    model.startRecording();
    for (var i = 0; i < 5; i++) {
      tunnel.inject(t(temp, [0x0C, 0x20 + i]));
    }
    await Future<void>.delayed(Duration.zero);
    expect(full, hasLength(1));
    expect(full.single.telegrams, hasLength(3));
    expect(model.recording, isFalse);
    await sub.cancel();
    model.dispose();
  });
}
