import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../platform/addon.dart';
import 'annotation.dart';
import 'installation.dart';
import 'recording.dart';
import 'box_keyring_consent.dart';
import 'watch_rules.dart';

/// A fault hunt: rules (from the watchers), duration and an optional time
/// window. The box or add-on checks them around the clock and, on every hit,
/// keeps the telegrams before and after it (see
/// `server/lib/src/fault_hunt.dart`).
@immutable
class FaultHuntDef {
  const FaultHuntDef({
    required this.id,
    required this.name,
    required this.created,
    required this.until,
    required this.rules,
    this.pre = const Duration(minutes: 2),
    this.post = const Duration(minutes: 1),
    this.from,
    this.to,
  });

  /// From watcher rules that the server can check ([WatchRule.serverCheck]).
  factory FaultHuntDef.fromWatchers(
    List<WatchRule> watchers, {
    required String name,
    required Duration duration,
    int? from,
    int? to,
    DateTime? now,
  }) {
    final start = now ?? DateTime.now();
    return FaultHuntDef(
      id: start.millisecondsSinceEpoch.toRadixString(36),
      name: name,
      created: start,
      until: start.add(duration),
      from: from,
      to: to,
      rules: [
        for (final w in watchers)
          if (w.serverCheck() case final check?)
            {'id': w.id, 'address': w.address, 'label': w.describe(), 'check': check},
      ],
    );
  }

  final String id;
  final String name;
  final DateTime created;
  final DateTime until;
  final List<Map<String, Object?>> rules;
  final Duration pre;
  final Duration post;

  /// Time window in minutes of the day (box local time), also across midnight.
  final int? from;
  final int? to;

  bool get hasWindow => from != null && to != null && from != to;
  bool activeAt(DateTime now) => now.isBefore(until);

  /// Stopped: the duration ends now, hits remain.
  FaultHuntDef stopped(DateTime now) => FaultHuntDef(
    id: id,
    name: name,
    created: created,
    until: now,
    rules: rules,
    pre: pre,
    post: post,
    from: from,
    to: to,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'created': created.millisecondsSinceEpoch,
    'until': until.millisecondsSinceEpoch,
    'pre': pre.inSeconds,
    'post': post.inSeconds,
    if (hasWindow) 'window': [from, to],
    'rules': rules,
  };

  factory FaultHuntDef.fromJson(Map<String, Object?> j) {
    final window = j['window'] as List?;
    return FaultHuntDef(
      id: j['id']! as String,
      name: j['name'] as String? ?? '',
      created: DateTime.fromMillisecondsSinceEpoch(j['created'] as int? ?? 0),
      until: DateTime.fromMillisecondsSinceEpoch(j['until']! as int),
      pre: Duration(seconds: j['pre'] as int? ?? 120),
      post: Duration(seconds: j['post'] as int? ?? 60),
      from: window?[0] as int?,
      to: window?[1] as int?,
      rules: [for (final r in (j['rules'] as List? ?? const [])) (r as Map).cast<String, Object?>()],
    );
  }
}

/// A hit: which rule, when, who sent.
@immutable
class HuntHit {
  const HuntHit({required this.time, required this.label, required this.destination, required this.source, this.value});

  factory HuntHit.fromJson(Map<String, Object?> j) => HuntHit(
    time: DateTime.fromMicrosecondsSinceEpoch(j['t']! as int),
    label: j['label'] as String? ?? '',
    destination: j['d']! as int,
    source: j['s']! as int,
    value: (j['value'] as num?)?.toDouble(),
  );

  final DateTime time;
  final String label;
  final int destination;
  final int source;
  final double? value;
}

/// A captured window with one or more hits.
@immutable
class HuntWindow {
  const HuntWindow({required this.file, required this.hits, this.from, this.to});

  factory HuntWindow.fromJson(Map<String, Object?> j) => HuntWindow(
    file: j['file']! as String,
    from: j['from'] == null ? null : DateTime.fromMicrosecondsSinceEpoch(j['from']! as int),
    to: j['to'] == null ? null : DateTime.fromMicrosecondsSinceEpoch(j['to']! as int),
    hits: [for (final h in (j['hits'] as List? ?? const [])) HuntHit.fromJson((h as Map).cast<String, Object?>())],
  );

