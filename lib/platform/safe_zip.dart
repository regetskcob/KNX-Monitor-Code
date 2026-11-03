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

/// [ZipDecoder.decodeBytes] with limits: the directory is checked before anything is unpacked.
/// `archive` does not output more than the size stated there when unpacking an entry, so the
/// numbers stated there are sufficient.
///
/// Throws [ZipLimitException]; for a damaged file, whatever [ZipDecoder] throws.
Archive decodeZipLimited(Uint8List bytes, {String? password, ZipLimits? limits}) {
  final l = limits ?? defaultZipLimits;
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
