import 'dart:convert';
import 'dart:typed_data';

/// Read-only reader for SQLite database files (file format 3), in plain Dart.
///
/// Enough to read the rows of ordinary rowid tables, e.g. a project of the XKNX Editor (.xknx).
/// No SQL: tables are read whole, as maps of column name to value. Runs everywhere the app runs
/// (browser, isolates) without a native library. Indexes, `WITHOUT ROWID` tables and a write-ahead
/// log are not supported; a database with uncommitted WAL content must be checkpointed first.
///
/// Throws [FormatException] for anything that is not a readable SQLite file.
class SqliteReader {
  SqliteReader(this._data) {
    if (_data.length < 100 || ascii.decode(_data.sublist(0, 15), allowInvalid: true) != 'SQLite format 3') {
      throw const FormatException('not an SQLite database');
    }
    final raw = _u16(16);
    _pageSize = raw == 1 ? 65536 : raw;
    if (_pageSize < 512 || _pageSize & (_pageSize - 1) != 0) {
      throw const FormatException('invalid SQLite page size');
    }
    _usable = _pageSize - _data[20];
    final encoding = _u32(56);
    if (encoding > 1) throw const FormatException('SQLite database is not UTF-8');
    _schema = [
      for (final row in _rows(1))
        if (row.values.length >= 5) _SchemaEntry(row.values),
    ];
  }

  final Uint8List _data;
  late final int _pageSize;
  late final int _usable;
  late final List<_SchemaEntry> _schema;

  /// Names of the tables.
  List<String> get tables => [
    for (final e in _schema)
      if (e.type == 'table') e.name,
  ];

  /// Column names of [table] as declared, or `null` if it does not exist.
  List<String>? columns(String table) => _table(table)?.columns.map((c) => c.name).toList();

  /// All rows of [table]; values are `null`, [int], [double], [String] or [Uint8List].
  ///
  /// A column declared as INTEGER PRIMARY KEY holds the rowid. Columns added later with ALTER
  /// TABLE that a row predates are `null`.
  List<Map<String, Object?>> rows(String table) {
    final t = _table(table);
    if (t == null) throw FormatException('table $table not found');
    if (t.withoutRowid) throw FormatException('table $table is WITHOUT ROWID');
    final names = t.columns;
    final alias = names.indexWhere((c) => c.rowidAlias);
    return [
      for (final row in _rows(t.rootPage))
        {
          for (var i = 0; i < names.length; i++)
            names[i].name: i == alias ? (row.values.elementAtOrNull(i) ?? row.rowid) : row.values.elementAtOrNull(i),
        },
    ];
  }

  _Table? _table(String name) {
    final entry = _schema.where((e) => e.type == 'table' && e.name.toLowerCase() == name.toLowerCase()).firstOrNull;
    if (entry == null) return null;
    return _Table.parse(entry.sql, entry.rootPage);
  }

  // --- B-tree ------------------------------------------------------------------------------------

  Iterable<_Row> _rows(int root) sync* {
    final pageCount = _data.length ~/ _pageSize;
    final stack = <int>[root];
    var visited = 0;
    while (stack.isNotEmpty) {
      final page = stack.removeLast();
      if (page < 1 || page > pageCount) throw const FormatException('SQLite page out of range');
      if (++visited > pageCount) throw const FormatException('SQLite b-tree has a cycle');
      final start = (page - 1) * _pageSize;
      final header = page == 1 ? 100 : 0;
      final h = start + header;
      final type = _data[h];
      final cells = _u16(h + 3);
      if (type == 0x05) {
        // Interior table page: children left to right, then the right-most pointer. Pushed in
        // reverse so rows come out in rowid order.
        final children = <int>[for (var i = 0; i < cells; i++) _u32(start + _u16(h + 12 + i * 2))];
        stack.add(_u32(h + 8));
        stack.addAll(children.reversed);
      } else if (type == 0x0D) {
        for (var i = 0; i < cells; i++) {
          yield _leafCell(start + _u16(h + 8 + i * 2));
        }
      } else {
        throw FormatException('unexpected SQLite page type $type');
      }
    }
  }

