import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// This app on this device (docs/keys.md): one random key, generated on first use, that stays
/// on the device. Everything that needs to tell devices apart knows this one by it, also a
/// paired box.
///
/// It never leaves through a backup (`FullBackup.keepsOut`): a restored backup on another
/// device is another app instance. It names the device and proves nothing.
abstract final class AppInstance {
  /// The settings key is older than this class (the account used it first) and stays.
  static const prefsKey = 'account_device_id';

  static final _pattern = RegExp(r'^[0-9a-f]{16,64}$');

  /// The first call in flight: account, sync and pairing may ask at the same time on first use,
  /// and all of them must get the same key.
  static Future<String>? _pending;

  static Future<String> id() => _pending ??= _load().whenComplete(() => _pending = null);

  static Future<String> _load() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(prefsKey);
    if (id == null || !_pattern.hasMatch(id)) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString(prefsKey, id);
    }
    return id;
  }
}
