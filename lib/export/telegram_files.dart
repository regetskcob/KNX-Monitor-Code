import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../model/recording.dart';
import '../model/tap_points.dart';

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
/// foreign input). Plain numbers stay numbers: a negative value is no formula, and the
/// apostrophe would turn -3.5 into text in the spreadsheet.
String csvCell(Object? v) {
  var text = '${v ?? ''}';
  final number = v is num || double.tryParse(text) != null;
  if (!number && text.isNotEmpty && '=+-@\t\r'.contains(text[0])) text = "'$text";
  return '"${text.replaceAll('"', '""')}"';
}

/// CSV as UTF-8 with byte order mark: without it Excel reads the file as ANSI
/// and "Küche" becomes "KÃ¼che".
Uint8List csvBytes(String csv) => Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);

/// Local time with its UTC offset (2026-10-25T02:30:00.000+02:00): without the
/// offset the hour that repeats when the clocks go back cannot be told apart.
String isoWithOffset(DateTime time) {
  final local = time.toLocal();
  final offset = local.timeZoneOffset;
  final minutes = offset.inMinutes.abs();
  final sign = offset.isNegative ? '-' : '+';
  final zone = '$sign${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
  return '${local.toIso8601String()}$zone';
}

/// CSV according to RFC 4180 (comma, quotes, CRLF).
///
/// With several tap points (issue #8) a last column `seen_at` lists where each telegram was seen:
/// the origin first, then `label+offset ms/hop` per further sighting, separated by `|`
/// (`1.1|1.2+38.2/5`). Labels are those of the open monitor or recording ([TapScope]), else the tap point's number.
/// Without tap points the file is as before.
String buildCsv(List<Telegram> telegrams) {
  final store = CatalogStore.instance;
  const cell = csvCell;
  final tapped = telegrams.any((t) => t.tap != 0 || t.sightings.isNotEmpty);
  final labels = TapScope.labels;
  String tap(int n) => n >= 0 && n < labels.length ? labels[n] : '${n + 1}';

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
      if (tapped) 'seen_at',
    ],
    for (final t in [...telegrams]..sort((a, b) => a.time.compareTo(b.time)))
      [
        isoWithOffset(t.time),
        t.type.name,
        t.sourceText,
        store.deviceOf(t)?.name,
        t.destinationText,
        store.infoOf(t)?.name,
        store.dptFor(t)?.toString(),
        store.value(t),
        hex(t.data).replaceAll(' ', ''),
        t.outgoing ? 1 : 0,
        t.repeated ? 1 : 0,
        t.priority.name,
        t.hopCount,
        hex(cemiOf(t)).replaceAll(' ', ''),
        if (tapped)
          [
            tap(t.tap),
            for (final x in t.sightings)
              '${tap(x.tap)}+${(x.offset.inMicroseconds / 1000).toStringAsFixed(1)}/${x.hopCount}',
          ].join('|'),
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
          'Host': host ?? 'Busclear',
          'ConnectionName': 'Busclear',
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

/// Why a telegram of an imported file could not be taken over.
enum TelegramSkip {
  /// No raw data (ETS: `RawData`) or fields to build the telegram from.
  noData,

  /// No time, or one that cannot be read.
  time,

  /// Not a group telegram: acknowledgement, device telegram, extended or damaged frame.
  frame,

  /// A line that is not in the file's format (truncated, foreign).
  line,
}

/// Telegrams read from a file, by time, and how many were left out why.
typedef ReadTelegrams = ({List<Telegram> telegrams, Map<TelegramSkip, int> skipped});

/// More telegrams than an import accepts ([maxTelegrams] of the reader).
class TooManyTelegrams implements Exception {
  const TooManyTelegrams(this.limit);
  final int limit;
}

/// The file declares a document type (`<!DOCTYPE`, entities). No telegram file of the ETS or of
/// another tool does; a file that does wants to make the parser expand entities.
class XmlDoctypeRefused implements Exception {
  const XmlDoctypeRefused();
}

/// Longest `RawData` taken seriously: an extended frame has at most 263 bytes.
const _maxRawHex = 1024;

/// Reads an ETS telegram file as a recording. Throws [FormatException] (also for a file with a
/// document type or with more than [maxTelegrams] telegrams).
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
Recording parseEtsXml(String xml, {required String name, int? maxTelegrams}) {
  final List<Telegram> telegrams;
  try {
    telegrams = readEtsXml(xml, maxTelegrams: maxTelegrams).telegrams;
  } on XmlDoctypeRefused {
    throw const FormatException('Die Datei enthält eine DOCTYPE-Deklaration.');
  } on TooManyTelegrams catch (e) {
    throw FormatException('Mehr als ${e.limit} Telegramme.');
  }
  if (telegrams.isEmpty) throw const FormatException('Keine Gruppentelegramme in der Datei.');
  return Recording(
    id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
    name: name,
    started: telegrams.first.time,
    ended: telegrams.last.time,
    telegrams: telegrams,
  );
}

/// The group telegrams of an ETS telegram file ([parseEtsXml] names the accepted variants), by
/// time, and what was skipped.
///
/// Reads the file as a stream of events, without building the document: a month of a busy bus
/// stays a list of telegrams. Entities other than the five predefined ones are never expanded
/// (package:xml knows no others), and a document type is refused outright ([XmlDoctypeRefused]).
/// Throws [FormatException] for text that is not XML, [TooManyTelegrams] beyond [maxTelegrams].
ReadTelegrams readEtsXml(String xml, {int? maxTelegrams}) {
  if (xml.startsWith('﻿')) xml = xml.substring(1);
  final zone = _commentOffset(xml);
  final telegrams = <Telegram>[];
  final skipped = <TelegramSkip, int>{};
  void skip(TelegramSkip why) => skipped[why] = (skipped[why] ?? 0) + 1;
  try {
    for (final event in parseEvents(xml)) {
      if (event is XmlDoctypeEvent) throw const XmlDoctypeRefused();
      if (event is! XmlStartElementEvent || event.localName != 'Telegram') continue;
      final rawText = _attribute(event, 'RawData');
      if (rawText == null || rawText.isEmpty) {
        skip(TelegramSkip.noData);
        continue;
      }
      var time = _etsTime(_attribute(event, 'Timestamp'));
      if (time == null) {
        skip(TelegramSkip.time);
        continue;
      }
      final raw = rawText.length > _maxRawHex ? null : parseHex(rawText);
      if (zone != null) time = time.subtract(zone);
      final cemi = raw == null ? null : _groupCemi(Uint8List.fromList(raw), _attribute(event, 'Service'));
      final t = cemi == null ? null : Telegram.fromCemi(cemi, time: time.toLocal());
      if (t == null) {
        skip(TelegramSkip.frame);
        continue;
      }
      if (maxTelegrams != null && telegrams.length >= maxTelegrams) throw TooManyTelegrams(maxTelegrams);
      telegrams.add(t);
    }
  } on XmlException catch (e) {
    throw FormatException(e.message);
  }
  telegrams.sort((a, b) => a.time.compareTo(b.time));
  return (telegrams: telegrams, skipped: skipped);
}

/// Attribute by local name, with or without a namespace prefix.
String? _attribute(XmlStartElementEvent el, String name) =>
    el.attributes.where((a) => a.localName == name).firstOrNull?.value.trim();

/// Timestamp of an ETS file as UTC; without a zone it counts as UTC.
DateTime? _etsTime(String? value) {
  if (value == null || value.isEmpty || value.length > 64) return null;
  // With `Z` or an offset Dart returns UTC; only times without a zone are local.
  final p = DateTime.tryParse(value);
  if (p == null || p.isUtc) return p;
  return DateTime.utc(p.year, p.month, p.day, p.hour, p.minute, p.second, p.millisecond, p.microsecond);
}

/// Gira: real offset of the local times that are marked `Z`.
Duration? _commentOffset(String xml) {
  final m = RegExp(r'<!--[^>]{0,200}?timezone\s+offset\s+([+-])(\d{2}):(\d{2})').firstMatch(xml);
  if (m == null) return null;
  final offset = Duration(hours: int.parse(m[2]!), minutes: int.parse(m[3]!));
  return m[1] == '-' ? -offset : offset;
}

// --- Reading our own CSV ----------------------------------------------------------

/// Whether [text] starts with the header row of [buildCsv].
bool looksLikeTelegramCsv(String text) {
  final end = text.indexOf('\n');
  final header = (end < 0 ? text : text.substring(0, end)).replaceAll('"', '').replaceAll('﻿', '').trim();
  final columns = header.split(RegExp('[,;\t]'));
  return columns.contains('time') && columns.contains('cemi') && columns.contains('destination');
}

/// The telegrams of a CSV written by [buildCsv], by time, and what was skipped. The frame comes
/// from the column `cemi`, the time from `time` (with its offset); names, type and value in the
/// file are not taken over, the project of the telegram's time names it again. Tap points
/// (`seen_at`) are not read back: the file only has their labels. A spreadsheet may have saved
/// the file with `;` or tabs.
///
/// Throws [FormatException] without the header, [TooManyTelegrams] beyond [maxTelegrams].
ReadTelegrams readTelegramCsv(String text, {int? maxTelegrams}) {
  if (text.startsWith('﻿')) text = text.substring(1);
  if (!looksLikeTelegramCsv(text)) throw const FormatException('Keine Telegramm-CSV.');
  final lines = const LineSplitter().convert(text);
  final separator = [
    ',',
    ';',
    '\t',
  ].reduce((a, b) => _csvCells(lines.first, a).length >= _csvCells(lines.first, b).length ? a : b);
  final header = _csvCells(lines.first, separator);
  final timeCol = header.indexOf('time');
  final cemiCol = header.indexOf('cemi');
  final sentCol = header.indexOf('sent');
  final telegrams = <Telegram>[];
  final skipped = <TelegramSkip, int>{};
  void skip(TelegramSkip why) => skipped[why] = (skipped[why] ?? 0) + 1;
  for (final line in lines.skip(1)) {
    if (line.trim().isEmpty) continue;
    final cells = _csvCells(line, separator);
    if (cells.length <= timeCol || cells.length <= cemiCol) {
      skip(TelegramSkip.line);
      continue;
    }
    final time = cells[timeCol].length > 64 ? null : DateTime.tryParse(cells[timeCol]);
    if (time == null) {
      skip(TelegramSkip.time);
      continue;
    }
    final hexText = cells[cemiCol];
    if (hexText.isEmpty) {
      skip(TelegramSkip.noData);
      continue;
    }
    final raw = hexText.length > _maxRawHex ? null : parseHex(hexText);
    var t = raw == null ? null : Telegram.fromCemi(Uint8List.fromList(raw), time: time.toLocal());
    if (t == null) {
      skip(TelegramSkip.frame);
      continue;
    }
    // A sent telegram whose frame was rebuilt as received by an older export.
    if (!t.outgoing && sentCol >= 0 && cells.length > sentCol && cells[sentCol] == '1') {
      t = Telegram.fromCemi(Uint8List.fromList([0x2E, ...raw!.skip(1)]), time: time.toLocal()) ?? t;
    }
    if (maxTelegrams != null && telegrams.length >= maxTelegrams) throw TooManyTelegrams(maxTelegrams);
    telegrams.add(t);
  }
  telegrams.sort((a, b) => a.time.compareTo(b.time));
  return (telegrams: telegrams, skipped: skipped);
}

/// Cells of a CSV line (RFC 4180 quotes; a cell does not span lines in our export).
List<String> _csvCells(String line, String separator) {
  final cells = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == separator) {
      cells.add(cell.toString());
      cell.clear();
    } else {
      cell.write(c);
    }
  }
  cells.add(cell.toString());
  return cells;
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