  final String file;
  final DateTime? from;
  final DateTime? to;
  final List<HuntHit> hits;
}

/// Who sent in all hits, most frequent first – "always the same sender" is often
/// the answer already.
List<(int source, int count)> huntSenders(List<HuntWindow> windows) {
  final counts = <int, int>{};
  for (final w in windows) {
    for (final h in w.hits) {
      counts[h.source] = (counts[h.source] ?? 0) + 1;
    }
  }
  return [for (final e in counts.entries) (e.key, e.value)]..sort((a, b) => b.$2.compareTo(a.$2));
}

/// Fault hunt on the paired box or in the add-on: store the definition, read
/// hits and windows, adopt a window as a recording.
class FaultHuntClient {
  const FaultHuntClient();

  static const path = 'fault_hunt.json';

  Future<String?> _read(String file) async {
    if (Addon.box != null) {
      final bytes = await Addon.getFile(file);
      return bytes == null ? null : utf8.decode(bytes);
    }
    return InstallationStore.instance.storage.read(file);
  }

  Future<void> _write(String file, String text) async {
    if (Addon.box case final box?) {
      // A box paired through a foreign link gets nothing before the user agreed.
      if (!await BoxProjectConsent.allowed(box)) return;
      return Addon.putFile(file, utf8.encode(text));
    }
    await InstallationStore.instance.storage.write(file, text);
  }

  /// Most recently created hunt (running or stopped), otherwise `null`.
  Future<FaultHuntDef?> current() async {
    try {
      final text = await _read(path);
      return text == null ? null : FaultHuntDef.fromJson(jsonDecode(text) as Map<String, Object?>);
    } on Object catch (e) {
      debugPrint('Fehlerjagd nicht lesbar: $e');
      return null;
    }
  }

  Future<void> start(FaultHuntDef hunt) => _write(path, jsonEncode(hunt.toJson()));

  Future<void> stop(FaultHuntDef hunt) => _write(path, jsonEncode(hunt.stopped(DateTime.now()).toJson()));

  /// Captured windows, newest first.
  Future<List<HuntWindow>> windows(String id) async {
    final text = await _read('hunts/$id/hits.ndjson');
    if (text == null) return const [];
    return [
      for (final line in const LineSplitter().convert(text))
        if (line.trim().isNotEmpty) HuntWindow.fromJson(jsonDecode(line) as Map<String, Object?>),
    ].reversed.toList();
  }

  /// Saves a window as a recording: telegrams with one comment per hit.
  Future<Recording> save(FaultHuntDef hunt, HuntWindow window) async {
    final text = await _read('hunts/${hunt.id}/${window.file}') ?? '';
    final telegrams = [
      for (final line in const LineSplitter().convert(text))
        if (line.trim().isNotEmpty) Telegram.fromJson(jsonDecode(line) as Map<String, Object?>),
    ]..sort((a, b) => a.time.compareTo(b.time));
    final first = telegrams.isEmpty ? window.hits.first.time : telegrams.first.time;
    final last = telegrams.isEmpty ? window.hits.last.time : telegrams.last.time;
    final recording = Recording(
      id: '${hunt.id}-${window.file.split('.').first}',
      name: '${hunt.name} · ${window.hits.first.label}',
      started: first,
      ended: last,
      telegrams: telegrams,
      project: CatalogStore.instance.catalog.projectName,
      installation: InstallationStore.instance.active.id,
      annotations: [
        for (final (i, h) in window.hits.indexed)
          Annotation(
            id: '${window.file}-$i',
            time: h.time,
            note: h.label,
            telegram: TelegramRef(
              time: h.time,
              source: h.source,
              destination: h.destination,
              type: TelegramType.write.name,
            ),
          ),
      ],
    );
    await RecordingStore.instance.save(recording);
    return recording;
  }
}
