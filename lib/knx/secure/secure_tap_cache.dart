import 'dart:typed_data';

import 'package:knx/secure.dart';

// Same logic as ha-addon/knx_monitor/server/lib/src/secure_taps.dart in the server.

/// KNX Data Secure with several tap points (issue #8).
///
/// A secured telegram that a coupler forwards arrives at several tap points with the same
/// sequence number. The replay check ([DataSecure.receive]) accepts a sequence number once, so the
/// copy at the second tap point would be refused and go missing there. This class lets exactly
/// that copy through, and only as a further sighting of the entry the first copy opened in the
/// `TapMerger`. It can never become an entry of its own, so nothing runs through history, MQTT,
/// alarms or watchers a second time.
///
/// [receive] hands a copy the decryption of the first one only if all of this holds:
///
/// - it is byte-identical in everything the MAC covers, MAC included (sender, destination,
///   address type, secured APDU with sequence number); only the repeat flag and the hop count
///   may differ, which are not protected and change on the way;
/// - it comes from a tap point that has not delivered this telegram yet;
/// - the entry of the first copy is still waiting in the merger ([released] has not seen it);
/// - it arrives within the merge window of that pair of tap points, counting only windows set
///   by hand ([windows]), else [defaultWindow]. A window the meter widened by itself does not
///   count: lag can be faked with unsecured telegrams.
///
/// The copy is given the repeat flag of the first one, so the merger files it under the same
/// key. Everything else goes to the normal check and is refused there as a replay. As a last
/// line, [released] tells the caller to drop a copy the merger released on its own after all.
///
/// Use: [receive], then [tag] the telegram parsed from its result, feed the merger, and ask
/// [released] for every telegram the merger gives back.
class SecureTapCache {
  SecureTapCache({DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// The merge window of the tap points without a setting of their own.
  static const defaultWindow = Duration(milliseconds: 100);

  /// Never longer than the widest merge window that can be set (5 s).
  static const maxWindow = Duration(seconds: 5);

  /// Telegrams remembered at most; older ones leave first (telegram flood).
  static const maxEntries = 256;

  /// Merge windows set by hand, by tap point. Not the measured ones.
  Map<int, Duration> windows = const {};

  final DateTime Function() _now;
  final _recent = <String, _Seen>{};
  final _marks = Expando<_Mark>();
  _Mark? _pending;

  /// Copies [released] told the caller to drop.
  int dropped = 0;

  Duration _windowOf(int tap) {
    final w = windows[tap] ?? defaultWindow;
    return w > maxWindow ? maxWindow : w;
  }

  /// Identity of a secured frame: everything the MAC covers plus the MAC itself, without the
  /// repeat flag (control field 1) and the hop count (bits 4–6 of control field 2).
  static String? _key(List<int> cemi) {
    if (cemi.length < 2) return null;
    final i = 2 + cemi[1];
    if (cemi.length < i + 8) return null;
    return [
      cemi[i + 1] & 0x8F,
      ...cemi.sublist(i + 2, i + 6),
      ...cemi.sublist(i + 7),
    ].map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Decrypts [cemi] received at tap point [tap] with [ds], see the class comment.
  (SecureResult, Uint8List) receive(DataSecure ds, int tap, Uint8List cemi, {DateTime? at}) {
    final now = at ?? _now();
    _pending = null;
    final key = _key(cemi);
    final hit = key == null ? null : _recent[key];
    if (hit != null && hit.open && !hit.taps.contains(tap)) {
      final age = now.difference(hit.time);
      final w0 = _windowOf(hit.first), w1 = _windowOf(tap);
      if (!age.isNegative && age <= (w0 > w1 ? w0 : w1)) {
        hit.taps.add(tap);
        _pending = _Mark(hit, copy: true);
        final i = 2 + cemi[1];
        return (
          SecureResult.decrypted,
          Uint8List.fromList([
            ...cemi.sublist(0, i),
            // The repeat flag of the first copy (bit 5), so both merge under one key.
            (cemi[i] & 0xDF) | hit.repeatBit,
            ...cemi.sublist(i + 1, i + 6),
            hit.apdu.length - 1,
            ...hit.apdu,
          ]),
        );
      }
    }
    final (result, plain) = ds.receive(cemi);
    if (result == SecureResult.decrypted && key != null) {
      _recent.removeWhere((_, v) => !v.open || now.difference(v.time) > maxWindow);
      while (_recent.length >= maxEntries) {
        _recent.remove(_recent.keys.first);
      }
      final i = 2 + cemi[1];
      final j = 2 + plain[1];
      final seen = _Seen(plain.sublist(j + 7, j + 8 + plain[j + 6]), now, tap, cemi[i] & 0x20);
      _recent[key] = seen;
      _pending = _Mark(seen, copy: false);
    }
    return (result, plain);
  }

  /// Marks [raw], the frame of the telegram parsed from the last [receive] result
  /// (`Telegram.raw`), so that [released] recognises it when the merger gives it back.
  void tag(List<int> raw) {
    final mark = _pending;
    _pending = null;
    if (mark != null && raw.isNotEmpty) _marks[raw] = mark;
  }

  /// Call for every telegram the merger releases, with its frame ([raw]) and whether it has
  /// sightings at further tap points ([merged]). Closes the entry for further copies. Returns
  /// `false` for a copy that left on its own: the caller must drop it.
  bool released(List<int> raw, {required bool merged}) {
    if (raw.isEmpty) return true;
    final mark = _marks[raw];
    if (mark == null) return true;
    mark.seen.open = false;
    if (!mark.copy || merged) return true;
    dropped++;
    return false;
  }

  /// Forgets everything (connection closed).
  void clear() {
    _recent.clear();
    _pending = null;
  }
}

class _Seen {
  _Seen(this.apdu, this.time, this.first, this.repeatBit) : taps = {first};

  /// Decrypted APDU (TPCI/APCI and data).
  final List<int> apdu;
  final DateTime time;

  /// Tap point of the first copy.
  final int first;

  /// Bit 5 of control field 1 of the first copy (0 = repeated).
  final int repeatBit;

  /// Tap points that delivered this telegram; each counts once.
  final Set<int> taps;

  /// Whether the first copy's entry is still waiting in the merger.
  bool open = true;
}

class _Mark {
  _Mark(this.seen, {required this.copy});
  final _Seen seen;

  /// A further copy rather than the first one.
  final bool copy;
}

/// Shared by all tunnels of the open monitor (one per tap point).
final secureTapCache = SecureTapCache();
