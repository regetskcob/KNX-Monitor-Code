import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/box_link.dart';

/// Whether the keyring may go to this box. A separate question per address and certificate: the keys
/// of a KNX Secure installation never go to a box without asking. Without a UI ([ask] empty)
/// the keyring stays here. The answer never comes from a backup
/// (`FullBackup.keepsOut`).
abstract final class BoxKeyringConsent {
  static const _prefix = 'box_keyring_consent:';

  /// Asks the user; `null` if asking is not possible right now. Set by the UI.
  static Future<bool?> Function(BoxLink box)? ask;

  static String _key(BoxLink box) => '$_prefix${box.url}${box.fp.isEmpty ? '' : '#${box.fp}'}';

  /// Several syncs at the same time: only one question.
  static final _asking = <String, Future<bool>>{};

  static Future<bool> allowed(BoxLink box) async {
    final key = _key(box);
    final prefs = await SharedPreferences.getInstance();
    final known = prefs.getBool(key);
    if (known != null) return known;
    return _asking[key] ??= _ask(box, key, prefs).whenComplete(() {
      _asking.remove(key);
    });
  }

  static Future<bool> _ask(BoxLink box, String key, SharedPreferences prefs) async {
    final answer = await ask?.call(box);
    if (answer == null) return false;
    await prefs.setBool(key, answer);
    debugPrint('Box: Keyring für ${box.address} ${answer ? 'freigegeben' : 'abgelehnt'}');
    return answer;
  }

  /// Newly paired: ask again.
  static Future<void> forget(BoxLink box) async => (await SharedPreferences.getInstance()).remove(_key(box));
}

/// Whether the project may go to this box: the ETS project, the installation's name and gateway,
/// and with it everything else the app shares with a box.
///
/// A box paired via a link from outside (another app, a web page, a QR code not scanned in the
/// app) is [pending] until the user confirms once ([confirm]): such a link may lead to a box that
/// someone else set up in the network. Pairing with the app's own scanner or by hand confirms
/// right away. Boxes paired before this existed count as confirmed. Like the keyring consent, the
/// state never comes from a backup (`FullBackup.keepsOut`).
abstract final class BoxProjectConsent {
  static const _prefix = 'box_project_pending:';

  static String _key(BoxLink box) => '$_prefix${box.url}${box.fp.isEmpty ? '' : '#${box.fp}'}';

  static Future<bool> pending(BoxLink box) async => (await SharedPreferences.getInstance()).getBool(_key(box)) ?? false;

  /// Whether project data may go to [box] now.
  static Future<bool> allowed(BoxLink box) async => !await pending(box);

  /// Paired via a link from outside: nothing goes there until [confirm].
  static Future<void> markPending(BoxLink box) async {
    await (await SharedPreferences.getInstance()).setBool(_key(box), true);
    debugPrint('Box: ${box.address} über fremden Link gekoppelt, Projekt erst nach Rückfrage');
  }

  static Future<void> confirm(BoxLink box) async => (await SharedPreferences.getInstance()).remove(_key(box));
}
