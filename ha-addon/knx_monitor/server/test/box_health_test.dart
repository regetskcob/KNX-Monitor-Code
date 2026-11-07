import 'dart:io';

import 'package:knx_monitor_server/box.dart';
import 'package:test/test.dart';

void main() {
  late Directory sys;
  var now = DateTime.utc(2026, 11, 7, 10);

  void write(String path, String text) => File('${sys.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  setUp(() => sys = Directory.systemTemp.createTempSync('sys'));
  tearDown(() => sys.deleteSync(recursive: true));

  BoxHealth health() => BoxHealth(sys: sys.path, now: () => now);

  test('parseThrottled accepts the sysfs and vcgencmd forms', () {
    expect(parseThrottled('50005'), 0x50005);
    expect(parseThrottled('0x50005\n'), 0x50005);
    expect(parseThrottled('throttled=0x0'), 0);
    expect(parseThrottled('kaputt'), isNull);
    expect(parseThrottled(null), isNull);
  });

  test('without a Raspberry Pi there is no status', () {
    final h = health()..sample();
    expect(h.status(), isNull);
  });

  test('temperature, maximum and throttling from the Pi 4 firmware node', () {
    write('class/thermal/thermal_zone0/temp', '61234\n');
    write('devices/platform/soc/soc:firmware/get_throttled', '50005\n');
    final h = health()..sample();
    now = now.add(const Duration(minutes: 1));
    write('class/thermal/thermal_zone0/temp', '55000\n');
    h.sample();
    final status = h.status()!;
    expect(status['temp'], 55.0);
    expect(status['maxTemp'], 61.2);
    expect(status['maxAt'], '2026-11-07T10:00:00.000Z');
    expect(status['throttled'], ['underVoltage', 'throttled']);
    expect(status['throttledBefore'], ['underVoltage', 'throttled']);
    expect(status['throttledSince'], 'boot');
  });

  test('finds get_throttled under another firmware node (Pi 5)', () {
    write('devices/platform/axi/axi:firmware/get_throttled', '80000');
    final status = (health()..sample()).status()!;
    expect(status['throttled'], isEmpty);
    expect(status['throttledBefore'], ['softTempLimit']);
  });

  test('falls back to the hwmon under-voltage alarm and remembers it', () {
    write('class/hwmon/hwmon0/name', 'cpu_thermal');
    write('class/hwmon/hwmon1/name', 'rpi_volt');
    write('class/hwmon/hwmon1/in0_lcrit_alarm', '1');
    final h = health()..sample();
    expect(h.status()!['throttled'], ['underVoltage']);
    write('class/hwmon/hwmon1/in0_lcrit_alarm', '0');
    h.sample();
    expect(h.status()!['throttled'], isEmpty);
    expect(h.status()!['throttledBefore'], ['underVoltage']);
    expect(h.status()!['throttledSince'], 'serverStart');
  });
}
