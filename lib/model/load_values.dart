import '../knx/dpt_codec.dart';
import '../knx/group_catalog.dart';
import '../knx/telegram.dart';

/// What a channel measures.
enum LoadKind {
  /// Current, normalized to amperes.
  current,

  /// Power, normalized to watts.
  power,
}

/// Factor to the unit of [LoadKind]; `null` if the type does not fit.
double? _factor(LoadKind kind, Dpt dpt) => switch ((kind, dpt.main, dpt.sub)) {
  (LoadKind.current, 7, 12 || null) => 0.001, // mA
  (LoadKind.current, 9, 21 || null) => 0.001, // mA
  (LoadKind.current, 14, 19 || null) => 1, // A
  (LoadKind.power, 9, 24 || null) => 1000, // kW
  (LoadKind.power, 14, 56 || null) => 1, // W
  _ => null,
};

/// The datapoint type alone says what is measured (7.012, 9.021, 14.019, 9.024, 14.056).
LoadKind? _kindOfDpt(Dpt dpt) => switch ((dpt.main, dpt.sub)) {
  (7, 12) || (9, 21) || (14, 19) => LoadKind.current,
  (9, 24) || (14, 56) => LoadKind.power,
  _ => null,
};

/// Name parts that rule out a measurement, even with "Strom" (current) in the name.
const _notAMeasurement = [
  'zähler',
  'zaehler',
  'meter',
  'verbrauch',
  'energie',
  'energy',
  'ausfall',
  'failure',
  'stoß',
  'stoss',
  'schwell',
  'threshold',
  'grenz',
  'limit',
  'alarm',
  'störung',
  'fault',
  'überlast',
  'overload',
  'abwurf',
  'steuerung',
  'status des',
];

LoadKind? _kindOfName(String name) {
  final n = name.toLowerCase();
  if (_notAMeasurement.any(n.contains)) return null;
  // Whole words, so "Stromkreis" (circuit) or "Blast" do not count.
  final words = n.split(RegExp(r'[^a-zäöüß0-9]+'));
  if (words.any(const {'strom', 'laststrom', 'current', 'ampere', 'strommessung', 'stromwert'}.contains)) {
    return LoadKind.current;
  }
  if (words.any(const {'leistung', 'wirkleistung', 'power', 'watt', 'last', 'load'}.contains)) return LoadKind.power;
  return null;
}

/// Whether [g] is a measuring channel. The type decides if it names current or
/// power. A generic or missing type needs a matching name; another specific
/// type (9.001 temperature) never is one.
LoadKind? loadKindOf(GroupInfo g, Dpt? dpt) {
  if (dpt != null) {
    if (_kindOfDpt(dpt) case final kind?) return kind;
    if (dpt.sub != null && !(dpt.main == 7 && dpt.sub == 1)) return null;
    if (dpt.main != 7 && dpt.main != 9 && dpt.main != 14) return null;
    final byName = _kindOfName(g.name);
    if (byName == null) return null;
    final effective = dpt.main == 7 ? const Dpt(7) : dpt;
    return _factor(byName, effective) == null ? null : byName;
  }
  return _kindOfName(g.name);
}

/// Measured value of [t] in the unit of [kind]; `null` if it contains no value
/// (read request, wrong length, own telegram).
double? loadValueOf(LoadKind kind, Dpt? dpt, Telegram t) {
  if (t.outgoing || t.type == TelegramType.read || t.isSmall) return null;
  // Without a type the length counts: 2 bytes float, 4 bytes IEEE.
  final effective = switch (dpt) {
    null when t.data.length == 2 => const Dpt(9),
    null when t.data.length == 4 => const Dpt(14),
    null => null,
    final d when d.main == 7 && d.sub == 1 => const Dpt(7),
    final d => d,
  };
  if (effective == null) return null;
  final factor = _factor(kind, effective);
  if (factor == null) return null;
  final value = numericValue(effective, t);
  return value == null || !value.isFinite ? null : value * factor;
}

/// A measured value.
typedef LoadSample = ({DateTime time, double value});

/// Why a channel stands out.
enum LoadHintKind {
  /// Used to send regularly and is now silent.
  silent,

  /// Ran continuously and now measures practically nothing.
  dropped,

  /// Deviates clearly from the usual for several measured values.
  deviation,
}

/// Thresholds of the hints, deliberately cautious and stated openly in the app.
abstract final class LoadRules {
  /// The usual needs this many measured values (non-zero) …
  static const baselineSamples = 20;

  /// … and they must span at least this long.
  static const baselineSpan = Duration(hours: 2);

  /// The latest measured values, all of which must stand out. A single outlier stays silent.
  static const recent = 3;

  /// Deviation from the usual from which a value counts (0.5 = 50 %).
  static const deviation = 0.5;

  /// Below this, a deviation means nothing (measurement noise of small loads).
  static const floorAmpere = 0.1;
  static const floorWatt = 25.0;

  /// Up to this share of the usual, a value counts as "nothing".
  static const droppedShare = 0.05;

  /// Zeros more often than this share: the load is switched, zero is normal.
  static const switchedShare = 0.2;

  /// Silent only after this many send intervals, at least [silentAtLeast].
  static const silentCycles = 5;
  static const silentAtLeast = Duration(minutes: 30);

  /// Longest send interval at which silence means something.
  static const silentCycleMax = Duration(hours: 1);
}

