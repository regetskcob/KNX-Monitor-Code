import '../knx/group_catalog.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/object_groups.dart';
import '../ui/telegram_row.dart' show formatDate;

/// Platform of the Home Assistant KNX integration, with its key in the YAML configuration
/// (home-assistant.io/integrations/knx).
enum HaPlatform {
  light('light'),
  cover('cover'),
  climate('climate'),
  switchPlatform('switch'),
  binarySensor('binary_sensor'),
  sensor('sensor');

  const HaPlatform(this.key);

  /// Key under `knx:`.
  final String key;

  String get title => switch (this) {
    light => s.haPlatformLight,
    cover => s.haPlatformCover,
    climate => s.haPlatformClimate,
    switchPlatform => s.haPlatformSwitch,
    binarySensor => s.haPlatformBinarySensor,
    sensor => s.haPlatformSensor,
  };
}

/// Why a mapping should be checked – flagged instead of guessed.
enum HaDoubt {
  /// Datapoint type missing in the project; mapped by name only.
  noDpt,

  /// No status feedback found: Home Assistant shows the last sent state.
  noState,

  /// The name does not tell whether it is a light or a load – created as a switch.
  lightOrSwitch,

  /// Several addresses match the same key; the first one is used.
  ambiguous,

  /// Setpoint without its own feedback: the state reads the same address.
  targetFromCommand,

  /// Only the main type of the DPT is known; `type` is generic.
  typeGuessed,

  /// Light with brightness only: Home Assistant requires a switch command (`address`). The entry is
  /// commented out in the file.
  noSwitch;

  String get text => switch (this) {
    noDpt => s.haDoubtNoDpt,
    noState => s.haDoubtNoState,
    lightOrSwitch => s.haDoubtLightOrSwitch,
    ambiguous => s.haDoubtAmbiguous,
    targetFromCommand => s.haDoubtTargetFromCommand,
    typeGuessed => s.haDoubtTypeGuessed,
    noSwitch => s.haDoubtNoSwitch,
  };
}

/// An entity for Home Assistant: name, room, addresses per key and further options (`type`,
/// `device_class` …).
class HaEntity {
  HaEntity(this.platform, this.name, {this.room});

  final HaPlatform platform;
  final String name;

  /// Room from the naming scheme or the middle group, for selection.
  final String? room;

  /// Object from the naming scheme the entity comes from (key and display name) – basis for device
  /// suggestions.
  String? objectKey;
  String? objectName;

  /// Key → group address, in write order.
  final addresses = <String, int>{};

  /// Further keys with fixed values.
  final options = <String, Object>{};

  /// Uncertain points (empty = certain).
  final doubts = <HaDoubt>{};

  bool get uncertain => doubts.isNotEmpty;

  /// Required key missing: only commented out in the file.
  bool get incomplete => doubts.contains(HaDoubt.noSwitch);

  /// All group addresses used.
  Iterable<int> get groups => addresses.values;

  /// Stable identifier for selection (platform + first address).
  String get id => '${platform.key}:${addresses.values.first}';
}

/// How a device suggestion was detected.
enum HaDeviceSource {
  /// Shared object name in the naming scheme, e.g. "EG WZ F01".
  nameScheme,

  /// The same ETS device sends the values, e.g. the weather station.
  busDevice,
}

/// Suggestion for a device in Home Assistant (`device:` with `id` and `name`): Home Assistant
/// groups entities with the same `id` into one device.
class HaDevice {
  const HaDevice(this.id, this.name, {required this.source, required this.entities, this.room, this.busAddress});

  /// Stable identifier, e.g. `eg_wz_f01` or `knx_1_2_20`.
  final String id;
  final String name;
  final HaDeviceSource source;

  /// [HaEntity.id] of the entities that belong to it.
  final List<String> entities;

  /// Common room of all entities, otherwise `null`.
  final String? room;

  /// Individual address for [HaDeviceSource.busDevice].
  final int? busAddress;
}

