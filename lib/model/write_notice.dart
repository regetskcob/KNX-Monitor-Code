import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Notice before writing to the bus. Once dismissed, it does not come back on this device;
/// dismissal and its time are included in diagnostic packages and bug reports.
class WriteNotice extends ChangeNotifier {
  WriteNotice._();

  static final instance = WriteNotice._();
  static const _key = 'write_notice_dismissed';

  DateTime? _dismissedAt;
  bool _loaded = false;

  /// When the notice was dismissed; `null` as long as it appears.
  DateTime? get dismissedAt => _dismissedAt;
  bool get dismissed => _dismissedAt != null;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _dismissedAt = DateTime.tryParse(prefs.getString(_key) ?? '');
    _loaded = true;
    notifyListeners();
  }

  Future<void> dismiss([DateTime? at]) async {
    _dismissedAt = (at ?? DateTime.now()).toUtc();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _dismissedAt!.toIso8601String());
  }

  /// Shows the notice again.
  Future<void> restore() async {
    _dismissedAt = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// For diagnostic packages and bug reports: only whether and when, nothing else.
  Map<String, Object?> toReport() => {
    'dismissed': dismissed,
    if (_dismissedAt case final at?) 'dismissedAt': at.toIso8601String(),
  };

  /// For tests of other write prompts.
  @visibleForTesting
  void debugDismiss() {
    _dismissedAt = DateTime.utc(2026);
    _loaded = true;
  }

  @visibleForTesting
  void debugReset() {
    _dismissedAt = null;
    _loaded = false;
  }
}
