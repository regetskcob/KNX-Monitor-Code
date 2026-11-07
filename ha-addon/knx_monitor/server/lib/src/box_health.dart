import 'dart:async';
import 'dart:io';

/// SoC temperature and throttling of the Raspberry Pi in the box.
///
/// The server runs with `DevicePolicy=closed` (knx-box.service), so
/// `vcgencmd` cannot reach `/dev/vcio`. Everything comes from sysfs instead:
/// - temperature: `/sys/class/thermal/thermal_zone0/temp` (millidegrees),
/// - throttling: `get_throttled` of the firmware driver (hex, same bits as
///   `vcgencmd get_throttled`), found under `/sys/devices/platform`,
/// - fallback for under-voltage: hwmon `rpi_volt`, `in0_lcrit_alarm`.
///
/// Samples every [interval] and remembers the highest temperature since the
/// server started, so a long test in a closed case needs no SSH.
class BoxHealth {
  BoxHealth({String sys = '/sys', this.interval = const Duration(minutes: 1), DateTime Function()? now})
    : _sys = sys,
      _now = now ?? DateTime.now;

  final String _sys;
  final Duration interval;
  final DateTime Function() _now;

  Timer? _timer;
  DateTime? _since;
  double? _temp;
  double? _maxTemp;
  DateTime? _maxAt;
  int? _throttled;
  int _seen = 0;
  String? _throttledFile;
  bool _searched = false;

  /// Whether the throttling bits come from the firmware (history since power-on)
  /// or only from the hwmon alarm (history only since the server started).
  bool _fromFirmware = false;

  /// Takes a first sample and then one every [interval].
  void start() {
    _since = _now();
    sample();
    _timer = Timer.periodic(interval, (_) => sample());
  }

  void stop() => _timer?.cancel();

  /// Reads temperature and throttling once.
  void sample() {
    _since ??= _now();
    final temp = readTemperature();
    if (temp != null) {
      _temp = temp;
      if (_maxTemp == null || temp > _maxTemp!) {
        _maxTemp = temp;
        _maxAt = _now();
      }
    }
    final throttled = readThrottled();
    if (throttled != null) {
      _throttled = throttled;
      // Bits 0–3 are "now"; bits 16–19 are "since boot" from the firmware.
      // Also remember what was seen now, in case only hwmon is available.
      _seen |= throttled | ((throttled & 0xf) << 16);
    }
  }

  /// SoC temperature in °C; `null` without a thermal zone (Docker, Mac).
  double? readTemperature() {
    final text = _read('$_sys/class/thermal/thermal_zone0/temp');
    final milli = text == null ? null : int.tryParse(text);
    return milli == null ? null : milli / 1000;
  }

  /// Throttling bits like `vcgencmd get_throttled`; `null` if unknown.
  int? readThrottled() {
    if (!_searched) {
      _searched = true;
      _throttledFile = _findThrottled();
    }
    if (_throttledFile case final path?) {
      final value = parseThrottled(_read(path));
      if (value != null) {
        _fromFirmware = true;
        return value;
      }
    }
    _fromFirmware = false;
    final alarm = _underVoltageAlarm();
    return alarm == null ? null : (alarm ? 1 : 0);
  }

  String? _findThrottled() {
    const known = 'devices/platform/soc/soc:firmware/get_throttled';
    if (File('$_sys/$known').existsSync()) return '$_sys/$known';
    // Pi 5 and newer kernels name the nodes differently; look two levels deep.
    final platform = Directory('$_sys/devices/platform');
    try {
      if (!platform.existsSync()) return null;
      for (final a in platform.listSync()) {
        if (a is! Directory) continue;
        final direct = File('${a.path}/get_throttled');
        if (direct.existsSync()) return direct.path;
        for (final b in a.listSync()) {
          if (b is! Directory || !b.path.contains('firmware')) continue;
          final nested = File('${b.path}/get_throttled');
          if (nested.existsSync()) return nested.path;
        }
      }
    } on FileSystemException {
      // Not readable: fall back to hwmon.
    }
    return null;
  }

  bool? _underVoltageAlarm() {
    final hwmon = Directory('$_sys/class/hwmon');
    try {
      if (!hwmon.existsSync()) return null;
      for (final entry in hwmon.listSync()) {
        if (_read('${entry.path}/name') != 'rpi_volt') continue;
        final alarm = _read('${entry.path}/in0_lcrit_alarm');
        if (alarm != null) return alarm != '0';
      }
    } on FileSystemException {
      return null;
    }
    return null;
  }

  String? _read(String path) {
    try {
      return File(path).readAsStringSync().trim();
    } on FileSystemException {
      return null;
    }
  }

  /// For `/api/box`: `null` if nothing could be read (no Raspberry Pi).
  Map<String, Object?>? status() {
    if (_temp == null && _throttled == null) return null;
    return {
      if (_temp case final t?) 'temp': _round(t),
      if (_maxTemp case final t?) 'maxTemp': _round(t),
      if (_maxAt case final at?) 'maxAt': at.toUtc().toIso8601String(),
      if (_since case final since?) 'since': since.toUtc().toIso8601String(),
      if (_throttled case final value?) ...{
        'throttled': throttleFlags(value & 0xf),
        'throttledBefore': throttleFlags((value | _seen) >> 16),
        'throttledSince': _fromFirmware ? 'boot' : 'serverStart',
      },
    };
  }

  static double _round(double value) => (value * 10).round() / 10;
}

/// Parses `get_throttled` (`50005`, `0x50005` or `throttled=0x50005`).
int? parseThrottled(String? text) {
  if (text == null) return null;
  var value = text.trim().toLowerCase();
  if (value.startsWith('throttled=')) value = value.substring(10);
  if (value.startsWith('0x')) value = value.substring(2);
  return int.tryParse(value, radix: 16);
}

/// Names of the set bits 0–3 (shift "since boot" down by 16 first).
List<String> throttleFlags(int bits) => [
  if (bits & 0x1 != 0) 'underVoltage',
  if (bits & 0x2 != 0) 'freqCapped',
  if (bits & 0x4 != 0) 'throttled',
  if (bits & 0x8 != 0) 'softTempLimit',
];
