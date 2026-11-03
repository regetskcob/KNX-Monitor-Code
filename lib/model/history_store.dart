import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../knx/telegram.dart';
import '../platform/addon.dart';
import '../platform/storage.dart';
import 'recording.dart';
import 'installation.dart';
import 'plan.dart';

/// A day in the long-term history.
class HistoryDay {
  const HistoryDay(this.date, this.path, this.bytes, {this.installation, this.withoutTime = false});

  /// Meaningless for [withoutTime]; never display.
  final DateTime date;

  /// Path in the [AppStorage], e.g. "history/2026-10-14.ndjson".
  final String path;
  final int bytes;

  /// Installation the day belongs to (`null` = the active one).
  final String? installation;

  /// Box recording from a start without a synchronized clock: intervals are
  /// correct, date and time are not. Therefore only appears in [HistoryStore.withoutTime].
  final bool withoutTime;
}

/// Long-term history: writes every telegram to one file per day (one JSON line
/// per telegram) and deletes days outside the retention period.
///
/// In the Home Assistant add-on the server writes and maintains the history
/// itself (even without an open browser); here only reading remains, plus the
/// settings that go to the server.
class HistoryStore extends ChangeNotifier {
  HistoryStore._();

  static final instance = HistoryStore._();

  static const _daysKey = 'history_days';
  static List<int> get choices => serverManaged ? const [0, 1, 7, 30, 90, 365] : const [0, 1, 3, 7, 14];
  static const _flushInterval = Duration(seconds: 5);

  /// The add-on server manages the history.
  static bool get serverManaged => Addon.available;

  /// Retention in days; 0 = off.
  int retentionDays = 0;
  bool get enabled => retentionDays > 0;

  /// Tier without long-term history (e.g. subscription expired): nothing new is
  /// added, existing data remains. Otherwise it would record invisibly what the user cannot see.
  bool get paused => enabled && !serverManaged && !recordingAllowed();

  @visibleForTesting
  static bool Function() recordingAllowed = () => Plan.instance.allows(Feature.longHistory);

  /// Add-on only: limit in MB and write interval in seconds (0 = immediately).
  int maxMegabytes = 1000;
  int flushSeconds = 5;
  static const sizeChoices = [250, 1000, 4000, 16000];
  static const flushChoices = [0, 5, 60, 600];

  final _buffer = <Telegram>[];
  Timer? _timer;

  static const _dir = 'history';

  /// History of the active installation.
  AppStorage get _storage => InstallationStore.instance.storage;

  static String _name(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.ndjson';

  Future<void> load() async {
    if (serverManaged) return _loadServer();
    final prefs = await SharedPreferences.getInstance();
    retentionDays = prefs.getInt(_daysKey) ?? 0;
    await _prune();
    notifyListeners();
  }

  Future<void> _loadServer() async {
    try {
      final config = ((await Addon.status())['config'] as Map?)?.cast<String, Object?>() ?? const {};
      retentionDays = config['retentionDays'] as int? ?? 7;
      maxMegabytes = config['maxMegabytes'] as int? ?? 1000;
      flushSeconds = config['flushSeconds'] as int? ?? 5;
    } on Object {
      // Older add-on without continuous recording.
    }
    notifyListeners();
  }

  /// Add-on only: settings to the server.
  Future<void> configureServer({int? retention, int? maxMegabytes, int? flushSeconds}) async {
    final status = await Addon.configure({
      'retentionDays': ?retention,
      'maxMegabytes': ?maxMegabytes,
      'flushSeconds': ?flushSeconds,
    });
    final config = (status['config'] as Map?)?.cast<String, Object?>() ?? const {};
    retentionDays = config['retentionDays'] as int? ?? retentionDays;
    this.maxMegabytes = config['maxMegabytes'] as int? ?? this.maxMegabytes;
    this.flushSeconds = config['flushSeconds'] as int? ?? this.flushSeconds;
    notifyListeners();
  }

  Future<void> setRetention(int days) async {
    if (serverManaged) return configureServer(retention: days);
    retentionDays = days;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_daysKey, days);
    if (!enabled) _buffer.clear();
    await _prune();
    notifyListeners();
  }

  /// At most this many wait in memory when nothing can be written.
  static const _maxPending = 50000;

