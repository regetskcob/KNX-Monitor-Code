import 'dart:typed_data';

import '../l10n/locale_controller.dart';

/// Kind of group telegram (APCI).
enum TelegramType { read, response, write }

/// Telegram priority (cEMI Ctrl1 bits 3–2).
enum TelegramPriority { system, normal, urgent, low }

/// A received KNX group telegram.
class Telegram {
  const Telegram({
    required this.time,
    required this.source,
    required this.destination,
    required this.type,
    required this.data,
    required this.isSmall,
    this.outgoing = false,
    this.priority = TelegramPriority.low,
    this.repeated = false,
    this.hopCount = 6,
    this.confirmError = false,
    Uint8List? raw,
  }) : raw = raw ?? const [];

  final DateTime time;

  /// Individual address of the sender (raw, 16 bit).
  final int source;

  /// Group address (raw, 16 bit).
  final int destination;

  final TelegramType type;

  /// Payload. With [isSmall] exactly one byte with the 6-bit value.
  final Uint8List data;

  /// Whether the value sits directly in the APCI byte (≤ 6 bit, e.g. DPT 1).
  final bool isSmall;

  /// Whether we sent it ourselves (confirmation L_Data.con from the gateway).
  final bool outgoing;

  /// Complete cEMI frame.
  final List<int> raw;

  final TelegramPriority priority;

  /// Whether the telegram is repeated – the first attempt was not acknowledged.
  final bool repeated;

  /// Routing counter: 6 directly from the sender, each coupler subtracts 1, 7 = unlimited.
  final int hopCount;

  /// Only for telegrams we sent (L_Data.con): the bus did not acknowledge.
  final bool confirmError;

  /// Whether the routing counter differs from 6 (passed a coupler, or a special case).
  bool get unusualHop => hopCount != 6;

  /// The same telegram with a different value ([small] ≤ 6 bit or [data]), e.g. when editing a
  /// recording. The raw frame is dropped.
  Telegram withValue({int? small, List<int> data = const []}) => Telegram(
    time: time,
    source: source,
    destination: destination,
    type: type,
    data: Uint8List.fromList(small != null ? [small] : data),
    isSmall: small != null,
    outgoing: outgoing,
    priority: priority,
    repeated: repeated,
    hopCount: hopCount,
  );

  Map<String, Object?> toJson() => {
    't': time.microsecondsSinceEpoch,
    's': source,
    'd': destination,
    'y': type.index,
    'x': hex(data).replaceAll(' ', ''),
    if (isSmall) 'm': true,
    if (outgoing) 'o': true,
    if (priority != TelegramPriority.low) 'p': priority.index,
    if (repeated) 'rp': true,
    if (hopCount != 6) 'h': hopCount,
    if (confirmError) 'ce': true,
    if (raw.isNotEmpty) 'r': hex(raw).replaceAll(' ', ''),
  };

  factory Telegram.fromJson(Map<String, Object?> j) => Telegram(
    time: DateTime.fromMicrosecondsSinceEpoch(j['t']! as int),
    source: j['s']! as int,
    destination: j['d']! as int,
    type: TelegramType.values[j['y']! as int],
    data: Uint8List.fromList(parseHex(j['x']! as String) ?? const []),
    isSmall: j['m'] == true,
    outgoing: j['o'] == true,
    priority: TelegramPriority.values[j['p'] as int? ?? TelegramPriority.low.index],
    repeated: j['rp'] == true,
    hopCount: j['h'] as int? ?? 6,
    confirmError: j['ce'] == true,
    raw: j['r'] == null ? null : Uint8List.fromList(parseHex(j['r']! as String) ?? const []),
  );

  String get sourceText => formatIndividual(source);
  String get destinationText => formatGroup(destination);

