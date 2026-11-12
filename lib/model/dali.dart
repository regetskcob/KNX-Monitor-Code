import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../catalog_store.dart';
import '../knx/dali.dart';
import '../knx/dali_text.dart';
import '../knx/demo_tunnel.dart';
import '../knx/group_catalog.dart';
import '../knx/knx_tunnel.dart';
import '../knx/read_sweep.dart';
import '../knx/shared_tunnel.dart';
import '../knx/telegram.dart';
import '../platform/addon.dart';
import '../platform/storage.dart';
import 'box_keyring_consent.dart';
import 'dali_demo.dart';
import 'dali_labels.dart';
import 'dali_project.dart';
import 'installation.dart';

export '../knx/dali.dart';
export 'dali_project.dart';

/// State of a luminaire or group as the views show it; the worst wins. [testFailed]: no fault
/// reported, but the last emergency test of the luminaire failed (see [DaliStore.overall]).
enum DaliState { unknown, ok, testFailed, lampFault, converterFault, gearFault }

/// State for a set of [DaliFault] bits; `null` = nothing reported yet.
DaliState daliStateOf(int? faults) {
  if (faults == null) return DaliState.unknown;
  if (faults & DaliFault.gear != 0) return DaliState.gearFault;
  if (faults & DaliFault.converter != 0) return DaliState.converterFault;
  if (faults & DaliFault.lamp != 0) return DaliState.lampFault;
  return DaliState.ok;
}

/// A change of the reported faults of a luminaire or group.
typedef DaliEvent = ({DateTime time, int faults});

/// What a luminaire or a group share: reported faults and when they changed.
abstract class DaliTarget {
  DaliTarget(this.gateway);

  /// Individual address of the gateway.
  final int gateway;

  /// Name entered in the app.
  String? name;

  /// Reported [DaliFault] bits; `null` until the gateway reports.
  int? faults;

  /// Since when [faults] has its value.
  DateTime? since;

  /// Last report, changed or not.
  DateTime? lastReport;

  /// The last changes, oldest first (at most [DaliStore.keepEvents]).
  final events = <DaliEvent>[];

  DaliState get state => daliStateOf(faults);
  bool get faulty => (faults ?? 0) != 0;

  Map<String, Object?> _stateJson() => {
    'f': ?faults,
    'since': ?since?.millisecondsSinceEpoch,
    't': ?lastReport?.millisecondsSinceEpoch,
    if (events.isNotEmpty)
      'h': [
        for (final e in events) [e.time.millisecondsSinceEpoch, e.faults],
      ],
  };

  /// Takes the runtime state of [j] (from `dali_state.json`, or an older `dali.json`); keys that
  /// are missing leave the value as it is.
  void _readState(Map<Object?, Object?> j) {
    if (j.containsKey('f')) faults = _int(j['f'], max: 7);
    if (j.containsKey('since')) since = _time(j['since']);
    if (j.containsKey('t')) lastReport = _time(j['t']);
    if (j['h'] case final List<Object?> h) {
      events.clear();
      for (final e in h.take(DaliStore.keepEvents)) {
        if (e case [final int t, final int f] when f >= 0 && f <= 7) {
          if (_time(t) case final time?) events.add((time: time, faults: f));
        }
      }
    }
  }
}

/// A luminaire (control gear) behind a gateway.
class DaliGear extends DaliTarget {
  DaliGear(super.gateway, {this.address, this.anchor}) : assert(address != null || anchor != null);

  /// DALI short address 0 to 63; `null` for an emergency converter whose objects do not tell it.
  final int? address;

  /// Group address that identifies a converter without [address].
  final int? anchor;

  /// Room entered in the app.
  String? room;

  /// DALI groups entered in the app (the gateway does not report them on KNX).
  Set<int> groups = {};

  /// Marked as emergency luminaire by hand; `null` = as detected.
  bool? emergencyByHand;

  /// Emergency luminaire according to its objects or reports.
  bool emergencyDetected = false;

  /// Group addresses of the converter status (DPT 244.600) and test result (DPT 245.600).
  int? statusGroup;
  int? resultGroup;

  /// Last converter mode reported.
  ConverterMode? mode;

  /// Burn hours, where a gateway reports them.
  int? burnHours;

  bool get emergency => emergencyByHand ?? emergencyDetected;

  String get id => address != null ? '$gateway:$address' : '$gateway:ga$anchor';

  Map<String, Object?> _key() => {'gw': gateway, 'a': ?address, if (address == null) 'ga': ?anchor};

  /// What was entered in the app and what the project says (`dali.json`, shared with the server).
  Map<String, Object?> toSetupJson() => {
    ..._key(),
    'n': ?name,
    'r': ?room,
    if (groups.isNotEmpty) 'g': groups.toList()..sort(),
    'em': ?emergencyByHand,
    if (emergencyDetected) 'emd': true,
    'st': ?statusGroup,
    'res': ?resultGroup,
  };

  /// What the bus reported (`dali_state.json`, local).
  Map<String, Object?> toStateJson() => {..._key(), ..._stateJson(), 'mode': ?mode?.name, 'hours': ?burnHours};

  Map<String, Object?> toJson() => {...toSetupJson(), ...toStateJson()};

  /// Identity of an entry: gateway and address (or anchor); `null` if it is not one.
  static (int, int?, int?)? keyOf(Object? json) {
    if (json is! Map) return null;
    final gateway = _int(json['gw'], max: 0xFFFF);
    final address = _int(json['a'], max: 63);
    final anchor = _int(json['ga'], max: 0xFFFF);
    if (gateway == null || (address == null && anchor == null)) return null;
    return (gateway, address, address == null ? anchor : null);
  }

  static DaliGear? fromJson(Object? json) {
    final key = keyOf(json);
    if (key == null) return null;
    final (gateway, address, anchor) = key;
    return DaliGear(gateway, address: address, anchor: anchor)..read(json! as Map);
  }

