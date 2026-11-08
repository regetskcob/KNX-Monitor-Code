import 'dart:convert';
import 'dart:typed_data';

import 'package:knx/knx.dart';
import 'package:pointycastle/digests/sha256.dart';

import 'dpt_value.dart';
import 'exporter.dart';

/// Every group telegram as one MQTT message (issue #11): topic
/// `<prefix>/telegram/<main>/<middle>/<sub>`, payload JSON with the receive
/// time, what the ETS project knows (name, DPT, decoded value, unit) and the
/// fields that let a database notice lost messages (`seq`, `boot`, see
/// [TelegramMeta]).
///
/// Pure translation from a history line (see [telegramJson]) to topic and
/// payload; [MqttBridge.onTelegram] sends it. Repeats are left out unless
/// [repeats] is on, as they carry nothing new.
///
/// KNX Data Secure telegrams arrive decrypted; sending them would put exactly
/// the data the installer chose to protect in plain text on the broker, where
/// every MQTT user can read it. They are left out unless [secure] is on.
class TelegramStream {
  const TelegramStream({
    this.prefix = 'knx_monitor',
    this.repeats = false,
    this.secure = false,
    bool raw = false,
    this.rawOnly = false,
    this.filter = GroupFilter.all,
  }) : raw = raw || rawOnly;

  final String prefix;
  final bool repeats;

  /// Whether decrypted KNX Data Secure telegrams are sent (marked `secure`).
  final bool secure;

  /// Raw data on top: full cEMI frame, frame kind, priority, acknowledge
  /// request and a [dedupKey] (add-on option `mqtt_raw`, MQTT_RAW=true).
  final bool raw;

  /// Raw data only: no name, DPT, value or unit from the ETS project, for
  /// databases that decode the values themselves (`mqtt_raw_only`,
  /// MQTT_RAW_ONLY=true). Implies [raw].
  final bool rawOnly;

  /// Group addresses that are sent; [GroupFilter.all] by default.
  final GroupFilter filter;

  static const _types = ['read', 'response', 'write'];
  static const _priorities = ['system', 'normal', 'urgent', 'low'];

  /// Whether a telegram to [group] passes [filter].
  bool accepts(int group) => filter.matches(group);

  /// Topic and payload for [line]; `null` for a line that is not sent
  /// (repeat with [repeats] off, filtered out, malformed line).
  (String, String)? message(
    Map<String, Object?> line,
    ExportSource source, {
    bool secure = false,
    TelegramMeta meta = const TelegramMeta(),
  }) {
    final payload = this.payload(line, source, secure: secure, meta: meta);
    if (payload == null) return null;
    return ('$prefix/telegram/${payload['ga']}', jsonEncode(payload));
  }

  /// The payload as a map; see [message].
  Map<String, Object?>? payload(
    Map<String, Object?> line,
    ExportSource source, {
    bool secure = false,
    TelegramMeta meta = const TelegramMeta(),
  }) {
    if (secure && !this.secure) return null;
    final micros = line['t'];
    final group = line['d'];
    final sender = line['s'];
    final type = line['y'];
    if (micros is! int || group is! int || sender is! int || type is! int || type < 0 || type > 2) return null;
    if (!filter.matches(group)) return null;
    final repeat = line['rp'] == true;
    if (repeat && !repeats) return null;
    final raw = line['x'] as String? ?? '';
    final small = line['m'] == true;
    final hasValue = type != 0;
    final dpt = rawOnly ? null : source.dptOf(group);
    final name = rawOnly ? null : source.nameOf(group);
    final senderName = rawOnly ? null : meta.deviceName?.call(sender);
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
    final cemi = line['r'] as String?;
    final frame = cemi == null ? null : hexBytes(cemi);
    final outgoing = line['o'] == true;
    return {
      't': micros ~/ 1000,
      'ts': isoMicros(micros),
      'inst': ?meta.installation,
      'boot': ?meta.boot,
      'seq': ?meta.seq,
      'ga': formatGroup3(group),
      'ga_name': ?name,
      'src': formatIndividual(sender),
      'src_name': ?senderName,
      'type': _types[type],
      'dpt': ?(dpt == null
          ? null
          : dpt.$2 == null
          ? '${dpt.$1}'
          : '${dpt.$1}.${dpt.$2.toString().padLeft(3, '0')}'),
      if (hasValue) 'value': ?value,
      if (hasValue) 'unit': ?unit,
      'hop': line['h'] as int? ?? 6,
      // Tap points (issue #8): where the telegram was seen, the first one first. Only with
      // further tap points.
      if (_tapsOf(line) case final taps?) ...{
        'taps': taps,
        // Stable names next to the numbers: a number changes when a tap point is removed, the
        // name stays.
        'tap_names': [for (final t in taps) meta.tapName(t)],
      },
      if (hasValue) 'raw': raw,
      'repeat': repeat,
      if (secure) 'secure': true,
      if (outgoing) 'outgoing': true,
      if (this.raw) ...{
        'msg': switch (frame) {
          [0x2E, ...] => 'con',
          [0x29, ...] => 'ind',
          _ => outgoing ? 'con' : 'ind',
        },
        'prio': _priorities[(line['p'] as int? ?? 3) & 0x03],
        'ack_req': ?_ackRequest(frame),
        'cemi': ?cemi,
        'key': dedupKey(sender, group, type, raw, small: small),
      },
      'project': ?meta.project,
    };
  }

  /// Numbers of the tap points that saw [line], the first one first; null with one tap point.
  static List<int>? _tapsOf(Map<String, Object?> line) {
    if (line['tp'] == null && line['sg'] == null) return null;
    return [
      line['tp'] as int? ?? 0,
      for (final s in (line['sg'] as List? ?? const []))
        if (s is List && s.isNotEmpty && s.first is int) s.first as int,
    ];
  }

