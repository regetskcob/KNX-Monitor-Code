import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../knx/demo_tunnel.dart';
import '../knx/telegram.dart';
import '../platform/storage.dart';
import 'installation.dart';

/// Bus view on a floor plan: points on a plan that light up when one of their
/// group addresses is on the bus. An open file format, so any floor plan can be
/// used; the server of the add-on and the dashboard card read the same file.
const floorViewFormat = 'busclear-floor-view';
const floorViewFormatVersion = 1;

/// Limits for files from elsewhere (a restored backup, another app version).
const floorViewMaxFloors = 24;
const floorViewMaxPoints = 600;
const floorViewMaxRooms = 200;
const floorViewMaxAddresses = 12;
const floorViewMaxText = 80;

/// Kinds a point can have; unknown ones are shown as [FloorPointKind.other].
enum FloorPointKind { light, button, blind, socket, heating, sensor, contact, other }

/// Where an image may lie in the installation's folder: only the two image
/// folders, never a path from a file.
final _imagePath = RegExp(r'^(home_plan_images|floor_view_images)/[0-9a-z]{1,32}\.jpg\.b64$');

bool isFloorImagePath(Object? path) => path is String && _imagePath.hasMatch(path);

String _text(Object? value) {
  if (value is! String) return '';
  final clean = value.replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), ' ').trim();
  return clean.length > floorViewMaxText ? clean.substring(0, floorViewMaxText) : clean;
}

double _unit(Object? value, double fallback) {
  final v = value is num ? value.toDouble() : fallback;
  return v.isFinite ? v.clamp(0.0, 1.0) : fallback;
}

/// A point on the plan with the group addresses that make it light up.
class FloorPoint {
  FloorPoint({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    this.kind = FloorPointKind.other,
    this.room = '',
    List<int>? addresses,
  }) : addresses = addresses ?? [];

  factory FloorPoint.fromJson(Map<Object?, Object?> j) => FloorPoint(
    id: _text(j['id']),
    name: _text(j['name']),
    x: _unit(j['x'], 0.5),
    y: _unit(j['y'], 0.5),
    kind: FloorPointKind.values.asNameMap()[j['kind']] ?? FloorPointKind.other,
    room: _text(j['room']),
    addresses: [
      for (final a in (j['addresses'] is List ? j['addresses']! as List : const <Object?>[]).take(
        floorViewMaxAddresses,
      ))
        if (a is int && a > 0 && a <= 0xFFFF) a,
    ],
  );

  final String id;
  String name;
  double x;
  double y;
  FloorPointKind kind;
  String room;
  final List<int> addresses;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'x': x,
    'y': y,
    'kind': kind.name,
    if (room.isNotEmpty) 'room': room,
    'addresses': addresses,
  };
}

/// Outline of a room, in shares of the plan (0–1).
class FloorArea {
  const FloorArea(this.name, this.x, this.y, this.w, this.h);

  factory FloorArea.fromJson(Map<Object?, Object?> j) =>
      FloorArea(_text(j['name']), _unit(j['x'], 0), _unit(j['y'], 0), _unit(j['w'], 0.2), _unit(j['h'], 0.2));

  final String name;
  final double x;
  final double y;
  final double w;
  final double h;

  Map<String, Object?> toJson() => {'name': name, 'x': x, 'y': y, 'w': w, 'h': h};
}

class FloorLevel {
  FloorLevel({
    required this.id,
    required this.name,
    this.aspect = 1.5,
    this.image,
    List<FloorArea>? rooms,
    List<FloorPoint>? points,
  }) : rooms = rooms ?? [],
       points = points ?? [];

  factory FloorLevel.fromJson(Map<Object?, Object?> j) {
    final aspect = j['aspect'] is num ? (j['aspect']! as num).toDouble() : 1.5;
    return FloorLevel(
      id: _text(j['id']),
      name: _text(j['name']),
      aspect: aspect.isFinite ? aspect.clamp(0.2, 5.0) : 1.5,
      image: isFloorImagePath(j['image']) ? j['image']! as String : null,
      rooms: [
        for (final r in (j['rooms'] is List ? j['rooms']! as List : const <Object?>[]).take(floorViewMaxRooms))
          if (r is Map) FloorArea.fromJson(r),
      ],
      points: [
        for (final p in (j['points'] is List ? j['points']! as List : const <Object?>[]).take(floorViewMaxPoints))
          if (p is Map) FloorPoint.fromJson(p),
      ],
    );
  }

  final String id;
  String name;

  /// Width divided by height.
  double aspect;

  /// Image in the installation's folder (base64 JPEG), see [isFloorImagePath].
  String? image;
  final List<FloorArea> rooms;
  final List<FloorPoint> points;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'aspect': aspect,
    'image': ?image,
    if (rooms.isNotEmpty) 'rooms': [for (final r in rooms) r.toJson()],
    'points': [for (final p in points) p.toJson()],
  };
}

/// The file is from a newer app version.
class FloorViewTooNew implements Exception {
  const FloorViewTooNew();
}