  /// Takes what [json] holds; keys that are missing leave the value as it is.
  void read(Map<Object?, Object?> json) {
    _readState(json);
    if (json.containsKey('n')) name = _text(json['n']);
    if (json.containsKey('r')) room = _text(json['r']);
    if (json.containsKey('em')) emergencyByHand = json['em'] is bool ? json['em'] as bool : null;
    if (json['emd'] == true) emergencyDetected = true;
    if (json.containsKey('st')) statusGroup = _int(json['st'], max: 0xFFFF);
    if (json.containsKey('res')) resultGroup = _int(json['res'], max: 0xFFFF);
    if (json.containsKey('mode')) mode = ConverterMode.values.asNameMap()[json['mode']];
    if (json.containsKey('hours')) burnHours = _int(json['hours'], max: 1 << 31);
    if (json['g'] case final List<Object?> g) {
      groups = {for (final n in g.take(16)) ?_int(n, max: 15)};
    }
  }
}

/// A DALI group of a gateway.
class DaliGroup extends DaliTarget {
  DaliGroup(super.gateway, this.group);

  /// DALI group 0 to 15.
  final int group;

  /// Group addresses from the project: switch, relative dimming, value, and the states.
  int? switchGroup;
  int? dimGroup;
  int? valueGroup;
  int? statusGroup;
  int? valueStatusGroup;

  String get id => '$gateway:g$group';

  Map<String, Object?> toSetupJson() => {'gw': gateway, 'g': group, 'n': ?name};
  Map<String, Object?> toStateJson() => {'gw': gateway, 'g': group, ..._stateJson()};
  Map<String, Object?> toJson() => {...toSetupJson(), ...toStateJson()};

  static DaliGroup? fromJson(Object? json) {
    if (json is! Map) return null;
    final gateway = _int(json['gw'], max: 0xFFFF);
    final group = _int(json['g'], max: 15);
    if (gateway == null || group == null) return null;
    return DaliGroup(gateway, group)..read(json);
  }

  void read(Map<Object?, Object?> json) {
    _readState(json);
    if (json.containsKey('n')) name = _text(json['n']);
  }
}

/// A KNX-DALI gateway.
class DaliGateway {
  DaliGateway(this.address);

  /// Individual address.
  final int address;

  /// Name entered in the app.
  String? name;

  /// Name and location from the project.
  String? projectName;
  String? location;

  /// Profile from the project's manufacturer and product.
  DaliProfile? profile;

  /// In the project (otherwise found while listening).
  bool inProject = false;

  /// Found while listening and taken over by the user. Until then a gateway outside the project is
  /// only a suggestion: kept in memory, never saved, and at most [DaliStore.maxSuggestions] of
  /// them (any device can send with any sender address).
  bool confirmed = false;

  /// In the project or confirmed: its reports count and are saved.
  bool get trusted => inProject || confirmed;

  /// Last telegram of any kind from the gateway.
  DateTime? lastSeen;

  /// Last DALI report (diagnostic, converter status, test result).
  DateTime? lastReport;

  /// Failed lamps or gear as the gateway counts them, where it has such an object.
  int? faultCount;

  /// Last gateway-specific fault number.
  int? faultCode;

  /// Diagnostic addresses (DPT 237.600, 238.600) the gateway was heard on.
  final diagnosticGroups = <int>{};

  Map<String, Object?> toSetupJson() => {
    'a': address,
    'n': ?name,
    'pn': ?projectName,
    'l': ?location,
    'p': ?profile?.id,
    if (confirmed) 'ok': true,
    if (diagnosticGroups.isNotEmpty) 'dg': diagnosticGroups.toList()..sort(),
  };

  Map<String, Object?> toStateJson() => {
    'a': address,
    'seen': ?lastSeen?.millisecondsSinceEpoch,
    't': ?lastReport?.millisecondsSinceEpoch,
    'count': ?faultCount,
    'code': ?faultCode,
  };

  Map<String, Object?> toJson() => {...toSetupJson(), ...toStateJson()};

  static DaliGateway? fromJson(Object? json) {
    if (json is! Map) return null;
    final address = _int(json['a'], max: 0xFFFF);
    if (address == null) return null;
    return DaliGateway(address)..read(json);
  }

  void read(Map<Object?, Object?> json) {
    if (json['dg'] case final List<Object?> groups) {
      diagnosticGroups.addAll([for (final g in groups.take(64)) ?_int(g, max: 0xFFFF)]);
    }
    if (json.containsKey('n')) name = _text(json['n']);
    if (json.containsKey('pn')) projectName = _text(json['pn']);
    if (json.containsKey('l')) location = _text(json['l']);
    if (json['ok'] == true) confirmed = true;
    if (json.containsKey('seen')) lastSeen = _time(json['seen']);
    if (json.containsKey('t')) lastReport = _time(json['t']);
    if (json.containsKey('count')) faultCount = _int(json['count'], max: 4096);
    if (json.containsKey('code')) faultCode = _int(json['code'], max: 255);
  }
}

/// A change the store reports: a luminaire or group enters or leaves a fault.
typedef DaliChange = ({DaliGateway gateway, DaliTarget target, int before, int after, DateTime time, int group});

/// Settings of the DALI views, per installation.
class DaliSettings {
  /// Days after which a function test is overdue.
  int functionDays = 30;

  /// Days after which a duration test is overdue.
  int durationDays = 365;

  /// Read the diagnostic addresses periodically. Off by default: it sends.
  bool poll = false;

  /// Minutes between two rounds of reading.
  int pollMinutes = 60;

  static const functionChoices = [7, 30, 90];
  static const durationChoices = [180, 365, 730];
  static const pollChoices = [15, 60, 360, 1440];

