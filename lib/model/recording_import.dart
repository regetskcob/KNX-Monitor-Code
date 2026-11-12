/// Reads old recordings from files so they can be kept as a recording of the installation
/// (issue #5): what the app itself writes (recording file, history day, CSV, ETS telegram file,
/// the server's zip of ETS files) and what the ETS group monitor and bus monitor export.
///
/// Nothing here touches a store: [readRecordingFile] only reads, the recordings screen shows
/// what was found and saves on confirmation. Pure Dart, so it runs in a background isolate.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../export/telegram_files.dart';
import '../knx/telegram.dart';
import '../platform/safe_zip.dart';
import 'annotation.dart';
import 'recording.dart';

/// Format a file to import was recognized as.
enum RecordingFormat {
  /// A recording as the app stores it (JSON with `telegrams`).
  recording,

  /// A day of the long-term history (one telegram as JSON per line).
  history,

  /// The app's telegram CSV.
  csv,

  /// ETS group monitor or bus monitor file (`CommunicationLog` XML), also from this app.
  etsXml,

  /// Zip of ETS telegram files, as the add-on and the box export the whole history.
  etsZip,
}

/// Why a file was not read.
enum RecordingImportError {
  /// Larger than [RecordingImportLimits.maxBytes].
  tooLarge,

  /// More telegrams than [RecordingImportLimits.maxTelegrams].
  tooMany,

  /// None of the known formats.
  unknownFormat,

  /// XML with a document type (entity declarations): refused unread.
  doctype,

  /// The format was recognized, the content is damaged.
  damaged,

  /// Readable, but without a single group telegram.
  empty,

  /// An archive that unpacks to more than allowed.
  archive,
}

class RecordingImportException implements Exception {
  const RecordingImportException(this.error, {this.detail, this.limit});

  final RecordingImportError error;

  /// The parser's own words for [RecordingImportError.damaged], if it has any.
  final String? detail;

  /// The limit that was exceeded (MB or telegrams).
  final int? limit;

  @override
  String toString() => 'RecordingImportException(${error.name}${detail == null ? '' : ': $detail'})';
}

/// Upper limits of an import. A recording is held in memory as a whole while it is shown, on a
/// phone too: 500,000 telegrams are about a week of a busy house.
class RecordingImportLimits {
  const RecordingImportLimits({
    this.maxBytes = 100 * 1024 * 1024,
    this.maxTelegrams = 500000,
    this.maxArchiveEntries = 400,
  });

  /// Largest file, and largest content an archive may unpack to.
  final int maxBytes;
  final int maxTelegrams;

  /// Most files in a zip of ETS files (a year of days).
  final int maxArchiveEntries;
}

/// What an import found, before anything is saved.
class RecordingImport {
  RecordingImport({
    required this.format,
    required this.fileName,
    required this.telegrams,
    required this.skipped,
    this.original,
  });

  final RecordingFormat format;

  /// Name of the picked file, kept as the source of the recording.
  final String fileName;

  /// By time; never empty.
  final List<Telegram> telegrams;

  /// Telegrams left out, by reason.
  final Map<TelegramSkip, int> skipped;

  /// The recording inside a recording file: its name, note, comments and tap points are kept.
  final Recording? original;

  DateTime get first => telegrams.first.time;
  DateTime get last => telegrams.last.time;
  int get skippedCount => skipped.values.fold(0, (a, b) => a + b);

  /// The recording to save: marked as imported, in [installation], with the original times.
  Recording toRecording({required String name, required String? installation, DateTime? now}) {
    final at = now ?? DateTime.now();
    final o = original;
    return Recording(
      id: at.microsecondsSinceEpoch.toRadixString(36),
      name: name,
      note: o?.note,
      started: o != null && !o.started.isAfter(first) ? o.started : first,
      ended: o != null && !o.ended.isBefore(last) ? o.ended : last,
      gateway: o?.gateway,
      project: o?.project,
      installation: installation,
      telegrams: telegrams,
      // Without their screenshots: those are files of the original, and deleting the import
      // must not take them away from it.
      annotations: [for (final a in o?.annotations ?? const <Annotation>[]) a.copyWith(shots: const [])],
      taps: o?.taps,
      imported: ImportOrigin(file: fileName, format: format.name, at: at, skipped: skippedCount),
    );
  }
}

