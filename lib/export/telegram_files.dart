import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../model/recording.dart';

/// cEMI raw data of a telegram; reconstructed if not present.
Uint8List cemiOf(Telegram t) {
  if (t.raw.isNotEmpty) return Uint8List.fromList(t.raw);
  final apci = switch (t.type) {
    TelegramType.read => 0x00,
    TelegramType.response => 0x40,
    TelegramType.write => 0x80,
  };
  final ctrl1 = 0x80 | (t.repeated ? 0x00 : 0x20) | 0x10 | (t.priority.index << 2) | (t.confirmError ? 0x01 : 0);
  return Uint8List.fromList([
    t.outgoing ? 0x2E : 0x29,
    0x00,
    ctrl1,
    0x80 | ((t.hopCount & 0x07) << 4),
    t.source >> 8,
    t.source & 0xFF,
    t.destination >> 8,
    t.destination & 0xFF,
    if (t.isSmall || t.type == TelegramType.read) ...[
      1,
      0x00,
      apci | ((t.data.isEmpty ? 0 : t.data[0]) & 0x3F),
    ] else ...[
      1 + t.data.length,
      0x00,
      apci,
      ...t.data,
    ],
  ]);
}

// --- CSV ------------------------------------------------------------------------

/// CSV cell in quotes with protection against formula injection: =, +, -, @ at the start would be
/// executed as a formula by Excel/Numbers (names come from the ETS project and are therefore
/// foreign input).
String csvCell(Object? v) {
  var text = '${v ?? ''}';
  if (text.isNotEmpty && '=+-@\t\r'.contains(text[0])) text = "'$text";
  return '"${text.replaceAll('"', '""')}"';
}

/// CSV according to RFC 4180 (comma, quotes, CRLF).
String buildCsv(List<Telegram> telegrams) {
  final store = CatalogStore.instance;
  const cell = csvCell;

  final rows = [
    [
      'time',
      'type',
      'source',
      'source_name',
      'destination',
      'name',
      'dpt',
      'value',
      'data_hex',
      'sent',
      'repeated',
      'priority',
      'hop_count',
      'cemi',
    ],
    for (final t in [...telegrams]..sort((a, b) => a.time.compareTo(b.time)))
      [
        t.time.toIso8601String(),
        t.type.name,
        t.sourceText,
        store.device(t.source)?.name,
        t.destinationText,
        store.info(t.destination)?.name,
        store.dptOf(t.destination)?.toString(),
        store.value(t),
        hex(t.data).replaceAll(' ', ''),
        t.outgoing ? 1 : 0,
        t.repeated ? 1 : 0,
        t.priority.name,
        t.hopCount,
        hex(cemiOf(t)).replaceAll(' ', ''),
      ],
  ];
  return '${rows.map((r) => r.map(cell).join(',')).join('\r\n')}\r\n';
}

// --- ETS telegram file (XML) ------------------------------------------------------

const _etsNamespace = 'http://knx.org/xml/telegrams/01';

/// Telegrams in the format of the ETS group monitor (`CommunicationLog`).
String buildEtsXml(List<Telegram> telegrams, {String? host}) {
  final items = [...telegrams]..sort((a, b) => a.time.compareTo(b.time));
  String ts(DateTime t) => t.toUtc().toIso8601String();
  final builder = XmlBuilder()..processing('xml', 'version="1.0" encoding="utf-8"');
  builder.element(
    'CommunicationLog',
    attributes: {'xmlns': _etsNamespace},
    nest: () {
      builder.element(
        'RecordStart',
        attributes: {
          'Timestamp': ts(items.isEmpty ? DateTime.now() : items.first.time),
          'Mode': 'LinkLayer',
          'Host': host ?? 'KNX Monitor',
          'ConnectionName': 'KNX Monitor',
          'ConnectorType': 'KnxIpTunneling',
          'MediumType': 'TP',
        },
      );
      for (final t in items) {
        builder.element(
          'Telegram',
          attributes: {
            'Timestamp': ts(t.time),
            'Service': t.outgoing ? 'L_Data.con' : 'L_Data.ind',
            'FrameFormat': 'CommonEmi',
            'RawData': hex(cemiOf(t)).replaceAll(' ', ''),
          },
        );
      }
      builder.element('RecordStop', attributes: {'Timestamp': ts(items.isEmpty ? DateTime.now() : items.last.time)});
    },
  );
  return builder.buildDocument().toXmlString(pretty: true);
}

