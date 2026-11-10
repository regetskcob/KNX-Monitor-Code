import 'dart:convert';
import 'dart:typed_data';

import '../l10n/locale_controller.dart';
import 'telegram.dart';

export 'package:knx/knx.dart' show Dpt;

/// A named group address from the ETS export.
class GroupInfo {
  const GroupInfo({
    required this.address,
    required this.name,
    this.path,
    this.dpt,
    this.description,
    this.links = const [],
  });

  final int address;
  final String name;

  /// Main and middle group, e.g. „Beleuchtung › Schalten“.
  final String? path;
  final Dpt? dpt;
  final String? description;

  /// Communication objects associated with this address (only from .knxproj).
  final List<GroupLink> links;

  Map<String, Object?> toJson() => {
    'a': address,
    'n': name,
    'p': path,
    if (dpt != null) 'd': [dpt!.main, dpt!.sub],
    'ds': description,
    if (links.isNotEmpty) 'l': [for (final l in links) l.toJson()],
  };

  factory GroupInfo.fromJson(Map<String, Object?> j) {
    final d = j['d'] as List?;
    return GroupInfo(
      address: j['a']! as int,
      name: j['n']! as String,
      path: j['p'] as String?,
      dpt: d == null ? null : Dpt(d[0] as int, d[1] as int?),
      description: j['ds'] as String?,
      links: [for (final l in (j['l'] as List? ?? const [])) GroupLink.fromJson(l as Map<String, Object?>)],
    );
  }
}

/// Flags of a communication object as the ETS shows them (German ETS letters): K communication, L
/// read, S write, Ü transmit, A update. Effective values – instance in the project before
/// ComObjectRef before the application's ComObject.
class ComFlags {
  const ComFlags({
    this.communication = true,
    this.read = false,
    this.write = false,
    this.transmit = false,
    this.update = false,
  });

  final bool communication;
  final bool read;
  final bool write;
  final bool transmit;
  final bool update;

  /// Whether it responds to read requests (K + L).
  bool get answersReads => communication && read;

  /// Set flags as the letters "CRWTU" (for JSON).
  String get code => [if (communication) 'C', if (read) 'R', if (write) 'W', if (transmit) 'T', if (update) 'U'].join();

  factory ComFlags.fromCode(String code) => ComFlags(
    communication: code.contains('C'),
    read: code.contains('R'),
    write: code.contains('W'),
    transmit: code.contains('T'),
    update: code.contains('U'),
  );

  @override
  bool operator ==(Object other) => other is ComFlags && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => code;
}

/// Association of a group address with a communication object of a device.
class GroupLink {
  const GroupLink({required this.device, this.object, this.text, this.sends = false, this.flags, this.ref});

  /// Individual address of the device.
  final int device;

  /// Number of the communication object.
  final int? object;

  /// Object or function text, if maintained in the project.
  final String? text;

  /// Sending association: first address on the object with the Ü (transmit) flag. Without known
  /// [flags] (CSV, missing application, old catalogs) just "first address".
  final bool sends;

  /// Flags of the object; `null` if unknown (CSV, older catalogs, application program missing from
  /// the export).
  final ComFlags? flags;

  /// Reference of the communication object in the project, as the ETS and the XKNX Editor name it
  /// (`M-0083_A-…_O-236_R-62`): identifies the object when handing a correction to the editor.
  final String? ref;

  Map<String, Object?> toJson() => {
    'd': device,
    'o': object,
    't': text,
    if (sends) 's': true,
    if (flags != null) 'f': flags!.code,
    if (ref != null) 'r': ref,
  };

  factory GroupLink.fromJson(Map<String, Object?> j) => GroupLink(
    device: j['d']! as int,
    object: j['o'] as int?,
    text: j['t'] as String?,
    sends: j['s'] == true,
    flags: j['f'] is String ? ComFlags.fromCode(j['f']! as String) : null,
    ref: j['r'] as String?,
  );
}

