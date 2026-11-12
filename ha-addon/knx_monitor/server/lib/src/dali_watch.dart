import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:knx/knx.dart' show formatIndividual;

import 'atomic_file.dart' show serialized;
import 'dali.dart';
import 'dpt_value.dart';
import 'health_check.dart' show daliFaultCounts;

/// DALI on the add-on or box, so it also works at night without an open app (the same rules as
/// the app's `lib/model/dali.dart` and `lib/model/dali_alarms.dart`):
///
/// - Faults per luminaire: a KNX-DALI gateway reports many luminaires on one diagnostic address
///   (DPT 237.600, 238.600), so the state counts per gateway and DALI address, not per group
///   address. Notifications and events go through a [FaultDebouncer]: a state counts once it held
///   for a while, notifications per gateway and minute are capped.
/// - Emergency lighting log: every new test result (DPT 245.600) becomes a line in
///   `dali_tests/<year>.ndjson`, append only, at most [emergencyLogMaxBytes] per year
///   ([EmergencyTracker] decides what is new, and marks results from another sender).
///
/// Any device on the bus can send anything with any sender address. So nothing here grows with
/// what arrives on the bus: senders, keys and notifications are bounded.
///
/// Names and the meaning of the gateway's objects come from `dali.json`, which the app writes
/// next to the project; without it luminaires are named by their address and at most
/// [maxUnknownGateways] senders are followed.
class DaliWatch {
  DaliWatch(
    this.data, {
    required this.dptOf,
    required this.formatGroup,
    required this.notify,
    this.onChange,
    this.timeKnown,
    FaultDebouncer? debouncer,
  }) : _debouncer = debouncer ?? FaultDebouncer();

  final Directory data;

  /// Datapoint type (main type, subtype) of a group address from the project.
  final (int, int?)? Function(int group) dptOf;
  final String Function(int group) formatGroup;
  final Future<void> Function({required String id, required String title, required String message}) notify;

  /// Every settled change of a luminaire, group or emergency test, within the event budget, even
  /// with notifications turned off (event for Home Assistant automations).
  final void Function(DaliFaultChange change)? onChange;

  /// Whether the clock is right (box without a synchronized clock: no log entries with a wrong
  /// date; the result is logged when it is seen again).
  final bool Function()? timeKnown;

  final FaultDebouncer _debouncer;

  /// Without `dali.json`: how many different senders are followed at most.
  static const maxUnknownGateways = 16;

  /// Faults remembered at most (luminaires and groups of all gateways).
  static const maxKeys = 4096;

  bool enabled = true;
  String language = 'de';

  /// Faults per gateway and DALI address (`<pa>:<address>`, groups `<pa>:g<group>`), oldest first.
  final _faults = LinkedHashMap<String, int>();

  /// What the debouncer's keys stand for, for the texts.
  final _labels = LinkedHashMap<String, ({String name, String detail, String groupAddress, bool test})>();
  final _unknownGateways = <int>{};

  final _tracker = EmergencyTracker();
  bool _seeded = false;
  final _overflowYears = <int>{};
  Timer? _timer;

  _Model _model = const _Model();
  DateTime? _modelTime;
  bool _modelLoaded = false;

  /// Luminaires and groups currently in a fault (since the start of the server).
  int get openCount => _faults.values.where((f) => f != 0).length;

  /// Luminaires in a fault per gateway, for the server's health check ([daliFaultCounts]):
  /// `[gateway, lamp faults, gear or converter faults]`. Like [openCount] it knows what was
  /// heard since the start of the server.
  List<List<int>> faultCounts() => daliFaultCounts(_faults);

  /// Results left out of the log because they came too often (see [EmergencyTracker.minGap]).
  int get suppressedResults => _tracker.suppressed;

  File get _modelFile => File('${data.path}/dali.json');

  /// A file larger than this is not the app's.
  static const _maxModelBytes = 4 * 1024 * 1024;

  Future<void> _reloadModel() async {
    try {
      final modified = await _modelFile.exists() ? await _modelFile.lastModified() : null;
      if (_modelLoaded && modified == _modelTime) return;
      _modelLoaded = true;
      _modelTime = modified;
      if (modified == null || await _modelFile.length() > _maxModelBytes) {
        _model = const _Model();
        return;
      }
      _model = _Model.parse(jsonDecode(await _modelFile.readAsString()));
    } on Object catch (e) {
      // Unreadable (perhaps still being written): keep what was known, no retry per telegram.
      stderr.writeln('dali.json: $e');
    }
  }

