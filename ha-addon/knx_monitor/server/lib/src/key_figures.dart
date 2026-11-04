import 'dart:io';

import 'bus.dart';

/// Key figures of the active installation for Home Assistant: the state of
/// the MQTT device ([MqttBridge]) and of the KNX Monitor integration
/// (ha_integration.dart) come from here, so both report the same numbers.
///
/// Rates (telegrams and repeats per minute, bus load) are differences between
/// two calls of [tick]; history size and availability need file access and are
/// refreshed in [measure], availability at most every [_availabilityEvery].
class KeyFigures {
  KeyFigures(this.currentBus, {DateTime Function() clock = DateTime.now}) : _clock = clock;

  /// Bus of the active installation (changes with the installation).
  final BusService Function() currentBus;
  final DateTime Function() _clock;

  BusService? _countedBus;
  int _lastToday = 0;
  int _lastRepeats = 0;
  double _lastBusy = 0;
  DateTime? _lastTick;
  double _perMinute = 0;
  double _repeatsPerMinute = 0;
  double _busLoad = 0;

  int? _historyBytes;
  double? _availability;
  DateTime? _availabilityAt;
  BusService? _availabilityBus;
  static const _availabilityEvery = Duration(minutes: 15);

  /// Updates the rates since the previous call.
  void count() {
    final bus = currentBus();
    final now = _clock();
    final last = _lastTick;
    // Different installation or new day: start over instead of jumps.
    if (!identical(bus, _countedBus) ||
        last == null ||
        bus.today < _lastToday ||
        bus.repeats < _lastRepeats ||
        bus.busy < _lastBusy) {
      _countedBus = bus;
      _perMinute = 0;
      _repeatsPerMinute = 0;
      _busLoad = 0;
    } else {
      final ms = now.difference(last).inMilliseconds;
      if (ms > 0) {
        _perMinute = (bus.today - _lastToday) / (ms / 60000);
        _repeatsPerMinute = (bus.repeats - _lastRepeats) / (ms / 60000);
        // Occupied seconds per elapsed second, as the app's bus load (9600 bit/s).
        _busLoad = ((bus.busy - _lastBusy) / (ms / 1000) * 100).clamp(0.0, 100.0);
      }
    }
    _lastToday = bus.today;
    _lastRepeats = bus.repeats;
    _lastBusy = bus.busy;
    _lastTick = now;
  }

  /// History size and availability over the last 24 hours (file access).
  Future<void> measure() async {
    final bus = currentBus();
    try {
      _historyBytes = (await bus.recorder.usage())['bytes'] as int?;
    } on Object catch (e) {
      stderr.writeln('Kennzahlen Verlaufsgröße: $e');
    }
    final now = _clock();
    final at = _availabilityAt;
    if (identical(bus, _availabilityBus) && at != null && now.difference(at) < _availabilityEvery) return;
    _availabilityBus = bus;
    _availabilityAt = now;
    try {
      _availability = await bus.availability.ratio(now.subtract(const Duration(hours: 24)), now);
    } on Object catch (e) {
      _availability = null;
      stderr.writeln('Kennzahlen Verfügbarkeit: $e');
    }
  }

  /// Megabyte as Home Assistant's `data_size` unit `MB` (10^6 bytes).
  static const _mb = 1000 * 1000;

  static double? _round(double? v) => v == null ? null : double.parse(v.toStringAsFixed(1));

  /// The figures as the MQTT device publishes them in its state topic.
  Map<String, Object?> state() {
    final bus = currentBus();
    final alarm = bus.alarms.lastTriggered;
    final free = bus.recorder.lastFree;
    final history = _historyBytes;
    return {
      'connected': bus.state == 'connected',
      'recording': bus.config.enabled,
      'per_minute': _round(_perMinute),
      'repeats_per_minute': _round(_repeatsPerMinute),
      'today': bus.today,
      'last': bus.lastTelegram?.toUtc().toIso8601String(),
      if (bus.installation?['name'] case final String name) 'installation': name,
      'bus_load': _round(_busLoad),
      'open_alarms': bus.alarms.openCount,
      // Name from the project, otherwise the group address.
      'last_alarm': alarm == null
          ? null
          : alarm.change.name.isEmpty
          ? alarm.change.groupAddress
          : alarm.change.name,
      'last_alarm_kind': alarm?.change.kind,
      'last_alarm_address': alarm?.change.groupAddress,
      'last_alarm_time': alarm?.time.toUtc().toIso8601String(),
      'history_mb': history == null ? null : _round(history / _mb),
      'free_mb': free == null ? null : _round(free / _mb),
      'low_space': bus.recorder.lowSpace,
      'availability_24h': _round(_availability == null ? null : _availability! * 100),
    };
  }
}