/// Derives a configuration for the Home Assistant KNX integration from the ETS project and writes
/// it as YAML.
///
/// It is based on the objects from [ObjectIndex] (command and feedback per light, window, room) and
/// the datapoint types. Anything that cannot be mapped unambiguously gets an [HaDoubt] and a review
/// comment in the file – nothing is guessed.
abstract final class HaConfig {
  /// Entities from the project, sorted by room, platform and name.
  static List<HaEntity> fromCatalog(GroupCatalog catalog) {
    final index = ObjectIndex.of(catalog);
    final used = <int>{};
    final out = <HaEntity>[];
    for (final o in index.objects) {
      out.addAll(_fromObject(o, catalog, used));
    }
    // Single addresses outside the objects: measurements and notifications.
    for (final g in catalog.groups.values.toList()..sort((a, b) => a.address.compareTo(b.address))) {
      if (used.contains(g.address)) continue;
      final e = _single(g, catalog, room: index.objectOf(g.address)?.room ?? _pathRoom(g));
      if (e != null) {
        out.add(e);
        used.add(g.address);
      }
    }
    out.sort((a, b) {
      final r = (a.room ?? '\u{FFFF}').compareTo(b.room ?? '\u{FFFF}');
      if (r != 0) return r;
      final p = a.platform.index.compareTo(b.platform.index);
      return p != 0 ? p : a.name.compareTo(b.name);
    });
    return out;
  }

  /// No room in the name: use the main group (weather, energy …) for grouping.
  static String? _pathRoom(GroupInfo g) {
    final first = g.path?.split(' › ').first.trim();
    return first == null || first.isEmpty ? null : first;
  }

  // --- Detection -------------------------------------------------------------

  static final _lightWords = RegExp(
    r'licht|leuchte|lampe|beleucht|spot|led|downlight|pendel|light|lamp|dimm|\bli\b|\bbel\b|\bl\d{1,3}\b',
    caseSensitive: false,
  );
  static final _loadWords = RegExp(
    r'steckdose|socket|outlet|plug|pumpe|pump|ventilator|fan|lüfter|luefter|heizstab|boiler|brunnen|sauna',
    caseSensitive: false,
  );
  static final _coverWords = RegExp(
    r'auf/ab|auf-/ab|up/down|fahren|jalousie|rollladen|rolladen|rollo|raffstore|markise|blind|shutter|cover',
    caseSensitive: false,
  );
  static final _shortWords = RegExp(r'lamelle|stopp?/|step|schritt|slat|kurz', caseSensitive: false);
  static final _stopWords = RegExp(r'^\s*(stopp?|stop|halt|anhalten)\s*$', caseSensitive: false);
  static final _angleWords = RegExp(r'lamelle|slat|angle|winkel|wendung', caseSensitive: false);
  static final _positionWords = RegExp(r'position|höhe|hoehe|height|%|prozent', caseSensitive: false);
  static final _actualTemp = RegExp(
    r'ist|actual|aktuell|raumtemp|room temp|temperatur$|temperature$|messwert',
    caseSensitive: false,
  );
  static final _setpoint = RegExp(r'soll|setpoint|basis', caseSensitive: false);
  static final _shift = RegExp(r'verschieb|shift', caseSensitive: false);
  static final _valve = RegExp(r'stellgr|stellwert|ventil|valve|command value|heizen.*wert', caseSensitive: false);
  static final _brightness = RegExp(r'helligkeit|dimmwert|wert|brightness|value|%|prozent', caseSensitive: false);
  static final _statusWords = RegExp(
    r'rückmeld|rueckmeld|status|aktuell|actual|\bist\b|\brms?\b|feedback|\bstate\b|zustand|\bfb\b',
    caseSensitive: false,
  );
  static final _relativeDim = RegExp(r'relativ|relative|dimmen$|dimming$', caseSensitive: false);

  static bool _isMain(Dpt? d, int main, [int? sub]) => d != null && d.main == main && (sub == null || d.sub == sub);

  static String _name(ObjectGroup o) =>
      o.room == null || o.title.startsWith(o.room!) ? o.title : '${o.room} ${o.title}';

