import '../knx/group_catalog.dart';

/// A function of an object, e.g. "Auf/Ab fahren" (move up/down) of "EG FL F01".
class ObjectMember {
  const ObjectMember(this.address, this.function, {required this.feedback});

  final int address;

  /// Name part after the object, e.g. "Aktuelle Position" (current position).
  final String function;

  /// Whether it is a status feedback rather than a command.
  final bool feedback;
}

/// Group addresses belonging to one object (window, light, room …).
class ObjectGroup {
  ObjectGroup(this.key, {required this.room, required this.title});

  /// Common name prefix, e.g. "EG FL F01".
  final String key;

  /// Room for the structure, e.g. "EG FL"; `null` without a recognizable room.
  final String? room;

  /// Display name (element abbreviation or the rest after the room), e.g. "F01".
  final String title;
  final members = <ObjectMember>[];

  List<ObjectMember> get commands => [
    for (final m in members)
      if (!m.feedback) m,
  ];
  List<ObjectMember> get feedbacks => [
    for (final m in members)
      if (m.feedback) m,
  ];
}

/// Derives objects from the group address names.
///
/// There is no fixed KNX naming scheme; the common ones are recognized without
/// being imposed:
/// 1. Element abbreviation (letters + digits, e.g. F01, L02, DK01, HT01):
///    everything up to and including the abbreviation is the object ("EG FL F01 Auf/Ab fahren").
/// 2. Otherwise the function is split off – function words at the end or at the
///    start ("… Licht schalten", "Status Steckdose Garten", "…_RM"); with
///    separators ("OG – Diele – Sollwert", "EG_KUE_LI_Decke_SW") the last
///    section. The rest is the object.
/// 3. Equal names with the function only in the middle group
///    ("Schalten › Küche Decke", "Rückmeldung › Küche Decke"): function from the path.
/// 4. Equal names in several rooms ("Wohnen › Licht schalten"): the path
///    distinguishes the objects.
class ObjectIndex {
  ObjectIndex._(this.objects, this._byAddress);

