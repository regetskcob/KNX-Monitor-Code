import 'dart:typed_data';

import '../l10n/locale_controller.dart';
import 'group_catalog.dart';
import 'telegram.dart';

/// Decodes [t] according to [dpt] into plain text with unit. `null` if the type is unknown or the
/// length does not match.
String? decodeDpt(Dpt dpt, Telegram t) {
  if (t.type == TelegramType.read) return null;
  final d = t.data;
  final bd = ByteData.sublistView(d);

  if (t.isSmall) {
    final v = d.isEmpty ? 0 : d[0];
    return switch (dpt.main) {
      1 => _bool(dpt.sub, v & 1 == 1),
      2 => '${v & 2 != 0 ? s.dpt2Forced : s.dpt2Free} · ${v & 1}',
      3 => _step(dpt.sub, v),
      _ => null,
    };
  }

  return switch ((dpt.main, d.length)) {
    (5, 1) => switch (dpt.sub) {
      1 => '${_n(d[0] * 100 / 255, 0)} %',
      3 => '${_n(d[0] * 360 / 255, 0)} °',
      _ => '${d[0]}',
    },
    (6, 1) => '${bd.getInt8(0)}${dpt.sub == 1 ? ' %' : ''}',
    (7, 2) => '${formatInt(bd.getUint16(0))}${_unit7[dpt.sub] ?? ''}',
    (8, 2) => dpt.sub == 10 ? '${_n(bd.getInt16(0) / 100, 2)} %' : formatInt(bd.getInt16(0)),
    (9, 2) => _scaled(decodeDpt9(d), _unit9[dpt.sub] ?? ''),
    (10, 3) => t.interpretations.first.$2,
    (11, 3) => t.interpretations[1].$2,
    (12, 4) => formatInt(bd.getUint32(0)),
    (13, 4) => _scaled(bd.getInt32(0).toDouble(), _unit13[dpt.sub] ?? ''),
    (14, 4) => _scaled(bd.getFloat32(0), _unit14[dpt.sub] ?? ''),
    (16, _) => String.fromCharCodes(d.where((b) => b != 0)),
    (17, 1) => s.dptSceneNumber((d[0] & 0x3F) + 1),
    (18, 1) => d[0] & 0x80 != 0 ? s.dptSceneStore((d[0] & 0x3F) + 1) : s.dptSceneRecall((d[0] & 0x3F) + 1),
    (19, 8) => t.interpretations.first.$2,
    (20, 1) when dpt.sub == 102 => _hvac(d[0]) ?? '${d[0]}',
    (232, 3) => '#${hex(d).replaceAll(' ', '')}',
    _ => null,
  };
}

/// Formats with the language's decimal separator, without superfluous zeros.
String _n(double v, int digits) {
  if (!v.isFinite) return '$v';
  var text = v.toStringAsFixed(digits);
  if (text.contains('.')) text = text.replaceFirst(RegExp(r'\.?0+$'), '');
  return localizeDecimal(text);
}

/// Value with unit; power and energy from 1000 upwards in the next unit ("1.250 W" → "1,25 kW",
/// "15.300 Wh" → "15,3 kWh").
String formatWithUnit(double v, String unit) => _scaled(v, unit);

String _scaled(double v, String unit) {
  final next = const {' W': ' kW', ' Wh': ' kWh', ' VAh': ' kVAh', ' VARh': ' kVARh', ' VA': ' kVA'}[unit];
  if (next != null && v.abs() >= 1000) return _scaled(v / 1000, next);
  return '${_n(v, 2)}$unit';
}

/// Plain text for 0 and 1 of a DPT 1 subtype, e.g. („Auf“, „Ab“) (up, down) for 1.008.
(String, String) dpt1Labels(int? sub) => switch (sub) {
  2 => (s.dpt1False, s.dpt1True),
  3 => (s.dpt1Disable, s.dpt1Enable),
  5 => (s.dpt1NoAlarm, s.dpt1Alarm),
  7 => (s.dpt1Decrease, s.dpt1Increase),
  8 => (s.dpt1Up, s.dpt1Down),
  9 => (s.dpt1Open, s.dpt1Close),
  10 => (s.dpt1Stop, s.dpt1Start),
  11 => (s.dpt1Inactive, s.dpt1Active),
  17 => (s.dpt1Trigger, s.dpt1Trigger),
  18 => (s.dpt1NotOccupied, s.dpt1Occupied),
  19 => (s.dpt1Closed, s.dpt1Opened),
  24 => (s.dpt1Day, s.dpt1Night),
  _ => (s.dpt1Off, s.dpt1On),
};

