import 'dart:convert';

import 'package:knx/knx.dart';

import 'dpt_value.dart';
import 'exporter.dart';

/// Every group telegram as one MQTT message (issue #11, first version): topic
/// `<prefix>/telegram/<main>/<middle>/<sub>`, payload JSON with the receive
/// time in ms and what the ETS project knows (name, DPT, decoded value, unit).
///
/// Pure translation from a history line (see [telegramJson]) to topic and
/// payload; [MqttBridge.onTelegram] sends it. Repeats are left out unless
/// [repeats] is on, as they carry nothing new.
///
/// KNX Data Secure telegrams arrive decrypted; sending them would put exactly
/// the data the installer chose to protect in plain text on the broker, where
/// every MQTT user can read it. They are left out unless [secure] is on.
class TelegramStream {
  const TelegramStream({this.prefix = 'knx_monitor', this.repeats = false, this.secure = false});

  final String prefix;
  final bool repeats;

  /// Whether decrypted KNX Data Secure telegrams are sent (marked `secure`).
  final bool secure;

  static const _types = ['read', 'response', 'write'];

  /// Topic and payload for [line]; `null` for a line that is not sent
  /// (repeat with [repeats] off, malformed line).
  (String, String)? message(Map<String, Object?> line, ExportSource source, {bool secure = false}) {
    final payload = this.payload(line, source, secure: secure);
    if (payload == null) return null;
    return ('$prefix/telegram/${payload['ga']}', jsonEncode(payload));
  }

  /// The payload as a map; see [message].
  Map<String, Object?>? payload(Map<String, Object?> line, ExportSource source, {bool secure = false}) {
    if (secure && !this.secure) return null;
    final micros = line['t'];
    final group = line['d'];
    final sender = line['s'];
    final type = line['y'];
    if (micros is! int || group is! int || sender is! int || type is! int || type < 0 || type > 2) return null;
    final repeat = line['rp'] == true;
    if (repeat && !repeats) return null;
    final raw = line['x'] as String? ?? '';
    final small = line['m'] == true;
    final dpt = source.dptOf(group);
    final name = source.nameOf(group);
    final hasValue = type != 0;
    Object? value;
    String? unit;
    if (hasValue && dpt != null) {
      final number = numericValue(dpt, hexBytes(raw), small: small);
      if (number != null && number.isFinite) {
        value = dpt.$1 == 1 ? number != 0 : _plain(number);
      }
      final u = dptUnit(Dpt(dpt.$1, dpt.$2));
      if (u.isNotEmpty) unit = u;
    }
    return {
      't': micros ~/ 1000,
      'ga': formatGroup3(group),
      'ga_name': ?name,
      'src': formatIndividual(sender),
      'type': _types[type],
      'dpt': ?(dpt == null
          ? null
          : dpt.$2 == null
          ? '${dpt.$1}'
          : '${dpt.$1}.${dpt.$2.toString().padLeft(3, '0')}'),
      if (hasValue) 'value': ?value,
      if (hasValue) 'unit': ?unit,
      if (hasValue) 'raw': raw,
      'repeat': repeat,
      if (secure) 'secure': true,
      if (line['o'] == true) 'outgoing': true,
    };
  }

  /// Whole numbers without ".0", so that JSON readers see an integer.
  static num _plain(double v) => v == v.roundToDouble() && v.abs() < 1e15 ? v.toInt() : v;

  /// Three-level group address ("1/2/3"), whatever style the project uses:
  /// topics need a fixed layout so ranges (`telegram/1/#`) can be subscribed.
  static String formatGroup3(int g) => '${(g >> 11) & 0x1F}/${(g >> 8) & 0x07}/${g & 0xFF}';
}
