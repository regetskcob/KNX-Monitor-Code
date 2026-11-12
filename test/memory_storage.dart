import 'package:knx_monitor/platform/storage.dart';

/// Dateiablage im Speicher für Tests.
class MemoryStorage implements AppStorage {
  final files = <String, String>{};

  @override
  Future<String?> read(String path) async => files[path];

  /// Hört bei jedem Schreiben mit (Tests zur Reihenfolge).
  void Function(String path, String text)? onWrite;

  @override
  Future<void> write(String path, String text) async {
    files[path] = text;
    onWrite?.call(path, text);
  }

  @override
  Future<void> append(String path, String text) async => files[path] = '${files[path] ?? ''}$text';

  @override
  Future<List<StoredFile>> list(String dir) async => [
    for (final MapEntry(:key, :value) in files.entries)
      if (key.startsWith('$dir/')) (name: key.substring(dir.length + 1), size: value.length),
  ];

  @override
  Future<void> delete(String path) async => files.remove(path);
}
