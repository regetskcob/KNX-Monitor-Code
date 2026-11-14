import '../catalog_store.dart';
import '../knx/dpt_codec.dart';
import '../knx/group_catalog.dart';
import '../knx/telegram.dart';
import 'object_groups.dart';

/// What a heating address means for the room.
enum HeatingRole { actual, setpoint, valve }

final _valveName = RegExp(r'stellwert|stellgr|ventil|valve|control value|heizen \(%\)', caseSensitive: false);
final _setpointName = RegExp(r'soll|setpoint|set point', caseSensitive: false);
final _actualName = RegExp(r'\bist\b|ist-|isttemp|temperatur|actual|temperature', caseSensitive: false);
final _notRoom = RegExp(
  r'außen|aussen|outdoor|outside|vorlauf|rücklauf|ruecklauf|flow|return|boden|floor|wasser|water|kessel|boiler|puffer',
  caseSensitive: false,
);

/// Role of [g] in room heating, from its datapoint type and name; `null` if
/// it is none (outdoor and system temperatures included).
HeatingRole? heatingRole(GroupInfo g, Dpt? dpt) {
  final text = '${g.name} ${g.path ?? ''}';
  if (_notRoom.hasMatch(g.name)) return null;
  if (((dpt?.main == 5 && dpt?.sub == 1) || dpt?.main == 1) && _valveName.hasMatch(text)) return HeatingRole.valve;
  if (dpt?.main != 9 || (dpt?.sub != null && dpt?.sub != 1)) return null;
  if (_setpointName.hasMatch(text)) return HeatingRole.setpoint;
  if (_actualName.hasMatch(g.name)) return HeatingRole.actual;
  return null;
}

/// What the three values of a room say together.
enum HeatingVerdict {
  /// Nothing heard yet.
  noData,

  /// Values are there, but not enough to judge (no setpoint or no actual value).
  incomplete,

  /// The actual temperature has not been sent for a long time: the controller
  /// is blind and may run in emergency mode.
  staleActual,

  /// Too cold, but the controller asks for no heat.
  notCalling,

  /// Too cold, valve open for a long time, and the room does not warm up.
  notWarming,

  /// Warmer than the setpoint, valve open anyway.
  overheating,

  /// Too cold, valve open: it is heating.
  heating,

  /// Within the setpoint.
  ok;

  bool get issue => this == staleActual || this == notCalling || this == notWarming || this == overheating;
}

/// A room with its heating values.
class HeatingRoom {
  HeatingRoom(this.room);

  final String room;
  final addresses = <HeatingRole, List<int>>{};

  double? actual, setpoint, valve;

  /// Time of the last actual temperature.
  DateTime? actualAt;
  HeatingVerdict verdict = HeatingVerdict.noData;
}

/// Thresholds of the check.
class HeatingLimits {
  const HeatingLimits({
    this.tolerance = 1.0,
    this.staleAfter = const Duration(hours: 2),
    this.warmUp = const Duration(minutes: 90),
    this.minRise = 0.3,
    this.openValve = 50,
  });

  /// Kelvin the room may be away from the setpoint before it counts.
  final double tolerance;

  /// An actual temperature older than this is missing.
  final Duration staleAfter;

  /// With an open valve the room should have gained [minRise] within this time.
  final Duration warmUp;
  final double minRise;

  /// Valve position in percent from which it counts as open.
  final double openValve;
}