class FloorView {
  FloorView({this.source = sourceOwn, List<FloorLevel>? floors, this.nextId = 1}) : floors = floors ?? [];

  /// Reads defensively: wrong types become defaults, lists are cut at the
  /// limits. Throws [FloorViewTooNew] or [FormatException].
  factory FloorView.fromJson(Object? json) {
    if (json is! Map || json['format'] != floorViewFormat) throw const FormatException('floor view');
    final version = json['version'];
    if (version is! int) throw const FormatException('floor view');
    if (version > floorViewFormatVersion) throw const FloorViewTooNew();
    return FloorView(
      source: json['source'] == sourceHomePlan ? sourceHomePlan : sourceOwn,
      floors: [
        for (final f in (json['floors'] is List ? json['floors']! as List : const <Object?>[]).take(floorViewMaxFloors))
          if (f is Map) FloorLevel.fromJson(f),
      ],
      nextId: json['nextId'] is int ? json['nextId']! as int : 1,
    );
  }

  /// Drawn by hand in the bus view.
  static const sourceOwn = 'own';

  /// Written from a house plan; redrawing it there replaces the file.
  static const sourceHomePlan = 'home-plan';

  String source;
  final List<FloorLevel> floors;
  int nextId;

  String newId(String prefix) => '$prefix${nextId++}';

  Iterable<FloorPoint> get points => floors.expand((f) => f.points);
  bool get isEmpty => floors.isEmpty;

  Map<String, Object?> toJson() => {
    'format': floorViewFormat,
    'version': floorViewFormatVersion,
    'source': source,
    'floors': [for (final f in floors) f.toJson()],
    'nextId': nextId,
  };
}

/// What a point shows.
enum PointState {
  /// A telegram within the last seconds.
  active,

  /// Heard, but not just now.
  heard,

  /// Has addresses, nothing heard yet, and the bus has not been watched long enough to call
  /// that unusual. Neutral: many devices only send when they are operated.
  unheard,

  /// Has addresses and nothing was heard although the bus has been watched for at least
  /// [FloorActivity.silentAfter]. Worth a look, still not a fault.
  silent,

  /// No group address yet.
  unlinked,
}

/// When each group address was last on the bus. Fed from the monitor's log and,
/// with the add-on or box, from the server's history.
class FloorActivity {
  FloorActivity({this.flash = const Duration(seconds: 4), this.silentAfter = const Duration(hours: 12)});

  /// Only after this much watched time does silence stand out, as with the watcher "stopped
  /// sending". The monitor alone rarely gets there; the recorded history of add-on and box does.
  final Duration silentAfter;

  /// A point stays highlighted this long after a telegram.
  final Duration flash;

  final _last = <int, DateTime>{};

  /// Since when the bus is watched: nothing older can be known.
  DateTime? since;

  DateTime? lastOf(FloorPoint p) {
    DateTime? best;
    for (final a in p.addresses) {
      final t = _last[a];
      if (t != null && (best == null || t.isAfter(best))) best = t;
    }
    return best;
  }

  PointState stateOf(FloorPoint p, DateTime now) {
    if (p.addresses.isEmpty) return PointState.unlinked;
    final last = lastOf(p);
    if (last == null) {
      final watched = since == null ? Duration.zero : now.difference(since!);
      return watched >= silentAfter ? PointState.silent : PointState.unheard;
    }
    return now.difference(last) <= flash ? PointState.active : PointState.heard;
  }

  /// Reads are questions, not a sign of life of the device behind the address.
  void observe(Telegram t) {
    if (t.type == TelegramType.read) return;
    note(t.destination, t.time);
  }

  void note(int address, DateTime time) {
    final known = _last[address];
    if (known == null || time.isAfter(known)) _last[address] = time;
  }

  /// Takes over the newest telegram per address of a log.
  void takeLatest(Map<int, Telegram> latest) {
    for (final t in latest.values) {
      observe(t);
    }
  }

  void clear() {
    _last.clear();
    since = null;
  }
}

/// The bus view of the active installation with its images.
class FloorViewStore extends ChangeNotifier {
  FloorViewStore._();

  static final instance = FloorViewStore._();
  static const path = 'floor_view.json';
  static const imageDir = 'floor_view_images';

  @visibleForTesting
  AppStorage? storageOverride;

  AppStorage get _storage => storageOverride ?? InstallationStore.instance.storage;

  FloorView _view = FloorView();
  FloorView get view => _view;

  /// From a newer app: shown as such and never overwritten.
  bool tooNew = false;
  bool _loaded = false;
  bool _demo = false;
  bool get loaded => _loaded;
  Timer? _saveTimer;
  final _images = <String, Uint8List>{};

  /// Loads the file; in the demo house a sample that is never written.
  Future<void> load({FloorView Function()? demo}) async {
    _saveTimer?.cancel();
    _images.clear();
    tooNew = false;
    _demo = DemoTunnel.active && storageOverride == null;
    if (_demo) {
      _view = demo?.call() ?? FloorView();
    } else {
      _view = FloorView();
      final text = await _storage.read(path);
      if (text != null) {
        try {
          _view = FloorView.fromJson(jsonDecode(text));
        } on FloorViewTooNew {
          tooNew = true;
        } on Object catch (e) {
          debugPrint('$path nicht lesbar: $e');
          await keepCorrupt(_storage, path, text);
        }
      }
    }
    _loaded = true;
    notifyListeners();
  }