  /// Queues a telegram; writing happens in batches every few seconds.
  void add(Telegram t) {
    if (!enabled || serverManaged || paused) return;
    _buffer.add(t);
    _timer ??= Timer(_flushInterval, flush);
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_buffer.isEmpty) return;
    final pending = List.of(_buffer);
    _buffer.clear();
    // Group by day (midnight can fall within a batch).
    final byDay = <String, StringBuffer>{};
    for (final t in pending) {
      (byDay[_name(t.time)] ??= StringBuffer()).writeln(jsonEncode(t.toJson()));
    }
    try {
      for (final MapEntry(key: name, value: lines) in byDay.entries) {
        await _storage.append('$_dir/$name', lines.toString());
      }
    } on Object catch (e) {
      // Disk full, keychain disrupted: do not discard, try again later. Whole
      // batches, so no duplicates except for the day already written.
      debugPrint('Verlauf: nicht geschrieben: $e');
      _buffer.insertAll(0, pending);
      if (_buffer.length > _maxPending) _buffer.removeRange(0, _buffer.length - _maxPending);
      _timer ??= Timer(_flushInterval * 6, flush);
    }
    notifyListeners();
  }

  /// Saved days, newest first – of the active installation or of [installation]
  /// (e.g. the week at a previous customer's, without switching the box).
  Future<List<HistoryDay>> days({String? installation}) async {
    final result = <HistoryDay>[];
    for (final f in await _files(installation)) {
      if (!f.name.endsWith('.ndjson')) continue;
      final date = DateTime.tryParse(f.name.replaceAll('.ndjson', ''));
      if (date != null) result.add(HistoryDay(date, '$_dir/${f.name}', f.size, installation: installation));
    }
    return result..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Sections of the box without a synchronized clock (`unsynced-…`), newest file first.
  Future<List<HistoryDay>> withoutTime({String? installation}) async {
    final found = [
      for (final f in await _files(installation))
        if (RegExp(r'^unsynced-\d+(-\d+)?\.ndjson$').hasMatch(f.name))
          HistoryDay(DateTime(0), '$_dir/${f.name}', f.size, installation: installation, withoutTime: true),
    ];
    return found..sort((a, b) => b.path.compareTo(a.path));
  }

  Future<List<StoredFile>> _files(String? installation) async {
    final id = installation ?? InstallationStore.instance.active.id;
    // Via the KNX box: its history, not the (empty) one on this device.
    return Addon.box != null
        ? [
            for (final f in (await _boxFiles(id)).cast<Map<Object?, Object?>>())
              (name: f['name']! as String, size: (f['size'] as num?)?.toInt() ?? 0),
          ]
        : await _storageOf(installation).list(_dir);
  }

  /// Storage of an installation other than the active one.
  AppStorage _storageOf(String? installation) =>
      installation == null || kIsWeb ? _storage : ScopedStorage(AppStorage.instance, 'installations/$installation/');

  /// History on the box; older boxes do not know installations.
  Future<List<Object?>> _boxFiles(String installation) async {
    try {
      return await Addon.listInstallationFiles(installation, _dir);
    } on AddonException {
      return Addon.listFiles(_dir);
    }
  }

  Future<List<int>?> _boxFile(HistoryDay day) async {
    final id = day.installation ?? InstallationStore.instance.active.id;
    try {
      return await Addon.getInstallationFile(id, day.path);
    } on AddonException {
      return Addon.getFile(day.path);
    }
  }

  /// Opens a day as a recording (for all views, playback, export).
  Future<Recording> open(HistoryDay day, {required String name}) async {
    final telegrams = <Telegram>[];
    int? firstMono;
    int? firstTime;
    final text = Addon.box != null
        ? utf8.decode(await _boxFile(day) ?? const [], allowMalformed: true)
        : await _storageOf(day.installation).read(day.path) ?? '';
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty) continue;
      try {
        final json = jsonDecode(line) as Map<String, Object?>;
        // Without a clock: the monotonic counter gives the intervals, the system time can jump.
        final mono = json['mono'];
        if (day.withoutTime && mono is int) {
          firstMono ??= mono;
          firstTime ??= json['t'] as int? ?? 0;
          json['t'] = firstTime + mono - firstMono;
        }
        telegrams.add(Telegram.fromJson(json));
      } on Object {
        // Skip a truncated or foreign line (app quit, older format) instead of making
        // the whole day unreadable.
      }
    }
    telegrams.sort((a, b) => a.time.compareTo(b.time));
    return Recording(
      id: day.withoutTime ? 'history-${day.path.split('/').last}' : 'history-${_name(day.date)}',
      name: name,
      started: telegrams.isEmpty ? day.date : telegrams.first.time,
      ended: telegrams.isEmpty ? day.date : telegrams.last.time,
      telegrams: telegrams,
    );
  }

  /// Delete only on this device: the box's server maintains its history
  /// (retention); otherwise the list would come from the box and deletion would happen here.
  bool get canDelete => Addon.box == null;

  Future<void> deleteAll({String? installation}) async {
    if (!canDelete) return;
    for (final d in await days(installation: installation)) {
      await _storageOf(installation).delete(d.path);
    }
    notifyListeners();
  }

  Future<void> delete(HistoryDay day) async {
    if (!canDelete) return;
    await _storageOf(day.installation).delete(day.path);
    notifyListeners();
  }

  /// Removes days outside the retention period (when "off": all).
  Future<void> _prune() async {
    // Paused: the days remain until the tier fits again.
    if (serverManaged || paused) return;
    final today = DateTime.now();
    final cutoff = DateTime(today.year, today.month, today.day).subtract(Duration(days: retentionDays - 1));
    for (final d in await days()) {
      if (!enabled || d.date.isBefore(cutoff)) await _storage.delete(d.path);
    }
  }
}