  /// What the log already holds, so the first telegram after a restart is not a new result.
  /// Reads at most [emergencyLogReadBytes] per file: a larger one is read up to there.
  Future<void> _seed() async {
    if (_seeded) return;
    _seeded = true;
    try {
      final dir = Directory('${data.path}/dali_tests');
      if (!await dir.exists()) return;
      final files = [
        await for (final f in dir.list())
          if (f is File && RegExp(r'/\d{4}\.ndjson$').hasMatch(f.path)) f,
      ]..sort((a, b) => a.path.compareTo(b.path));
      for (final f in files) {
        final (:text, :cut) = await _head(f);
        final read = readEmergencyLog(text, cut: cut);
        if (read.overflow || cut) _overflowYears.add(int.parse(f.uri.pathSegments.last.substring(0, 4)));
        final entries = read.entries..sort((a, b) => a.time.compareTo(b.time));
        entries.forEach(_tracker.seed);
      }
    } on Object catch (e) {
      stderr.writeln('dali_tests: $e');
    }
  }

  static Future<({String text, bool cut})> _head(File file) async {
    final raf = await file.open();
    try {
      final length = await raf.length();
      final bytes = await raf.read(length < emergencyLogReadBytes ? length : emergencyLogReadBytes);
      return (text: utf8.decode(bytes, allowMalformed: true), cut: length > emergencyLogReadBytes);
    } finally {
      await raf.close();
    }
  }

  Future<void> _queue = Future.value();

  /// Checks a telegram line (same format as in the history). One after the other: the state of a
  /// luminaire depends on the order of its reports. [secure]: the telegram arrived KNX Data
  /// Secure.
  Future<void> check(Map<String, Object?> t, {bool secure = false}) {
    if (t['y'] == 0 || t['o'] == true) return Future.value(); // read request, own telegram
    return _queue = _queue.then((_) => _check(t, secure), onError: (Object _) => _check(t, secure));
  }

  Future<void> _check(Map<String, Object?> t, bool secure) async {
    final group = t['d'];
    final source = t['s'];
    final stamp = t['t'];
    if (group is! int || source is! int || stamp is! int) return;
    final dpt = dptOf(group);
    final isDali = dpt != null && isDaliDpt(dpt.$1, dpt.$2);
    // Only DALI types and 1-bit objects can be DALI here: everything else never reads the model.
    if (!isDali && dpt?.$1 != 1) return;
    await _reloadModel();
    final object = _model.objects[group];
    if (!isDali && object == null) return;
    final small = t['m'] == true;
    final bytes = hexBytes(t['x'] as String? ?? '');
    final time = DateTime.fromMicrosecondsSinceEpoch(stamp);

    if (isDali && (dpt.$1 == 237 || dpt.$1 == 238)) {
      final report = small ? null : decodeDaliReport(dpt.$1, bytes);
      if (report == null || report.readRequest) return;
      final pa = _gatewayOf(source, object);
      if (pa == null) return;
      _report(pa, report.address, report.faults, group, time, isGroup: report.isGroup);
      return;
    }
    if (isDali && dpt.$1 == 244) {
      final status = small ? null : decodeConverterStatus(bytes);
      if (status == null) return;
      final gateway = object?.gateway;
      // Only the gateway's status counts (any device could send one).
      final trusted = gateway == null || gateway == source;
      final gear = _model.converterAt(group);
      if (gear?.result case final result?) _tracker.status(result, status, trusted: trusted);
      if (!trusted || status.failure == ConverterFlag.unknown || gear?.address == null) return;
      final pa = gateway ?? source;
      final key = '$pa:${gear!.address}';
      final others = (_faults[key] ?? 0) & ~DaliFault.converter;
      final faults = others | (status.failure == ConverterFlag.yes ? DaliFault.converter : 0);
      _report(pa, gear.address!, faults, group, time);
      return;
    }
    if (isDali && dpt.$1 == 245) {
      if (small || timeKnown?.call() == false) return;
      await _seed();
      final gear = _model.converterAt(group);
      final entries = _tracker.result(
        group,
        bytes,
        time,
        gateway: object?.gateway,
        address: gear?.address ?? object?.index,
        source: source,
        secure: secure,
      );
      if (entries.isEmpty) return;
      await _append(entries, time);
      // A failed test is a fault of the luminaire; only from the gateway.
      final counting = entries.where((e) => !e.foreign).toList();
      if (counting.isEmpty) return;
      final pa = object?.gateway ?? source;
      final failed = counting.any((e) => e.result == EmergencyResult.failed);
      final key = 'test:$group';
      final de = language.startsWith('de');
      _labels.remove(key);
      _labels[key] = (
        name: gear?.name ?? _emergencyName(gear?.address ?? object?.index, group, de),
        detail: 'Gateway ${formatIndividual(pa)}',
        groupAddress: formatGroup(group),
        test: true,
      );
      _debouncer.report(key, pa, failed ? 8 : 0, time);
      _schedule(time);
      return;
    }
    // Gateways with one fault object per control gear (from a profile or the object texts).
    if (object == null || !small || bytes.isEmpty || object.index == null) return;
    if (source != object.gateway) return;
    final on = bytes[0] & 1 == 1;
    switch (object.role) {
      case 'lampFault' || 'gearFault':
        final bit = object.role == 'lampFault' ? DaliFault.lamp : DaliFault.gear;
        final key = '${object.gateway}:${object.index}';
        _report(object.gateway, object.index!, ((_faults[key] ?? 0) & ~bit) | (on ? bit : 0), group, time);
      case 'groupFault':
        _report(object.gateway, object.index!, on ? DaliFault.gear : 0, group, time, isGroup: true);
    }
  }

