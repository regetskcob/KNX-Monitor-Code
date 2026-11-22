import 'telegram.dart';

/// Signal strength of a KNX RF frame as the receiver measured it (two bits of the RF-Info field).
enum RfSignal { none, weak, medium, strong }

/// RF medium information a cEMI frame carries when it was received on KNX RF
/// (additional information type 0x02, length 8: RF-Info, serial number or
/// domain address, link layer frame number).
///
/// Only interfaces on the RF medium (IP-RF couplers, RF USB sticks behind a
/// cEMI server) add it; telegrams that crossed a media coupler onto TP do not
/// have it.
final class RfInfo {
  const RfInfo({
    required this.signal,
    required this.retransmitterSignal,
    required this.batteryOk,
    required this.transmitOnly,
    required this.serialOrDomain,
    required this.frameNumber,
  });

  /// Signal strength at the receiver.
  final RfSignal signal;

  /// Signal strength a retransmitter reported (none without a retransmitter).
  final RfSignal retransmitterSignal;

  /// Whether the transmitter reports its battery as fine.
  final bool batteryOk;

  /// Whether the device only transmits (unidirectional, e.g. a battery push button).
  final bool transmitOnly;

  /// Serial number (KNX RF Ready, transmit-only devices) or domain address, 6 bytes as hex.
  final String serialOrDomain;

  /// Link layer frame number (0–7 in KNX RF 1.1), counts up per frame of a transmitter.
  final int frameNumber;

  static const _type = 0x02;

  /// RF medium information of the cEMI frame [cemi], or `null` if it has none.
  static RfInfo? parse(List<int> cemi) {
    if (cemi.length < 2) return null;
    final end = 2 + cemi[1];
    if (end > cemi.length) return null;
    var i = 2;
    while (i + 2 <= end) {
      final type = cemi[i];
      final length = cemi[i + 1];
      final start = i + 2;
      if (start + length > end) return null;
      if (type == _type && length >= 8) {
        final info = cemi[start];
        return RfInfo(
          signal: RfSignal.values[(info >> 4) & 0x03],
          retransmitterSignal: RfSignal.values[(info >> 2) & 0x03],
          batteryOk: info & 0x02 != 0,
          transmitOnly: info & 0x01 != 0,
          serialOrDomain: hexOf(cemi.sublist(start + 1, start + 7)),
          frameNumber: cemi[start + 7] & 0x07,
        );
      }
      i = start + length;
    }
    return null;
  }
}

/// What the RF telegrams of one device in a log say about its radio link.
final class RfDeviceStats {
  const RfDeviceStats({
    required this.frames,
    required this.batteryOk,
    required this.signal,
    required this.weakShare,
    required this.repeated,
    required this.lost,
    required this.serialOrDomain,
    required this.transmitOnly,
  });

  /// Frames with RF medium information.
  final int frames;

  /// Battery state of the latest frame.
  final bool batteryOk;

  /// Signal strength of the latest frame.
  final RfSignal signal;

  /// Share of frames received with weak or no signal (0–1).
  final double weakShare;

  /// Frames that repeated the previous frame number (retries of the transmitter).
  final int repeated;

  /// Frames missing between two received ones, counted from gaps in the frame number. A gap of
  /// more than half the counter range is not counted: after a long pause it may have wrapped.
  final int lost;

  final String serialOrDomain;
  final bool transmitOnly;

  /// Repeats closer than this count as retries; later the same number is a new frame after wrap.
  static const retryWindow = Duration(seconds: 2);

  /// Gaps in the frame number count as lost only between frames closer than this: a longer pause
  /// may be time the app was not listening.
  static const lossWindow = Duration(minutes: 10);

  /// Statistics of the frames [source] sent in [log] (oldest first), or `null` without RF frames.
  static RfDeviceStats? of(int source, Iterable<Telegram> log) => _of([
    for (final t in log)
      if (t.source == source && !t.outgoing) t,
  ]);

  /// Statistics per sender of every sender with RF frames in [log] (oldest first), in one pass.
  static Map<int, RfDeviceStats> all(Iterable<Telegram> log) {
    final bySource = <int, List<Telegram>>{};
    for (final t in log) {
      if (t.outgoing || RfInfo.parse(t.raw) == null) continue;
      (bySource[t.source] ??= []).add(t);
    }
    return {for (final MapEntry(key: a, value: ts) in bySource.entries) a: ?_of(ts)};
  }

  static RfDeviceStats? _of(List<Telegram> telegrams) {
    var frames = 0, weak = 0, repeated = 0, lost = 0;
    RfInfo? last;
    DateTime? lastTime;
    int? lastTap;
    for (final t in telegrams) {
      final rf = RfInfo.parse(t.raw);
      if (rf == null) continue;
      if (last != null && lastTime != null) {
        final gap = (rf.frameNumber - last.frameNumber) & 0x07;
        final since = t.time.difference(lastTime);
        // The same frame from another tap point: one frame, not a retry.
        if (gap == 0 && since <= retryWindow && t.tap != lastTap) continue;
        if (gap == 0 && since <= retryWindow) {
          repeated++;
        } else if (gap > 1 && gap <= 4 && since <= lossWindow) {
          lost += gap - 1;
        }
      }
      frames++;
      if (rf.signal.index <= RfSignal.weak.index) weak++;
      last = rf;
      lastTime = t.time;
      lastTap = t.tap;
    }
    if (last == null) return null;
    return RfDeviceStats(
      frames: frames,
      batteryOk: last.batteryOk,
      signal: last.signal,
      weakShare: weak / frames,
      repeated: repeated,
      lost: lost,
      serialOrDomain: last.serialOrDomain,
      transmitOnly: last.transmitOnly,
    );
  }
}