/// Hint for a channel; the numbers are included so it can be verified.
class LoadHint {
  const LoadHint(this.kind, {required this.typical, required this.latest, this.cycle, this.since});

  final LoadHintKind kind;

  /// Median of the earlier measured values (without zeros).
  final double typical;
  final double latest;

  /// Usual send interval ([LoadHintKind.silent]).
  final Duration? cycle;

  /// Time of the last telegram ([LoadHintKind.silent]).
  final DateTime? since;

  /// Deviation in percent, signed.
  int get percent => typical == 0 ? 0 : ((latest - typical) / typical * 100).round();
}

/// A channel with its values.
class LoadChannel {
  LoadChannel({required this.group, required this.kind, required this.samples, required this.hint});

  final GroupInfo group;
  final LoadKind kind;

  /// By time, oldest first.
  final List<LoadSample> samples;
  final LoadHint? hint;

  int get address => group.address;
  LoadSample? get latest => samples.isEmpty ? null : samples.last;

  /// Largest measured value in the time range.
  LoadSample? get peak => samples.isEmpty ? null : samples.reduce((a, b) => b.value > a.value ? b : a);
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Hint for [samples] (oldest first) at time [now]; `null` without a reason.
/// Better once too few than a false alarm: only what the usual reliably knows
/// counts, and a switched-off load is not a failure.
LoadHint? loadHint(LoadKind kind, List<LoadSample> samples, DateTime now) {
  if (samples.length <= LoadRules.recent) return null;
  final earlier = samples.sublist(0, samples.length - LoadRules.recent);
  final recent = samples.sublist(samples.length - LoadRules.recent);
  final working = [
    for (final x in earlier)
      if (x.value != 0) x,
  ];
  if (working.length < LoadRules.baselineSamples) return null;
  if (working.last.time.difference(working.first.time) < LoadRules.baselineSpan) return null;
  final typical = _median([for (final x in working) x.value.abs()]);
  if (typical == 0) return null;
  final latest = recent.last.value;

  // Silent: only for truly regular sending. Many actuators only send on change,
  // in which case silence means nothing at all.
  final gaps = [
    for (var i = 1; i < samples.length; i++) samples[i].time.difference(samples[i - 1].time).inMilliseconds.toDouble(),
  ]..sort();
  final cycle = Duration(milliseconds: _median(gaps).round());
  final p90 = gaps[(gaps.length * 0.9).floor().clamp(0, gaps.length - 1)];
  if (cycle > Duration.zero && cycle <= LoadRules.silentCycleMax && p90 <= cycle.inMilliseconds * 1.5) {
    final limit = cycle * LoadRules.silentCycles;
    final wait = limit > LoadRules.silentAtLeast ? limit : LoadRules.silentAtLeast;
    if (now.difference(samples.last.time) > wait) {
      return LoadHint(LoadHintKind.silent, typical: typical, latest: latest, cycle: cycle, since: samples.last.time);
    }
  }

  final floor = kind == LoadKind.current ? LoadRules.floorAmpere : LoadRules.floorWatt;
  final zeros = earlier.length - working.length;
  if (recent.every((x) => x.value.abs() <= typical * LoadRules.droppedShare)) {
    // Often zero: the load is switched, that is not a failure.
    if (zeros > earlier.length * LoadRules.switchedShare || typical < floor) return null;
    return LoadHint(LoadHintKind.dropped, typical: typical, latest: latest);
  }

  // Deviation: all latest values on the same side, beyond threshold and spread.
  final spread = _median([for (final x in working) (x.value.abs() - typical).abs()]) * 1.4826 * 3;
  var limit = typical * LoadRules.deviation;
  if (spread > limit) limit = spread;
  if (floor > limit) limit = floor;
  final above = recent.every((x) => x.value.abs() - typical > limit);
  final below = recent.every((x) => typical - x.value.abs() > limit);
  return above || below ? LoadHint(LoadHintKind.deviation, typical: typical, latest: latest) : null;
}

/// Measuring channels from [groups] and their values from [telegrams], by
/// address. Only reads existing telegrams and never queries the bus. Channels
/// without a measured value appear with an empty list so they stay findable.
List<LoadChannel> loadChannels(
  Iterable<GroupInfo> groups,
  Iterable<Telegram> telegrams, {
  required Dpt? Function(int address) dptOf,
  required DateTime now,
}) {
  final kinds = <int, (GroupInfo, LoadKind, Dpt?)>{};
  for (final g in groups) {
    final dpt = dptOf(g.address);
    if (loadKindOf(g, dpt) case final kind?) kinds[g.address] = (g, kind, dpt);
  }
  final samples = <int, List<LoadSample>>{for (final a in kinds.keys) a: []};
  for (final t in telegrams) {
    final entry = kinds[t.destination];
    if (entry == null) continue;
    if (loadValueOf(entry.$2, entry.$3, t) case final v?) samples[t.destination]!.add((time: t.time, value: v));
  }
  final out = [
    for (final MapEntry(key: address, value: (g, kind, _)) in kinds.entries)
      () {
        final list = samples[address]!..sort((a, b) => a.time.compareTo(b.time));
        return LoadChannel(group: g, kind: kind, samples: list, hint: loadHint(kind, list, now));
      }(),
  ];
  return out..sort((a, b) => a.address.compareTo(b.address));
}
