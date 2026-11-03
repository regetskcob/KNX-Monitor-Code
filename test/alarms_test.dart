import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/alarms.dart';
import 'package:knx_monitor/model/sections.dart';

void main() {
  final smoke = parseGroup('9/0/1')!;
  final status = parseGroup('9/0/2')!;
  final sensor = parseGroup('8/1/12')!;
  final leak = parseGroup('9/0/3')!;
  final lamp = parseGroup('1/4/73')!;
  final temp = parseGroup('2/0/0')!;

  setUp(() {
    CatalogStore.instance.catalog = GroupCatalog({
      smoke: GroupInfo(address: smoke, name: 'Rauchmelder Flur', dpt: const Dpt(1, 5)),
      status: GroupInfo(address: status, name: 'Heizung Status', dpt: const Dpt(21, 1)),
      sensor: GroupInfo(address: sensor, name: 'Außentemperatur Sensor defekt', dpt: const Dpt(1, 1)),
      leak: GroupInfo(address: leak, name: 'Water leak kitchen', dpt: const Dpt(1, 2)),
      lamp: GroupInfo(address: lamp, name: 'Außenleuchte Deich Rückmeldung', dpt: const Dpt(1, 1)),
      temp: GroupInfo(address: temp, name: 'Fehlerspeicher Temperatur', dpt: const Dpt(9, 1)),
    });
  });

  Telegram t(int ga, List<int> data, {bool small = true, TelegramType type = TelegramType.write}) => Telegram(
    time: DateTime(2026),
    source: 0x1105,
    destination: ga,
    type: type,
    data: Uint8List.fromList(data),
    isSmall: small,
  );

  test('Erkennung der Alarm-/Störungsadressen', () {
    final c = CatalogStore.instance.catalog;
    expect(alarmKindOf(c[smoke]), AlarmKind.alarm); // DPT 1.005
    expect(alarmKindOf(c[status]), AlarmKind.fault); // DPT 21.001
    expect(alarmKindOf(c[sensor]), AlarmKind.fault); // Name „defekt“
    expect(alarmKindOf(c[leak]), AlarmKind.alarm); // englischer Name
    expect(alarmKindOf(c[lamp]), isNull);
    expect(alarmKindOf(c[temp]), isNull); // nur 1-Bit-Werte werden am Namen erkannt
  });

  test('Aktiv nur bei Wert 1 bzw. gesetzten Status-Bits', () {
    expect(activeAlarm(t(smoke, [1])), AlarmKind.alarm);
    expect(activeAlarm(t(smoke, [0])), isNull);
    expect(activeAlarm(t(smoke, [0], type: TelegramType.read)), isNull);
    expect(activeAlarm(t(sensor, [1])), AlarmKind.fault);
    expect(activeAlarm(t(status, [0x02], small: false)), AlarmKind.fault); // Fault
    expect(activeAlarm(t(status, [0x08], small: false)), AlarmKind.alarm); // InAlarm
    expect(activeAlarm(t(status, [0x01], small: false)), isNull); // nur „Außer Betrieb“
    expect(activeAlarm(t(lamp, [1])), isNull);
  });

  test('eigene Sektion vor Wetter & Co.', () {
    expect(sectionFor(sensor).id, 'type:alarms');
    expect(sectionFor(smoke).id, 'type:alarms');
    expect(sectionFor(lamp).id, 'main:1');
  });
}
