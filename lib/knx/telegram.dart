import 'dart:typed_data';

import 'package:knx/knx.dart';

import '../l10n/locale_controller.dart';

// The protocol part (telegram, cEMI, addresses, hex) lives in package:knx; this library adds the
// app's texts and the group address style of the loaded project.
export 'package:knx/knx.dart';

/// Current style; follows the loaded project (see CatalogStore).
var groupStyle = GroupStyle.threeLevel;

/// Group address in the style of the loaded project ([groupStyle]).
String formatGroup(int a) => formatGroupAddress(a, groupStyle);

/// Parses "1/2/3" (3-level) or "1/234" (2-level); a plain number only in projects with free style.
/// `null` if invalid.
int? parseGroup(String s) => parseGroupAddress(s, groupStyle);

/// Texts of a telegram for the UI (language of the app, style of the project).
extension TelegramTexts on Telegram {
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