  Map<String, Object?> toJson() => {
    'functionDays': functionDays,
    'durationDays': durationDays,
    if (poll) 'poll': true,
    'pollMinutes': pollMinutes,
  };

  void read(Object? json) {
    if (json is! Map) return;
    functionDays = _int(json['functionDays'], min: 1, max: 3650) ?? functionDays;
    durationDays = _int(json['durationDays'], min: 1, max: 3650) ?? durationDays;
    poll = json['poll'] == true;
    pollMinutes = _int(json['pollMinutes'], min: 5, max: 10080) ?? pollMinutes;
  }
}

int? _int(Object? v, {int min = 0, required int max}) => v is int && v >= min && v <= max ? v : null;

String? _text(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  if (t.isEmpty) return null;
  return t.length > 120 ? t.substring(0, 120) : t;
}

DateTime? _time(Object? v) => v is int && v > 0 && v < 8640000000000000 ? DateTime.fromMillisecondsSinceEpoch(v) : null;

/// The DALI side of the installation: gateways, luminaires and groups with their state.
///
/// Which devices are gateways and what their objects mean comes from the project
/// ([DaliProject]); the state comes from the telegrams ([observe]); names, rooms and groups of a
/// luminaire are entered in the app.
///
/// Two files next to the project, only where there is DALI:
/// - `dali.json`: what was entered in the app and what the objects mean. Written on edits and
///   project changes, shared with the add-on server and the box (it names luminaires there).
/// - `dali_state.json`: what the bus reported. Local; a change of a fault is saved within seconds,
///   mere liveness at most every [_seenEvery].
///
/// Any device on the bus can send with any sender address. Reports count only from gateways in the
/// project or confirmed by the user; others become suggestions, at most [maxSuggestions], kept in
/// memory until the user takes one over.
class DaliStore extends ChangeNotifier {
  DaliStore._() {
    CatalogStore.instance.addListener(_projectChanged);
    DaliText.nameOf = daliNameOf;
  }

  static final instance = DaliStore._();

  /// Setup of the active installation (shared with the server).
  static const path = 'dali.json';

  /// Runtime state of the active installation (local).
  static const statePath = 'dali_state.json';

  /// Changes kept per luminaire or group.
  static const keepEvents = 20;

  /// Gateways found while listening that are not taken over yet.
  static const maxSuggestions = 16;

  /// A file larger than this is not ours.
  static const _maxBytes = 4 * 1024 * 1024;

  /// Liveness and "nothing changed" reports are only written this often.
  static const _seenEvery = Duration(minutes: 10);

  final _gateways = <int, DaliGateway>{};
  final _gear = <String, DaliGear>{};
  final _groups = <String, DaliGroup>{};
  final settings = DaliSettings();

  /// Last telegram seen at all: later ones in the daily history are still to be caught up.
  DateTime? lastObserved;

  DaliProject _project = DaliProject.empty;
  bool _projectDirty = true;
  bool _loaded = false;
  bool _setupDirty = false;
  bool _stateDirty = false;
  Timer? _saveTimer;
  DateTime? _stateSaved;
  String? _storedSetup;
  String? _storedState;

  /// Luminaires per gateway, rebuilt when luminaires come or go (not per frame).
  Map<int, List<DaliGear>>? _byGateway;

  final _changes = StreamController<DaliChange>.broadcast();

  /// Luminaires and groups that enter or leave a fault, live only.
  Stream<DaliChange> get changes => _changes.stream;

  /// Results of emergency tests go here (the log store listens).
  void Function(List<EmergencyTest> entries)? onTests;

  /// Whether the last counting emergency test of a luminaire failed (set by the log store).
  bool Function(DaliGear gear)? testFailedOf;
  var tracker = EmergencyTracker();

  /// What the installation had before a demo started.
  ({
    Map<int, DaliGateway> gateways,
    Map<String, DaliGear> gear,
    Map<String, DaliGroup> groups,
    Map<String, Object?> settings,
    DateTime? lastObserved,
    EmergencyTracker tracker,
    bool setupDirty,
    bool stateDirty,
    String? storedSetup,
    String? storedState,
  })?
  _beforeDemo;

  /// The demo house has its own DALI gateway. Its state lives in memory only and never mixes with
  /// the installation's: entering the demo sets the installation's state aside, leaving it brings
  /// it back. Checked wherever the state is read or changed, so every way into the demo (demo
  /// button, tour) is covered.
  void _syncDemo() {
    if (DemoTunnel.active == (_beforeDemo != null)) return;
    if (DemoTunnel.active) {
      _saveTimer?.cancel();
      _beforeDemo = (
        gateways: Map.of(_gateways),
        gear: Map.of(_gear),
        groups: Map.of(_groups),
        settings: settings.toJson(),
        lastObserved: lastObserved,
        tracker: tracker,
        setupDirty: _setupDirty,
        stateDirty: _stateDirty,
        storedSetup: _storedSetup,
        storedState: _storedState,
      );
      _clear();
      _projectDirty = true;
      // What the demo log already holds is no new result when the gateway reports it.
      demoEmergencyLog(DemoTunnel.clock()).forEach(tracker.seed);
    } else {
      final before = _beforeDemo!;
      _beforeDemo = null;
      _clear();
      _gateways.addAll(before.gateways);
      _gear.addAll(before.gear);
      _groups.addAll(before.groups);
      settings.read(before.settings);
      lastObserved = before.lastObserved;
      tracker = before.tracker;
      _setupDirty = before.setupDirty;
      _stateDirty = before.stateDirty;
      _storedSetup = before.storedSetup;
      _storedState = before.storedState;
      _projectDirty = true;
      // A save that was pending when the demo started.
      if (_setupDirty || _stateDirty) _schedule(const Duration(seconds: 2));
    }
  }

