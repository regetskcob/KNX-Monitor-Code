/// Writes a zip archive while it is being sent, without holding it in memory.
///
/// Entries are deflated and their size and CRC follow the data (data
/// descriptor), so nothing has to be known in advance. No Zip64: every entry and
/// the whole archive stay below 4 GB, far more than a day of history (see
/// `writeEtsZip`).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// An entry [ZipStream] wrote: name, uncompressed size, CRC-32 and, if asked for, the SHA-256 of
/// the content.
typedef ZipWritten = ({String name, int size, int crc, Uint8List? sha256});

class ZipStream {
  ZipStream(this._emit);

  final Future<void> Function(List<int> bytes) _emit;
  final _central = BytesBuilder();
  var _offset = 0;
  var _entries = 0;

  /// The entries written so far, in order.
  final written = <ZipWritten>[];

  Future<void> _write(List<int> bytes) async {
    _offset += bytes.length;
    await _emit(bytes);
  }

  /// Adds the file [name]; [write] delivers its content in pieces.
  Future<void> add(
    String name,
    DateTime modified,
    Future<void> Function(Future<void> Function(String text) write) write, {
    bool digest = false,
  }) => _entry(name, modified, 6, digest, (put) => write((text) => put(utf8.encode(text))));

  /// Adds the file [name] with the bytes of [data]. [level] 0 stores already compressed data
  /// (packed history days) in deflate blocks without compressing it again: cheap on the Pi, and
  /// every zip reader understands it.
  /// With [digest] the SHA-256 of the content is noted in [written].
  Future<void> addStream(
    String name,
    DateTime modified,
    Stream<List<int>> data, {
    int level = 6,
    bool digest = false,
  }) => _entry(name, modified, level, digest, (put) async {
    await for (final chunk in data) {
      await put(chunk);
    }
  });

  Future<void> _entry(
    String name,
    DateTime modified,
    int level,
    bool digest,
    Future<void> Function(Future<void> Function(List<int> bytes) put) produce,
  ) async {
    final sha = digest ? Sha256Stream() : null;
    final nameBytes = utf8.encode(name);
    final (time, date) = _dosTime(modified);
    final start = _offset;
    await _write(
      (_Le()
            ..u32(0x04034b50)
            ..u16(20)
            ..u16(0x0808) // sizes in the data descriptor, UTF-8 name
            ..u16(8) // deflate
            ..u16(time)
            ..u16(date)
            ..u32(0)
            ..u32(0)
            ..u32(0)
            ..u16(nameBytes.length)
            ..u16(0)
            ..bytes(nameBytes))
          .done(),
    );

    var crc = 0;
    var size = 0;
    var compressed = 0;
    final pending = <List<int>>[];
    final deflater = ZLibEncoder(raw: true, level: level).startChunkedConversion(_Collect(pending));
    Future<void> drain() async {
      for (final chunk in pending) {
        compressed += chunk.length;
        await _write(chunk);
      }
      pending.clear();
    }

    await produce((bytes) async {
      crc = crc32(bytes, crc);
      sha?.add(bytes);
      size += bytes.length;
      deflater.add(bytes);
      await drain();
    });
    deflater.close();
    await drain();

    // Without Zip64 sizes and offsets have 32 bits; beyond that the archive
    // would look whole but point to wrong places. Better a recognisably
    // aborted download than a quietly broken one.
    if (size > _max32 || compressed > _max32 || start > _max32 || _entries >= 0xFFFF) {
      throw StateError('Zip zu groß (über 4 GB oder 65535 Dateien), bitte kürzere Zeiträume exportieren.');
    }
    await _write(
      (_Le()
            ..u32(0x08074b50)
            ..u32(crc)
            ..u32(compressed)
            ..u32(size))
          .done(),
    );
    _central.add(
      (_Le()
            ..u32(0x02014b50)
            ..u16(20)
            ..u16(20)
            ..u16(0x0808)
            ..u16(8)
            ..u16(time)
            ..u16(date)
            ..u32(crc)
            ..u32(compressed)
            ..u32(size)
            ..u16(nameBytes.length)
            ..u16(0)
            ..u16(0)
            ..u16(0)
            ..u16(0)
            ..u32(0)
            ..u32(start)
            ..bytes(nameBytes))
          .done(),
    );
    _entries++;
    written.add((name: name, size: size, crc: crc, sha256: sha?.close()));
  }

  static const _max32 = 0xFFFFFFFF;

  /// Central directory and end of the archive.
  Future<void> close() async {
    final directory = _central.takeBytes();
    final at = _offset;
    if (at > _max32) throw StateError('Zip zu groß (über 4 GB), bitte kürzere Zeiträume exportieren.');
    await _write(directory);
    await _write(
      (_Le()
            ..u32(0x06054b50)
            ..u16(0)
            ..u16(0)
            ..u16(_entries)
            ..u16(_entries)
            ..u32(directory.length)
            ..u32(at)
            ..u16(0))
          .done(),
    );
  }

  static (int, int) _dosTime(DateTime d) => (
    (d.hour << 11) | (d.minute << 5) | (d.second ~/ 2),
    ((d.year - 1980).clamp(0, 127) << 9) | (d.month << 5) | d.day,
  );
}

/// Keeps what the deflater produces until it is sent.
class _Collect implements Sink<List<int>> {
  _Collect(this._into);
  final List<List<int>> _into;
  @override
  void add(List<int> data) => _into.add(data);
  @override
  void close() {}
}

/// Little-endian fields of a zip header.
class _Le {
  final _b = BytesBuilder();
  void u16(int v) => _b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(int v) => _b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  void bytes(List<int> v) => _b.add(v);
  Uint8List done() => _b.takeBytes();
}

final _crcTable = Uint32List.fromList(
  List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  }),
);

/// CRC-32 of [bytes], continuing from [crc]. Runs over whole box backups on the Pi, hence the
/// typed table and the indexed loop.
int crc32(List<int> bytes, [int crc = 0]) {
  final table = _crcTable;
  var c = crc ^ 0xFFFFFFFF;
  for (var i = 0, n = bytes.length; i < n; i++) {
    c = table[(c ^ bytes[i]) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

/// SHA-256 over content that arrives in pieces (package:crypto: compiled, several times faster
/// than pointycastle's, which matters for a history of hundreds of megabytes on a Raspberry Pi).
class Sha256Stream {
  Sha256Stream() {
    _input = crypto.sha256.startChunkedConversion(_DigestSink((d) => _digest = d));
  }

  late final ByteConversionSink _input;
  crypto.Digest? _digest;

  void add(List<int> bytes) => _input.add(bytes);

  /// The digest; nothing may be added afterwards.
  Uint8List close() {
    _input.close();
    return Uint8List.fromList(_digest!.bytes);
  }
}

class _DigestSink implements Sink<crypto.Digest> {
  _DigestSink(this._onDigest);
  final void Function(crypto.Digest digest) _onDigest;

  @override
  void add(crypto.Digest data) => _onDigest(data);

  @override
  void close() {}
}