  factory ObjectIndex.of(GroupCatalog catalog) {
    final groups = catalog.groups.values.toList()..sort((a, b) => a.address.compareTo(b.address));
    final names = {for (final g in groups) g.address: _Name.parse(g.name)};

    // Frequent first words = floors (EG, OG, DG …), if short and in uppercase.
    final firstCounts = <String, int>{};
    for (final n in names.values) {
      if (n.tokens.isNotEmpty) firstCounts[n.tokens.first] = (firstCounts[n.tokens.first] ?? 0) + 1;
    }
    bool isLevel(String token) => _levelCode.hasMatch(token) && (firstCounts[token] ?? 0) >= 3;

    final objects = <String, ObjectGroup>{};
    final byAddress = <int, ObjectGroup>{};
    void put(int address, String key, String function, {String? room, required String title}) {
      final group = objects.putIfAbsent(key, () => ObjectGroup(key, room: room, title: title));
      group.members.add(ObjectMember(address, function.isEmpty ? key : function, feedback: _isFeedback(function)));
      byAddress[address] = group;
    }

    // Room numbers: prefixes followed by an element abbreviation ("OG K1" in "OG K1 L01 …").
    // "OG K1 Ist-Temperatur" is then room K1, not element K1.
    final roomPrefixes = <String>{};
    for (final g in groups) {
      final t = names[g.address]!.words;
      final e = t.indexWhere(_elementCode.hasMatch);
      if (e > 0 && e + 2 < t.length && _elementCode.hasMatch(t[e + 1])) roomPrefixes.add(t.take(e + 1).join(' '));
    }

    // 1. Element abbreviation – unchanged from earlier versions.
    final rest = <GroupInfo>[];
    for (final g in groups) {
      final t = names[g.address]!.words;
      var element = t.indexWhere(_elementCode.hasMatch);
      // "OG K1 L01 Schalten": K1 is the room number, the element is the last abbreviation in the sequence.
      while (element > 0 && element + 2 < t.length && _elementCode.hasMatch(t[element + 1])) {
        element++;
      }
      if (t.length >= 2 &&
          element > 0 &&
          element < t.length - 1 &&
          !roomPrefixes.contains(t.take(element + 1).join(' '))) {
        final level = isLevel(t[0]);
        final roomCode = _roomCode.hasMatch(t[1]) || _elementCode.hasMatch(t[1]);
        final roomLength = !level ? 0 : (t.length >= 3 && roomCode && element != 1 ? 2 : 1);
        put(
          g.address,
          t.take(element + 1).join(' '),
          t.skip(element + 1).join(' '),
          room: roomLength == 0 ? null : t.take(roomLength).join(' '),
          title: t.sublist(roomLength, element + 1).join(' '),
        );
      } else {
        rest.add(g);
      }
    }

    // 2. Split off the function.
    final split = {for (final g in rest) g.address: names[g.address]!.splitFunction()};
    String? pathLast(GroupInfo g) => g.path?.split(' › ').last.trim();

    // 3./4. Equal object names: function or room from the path.
    final byKey = <String, List<GroupInfo>>{};
    for (final g in rest) {
      final key = split[g.address]!.key.join(' ').toLowerCase();
      if (key.isNotEmpty) (byKey[key] ??= []).add(g);
    }
    for (final members in byKey.values) {
      final paths = {for (final g in members) g.path};
      final functions = [
        for (final g in members)
          if (split[g.address]!.function.isNotEmpty) split[g.address]!.function.toLowerCase(),
      ];
      // The same function in different paths = different objects (rooms).
      final perRoom = paths.length > 1 && functions.toSet().length < functions.length;
      for (final g in members) {
        final n = split[g.address]!;
        final where = pathLast(g);
        if (perRoom && where != null) {
          put(g.address, '$where › ${n.key.join(' ')}', n.function, room: where, title: n.key.join(' '));
          continue;
        }
        final (:room, :title) = _roomAndTitle(n, isLevel, fallbackRoom: _roomLike(where) ? where : null);
        // Only the name without a function: the function is in the middle group.
        final function = n.function.isEmpty && where != null && paths.length > 1 ? where : n.function;
        put(g.address, n.key.join(' '), function, room: room, title: title);
      }
    }

    // 5. Assign single addresses to the next shorter object
    // ("EG FL Licht An/Aus" → "EG FL", "EG WZ (EZ) Ventil-Zustand" → "EG WZ").
    for (final o in [...objects.values]) {
      if (o.members.length != 1) continue;
      final m = o.members.single;
      final words = o.key.split(' ');
      for (var n = words.length - 1; n >= 1; n--) {
        final parent = objects[words.take(n).join(' ')];
        if (parent == null || parent.members.length < 2) continue;
        objects.remove(o.key);
        final function = [...words.skip(n), if (m.function != o.key) m.function].join(' ');
        parent.members.add(ObjectMember(m.address, function, feedback: _isFeedback(function)));
        byAddress[m.address] = parent;
        break;
      }
    }

    // 6. Remaining single addresses: series with the same first two words
    // ("Rollladen EG …", "Fahrzeitmessung starten …").
    final single = [
      for (final o in objects.values)
        if (o.members.length == 1) o.members.single.address,
    ];
    objects.removeWhere((_, o) => o.members.length < 2);
    byAddress.removeWhere((_, o) => o.members.length < 2);
    final series = <String, List<int>>{};
    for (final a in single) {
      final t = names[a]!.words;
      if (t.length >= 3) (series['${t[0]} ${t[1]}'] ??= []).add(a);
    }
    for (final MapEntry(key: key, value: addresses) in series.entries) {
      if (addresses.length < 2 || objects.containsKey(key)) continue;
      for (final a in addresses) {
        put(a, key, names[a]!.words.skip(2).join(' '), title: key);
      }
    }
    return ObjectIndex._(objects.values.toList(), byAddress);
  }

  /// Room and display name of an object: the room comes before the first trade
  /// word ("EG Flur | Licht"), with sections all but the last
  /// ("OG – Treppenaufgang | Deckenlicht"), otherwise floor + room.
  static ({String? room, String title}) _roomAndTitle(_Split n, bool Function(String) isLevel, {String? fallbackRoom}) {
    final key = n.key;
    // A trade at the front ("Licht EG Küche Decke") belongs to the title.
    final lead = key.takeWhile(_isTrade).toList();
    final rem = key.skip(lead.length).toList();
    String join(Iterable<String> t) => t.join(' ');
    final trade = rem.indexWhere(_isTrade);
    if (trade > 0) return (room: join(rem.take(trade)), title: join([...lead, ...rem.skip(trade)]));
    if (n.keySegments >= 3) {
      final last = n.lastKeySegment;
      return (room: join(rem.take(rem.length - last)), title: join([...lead, ...rem.skip(rem.length - last)]));
    }
    if (rem.isNotEmpty && isLevel(rem.first)) {
      final room = join(rem.take(2));
      final title = join([...lead, ...rem.skip(2)]);
      return (room: room, title: title.isEmpty ? room : title);
    }
    if (rem.length >= 2) return (room: join(rem.take(rem.length - 1)), title: join([...lead, rem.last]));
    return (room: fallbackRoom, title: join(key));
  }

  /// Middle group as the room, unless it is named after a function or trade.
  static bool _roomLike(String? name) =>
      name != null &&
      !name.split(RegExp(r'[\s&/,-]+')).any((w) => _isTrade(w) || _isFunction(w.toLowerCase())) &&
      !RegExp(r'zentral|global|sonstig|allgemein|central|general|misc', caseSensitive: false).hasMatch(name);

