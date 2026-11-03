import '../knx/group_catalog.dart';

/// Predefined charts derived from the ETS project: which addresses typically
/// belong together (actual and setpoint of a room, the weather station …).
/// The library under "Diagramme" (charts) shows them; "Übernehmen" (adopt) turns
/// one into a custom chart ([SavedCharts]).
enum ChartRecipe {
  /// Per room: actual temperature, setpoint, control value, heating/cooling.
  climate,

  /// Per room: CO₂, humidity, plus the temperature.
  air,

  /// Per room: presence, brightness, light status feedback.
  light,

  /// Blind positions, plus wind and rain alarm.
  shading,

  /// Outdoor temperature, wind, brightness, rain.
  weather,

  /// Power and meter readings.
  energy,
}

/// A template: recipe, place (room from the name or ETS building, empty for the
/// whole building) and the addresses in order.
class ChartTemplate {
  const ChartTemplate(this.recipe, this.place, this.addresses);

  final ChartRecipe recipe;
  final String place;
  final List<int> addresses;

  @override
  String toString() => '${recipe.name}($place: $addresses)';
}

/// At most this many series per template (like [SavedCharts.maxSeries]).
const _maxSeries = 8;

/// Blinds per shading template; more are spread over further templates.
const _shadesPerChart = 6;

/// Roles of a group address in the recipes.
enum _Role {
  temperature,
  setpoint,
  valve,
  heating,
  co2,
  humidity,
  lux,
  presence,
  lightFeedback,
  shade,
  outdoorTemperature,
  outdoorLux,
  wind,
  rain,
  power,
  energy,
}

/// Words that denote a role or just "value" – not a place. Lowercase, without
/// umlauts (see [_fold]).
const _vocabulary = {
  'ist',
  'soll',
  'sollwert',
  'basissollwert',
  'wert',
  'temperatur',
  'temp',
  'raumtemperatur',
  'isttemperatur',
  'solltemperatur',
  'stellgroesse',
  'stellwert',
  'ventil',
  'status',
  'rm',
  'rueckmeldung',
  'feedback',
  'schalten',
  'praesenz',
  'bewegung',
  'anwesenheit',
  'helligkeit',
  'lux',
  'co2',
  'feuchte',
  'luftfeuchte',
  'luftfeuchtigkeit',
  'relative',
  'heizen',
  'kuehlen',
  'heizung',
  'zustand',
  'actual',
  'setpoint',
  'temperature',
  'humidity',
  'brightness',
  'presence',
  'motion',
  'valve',
  'heating',
  'cooling',
  'switch',
  'state',
  'value',
  'position',
  'hoehe',
  'lamellen',
  'licht',
  'light',
  'luftqualitaet',
  'voc',
  'raum',
  'room',
  'aktuelle',
  'current',
  'dimmwert',
  'dim',
};

/// Lowercase, umlauts spelled out – names from the ETS use both.
String _fold(String s) =>
    s.toLowerCase().replaceAll('ä', 'ae').replaceAll('ö', 'oe').replaceAll('ü', 'ue').replaceAll('ß', 'ss');

bool _has(String folded, String pattern) => RegExp(pattern).hasMatch(folded);

const _outdoor = r'aussen|outdoor|outside|wetter|weather';
const _status = r'\brm\b|rueck|status|feedback|zustand|state';

