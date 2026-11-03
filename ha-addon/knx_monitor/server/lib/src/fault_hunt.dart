import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'watchers.dart';

/// Fault hunt on the box and the add-on: the app puts `fault_hunt.json` next
/// to the project (rules in the watcher format, duration, optionally a time
/// window such as "22–6 o'clock"). On every hit the server keeps the telegrams
/// before and after – in `hunts/<id>/`, outside the history, so that cleanup
/// by days does not delete them.
///
/// - `hunts/<id>/<start>.ndjson`: telegram lines of one window (same format
///   as the history).
/// - `hunts/<id>/hits.ndjson`: one line `{file, from, to, hits}` per window.
class FaultHunt {
  FaultHunt(this.data, {this.maxHits = 200, this.maxSpan = const Duration(minutes: 10)});

  final Directory data;

  /// At most this many hits per hunt: continuous firing does not fill the card.
  final int maxHits;

  /// A window grows with further hits at most this far.
  final Duration maxSpan;

  File get _file => File('${data.path}/fault_hunt.json');

  _Hunt? _hunt;
  DateTime? _fileTime;
  DateTime? _checked;
  int _hits = 0;

  /// Telegrams of the last [_Hunt.pre] (lead time).
  final _buffer = Queue<Map<String, Object?>>();
  _Window? _open;
  Timer? _closeTimer;

  /// Running hunt (for tests and the status).
  String? get activeId => _hunt?.id;

  Future<void> _reload(DateTime now) async {
    // Check at most every 5 s, not on every telegram.
    if (_checked case final c? when now.difference(c).abs() < const Duration(seconds: 5)) return;
    _checked = now;
    try {
      if (!await _file.exists()) {
        _hunt = null;
        _fileTime = null;
        return;
      }
      final modified = await _file.lastModified();
      if (modified == _fileTime) return;
      _fileTime = modified;
      final hunt = _Hunt.parse(jsonDecode(await _file.readAsString()) as Map<String, Object?>);
      if (hunt?.id != _hunt?.id) {
        await _flush();
        _hits = hunt == null ? 0 : await _countHits(hunt.id);
      }
      _hunt = hunt;
    } on Object catch (e) {
      stderr.writeln('fault_hunt.json: $e');
      _hunt = null;
      _fileTime = null;
    }
  }

  Future<int> _countHits(String id) async {
    final index = File('${data.path}/hunts/$id/hits.ndjson');
    if (!await index.exists()) return 0;
    var n = 0;
    for (final line in await index.readAsLines()) {
      if (line.trim().isEmpty) continue;
      n += ((jsonDecode(line) as Map)['hits'] as List? ?? const []).length;
    }
    return n;
  }

  /// Sequential processing: [add] waits for files, and a burst of telegrams
  /// must not overtake itself meanwhile.
  Future<void> _queue = Future.value();

  /// Telegram line from the bus ([now]: the box's time), in arrival order.
  Future<void> add(Map<String, Object?> line, DateTime now) =>
      _queue = _queue.then((_) => _add(line, now)).catchError((Object e) => stderr.writeln('Fehlerjagd: $e'));

  Future<void> _add(Map<String, Object?> line, DateTime now) async {
    await _reload(now);
    final hunt = _hunt;
    final open = _open;
    if (open != null) {
      open.lines.add(line);
      if (now.isAfter(open.end)) await _flush();
    }
    if (hunt == null) {
      _buffer.clear();
      return;
    }
    _buffer.add(line);
    final keep = now.subtract(hunt.pre).microsecondsSinceEpoch;
    while (_buffer.isNotEmpty && (_buffer.first['t']! as int) < keep) {
      _buffer.removeFirst();
    }
    if (!hunt.activeAt(now) || line['y'] == 0 || line['o'] == true) return;
    for (final rule in hunt.rules) {
      if (!rule.matches(line)) continue;
      _hit(hunt, line, rule.label, rule.number(line), now);
      break;
    }
  }

