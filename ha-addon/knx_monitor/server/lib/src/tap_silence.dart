// Same logic as lib/model/tap_points.dart (TapSilence) in the app.

/// Spots a tap point that is connected but hears nothing (issue #8), typically routing without an
/// IP router in the network: it says "connected", yet no telegram arrives there. A tap point counts as
/// silent once the others delivered [threshold] frames since it connected and it heard none.
class TapSilence {
  /// Frames from the other tap points before a quiet one counts as silent.
  static const threshold = 20;

  final _heard = <int, int>{};
  final _base = <int, int>{};
  int _total = 0;

  /// Tap point [tap] (0 = first) connected: starts counting afresh.
  void connected(int tap) {
    _heard[tap] = 0;
    _base[tap] = _total;
  }

  /// Tap point [tap] is gone or paused: no longer judged.
  void disconnected(int tap) {
    _heard.remove(tap);
    _base.remove(tap);
  }

  /// A frame arrived at [tap]. Returns whether that changed which tap points are silent.
  bool heard(int tap) {
    final before = _base.keys.where(silent).length;
    _total++;
    if (_heard.containsKey(tap)) _heard[tap] = _heard[tap]! + 1;
    return _base.keys.where(silent).length != before;
  }

  /// Whether [tap] is connected, has heard nothing, and the others delivered enough meanwhile.
  bool silent(int tap) {
    final base = _base[tap];
    return base != null && _heard[tap] == 0 && _total - base >= threshold;
  }
}