String _bool(int? sub, bool v) {
  final (off, on) = dpt1Labels(sub);
  return v ? on : off;
}

String _step(int? sub, int v) {
  final up = v & 0x08 != 0;
  final steps = v & 0x07;
  final dir = sub == 8 ? (up ? s.dpt1Down : s.dpt1Up) : (up ? s.dpt3Brighter : s.dpt3Darker);
  return steps == 0 ? s.dpt1Stop : '$dir · 1/${1 << (steps - 1)}';
}

const _unit7 = {5: ' s', 6: ' min', 7: ' h', 12: ' mA', 13: ' lx', 600: ' K'};

const _unit9 = {
  1: ' °C',
  2: ' K',
  3: ' K/h',
  4: ' lx',
  5: ' m/s',
  6: ' Pa',
  7: ' %',
  8: ' ppm',
  9: ' m³/h',
  10: ' s',
  11: ' ms',
  20: ' mV',
  21: ' mA',
  22: ' W/m²',
  24: ' kW',
  25: ' l/h',
  26: ' l/m²',
  27: ' °F',
  28: ' km/h',
  29: ' g/m³',
  30: ' µg/m³',
};

const _unit13 = {10: ' Wh', 11: ' VAh', 12: ' VARh', 13: ' kWh'};

const _unit14 = {7: ' °', 19: ' A', 27: ' V', 31: ' J', 33: ' Hz', 56: ' W', 57: '', 68: ' °C', 76: ' m³'};

String? _hvac(int mode) => switch (mode) {
  0 => s.hvacAuto,
  1 => s.hvacComfort,
  2 => s.hvacStandby,
  3 => s.hvacEconomy,
  4 => s.hvacProtection,
  _ => null,
};

/// Whether [encodeForDpt] can write this DPT.
bool canEncodeDpt(Dpt dpt) => const {1, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 20, 232}.contains(dpt.main);

/// Input format for fields that do not expect a number.
String? dptInputHint(Dpt dpt) => switch (dpt.main) {
  10 => 'hh:mm:ss',
  11 => 'TT.MM.JJJJ',
  16 => 'Text (max. 14)',
  232 => '#RRGGBB',
  _ => null,
};