  /// The gateway a diagnostic report counts for, `null` to ignore it. With `dali.json` only the
  /// gateways it names; without it at most [maxUnknownGateways] senders.
  int? _gatewayOf(int source, _Object? object) {
    if (_model.gateways.isNotEmpty) return _model.gateways.containsKey(source) ? source : null;
    if (object != null) return object.gateway == source ? source : null;
    if (_unknownGateways.contains(source)) return source;
    if (_unknownGateways.length >= maxUnknownGateways) return null;
    _unknownGateways.add(source);
    return source;
  }

  Future<void> _append(List<EmergencyTest> entries, DateTime now) async {
    final byYear = <int, List<EmergencyTest>>{};
    for (final e in entries) {
      (byYear[e.time.year] ??= []).add(e);
    }
    for (final MapEntry(key: year, value: list) in byYear.entries) {
      if (_overflowYears.contains(year)) continue;
      final file = File('${data.path}/${emergencyLogPath(year)}');
      await file.parent.create(recursive: true);
      // Same queue as appends through the file API (files.dart), so the yearly limit holds.
      final (:chunk, :size) = await serialized(file, () async {
        final size = await file.exists() ? await file.length() : 0;
        final chunk = emergencyLogChunk(size, list, now);
        if (chunk.text.isNotEmpty) await file.writeAsString(chunk.text, mode: FileMode.append, flush: true);
        return (chunk: chunk, size: size);
      });
      if (chunk.overflow || size >= emergencyLogMaxBytes) {
        _overflowYears.add(year);
        final de = language.startsWith('de');
        await notify(
          id: 'knx_dali_log_full',
          title: de ? 'Notlicht-Prüfbuch voll' : 'Emergency lighting log full',
          message: de
              ? 'Das Prüfbuch $year hat seine Grenze erreicht; weitere Ergebnisse werden nicht mehr '
                    'eingetragen. Ungewöhnlich viele Ergebnis-Telegramme auf dem Bus.'
              : 'The log for $year reached its limit; further results are not entered. Unusually '
                    'many result telegrams on the bus.',
        );
      }
    }
  }