/// A device from the ETS topology (only from .knxproj).
class DeviceInfo {
  const DeviceInfo({
    required this.address,
    required this.name,
    this.product,
    this.manufacturer,
    this.location,
    this.description,
    this.serial,
    this.tunnelOf,
    this.neverProgrammed = false,
    this.pendingDownload = const [],
    this.rf = false,
  });

  final int address;

  /// The device sits on a KNX RF line (radio) according to the project. Busclear sees its
  /// telegrams through the media coupler only: no signal strength, no battery state. A
  /// battery-powered transmitter speaks only when it has something to say, so its silence is no
  /// finding. `false` when the source does not tell.
  final bool rf;

  /// The project knows when devices were downloaded, and this one never was: configured but not
  /// put into operation, or not installed at all. `false` when the source does not tell.
  final bool neverProgrammed;

  /// Parts changed in the project since the last download and not yet loaded into the device, as
  /// the ETS and the XKNX Editor mark them ("Adr Prg Par Grp Cfg"). Empty when nothing is pending
  /// or the source does not tell.
  final List<DownloadPart> pendingDownload;

  /// Additional address (tunnel) of the IP interface with this address – not a separate device.
  final int? tunnelOf;

  bool get isTunnel => tunnelOf != null;

  /// Name from the project, falling back to the product name.
  final String name;
  final String? product;
  final String? manufacturer;

  /// Location from the building structure, e.g. „EG › Küche“.
  final String? location;
  final String? description;

  /// Serial number according to the project (12 hex characters), if stored.
  final String? serial;

  Map<String, Object?> toJson() => {
    'a': address,
    'n': name,
    'p': product,
    'm': manufacturer,
    'l': location,
    'ds': description,
    if (serial != null) 'sn': serial,
    if (tunnelOf != null) 'tu': tunnelOf,
    if (neverProgrammed) 'np': true,
    if (pendingDownload.isNotEmpty) 'pd': [for (final p in pendingDownload) p.name],
    if (rf) 'rf': true,
  };

  factory DeviceInfo.fromJson(Map<String, Object?> j) => DeviceInfo(
    address: j['a']! as int,
    name: j['n']! as String,
    product: j['p'] as String?,
    manufacturer: j['m'] as String?,
    location: j['l'] as String?,
    description: j['ds'] as String?,
    serial: j['sn'] as String?,
    tunnelOf: j['tu'] as int?,
    neverProgrammed: j['np'] == true,
    pendingDownload: [for (final n in (j['pd'] as List? ?? const [])) ?DownloadPart.values.asNameMap()[n]],
    rf: j['rf'] == true,
  );

  DeviceInfo _asTunnelOf(int parent) => DeviceInfo(
    address: address,
    name: name,
    product: product,
    manufacturer: manufacturer,
    location: location,
    description: description,
    serial: serial,
    tunnelOf: parent,
    rf: rf,
  );
}

/// Whether a medium as a project names it is KNX RF: the ETS id `MT-2`, the short `RF` of the
/// XKNX Editor, or a text like "Radio Frequency (RF)" in the project Home Assistant keeps.
bool isRfMedium(Object? medium) {
  if (medium is! String) return false;
  final m = medium.trim().toLowerCase();
  return m == 'mt-2' || m == 'rf' || m.contains('radio') || RegExp(r'\brf\b').hasMatch(m);
}

/// Part of a device download, as the ETS and the XKNX Editor track it per device.
enum DownloadPart {
  /// Individual address.
  address,

  /// Application program.
  application,

  /// Parameters.
  parameters,

  /// Group communication (association and group address tables).
  groups,

  /// Medium configuration.
  medium,
}

/// Group addresses and devices, imported from ETS CSV or .knxproj.
class GroupCatalog {
  GroupCatalog(
    this.groups, {
    this.devices = const {},
    this.projectName,
    this.manufacturers = const {},
    this.style = GroupStyle.threeLevel,
    this.externalSenders = const {},
  });

