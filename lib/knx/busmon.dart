import 'dart:typed_data';

import 'telegram.dart';

/// Kind of frame in the bus monitor: acknowledgement or data telegram.
enum BusmonKind {
  /// The receiver accepted the telegram.
  ack,

  /// The receiver rejected it (received with errors) – the sender repeats.
  nak,

  /// The receiver was busy – the sender repeats.
  busy,

  /// NAK and BUSY at the same time (several receivers, different answers).
  nakBusy,

  /// Data telegram (L_Data, standard or extended format).
  data,

  /// Cannot be classified (e.g. truncated or corrupted).
  unknown,
}

/// A raw frame from the bus (cEMI L_Busmon.ind, code 0x2B) – including acknowledgements,
/// repetitions and faulty telegrams that do not appear in the normal group monitor.
class BusmonFrame {
  BusmonFrame({
    required this.time,
    required this.raw,
    required this.kind,
    this.status = 0,
    this.timestamp,
    this.telegram,
    this.checksumOk = true,
    this.source,
    this.destination,
    this.groupAddressed = false,
    this.repeated = false,
  });

  final DateTime time;

  /// TP frame as on the wire (including checksum).
  final Uint8List raw;
  final BusmonKind kind;

  /// Status byte from the additional info (KNX 03.06.03): bit 7 frame error, bit 6 bit error, bit 5
  /// parity error, bit 4 overflow, bit 3 lost, bits 2–0 sequence number.
  final int status;

  /// Relative timestamp of the gateway in microseconds (if provided).
  final int? timestamp;

  /// Group telegram with value (only for data to group addresses).
  final Telegram? telegram;
  final bool checksumOk;
  final int? source;
  final int? destination;
  final bool groupAddressed;
  final bool repeated;

  bool get frameError => status & 0x80 != 0;
  bool get bitError => status & 0x40 != 0;
  bool get parityError => status & 0x20 != 0;
  bool get overflow => status & 0x10 != 0;
  bool get lost => status & 0x08 != 0;

  /// Whether there is any transmission error (status or checksum).
  bool get hasError => frameError || bitError || parityError || overflow || lost || !checksumOk;

  bool get isAck => kind == BusmonKind.ack;

  /// Whether this is a negative acknowledgement (NAK, BUSY or both).
  bool get isNegative => kind == BusmonKind.nak || kind == BusmonKind.busy || kind == BusmonKind.nakBusy;

  /// Parses cEMI L_Busmon.ind; `null` for another message code.
  static BusmonFrame? parse(Uint8List cemi, {DateTime? time}) {
    if (cemi.length < 3 || cemi[0] != 0x2B) return null;
    final infoLength = cemi[1];
    if (cemi.length < 2 + infoLength + 1) return null;
    var status = 0;
    int? timestamp;
    // Additional info: type, length, data.
    for (var i = 2; i + 1 < 2 + infoLength;) {
      final type = cemi[i];
      final len = cemi[i + 1];
      final data = cemi.sublist(i + 2, (i + 2 + len).clamp(0, 2 + infoLength));
      switch (type) {
        case 0x03 when data.isNotEmpty:
          status = data[0];
        case 0x04 when data.length >= 2:
          timestamp = (data[0] << 8) | data[1];
        case 0x06 when data.length >= 4:
          timestamp = (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];
      }
      i += 2 + len;
    }
    final raw = Uint8List.fromList(cemi.sublist(2 + infoLength));
    return fromRaw(raw, time: time ?? DateTime.now(), status: status, timestamp: timestamp);
  }

  /// Evaluates a TP frame (acknowledgement or data telegram).
  static BusmonFrame fromRaw(Uint8List raw, {required DateTime time, int status = 0, int? timestamp}) {
    BusmonFrame frame(BusmonKind kind) =>
        BusmonFrame(time: time, raw: raw, kind: kind, status: status, timestamp: timestamp);
    if (raw.length == 1) {
      return switch (raw[0]) {
        0xCC => frame(BusmonKind.ack),
        0x0C => frame(BusmonKind.nak),
        0xC0 => frame(BusmonKind.busy),
        0x00 => frame(BusmonKind.nakBusy),
        _ => frame(BusmonKind.unknown),
      };
    }
    // Standard frame: control field 10xx xx00, at least 8 bytes including checksum.
    if (raw.length < 8 || raw[0] & 0xD3 != 0x90) return frame(BusmonKind.unknown);
    final length = raw[5] & 0x0F;
    final end = 6 + length + 1; // TPCI/APCI + data
    if (raw.length < end + 1) return frame(BusmonKind.unknown);

    var xor = 0;
    for (var i = 0; i < end; i++) {
      xor ^= raw[i];
    }
    final checksumOk = (~xor & 0xFF) == raw[end];
    final group = raw[5] & 0x80 != 0;
    final source = (raw[1] << 8) | raw[2];
    final destination = (raw[3] << 8) | raw[4];

    // Convert to cEMI L_Data.ind so values appear as in the group monitor.
    final cemi = Uint8List.fromList([
      0x29,
      0x00,
      raw[0],
      raw[5] & 0xF0,
      ...raw.sublist(1, 5),
      length,
      ...raw.sublist(6, end),
    ]);
    return BusmonFrame(
      time: time,
      raw: raw,
      kind: BusmonKind.data,
      status: status,
      timestamp: timestamp,
      telegram: group ? Telegram.fromCemi(cemi, time: time) : null,
      checksumOk: checksumOk,
      source: source,
      destination: destination,
      groupAddressed: group,
      repeated: raw[0] & 0x20 == 0,
    );
  }
}

/// Bus load of a TP line (9600 bit/s) from the observed frames.
///
/// 13 bit times per character (start, 8 data, parity, stop, 2 pause); at least 50 bit times of idle
/// before a telegram, 15 before an acknowledgement.
class BusLoad {
  static const bitRate = 9600;
  static const _keep = 120;

  /// Busy time per second (Unix second → seconds).
  final _busy = <int, double>{};

  /// Busy time of a frame in seconds.
  static double busyTime(BusmonFrame f) => (f.raw.length == 1 ? 15 + 13 : 50 + 13 * f.raw.length) / bitRate;

  void add(BusmonFrame f, {DateTime? now}) {
    final second = (now ?? f.time).millisecondsSinceEpoch ~/ 1000;
    _busy[second] = (_busy[second] ?? 0) + busyTime(f);
    _busy.removeWhere((s, _) => s < second - _keep);
  }

  void clear() => _busy.clear();

  /// Load (0–1) per second, oldest first, up to and including [now].
  List<double> history({int seconds = 60, DateTime? now}) {
    final end = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    return [for (var s = end - seconds + 1; s <= end; s++) (_busy[s] ?? 0).clamp(0, 1).toDouble()];
  }

  /// Average load (0–1) over the last [seconds] seconds.
  double average({int seconds = 10, DateTime? now}) {
    final h = history(seconds: seconds, now: now);
    return h.fold(0.0, (a, b) => a + b) / seconds;
  }
}
