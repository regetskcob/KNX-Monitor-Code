import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../knx/telegram.dart';

import '../platform/storage.dart';
import 'installation.dart';

/// A comment in a recording: what happened at a point in time, attached either
/// to a telegram or to a chart, with up to [maxShots] screenshots.
/// Used for diagnostic packages and the "Fehler melden" (report a problem) message to the electrician.
class Annotation {
  Annotation({required this.id, required this.time, this.note = '', this.telegram, this.chart, List<String>? shots})
    : shots = shots ?? [];

  /// Screenshots per comment (and on the diagnostic package itself).
  static const maxShots = 3;

  final String id;

  /// Point in time within the recording.
  final DateTime time;

  /// What happened, in the user's words.
  String note;

  /// The commented telegram, if set on a telegram.
  final TelegramRef? telegram;

  /// The chart in which it was noticed, if set there.
  final ChartRef? chart;

  /// IDs of the screenshots in the [ShotStore].
  List<String> shots;

  static String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  Annotation copyWith({String? note, List<String>? shots, TelegramRef? telegram}) => Annotation(
    id: id,
    time: time,
    note: note ?? this.note,
    telegram: telegram ?? this.telegram,
    chart: chart,
    shots: [...(shots ?? this.shots)],
  );

  Map<String, Object?> toJson() => {
    'id': id,
    't': time.microsecondsSinceEpoch,
    if (note.isNotEmpty) 'note': note,
    'telegram': ?telegram?.toJson(),
    'chart': ?chart?.toJson(),
    if (shots.isNotEmpty) 'shots': shots,
  };

  factory Annotation.fromJson(Map<String, Object?> j) => Annotation(
    id: j['id']! as String,
    time: DateTime.fromMicrosecondsSinceEpoch(j['t']! as int),
    note: j['note'] as String? ?? '',
    telegram: j['telegram'] == null ? null : TelegramRef.fromJson((j['telegram']! as Map).cast()),
    chart: j['chart'] == null ? null : ChartRef.fromJson((j['chart']! as Map).cast()),
    shots: [...?(j['shots'] as List?)?.cast<String>()],
  );
}

/// A telegram as a reference: time, sender, destination and kind find it again
/// in the recording; the raw value and short form keep the comment
/// understandable without the recording (older comments in a diagnostic package).
class TelegramRef {
  const TelegramRef({
    required this.time,
    required this.source,
    required this.destination,
    required this.type,
    this.data = const [],
    this.isSmall = false,
  });

  /// Reference to a telegram, with its value.
  factory TelegramRef.of(Telegram t) => TelegramRef(
    time: t.time,
    source: t.source,
    destination: t.destination,
    type: t.type.name,
    data: [...t.data],
    isSmall: t.isSmall,
  );

  final DateTime time;
  final int source;
  final int destination;

  /// [TelegramType.name]
  final String type;

  /// Payload as in the telegram (for [isSmall], the 6-bit value in the first byte).
  final List<int> data;
  final bool isSmall;

  /// The telegram rebuilt, e.g. to decode the value.
  Telegram toTelegram() => Telegram(
    time: time,
    source: source,
    destination: destination,
    type: TelegramType.values.firstWhere((t) => t.name == type, orElse: () => TelegramType.write),
    data: Uint8List.fromList(data),
    isSmall: isSmall,
  );

  Map<String, Object?> toJson() => {
    't': time.microsecondsSinceEpoch,
    's': source,
    'd': destination,
    'type': type,
    if (data.isNotEmpty) 'data': data,
    if (isSmall) 'small': true,
  };

  factory TelegramRef.fromJson(Map<String, Object?> j) => TelegramRef(
    time: DateTime.fromMicrosecondsSinceEpoch(j['t']! as int),
    source: j['s']! as int,
    destination: j['d']! as int,
    type: j['type'] as String? ?? 'write',
    data: [...?(j['data'] as List?)?.cast<int>()],
    isSmall: j['small'] == true,
  );
}

/// A chart as a reference: the group addresses shown and the visible window.
class ChartRef {
  const ChartRef({required this.groups, required this.from, required this.to, this.values = const []});

  final List<int> groups;
  final DateTime from;
  final DateTime to;

  /// Values of the series at the comment's time, as shown then.
  final List<ChartValue> values;

  Map<String, Object?> toJson() => {
    'groups': groups,
    'from': from.microsecondsSinceEpoch,
    'to': to.microsecondsSinceEpoch,
    if (values.isNotEmpty) 'values': [for (final v in values) v.toJson()],
  };

  factory ChartRef.fromJson(Map<String, Object?> j) => ChartRef(
    groups: [...(j['groups']! as List).cast<int>()],
    from: DateTime.fromMicrosecondsSinceEpoch(j['from']! as int),
    to: DateTime.fromMicrosecondsSinceEpoch(j['to']! as int),
    values: [
      for (final v in (j['values'] as List?) ?? const [])
        if (v is Map) ChartValue.fromJson(v.cast<String, Object?>()),
    ],
  );
}

/// Value of a chart series at a comment: the one that applied then ([now]) and
/// the different one before it ([before]), as text in the app's language.
class ChartValue {
  const ChartValue({required this.group, required this.name, required this.now, this.before});

  /// Group address (or metric id) of the series.
  final int group;
  final String name;
  final String now;
  final String? before;

  Map<String, Object?> toJson() => {'g': group, 'n': name, 'v': now, 'b': ?before};

  factory ChartValue.fromJson(Map<String, Object?> j) => ChartValue(
    group: j['g'] as int? ?? 0,
    name: j['n'] as String? ?? '',
    now: j['v'] as String? ?? '',
    before: j['b'] as String?,
  );
}

/// Longest edge of a screenshot after downscaling; text stays readable.
const shotMaxEdge = 1920;