  /// Address style of the project (ETS: 3-level, 2-level, free).
  final GroupStyle style;

  static final empty = GroupCatalog(const {});

  final Map<int, GroupInfo> groups;
  final Map<int, DeviceInfo> devices;

  /// Lines (area and line, as in the upper byte of an individual address) that are KNX RF
  /// according to the project.
  late final Set<int> rfLines = {
    for (final d in devices.values)
      if (d.rf) d.address >> 8,
  };
  final String? projectName;

  /// KNX manufacturer ID → name (from the master data of the .knxproj).
  final Map<int, String> manufacturers;

  /// Group addresses something outside the project writes to, e.g. Home Assistant entities and
  /// exposes (taken over with the project of its KNX integration). They have a sender even without
  /// one in the project.
  final Set<int> externalSenders;

  bool get isEmpty => groups.isEmpty;
  int get length => groups.length;

  GroupInfo? operator [](int address) => groups[address];

  Map<String, Object?> toJson() => {
    'v': 1,
    'project': projectName,
    if (style != GroupStyle.threeLevel) 'style': style.name,
    'groups': [for (final g in groups.values) g.toJson()],
    'devices': [for (final d in devices.values) d.toJson()],
    'manufacturers': {for (final MapEntry(:key, :value) in manufacturers.entries) '$key': value},
    if (externalSenders.isNotEmpty) 'xs': (externalSenders.toList()..sort()),
  };

  factory GroupCatalog.fromJson(Map<String, Object?> j) {
    final groups = [for (final g in j['groups']! as List) GroupInfo.fromJson(g as Map<String, Object?>)];
    final devices = {
      for (final d in (j['devices'] as List? ?? const []))
        (d as Map<String, Object?>)['a']! as int: DeviceInfo.fromJson(d),
    };
    // Older catalogs without tunnel identifier: "<device> · Tunnel n" with the same product on the
    // same line belongs to this device.
    for (final d in devices.values.toList()) {
      if (d.isTunnel || !d.name.contains(' · ')) continue;
      final parent = devices.values
          .where(
            (p) =>
                p.address != d.address &&
                !p.isTunnel &&
                p.address >> 8 == d.address >> 8 &&
                p.product == d.product &&
                d.name.startsWith('${p.name} · '),
          )
          .firstOrNull;
      if (parent != null) devices[d.address] = d._asTunnelOf(parent.address);
    }
    return GroupCatalog(
      {for (final g in groups) g.address: g},
      devices: devices,
      projectName: j['project'] as String?,
      style: GroupStyle.values.asNameMap()[j['style']] ?? GroupStyle.threeLevel,
      manufacturers: {
        for (final MapEntry(:key, :value) in ((j['manufacturers'] as Map?) ?? const {}).entries)
          int.parse(key as String): value as String,
      },
      externalSenders: {...?(j['xs'] as List?)?.whereType<int>()},
    );
  }