  /// Maps the members of an object to platforms. Remaining members (feedback, measurements) become
  /// sensors.
  static List<HaEntity> _fromObject(ObjectGroup o, GroupCatalog catalog, Set<int> used) {
    final out = <HaEntity>[];
    final name = _name(o);
    Dpt? dpt(ObjectMember m) => catalog[m.address]?.dpt;
    String text(ObjectMember m) => '${m.function} ${catalog[m.address]?.name ?? ''}';
    final free = [...o.members];

    /// First unused address that matches; further matches make the mapping uncertain.
    int? take(HaEntity e, String key, bool Function(ObjectMember) test) {
      final hits = free.where(test).toList();
      if (hits.isEmpty) return null;
      if (hits.length > 1) e.doubts.add(HaDoubt.ambiguous);
      final m = hits.first;
      free.remove(m);
      e.addresses[key] = m.address;
      if (dpt(m) == null) e.doubts.add(HaDoubt.noDpt);
      return m.address;
    }

    final allText = o.members.map(text).join(' ') + o.key;

    // Roller shutter/blind
    final looksCover =
        o.members.any((m) => _isMain(dpt(m), 1, 8) || _isMain(dpt(m), 1, 7) || _isMain(dpt(m), 1, 10)) ||
        _coverWords.hasMatch(allText);
    if (looksCover) {
      final e = HaEntity(HaPlatform.cover, name, room: o.room);
      take(
        e,
        'move_long_address',
        (m) =>
            !m.feedback &&
            (_isMain(dpt(m), 1, 8) || (dpt(m) == null || _isMain(dpt(m), 1)) && _coverWords.hasMatch(m.function)) &&
            !_shortWords.hasMatch(m.function),
      );
      take(
        e,
        'move_short_address',
        (m) => !m.feedback && (_isMain(dpt(m), 1, 7) || _isMain(dpt(m), 1) && _shortWords.hasMatch(m.function)),
      );
      take(
        e,
        'stop_address',
        (m) => !m.feedback && (_isMain(dpt(m), 1, 10) || _isMain(dpt(m), 1) && _stopWords.hasMatch(m.function)),
      );
      bool percent(ObjectMember m) => _isMain(dpt(m), 5, 1) || dpt(m) == null && _positionWords.hasMatch(m.function);
      take(e, 'angle_address', (m) => !m.feedback && percent(m) && _angleWords.hasMatch(m.function));
      take(e, 'angle_state_address', (m) => m.feedback && percent(m) && _angleWords.hasMatch(m.function));
      take(e, 'position_address', (m) => !m.feedback && percent(m));
      take(e, 'position_state_address', (m) => m.feedback && percent(m));
      if (e.addresses.containsKey('move_long_address') || e.addresses.containsKey('position_address')) {
        if (!e.addresses.containsKey('position_state_address')) e.doubts.add(HaDoubt.noState);
        out.add(e);
      } else {
        // Without a move command it is not a cover for Home Assistant: put it back.
        free
          ..clear()
          ..addAll(o.members);
      }
    }

    // Room temperature controller
    final hasActual = free.any(
      (m) => _isMain(dpt(m), 9, 1) && _actualTemp.hasMatch(m.function) && !_setpoint.hasMatch(m.function),
    );
    final hasSetpoint = free.any(
      (m) =>
          (_isMain(dpt(m), 9, 1) || dpt(m) == null) && _setpoint.hasMatch(m.function) && !_shift.hasMatch(m.function),
    );
    if (hasActual && hasSetpoint) {
      final e = HaEntity(HaPlatform.climate, name, room: o.room);
      take(
        e,
        'temperature_address',
        (m) => _isMain(dpt(m), 9, 1) && _actualTemp.hasMatch(m.function) && !_setpoint.hasMatch(m.function),
      );
      bool setpoint(ObjectMember m) =>
          (_isMain(dpt(m), 9, 1) || dpt(m) == null) && _setpoint.hasMatch(m.function) && !_shift.hasMatch(m.function);
      final state = take(e, 'target_temperature_state_address', (m) => m.feedback && setpoint(m));
      final command = take(e, 'target_temperature_address', (m) => !m.feedback && setpoint(m));
      if (state == null && command != null) {
        // Required key: without its own feedback Home Assistant reads the command.
        e.addresses['target_temperature_state_address'] = command;
        e.doubts.add(HaDoubt.targetFromCommand);
      }
      bool shift(ObjectMember m) => _shift.hasMatch(m.function) && (_isMain(dpt(m), 9) || _isMain(dpt(m), 6));
      final shiftCommand = free.where((m) => !m.feedback && shift(m)).firstOrNull;
      final shiftState = free.where((m) => m.feedback && shift(m)).firstOrNull;
      if (shiftCommand != null && shiftState != null) {
        // Both or neither (schema: Inclusive).
        free
          ..remove(shiftCommand)
          ..remove(shiftState);
        e.addresses['setpoint_shift_address'] = shiftCommand.address;
        e.addresses['setpoint_shift_state_address'] = shiftState.address;
        e.options['setpoint_shift_mode'] = _isMain(dpt(shiftCommand), 9) ? 'DPT9002' : 'DPT6010';
      }
      take(e, 'operation_mode_address', (m) => !m.feedback && _isMain(dpt(m), 20, 102));
      take(e, 'operation_mode_state_address', (m) => m.feedback && _isMain(dpt(m), 20, 102));
      take(e, 'controller_mode_address', (m) => !m.feedback && _isMain(dpt(m), 20, 105));
      take(e, 'controller_mode_state_address', (m) => m.feedback && _isMain(dpt(m), 20, 105));
      take(e, 'heat_cool_address', (m) => !m.feedback && _isMain(dpt(m), 1, 100));
      take(e, 'heat_cool_state_address', (m) => m.feedback && _isMain(dpt(m), 1, 100));
      take(e, 'command_value_state_address', (m) => _isMain(dpt(m), 5, 1) && _valve.hasMatch(m.function));
      out.add(e);
    }

    // Light or switch
    bool switching(ObjectMember m) =>
        _isMain(dpt(m), 1, 1) ||
        dpt(m) == null && RegExp(r'schalt|switch|ein/aus|an/aus|on/off', caseSensitive: false).hasMatch(m.function);
    bool brightness(ObjectMember m) =>
        (_isMain(dpt(m), 5, 1) || dpt(m) == null && _brightness.hasMatch(m.function)) &&
        !_relativeDim.hasMatch(m.function) &&
        !_valve.hasMatch(m.function);
    final hasSwitch = free.any((m) => !m.feedback && switching(m));
    // "Helligkeitswert" (brightness value) counts as a measurement in the object index; for lights
    // it matters whether the name explicitly says status.
    bool brightnessState(ObjectMember m) => _statusWords.hasMatch(m.function);
    final hasBrightness = free.any((m) => !brightnessState(m) && brightness(m));
    final isLight = hasBrightness && hasSwitch || _lightWords.hasMatch('${o.title} ${o.key} $allText');
    final isLoad = _loadWords.hasMatch('${o.title} ${o.key} $allText');
    if (hasSwitch || (hasBrightness && isLight)) {
      final light = isLight && !isLoad;
      final e = HaEntity(light ? HaPlatform.light : HaPlatform.switchPlatform, name, room: o.room);
      take(e, 'address', (m) => !m.feedback && switching(m));
      take(e, 'state_address', (m) => m.feedback && switching(m));
      if (light) {
        take(e, 'brightness_address', (m) => !brightnessState(m) && brightness(m));
        take(e, 'brightness_state_address', (m) => brightnessState(m) && brightness(m));
      }
      if (!light && !isLoad) e.doubts.add(HaDoubt.lightOrSwitch);
      if (!e.addresses.containsKey('address')) {
        // Brightness only: HA requires `address` – show it, but do not activate it.
        e.doubts.add(HaDoubt.noSwitch);
      } else if (!e.addresses.containsKey('state_address')) {
        e.doubts.add(HaDoubt.noState);
      }
      if (e.addresses.isNotEmpty) out.add(e);
    }

    // Remaining feedback and measurements (commands stay out).
    for (final m in free.toList()) {
      final g = catalog[m.address];
      if (g == null || !m.feedback) continue;
      if (used.contains(m.address) || out.any((e) => e.groups.contains(m.address))) continue;
      final function = m.function == o.key ? g.name : m.function;
      final e = _single(g, catalog, room: o.room, name: '$name $function'.trim(), feedback: m.feedback);
      if (e != null) out.add(e);
    }
    for (final e in out) {
      used.addAll(e.groups);
      e
        ..objectKey = o.key
        ..objectName = name;
    }
    return out;
  }