/// JPEG quality of the screenshots.
const shotQuality = 85;

/// Total screenshots in a diagnostic package.
const maxShotsPerPackage = 15;

/// Downscales an image to at most [shotMaxEdge] on the long edge and stores it
/// as JPEG ([shotQuality]). Metadata (EXIF, location) is dropped.
/// Throws [FormatException] if it is not a readable image.
Uint8List compressShot(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) throw const FormatException('image');
  final long = image.width > image.height ? image.width : image.height;
  final scaled = long <= shotMaxEdge
      ? image
      : img.copyResize(
          image,
          width: image.width >= image.height ? shotMaxEdge : null,
          height: image.height > image.width ? shotMaxEdge : null,
          interpolation: img.Interpolation.average,
        );
  return img.encodeJpg(scaled, quality: shotQuality);
}

/// [compressShot] off the UI thread (on the web in the same thread).
Future<Uint8List> compressShotAsync(Uint8List bytes) => compute(compressShot, bytes);

/// Screenshots of the comments, stored separately from the recordings
/// (otherwise the recording list would read all images on every open).
class ShotStore {
  ShotStore._();

  static final instance = ShotStore._();

  static const _dir = 'shots';
  static String _path(String id) => '$_dir/$id.jpg.b64';

  /// Only IDs in our own format (base36 like [Annotation.newId]): otherwise IDs
  /// from foreign packages end up unchecked in a file path.
  static bool validId(String id) => RegExp(r'^[0-9a-z]{1,32}$').hasMatch(id);
  AppStorage get _storage => AppStorage.instance;

  /// Space used by all screenshots in bytes (base64 in storage).
  Future<int> usedBytes() async => (await _storage.list(_dir)).fold<int>(0, (n, f) => n + f.size);

  /// Stores an already compressed JPEG under [id] (a new one if empty).
  /// Throws [ShotQuotaExceeded] when the limit is reached.
  Future<String> put(Uint8List jpeg, {String? id, bool checkQuota = true}) async {
    if (checkQuota && await usedBytes() + jpeg.length * 4 ~/ 3 > shotQuotaBytes) throw const ShotQuotaExceeded();
    final key = id ?? Annotation.newId();
    if (!validId(key)) throw ArgumentError.value(key, 'id', 'keine gültige Screenshot-ID');
    await _storage.write(_path(key), base64Encode(jpeg));
    return key;
  }

  Future<Uint8List?> read(String id) async {
    if (!validId(id)) return null;
    final text = await _storage.read(_path(id));
    return text == null ? null : base64Decode(text);
  }

  Future<void> delete(String id) async {
    if (validId(id)) await _storage.delete(_path(id));
  }
}

/// Limit for all stored screenshots combined.
const shotQuotaBytes = 100 * 1024 * 1024;

/// No more space for screenshots ([shotQuotaBytes] reached).
class ShotQuotaExceeded implements Exception {
  const ShotQuotaExceeded();
}

/// Comments on the user's own installation, independent of recordings: set in
/// everyday use on telegrams in the live list, in charts or in the timeline.
/// One file per installation; a diagnostic package includes the comments in its
/// time range. Recordings from foreign packages keep their own.
class AnnotationStore extends ChangeNotifier {
  AnnotationStore._();

  static final instance = AnnotationStore._();

  static const _path = 'annotations.json';
  AppStorage Function() storage = () => InstallationStore.instance.storage;

  List<Annotation> _all = [];
  Set<String> _telegramKeys = {};

  /// All comments, by time.
  List<Annotation> get all => List.unmodifiable(_all);

  Future<void> load() async {
    _all =
        await readStored(
          storage(),
          _path,
          (text) => [for (final a in jsonDecode(text) as List) Annotation.fromJson((a as Map).cast())],
        ) ??
        [];
    _index();
    notifyListeners();
  }

  void _index() {
    _all.sort((a, b) => a.time.compareTo(b.time));
    _telegramKeys = {
      for (final a in _all)
        if (a.telegram case final t?) telegramKey(t.time, t.source, t.destination),
    };
  }

  static String telegramKey(DateTime time, int source, int destination) =>
      '${time.microsecondsSinceEpoch}:$source:$destination';

  /// Whether the telegram has a comment (flag in the live list).
  bool hasTelegram(DateTime time, int source, int destination) =>
      _telegramKeys.contains(telegramKey(time, source, destination));

  /// Comments on a telegram.
  List<Annotation> forTelegram(DateTime time, int source, int destination) => [
    for (final a in _all)
      if (a.telegram case final t? when t.time == time && t.source == source && t.destination == destination) a,
  ];

  /// Comments in [from]…[to] (`null` = open-ended).
  List<Annotation> inRange(DateTime? from, DateTime? to) => [
    for (final a in _all)
      if ((from == null || !a.time.isBefore(from)) && (to == null || !a.time.isAfter(to))) a,
  ];

  Future<void> add(Annotation a) async {
    _all.add(a);
    await _save();
  }

  Future<void> replace(Annotation a) async {
    final i = _all.indexWhere((x) => x.id == a.id);
    if (i < 0) return;
    final removed = _all[i].shots.where((id) => !a.shots.contains(id));
    _all[i] = a;
    await _save();
    for (final id in removed) {
      await ShotStore.instance.delete(id);
    }
  }

  Future<void> remove(Annotation a) async {
    _all.removeWhere((x) => x.id == a.id);
    await _save();
    for (final id in a.shots) {
      await ShotStore.instance.delete(id);
    }
  }

  Future<void> _save() async {
    _index();
    await storage().write(_path, jsonEncode([for (final a in _all) a.toJson()]));
    notifyListeners();
  }

  @visibleForTesting
  void debugReset() {
    _all = [];
    _telegramKeys = {};
  }
}
