import 'dart:convert';
import 'dart:typed_data';

import '../l10n/locale_controller.dart';
import 'group_catalog.dart';
import 'knxproj_parser.dart' show KnxprojPasswordException, dptFromObjects, serialFromBase64;
import 'secure/package_crypto.dart' show aesGcm, pbkdf2;
import 'sqlite_reader.dart';
import 'telegram.dart';

/// Whether [bytes] look like a project of the XKNX Editor (an SQLite file with its tables).
bool isXknx(Uint8List bytes) {
  try {
    final tables = SqliteReader(bytes).tables.toSet();
    return tables.containsAll(const {'projects', 'group_addresses', 'com_object_links'});
  } on Object {
    return false;
  }
}

/// Key derivation of a password-protected .xknx (salt and iterations), or `null` if the project
/// has no password. For computing the key outside the parser, e.g. with the browser's Web Crypto.
({List<int> salt, int iterations})? xknxKeyDerivation(Uint8List bytes) {
  final project = _project(SqliteReader(bytes));
  return _kdf(project['password_salt'] as String?);
}

/// Reads a project of the XKNX Editor (.xknx, github.com/XKNX/xknx-editor): group addresses with
/// ranges and DPT, devices with product, manufacturer and location, and the associations with their
/// flags – the same catalog as [parseKnxproj].
///
/// The file is an SQLite database; it is only read. The editor encrypts only KNX Secure keys with
/// the project password, which are not imported. A password-protected project still asks for its
/// password and checks it against the stored check value, as the editor does: whoever opens the
/// project should know it. [key] is the already derived key (32 bytes), e.g. from Web Crypto.
///
/// Throws [KnxprojPasswordException] or [FormatException].
GroupCatalog parseXknx(Uint8List bytes, {String? password, List<int>? key}) {
  final SqliteReader db;
  try {
    db = SqliteReader(bytes);
  } on FormatException {
    throw FormatException(s.projectXknxInvalid);
  }
  final List<Map<String, Object?>> projects,
      ranges,
      gas,
      devices,
      segments,
      lines,
      areas,
      spaces,
      additional,
      objects,
      links;
  try {
    projects = db.rows('projects');
    ranges = db.rows('group_ranges');
    gas = db.rows('group_addresses');
    devices = db.rows('devices');
    segments = db.rows('segments');
    lines = db.rows('lines');
    areas = db.rows('areas');
    spaces = db.tables.contains('spaces') ? db.rows('spaces') : const [];
    additional = db.tables.contains('device_additional_addresses') ? db.rows('device_additional_addresses') : const [];
    objects = db.rows('com_objects');
    links = db.rows('com_object_links');
  } on FormatException {
    throw FormatException(s.projectXknxInvalid);
  }
  if (projects.isEmpty) throw FormatException(s.projectXknxInvalid);
  final project = projects.first;
  _checkPassword(project, password, key);

  final style = switch (project['group_address_style']) {
    'TwoLevel' => GroupStyle.twoLevel,
    'Free' => GroupStyle.free,
    _ => GroupStyle.threeLevel,
  };

  // --- Individual addresses: area.line.device over segment → line → area ------------------------
  final areaOf = {for (final a in areas) a['id']: a['address'] as int?};
  final lineOf = {for (final l in lines) l['id']: (area: areaOf[l['area_id']], line: l['address'] as int?)};
  final segmentLine = {for (final seg in segments) seg['id']: lineOf[seg['line_id']]};
  int? individual(Map<String, Object?> d) {
    final number = d['address'] as int?;
    final line = segmentLine[d['segment_id']];
    final area = line?.area;
    final l = line?.line;
    if (number == null || area == null || l == null) return null;
    if (area > 15 || l > 15 || number > 255) return null;
    return (area << 12) | (l << 8) | number;
  }

  // --- Locations: the spaces from the room up to below the building -----------------------------
  final spaceById = {for (final sp in spaces) sp['id']: sp};
  String? location(Object? spaceId) {
    final parts = <String>[];
    var current = spaceById[spaceId];
    var guard = 0;
    while (current != null && guard++ < 32) {
      final name = _text(current['name']);
      if (current['space_type'] != 'Building' && name != null) parts.add(name);
      current = spaceById[current['parent_id']];
    }
    return parts.isEmpty ? null : parts.reversed.join(' › ');
  }

  // --- Devices ----------------------------------------------------------------------------------
  final downloadKnown = devices.any((d) => _text(d['last_download']) != null);
  final manufacturers = <int, String>{};
  final addressOf = <Object?, int>{};
  final catalogDevices = <int, DeviceInfo>{};
  for (final d in devices) {
    final address = individual(d);
    if (address == null) continue;
    addressOf[d['id']] = address;
    final product = _text(d['product_name']) ?? _text(d['hardware_name']);
    final manufacturer = _text(d['manufacturer_name']);
    final manufacturerId = RegExp(r'^M-([0-9A-Fa-f]{4})_').firstMatch(_text(d['product_ref_id']) ?? '')?.group(1);
    if (manufacturer != null && manufacturerId != null) {
      manufacturers[int.parse(manufacturerId, radix: 16)] = manufacturer;
    }
    catalogDevices[address] = DeviceInfo(
      address: address,
      name: _text(d['name']) ?? product ?? s.projectDefaultDevice,
      product: product,
      manufacturer: manufacturer,
      location: location(d['space_id']),
      description: _text(d['description']),
      serial: serialFromBase64(_text(d['serial_number'])),
      neverProgrammed: downloadKnown && _text(d['last_download']) == null,
      pendingDownload: _text(d['last_download']) == null
          ? const []
          : [
              for (final (part, column) in _loadedColumns)
                if (d[column] == 0) part,
            ],
    );
  }
  // Additional addresses of IP interfaces (tunnels) – otherwise "foreign".
  final tunnelIndex = <int, int>{};
  for (final t in additional) {
    final parent = addressOf[t['device_id']];
    final number = t['address'] as int?;
    if (parent == null || number == null || number > 255) continue;
    final owner = catalogDevices[parent]!;
    final index = tunnelIndex[parent] = (tunnelIndex[parent] ?? 0) + 1;
    final pa = (parent & 0xFF00) | number;
    catalogDevices.putIfAbsent(
      pa,
      () => DeviceInfo(
        address: pa,
        name: '${owner.name} · ${_text(t['name']) ?? 'Tunnel $index'}',
        product: owner.product,
        manufacturer: owner.manufacturer,
        location: owner.location,
        tunnelOf: parent,
      ),
    );
  }

  // --- Associations -----------------------------------------------------------------------------
  final objectById = {for (final o in objects) o['id']: o};
  final linksByGa = <Object?, List<GroupLink>>{};
  final objectDpts = <Object?, List<Dpt?>>{};
  for (final l in links) {
    final o = objectById[l['com_object_id']];
    if (o == null) continue;
    final device = addressOf[o['device_id']];
    if (device == null) continue;
    bool? flag(String name) {
      final v = o['${name}_flag_override'] ?? o['${name}_flag'];
      return v == null ? null : v != 0;
    }

    final c = flag('communication');
    final r = flag('read');
    final w = flag('write');
    final t = flag('transmit');
    final u = flag('update');
    final flags = c == null || r == null || w == null || t == null || u == null
        ? null
        : ComFlags(communication: c, read: r, write: w, transmit: t, update: u);
    // Sending, as with the .knxproj: first address with Ü, not an input that accepts values (S + A),
    // and not without K.
    final transmits = t == null ? null : t && c != false && !(w == true && u == true);
    final ref = _text(o['ref_id']);
    // Object number only where it is in the reference; objects of modules have it in the
    // application only – better none than a wrong one.
    final number = ref == null || ref.contains('_MD-')
        ? null
        : int.tryParse(RegExp(r'_O-(\d+)_R-').firstMatch(ref)?.group(1) ?? '');
    final text = [_text(o['text_override']), _text(o['function_text_override'])].whereType<String>().join(' – ');
    final dptText = _text(o['datapoint_type_override']);
    (objectDpts[l['group_address_id']] ??= []).add(
      dptText == null || dptText.contains(' ') ? null : Dpt.tryParse(dptText),
    );
    (linksByGa[l['group_address_id']] ??= []).add(
      GroupLink(
        device: device,
        object: number,
        text: text.isEmpty ? null : text,
        sends: l['is_sending'] == 1 && (transmits ?? true),
        flags: flags,
        ref: ref,
      ),
    );
  }

  // --- Group addresses --------------------------------------------------------------------------
  final rangeById = {for (final r in ranges) r['id']: r};
  String? path(Object? rangeId) {
    final parts = <String>[];
    var current = rangeById[rangeId];
    var guard = 0;
    while (current != null && guard++ < 8) {
      final name = _text(current['name']);
      if (name != null) parts.add(name);
      current = rangeById[current['parent_id']];
    }
    return parts.isEmpty ? null : parts.reversed.join(' › ');
  }

  final groups = <int, GroupInfo>{};
  for (final g in gas) {
    final address = g['address'] as int?;
    if (address == null || address < 0 || address > 0xFFFF) continue;
    final dptText = _text(g['datapoint_type']);
    groups[address] = GroupInfo(
      address: address,
      name: _text(g['name']) ?? s.projectDefaultGroup,
      path: path(g['group_range_id']),
      dpt: dptText == null ? dptFromObjects(objectDpts[g['id']]) : Dpt.tryParse(dptText),
      description: _text(g['description']),
      links: [...?linksByGa[g['id']]]..sort((a, b) => a.device.compareTo(b.device)),
    );
  }
  if (groups.isEmpty) throw FormatException(s.projectNoGroups);
  return GroupCatalog(
    groups,
    devices: catalogDevices,
    projectName: _text(project['name']),
    style: style,
    manufacturers: manufacturers,
  );
}