  /// Names, rooms and groups of the demo gateway's luminaires, as somebody would have entered
  /// them.
  void _seedDemo() {
    if (!_gateways.containsKey(DemoDali.gateway)) return;
    for (final l in demoLuminaires()) {
      final gear = _gearFor(DemoDali.gateway, l.address);
      if (gear.name != null) return;
      gear
        ..name = l.name
        ..room = l.room
        ..groups = {l.group};
    }
    for (final (i, name) in demoGroupNames().indexed) {
      _groups['${DemoDali.gateway}:g$i']?.name = name;
    }
  }

  /// The project's DALI side, rebuilt when the project changes.
  DaliProject get project {
    _syncDemo();
    if (_projectDirty) {
      final store = CatalogStore.instance;
      _project = DaliProject.of(store.catalog, store.dptOf);
      _projectDirty = false;
      _applyProject();
      if (DemoTunnel.active) _seedDemo();
      // The server learns what the objects mean (the text only changes with the project). Not
      // while the files are read: a save then would lose what they hold.
      if (_loaded && !_reading && !_project.isEmpty) _changedSetup();
    }
    return _project;
  }

  void _projectChanged() {
    _projectDirty = true;
    notifyListeners();
  }

  /// Whether the installation has anything DALI at all.
  bool get isEmpty => project.isEmpty && _gateways.isEmpty;

  /// Gateways by individual address: the trusted ones, then the suggestions.
  List<DaliGateway> get gateways {
    project;
    return _gateways.values.toList()..sort((a, b) {
      if (a.trusted != b.trusted) return a.trusted ? -1 : 1;
      return a.address.compareTo(b.address);
    });
  }

  DaliGateway? gateway(int address) {
    project;
    return _gateways[address];
  }

  Map<int, List<DaliGear>> get _index => _byGateway ??= () {
    final map = <int, List<DaliGear>>{};
    for (final g in _gear.values) {
      (map[g.gateway] ??= []).add(g);
    }
    return map;
  }();

  /// Luminaires of [gateway]: faults first (a failed emergency test counts), then by address;
  /// converters without address last.
  List<DaliGear> gearOf(int gateway) {
    project;
    final list = [...?_index[gateway]];
    final attention = {for (final g in list) g.id: overall(g).index > DaliState.ok.index};
    return list..sort((a, b) {
      final fa = attention[a.id]!;
      final fb = attention[b.id]!;
      if (fa != fb) return fa ? -1 : 1;
      return (a.address ?? 100 + (a.anchor ?? 0)).compareTo(b.address ?? 100 + (b.anchor ?? 0));
    });
  }

  /// The state a luminaire shows everywhere: its reported faults, or a failed emergency test.
  DaliState overall(DaliGear gear) {
    if (gear.faulty) return gear.state;
    if (gear.emergency && (testFailedOf?.call(gear) ?? false)) return DaliState.testFailed;
    return gear.state;
  }

  /// Whether a luminaire needs a look: a fault or a failed emergency test.
  bool needsAttention(DaliGear gear) => overall(gear).index > DaliState.ok.index;

  DaliGear? gear(int gateway, int address) {
    project;
    return _gear['$gateway:$address'];
  }

  /// Luminaire by [DaliGear.id].
  DaliGear? gearById(String id) {
    project;
    return _gear[id];
  }

  /// Groups of [gateway] by number.
  List<DaliGroup> groupsOf(int gateway) {
    project;
    return _groups.values.where((g) => g.gateway == gateway).toList()..sort((a, b) => a.group.compareTo(b.group));
  }

  DaliGroup? group(int gateway, int group) {
    project;
    return _groups['$gateway:g$group'];
  }

  /// The worst state of a group: its own report, and that of the luminaires entered in it.
  DaliState groupState(DaliGroup group) {
    var worst = group.state;
    for (final g in _index[group.gateway] ?? const <DaliGear>[]) {
      if (!g.groups.contains(group.group)) continue;
      final state = overall(g);
      if (state.index > worst.index) worst = state;
    }
    return worst;
  }

  /// All luminaires with a reported fault, of trusted gateways.
  List<DaliGear> get faultyGear {
    project;
    return [
      for (final g in _gateways.values)
        if (g.trusted)
          for (final x in _index[g.address] ?? const <DaliGear>[])
            if (x.faulty) x,
    ];
  }

  /// All emergency luminaires of trusted gateways.
  List<DaliGear> get emergencyGear {
    project;
    return [
      for (final g in gateways)
        if (g.trusted) ...gearOf(g.address).where((x) => x.emergency),
    ];
  }

  /// The luminaire whose test results arrive at [resultGroup].
  DaliGear? gearOfResult(int resultGroup) {
    project;
    for (final g in _gear.values) {
      if (g.resultGroup == resultGroup) return g;
    }
    return null;
  }

  // --- Loading and saving ---------------------------------------------------------------------

  Future<void> load() async {
    await DaliProfiles.load();
    _projectDirty = true;
    // In the demo the installation's files stay closed; they are read when the demo is over.
    if (_loaded || DemoTunnel.active) return;
    _loaded = true;
    _reading = true;
    try {
      await _readFiles();
    } finally {
      _reading = false;
    }
  }

  /// Files are being read: nothing is saved meanwhile.
  bool _reading = false;

  Future<void> _readFiles() async {
    // The project's gateways first: the files only add to gateways that are known.
    project;
    final storage = InstallationStore.instance.storage;
    final setup = await readStored(storage, path, (text) {
      if (text.length > _maxBytes) throw const FormatException('dali.json too large');
      _read(jsonDecode(text), setup: true);
      return text;
    });
    _storedSetup = setup;
    final state = await readStored(storage, statePath, (text) {
      if (text.length > _maxBytes) throw const FormatException('dali_state.json too large');
      _read(jsonDecode(text), setup: false);
      return text;
    });
    _storedState = state;
    _byGateway = null;
    // The files replaced what the project had already put there.
    _projectDirty = true;
    if (setup != null || state != null) notifyListeners();
  }

