import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../platform/storage.dart';
import 'alarms.dart';
import 'annotation.dart';
import 'telegram_log.dart';

/// A saved recording of bus traffic for documentation.
class Recording {
  Recording({
    required this.id,
    required this.name,
    required this.started,
    required this.ended,
    required this.telegrams,
    this.note,
    this.gateway,
    this.project,
    this.installation,
    List<Annotation>? annotations,
    this.diagnostics,
  }) : annotations = annotations ?? [];

  final String id;
  String name;
  String? note;
  final DateTime started;
  final DateTime ended;

  /// E.g. "Gira X1 · 192.168.1.22".
  final String? gateway;
  final String? project;

  /// ID of the installation in which it was recorded (older recordings: `null`).
  final String? installation;
  final List<Telegram> telegrams;

  /// Comments at points in time, on telegrams or charts, by time.
  final List<Annotation> annotations;

  /// Opened from a diagnostic package: problem description, technical details and
  /// log for the findings (`problem`, `expected`, `occurred`, `technical`, `log`, `shots`).
  final Map<String, Object?>? diagnostics;

  Duration get duration => ended.difference(started);

  /// New recording (own ID) with the same key data, e.g. an edited version; the
  /// original stays unchanged.
  Recording copyWith({String? name, List<Telegram>? telegrams}) => Recording(
    id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
    name: name ?? this.name,
    note: note,
    started: started,
    ended: ended,
    gateway: gateway,
    project: project,
    installation: installation,
    telegrams: List.of(telegrams ?? this.telegrams),
    annotations: [for (final a in annotations) a.copyWith()],
    diagnostics: diagnostics,
  );

  Map<String, Object?> toJson() => {
    'v': 1,
    'id': id,
    'name': name,
    'note': note,
    'started': started.microsecondsSinceEpoch,
    'ended': ended.microsecondsSinceEpoch,
    'gateway': gateway,
    'project': project,
    'installation': ?installation,
    'telegrams': [for (final t in telegrams) t.toJson()],
    if (annotations.isNotEmpty) 'annotations': [for (final a in annotations) a.toJson()],
    'diagnostics': ?diagnostics,
  };

  factory Recording.fromJson(Map<String, Object?> j) => Recording(
    id: j['id']! as String,
    name: j['name']! as String,
    note: j['note'] as String?,
    started: DateTime.fromMicrosecondsSinceEpoch(j['started']! as int),
    ended: DateTime.fromMicrosecondsSinceEpoch(j['ended']! as int),
    gateway: j['gateway'] as String?,
    project: j['project'] as String?,
    installation: j['installation'] as String?,
    telegrams: [for (final t in j['telegrams']! as List) Telegram.fromJson(t as Map<String, Object?>)],
    annotations: [for (final a in (j['annotations'] as List?) ?? const []) Annotation.fromJson((a as Map).cast())]
      ..sort((a, b) => a.time.compareTo(b.time)),
    diagnostics: (j['diagnostics'] as Map?)?.cast<String, Object?>(),
  );
}

/// Header data of a recording for the list (without loading telegrams).
class RecordingSummary {
  const RecordingSummary({
    required this.id,
    required this.name,
    required this.started,
    required this.ended,
    required this.count,
    this.note,
    this.gateway,
    this.project,
    this.installation,
    this.annotations = 0,
    this.diagnostics = false,
  });

  final String id;
  final String name;
  final String? note;
  final DateTime started;
  final DateTime ended;
  final int count;
  final String? gateway;
  final String? project;
  final String? installation;

  /// Number of comments.
  final int annotations;

  /// Whether it comes from a diagnostic package.
  final bool diagnostics;

  Duration get duration => ended.difference(started);
}

/// Running recording: collects telegrams until [stop] returns a [Recording].
class Recorder {
  Recorder({this.gateway, this.project, this.installation, DateTime? started}) : started = started ?? DateTime.now();

  final DateTime started;
  final String? gateway;
  final String? project;
  final String? installation;
  final telegrams = <Telegram>[];

  /// Comments set during the recording ("Jetzt ist es passiert", it just happened).
  final annotations = <Annotation>[];

  Recording stop({required String name, String? note}) => Recording(
    id: started.microsecondsSinceEpoch.toRadixString(36),
    name: name,
    note: note,
    started: started,
    ended: DateTime.now(),
    gateway: gateway,
    project: project,
    installation: installation,
    telegrams: List.of(telegrams),
    annotations: List.of(annotations),
  );
}

/// Recording as a [TelegramLog] for the shared views.
class RecordingLog extends TelegramLog {
  RecordingLog(this.recording) {
    addAll(recording.telegrams);
  }

  final Recording recording;

  /// Playback position (absolute time); `null` = whole recording.
  DateTime? playhead;

  @override
  DateTime get clock => playhead ?? recording.ended;

  static const _bins = 60;

  /// Distribution of telegrams over the recording duration in 60 segments.
  @override
  List<int> get activityBins {
    final bins = List.filled(_bins, 0);
    final span = recording.duration.inMicroseconds;
    if (span <= 0) return bins;
    // From the displayed telegrams – fills up during playback.
    for (final t in log) {
      final i = (t.time.difference(recording.started).inMicroseconds * _bins ~/ span).clamp(0, _bins - 1);
      bins[i]++;
    }
    return bins;
  }

