import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Expert mode: brings tools, exports and all metrics directly into the UI.
/// Without it the monitor stays lean – nothing is lost, it just sits one level
/// deeper ("Werkzeuge" (tools) menu, "Exportieren …" (export)).
class ExpertMode extends ValueNotifier<bool> {
  ExpertMode._() : super(false);

  static final instance = ExpertMode._();
  static const _key = 'expert_mode';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    // The Home Assistant add-on is mostly used by professionals: on by default there.
    value = prefs.getBool(_key) ?? kIsWeb;
  }

  Future<void> set(bool on) async {
    value = on;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, on);
  }
}

/// Shorthand for `ExpertMode.instance.value`.
bool get expert => ExpertMode.instance.value;
