import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'recorder.dart';

/// Bus view on the floor plan for the dashboard card "Busclear Grundriss"
/// (`custom:knx-monitor-floor-card`) and the app in the browser.
///
/// The app stores the view as `floor_view.json` in the installation's folder
/// (format `busclear-floor-view`, see `lib/model/floor_view.dart` of the
/// app): levels with an optional image, room outlines and points with their
/// group addresses. This service reads the file defensively, adds when each
/// address was last on the bus (live since the start, before that from the
/// recorded history) and serves the images. Read-only: nothing here writes a
/// file or sends to the bus.
class FloorViewService {
  FloorViewService({this.historyDays = 7, DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// How far back the history is searched for the last telegram of an address.
  final int historyDays;
  final DateTime Function() _now;

  static const fileName = 'floor_view.json';
  static const format = 'busclear-floor-view';
  static const formatVersion = 1;

  /// Limits, the same as in the app: a file from elsewhere must not grow the answer.
  static const maxFileBytes = 2 * 1024 * 1024;
  static const maxFloors = 24;
  static const maxPoints = 600;
  static const maxRooms = 200;
  static const maxAddresses = 12;
  static const maxText = 80;

  /// Largest image served (base64 text in the file, about 6 MB of JPEG).
  static const maxImageFileBytes = 8 * 1024 * 1024;

  /// Images lie in one of the two image folders of the app, under a generated
  /// name. Nothing else is ever opened, whatever the file says.
  static final imagePath = RegExp(r'^(home_plan_images|floor_view_images)/[0-9a-z]{1,32}\.jpg\.b64$');

  /// Last telegram per group address in milliseconds, of the installation in [_root].
  final _last = <int, int>{};
  String? _root;
  late int _since = _now().millisecondsSinceEpoch;

  /// Addresses whose history has been read, and the one scan that may run at a time.
  final _seeded = <int>{};
  Future<void>? _seeding;

  /// Counts up with every change of installation: a running scan of the old one stops.
  var _generation = 0;

  /// Everything known belongs to one installation. Another one starts empty: other addresses,
  /// another history, and never the times of the previous one.
  void _enter(String root) {
    if (_root == root) return;
    _root = root;
    _generation++;
    _last.clear();
    _seeded.clear();
    _seeding = null;
    _images.clear();
    _since = _now().millisecondsSinceEpoch;
  }

  /// Every recorded group telegram (history line) of the installation in [root]. Cheap: one map
  /// entry. Reads are questions, not a sign of life.
  void observe(Map<String, Object?> line, {required String root}) {
    _enter(root);
    final address = line['d'];
    final time = line['t'];
    if (address is! int || time is! int || line['y'] == 0) return;
    final ms = time ~/ 1000;
    if (ms > (_last[address] ?? 0)) _last[address] = ms;
  }

  static String _text(Object? value) {
    if (value is! String) return '';
    final clean = value.replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), ' ').trim();
    return clean.length > maxText ? clean.substring(0, maxText) : clean;
  }

  static double _unit(Object? value, double fallback) {
    final v = value is num ? value.toDouble() : fallback;
    return v.isFinite ? v.clamp(0.0, 1.0) : fallback;
  }

  /// The view of [json] with only the known fields, in the known types and within the limits;
  /// `null` if it is not a floor view this server understands.
  static List<Map<String, Object?>>? sanitize(Object? json) {
    if (json is! Map || json['format'] != format) return null;
    final version = json['version'];
    if (version is! int || version < 1 || version > formatVersion) return null;
    final floors = json['floors'];
    if (floors is! List) return const [];
    var points = 0;
    return [
      for (final f in floors.take(maxFloors))
        if (f is Map)
          {
            'id': _text(f['id']),
            'name': _text(f['name']),
            'aspect': switch (f['aspect']) {
              final num a when a.isFinite => a.toDouble().clamp(0.2, 5.0),
              _ => 1.5,
            },
            'image': f['image'] is String && imagePath.hasMatch(f['image'] as String),
            'rooms': [
              for (final r in (f['rooms'] is List ? f['rooms'] as List : const <Object?>[]).take(maxRooms))
                if (r is Map)
                  {
                    'name': _text(r['name']),
                    'x': _unit(r['x'], 0),
                    'y': _unit(r['y'], 0),
                    'w': _unit(r['w'], 0.2),
                    'h': _unit(r['h'], 0.2),
                  },
            ],
            'points': [
              for (final p in f['points'] is List ? f['points'] as List : const <Object?>[])
                if (p is Map && points++ < maxPoints)
                  {
                    'id': _text(p['id']),
                    'name': _text(p['name']),
                    'kind': _text(p['kind']),
                    'room': _text(p['room']),
                    'x': _unit(p['x'], 0.5),
                    'y': _unit(p['y'], 0.5),
                    'addresses': [
                      for (final a in (p['addresses'] is List ? p['addresses'] as List : const <Object?>[]).take(
                        maxAddresses,
                      ))
                        if (a is int && a > 0 && a <= 0xFFFF) a,
                    ],
                  },
            ],
          },
    ];
  }

  static Future<Object?> _read(Directory root) async {
    final file = File('${root.path}/$fileName');
    try {
      if (!await file.exists() || await file.length() > maxFileBytes) return null;
      return jsonDecode(await file.readAsString());
    } on Object catch (e) {
      stderr.writeln('$fileName: $e');
      return null;
    }
  }