  /// Floor abbreviations: EG, OG, OG2, DG, UG, KG, SP …, English GF, FF, 1F, L2.
  static final _levelCode = RegExp(r'^([A-ZÄÖÜ]{1,3}\d?|\d[A-Z]{1,2})$');

  /// Room abbreviations: FL, WC, KÜ, WZ/KÜ …
  static final _roomCode = RegExp(r'^[A-ZÄÖÜ][A-ZÄÖÜ/]{0,7}$');

  /// Element abbreviations: F01, L02, DK01, DF01, HT01, T01 …
  static final _elementCode = RegExp(r'^[A-ZÄÖÜ]{1,3}\d{1,3}$');

  /// Trades and devices (German, English, common abbreviations).
  static final _trade = RegExp(
    r'^(licht|.*licht|beleuchtung|leuchte.*|.*leuchte|lampe|spots?|led|li|bel|'
    r'rollladen|rolladen|rollo|jalousie|jal|raffstore?|markise|beschattung|behang|rl|rol|'
    r'fenster|.*fenster|fensterkontakte?|tür|tuer|tor|.*tor|reed|kontakte?|'
    r'heizung|hzg|hz|fbh|fussbodenheizung|fußbodenheizung|thermostat|klima|lüftung|lueftung|kwl|'
    r'steckdosen?|.*-steckdosen?|sd|'
    // English
    r'.*lights?|lighting|lamps?|pendant|chandelier|dimmer|blinds?|shutters?|shades?|curtains?|awning|'
    r'screens?|windows?|doors?|gate|garage|heating|radiators?|ufh|hvac|fan|ventilation|sockets?|'
    r'outlets?|plugs?)$',
    caseSensitive: false,
  );
  static bool _isTrade(String token) => _trade.hasMatch(_Name.bare(token));

  /// Words that denote a function – command or status feedback.
  static const _functionWords = {
    // Switching/dimming
    'schalten', 'schalte', 'ein', 'aus', 'an', 'ein/aus', 'an/aus', 'ein-/ausschalten', 'sw', 's',
    'switch', 'on', 'off', 'on/off', 'toggle', 'dimmen', 'dimming', 'dim', 'relativ', 'absolut',
    'dimmwert', 'helligkeitswert', 'wert', 'value', 'val', 'prozent', 'percent',
    // Blinds
    'auf/ab', 'auf-/ab', 'auf-/abfahren', 'auf/abfahren', 'fahren', 'abfahren', 'auffahren', 'aufab',
    'up/down', 'updown', 'stopp', 'stop', 'stopp/lamelle', 'lamelle', 'lamellen', 'step', 'slat',
    'position', 'pos', 'höhe', 'hoehe', 'anfahren', 'move', 'anhalten', 'halt', '%',
    // General
    'sperre', 'sperren', 'lock', 'freigabe', 'enable', 'szene', 'scene', 'modus', 'mode',
    'betriebsart', 'betriebsmodus', 'stellgröße', 'stellwert', 'heizen', 'kühlen', 'farbe', 'color',
    'colour', 'rgb', 'rgbw', 'hsv', 'farbtemperatur', 'kelvin', 'tw', 'zwangsführung', 'automatik',
    'auto', 'manuell', 'setpoint', 'messwert', 'basis-komfort', 'komfort', 'basis', 'nacht',
    'frostschutz', 'eco', 'standby', 'comfort', 'präsenz', 'anwesenheit', 'bewegung',
    // Status feedback
    'status', 'stat', 'rm', 'rms', 'rückmeldung', 'rueckmeldung', 'zustand', 'state', 'feedback', 'fb',
    'ist', 'istwert', 'actual', 'current', 'aktuell', 'aktuelle', 'aktueller', 'aktuellen',
    'geöffnet', 'gekippt', 'geschlossen', 'offen', 'kipp', 'auf/zu', 'open', 'closed', 'verfahrstatus',
    'opened', 'tilted', 'measured', 'brightness', 'angle', 'height', 'tilt', 'block', 'blocking',
    'presence', 'motion', 'occupancy', 'humidity', 'valve', 'heat', 'cool', 'stop/step', 'dimvalue',
    // Measured values and counters
    'verbrauch', 'leistung', 'energie', 'zähler', 'zaehler', 'betriebsstunden', 'betriesstunden',
    'power', 'energy', 'consumption',
  };

  static final _functionPrefix = RegExp(
    r'^(ist[-a-zäöü]{2,}|soll[-a-zäöü]*|rückmeld.*|rueckmeld.*|status.*|dimm.*|schalt.*|'
    r'temperatur.*|temperature.*|helligkeit.*|.*messwert|sollwert.*|setpoint.*|.+-(zustand|status|wert))$',
  );

