import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A file unpacks to more than the app accepts ("zip bomb").
class ZipLimitException implements Exception {
  const ZipLimitException(this.reason);
  final String reason;
  @override
  String toString() => 'Archiv zu groß: $reason';
}

/// Upper limits when unpacking foreign archives.
class ZipLimits {
  const ZipLimits({
    this.maxTotalBytes = 1024 * 1024 * 1024,
    this.maxFileBytes = 512 * 1024 * 1024,
    this.maxEntries = 100000,
  });

  final int maxTotalBytes;
  final int maxFileBytes;
  final int maxEntries;
}

/// Limits when the caller does not specify its own. Real ETS projects are far below them.
ZipLimits defaultZipLimits = const ZipLimits();

/// Number of entries a zip states in its end record, read without parsing the directory; `null`
/// if [bytes] has no such record. A zip64 archive (count 0xFFFF) reports that value: far above
/// any limit here.
int? zipEntryCount(Uint8List bytes) {
  // The end record is at most 22 bytes plus a comment of up to 65,535 bytes from the end.
  final from = bytes.length - 22;
  final to = from - 0xFFFF < 0 ? 0 : from - 0xFFFF;
  for (var i = from; i >= to; i--) {
    if (bytes[i] == 0x50 && bytes[i + 1] == 0x4B && bytes[i + 2] == 0x05 && bytes[i + 3] == 0x06) {
      return bytes[i + 10] | (bytes[i + 11] << 8);
    }
  }
  return null;
}

/// [ZipDecoder.decodeBytes] with limits: the directory is checked before anything is unpacked.
/// `archive` does not output more than the size stated there when unpacking an entry, so the
/// numbers stated there are sufficient.
///
/// Throws [ZipLimitException]; for a damaged file, whatever [ZipDecoder] throws.
Archive decodeZipLimited(Uint8List bytes, {String? password, ZipLimits? limits}) {
  final l = limits ?? defaultZipLimits;
  // Before the directory is parsed into a list: an archive that states more entries than allowed
  // is refused from its end record alone.
  if (zipEntryCount(bytes) case final stated? when stated > l.maxEntries) {
    throw ZipLimitException('$stated Einträge');
  }
  final headers = (ZipDirectory()..read(InputMemoryStream(bytes), password: password)).fileHeaders;
  if (headers.length > l.maxEntries) throw ZipLimitException('${headers.length} Einträge');
  var total = 0;
  for (final h in headers) {
    final size = h.uncompressedSize;
    if (size > l.maxFileBytes) throw ZipLimitException('${h.filename}: $size Bytes');
    total += size;
    if (total > l.maxTotalBytes) throw ZipLimitException('zusammen über ${l.maxTotalBytes} Bytes');
  }
  return ZipDecoder().decodeBytes(bytes, password: password);
}
