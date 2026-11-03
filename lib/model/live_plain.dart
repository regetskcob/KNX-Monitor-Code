import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Live list in full sentences instead of address and name (persisted, off by default).
class LivePlainSetting extends ValueNotifier<bool> {
  LivePlainSetting._() : super(false);

  static final instance = LivePlainSetting._();
  static const _key = 'live_plain_text';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    value = prefs.getBool(_key) ?? false;
  }

  Future<void> set(bool on) async {
    value = on;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, on);
  }
}
