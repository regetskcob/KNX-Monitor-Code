import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// How long a copied secret stays in the clipboard.
const secretClipboardLifetime = Duration(seconds: 60);

const _channel = MethodChannel('knx/native');

Timer? _clearTimer;

/// Copies a secret (token, password, TOTP secret, invitation code) and removes it again after
/// [keep], if the clipboard still holds it then.
///
/// iOS: only on this device (not via Universal Clipboard) and with an expiry date the system
/// enforces. Android: marked as sensitive, so the keyboard and the system preview hide it (13+);
/// the app clears it natively, without reading the clipboard. Elsewhere the clipboard is compared
/// and cleared from here; in the browser it stays, because reading it would ask for permission.
Future<void> copySecret(String text, {Duration keep = secretClipboardLifetime}) async {
  _clearTimer?.cancel();
  _clearTimer = null;
  if (await _copyNative(text, keep)) return;
  await Clipboard.setData(ClipboardData(text: text));
  if (kIsWeb) return;
  _clearTimer = Timer(keep, () => unawaited(_clearIfUnchanged(text)));
}

Future<bool> _copyNative(String text, Duration keep) async {
  if (kIsWeb || !(defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android)) {
    return false;
  }
  try {
    return await _channel.invokeMethod<bool>('copySecret', {'text': text, 'seconds': keep.inSeconds}) ?? false;
  } on Object catch (e) {
    // Older native part without the method: the plain way.
    debugPrint('Zwischenablage: $e');
    return false;
  }
}

Future<void> _clearIfUnchanged(String text) async {
  try {
    final now = await Clipboard.getData(Clipboard.kTextPlain);
    if (now?.text == text) await Clipboard.setData(const ClipboardData(text: ''));
  } on Object catch (e) {
    debugPrint('Zwischenablage nicht geleert: $e');
  }
}