/// Role from datapoint type and name; lights and blinds also from the path
/// ("Beleuchtung › Rückmeldung"), because the name often only says "L01 …".
_Role? _roleOf(String name, String? path, Dpt? dpt) {
  if (dpt == null) return null;
  final n = _fold(name);
  final np = _fold('$name ${path ?? ''}');
  final light = _has(np, r'licht|light|leuchte|lampe|beleuchtung|spot|dimm');
  final shade = _has(np, r'jalousie|rolll?aden|raffstore|markise|blind|shutter|beschattung|behang');
  final setpoint = _has(n, r'soll|setpoint|set point|basis');
  return switch ((dpt.main, dpt.sub)) {
    (9, 1) when _has(n, _outdoor) => _Role.outdoorTemperature,
    (9, 1) when setpoint => _Role.setpoint,
    (9, 1) => _Role.temperature,
    (9, 4) when _has(n, _outdoor) => _Role.outdoorLux,
    (9, 4) => _Role.lux,
    (9, 5) => _Role.wind,
    (9, 7) => _Role.humidity,
    (9, 8) => _Role.co2,
    (9, 24) || (14, 56) => _Role.power,
    (13, 10) || (13, 13) => _Role.energy,
    (5, 1) when shade && _has(np, r'position|hoehe|height|status|rm\b|rueck') => _Role.shade,
    (5, 1) when _has(n, r'stell|ventil|valve') => _Role.valve,
    (5, 1) when light && _has(np, _status) => _Role.lightFeedback,
    (1, 18) => _Role.presence,
    (1, _) when _has(n, r'praesenz|presence|bewegung|motion|anwesen') => _Role.presence,
    (1, _) when _has(n, r'regen|rain') => _Role.rain,
    (1, _) when _has(n, r'heizen|kuehlen|heating|cooling') && _has(n, _status) => _Role.heating,
    (1, 1) when light && _has(np, _status) => _Role.lightFeedback,
    _ => null,
  };
}

/// Channel abbreviations like "L01", "F01", "JA02" – not a place ("K1" for a
/// children's room stays one).
final _channel = RegExp(r'^[A-Za-z]{1,2}\d{2,3}$');

/// Place from the name: what comes before the first role word ("EG KÜ
/// Ist-Temperatur" → "EG KÜ"), otherwise what remains ("Ist-Temperatur
/// Wohnen" → "Wohnen"). Channel abbreviations do not count ("EG WZ L01 …" → "EG WZ").
String _placeFromName(String name) {
  final tokens = name.split(RegExp(r'[\s\-_/,:;()]+')).where((t) => t.isNotEmpty && !_channel.hasMatch(t)).toList();
  bool role(String t) => _vocabulary.contains(_fold(t));
  final first = tokens.indexWhere(role);
  final before = first < 0 ? tokens : tokens.sublist(0, first);
  if (before.isNotEmpty) return before.join(' ');
  return tokens.where((t) => !role(t)).join(' ');
}

/// Place of an address: from the name, otherwise the ETS location of the sending
/// device, otherwise the middle group.
String _placeOf(GroupInfo g, Map<int, DeviceInfo> devices) {
  final fromName = _placeFromName(g.name);
  if (fromName.isNotEmpty) return fromName;
  final link = g.links.where((l) => l.sends).firstOrNull ?? g.links.firstOrNull;
  final location = link == null ? null : devices[link.device]?.location;
  if (location != null && location.isNotEmpty) return location.split(' › ').last;
  final path = g.path?.split(' › ');
  return path == null || path.length < 2 ? '' : path[1];
}

/// Whether [place] belongs to room [room]: equal or finer ("OG BZ L01" in "OG BZ").
bool _within(String place, String room) {
  final p = _fold(place);
  final r = _fold(room);
  return p == r || (r.isNotEmpty && p.startsWith('$r '));
}