/// Encodes user input for [dpt]. Result: either `small` (≤ 6 bit) or `data`. `null` for invalid
/// input.
({int? small, List<int> data})? encodeForDpt(Dpt dpt, String input) {
  switch (dpt.main) {
    case 16:
      // Text, 14 characters ISO 8859-1; empty is allowed (e.g. clears a display).
      if (input.length > 14 || input.codeUnits.any((c) => c > 0xFF)) return null;
      return (small: null, data: [...input.codeUnits, ...List.filled(14 - input.length, 0)]);
    case 10:
      final m = RegExp(r'^\s*(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?\s*$').firstMatch(input);
      if (m == null) return null;
      final (h, min, sec) = (int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3] ?? '0'));
      return h < 24 && min < 60 && sec < 60 ? (small: null, data: [h, min, sec]) : null;
    case 11:
      final de = RegExp(r'^\s*(\d{1,2})\.(\d{1,2})\.(\d{4})\s*$').firstMatch(input);
      final iso = RegExp(r'^\s*(\d{4})-(\d{1,2})-(\d{1,2})\s*$').firstMatch(input);
      final (int y, int mo, int d) = de != null
          ? (int.parse(de[3]!), int.parse(de[2]!), int.parse(de[1]!))
          : iso != null
          ? (int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!))
          : (0, 0, 0);
      if (y < 1990 || y > 2089 || mo < 1 || mo > 12 || d < 1 || d > 31) return null;
      return (small: null, data: [d, mo, y % 100]);
    case 232:
      final hexColor = RegExp(r'^\s*#?([0-9a-fA-F]{6})\s*$').firstMatch(input);
      if (hexColor != null) {
        final v = int.parse(hexColor[1]!, radix: 16);
        return (small: null, data: [v >> 16, (v >> 8) & 0xFF, v & 0xFF]);
      }
      final rgb = input.split(RegExp(r'[,;\s]+')).where((p) => p.isNotEmpty).map(int.tryParse).toList();
      if (rgb.length == 3 && rgb.every((c) => c != null && c >= 0 && c <= 255)) {
        return (small: null, data: [for (final c in rgb) c!]);
      }
      return null;
  }
  final s = input.trim().replaceAll(',', '.').replaceAll(RegExp(r'[^\d.\-]'), '');
  final v = double.tryParse(s);
  if (v == null) return null;
  switch (dpt.main) {
    case 1:
      return v == 0 || v == 1 ? (small: v.toInt(), data: const []) : null;
    case 5:
      final raw = switch (dpt.sub) {
        1 => (v * 255 / 100).round(),
        3 => (v * 255 / 360).round(),
        _ => v.round(),
      };
      return raw >= 0 && raw <= 255 ? (small: null, data: [raw]) : null;
    case 6:
      return v >= -128 && v <= 127 ? (small: null, data: [v.round() & 0xFF]) : null;
    case 7:
      final r = v.round();
      return r >= 0 && r <= 0xFFFF ? (small: null, data: [r >> 8, r & 0xFF]) : null;
    case 8:
      final r = v.round();
      return r >= -32768 && r <= 32767 ? (small: null, data: [(r >> 8) & 0xFF, r & 0xFF]) : null;
    case 12:
      final r = v.round();
      return r >= 0 && r <= 0xFFFFFFFF
          ? (small: null, data: [for (var i = 3; i >= 0; i--) (r >> (8 * i)) & 0xFF])
          : null;
    case 13:
      final r = v.round();
      return r >= -2147483648 && r <= 2147483647
          ? (small: null, data: [for (var i = 3; i >= 0; i--) (r >> (8 * i)) & 0xFF])
          : null;
    case 20:
      final r = v.round();
      return r >= 0 && r <= 255 ? (small: null, data: [r]) : null;
    case 9:
      final b = encodeDpt9(v);
      return b == null ? null : (small: null, data: b);
    case 14:
      final bd = ByteData(4)..setFloat32(0, v);
      return (small: null, data: bd.buffer.asUint8List());
    case 17:
      final r = v.round();
      return r >= 1 && r <= 64 ? (small: null, data: [r - 1]) : null;
    default:
      return null;
  }
}

/// Unit of a DPT for input fields, e.g. "°C" for 9.001. Empty if there is none.
String dptUnit(Dpt d) =>
    (switch (d.main) {
              5 => const {1: '%', 3: '°'}[d.sub],
              6 => d.sub == 1 ? '%' : null,
              7 => _unit7[d.sub],
              9 => _unit9[d.sub],
              13 => _unit13[d.sub],
              14 => _unit14[d.sub],
              _ => null,
            } ??
            '')
        .trim();

/// Numeric value for history charts, according to [dpt] or heuristically. `null` if no meaningful
/// numeric value can be derived (e.g. text, time).
double? numericValue(Dpt? dpt, Telegram t) {
  if (t.type == TelegramType.read || t.data.isEmpty) return null;
  final d = t.data;
  final bd = ByteData.sublistView(d);
  if (t.isSmall) return dpt == null || dpt.main <= 2 ? d[0].toDouble() : null;
  return switch ((dpt?.main, d.length)) {
    (5, 1) when dpt!.sub == 1 => d[0] * 100 / 255,
    (5 || 6 || null, 1) => dpt?.main == 6 ? bd.getInt8(0).toDouble() : d[0].toDouble(),
    (7, 2) => bd.getUint16(0).toDouble(),
    (8, 2) => bd.getInt16(0).toDouble(),
    (9 || null, 2) => decodeDpt9(d),
    (12, 4) => bd.getUint32(0).toDouble(),
    (13, 4) => bd.getInt32(0).toDouble(),
    (14, 4) => bd.getFloat32(0),
    _ => null,
  };
}