  static bool _isFunction(String bare) => _functionWords.contains(bare) || _functionPrefix.hasMatch(bare);

  static final _feedbackWords = RegExp(
    r'rückmeld|rücmled|rueckmeld|status|aktuell|\bist\b|ist-|isttemp|istwert|zustand|feedback|\bstate\b|'
    r'actual|current|\brms?\b|\bfb\b|\bstat\b|messwert|verfahrstatus|geöffnet|gekippt|\bkipp|'
    r'geschlossen|offen|präsenz|helligkeit|temperatur(?!.*soll)|'
    r'\bopened\b|\btilted\b|\bclosed\b|occupan|presence|motion|humidity|\bmeasured\b|'
    // Measured and reported, never commanded: humidity in German, results of a test.
    r'feuchte|feuchtigkeit|ergebnis|\bresults?\b',
    caseSensitive: false,
  );

  static final _setpoint = RegExp(r'soll|setpoint', caseSensitive: false);
  static final _actual = RegExp(r'aktuell|actual|\bist\b|ist-|status|rückmeld|rueckmeld|\brm\b', caseSensitive: false);

  /// Setpoints are commands – except as status feedback ("Aktueller Sollwert").
  /// Name sounds like status feedback ("… Rückmeldung", "Status …", "Ist-Temperatur").
  static bool isFeedbackName(String name) => _isFeedback(name);

  static bool _isFeedback(String function) =>
      _feedbackWords.hasMatch(function) && !(_setpoint.hasMatch(function) && !_actual.hasMatch(function));

  final List<ObjectGroup> objects;
  final Map<int, ObjectGroup> _byAddress;

  ObjectGroup? objectOf(int address) => _byAddress[address];

  static GroupCatalog? _cachedFor;
  static ObjectIndex? _cached;

  /// Index for the current catalog (cached).
  static ObjectIndex forCatalog(GroupCatalog catalog) {
    if (!identical(catalog, _cachedFor)) {
      _cached = ObjectIndex.of(catalog);
      _cachedFor = catalog;
    }
    return _cached!;
  }
}

/// A group address name in words, with sections at separators
/// ("OG – Diele – Sollwert", "EG_KUE_LI_Decke", "EG.BAD.HZG").
class _Name {
  _Name(this.words, this.segments);

  /// Words as in the name (space-separated, for element abbreviations).
  final List<String> words;

  /// Sections, each with its words without separators.
  final List<List<String>> segments;

  List<String> get tokens => [for (final s in segments) ...s];

  static final _spacedSeparator = RegExp(r'\s+[-–—|:]\s+');

  factory _Name.parse(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    List<String> wordsOf(String s) => s.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    var parts = name.split(_spacedSeparator);
    // Without spaces: underscore or dot as separator ("EG_KUE_LI_Decke_SW").
    if (parts.length == 1 && !name.trim().contains(' ')) parts = name.split(RegExp(r'[_.]'));
    return _Name(words, [for (final p in parts) wordsOf(p)].where((s) => s.isNotEmpty).toList());
  }

  /// Word without punctuation, lowercase: "(Dimmen)" → "dimmen".
  static String bare(String token) => token.toLowerCase().replaceAll(RegExp(r'^[(\[\"„]+|[)\]\"“:,]+$'), '');

  /// Splits off function words at the front and back; with three or more
  /// sections, the last one is always the function.
  _Split splitFunction() {
    final segs = [for (final s in segments) List.of(s)];
    final tail = <String>[];
    final head = <String>[];
    if (segs.length >= 3) tail.insertAll(0, segs.removeLast());
    var key = [for (final s in segs) ...s];
    while (key.length > 1 && ObjectIndex._isFunction(bare(key.last))) {
      tail.insert(0, key.removeLast());
    }
    while (key.length > 1 && ObjectIndex._isFunction(bare(key.first))) {
      head.add(key.removeAt(0));
    }
    // Count the sections of the object name (for room/title).
    var remaining = key.length;
    var keySegments = 0;
    var last = 0;
    for (final s in segs) {
      if (remaining <= 0) break;
      final n = s.length < remaining ? s.length : remaining;
      keySegments++;
      last = n;
      remaining -= n;
    }
    return _Split(key, [...head, ...tail].join(' '), keySegments: keySegments, lastKeySegment: last);
  }
}

/// Object name and function of a group address name.
class _Split {
  _Split(this.key, this.function, {required this.keySegments, required this.lastKeySegment});

  final List<String> key;
  final String function;

  /// Number of sections of the object name and words in the last one.
  final int keySegments;
  final int lastKeySegment;
}