  /// Reads a file. Entries one by one: a broken one is skipped, the others stay. State of a
  /// luminaire or group whose gateway is unknown is dropped.
  void _read(Object? json, {required bool setup}) {
    if (json is! Map) throw const FormatException('DALI file is not an object');
    if (setup) settings.read(json['settings']);
    if (json.containsKey('seen')) lastObserved = _time(json['seen']) ?? lastObserved;
    void each(Object? list, int max, void Function(Map<Object?, Object?> j) take) {
      if (list is! List) return;
      for (final j in list.take(max)) {
        if (j is! Map) continue;
        try {
          take(j);
        } on Object catch (e) {
          debugPrint('DALI: Eintrag übersprungen: $e');
        }
      }
    }

    each(json['gateways'], 256, (j) {
      final address = _int(j['a'], max: 0xFFFF);
      if (address == null) return;
      // Only trusted gateways are saved: whatever a file names was taken over (project gateways
      // too; a gateway that leaves the project stays, the user removes it).
      _gateways.putIfAbsent(address, () => DaliGateway(address)..confirmed = true).read(j);
    });
    each(json['gear'], 256 * 64, (j) {
      final key = DaliGear.keyOf(j);
      if (key == null || !_gateways.containsKey(key.$1)) return;
      final (gateway, address, anchor) = key;
      final id = address != null ? '$gateway:$address' : '$gateway:ga$anchor';
      _gear.putIfAbsent(id, () => DaliGear(gateway, address: address, anchor: anchor)).read(j);
    });
    each(json['groups'], 256 * 16, (j) {
      final gateway = _int(j['gw'], max: 0xFFFF);
      final group = _int(j['g'], max: 15);
      if (gateway == null || group == null || !_gateways.containsKey(gateway)) return;
      _groups.putIfAbsent('$gateway:g$group', () => DaliGroup(gateway, group)).read(j);
    });
  }

  /// Reloads the saved state (after a demo, on switching the installation).
  Future<void> reload() async {
    await flush();
    _beforeDemo = null;
    _clear();
    _loaded = false;
    await load();
    notifyListeners();
  }

  void _clear() {
    _saveTimer?.cancel();
    _setupDirty = false;
    _stateDirty = false;
    _gateways.clear();
    _gear.clear();
    _groups.clear();
    _byGateway = null;
    tracker = EmergencyTracker();
    lastObserved = null;
    _stateSaved = null;
    _storedSetup = null;
    _storedState = null;
    settings
      ..functionDays = 30
      ..durationDays = 365
      ..poll = false
      ..pollMinutes = 60;
  }

  Iterable<DaliGateway> get _trusted => gateways.where((g) => g.trusted);
  bool _trustedId(int gateway) => _gateways[gateway]?.trusted ?? false;

  /// `dali.json`: what was entered and what the objects mean, for the trusted gateways.
  Map<String, Object?> toSetupJson() => {
    'v': 1,
    'settings': settings.toJson(),
    'gateways': [for (final g in _trusted) g.toSetupJson()],
    'gear': [
      for (final g in _gear.values)
        if (_trustedId(g.gateway)) g.toSetupJson(),
    ],
    'groups': [
      for (final g in _groups.values)
        if (_trustedId(g.gateway) && g.name != null) g.toSetupJson(),
    ],
    // For the add-on server and the box: what the objects mean, so they can name a luminaire in a
    // notification and pair converter status and test result without the profiles.
    'objects': {for (final o in project.objects.values) '${o.group}': o.toJson()},
  };

  /// `dali_state.json`: what the bus reported, for the trusted gateways.
  Map<String, Object?> toStateJson() => {
    'v': 1,
    'seen': ?lastObserved?.millisecondsSinceEpoch,
    'gateways': [for (final g in _trusted) g.toStateJson()],
    'gear': [
      for (final g in _gear.values)
        if (_trustedId(g.gateway) && (g.faults != null || g.lastReport != null || g.mode != null)) g.toStateJson(),
    ],
    'groups': [
      for (final g in _groups.values)
        if (_trustedId(g.gateway) && (g.faults != null || g.lastReport != null)) g.toStateJson(),
    ],
  };

  /// Everything, for tests and diagnostics.
  Map<String, Object?> toJson() => {...toSetupJson(), ...toStateJson()};

  void _schedule(Duration wait) {
    if (DemoTunnel.active) return;
    if (_saveTimer?.isActive ?? false) return;
    _saveTimer = Timer(wait, () => unawaited(_save()));
  }

  /// Something entered in the app, or the project: saved right away.
  void _changedSetup() {
    _setupDirty = true;
    _saveTimer?.cancel();
    _schedule(Duration.zero);
  }

  /// The bus reported something. [urgent]: a fault came or went (saved within seconds); otherwise
  /// liveness, saved at most every [_seenEvery].
  void _changedState({bool urgent = false}) {
    _stateDirty = true;
    notifyListeners();
    final saved = _stateSaved;
    final due = urgent || saved == null || DateTime.now().difference(saved) >= _seenEvery;
    _schedule(due ? const Duration(seconds: 2) : _seenEvery - DateTime.now().difference(saved));
  }

  final _saving = <Future<void>>{};

  Future<void> _save() async {
    if (DemoTunnel.active || _reading || isEmpty) return;
    final writes = <Future<void>>[];
    if (_setupDirty) {
      _setupDirty = false;
      final text = jsonEncode(toSetupJson());
      if (text != _storedSetup) {
        _storedSetup = text;
        writes.add(_writeSetup(text));
      }
    }
    if (_stateDirty) {
      _stateDirty = false;
      _stateSaved = DateTime.now();
      final text = jsonEncode(toStateJson());
      if (text != _storedState) {
        _storedState = text;
        writes.add(InstallationStore.instance.storage.write(statePath, text));
      }
    }
    for (final write in writes) {
      _saving.add(write);
      try {
        await write;
      } on Object catch (e) {
        debugPrint('DALI nicht gespeichert: $e');
      } finally {
        _saving.remove(write);
      }
    }
  }