  /// Single address as sensor or binary sensor – only notifications and measurements, no commands
  /// (those belong in an object).
  static HaEntity? _single(GroupInfo g, GroupCatalog catalog, {String? room, String? name, bool? feedback}) {
    final d = g.dpt;
    if (d == null) return null;
    final isFeedback = feedback ?? ObjectIndex.isFeedbackName(g.name);
    // If a device sends on this address and none listens to it (sensor), it is a notification.
    final sentByDevice = g.links.any((l) => l.sends) && g.links.every((l) => l.sends);
    final title = name ?? g.name;
    if (d.main == 1) {
      if (!isFeedback && !sentByDevice) return null;
      final e = HaEntity(HaPlatform.binarySensor, title, room: room);
      e.addresses['state_address'] = g.address;
      final cls = _binaryClass('$title ${g.path ?? ''}');
      if (cls != null) e.options['device_class'] = cls;
      return e;
    }
    final type = sensorType(d);
    if (type == null) return null;
    // Measurements (9, 12–14) always; 1-byte/2-byte values only as feedback.
    final measurement = const {9, 12, 13, 14}.contains(d.main);
    if (!measurement && !isFeedback && !sentByDevice) return null;
    final e = HaEntity(HaPlatform.sensor, title, room: room);
    e.addresses['state_address'] = g.address;
    e.options['type'] = type;
    if (d.sub == null) e.doubts.add(HaDoubt.typeGuessed);
    return e;
  }