/// Heating check per room: actual temperature, setpoint and valve side by side
/// with a verdict that says who to look at – controller, actuator or the
/// hydraulics. Read-only, from what was heard; [history] is the recording in
/// chronological order, [now] the time to judge at.
List<HeatingRoom> checkHeating(
  GroupCatalog catalog,
  Map<int, Telegram> latest,
  List<Telegram> history, {
  required DateTime now,
  CatalogStore? store,
  HeatingLimits limits = const HeatingLimits(),
}) {
  final c = store ?? CatalogStore.instance;
  final index = ObjectIndex.of(catalog);
  final rooms = <String, HeatingRoom>{};
  for (final g in catalog.groups.values) {
    final role = heatingRole(g, c.dptOf(g.address));
    if (role == null) continue;
    final room = index.objectOf(g.address)?.room ?? _roomFromName(g.name);
    if (room == null) continue;
    (rooms.putIfAbsent(room, () => HeatingRoom(room)).addresses[role] ??= []).add(g.address);
  }

  Telegram? last(HeatingRoom r, HeatingRole role) {
    Telegram? best;
    for (final a in r.addresses[role] ?? const <int>[]) {
      final t = latest[a];
      if (t == null || t.type == TelegramType.read) continue;
      if (best == null || t.time.isAfter(best.time)) best = t;
    }
    return best;
  }

  double? number(Telegram? t) {
    if (t == null) return null;
    final dpt = c.dptOf(t.destination);
    if (dpt?.main == 1) return t.data.isNotEmpty && t.data[0] & 1 == 1 ? 100 : 0;
    return numericValue(dpt, t);
  }

  final result =
      rooms.values.where((r) => r.addresses.length > 1 || r.addresses.containsKey(HeatingRole.valve)).toList()
        ..sort((a, b) => a.room.compareTo(b.room));
  for (final r in result) {
    final actual = last(r, HeatingRole.actual);
    r
      ..actual = number(actual)
      ..actualAt = actual?.time
      ..setpoint = number(last(r, HeatingRole.setpoint))
      ..valve = number(last(r, HeatingRole.valve));
    r.verdict = _verdict(r, history, now, limits, c);
  }
  return result;
}

HeatingVerdict _verdict(HeatingRoom r, List<Telegram> history, DateTime now, HeatingLimits l, CatalogStore c) {
  final actual = r.actual, setpoint = r.setpoint, valve = r.valve;
  if (actual == null && setpoint == null && valve == null) return HeatingVerdict.noData;
  if (r.actualAt case final at? when now.difference(at) > l.staleAfter) return HeatingVerdict.staleActual;
  if (actual == null || setpoint == null) return HeatingVerdict.incomplete;
  final missing = setpoint - actual;
  if (missing > l.tolerance) {
    if (valve == null) return HeatingVerdict.incomplete;
    if (valve <= 0) return HeatingVerdict.notCalling;
    if (valve >= l.openValve && _flat(r, history, now, l, c)) return HeatingVerdict.notWarming;
    return HeatingVerdict.heating;
  }
  if (missing < -l.tolerance && (valve ?? 0) > 0) return HeatingVerdict.overheating;
  return HeatingVerdict.ok;
}

/// Whether the room has not warmed up over [HeatingLimits.warmUp] although the
/// valve was open the whole time. Needs a recording that reaches back that far.
bool _flat(HeatingRoom r, List<Telegram> history, DateTime now, HeatingLimits l, CatalogStore c) {
  final from = now.subtract(l.warmUp);
  final actual = {...?r.addresses[HeatingRole.actual]};
  final valves = {...?r.addresses[HeatingRole.valve]};
  double? before;
  var reaches = false;
  for (final t in history) {
    if (t.type == TelegramType.read) continue;
    if (valves.contains(t.destination) && !t.time.isBefore(from)) {
      final dpt = c.dptOf(t.destination);
      final v = dpt?.main == 1 ? (t.data.isNotEmpty && t.data[0] & 1 == 1 ? 100.0 : 0.0) : numericValue(dpt, t);
      if (v != null && v < l.openValve) return false;
    }
    if (!actual.contains(t.destination)) continue;
    if (t.time.isBefore(from)) {
      reaches = true;
      before = numericValue(c.dptOf(t.destination), t) ?? before;
    }
  }
  return reaches && before != null && r.actual! - before < l.minRise;
}

/// Room from a name like "OG Bad Ist-Temperatur": everything before the role word.
String? _roomFromName(String name) {
  final m = RegExp(
    r'^(.*?)[\s\-–_.]*(ist\b|ist-|soll|stellwert|ventil|temperatur|setpoint|actual|valve)',
    caseSensitive: false,
  ).firstMatch(name);
  final room = m?[1]?.trim();
  return room == null || room.isEmpty ? null : room;
}

final _hasHeating = Expando<bool>();

/// Whether [catalog] has room heating to check at all (remembered per catalog).
bool hasHeating(GroupCatalog catalog, {CatalogStore? store}) => _hasHeating[catalog] ??= () {
  final c = store ?? CatalogStore.instance;
  return catalog.groups.values.any((g) => heatingRole(g, c.dptOf(g.address)) == HeatingRole.valve);
}();