  Future<void> _writeSetup(String text) async {
    await InstallationStore.instance.storage.write(path, text);
    // Via the Busclear Box: put the setup there too (not the state: the box keeps its own), so it
    // names the luminaire in its notifications.
    final installations = InstallationStore.instance;
    final box = Addon.box;
    if (box == null || (installations.boxActive != null && installations.boxActive != installations.active.id)) return;
    if (!await BoxProjectConsent.allowed(box)) return;
    await Addon.putFile(path, utf8.encode(text));
  }

  /// Waits until pending saves are done (switching installations, tests).
  Future<void> flush() async {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      await _save();
    }
    await Future.wait([..._saving]).then((_) {}, onError: (Object _) {});
  }

  // --- Project ----------------------------------------------------------------------------------

  /// Takes names, locations and object addresses from the project; state and what was entered in
  /// the app stay.
  void _applyProject() {
    final p = _project;
    for (final g in _gateways.values) {
      g.inProject = p.gateways.containsKey(g.address);
      if (!g.inProject) g.profile = null;
    }
    for (final pg in p.gateways.values) {
      _gateways.putIfAbsent(pg.address, () => DaliGateway(pg.address))
        ..inProject = true
        ..projectName = pg.name
        ..location = pg.location
        ..profile = pg.profile;
    }
    for (final g in _groups.values) {
      g
        ..switchGroup = null
        ..dimGroup = null
        ..valueGroup = null
        ..statusGroup = null
        ..valueStatusGroup = null;
    }
    for (final g in _gear.values) {
      g
        ..statusGroup = null
        ..resultGroup = null;
    }
    for (final o in p.objects.values) {
      switch (o.role.counts) {
        case DaliIndex.group:
          final index = o.index;
          if (index == null) continue;
          final group = _groups.putIfAbsent('${o.gateway}:g$index', () => DaliGroup(o.gateway, index));
          switch (o.role) {
            case DaliRole.groupSwitch:
              group.switchGroup = o.group;
            case DaliRole.groupDim:
              group.dimGroup = o.group;
            case DaliRole.groupValue:
              group.valueGroup = o.group;
            case DaliRole.groupStatus:
              group.statusGroup = o.group;
            case DaliRole.groupValueStatus:
              group.valueStatusGroup = o.group;
            default:
          }
        case DaliIndex.gear:
          if (o.role != DaliRole.emergencyStatus && o.role != DaliRole.emergencyResult) continue;
          final gear = _gearFor(o.gateway, o.index, anchor: o.group)..emergencyDetected = true;
          if (o.role == DaliRole.emergencyStatus) {
            gear.statusGroup = o.group;
          } else {
            gear.resultGroup = o.group;
          }
        case DaliIndex.none:
      }
    }
    // Converters without address that the project no longer has and that never reported.
    _gear.removeWhere(
      (_, g) => g.address == null && g.statusGroup == null && g.resultGroup == null && g.lastReport == null,
    );
    _byGateway = null;
  }

  DaliGear _gearFor(int gateway, int? address, {int? anchor}) {
    final id = address != null ? '$gateway:$address' : '$gateway:ga$anchor';
    final existing = _gear[id];
    if (existing != null) return existing;
    _byGateway = null;
    return _gear[id] = DaliGear(gateway, address: address, anchor: address == null ? anchor : null);
  }

  // --- Telegrams --------------------------------------------------------------------------------

  /// The gateway a report from [source] counts for: a trusted one, or a suggestion while there is
  /// room for one. `null` = ignore the report.
  DaliGateway? _admit(int source, DateTime time) {
    final known = _gateways[source];
    if (known != null) return known;
    // Senders the project does not know: a suggestion, but never more than a few.
    if (_gateways.values.where((g) => !g.trusted).length >= maxSuggestions) return null;
    return _gateways[source] = DaliGateway(source)..lastSeen = time;
  }

  /// Takes a telegram from the bus. [live] = just arrived (changes are announced); otherwise
  /// replayed from the history.
  void observe(Telegram t, {bool live = true}) {
    _syncDemo();
    if (t.type == TelegramType.read || t.outgoing) return;
    final p = project;
    final store = CatalogStore.instance;
    final dpt = store.dptOf(t.destination);
    final isDali = dpt != null && isDaliDpt(dpt.main, dpt.sub);
    final object = p.objects[t.destination];
    final known = _gateways[t.source];
    if (known != null) {
      known.lastSeen = t.time;
      if (live && known.trusted) _changedState();
    }
    if (!isDali && object == null) return;
    if (lastObserved == null || t.time.isAfter(lastObserved!)) lastObserved = t.time;

    if (isDali && (dpt.main == 237 || dpt.main == 238)) {
      if (t.isSmall) return;
      final report = decodeDaliReport(dpt.main, t.data);
      if (report == null || report.readRequest) return;
      // The sender is the gateway. One the project does not name for this address is at most a
      // suggestion: any device can send with any sender address.
      final gw = _admit(t.source, t.time);
      if (gw == null) return;
      gw
        ..lastReport = t.time
        ..diagnosticGroups.add(t.destination);
      final pa = gw.address;
      final DaliTarget target = report.isGroup
          ? _groups.putIfAbsent('$pa:g${report.address}', () => DaliGroup(pa, report.address))
          : _gearFor(pa, report.address);
      if (target is DaliGear && report.faults & DaliFault.converter != 0) target.emergencyDetected = true;
      _report(gw, target, report.faults, t, live: live);
      return;
    }

    if (isDali && dpt.main == 244) {
      if (t.isSmall) return;
      final status = decodeConverterStatus(t.data);
      if (status == null) return;
      // With the project the object names its gateway; only its status counts.
      if (object != null && object.gateway != t.source) return;
      final gw = object != null ? _gateways[object.gateway] : _admit(t.source, t.time);
      if (gw == null) return;
      gw.lastReport = t.time;
      final gear = _gearFor(gw.address, object?.index, anchor: t.destination)
        ..emergencyDetected = true
        ..statusGroup ??= t.destination
        ..mode = status.mode;
      if (gear.resultGroup case final result?) tracker.status(result, status);
      // The status only knows "a failure" or "none"; "unknown" changes nothing.
      if (status.failure != ConverterFlag.unknown) {
        final others = (gear.faults ?? 0) & ~DaliFault.converter;
        _report(gw, gear, others | (status.failure == ConverterFlag.yes ? DaliFault.converter : 0), t, live: live);
      } else {
        gear.lastReport = t.time;
        _changedState();
      }
      return;
    }

    if (isDali && dpt.main == 245) {
      if (t.isSmall || decodeConverterTestResult(t.data) == null) return;
      // Without the project the sender is the gateway (if it is one we follow); with it, a result
      // from another sender is logged as foreign and counts for nothing.
      final gw = object != null ? _gateways[object.gateway] : _admit(t.source, t.time);
      if (gw == null) return;
      final gear = _gearFor(gw.address, object?.index, anchor: t.destination)
        ..emergencyDetected = true
        ..resultGroup ??= t.destination;
      final foreign = t.source != gw.address;
      final entries = tracker.result(
        t.destination,
        t.data,
        t.time,
        gateway: gw.address,
        address: gear.address,
        source: t.source,
        // Decrypted by the tunnel with the keyring; a telegram from the history does not know it.
        secure: arrivedSecure(t),
      );
      if (!foreign) {
        gw.lastReport = t.time;
        gear.lastReport = t.time;
      }
      if (entries.isNotEmpty && gw.trusted) onTests?.call(entries);
      _changedState(urgent: entries.isNotEmpty);
      return;
    }

    if (object == null || t.source != object.gateway) return;
    final gw = _gateways[object.gateway];
    if (gw == null) return;
    gw.lastReport = t.time;
    final value = t.data.isEmpty ? 0 : t.data.fold<int>(0, (v, b) => (v << 8) | b);
    final on = t.isSmall && t.data.isNotEmpty && t.data[0] & 1 == 1;
    switch (object.role) {
      case DaliRole.lampFault || DaliRole.gearFault when object.index != null && t.isSmall:
        final gear = _gearFor(object.gateway, object.index);
        final bit = object.role == DaliRole.lampFault ? DaliFault.lamp : DaliFault.gear;
        _report(gw, gear, ((gear.faults ?? 0) & ~bit) | (on ? bit : 0), t, live: live);
      case DaliRole.groupFault when object.index != null && t.isSmall:
        final group = _groups.putIfAbsent(
          '${object.gateway}:g${object.index}',
          () => DaliGroup(object.gateway, object.index!),
        );
        _report(gw, group, on ? DaliFault.gear : 0, t, live: live);
      case DaliRole.faultCount when !t.isSmall && t.data.length <= 2:
        if (gw.faultCount != value) {
          gw.faultCount = value;
          _changedState(urgent: true);
        }
      case DaliRole.faultCode when !t.isSmall && t.data.length == 1:
        if (gw.faultCode != value) {
          gw.faultCode = value;
          _changedState(urgent: true);
        }
      case DaliRole.burnHours when object.index != null && !t.isSmall && t.data.length <= 4:
        final gear = _gearFor(object.gateway, object.index);
        if (gear.burnHours != value) {
          gear.burnHours = value;
          _changedState();
        }
      default:
    }
  }

  void _report(DaliGateway gw, DaliTarget target, int faults, Telegram t, {required bool live}) {
    final before = target.faults;
    target.lastReport = t.time;
    if (before != faults) {
      target
        ..faults = faults
        ..since = t.time
        ..events.add((time: t.time, faults: faults));
      if (target.events.length > keepEvents) target.events.removeRange(0, target.events.length - keepEvents);
      // The first report of a healthy luminaire is no news; a first report with a fault is. Only
      // trusted gateways are announced.
      if (live && gw.trusted && (before ?? 0) != faults) {
        _changes.add((
          gateway: gw,
          target: target,
          before: before ?? 0,
          after: faults,
          time: t.time,
          group: t.destination,
        ));
      }
    }
    _changedState(urgent: before != faults);
  }

  /// Replays telegrams from the history (oldest first) that are newer than what was seen, without
  /// announcing changes: what happened while the app was closed and the add-on or box recorded.
  void catchUp(Iterable<Telegram> telegrams) {
    final from = lastObserved;
    for (final t in telegrams) {
      if (from != null && !t.time.isAfter(from)) continue;
      observe(t, live: false);
    }
  }

  // --- What is entered in the app ---------------------------------------------------------------

  void editGear(DaliGear gear, {String? name, String? room, Set<int>? groups, bool? emergency}) {
    gear
      ..name = _text(name)
      ..room = _text(room)
      ..groups = {...?groups?.where((g) => g >= 0 && g <= 15)}
      ..emergencyByHand = emergency == gear.emergencyDetected ? null : emergency;
    notifyListeners();
    _changedSetup();
  }

  void rename(DaliTarget target, String? name) {
    target.name = _text(name);
    notifyListeners();
    _changedSetup();
  }

  void renameGateway(DaliGateway gateway, String? name) {
    gateway.name = _text(name);
    notifyListeners();
    _changedSetup();
  }

  /// Takes over a gateway found while listening: from now on its reports count and are saved.
  void confirmGateway(DaliGateway gateway) {
    if (gateway.trusted) return;
    gateway.confirmed = true;
    notifyListeners();
    _changedSetup();
    _changedState(urgent: true);
  }

  /// Forgets a gateway found while listening, with its luminaires and groups.
  void removeGateway(DaliGateway gateway) {
    if (gateway.inProject) return;
    _gateways.remove(gateway.address);
    _gear.removeWhere((_, g) => g.gateway == gateway.address);
    _groups.removeWhere((_, g) => g.gateway == gateway.address);
    _byGateway = null;
    notifyListeners();
    _changedSetup();
    _changedState(urgent: true);
  }

  void updateSettings(void Function(DaliSettings s) change) {
    change(settings);
    notifyListeners();
    if (isEmpty || DemoTunnel.active) return;
    _changedSetup();
  }

  // --- Reading ----------------------------------------------------------------------------------

  /// Group addresses whose state a read brings back: the diagnostic objects and the fault and
  /// converter objects of [gateway] (all trusted gateways without one). Only objects the gateway
  /// sends on; objects whose flags are known and do not allow reading are left out.
  List<int> readableAddresses([int? gateway]) {
    final p = project;
    final catalog = CatalogStore.instance.catalog;
    const roles = {
      DaliRole.diagnostic,
      DaliRole.lampFault,
      DaliRole.gearFault,
      DaliRole.groupFault,
      DaliRole.faultCount,
      DaliRole.emergencyStatus,
      DaliRole.emergencyResult,
    };
    bool readable(DaliObject o) {
      final links = catalog[o.group]?.links.where((l) => l.device == o.gateway) ?? const <GroupLink>[];
      return links.isEmpty || links.any((l) => l.flags?.answersReads ?? true);
    }

    return {
      for (final o in p.objects.values)
        if (roles.contains(o.role) && (gateway == null || o.gateway == gateway) && readable(o)) o.group,
      // Heard without a project: nothing known speaks against reading.
      for (final g in _trusted)
        if (gateway == null || g.address == gateway) ...g.diagnosticGroups.where((a) => !p.objects.containsKey(a)),
    }.toList()..sort();
  }

  /// Diagnostic addresses (DPT 237.600, 238.600) of [gateway]: from the project and as heard.
  Set<int> diagnosticGroupsOf(int gateway) => {
    for (final MapEntry(:key, :value) in project.diagnostics.entries)
      if (value.contains(gateway)) key,
    ...?_gateways[gateway]?.diagnosticGroups,
  };

  /// Whether reading is possible on [tunnel]: not on a server in read-only mode, not for a device
  /// paired for viewing only.
  static bool canRead(KnxTunnel tunnel) => !(tunnel is SharedTunnel && tunnel.readOnly);

  bool reading = false;
  int readSent = 0;
  int readTotal = 0;

  /// Reads the diagnostic addresses once (5 per second). The answers arrive as telegrams like any
  /// others. Returns how many addresses answered; `null` if reading is not possible or already
  /// running.
  Future<int?> readDiagnostics(KnxTunnel tunnel, {int? gateway}) async {
    if (reading || !canRead(tunnel) || tunnel.state.value != TunnelState.connected) return null;
    final addresses = readableAddresses(gateway);
    if (addresses.isEmpty) return 0;
    reading = true;
    readSent = 0;
    readTotal = addresses.length;
    notifyListeners();
    try {
      final answers = await ReadSweep.run(
        tunnel,
        addresses,
        cancelled: () => !reading,
        onSent: (n) {
          readSent = n;
          notifyListeners();
        },
      );
      return answers.length;
    } finally {
      reading = false;
      notifyListeners();
    }
  }

  void cancelRead() {
    if (!reading) return;
    reading = false;
    notifyListeners();
  }

  @visibleForTesting
  void debugReset() {
    _clear();
    _loaded = true;
    _projectDirty = true;
    reading = false;
  }

  /// For tests only: allows [load] again.
  @visibleForTesting
  void debugAllowLoad() => _loaded = false;
}

