import '../catalog_store.dart';
import '../knx/dpt_codec.dart';
import '../knx/group_catalog.dart';
import '../knx/telegram.dart';
import 'device_channels.dart';
import 'push_buttons.dart';

/// Form factor of a device – determines the drawing on the device sheet.
enum DeviceShape {
  /// DIN rail device with channels (actuators, default).
  din,

  /// Push button (55 frame, glass push button).
  pushButton,

  /// Push-button interface/binary input for the flush-mounted box, with connection wires.
  flushInput,

  /// Presence detector on the ceiling.
  ceilingPresence,

  /// Motion detector on the wall (outdoor).
  wallMotion,

  /// Weather station.
  weatherStation,

  /// Smoke detector on the ceiling.
  smokeDetector,
}

final _flushWords = RegExp(r'interface|schnittstelle|binär|binary', caseSensitive: false);
final _presenceWords = RegExp(r'präsenz|presence|prema|\bP360|\bS360', caseSensitive: false);
final _motionWords = RegExp(r'bewegungsmelder|motion|luxa|\bP300|wächter', caseSensitive: false);
final _smokeWords = RegExp(r'rauchwarn|rauchmelder|smoke|\bRWM\b', caseSensitive: false);
final _weatherWords = RegExp(r'wetter|weather|meteo', caseSensitive: false);

/// Form factor from product and name.
DeviceShape shapeOf(int device, GroupCatalog catalog) {
  final info = catalog.devices[device];
  if (info == null) return DeviceShape.din;
  final name = '${info.product ?? ''} ${info.name}';
  if (pushButtonOf(device, catalog) != null) return DeviceShape.pushButton;
  if (_smokeWords.hasMatch(name)) return DeviceShape.smokeDetector;
  if (_weatherWords.hasMatch(name)) return DeviceShape.weatherStation;
  if (_motionWords.hasMatch(name)) return DeviceShape.wallMotion;
  if (_presenceWords.hasMatch(name)) return DeviceShape.ceilingPresence;
  // DIN rail binary inputs (REG) stay on the DIN rail.
  if (_flushWords.hasMatch(name) &&
      !RegExp(r'\bREG\b|\d\s*TE\b|hutschiene|din rail', caseSensitive: false).hasMatch(name)) {
    return DeviceShape.flushInput;
  }
  return DeviceShape.din;
}

/// All objects of a device, by object number.
List<DeviceObject> objectsOf(int device, GroupCatalog catalog) {
  final out = <DeviceObject>[];
  final seen = <int>{};
  for (final g in catalog.groups.values) {
    for (final l in g.links) {
      if (l.device != device || !seen.add(g.address)) continue;
      out.add(DeviceObject(address: g.address, number: l.object, text: l.text, sends: l.sends));
    }
  }
  return out..sort((a, b) => (a.number ?? 1 << 20).compareTo(b.number ?? 1 << 20));
}

/// Role of a sensor object for the drawing.
enum SensorRole {
  presence,
  brightness,
  light,
  dayNight,
  temperature,
  wind,
  rain,
  twilight,
  elevation,
  azimuth,
  humidity,
}

/// Role from datapoint type and name – `null` if the object has no place in the
/// drawing (it still appears in the object list).
SensorRole? roleOf(DeviceObject o, GroupCatalog catalog) {
  final g = catalog[o.address];
  final d = g?.dpt;
  final name = '${o.text ?? ''} ${g?.name ?? ''}'.toLowerCase();
  if (RegExp(r'defekt|fehler|error|fault|alarm').hasMatch(name)) return null;
  if (RegExp(r'elevation|höhe der sonne|sonnenhöhe').hasMatch(name)) return SensorRole.elevation;
  if (RegExp(r'azimut').hasMatch(name)) return SensorRole.azimuth;
  if (RegExp(r'tag\s*/\s*nacht|day\s*/\s*night').hasMatch(name)) return SensorRole.dayNight;
  if (RegExp(r'dämmerung|twilight').hasMatch(name)) return SensorRole.twilight;
  if (RegExp(r'regen|rain').hasMatch(name)) return SensorRole.rain;
  if (d?.main == 9 && d?.sub == 5 || RegExp(r'wind').hasMatch(name)) return SensorRole.wind;
  if (d?.main == 9 && d?.sub == 7 || RegExp(r'feuchte|humidity').hasMatch(name)) return SensorRole.humidity;
  if (d?.main == 9 && d?.sub == 4 || RegExp(r'helligkeit|brightness|lux').hasMatch(name)) return SensorRole.brightness;
  if (d?.main == 9 && d?.sub == 1 || RegExp(r'temperatur').hasMatch(name)) return SensorRole.temperature;
  if (RegExp(r'präsenz|anwesen|presence|bewegung|motion|occupan').hasMatch(name)) return SensorRole.presence;
  if (d?.main == 1 && o.sends || RegExp(r'licht|light|leuchte|schalten').hasMatch(name)) return SensorRole.light;
  return null;
}

/// Current value of an object as a number (`null` = unknown).
double? numberOf(int address, Map<int, Telegram> latest) {
  final t = latest[address];
  if (t == null || t.type == TelegramType.read) return null;
  return numericValue(CatalogStore.instance.dptOf(address), t);
}

/// Compass direction from a name ("Helligkeit NW (vorne)", "Ost"): angle in
/// degrees (0 = north, clockwise) or `null`.
double? bearingOf(String name) {
  final m = RegExp(
    r'\b(NO|NE|NW|SO|SE|SW|N|O|E|S|W|nord|ost|süd|west|north|east|south)\b',
    caseSensitive: false,
  ).firstMatch(name);
  if (m == null) return null;
  return switch (m[1]!.toLowerCase()) {
    'n' || 'nord' || 'north' => 0,
    'no' || 'ne' => 45,
    'o' || 'e' || 'ost' || 'east' => 90,
    'so' || 'se' => 135,
    's' || 'süd' || 'south' => 180,
    'sw' => 225,
    'w' || 'west' => 270,
    'nw' => 315,
    _ => null,
  };
}
