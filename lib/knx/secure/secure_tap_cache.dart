import 'dart:typed_data';

/// The same KNX Data Secure telegram seen at a further tap point (issue #8): its sequence number is
/// spent, so the replay check would refuse it there and it would go missing. Within [window] the
/// bytes seen at one tap point get the decryption of the first; a real replay later still meets the
/// check. Keyed by sender, destination and secured APDU, without the control fields, which couplers
/// change on the way (hop count). The add-on/box server does the same (`BusService.secureSeenAt`).
class SecureTapCache {
  SecureTapCache({this.window = const Duration(seconds: 3), DateTime Function()? now}) : _now = now ?? DateTime.now;

  final Duration window;
  final DateTime Function() _now;
  final _recent = <String, (List<int>, DateTime)>{};

  static String _key(List<int> cemi) {
    final i = 2 + cemi[1];
    return [
      ...cemi.sublist(i + 2, i + 6),
      ...cemi.sublist(i + 7),
    ].map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Notes [decrypted], the accepted decryption of the secured [cemi].
  void remember(List<int> cemi, Uint8List decrypted) {
    final now = _now();
    _recent.removeWhere((_, v) => now.difference(v.$2) > window);
    final j = 2 + decrypted[1];
    _recent[_key(cemi)] = (decrypted.sublist(j + 7, j + 8 + decrypted[j + 6]), now);
  }

  /// [cemi] with the decrypted APDU if seen within [window] at another tap point, else `null`.
  Uint8List? seen(List<int> cemi) {
    final hit = _recent[_key(cemi)];
    if (hit == null || _now().difference(hit.$2) > window) return null;
    final i = 2 + cemi[1];
    return Uint8List.fromList([...cemi.sublist(0, i + 6), hit.$1.length - 1, ...hit.$1]);
  }
}

/// Shared by all tunnels of the open monitor (one per tap point).
final secureTapCache = SecureTapCache();