  @override
  List<int> get alarmBins {
    final bins = List.filled(_bins, 0);
    final span = recording.duration.inMicroseconds;
    if (span <= 0) return bins;
    for (final t in log) {
      if (activeAlarm(t) == null) continue;
      bins[(t.time.difference(recording.started).inMicroseconds * _bins ~/ span).clamp(0, _bins - 1)]++;
    }
    return bins;
  }

  @override
  String get activityLabel => s.activityOverRecording;
}

/// Stores recordings as JSON files in the app directory.
class RecordingStore extends ChangeNotifier {
  RecordingStore._();

  static final instance = RecordingStore._();

  List<RecordingSummary> summaries = [];

  static const _dir = 'recordings';
  static String _path(String id) => '$_dir/$id.json';
  AppStorage get _storage => AppStorage.instance;

  /// Loads the header data of all recordings, newest first.
  Future<void> load() async {
    final result = <RecordingSummary>[];
    for (final f in await _storage.list(_dir)) {
      if (!f.name.endsWith('.json')) continue;
      try {
        final json = await _storage.read('$_dir/${f.name}');
        if (json != null) result.add(_summary(Recording.fromJson(jsonDecode(json) as Map<String, Object?>)));
      } on Object catch (e) {
        debugPrint('Aufnahme ${f.name} nicht lesbar: $e');
      }
    }
    summaries = result..sort((a, b) => b.started.compareTo(a.started));
    notifyListeners();
  }

  /// Number of saved recordings, without reading them.
  Future<int> count() async => (await _storage.list(_dir)).where((f) => f.name.endsWith('.json')).length;

  Future<Recording> open(String id) async =>
      Recording.fromJson(jsonDecode((await _storage.read(_path(id)))!) as Map<String, Object?>);

  Future<void> save(Recording r) async {
    await _storage.write(_path(r.id), jsonEncode(r.toJson()));
    summaries = [_summary(r), ...summaries.where((s) => s.id != r.id)]..sort((a, b) => b.started.compareTo(a.started));
    notifyListeners();
  }

  Future<void> delete(String id) async {
    // Also remove the screenshots of the comments and of a diagnostic package.
    try {
      final r = await open(id);
      for (final shot in {
        for (final a in r.annotations) ...a.shots,
        ...?(r.diagnostics?['shots'] as List?)?.cast<String>(),
      }) {
        await ShotStore.instance.delete(shot);
      }
    } on Object catch (e) {
      debugPrint('Screenshots der Aufnahme $id nicht entfernt: $e');
    }
    await _storage.delete(_path(id));
    summaries = summaries.where((s) => s.id != id).toList();
    notifyListeners();
  }

  static RecordingSummary _summary(Recording r) => RecordingSummary(
    id: r.id,
    name: r.name,
    note: r.note,
    started: r.started,
    ended: r.ended,
    count: r.telegrams.length,
    gateway: r.gateway,
    project: r.project,
    installation: r.installation,
    annotations: r.annotations.length,
    diagnostics: r.diagnostics != null,
  );
}

/// Plays a recording into its [RecordingLog] in real time.
///
/// Without playback the log shows the complete recording. [seek] builds the
/// state up to the chosen position, [play] continues feeding from there – at
/// a selectable speed.
class RecordingPlayer extends ChangeNotifier {
  RecordingPlayer(this.log) : position = log.recording.duration;

  static const speeds = [1.0, 2.0, 5.0, 10.0, 30.0, 60.0];

  final RecordingLog log;
  Duration position;
  double speed = 1;
  bool get playing => _timer != null;

  Timer? _timer;
  DateTime _lastTick = DateTime(0);
  List<int>? _density;
  int _next = 0;

  Recording get _r => log.recording;
  Duration get duration => _r.duration;

  /// Telegrams per segment over the whole recording ([bins] equally long
  /// segments) – for the progress bar in the player.
  /// Counted once: the recording does not change during playback.
  List<int> density(int bins) {
    if (_density case final cached? when cached.length == bins) return cached;
    final counts = _density = List.filled(bins, 0);
    final total = duration.inMicroseconds;
    if (total <= 0) return counts;
    for (final t in _telegrams) {
      final i = (t.time.difference(_r.started).inMicroseconds * bins ~/ total).clamp(0, bins - 1);
      counts[i]++;
    }
    return counts;
  }

  List<Telegram> get _telegrams => _r.telegrams;

  void play() {
    if (playing) return;
    if (position >= duration) seek(Duration.zero);
    _lastTick = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 40), (_) => _tick());
    notifyListeners();
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  void toggle() => playing ? pause() : play();

  /// Jumps to [to]: the log then shows all telegrams up to this point.
  void seek(Duration to) {
    position = to < Duration.zero ? Duration.zero : (to > duration ? duration : to);
    final end = _r.started.add(position);
    log.playhead = end;
    _next = _telegrams.indexWhere((t) => t.time.isAfter(end));
    if (_next < 0) _next = _telegrams.length;
    log
      ..clear()
      ..addAll(_telegrams.take(_next));
    notifyListeners();
  }

  void cycleSpeed() {
    speed = speeds[(speeds.indexOf(speed) + 1) % speeds.length];
    notifyListeners();
  }

  void _tick() {
    final now = DateTime.now();
    position += (now.difference(_lastTick)) * speed;
    _lastTick = now;
    final end = _r.started.add(position);
    log.playhead = end;
    while (_next < _telegrams.length && !_telegrams[_next].time.isAfter(end)) {
      log.add(_telegrams[_next++]);
    }
    if (position >= duration) {
      position = duration;
      log.playhead = null;
      pause();
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