  /// Readable short form of the value (only heuristic without an ETS project).
  String get valueText {
    if (type == TelegramType.read) return '—';
    if (isSmall) {
      final v = data.isEmpty ? 0 : data[0];
      return switch (v) {
        0 => '0 · ${s.dpt1Off}',
        1 => '1 · ${s.dpt1On}',
        _ => '$v',
      };
    }
    return switch (data.length) {
      1 => '${hex(data)} · ${data[0]} · ${(data[0] * 100 / 255).round()} %',
      2 => '${hex(data)} · ≈ ${localizeDecimal(decodeDpt9(data).toStringAsFixed(2))}',
      3 => switch (_guess3(data, time.year)) {
        final guess? => '${hex(data)} · ≈ $guess',
        null => hex(data),
      },
      8 when _isDateTime(data, time.year) => '${hex(data)} · ≈ ${_dpt19(data)}',
      _ => hex(data),
    };
  }

  /// All plausible interpretations of the payload, key = DPT.
  List<(String, String)> get interpretations {
    if (type == TelegramType.read) return const [];
    final d = data;
    final bd = ByteData.sublistView(d);
    if (isSmall) {
      final v = d.isEmpty ? 0 : d[0];
      return [
        if (v <= 1) ('1.001 ${s.dptNameSwitch}', v == 1 ? s.dpt1On : s.dpt1Off),
        if (v <= 1) ('1.008 ${s.dptNameUpDown}', v == 1 ? s.dpt1Down : s.dpt1Up),
        ('6 bit', '$v'),
      ];
    }
    return switch (d.length) {
      1 => [
        ('5.001 ${s.dptNamePercent}', '${localizeDecimal((d[0] * 100 / 255).toStringAsFixed(1))} %'),
        ('5.010 ${s.dptNameCounter}', '${d[0]}'),
        ('6.010 ${s.dptNameSigned}', '${bd.getInt8(0)}'),
        ('17.001 ${s.dptNameScene}', '${(d[0] & 0x3F) + 1}${d[0] & 0x80 != 0 ? ' (${s.dptSceneLearn})' : ''}'),
      ],
      2 => [
        ('9.xxx ${s.dptNameFloat}', localizeDecimal(decodeDpt9(d).toStringAsFixed(2))),
        ('7.001 ${s.dptNameCounter}', '${bd.getUint16(0)}'),
        ('8.001 ${s.dptNameSigned}', '${bd.getInt16(0)}'),
      ],
      3 => [
        ('10.001 ${s.dptNameTime}', _dpt10(d)),
        ('11.001 ${s.dptNameDate}', _dpt11(d)),
        ('232.600 RGB', '${d[0]}, ${d[1]}, ${d[2]}'),
      ],
      4 => [
        ('14.xxx ${s.dptNameFloat}', _num(bd.getFloat32(0))),
        ('12.001 ${s.dptNameCounter}', '${bd.getUint32(0)}'),
        ('13.001 ${s.dptNameSigned}', '${bd.getInt32(0)}'),
      ],
      8 => [('19.001 ${s.dptNameDateTime}', _dpt19(d))],
      14 => [('16.000 ${s.dptNameText}', String.fromCharCodes(d.where((b) => b != 0)))],
      _ => const [],
    };
  }