  /// The view of the installation in [root] with the last telegram per linked address
  /// (`last`: address → milliseconds) and since when the bus is known (`since`).
  Future<Map<String, Object?>> describe(Directory root, Recorder recorder) async {
    final now = _now().millisecondsSinceEpoch;
    _enter(root.path);
    final floors = sanitize(await _read(root));
    if (floors == null) {
      return {'available': false, 'floors': const <Object?>[], 'last': const <String, int>{}, 'now': now};
    }
    final addresses = <int>{
      for (final f in floors)
        for (final p in f['points']! as List) ...((p as Map)['addresses']! as List).cast<int>(),
    };
    // Only what is missing is read, and only one scan runs at a time; what a scan started
    // meanwhile does not cover is picked up by the next request.
    final missing = addresses.difference(_seeded);
    if (missing.isNotEmpty) _seeding ??= _seed(recorder, missing, _generation);
    return {
      'available': true,
      'floors': floors,
      'last': {
        for (final a in addresses)
          if (_last[a] case final t?) '$a': t,
      },
      'since': _since,
      'now': now,
      if (_seeding != null) 'loading': true,
    };
  }

  /// Lines between two pauses of a scan: the event loop serves requests in between.
  static const _slice = 2000;

  /// Fills [_last] for [addresses] from the recorded days, in slices, and stops when the
  /// installation changes ([generation]). Requests meanwhile answer with what is known
  /// (`loading`).
  Future<void> _seed(Recorder recorder, Set<int> addresses, int generation) async {
    bool current() => generation == _generation;
    try {
      await recorder.flush();
      final today = _now();
      int? earliest;
      var read = 0;
      days:
      for (var back = 0; back < historyDays; back++) {
        final day = DateTime(today.year, today.month, today.day - back);
        final lines = await recorder.dayLines(Recorder.dayName(day));
        if (!current()) return;
        if (lines == null) continue;
        earliest = day.millisecondsSinceEpoch;
        await for (final line in lines) {
          if (++read % _slice == 0) {
            await Future<void>.delayed(Duration.zero);
            if (!current()) break days;
          }
          final address = int.tryParse(Recorder.field(line, 'd') ?? '');
          if (address == null || !addresses.contains(address) || Recorder.field(line, 'y') == '0') continue;
          final time = int.tryParse(Recorder.field(line, 't') ?? '');
          if (time == null) continue;
          final ms = time ~/ 1000;
          if (ms > (_last[address] ?? 0)) _last[address] = ms;
        }
      }
      if (!current()) return;
      if (earliest != null && earliest < _since) _since = earliest;
      _seeded.addAll(addresses);
    } on Object catch (e) {
      stderr.writeln('Busansicht: Verlauf nicht lesbar: $e');
      if (current()) _seeded.addAll(addresses); // Not again on every request.
    } finally {
      if (current()) _seeding = null;
    }
  }

  /// Decoded images by path, valid while the file keeps its time and size. At most
  /// [maxCachedImages], so a plan with many levels does not stay in memory.
  final _images = <String, ({DateTime modified, int size, List<int> bytes, String etag})>{};
  static const maxCachedImages = 4;

  /// One decode at a time: each holds the base64 text and the bytes of an image.
  Future<void> _decoding = Future.value();

  /// JPEG of the level [floorId] with its ETag, or `null`: no such level, no image, a path
  /// outside the image folders, too large or not a JPEG.
  Future<({List<int> bytes, String etag})?> image(Directory root, String floorId) async {
    _enter(root.path);
    final json = await _read(root);
    if (json is! Map || json['floors'] is! List) return null;
    for (final f in (json['floors'] as List).take(maxFloors)) {
      if (f is! Map || f['id'] != floorId) continue;
      final path = f['image'];
      if (path is! String || !imagePath.hasMatch(path)) return null;
      final file = File('${root.path}/$path');
      final previous = _decoding;
      final done = Completer<void>();
      _decoding = done.future;
      try {
        await previous;
        if (!await file.exists()) return null;
        final stat = await file.stat();
        if (stat.size > maxImageFileBytes) return null;
        final cached = _images[path];
        if (cached != null && cached.modified == stat.modified && cached.size == stat.size) {
          return (bytes: cached.bytes, etag: cached.etag);
        }
        final bytes = base64Decode((await file.readAsString()).trim());
        if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8 || bytes[2] != 0xFF) return null;
        final etag = '"${stat.modified.millisecondsSinceEpoch.toRadixString(36)}-${stat.size.toRadixString(36)}"';
        _images.remove(path);
        while (_images.length >= maxCachedImages) {
          _images.remove(_images.keys.first);
        }
        _images[path] = (modified: stat.modified, size: stat.size, bytes: bytes, etag: etag);
        return (bytes: bytes, etag: etag);
      } on Object catch (e) {
        stderr.writeln('$path: $e');
        return null;
      } finally {
        done.complete();
      }
    }
    return null;
  }

  /// Serves `GET /api/floor-view` and `GET /api/floor-view/image?floor=<id>`.
  Future<void> serve(HttpRequest request, Directory root, Recorder recorder) async {
    final response = request.response;
    if (request.method != 'GET') {
      response.statusCode = HttpStatus.methodNotAllowed;
      return response.close();
    }
    if (request.uri.path == '/api/floor-view') {
      response.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.cacheControlHeader, 'no-store');
      response.write(jsonEncode(await describe(root, recorder)));
      return response.close();
    }
    final image = await this.image(root, request.uri.queryParameters['floor'] ?? '');
    if (image == null) {
      response.statusCode = HttpStatus.notFound;
      return response.close();
    }
    response.headers
      ..set(HttpHeaders.etagHeader, image.etag)
      ..set(HttpHeaders.cacheControlHeader, 'private, max-age=300');
    if (request.headers.value(HttpHeaders.ifNoneMatchHeader) == image.etag) {
      response.statusCode = HttpStatus.notModified;
      return response.close();
    }
    response.headers
      ..contentType = ContentType('image', 'jpeg')
      ..set('X-Content-Type-Options', 'nosniff');
    response.add(image.bytes);
    return response.close();
  }
}