  _Row _leafCell(int offset) {
    var p = offset;
    final (size, a) = _varint(p);
    p += a;
    final (rowid, b) = _varint(p);
    p += b;
    final u = _usable;
    final x = u - 35;
    final Uint8List payload;
    if (size <= x) {
      payload = Uint8List.sublistView(_data, p, p + size);
    } else {
      final m = ((u - 12) * 32 ~/ 255) - 23;
      final k = m + ((size - m) % (u - 4));
      final local = k <= x ? k : m;
      final out = BytesBuilder(copy: false)..add(Uint8List.sublistView(_data, p, p + local));
      var next = _u32(p + local);
      var remaining = size - local;
      var hops = 0;
      while (remaining > 0) {
        if (next == 0 || ++hops > _data.length ~/ _pageSize) {
          throw const FormatException('broken SQLite overflow chain');
        }
        final start = (next - 1) * _pageSize;
        final take = remaining < u - 4 ? remaining : u - 4;
        out.add(Uint8List.sublistView(_data, start + 4, start + 4 + take));
        remaining -= take;
        next = _u32(start);
      }
      payload = out.takeBytes();
    }
    return _Row(rowid, _record(payload));
  }

  // --- Records -----------------------------------------------------------------------------------

  static List<Object?> _record(Uint8List r) {
    final bd = ByteData.sublistView(r);
    final (headerSize, n) = _varintIn(r, 0);
    var hp = n;
    var bp = headerSize;
    final values = <Object?>[];
    while (hp < headerSize) {
      final (type, m) = _varintIn(r, hp);
      hp += m;
      switch (type) {
        case 0:
          values.add(null);
        case 1:
          values.add(bd.getInt8(bp));
          bp += 1;
        case 2:
          values.add(bd.getInt16(bp));
          bp += 2;
        case 3:
          values.add((bd.getInt8(bp) << 16) | bd.getUint16(bp + 1));
          bp += 3;
        case 4:
          values.add(bd.getInt32(bp));
          bp += 4;
        case 5:
          values.add((bd.getInt16(bp) * 0x100000000) + bd.getUint32(bp + 2));
          bp += 6;
        case 6:
          values.add((bd.getInt32(bp) * 0x100000000) + bd.getUint32(bp + 4));
          bp += 8;
        case 7:
          values.add(bd.getFloat64(bp));
          bp += 8;
        case 8:
          values.add(0);
        case 9:
          values.add(1);
        case >= 12 when type.isEven:
          final len = (type - 12) >> 1;
          values.add(Uint8List.fromList(Uint8List.sublistView(r, bp, bp + len)));
          bp += len;
        case >= 13:
          final len = (type - 13) >> 1;
          values.add(utf8.decode(Uint8List.sublistView(r, bp, bp + len), allowMalformed: true));
          bp += len;
        default:
          throw const FormatException('invalid SQLite record');
      }
    }
    return values;
  }

  // --- Helpers -----------------------------------------------------------------------------------

  int _u16(int o) => (_data[o] << 8) | _data[o + 1];
  int _u32(int o) => _data[o] * 0x1000000 + (_data[o + 1] << 16 | _data[o + 2] << 8 | _data[o + 3]);
  (int, int) _varint(int o) => _varintIn(_data, o);

  /// SQLite varint: up to 9 bytes, big-endian, high bit = continue; the ninth byte counts fully.
  /// Multiplication instead of shifts: in the browser, shifts truncate to 32 bits.
  static (int, int) _varintIn(Uint8List d, int o) {
    var v = 0;
    for (var i = 0; i < 8; i++) {
      final b = d[o + i];
      v = v * 128 + (b & 0x7F);
      if (b < 0x80) return (v, i + 1);
    }
    return (v * 256 + d[o + 8], 9);
  }
}