/// Reads an ETS telegram file as a recording. Throws [FormatException].
///
/// Besides the ETS and our own [buildEtsXml] this accepts what other tools write
/// in the same format:
/// - knx-telegram-store (Home Assistant's KNX integration) and SpectrumKNX,
///   which uses its writer
///   (github.com/XKNX/knx-telegram-store, `src/knx_telegram_store/formats/ets_xml.py`):
///   no `RecordStart`/`RecordStop`, extra `ConnectionName`, single-quoted
///   attributes, timestamps with six fraction digits;
/// - the ETS 6 itself: seven fraction digits, extra `TransportSecurity`;
/// - Gira loggers: `L_Busmon.ind` with raw TP1 frames, local time marked `Z`
///   plus a comment `<!-- timezone offset +01:00 hour -->`;
/// - knx-ultimate (Node-RED): no XML declaration, lowercase hex.
///
/// Namespace or prefix do not matter; timestamps without a zone count as UTC
/// (like knx-telegram-store); telegrams without `RawData` or that are not group
/// telegrams are skipped.
Recording parseEtsXml(String xml, {required String name}) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml.startsWith('﻿') ? xml.substring(1) : xml);
  } on XmlException catch (e) {
    throw FormatException(e.message);
  }
  final zone = _commentOffset(doc);
  final telegrams = <Telegram>[];
  for (final el in doc.descendantElements.where((e) => e.localName == 'Telegram')) {
    final raw = parseHex(_attribute(el, 'RawData') ?? '');
    var time = _etsTime(_attribute(el, 'Timestamp'));
    if (raw == null || time == null) continue;
    if (zone != null) time = time.subtract(zone);
    final cemi = _groupCemi(Uint8List.fromList(raw), _attribute(el, 'Service'));
    final t = cemi == null ? null : Telegram.fromCemi(cemi, time: time.toLocal());
    if (t != null) telegrams.add(t);
  }
  if (telegrams.isEmpty) throw const FormatException('Keine Gruppentelegramme in der Datei.');
  telegrams.sort((a, b) => a.time.compareTo(b.time));
  return Recording(
    id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
    name: name,
    started: telegrams.first.time,
    ended: telegrams.last.time,
    telegrams: telegrams,
  );
}

/// Attribute by local name, with or without a namespace prefix.
String? _attribute(XmlElement el, String name) =>
    el.attributes.where((a) => a.localName == name).firstOrNull?.value.trim();

/// Timestamp of an ETS file as UTC; without a zone it counts as UTC.
DateTime? _etsTime(String? value) {
  if (value == null || value.isEmpty) return null;
  // With `Z` or an offset Dart returns UTC; only times without a zone are local.
  final p = DateTime.tryParse(value);
  if (p == null || p.isUtc) return p;
  return DateTime.utc(p.year, p.month, p.day, p.hour, p.minute, p.second, p.millisecond, p.microsecond);
}

/// Gira: real offset of the local times that are marked `Z`.
Duration? _commentOffset(XmlDocument doc) {
  for (final c in doc.descendants.whereType<XmlComment>()) {
    final m = RegExp(r'timezone\s+offset\s+([+-])(\d{2}):(\d{2})').firstMatch(c.value);
    if (m == null) continue;
    final offset = Duration(hours: int.parse(m[2]!), minutes: int.parse(m[3]!));
    return m[1] == '-' ? -offset : offset;
  }
  return null;
}

/// cEMI L_Data frame of a `Telegram` element: L_Data.ind/.con as is,
/// L_Data.req as sent (.con), `L_Busmon.ind` (message code 0x2B) converted from
/// the raw TP1 frame. `null` if nothing usable.
Uint8List? _groupCemi(Uint8List raw, String? service) {
  if (raw.length < 2) return null;
  if (raw[0] == 0x11) return Uint8List.fromList([0x2E, ...raw.skip(1)]);
  if (raw[0] != 0x2B && service != 'L_Busmon.ind') return raw;
  // Busmonitor: 2B, additional info, TP1 frame (control, source, destination,
  // address type/hop count/length, TPCI/APCI, data, checksum).
  final i = raw[0] == 0x2B ? 2 + raw[1] : 0;
  if (raw.length < i + 8) return null;
  final frame = raw.sublist(i);
  final ctrl = frame[0];
  if (ctrl & 0x80 == 0) return null; // extended frame or acknowledgement
  final length = frame[5] & 0x0F;
  if (frame.length < 6 + length + 2) return null;
  // Checksum: inverted XOR over the frame; a broken frame is no telegram.
  var check = 0;
  for (var k = 0; k < 6 + length + 1; k++) {
    check ^= frame[k];
  }
  if ((check ^ 0xFF) != frame[6 + length + 1]) return null;
  return Uint8List.fromList([
    0x29,
    0x00,
    ctrl & 0xBC,
    frame[5] & 0xF0,
    ...frame.sublist(1, 5),
    length,
    ...frame.sublist(6, 6 + length + 1),
  ]);
}

Uint8List utf8Bytes(String text) => Uint8List.fromList(utf8.encode(text));