  /// Parses a cEMI frame. Returns `null` for anything that is not a group telegram (L_Data.ind /
  /// L_Data.con).
  static Telegram? fromCemi(Uint8List c, {DateTime? time}) {
    if (c.length < 2) return null;
    final code = c[0];
    if (code != 0x29 && code != 0x2E) return null;
    final i = 2 + c[1];
    if (c.length < i + 9) return null;

    final ctrl2 = c[i + 1];
    if (ctrl2 & 0x80 == 0) return null; // not a group address

    final source = (c[i + 2] << 8) | c[i + 3];
    final destination = (c[i + 4] << 8) | c[i + 5];
    final npduLength = c[i + 6];
    final apci = ((c[i + 7] & 0x03) << 8) | c[i + 8];

    final type = switch (apci & 0x3C0) {
      0x000 => TelegramType.read,
      0x040 => TelegramType.response,
      0x080 => TelegramType.write,
      _ => null,
    };
    if (type == null) return null;

    final isSmall = npduLength <= 1;
    final Uint8List data;
    if (isSmall) {
      data = Uint8List.fromList([c[i + 8] & 0x3F]);
    } else {
      final end = (i + 8 + npduLength).clamp(i + 9, c.length);
      data = Uint8List.fromList(c.sublist(i + 9, end));
    }

    return Telegram(
      time: time ?? DateTime.now(),
      source: source,
      destination: destination,
      type: type,
      data: data,
      isSmall: isSmall,
      outgoing: code == 0x2E,
      priority: TelegramPriority.values[(c[i] >> 2) & 0x03],
      // cEMI: bit 5 = 0 in L_Data.ind means "repeated".
      repeated: code == 0x29 && c[i] & 0x20 == 0,
      hopCount: (ctrl2 >> 4) & 0x07,
      confirmError: code == 0x2E && c[i] & 0x01 != 0,
      raw: Uint8List.fromList(c),
    );
  }
}

/// Builds a cEMI L_Data.req for a group telegram.
///
/// [small] = value (0–63) directly in the APCI byte; otherwise [data] as payload.
Uint8List buildGroupRequest(int destination, TelegramType type, {List<int> data = const [], int? small}) {
  final apci = switch (type) {
    TelegramType.read => 0x00,
    TelegramType.response => 0x40,
    TelegramType.write => 0x80,
  };
  final inline = type == TelegramType.read || small != null;
  return Uint8List.fromList([
    0x11, 0x00, // L_Data.req, no additional info
    0xBC, 0xE0, // standard frame, group address, hop count 6
    0x00, 0x00, // source: set by the gateway
    destination >> 8, destination & 0xFF,
    inline ? 1 : 1 + data.length,
    0x00,
    apci | (inline ? (small ?? 0) & 0x3F : 0),
    if (!inline) ...data,
  ]);
}

/// Display style of group addresses as configured in the ETS project.
enum GroupStyle {
  /// Main/middle/sub, e.g. 1/2/3 (default).
  threeLevel,

  /// Main/sub, e.g. 1/515.
  twoLevel,

  /// Free number 0–65535, e.g. 2563.
  free,
}

/// Current style; follows the loaded project (see CatalogStore).
var groupStyle = GroupStyle.threeLevel;

String formatGroup(int a) => switch (groupStyle) {
  GroupStyle.threeLevel => '${(a >> 11) & 0x1F}/${(a >> 8) & 0x07}/${a & 0xFF}',
  GroupStyle.twoLevel => '${(a >> 11) & 0x1F}/${a & 0x7FF}',
  GroupStyle.free => '$a',
};

String formatIndividual(int a) => '${(a >> 12) & 0x0F}.${(a >> 8) & 0x0F}.${a & 0xFF}';

/// Parses "1.1.5". `null` if invalid.
int? parseIndividual(String s) {
  final p = s.trim().split('.').map(_parsePart).toList();
  return switch (p) {
    [final a?, final l?, final d?] when a <= 15 && l <= 15 && d <= 255 => (a << 12) | (l << 8) | d,
    _ => null,
  };
}

/// Parses "1/2/3" (3-level) or "1/234" (2-level). `null` if invalid.
int? parseGroup(String s) {
  final p = s.trim().split('/').map(_parsePart).toList();
  if (p.any((v) => v == null)) return null;
  return switch (p) {
    [final m?, final mi?, final sub?] when m <= 31 && mi <= 7 && sub <= 255 => (m << 11) | (mi << 8) | sub,
    [final m?, final sub?] when m <= 31 && sub <= 2047 => (m << 11) | sub,
    // Free address only in projects with free style (otherwise "5" would be ambiguous).
    [final free?] when groupStyle == GroupStyle.free && free <= 0xFFFF => free,
    _ => null,
  };
}

/// Digits only: `int.tryParse` would also accept "-3" or "+3", and negative parts would result in a
/// completely different address after shifting.
int? _parsePart(String s) => RegExp(r'^\d{1,5}$').hasMatch(s) ? int.parse(s) : null;

String hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

/// Parses hex like "0C 1A" or "0c1a". `null` if invalid/empty.
List<int>? parseHex(String s) {
  final clean = s.replaceAll(RegExp(r'[\s:,-]|0x'), '');
  if (clean.isEmpty || clean.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(clean)) {
    return null;
  }
  return [for (var i = 0; i < clean.length; i += 2) int.parse(clean.substring(i, i + 2), radix: 16)];
}

/// Decode a 2-byte float (DPT 9.xxx).
double decodeDpt9(List<int> b) {
  var mantissa = ((b[0] & 0x07) << 8) | b[1];
  if (b[0] & 0x80 != 0) mantissa -= 2048;
  final exponent = (b[0] >> 3) & 0x0F;
  return 0.01 * mantissa * (1 << exponent);
}

/// Encode a 2-byte float (DPT 9.xxx). `null` outside the range.
List<int>? encodeDpt9(double value) {
  final scaled = value * 100;
  for (var e = 0; e <= 15; e++) {
    final m = (scaled / (1 << e)).round();
    if (m >= -2048 && m <= 2047) {
      final raw = m & 0xFFF;
      return [((raw >> 11) & 1) << 7 | e << 3 | (raw >> 8) & 0x07, raw & 0xFF];
    }
  }
  return null;
}

List<String> get _weekdays => [
  '',
  s.weekdayMon,
  s.weekdayTue,
  s.weekdayWed,
  s.weekdayThu,
  s.weekdayFri,
  s.weekdaySat,
  s.weekdaySun,
];

String _two(int v) => v.toString().padLeft(2, '0');

/// 3 bytes without a datapoint type: date (DPT 11) if the year matches the reception time,
/// otherwise time of day (DPT 10) if it is valid. Otherwise no interpretation.
String? _guess3(List<int> d, int year) {
  final date = d[0] >= 1 && d[0] <= 31 && d[1] >= 1 && d[1] <= 12 && d[2] < 100;
  if (date && ((d[2] - year % 100).abs() <= 1)) return _dpt11(d);
  if ((d[0] & 0x1F) < 24 && d[1] < 60 && d[2] < 60) return _dpt10(d);
  return null;
}

String _dpt10(List<int> d) {
  final day = _weekdays[d[0] >> 5];
  return '${day.isEmpty ? '' : '$day '}${_two(d[0] & 0x1F)}:${_two(d[1] & 0x3F)}:${_two(d[2] & 0x3F)}';
}

String _dpt11(List<int> d) {
  final y = d[2] & 0x7F;
  return _date(y < 90 ? 2000 + y : 1900 + y, d[1] & 0x0F, d[0] & 0x1F);
}

/// 8 bytes without a datapoint type: date and time (DPT 19) if the year and fields match.
bool _isDateTime(List<int> d, int year) =>
    (1900 + d[0] - year).abs() <= 1 &&
    (d[1] & 0x0F) >= 1 &&
    (d[1] & 0x0F) <= 12 &&
    (d[2] & 0x1F) >= 1 &&
    (d[3] & 0x1F) < 24 &&
    (d[4] & 0x3F) < 60 &&
    (d[5] & 0x3F) < 60;

String _dpt19(List<int> d) =>
    '${_date(1900 + d[0], d[1] & 0x0F, d[2] & 0x1F)} '
    '${_two(d[3] & 0x1F)}:${_two(d[4] & 0x3F)}:${_two(d[5] & 0x3F)}';

/// Date depending on the language as "31.12.2024" or "2024-12-31".
String _date(int year, int month, int day) =>
    s.localeName.startsWith('de') ? '${_two(day)}.${_two(month)}.$year' : '$year-${_two(month)}-${_two(day)}';

String _num(double v) =>
    v.isFinite && v.abs() < 1e9 ? localizeDecimal(v.toStringAsFixed(v == v.roundToDouble() ? 0 : 3)) : v.toString();