const _loadedColumns = [
  (DownloadPart.address, 'individual_address_loaded'),
  (DownloadPart.application, 'application_program_loaded'),
  (DownloadPart.parameters, 'parameters_loaded'),
  (DownloadPart.groups, 'communication_part_loaded'),
  (DownloadPart.medium, 'medium_config_loaded'),
];

// --- Password -----------------------------------------------------------------------------------

const _aad = 'xknx-editor/enc1';
const _check = 'xknx-editor project password';

Map<String, Object?> _project(SqliteReader db) {
  final rows = db.rows('projects');
  if (rows.isEmpty) throw FormatException(s.projectXknxInvalid);
  return rows.first;
}

/// `pbkdf2-sha256:<iterations>:<base64 salt>` as the editor stores it.
({List<int> salt, int iterations})? _kdf(String? stored) {
  if (stored == null || stored.isEmpty) return null;
  final parts = stored.split(':');
  final iterations = parts.length == 3 ? int.tryParse(parts[1]) : null;
  if (parts.length != 3 || parts[0] != 'pbkdf2-sha256' || iterations == null || iterations < 1) {
    throw FormatException(s.projectXknxInvalid);
  }
  return (salt: base64.decode(parts[2]), iterations: iterations);
}

void _checkPassword(Map<String, Object?> project, String? password, List<int>? key) {
  final kdf = _kdf(project['password_salt'] as String?);
  if (kdf == null) return;
  if (key == null && (password == null || password.isEmpty)) {
    throw const KnxprojPasswordException(wrong: false);
  }
  final k = key ?? pbkdf2(utf8.encode(password!), kdf.salt, kdf.iterations, 32);
  if (!_verify(Uint8List.fromList(k), project['password_check'] as String? ?? '')) {
    throw const KnxprojPasswordException(wrong: true);
  }
}

/// The check value is "enc1:" + base64(nonce | AES-256-GCM(check text)).
bool _verify(Uint8List key, String check) {
  if (!check.startsWith('enc1:')) return false;
  try {
    final raw = base64.decode(check.substring(5));
    if (raw.length < 12 + 16) return false;
    final open = aesGcm(
      encrypt: false,
      key: key,
      nonce: Uint8List.sublistView(raw, 0, 12),
      aad: Uint8List.fromList(utf8.encode(_aad)),
      data: Uint8List.sublistView(raw, 12),
    );
    return utf8.decode(open, allowMalformed: true) == _check;
  } on Object {
    return false;
  }
}

String? _text(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}