/// Templates for a project: [groups] and [devices] from the catalog, [dptOf]
/// with the types including the user's own corrections. Order: by recipe, then
/// room.
List<ChartTemplate> chartTemplates(
  Map<int, GroupInfo> groups,
  Map<int, DeviceInfo> devices, {
  required Dpt? Function(int address) dptOf,
}) {
  final byRole = <_Role, List<(int, String)>>{};
  for (final g in groups.values.toList()..sort((a, b) => a.address.compareTo(b.address))) {
    final role = _roleOf(g.name, g.path, dptOf(g.address));
    if (role != null) (byRole[role] ??= []).add((g.address, _placeOf(g, devices)));
  }
  List<(int, String)> all(_Role r) => byRole[r] ?? const [];
  List<int> inRoom(_Role r, String room, {int max = _maxSeries}) => [
    for (final (a, p) in all(r))
      if (_within(p, room)) a,
  ].take(max).toList();
  List<int> limit(Iterable<int> list) => list.toSet().take(_maxSeries).toList();

  final out = <ChartTemplate>[];

  // Per room with actual temperature: room climate.
  final climateRooms = {for (final (_, p) in all(_Role.temperature)) p};
  for (final room in climateRooms) {
    final series = limit([
      ...inRoom(_Role.temperature, room, max: 1),
      ...inRoom(_Role.setpoint, room, max: 2),
      ...inRoom(_Role.valve, room, max: 2),
      ...inRoom(_Role.heating, room, max: 2),
    ]);
    if (series.length >= 2) out.add(ChartTemplate(ChartRecipe.climate, room, series));
  }

  // Per room with CO₂ or humidity: air.
  final airRooms = {
    for (final (_, p) in [...all(_Role.co2), ...all(_Role.humidity)]) p,
  };
  for (final room in airRooms) {
    final series = limit([
      ...inRoom(_Role.co2, room, max: 2),
      ...inRoom(_Role.humidity, room, max: 2),
      ...inRoom(_Role.temperature, room, max: 1),
    ]);
    if (series.length >= 2) out.add(ChartTemplate(ChartRecipe.air, room, series));
  }

  // Per room with presence, brightness or light status feedback: light.
  final lightRooms = {
    for (final (_, p) in [...all(_Role.presence), ...all(_Role.lux), ...all(_Role.lightFeedback)]) p,
  };
  for (final room in lightRooms) {
    final series = limit([
      ...inRoom(_Role.presence, room, max: 2),
      ...inRoom(_Role.lux, room, max: 2),
      ...inRoom(_Role.lightFeedback, room, max: 4),
    ]);
    if (series.length >= 2) out.add(ChartTemplate(ChartRecipe.light, room, series));
  }

  // Shading per floor (first word of the place: "EG", "OG"), otherwise for the
  // whole house; up to six blinds each, plus wind and rain alarm.
  final alarms = [...all(_Role.wind), ...all(_Role.rain)].map((e) => e.$1).take(2).toList();
  final byFloor = <String, List<int>>{};
  for (final (a, p) in all(_Role.shade)) {
    final words = p.split(' ');
    (byFloor[words.length > 1 ? words.first : ''] ??= []).add(a);
  }
  if (byFloor.length == 1) byFloor[''] = byFloor.remove(byFloor.keys.first)!;
  for (final MapEntry(key: floor, value: shades) in byFloor.entries) {
    for (var i = 0; i < shades.length; i += _shadesPerChart) {
      final part = shades.skip(i).take(_shadesPerChart).toList();
      final n = shades.length > _shadesPerChart ? ' ${i ~/ _shadesPerChart + 1}' : '';
      out.add(ChartTemplate(ChartRecipe.shading, '$floor$n'.trim(), limit([...part, ...alarms])));
    }
  }

  // Weather station.
  final weather = limit([
    ...all(_Role.outdoorTemperature).take(1).map((e) => e.$1),
    ...all(_Role.wind).take(1).map((e) => e.$1),
    ...all(_Role.outdoorLux).take(2).map((e) => e.$1),
    ...all(_Role.rain).take(1).map((e) => e.$1),
  ]);
  if (weather.length >= 2) out.add(ChartTemplate(ChartRecipe.weather, '', weather));

  // Energy: power before meter readings.
  final energy = limit([...all(_Role.power).map((e) => e.$1), ...all(_Role.energy).map((e) => e.$1)]);
  if (energy.isNotEmpty) out.add(ChartTemplate(ChartRecipe.energy, '', energy));

  return out..sort((a, b) {
    final r = a.recipe.index.compareTo(b.recipe.index);
    return r != 0 ? r : _fold(a.place).compareTo(_fold(b.place));
  });
}

/// Role of an address (as in the recipes) for custom templates
/// ([TemplateRule]); `null` if none is recognizable.
String? chartRoleOf(GroupInfo g, Dpt? dpt) => _roleOf(g.name, g.path, dpt)?.name;

/// All roles a template can name.
Set<String> get chartRoleNames => {for (final r in _Role.values) r.name};

/// Place of an address as in the recipes (name, ETS location, middle group).
String chartPlaceOf(GroupInfo g, Map<int, DeviceInfo> devices) => _placeOf(g, devices);

/// Whether [place] belongs to room [room] (equal or finer).
bool chartPlaceWithin(String place, String room) => _within(place, room);
