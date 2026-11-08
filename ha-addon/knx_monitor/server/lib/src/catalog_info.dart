import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pointycastle/digests/sha256.dart';

/// What the telegram stream (issue #11) needs from the ETS project of an
/// installation (`catalog.json` in its data folder): device names by
/// individual address and the project state ([project]).
///
/// The catalog carries no project id or date of its own, so [project] is a
/// short hash of the file plus its modification time: a new upload gives a
/// new id. Callers on the telegram path read the cached values only; [poll]
/// checks the file's modification time at most every [every] in the
/// background and rereads it only when it changed.
class CatalogInfo {
  CatalogInfo({this.every = const Duration(seconds: 10), DateTime Function() clock = DateTime.now}) : _clock = clock;

  final Duration every;
  final DateTime Function() _clock;

  String? _path;
  DateTime? _modified;
  DateTime? _checked;
  Future<void>? _loading;
  Map<int, String> _devices = const {};
  Map<String, Object?>? _project;

  /// `{id, date}` of the loaded catalog; `null` without one (or before the
  /// first [poll] finished). `id`: first 8 hex characters of the SHA-256 of
  /// `catalog.json`; `date`: its modification time, ISO 8601 UTC.
  Map<String, Object?>? get project => _project;

  /// Device name from the ETS project; `null` if unknown or empty.
  String? deviceName(int individual) => _devices[individual];

  /// Checks [folder] (the active installation's data folder) for a changed
  /// catalog, at most every [every] unless the folder changed. Never throws;
  /// the result applies to later telegrams.
  void poll(Directory folder) {
    final path = '${folder.path}/catalog.json';
    final now = _clock();
    if (path == _path && _checked != null && now.difference(_checked!) < every) return;
    if (_loading != null) return;
    if (path != _path) {
      // Other installation: its project, not the old one, even while loading.
      _path = path;
      _modified = null;
      _devices = const {};
      _project = null;
    }
    _checked = now;
    _loading = _load(File(path)).whenComplete(() => _loading = null);
  }

  /// Waits for a [poll] in progress (tests, start).
  Future<void> get ready => _loading ?? Future.value();

  Future<void> _load(File file) async {
    try {
      if (!await file.exists()) {
        _modified = null;
        _devices = const {};
        _project = null;
        return;
      }
      final modified = await file.lastModified();
      if (modified == _modified) return;
      final bytes = await file.readAsBytes();
      final json = jsonDecode(utf8.decode(bytes));
      final devices = <int, String>{};
      if (json is Map<String, Object?>) {
        for (final d in (json['devices'] as List? ?? const []).whereType<Map<String, Object?>>()) {
          if ((d['a'], d['n']) case (final int a, final String n) when n.trim().isNotEmpty) devices[a] = n;
        }
      }
      final hash = SHA256Digest().process(bytes);
      if (file.path != _path) return; // switched meanwhile
      _modified = modified;
      _devices = devices;
      _project = {
        'id': [for (final b in hash.take(4)) b.toRadixString(16).padLeft(2, '0')].join(),
        'date': '${modified.toUtc().toIso8601String().split('.').first}Z',
      };
    } on Object {
      // Unreadable (perhaps being written): try again on the next poll.
      _modified = null;
    }
  }
}