  /// Decodes the bytes of an ETS CSV (UTF-8 with/without BOM, UTF-16 LE, Latin-1).
  static String decodeBytes(Uint8List b) {
    if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
      final units = Uint16List.view(b.buffer, b.offsetInBytes + 2, (b.length - 2) ~/ 2);
      return String.fromCharCodes(units);
    }
    final start = b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF ? 3 : 0;
    try {
      return utf8.decode(b.sublist(start));
    } on FormatException {
      return latin1.decode(b);
    }
  }

  /// Parses the ETS group address export as CSV, format "1/1" (one column for the name) or "3/1"
  /// (Main/Middle/Sub with range rows). The separator (`,` `;` tab) is detected.
  ///
  /// Throws [FormatException] if no group address is found.
  static GroupCatalog parseCsv(String text) {
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final lines = text.split(RegExp(r'\r\n|\n|\r')).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) throw FormatException(s.csvEmpty);

    final sep = [
      ',',
      ';',
      '\t',
    ].reduce((a, b) => _split(lines.first, a).length >= _split(lines.first, b).length ? a : b);
    final rows = lines.map((l) => _split(l, sep)).toList();

    // Find columns by the header row (English or German).
    final header = rows.first.map((h) => h.toLowerCase()).toList();
    int col(List<String> names) => header.indexWhere(names.contains);
    final hasHeader = header.any((h) => h.contains('address') || h.contains('adresse'));
    var addrCol = col(['address', 'adresse', 'gruppenadresse']);
    final dptCol = col(['datapointtype', 'datenpunkttyp', 'dpt']);
    final nameCol = col(['group name', 'name', 'gruppenname']);
    final mainCol = col(['main', 'hauptgruppe']);
    final threeLevel = mainCol >= 0;
    if (addrCol < 0) {
      // Without a header row: the first column that looks like a group address.
      addrCol = rows.first.indexWhere((c) => RegExp(r'^\d+/[\d-]+(/[\d-]+)?$').hasMatch(c));
      if (addrCol < 0) {
        throw FormatException(s.csvNoAddressColumn);
      }
    }

    final groups = <int, GroupInfo>{};
    String? mainName, middleName;
    var style = GroupStyle.threeLevel;
    for (final r in rows.skip(hasHeader ? 1 : 0)) {
      if (r.length <= addrCol) continue;
      final addr = r[addrCol];
      if (threeLevel && addr.endsWith('/-/-')) {
        mainName = _cell(r, mainCol);
        middleName = null;
        continue;
      }
      if (threeLevel && addr.endsWith('/-')) {
        middleName = _cell(r, mainCol + 1);
        continue;
      }
      final (ga, addrStyle) = _parseAddress(addr);
      if (ga == null) continue;
      style = addrStyle;

      final name = threeLevel
          ? [for (var i = mainCol + 2; i >= mainCol; i--) _cell(r, i)].firstWhere((s) => s.isNotEmpty, orElse: () => '')
          : _cell(r, nameCol >= 0 ? nameCol : (addrCol == 0 ? 1 : 0));
      final path = [mainName, middleName].whereType<String>().where((s) => s.isNotEmpty).join(' › ');
      groups[ga] = GroupInfo(
        address: ga,
        name: name.isEmpty ? formatGroup(ga) : name,
        path: path.isEmpty ? null : path,
        dpt: dptCol >= 0 ? Dpt.tryParse(_cell(r, dptCol)) : null,
      );
    }
    if (groups.isEmpty) {
      throw FormatException(s.csvNoGroups);
    }
    return GroupCatalog(groups, style: style);
  }

  /// Address in any ETS style: "1/2/3", "1/515" or free "2563".
  static (int?, GroupStyle) _parseAddress(String text) {
    final parts = text.trim().split('/');
    // Digits only, see parseGroup.
    final n = [for (final p in parts) RegExp(r'^\d{1,5}$').hasMatch(p.trim()) ? int.parse(p.trim()) : null];
    if (n.any((v) => v == null)) return (null, GroupStyle.threeLevel);
    return switch (n) {
      [final m?, final mi?, final sub?] when m <= 31 && mi <= 7 && sub <= 255 => (
        (m << 11) | (mi << 8) | sub,
        GroupStyle.threeLevel,
      ),
      [final m?, final sub?] when m <= 31 && sub <= 2047 => ((m << 11) | sub, GroupStyle.twoLevel),
      [final free?] when free <= 0xFFFF => (free, GroupStyle.free),
      _ => (null, GroupStyle.threeLevel),
    };
  }

  static String _cell(List<String> r, int i) => i >= 0 && i < r.length ? r[i].trim() : '';

  /// CSV line with quote support ("a;"b;c";d").
  static List<String> _split(String line, String sep) {
    final out = <String>[];
    final cur = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          cur.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (ch == sep && !quoted) {
        out.add(cur.toString());
        cur.clear();
      } else {
        cur.write(ch);
      }
    }
    out.add(cur.toString());
    return out;
  }
}