  /// Loads once, and again when the demo house was entered or left.
  Future<void> ensureLoaded({FloorView Function()? demo}) async {
    if (!_loaded || _demo != (DemoTunnel.active && storageOverride == null)) await load(demo: demo);
  }

  void changed() {
    notifyListeners();
    if (tooNew || _demo) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () => unawaited(save()));
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    if (!tooNew && !_demo) await _storage.write(path, jsonEncode(_view.toJson()));
  }

  /// Replaces the whole view (from the house plan). Images of the own view go.
  Future<void> replace(FloorView view) async {
    if (tooNew) return;
    if (!_demo) {
      final keep = {for (final f in view.floors) ?f.image};
      for (final f in await _storage.list(imageDir)) {
        if (!keep.contains('$imageDir/${f.name}')) await _storage.delete('$imageDir/${f.name}');
      }
    }
    _images.clear();
    _view = view;
    notifyListeners();
    await save();
  }

  Future<Uint8List?> image(FloorLevel floor) async {
    final file = floor.image;
    if (file == null || !isFloorImagePath(file)) return null;
    final cached = _images[file];
    if (cached != null) return cached;
    try {
      final text = await _storage.read(file);
      if (text == null) return null;
      return _images[file] = base64Decode(text);
    } on Object catch (e) {
      debugPrint('$file nicht lesbar: $e');
      return null;
    }
  }

  Future<void> setImage(FloorLevel floor, Uint8List jpeg, double aspect) async {
    final file = '$imageDir/${floor.id}.jpg.b64';
    if (!isFloorImagePath(file)) return;
    if (!_demo) await _storage.write(file, base64Encode(jpeg));
    _images[file] = jpeg;
    floor
      ..image = file
      ..aspect = aspect;
    changed();
  }

  Future<void> removeFloor(FloorLevel floor) async {
    final file = floor.image;
    if (file != null && file.startsWith('$imageDir/') && !_demo) await _storage.delete(file);
    _images.remove(file);
    _view.floors.remove(floor);
    changed();
  }

  @visibleForTesting
  void debugReset() {
    _saveTimer?.cancel();
    _images.clear();
    _view = FloorView();
    _loaded = false;
    tooNew = false;
    _demo = false;
  }
}

/// Sample for the demo house: the ground floor with the rooms and addresses of
/// the demo project ([demoCatalog]), drawn without an image.
FloorView demoFloorView({required bool german}) {
  String t(String d, String e) => german ? d : e;
  int ga(int main, int middle, int sub) => (main << 11) | (middle << 8) | sub;
  final rooms = [
    (0, t('Wohnen', 'Living'), 0.0, 0.0, 0.55, 0.6),
    (1, t('Küche', 'Kitchen'), 0.55, 0.0, 0.45, 0.6),
    (4, t('Flur', 'Hall'), 0.0, 0.6, 0.45, 0.4),
    (5, t('Büro', 'Office'), 0.45, 0.6, 0.55, 0.4),
  ];
  var id = 1;
  final points = <FloorPoint>[];
  for (final (n, name, x, y, w, h) in rooms) {
    points
      ..add(
        FloorPoint(
          id: 'p${id++}',
          name: t('$name Licht', '$name light'),
          kind: FloorPointKind.light,
          room: name,
          x: x + w * 0.5,
          y: y + h * 0.45,
          addresses: [ga(1, 0, n), ga(1, 1, n)],
        ),
      )
      ..add(
        FloorPoint(
          id: 'p${id++}',
          name: t('$name Rollladen', '$name shutter'),
          kind: FloorPointKind.blind,
          room: name,
          x: x + w * 0.5,
          y: y < 0.3 ? y + 0.04 : y + h - 0.04,
          addresses: [ga(3, 1, n), ga(3, 0, n)],
        ),
      )
      ..add(
        FloorPoint(
          id: 'p${id++}',
          name: t('$name Temperatur', '$name temperature'),
          kind: FloorPointKind.heating,
          room: name,
          x: x + w * 0.15,
          y: y + h * 0.75,
          addresses: [ga(2, 0, n)],
        ),
      );
  }
  // One point with an address nothing sends to: shows what "silent" looks like.
  points.add(
    FloorPoint(
      id: 'p${id++}',
      name: t('Büro Steckdose', 'Office socket'),
      kind: FloorPointKind.socket,
      room: rooms.last.$2,
      x: 0.9,
      y: 0.9,
      addresses: [ga(6, 7, 250)],
    ),
  );
  return FloorView(
    floors: [
      FloorLevel(
        id: 'f1',
        name: t('Erdgeschoss', 'Ground floor'),
        aspect: 1.4,
        rooms: [for (final (_, name, x, y, w, h) in rooms) FloorArea(name, x, y, w, h)],
        points: points,
      ),
    ],
    nextId: id,
  );
}