class _Row {
  const _Row(this.rowid, this.values);
  final int rowid;
  final List<Object?> values;
}

class _SchemaEntry {
  _SchemaEntry(List<Object?> v)
    : type = v[0] as String? ?? '',
      name = v[1] as String? ?? '',
      rootPage = (v[3] as int?) ?? 0,
      sql = v[4] as String? ?? '';
  final String type;
  final String name;
  final int rootPage;
  final String sql;
}

class _Column {
  const _Column(this.name, {this.rowidAlias = false});
  final String name;
  final bool rowidAlias;
}

class _Table {
  const _Table(this.columns, this.rootPage, {this.withoutRowid = false});
  final List<_Column> columns;
  final int rootPage;
  final bool withoutRowid;

  /// Column names from the CREATE TABLE statement; recognises an INTEGER PRIMARY KEY (on the
  /// column or as a single-column table constraint), which is an alias of the rowid.
  static _Table parse(String sql, int root) {
    final open = sql.indexOf('(');
    final close = sql.lastIndexOf(')');
    if (open < 0 || close < open) throw const FormatException('unreadable SQLite schema');
    final parts = _splitTopLevel(sql.substring(open + 1, close));
    final names = <String>[];
    final types = <String>[];
    var inlinePk = -1;
    String? constraintPk;
    for (final part in parts) {
      final text = part.trim();
      final upper = text.toUpperCase();
      if (RegExp(r'^(CONSTRAINT|PRIMARY\s+KEY|UNIQUE|CHECK|FOREIGN\s+KEY)\b').hasMatch(upper)) {
        final pk = RegExp(r'PRIMARY\s+KEY\s*\(([^)]*)\)', caseSensitive: false).firstMatch(text);
        if (pk != null) {
          final cols = pk.group(1)!.split(',');
          if (cols.length == 1) constraintPk = _unquote(cols.single.trim().split(RegExp(r'\s+')).first);
        }
        continue;
      }
      final m = RegExp(r'^("[^"]*"|`[^`]*`|\[[^\]]*\]|\S+)\s*(.*)$', dotAll: true).firstMatch(text);
      if (m == null) continue;
      names.add(_unquote(m.group(1)!));
      final rest = m.group(2)!.toUpperCase();
      types.add(RegExp(r'^[A-Z]+').firstMatch(rest)?.group(0) ?? '');
      if (RegExp(r'\bPRIMARY\s+KEY\b').hasMatch(rest)) inlinePk = names.length - 1;
    }
    var alias = inlinePk;
    if (alias < 0 && constraintPk != null) {
      alias = names.indexWhere((n) => n.toLowerCase() == constraintPk!.toLowerCase());
    }
    final withoutRowid = RegExp(r'\)\s*WITHOUT\s+ROWID', caseSensitive: false).hasMatch(sql.substring(close - 1));
    return _Table(
      [
        for (var i = 0; i < names.length; i++)
          _Column(names[i], rowidAlias: i == alias && types[i] == 'INTEGER' && !withoutRowid),
      ],
      root,
      withoutRowid: withoutRowid,
    );
  }

  static String _unquote(String s) {
    if (s.length >= 2 &&
        ((s.startsWith('"') && s.endsWith('"')) ||
            (s.startsWith('`') && s.endsWith('`')) ||
            (s.startsWith('[') && s.endsWith(']')))) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  static List<String> _splitTopLevel(String s) {
    final out = <String>[];
    var depth = 0;
    var start = 0;
    String? quote;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (quote != null) {
        if (c == quote) quote = null;
        continue;
      }
      if (c == '"' || c == "'" || c == '`') {
        quote = c;
      } else if (c == '[') {
        quote = ']';
      } else if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
      } else if (c == ',' && depth == 0) {
        out.add(s.substring(start, i));
        start = i + 1;
      }
    }
    out.add(s.substring(start));
    return out;
  }
}