  static String? _binaryClass(String text) {
    final t = text.toLowerCase();
    if (RegExp(r'fenster|window|kipp|reed').hasMatch(t)) return 'window';
    if (RegExp(r'tür|tuer|door|tor\b|garage').hasMatch(t)) return 'door';
    if (RegExp(r'präsenz|praesenz|presence|anwesen|occupan').hasMatch(t)) return 'occupancy';
    if (RegExp(r'bewegung|motion|pir').hasMatch(t)) return 'motion';
    if (RegExp(r'rauch|smoke').hasMatch(t)) return 'smoke';
    if (RegExp(r'wasser|leck|leak|moisture|feuchte.*alarm').hasMatch(t)) return 'moisture';
    return null;
  }

  /// Values for `type` according to xknx (names Home Assistant documents); otherwise the DPT number
  /// as text, which HA also accepts ("9.001").
  static const _types = <String, String>{
    '5.001': 'percent',
    '5.003': 'angle',
    '5.004': 'percentU8',
    '5.010': 'pulse',
    '6.001': 'percentV8',
    '6.010': 'counter_pulses',
    '7.001': 'pulse_2byte',
    '7.012': 'current',
    '7.013': 'brightness',
    '7.600': 'color_temperature',
    '8.001': 'pulse_2byte_signed',
    '9.001': 'temperature',
    '9.002': 'temperature_difference_2byte',
    '9.004': 'illuminance',
    '9.005': 'wind_speed_ms',
    '9.006': 'pressure_2byte',
    '9.007': 'humidity',
    '9.008': 'ppm',
    '9.020': 'voltage',
    '9.021': 'curr',
    '9.024': 'power_2byte',
    '9.025': 'volume_flow',
    '9.026': 'rain_amount',
    '9.028': 'wind_speed_kmh',
    '12.001': 'pulse_4_ucount',
    '13.001': 'pulse_4byte',
    '13.010': 'active_energy',
    '13.013': 'active_energy_kwh',
    '14.031': 'energy',
    '14.056': 'power',
    '14.076': 'volume',
    '16.000': 'string',
    '16.001': 'latin_1',
    '17.001': 'scene_number',
  };

  /// Generic types when only the main type is known.
  static const _mainTypes = <int, String>{
    5: '1byte_unsigned',
    6: '1byte_signed',
    7: '2byte_unsigned',
    8: '2byte_signed',
    9: '2byte_float',
    12: '4byte_unsigned',
    13: '4byte_signed',
  };

  /// Sensor `type` for [d]; `null` for types without a sensor (DPT 1, 3, 20 …).
  static String? sensorType(Dpt d) {
    const sensorMains = {5, 6, 7, 8, 9, 12, 13, 14, 16, 17};
    if (!sensorMains.contains(d.main)) return null;
    if (d.sub == null) return _mainTypes[d.main] ?? '${d.main}';
    return _types['$d'] ?? '$d';
  }

  // --- Devices ------------------------------------------------------------------

  /// Suggestions for `device:` – entities that recognisably belong together. Only suggestions: a
  /// device goes into the file only when the user accepts it.
  ///
  /// First, objects from the naming scheme with several entities (light with presence, controller
  /// with window contact). Remaining sensors are grouped by the ETS device that sends their values
  /// (weather station, presence detector) – but not actuators, since a switch actuator serves
  /// lights in many rooms.
  static List<HaDevice> devices(List<HaEntity> entities, GroupCatalog catalog) {
    final out = <HaDevice>[];
    final ids = <String>{};
    String unique(String base) {
      var id = base.isEmpty ? 'knx_device' : base;
      for (var n = 2; !ids.add(id); n++) {
        id = '${base}_$n';
      }
      return id;
    }

    final taken = <String>{};
    final byObject = <String, List<HaEntity>>{};
    for (final e in entities) {
      if (e.objectKey != null) (byObject[e.objectKey!] ??= []).add(e);
    }
    for (final MapEntry(key: key, value: list) in byObject.entries) {
      if (list.length < 2) continue;
      out.add(
        HaDevice(
          unique(slug(key)),
          list.first.objectName ?? key,
          source: HaDeviceSource.nameScheme,
          room: _commonRoom(list),
          entities: [for (final e in list) e.id],
        ),
      );
      taken.addAll(list.map((e) => e.id));
    }

    final bySender = <int, List<HaEntity>>{};
    for (final e in entities) {
      if (taken.contains(e.id)) continue;
      if (e.platform != HaPlatform.sensor && e.platform != HaPlatform.binarySensor) continue;
      final senders = {
        for (final a in e.groups)
          for (final l in catalog[a]?.links ?? const <GroupLink>[])
            if (l.sends) l.device,
      };
      if (senders.length != 1) continue;
      final device = catalog.devices[senders.single];
      if (device == null || device.isTunnel) continue;
      (bySender[device.address] ??= []).add(e);
    }
    for (final MapEntry(key: address, value: list) in bySender.entries) {
      if (list.length < 2) continue;
      final device = catalog.devices[address]!;
      out.add(
        HaDevice(
          unique('knx_${formatIndividual(address).replaceAll('.', '_')}'),
          device.name,
          source: HaDeviceSource.busDevice,
          busAddress: address,
          room: _commonRoom(list),
          entities: [for (final e in list) e.id],
        ),
      );
    }
    out.sort((a, b) {
      final r = (a.room ?? '\u{FFFF}').compareTo(b.room ?? '\u{FFFF}');
      return r != 0 ? r : a.name.compareTo(b.name);
    });
    return out;
  }

