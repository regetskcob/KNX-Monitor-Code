import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../knx/demo_tunnel.dart';
import '../platform/storage.dart';
import 'installation.dart';

/// A generated export file (PDF, CSV, ETS XML, ZIP).
class ExportEntry {
  const ExportEntry({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.time,
  });

  factory ExportEntry.fromJson(Map<String, Object?> j) => ExportEntry(
    id: j['id']! as String,
    name: j['name']! as String,
    mimeType: j['mime']! as String,
    size: j['size']! as int,
    time: DateTime.fromMillisecondsSinceEpoch(j['t']! as int),
  );

  final String id;
  final String name;
  final String mimeType;

  /// Size in bytes.
  final int size;
  final DateTime time;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'mime': mimeType,
    'size': size,
    't': time.millisecondsSinceEpoch,
  };
}

/// The most recently generated exports per installation, to share them again
/// without regenerating them. Keeps only the latest [keep]; files larger than
/// [maxBytes] are not kept.
class ExportHistory extends ChangeNotifier {
  ExportHistory._();

  static final instance = ExportHistory._();

  static const keep = 5;
  static const maxBytes = 20 * 1024 * 1024;
  static const _dir = 'exports';
  static const _index = '$_dir/index.json';
  static String _path(String id) => '$_dir/$id.b64';

  AppStorage Function() storage = () => InstallationStore.instance.storage;

  List<ExportEntry> _entries = [];

  /// Newest first.
  List<ExportEntry> get entries => List.unmodifiable(_entries);

  Future<void> load() async {
    _entries =
        await readStored(
          storage(),
          _index,
          (text) => [for (final e in jsonDecode(text) as List) ExportEntry.fromJson((e as Map).cast())],
        ) ??
        [];
    notifyListeners();
  }

  /// Remembers a generated file; the oldest drops out as soon as there are more
  /// than [keep]. Errors while storing are no reason to let the export
  /// fail.
  Future<void> add(String name, Uint8List bytes, String mimeType) async {
    // Demo house: nothing in the history of the real installation (like acceptance
    // and commissioning); the file is shared anyway.
    if (bytes.length > maxBytes || DemoTunnel.active) return;
    try {
      final now = DateTime.now();
      final entry = ExportEntry(
        id: now.microsecondsSinceEpoch.toRadixString(36),
        name: name,
        mimeType: mimeType,
        size: bytes.length,
        time: now,
      );
      await storage().write(_path(entry.id), base64Encode(bytes));
      _entries = [entry, ..._entries];
      while (_entries.length > keep) {
        await storage().delete(_path(_entries.removeLast().id));
      }
      await _save();
      notifyListeners();
    } on Object catch (e) {
      debugPrint('Export nicht gemerkt: $e');
    }
  }

  Future<Uint8List?> read(ExportEntry e) async {
    final text = await storage().read(_path(e.id));
    return text == null ? null : base64Decode(text);
  }

  Future<void> remove(ExportEntry e) async {
    _entries = [..._entries]..removeWhere((x) => x.id == e.id);
    await storage().delete(_path(e.id));
    await _save();
    notifyListeners();
  }

  Future<void> _save() => storage().write(_index, jsonEncode([for (final e in _entries) e.toJson()]));

  @visibleForTesting
  void debugReset() => _entries = [];
}