/// Reads the diagnostic addresses periodically while connected, if the installation's setting
/// asks for it ([DaliSettings.poll], off by default because it sends). Never on a server in
/// read-only mode. The first round comes after a random part of the interval, and a round is left
/// out while every gateway reported within the interval anyway (another view on the same server
/// read, or the gateway sends by itself): several views on one server do not all read.
class DaliPoller {
  DaliPoller(
    this.tunnel, {
    Duration check = const Duration(minutes: 1),
    DateTime Function()? now,
    Random? random,
    this.firstDelay,
  }) : _now = now ?? DateTime.now,
       _random = random ?? Random() {
    _timer = Timer.periodic(check, (_) => unawaited(tick()));
  }

  final KnxTunnel tunnel;
  final DateTime Function() _now;
  final Random _random;

  /// Wait before the first round; random within half the interval without it.
  final Duration? firstDelay;
  late final Timer _timer;
  DateTime? _last;
  DateTime? _start;

  /// One check: reads if it is due. Returns whether a round ran.
  Future<bool> tick() async {
    final store = DaliStore.instance;
    final settings = store.settings;
    if (!settings.poll || store.isEmpty || !DaliStore.canRead(tunnel)) return false;
    final now = _now();
    final interval = Duration(minutes: settings.pollMinutes);
    if (_last == null) {
      _start ??= now.add(firstDelay ?? Duration(seconds: _random.nextInt(interval.inSeconds ~/ 2 + 1)));
      if (now.isBefore(_start!)) return false;
    } else if (now.difference(_last!) < interval) {
      return false;
    }
    _last = now;
    final gateways = store.gateways.where((g) => g.trusted).toList();
    final fresh =
        gateways.isNotEmpty && gateways.every((g) => g.lastReport != null && now.difference(g.lastReport!) < interval);
    if (fresh) return false;
    return await store.readDiagnostics(tunnel) != null;
  }

  void dispose() => _timer.cancel();
}