/// Whether [bytes] is a zip that holds ETS telegram files and nothing that marks a package of
/// the app (those have a JSON manifest): the recordings screen then imports it here instead of
/// opening it as a package.
bool looksLikeEtsZip(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) return false;
  // More entries than an import takes: not looked through here. [readRecordingFile] refuses it by
  // the same number, with the message for an archive that is too large.
  final stated = zipEntryCount(bytes);
  if (stated == null) return false;
  if (stated > const RecordingImportLimits().maxArchiveEntries) return true;
  try {
    final names = [
      for (final h in (ZipDirectory()..read(InputMemoryStream(bytes))).fileHeaders)
        if (!h.filename.endsWith('/')) h.filename.toLowerCase(),
    ];
    return names.isNotEmpty && names.every((n) => n.endsWith('.xml'));
  } on Object {
    return false;
  }
}

/// Reads [bytes] of the file [fileName] in whatever known format it is (by content, not by
/// extension). Throws [RecordingImportException].
RecordingImport readRecordingFile(
  Uint8List bytes, {
  required String fileName,
  RecordingImportLimits limits = const RecordingImportLimits(),
}) {
  if (bytes.length > limits.maxBytes) {
    throw RecordingImportException(RecordingImportError.tooLarge, limit: limits.maxBytes ~/ (1024 * 1024));
  }
  try {
    if (bytes.length > 3 && bytes[0] == 0x50 && bytes[1] == 0x4B) return _readZip(bytes, fileName, limits);
    final text = _decode(bytes);
    final start = _firstNonSpace(text);
    final ReadTelegrams read;
    final RecordingFormat format;
    Recording? original;
    if (start == '<') {
      format = RecordingFormat.etsXml;
      read = readEtsXml(text, maxTelegrams: limits.maxTelegrams);
    } else if (start == '{') {
      (read, original) = _readJson(text, limits);
      format = original == null ? RecordingFormat.history : RecordingFormat.recording;
    } else if (looksLikeTelegramCsv(text)) {
      format = RecordingFormat.csv;
      read = readTelegramCsv(text, maxTelegrams: limits.maxTelegrams);
    } else {
      throw const RecordingImportException(RecordingImportError.unknownFormat);
    }
    if (read.telegrams.isEmpty) throw const RecordingImportException(RecordingImportError.empty);
    return RecordingImport(
      format: format,
      fileName: fileName,
      telegrams: read.telegrams,
      skipped: read.skipped,
      original: original,
    );
  } on RecordingImportException {
    rethrow;
  } on TooManyTelegrams catch (e) {
    throw RecordingImportException(RecordingImportError.tooMany, limit: e.limit);
  } on XmlDoctypeRefused {
    throw const RecordingImportException(RecordingImportError.doctype);
  } on ZipLimitException catch (e) {
    throw RecordingImportException(RecordingImportError.archive, detail: e.reason);
  } on FormatException catch (e) {
    throw RecordingImportException(RecordingImportError.damaged, detail: e.message);
  } on Object catch (e) {
    // A type error deep in foreign JSON, a broken archive: damaged, not a crash.
    throw RecordingImportException(RecordingImportError.damaged, detail: '${e.runtimeType}');
  }
}

/// UTF-8 with or without a byte order mark, UTF-16 with one (the ETS on Windows); broken bytes
/// become replacement characters instead of ending the import.
String _decode(Uint8List b) {
  if (b.length >= 2 && ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF))) {
    final little = b[0] == 0xFF;
    final data = ByteData.sublistView(b, 2, 2 + ((b.length - 2) & ~1));
    return String.fromCharCodes([
      for (var i = 0; i < data.lengthInBytes; i += 2) data.getUint16(i, little ? Endian.little : Endian.big),
    ]);
  }
  final text = utf8.decode(b, allowMalformed: true);
  return text.startsWith('﻿') ? text.substring(1) : text;
}

