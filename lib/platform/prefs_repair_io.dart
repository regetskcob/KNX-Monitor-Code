import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> ensurePreferencesReadable() async {
  try {
    await SharedPreferences.getInstance();
    return;
  } on Object catch (e) {
    debugPrint('Einstellungen nicht lesbar: $e');
    if (!Platform.isLinux && !Platform.isWindows) return;
  }
  try {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}shared_preferences.json');
    if (file.existsSync()) {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await file.rename('${file.path}.corrupt-$stamp');
      debugPrint('Einstellungen beiseitegelegt: ${file.path}.corrupt-$stamp');
    }
    // getInstance resets itself after an error and reads again.
    await SharedPreferences.getInstance();
  } on Object catch (e) {
    debugPrint('Einstellungen weiter nicht lesbar: $e');
  }
}