  /// Acknowledge request from the cEMI frame (bit 1 of control field 1,
  /// after the additional info); `null` without a usable frame.
  static bool? _ackRequest(Uint8List? frame) {
    if (frame == null || frame.length < 3) return null;
    final ctrl1 = 2 + frame[1];
    if (ctrl1 >= frame.length) return null;
    return frame[ctrl1] & 0x02 != 0;
  }

  /// Checksum of what the telegram says, without the way it took: sender,
  /// group address, APCI and payload, but not hop count, repeat bit,
  /// priority or frame kind. The same telegram seen at two tap points (#8),
  /// or once more as a repeat, gets the same key. First 16 hex characters of
  /// SHA-256 over `src(2) dst(2) type(1) small(1) payload`.
  static String dedupKey(int source, int group, int type, String payload, {bool small = false}) {
    final data = hexBytes(payload);
    final bytes = Uint8List(6 + data.length)
      ..[0] = source >> 8 & 0xFF
      ..[1] = source & 0xFF
      ..[2] = group >> 8 & 0xFF
      ..[3] = group & 0xFF
      ..[4] = type
      ..[5] = small ? 1 : 0
      ..setRange(6, 6 + data.length, data);
    final hash = SHA256Digest().process(bytes);
    return [for (final b in hash.take(8)) b.toRadixString(16).padLeft(2, '0')].join();
  }

  /// ISO 8601 in UTC with always six decimal places, e.g.
  /// `2026-11-07T21:56:22.430079Z` (Dart's own form drops zero microseconds).
  static String isoMicros(int micros) {
    final d = DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
    String two(int v) => v.toString().padLeft(2, '0');
    final fraction = (micros % 1000000).toString().padLeft(6, '0');
    return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}'
        'T${two(d.hour)}:${two(d.minute)}:${two(d.second)}.${fraction}Z';
  }

  /// Whole numbers without ".0", so that JSON readers see an integer.
  static num _plain(double v) => v == v.roundToDouble() && v.abs() < 1e15 ? v.toInt() : v;

  /// Three-level group address ("1/2/3"), whatever style the project uses:
  /// topics need a fixed layout so ranges (`telegram/1/#`) can be subscribed.
  static String formatGroup3(int g) => '${(g >> 11) & 0x1F}/${(g >> 8) & 0x07}/${g & 0xFF}';
}

/// What the bridge knows beyond the telegram line: running number, server
/// start, installation and ETS project state. All optional; missing fields
/// are left out of the payload.
class TelegramMeta {
  const TelegramMeta({this.seq, this.boot, this.installation, this.project, this.deviceName, this.tapNames});

  /// Running number per server start ([boot]); a gap means a lost message.
  final int? seq;

  /// Random id per server start (UUID v4); a new value means [seq] restarted.
  final String? boot;

  /// Installation id (default the active installation, MQTT_INSTALLATION).
  final String? installation;

  /// `{id, date}` of the loaded ETS project (see [CatalogInfo.project]).
  final Map<String, Object?>? project;

  /// Device name of a sender (individual address) from the ETS project.
  final String? Function(int individual)? deviceName;

  /// Names of the tap points by number (issue #8): `main` for the normal connection, then the
  /// names set for the further tap points. Null without further tap points.
  final List<String>? tapNames;

  /// Name of tap point [tap]; `tap <n>` when it is no longer configured.
  String tapName(int tap) {
    final names = tapNames;
    return names != null && tap >= 0 && tap < names.length ? names[tap] : 'tap $tap';
  }
}

/// Group addresses that go to MQTT, e.g. `1/#,3/2/#,4/1/7` (three-level,
/// like the topics): `#` as the last level takes everything below it. Empty
/// sends everything.
class GroupFilter {
  const GroupFilter._(this._rules, this.text, this.invalid);

  /// No filter: every group address.
  static const all = GroupFilter._([], '', []);

  /// Parses comma- or space-separated patterns; unreadable ones end up in
  /// [invalid] (the server logs them) and match nothing.
  factory GroupFilter.parse(String? text) {
    final rules = <(int, int)>[];
    final invalid = <String>[];
    final parts = (text ?? '').split(RegExp(r'[,;\s]+')).where((p) => p.isNotEmpty).toList();
    for (final p in parts) {
      final rule = _rule(p);
      if (rule == null) {
        invalid.add(p);
      } else {
        rules.add(rule);
      }
    }
    if (parts.isEmpty) return all;
    return GroupFilter._(rules, parts.join(','), invalid);
  }

  /// (mask, value) per pattern on the 16-bit group address.
  final List<(int, int)> _rules;

  /// The patterns as read (normalised, comma-separated); empty = no filter.
  final String text;

  /// Patterns that could not be read.
  final List<String> invalid;

  /// Whether no filter is set.
  bool get isAll => text.isEmpty;

  bool matches(int group) {
    if (isAll) return true;
    for (final (mask, value) in _rules) {
      if (group & mask == value) return true;
    }
    return false;
  }

  static const _bits = [5, 3, 8];
  static const _shifts = [11, 8, 0];

  static (int, int)? _rule(String pattern) {
    final levels = pattern.split('/');
    if (levels.isEmpty || levels.length > 3) return null;
    var mask = 0;
    var value = 0;
    for (final (i, level) in levels.indexed) {
      if (level == '#') {
        return i == levels.length - 1 ? (mask, value) : null;
      }
      final n = int.tryParse(level);
      if (n == null || n < 0 || n >= 1 << _bits[i]) return null;
      mask |= ((1 << _bits[i]) - 1) << _shifts[i];
      value |= n << _shifts[i];
    }
    // Without "#" only a complete address.
    return levels.length == 3 ? (mask, value) : null;
  }
}
