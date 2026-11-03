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
Recording parseEtsXml(String xml, {required String name}) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } on XmlException catch (e) {
    throw FormatException(e.message);
  }
  final telegrams = <Telegram>[];
  for (final el in doc.findAllElements('Telegram')) {
    final raw = parseHex(el.getAttribute('RawData') ?? '');
    final time = DateTime.tryParse(el.getAttribute('Timestamp') ?? '')?.toLocal();
    if (raw == null || time == null) continue;
    final t = Telegram.fromCemi(Uint8List.fromList(raw), time: time);
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

Uint8List utf8Bytes(String text) => Uint8List.fromList(utf8.encode(text));
