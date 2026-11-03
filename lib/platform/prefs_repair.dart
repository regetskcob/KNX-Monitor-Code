import 'prefs_repair_io.dart' if (dart.library.js_interop) 'prefs_repair_web.dart' as impl;

/// Ensures the settings are readable before the loaders open them. On Linux and Windows they are a
/// JSON file that the plugin does not write atomically; if it is truncated, every start would fail.
/// It is then moved aside (`.corrupt`) and the app starts with default settings. Projects and
/// recordings live in their own files and are preserved.
Future<void> ensurePreferencesReadable() => impl.ensurePreferencesReadable();
