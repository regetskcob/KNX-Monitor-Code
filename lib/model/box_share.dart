import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/addon.dart';
import 'installation.dart';

enum BoxShareOutcome {
  /// Both are the same, or there is nothing to share here.
  same,

  /// Newer here: put on the box.
  pushed,

  /// The box has a state this device does not know from it: it may have been
  /// changed there (browser on the box Wi-Fi). Stays until someone decides.
  boxDiffers,
}

/// Syncs files with the box. There are no versions or timestamps there, so it
/// is a three-way comparison of content hashes: here, on the box, and what was
/// last provably on both. Only the hash is remembered, never the content.
abstract final class BoxShare {
  static String _hash(List<int> bytes) => sha256.convert(bytes).toString();

  static String _key(String installation, String path) =>
      InstallationStore.scopedKey(installation, 'box_shared:${Addon.box?.address ?? ''}:$path');

  /// [text] is now on the box as well.
  static Future<void> remember(String installation, String path, String text) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(installation, path), _hash(utf8.encode(text)));
  }

  /// Puts [local] on the box only if it is missing there or the box still holds
  /// the last shared state. Throws if the box does not respond.
  static Future<BoxShareOutcome> sync(
    String installation,
    String path, {
    required String? local,
    required Future<List<int>?> Function() readBox,
    required Future<void> Function(List<int> bytes) writeBox,
  }) async {
    if (local == null) return BoxShareOutcome.same;
    final bytes = utf8.encode(local);
    final box = await readBox();
    final prefs = await SharedPreferences.getInstance();
    final key = _key(installation, path);
    final boxHash = box == null ? null : _hash(box);
    if (boxHash == _hash(bytes)) {
      await prefs.setString(key, boxHash!);
      return BoxShareOutcome.same;
    }
    if (boxHash != null && boxHash != prefs.getString(key)) {
      debugPrint('Box: $path unterscheidet sich, bleibt unverändert');
      return BoxShareOutcome.boxDiffers;
    }
    await writeBox(bytes);
    await prefs.setString(key, _hash(bytes));
    return BoxShareOutcome.pushed;
  }
}