  void _report(int pa, int address, int faults, int group, DateTime time, {bool isGroup = false}) {
    final key = isGroup ? '$pa:g$address' : '$pa:$address';
    _faults.remove(key);
    _faults[key] = faults;
    while (_faults.length > maxKeys) {
      _faults.remove(_faults.keys.first);
    }
    final de = language.startsWith('de');
    final gear = isGroup ? null : _model.gear['$pa:$address'];
    final name =
        (isGroup ? _model.groups['$pa:$address'] : gear?.name) ??
        (isGroup
            ? '${de ? 'Gruppe' : 'Group'} $address'
            : gear?.emergency ?? false
            ? _emergencyName(address, null, de)
            : '${de ? 'EVG' : 'ECG'} $address');
    _labels.remove(key);
    _labels[key] = (
      name: name,
      detail: [
        if (isGroup) '${de ? 'Gruppe' : 'Group'} $address' else '${de ? 'EVG' : 'ECG'} $address',
        ?gear?.room,
        'Gateway ${formatIndividual(pa)}',
      ].join(' · '),
      groupAddress: formatGroup(group),
      test: false,
    );
    while (_labels.length > maxKeys) {
      _labels.remove(_labels.keys.first);
    }
    _debouncer.report(key, pa, faults, time);
    _schedule(time);
  }

  static String _emergencyName(int? address, int? group, bool de) => address != null
      ? '${de ? 'Notlicht' : 'Emergency'} $address'
      : '${de ? 'Notleuchte' : 'Emergency luminaire'} $group';

  /// The telegram's time drives the debouncer; the timer fires when the next change settles.
  DateTime _clock = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _timerFor = DateTime.fromMillisecondsSinceEpoch(0);

  void _schedule(DateTime now) {
    if (now.isAfter(_clock)) _clock = now;
    final due = _debouncer.nextDue;
    if (due == null) return;
    if (_timer?.isActive ?? false) {
      if (!due.isBefore(_timerFor)) return;
      _timer!.cancel();
    }
    _timerFor = due;
    final wait = due.difference(_clock);
    _timer = Timer(wait.isNegative ? Duration.zero : wait, () {
      // Time passes for the debouncer as it does here.
      _clock = _clock.add(wait.isNegative ? Duration.zero : wait);
      unawaited(flush(_clock));
    });
  }

  /// Hands out what settled by [now]: events, notifications, summaries.
  Future<void> flush(DateTime now) async {
    final de = language.startsWith('de');
    for (final n in _debouncer.take(now)) {
      if (n.count > 0) {
        if (!enabled) continue;
        await notify(
          id: 'knx_dali_${n.gateway}_summary',
          title: de ? 'DALI: ${n.count} weitere Meldungen' : 'DALI: ${n.count} more reports',
          message: de
              ? '${n.count} Leuchten melden Fehler oder Änderungen · Gateway ${formatIndividual(n.gateway)}'
              : '${n.count} luminaires report faults or changes · gateway ${formatIndividual(n.gateway)}',
        );
        continue;
      }
      final label = _labels[n.key];
      if (label == null) continue;
      if (n.event) {
        final parts = n.key.split(':');
        final index = int.tryParse(parts.last.replaceFirst('g', '')) ?? 0;
        onChange?.call(
          DaliFaultChange(
            gateway: formatIndividual(n.gateway),
            address: index,
            isGroup: parts.last.startsWith('g'),
            test: label.test,
            name: label.name,
            faults: n.after,
            groupAddress: label.groupAddress,
          ),
        );
      }
      if (!n.notify || !enabled) continue;
      final String title;
      if (n.after == 0) {
        title = '${de ? 'Wieder in Ordnung' : 'Back to normal'}: ${label.name}';
      } else if (label.test) {
        title = '${de ? 'Notlichttest durchgefallen' : 'Emergency test failed'}: ${label.name}';
      } else {
        title = '${faultText(n.after, de: de)}: ${label.name}';
      }
      final t = n.time;
      final clock = [t.hour, t.minute, t.second].map((v) => v.toString().padLeft(2, '0')).join(':');
      await notify(id: 'knx_dali_${n.key.replaceAll(':', '_')}', title: title, message: '${label.detail} · $clock');
    }
    _schedule(now);
  }

  /// Stops the timer (server shutdown, tests).
  void dispose() => _timer?.cancel();

  /// Fault flags in words, the worst first (as in the app).
  static String faultText(int faults, {required bool de}) => [
    if (faults & DaliFault.gear != 0) de ? 'EVG-Fehler' : 'ECG failure',
    if (faults & DaliFault.converter != 0) de ? 'Konverterfehler' : 'Converter failure',
    if (faults & DaliFault.lamp != 0) de ? 'Lampenfehler' : 'Lamp failure',
  ].join(', ');
}