  void _hit(_Hunt hunt, Map<String, Object?> line, String label, double? value, DateTime now) {
    if (_hits >= maxHits) return;
    _hits++;
    final hit = {'t': line['t'], 'label': label, 'd': line['d'], 's': line['s'], 'x': line['x'], 'value': ?value};
    final open = _open;
    if (open != null && open.hunt == hunt.id) {
      open.hits.add(hit);
      final end = now.add(hunt.post);
      final limit = open.start.add(maxSpan);
      open.end = end.isAfter(limit) ? limit : end;
    } else {
      _open = _Window(hunt.id, start: now, end: now.add(hunt.post), lines: [..._buffer], hits: [hit]);
    }
    // If nothing follows, the clock closes the window.
    _closeTimer?.cancel();
    _closeTimer = Timer(
      _open!.end.difference(now) + const Duration(seconds: 1),
      () => _queue = _queue.then((_) => _flush()),
    );
  }

  /// Writes the open window (also when the server shuts down).
  Future<void> _flush() async {
    final w = _open;
    if (w == null) return;
    _open = null;
    _closeTimer?.cancel();
    try {
      final dir = Directory('${data.path}/hunts/${w.hunt}');
      await dir.create(recursive: true);
      final name = '${w.start.millisecondsSinceEpoch}.ndjson';
      await File('${dir.path}/$name').writeAsString(w.lines.map(jsonEncode).map((l) => '$l\n').join(), flush: true);
      final times = [for (final l in w.lines) l['t']! as int];
      await File('${dir.path}/hits.ndjson').writeAsString(
        '${jsonEncode({'file': name, 'from': times.isEmpty ? null : times.reduce((a, b) => a < b ? a : b), 'to': times.isEmpty ? null : times.reduce((a, b) => a > b ? a : b), 'hits': w.hits})}\n',
        mode: FileMode.append,
        flush: true,
      );
    } on Object catch (e) {
      stderr.writeln('Fehlerjagd: $e');
    }
  }

  /// On shutdown: works off the queue and writes the open window.
  Future<void> close() => _queue = _queue.then((_) => _flush());
}

class _Window {
  _Window(this.hunt, {required this.start, required this.end, required this.lines, required this.hits});
  final String hunt;
  final DateTime start;
  DateTime end;
  final List<Map<String, Object?>> lines;
  final List<Map<String, Object?>> hits;
}

typedef _HuntRule = ({
  String label,
  bool Function(Map<String, Object?> t) matches,
  double? Function(Map<String, Object?> t) number,
});

class _Hunt {
  _Hunt({
    required this.id,
    required this.until,
    required this.rules,
    required this.pre,
    required this.post,
    this.from,
    this.to,
  });

  static _Hunt? parse(Map<String, Object?> j) {
    final id = j['id'] as String?;
    final until = j['until'] as int?;
    if (id == null || until == null || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) return null;
    final rules = <_HuntRule>[
      for (final r in (j['rules'] as List? ?? const []).cast<Map<String, Object?>>()) ?parseServerRule(r),
    ];
    if (rules.isEmpty) return null;
    final window = j['window'] as List?;
    return _Hunt(
      id: id,
      until: DateTime.fromMillisecondsSinceEpoch(until),
      rules: rules,
      pre: Duration(seconds: (j['pre'] as int? ?? 120).clamp(0, 600)),
      post: Duration(seconds: (j['post'] as int? ?? 60).clamp(0, 600)),
      from: window?[0] as int?,
      to: window?[1] as int?,
    );
  }

  final String id;
  final DateTime until;
  final List<_HuntRule> rules;
  final Duration pre;
  final Duration post;

  /// Time window in minutes of the day (box local time), may span midnight
  /// (22:00–06:00 = 1320–360).
  final int? from;
  final int? to;

  bool activeAt(DateTime now) {
    if (now.isAfter(until)) return false;
    final from = this.from;
    final to = this.to;
    if (from == null || to == null || from == to) return true;
    final m = now.hour * 60 + now.minute;
    return from < to ? m >= from && m < to : m >= from || m < to;
  }
}