String? _firstNonSpace(String text) {
  for (var i = 0; i < text.length && i < 4096; i++) {
    final c = text[i];
    if (c != ' ' && c != '\n' && c != '\r' && c != '\t') return c;
  }
  return null;
}

/// A recording file (one JSON object with `telegrams`) or a history day (one telegram per line).
(ReadTelegrams, Recording?) _readJson(String text, RecordingImportLimits limits) {
  final telegrams = <Telegram>[];
  final skipped = <TelegramSkip, int>{};
  void skip(TelegramSkip why) => skipped[why] = (skipped[why] ?? 0) + 1;
  void take(Object? json) {
    Telegram t;
    try {
      t = Telegram.fromJson((json! as Map).cast<String, Object?>());
    } on Object {
      return skip(json is Map && json['t'] is! int ? TelegramSkip.time : TelegramSkip.line);
    }
    if (telegrams.length >= limits.maxTelegrams) throw TooManyTelegrams(limits.maxTelegrams);
    telegrams.add(t);
  }

  Object? whole;
  try {
    whole = jsonDecode(text);
  } on FormatException {
    whole = null; // several lines: a history day
  }
  Recording? original;
  if (whole is Map && whole['telegrams'] is List) {
    final list = whole['telegrams']! as List;
    if (list.length > limits.maxTelegrams) throw TooManyTelegrams(limits.maxTelegrams);
    list.forEach(take);
    // Name, note, comments and tap points; the telegrams are the checked ones from above.
    original = Recording.fromJson({...whole.cast<String, Object?>(), 'telegrams': const <Object?>[], 'imported': null});
  } else if (whole is Map && whole['t'] is int && whole['d'] is int) {
    take(whole); // a history day with a single telegram
  } else if (whole != null) {
    throw const RecordingImportException(RecordingImportError.unknownFormat);
  } else {
    var lines = 0;
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty) continue;
      lines++;
      Object? json;
      try {
        json = jsonDecode(line);
      } on FormatException {
        skip(TelegramSkip.line); // truncated after a power failure
        continue;
      }
      if (json is Map) {
        take(json);
      } else {
        skip(TelegramSkip.line);
      }
    }
    // Not a single line of ours: some other JSON-like file, not a damaged history.
    if (telegrams.isEmpty && lines > 0) throw const RecordingImportException(RecordingImportError.unknownFormat);
  }
  telegrams.sort((a, b) => a.time.compareTo(b.time));
  return ((telegrams: telegrams, skipped: skipped), original);
}

/// A zip of ETS telegram files (one per day). Checked against [limits] before anything unpacks.
RecordingImport _readZip(Uint8List bytes, String fileName, RecordingImportLimits limits) {
  if (!looksLikeEtsZip(bytes)) throw const RecordingImportException(RecordingImportError.unknownFormat);
  final archive = decodeZipLimited(
    bytes,
    limits: ZipLimits(
      maxTotalBytes: limits.maxBytes,
      maxFileBytes: limits.maxBytes,
      maxEntries: limits.maxArchiveEntries,
    ),
  );
  final telegrams = <Telegram>[];
  final skipped = <TelegramSkip, int>{};
  for (final file in archive.files.where((f) => f.isFile)) {
    final read = readEtsXml(_decode(file.content), maxTelegrams: limits.maxTelegrams - telegrams.length + 1);
    if (telegrams.length + read.telegrams.length > limits.maxTelegrams) throw TooManyTelegrams(limits.maxTelegrams);
    telegrams.addAll(read.telegrams);
    for (final MapEntry(:key, :value) in read.skipped.entries) {
      skipped[key] = (skipped[key] ?? 0) + value;
    }
  }
  if (telegrams.isEmpty) throw const RecordingImportException(RecordingImportError.empty);
  telegrams.sort((a, b) => a.time.compareTo(b.time));
  return RecordingImport(format: RecordingFormat.etsZip, fileName: fileName, telegrams: telegrams, skipped: skipped);
}