/// A luminaire, group or emergency test changes its state ([faults] 0 = back to normal), after
/// it settled.
class DaliFaultChange {
  const DaliFaultChange({
    required this.gateway,
    required this.address,
    required this.isGroup,
    required this.name,
    required this.faults,
    required this.groupAddress,
    this.test = false,
  });

  /// Individual address of the gateway, formatted.
  final String gateway;

  /// DALI short address, or group with [isGroup]; for a [test] the result object's group address.
  final int address;
  final bool isGroup;

  /// An emergency test failed ([faults] 8) or passed again (0).
  final bool test;
  final String name;

  /// [DaliFault] bits.
  final int faults;

  /// Group address the report came on, formatted.
  final String groupAddress;
}

class _Object {
  const _Object(this.gateway, this.role, this.index);
  final int gateway;
  final String role;
  final int? index;
}

class _Gear {
  const _Gear({this.address, this.name, this.room, this.emergency = false, this.status, this.result});
  final int? address;
  final String? name;
  final String? room;
  final bool emergency;
  final int? status;
  final int? result;
}

/// What the server needs from the app's `dali.json`. Everything in it is input from outside:
/// wrong types and absurd sizes are skipped, never thrown.
class _Model {
  const _Model({this.gateways = const {}, this.gear = const {}, this.groups = const {}, this.objects = const {}});

  /// Individual address → name.
  final Map<int, String?> gateways;

  /// `<pa>:<address>` → luminaire; converters without address under `<pa>:ga<group address>`.
  final Map<String, _Gear> gear;

  /// `<pa>:<group>` → name.
  final Map<String, String> groups;

  /// Group address → object.
  final Map<int, _Object> objects;

  /// The converter whose status or result object is [group].
  _Gear? converterAt(int group) {
    for (final g in gear.values) {
      if (g.status == group || g.result == group) return g;
    }
    return null;
  }

  static int? _int(Object? v, int max) => v is int && v >= 0 && v <= max ? v : null;

  static String? _text(Object? v) {
    if (v is! String || v.trim().isEmpty) return null;
    final t = v.trim();
    return t.length > 120 ? t.substring(0, 120) : t;
  }

  static _Model parse(Object? json) {
    if (json is! Map) return const _Model();
    final gateways = <int, String?>{};
    for (final g in (json['gateways'] is List ? json['gateways'] as List : const <Object?>[]).take(256)) {
      if (g is! Map) continue;
      final pa = _int(g['a'], 0xFFFF);
      if (pa != null) gateways[pa] = _text(g['n']) ?? _text(g['pn']);
    }
    final gear = <String, _Gear>{};
    for (final g in (json['gear'] is List ? json['gear'] as List : const <Object?>[]).take(256 * 64)) {
      if (g is! Map) continue;
      final pa = _int(g['gw'], 0xFFFF);
      final address = _int(g['a'], 63);
      final anchor = _int(g['ga'], 0xFFFF);
      if (pa == null || (address == null && anchor == null)) continue;
      gear[address != null ? '$pa:$address' : '$pa:ga$anchor'] = _Gear(
        address: address,
        name: _text(g['n']),
        room: _text(g['r']),
        emergency: g['em'] is bool ? g['em'] as bool : g['emd'] == true,
        status: _int(g['st'], 0xFFFF),
        result: _int(g['res'], 0xFFFF),
      );
    }
    final groups = <String, String>{};
    for (final g in (json['groups'] is List ? json['groups'] as List : const <Object?>[]).take(256 * 16)) {
      if (g is! Map) continue;
      final pa = _int(g['gw'], 0xFFFF);
      final group = _int(g['g'], 15);
      final name = _text(g['n']);
      if (pa != null && group != null && name != null) groups['$pa:$group'] = 'G$group $name';
    }
    final objects = <int, _Object>{};
    if (json['objects'] case final Map<Object?, Object?> map) {
      for (final MapEntry(:key, :value) in map.entries.take(65536)) {
        final group = key is String ? int.tryParse(key) : null;
        if (group == null || group < 0 || group > 0xFFFF || value is! Map) continue;
        final pa = _int(value['gw'], 0xFFFF);
        final role = value['r'];
        if (pa != null && role is String) objects[group] = _Object(pa, role, _int(value['i'], 63));
      }
    }
    return _Model(gateways: gateways, gear: gear, groups: groups, objects: objects);
  }
}
