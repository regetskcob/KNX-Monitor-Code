import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:knx/knx.dart';

import 'atomic_file.dart';
import 'bus.dart';
import 'recorder.dart';

/// "A device stopped sending" for the KNX Monitor integration of Home
/// Assistant (`GET /api/ha/silent`, ha_integration.dart).
///
/// Every [every] it reads the last [window] of the active installation's
/// history through its [Recorder] and applies the silence rule the app's
/// health check uses ([cycleSilences] in package:knx): addresses with a
/// regular interval that have been silent for more than three times that.
///
/// - While recording is off or the bus is not connected nothing is reported:
///   after an outage every cyclic address would look silent. For the same
///   reason an address only counts once the bus has been connected for longer
///   than its limit.
/// - An address that sends again leaves the list at once ([observe]), not only
///   at the next check.
/// - Ignored addresses ([ignore]) are kept in `cycle_watch.json` of the
///   installation and come back by themselves once they send again.
class CycleWatch {
  CycleWatch(
    this.currentBus, {
    this.window = const Duration(days: 7),
    this.every = const Duration(hours: 1),
    DateTime Function() clock = DateTime.now,
  }) : _clock = clock;

  /// Bus of the active installation (changes with the installation).
  final BusService Function() currentBus;

  /// How much history the rule looks at.
  final Duration window;

  /// How often the history is read again.
  final Duration every;
  final DateTime Function() _clock;

  /// Most entries [silent] returns.
  static const maxListed = 20;

  Timer? _timer;
  Future<void>? _checking;

  /// Bus the results below belong to.
  BusService? _bus;

  /// Silent addresses of the last [check], ignored ones included.
  final _found = <int, CycleSilence>{};

  /// Ignored address → time (µs) of its last telegram when it was ignored.
  final _ignored = <int, int>{};

  File _file(BusService bus) => File('${bus.data.path}/cycle_watch.json');

  /// First check soon after start (the history is read in the background),
  /// then every [every].
  void start({Duration first = const Duration(minutes: 2)}) {
    _timer?.cancel();
    _timer = Timer(first, () {
      unawaited(_checkLogged());
      _timer = Timer.periodic(every, (_) => unawaited(_checkLogged()));
    });
  }

  void stop() => _timer?.cancel();

  Future<void> _checkLogged() => check().catchError((Object e) => stderr.writeln('Schweige-Prüfung: $e'));

  /// Reads the history again; one check at a time.
  Future<void> check() => _checking ??= _check().whenComplete(() => _checking = null);

  Future<void> _check() async {
    final bus = currentBus();
    if (!identical(bus, _bus)) await _switchTo(bus);
    // Names and the group address style for [silent].
    await bus.alarms.loadCatalog();
    final now = _clock();
    final from = now.subtract(window);
    final start = from.microsecondsSinceEpoch;
    final times = <int, List<int>>{};
    // Lines in the buffer count too.
    await bus.recorder.flush();
    for (var d = DateTime(from.year, from.month, from.day); !d.isAfter(now); d = DateTime(d.year, d.month, d.day + 1)) {
      final lines = await bus.recorder.dayLines(Recorder.dayName(d));
      if (lines == null) continue;
      await for (final line in lines) {
        // Only the fields the rule needs, without decoding the whole line.
        final t = int.tryParse(Recorder.field(line, 't') ?? '');
        final ga = int.tryParse(Recorder.field(line, 'd') ?? '');
        if (t == null || ga == null || t < start) continue;
        // Read requests and our own telegrams say nothing about the sender.
        if (Recorder.field(line, 'y') == '0' || line.contains('"o":true')) continue;
        (times[ga] ??= []).add(t);
      }
    }
    if (!identical(bus, currentBus())) return; // installation changed meanwhile
    _found
      ..clear()
      ..addEntries([for (final s in cycleSilences(times, now)) MapEntry(s.address, s)]);
    // Sent again since it was ignored (also while the server was not running).
    var changed = false;
    for (final MapEntry(key: ga, value: last) in _ignored.entries.toList()) {
      final newest = times[ga]?.last;
      if (newest != null && newest > last) {
        _ignored.remove(ga);
        changed = true;
      }
    }
    if (changed) await _save(bus);
  }

  Future<void> _switchTo(BusService bus) async {
    _bus = bus;
    _found.clear();
    _ignored.clear();
    try {
      final json = jsonDecode(await _file(bus).readAsString()) as Map<String, Object?>;
      for (final MapEntry(:key, :value) in ((json['ignored'] as Map?) ?? const {}).entries) {
        if (int.tryParse('$key') case final ga? when value is int) _ignored[ga] = value;
      }
    } on Object {
      // Missing or damaged: nothing ignored.
    }
  }

  Future<void> _save(BusService bus) => writeAtomic(
    _file(bus),
    text: jsonEncode({
      'ignored': {for (final MapEntry(:key, :value) in _ignored.entries) '$key': value},
    }),
  );

  /// A telegram of [bus] (history line): if its address was silent or
  /// ignored, it is not any more.
  void observe(BusService bus, Map<String, Object?> line) {
    if (!identical(bus, _bus) || line['y'] == 0 || line['o'] == true) return;
    final ga = line['d'];
    if (ga is! int) return;
    _found.remove(ga);
    if (_ignored.remove(ga) != null) unawaited(_save(bus).catchError((Object e) => stderr.writeln('cycle_watch: $e')));
  }

  /// Silent addresses that are reported now: not ignored, recording on, bus
  /// connected for longer than the address's limit. Oldest silence first.
  List<CycleSilence> _reported() {
    final bus = _bus;
    if (bus == null || !identical(bus, currentBus())) return const [];
    if (!bus.config.enabled || bus.state != 'connected') return const [];
    final now = _clock();
    final since = bus.since;
    return [
      for (final s in _found.values)
        if (!_ignored.containsKey(s.address) && (since == null || now.difference(since) > s.limit)) s,
    ]..sort((a, b) => a.last.compareTo(b.last));
  }

  /// Number of silent addresses (`silent` in `GET /api/ha/state`).
  int get count => _reported().length;

  /// `GET /api/ha/silent`: at most [maxListed], oldest silence first, with
  /// the name from the project if the server has it.
  List<Map<String, Object?>> silent() {
    final bus = _bus;
    if (bus == null) return const [];
    return [
      for (final s in _reported().take(maxListed))
        {
          'address': bus.alarms.formatGroup(s.address),
          'name': bus.alarms.nameOf(s.address),
          'last': s.last.toUtc().toIso8601String(),
          'interval_s': s.interval.inSeconds,
        },
    ];
  }

  /// `POST /api/ha/silent/ignore`: no longer reports [address] (as in
  /// [silent]) until it sends again. `false` if it is not silent.
  Future<bool> ignore(String address) async {
    final bus = _bus;
    if (bus == null || !identical(bus, currentBus())) return false;
    final match = _found.values.where((s) => bus.alarms.formatGroup(s.address) == address).firstOrNull;
    if (match == null) return false;
    _ignored[match.address] = match.last.microsecondsSinceEpoch;
    await _save(bus);
    return true;
  }
}
