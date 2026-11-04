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

class ZipStream {
  ZipStream(this._emit);

  final Future<void> Function(List<int> bytes) _emit;
  final _central = BytesBuilder();
  var _offset = 0;
  var _entries = 0;

  Future<void> _write(List<int> bytes) async {
    _offset += bytes.length;
    await _emit(bytes);
  }

  /// Adds the file [name]; [write] delivers its content in pieces.
  Future<void> add(
    String name,
    DateTime modified,
    Future<void> Function(Future<void> Function(String text) write) write,
  ) async {
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
    final deflater = ZLibEncoder(raw: true, level: 6).startChunkedConversion(_Collect(pending));
    Future<void> drain() async {
      for (final chunk in pending) {
        compressed += chunk.length;
        await _write(chunk);
      }
      pending.clear();
    }

    await write((text) async {
      final bytes = utf8.encode(text);
      crc = crc32(bytes, crc);
      size += bytes.length;
      deflater.add(bytes);
      await drain();
    });
    deflater.close();
    await drain();

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
  }

  /// Central directory and end of the archive.
  Future<void> close() async {
    final directory = _central.takeBytes();
    final at = _offset;
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

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

/// CRC-32 of [bytes], continuing from [crc].
int crc32(List<int> bytes, [int crc = 0]) {
  var c = crc ^ 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}
