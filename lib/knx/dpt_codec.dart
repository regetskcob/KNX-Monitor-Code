import 'dart:typed_data';

import '../l10n/locale_controller.dart';
import 'dali.dart';
import 'dali_text.dart';
import 'telegram.dart';

export 'package:knx/knx.dart' show canEncodeDpt, dptUnit, encodeForDpt;

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

  // DALI diagnostics of a KNX-DALI gateway: decoded for display only, never sent.
  if (isDaliDpt(dpt.main, dpt.sub)) return daliValueText(dpt, t);

  return switch ((dpt.main, d.length)) {
    (5, 1) => switch (dpt.sub) {
      1 => '${_n(d[0] * 100 / 255, 0)} %',
      3 => '${_n(d[0] * 360 / 255, 0)} °',
      _ => '${d[0]}',
    },
    (6, 1) => '${bd.getInt8(0)}${dpt.sub == 1 ? ' %' : ''}',
    (7, 2) => '${formatInt(bd.getUint16(0))}${_spaced(dptUnit(dpt))}',
    (8, 2) => dpt.sub == 10 ? '${_n(bd.getInt16(0) / 100, 2)} %' : formatInt(bd.getInt16(0)),
    (9, 2) => _scaled(decodeDpt9(d), _spaced(dptUnit(dpt))),
    (10, 3) => t.interpretations.first.$2,
    (11, 3) => t.interpretations[1].$2,
    (12, 4) => formatInt(bd.getUint32(0)),
    (13, 4) => _scaled(bd.getInt32(0).toDouble(), _spaced(dptUnit(dpt))),
    (14, 4) => _scaled(bd.getFloat32(0), _spaced(dptUnit(dpt))),
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

/// Unit with a leading space, nothing without a unit.
String _spaced(String unit) => unit.isEmpty ? '' : ' $unit';

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

String? _hvac(int mode) => switch (mode) {
  0 => s.hvacAuto,
  1 => s.hvacComfort,
  2 => s.hvacStandby,
  3 => s.hvacEconomy,
  4 => s.hvacProtection,
  _ => null,
};

/// Input format for fields that do not expect a number.
String? dptInputHint(Dpt dpt) => switch (dpt.main) {
  10 => 'hh:mm:ss',
  11 => 'TT.MM.JJJJ',
  16 => 'Text (max. 14)',
  232 => '#RRGGBB',
  _ => null,
};

/// Numeric value for history charts, according to [dpt] or heuristically. `null` if no meaningful numeric
/// value can be derived (e.g. a read request, text, time).
double? numericValue(Dpt? dpt, Telegram t) =>
    t.type == TelegramType.read ? null : dptNumericValue(dpt, t.data, small: t.isSmall);