  static String? _commonRoom(List<HaEntity> list) {
    final rooms = {for (final e in list) e.room};
    return rooms.length == 1 ? rooms.single : null;
  }

  /// Identifier for `device.id`: lowercase letters, digits and `_`.
  static String slug(String text) {
    const umlauts = {'ä': 'ae', 'ö': 'oe', 'ü': 'ue', 'ß': 'ss'};
    final lower = text.toLowerCase().split('').map((c) => umlauts[c] ?? c).join();
    return lower.replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  }

  // --- YAML --------------------------------------------------------------------

  /// Content for `knx.yaml`, included with `knx: !include knx.yaml`. Uncertain entities carry a
  /// "Prüfen: …" (check) comment.
  static String toYaml(
    List<HaEntity> entities, {
    required GroupCatalog catalog,
    String? appVersion,
    DateTime? created,
    Iterable<HaDevice> devices = const [],
  }) {
    final deviceOf = {
      for (final d in devices)
        for (final id in d.entities) id: d,
    };
    final b = StringBuffer();
    final when = created ?? DateTime.now();
    b.writeln('# ${s.haYamlHeader(appVersion ?? '', catalog.projectName ?? '-', formatDate(when))}');
    b.writeln('# ${s.haYamlInclude}');
    b.writeln('# ${s.haYamlSchema}');
    if (entities.any((e) => deviceOf.containsKey(e.id))) b.writeln('# ${s.haYamlDevices}');
    for (final p in HaPlatform.values) {
      final list = entities.where((e) => e.platform == p).toList();
      if (list.isEmpty) continue;
      b.writeln();
      // Only commented-out entries: comment out the key too, otherwise it stands empty.
      b.writeln('${list.every((e) => e.incomplete) ? '# ' : ''}${p.key}:');
      for (final e in list) {
        if (e.uncertain) {
          b.writeln('  # ${s.haYamlCheck(e.doubts.map((d) => d.text).join(' · '))}');
        }
        // Incomplete: commented out so Home Assistant accepts the file.
        final off = e.incomplete ? '# ' : '';
        b.writeln('  $off- name: ${_quote(e.name)}');
        for (final MapEntry(:key, :value) in e.addresses.entries) {
          final info = catalog[value];
          final comment = info == null
              ? ''
              : '  # ${_comment(info.name)}${info.dpt == null ? '' : ' · DPT ${info.dpt}'}';
          b.writeln('  $off  $key: ${_quote(formatGroup(value))}$comment');
        }
        for (final MapEntry(:key, :value) in e.options.entries) {
          b.writeln('  $off  $key: ${value is String ? _quote(value) : value}');
        }
        final device = deviceOf[e.id];
        if (device != null) {
          b.writeln('  $off  device:');
          b.writeln('  $off    id: ${_quote(device.id)}');
          b.writeln('  $off    name: ${_quote(device.name)}');
        }
      }
    }
    return b.toString();
  }

  /// Double quotes with escapes (YAML 1.2, like JSON).
  static String _quote(String v) =>
      '"${v.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', ' ').replaceAll('\t', ' ')}"';

  /// Comments must not contain a line break.
  static String _comment(String v) => v.replaceAll(RegExp(r'[\r\n]+'), ' ');
}
