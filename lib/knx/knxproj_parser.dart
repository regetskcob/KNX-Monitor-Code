import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import '../l10n/locale_controller.dart';
import '../platform/safe_zip.dart';
import 'group_catalog.dart';
import 'telegram.dart';

/// The project is protected and [password] is missing or wrong.
class KnxprojPasswordException implements Exception {
  const KnxprojPasswordException({required this.wrong});

  /// `true`: password given but wrong. `false`: none given.
  final bool wrong;

  @override
  String toString() => wrong ? s.projectPasswordWrong : s.projectPasswordRequired;
}

/// Reads an ETS project (.knxproj, ETS5/ETS6): group addresses with ranges and DPT, devices with
/// product/manufacturer/location, and the associations between communication objects and group
/// addresses.
///
/// Unpacks only project, hardware and master data – the often very large application programs are
/// left untouched.
///
/// [ets6Password]: already derived ZIP password ([ets6ZipPassword]), e.g. computed faster via the
/// browser's cryptography.
///
/// Throws [KnxprojPasswordException] or [FormatException].
GroupCatalog parseKnxproj(Uint8List bytes, {String? password, String? ets6Password, String language = 'de-DE'}) {
  final Archive outer;
  try {
    outer = decodeZipLimited(bytes);
  } on ZipLimitException {
    throw FormatException(s.zipTooLarge);
  } on Object {
    throw FormatException(s.projectInvalidFile);
  }

  final master = outer.findFile('knx_master.xml');
  final schema = master == null ? 20 : _schemaVersion(master.content);

  final project = _openProject(outer, password, ets6Password, schema);
  final hardware = _products(outer, language);
  final manufacturers = master == null ? const <String, String>{} : _manufacturers(master.content);

  final doc = XmlDocument.parse(utf8.decode(project.data, allowMalformed: true));
  final info = project.info == null ? null : XmlDocument.parse(utf8.decode(project.info!, allowMalformed: true));
  final projectInfo = info?.findAllElements('ProjectInformation').firstOrNull;
  final projectName = projectInfo?.getAttribute('Name');
  final style = switch (projectInfo?.getAttribute('GroupAddressStyle')) {
    'TwoLevel' => GroupStyle.twoLevel,
    'Free' => GroupStyle.free,
    _ => GroupStyle.threeLevel,
  };

  // --- Group addresses -------------------------------------------------------
  final gaIds = <String, int>{}; // "GA-12" → address
  final gaElements = <int, XmlElement>{};
  for (final ga in doc.findAllElements('GroupAddress')) {
    final address = int.tryParse(ga.getAttribute('Address') ?? '');
    final id = ga.getAttribute('Id');
    if (address == null || id == null) continue;
    gaIds[_shortId(id, 'GA-')] = address;
    gaElements[address] = ga;
  }

  // --- Locations from the building structure ---------------------------------
  final locations = <String, String>{}; // DeviceInstance ID → location
  for (final ref in doc.findAllElements('DeviceInstanceRef')) {
    final id = ref.getAttribute('RefId');
    if (id == null) continue;
    final parts = ref.ancestorElements
        .where((e) => e.localName == 'BuildingPart' || e.localName == 'Space')
        .where((e) => e.getAttribute('Type') != 'Building')
        .map((e) => e.getAttribute('Name') ?? '')
        .where((n) => n.isNotEmpty)
        .toList()
        .reversed;
    if (parts.isNotEmpty) locations[id] = parts.join(' › ');
  }

  // --- Flags from the application programs --------------------------------
  // Only the first address of an object is sent – and only if the Ü (transmit) flag is set (display
  // objects also have their only address in first place, but do not send). The project comparison
  // needs K and L.
  final programs = _programsOfHardware(outer);
  final appOf = <XmlElement, String>{};
  for (final di in doc.findAllElements('DeviceInstance')) {
    final app = programs[di.getAttribute('Hardware2ProgramRefId')];
    if (app != null) appOf[di] = app;
  }
  // Only objects for which the project alone is not enough: a flag is missing on the instance, the
  // datapoint type is missing on object and group address, or the object comes from a module (its
  // number is only in the application).
  final gaWithoutDpt = {
    for (final MapEntry(:key, :value) in gaIds.entries)
      if (gaElements[value]?.getAttribute('DatapointType') == null) key,
  };
  final needed = <String>{};
  for (final MapEntry(key: di, value: app) in appOf.entries) {
    for (final co in di.findAllElements('ComObjectInstanceRef')) {
      final refs = _linkedGroupIds(co);
      if (refs.isEmpty) continue;
      final flagsMissing = _flagNames.any((name) => co.getAttribute(name) == null);
      final dptMissing = co.getAttribute('DatapointType') == null && refs.any(gaWithoutDpt.contains);
      final refId = co.getAttribute('RefId') ?? '';
      if (!flagsMissing && !dptMissing && !refId.startsWith('MD-')) continue;
      needed.add(_appRefId(app, refId));
    }
  }
  final appObjects = _objectFlags(outer, needed);

  // --- Devices and associations ----------------------------------------------
  final devices = <int, DeviceInfo>{};
  final links = <int, List<GroupLink>>{};
  // Datapoint types of the associated objects per group address – fallback when the group address
  // itself has none (always in ETS4, often in ETS5/6).
  final objectDpts = <int, List<Dpt?>>{};
  for (final di in doc.findAllElements('DeviceInstance')) {
    final address = _deviceAddress(di);
    if (address == null) continue;
    final productRef = di.getAttribute('ProductRefId');
    final product = hardware[productRef];
    final name = (di.getAttribute('Name') ?? '').trim();
    devices[address] = DeviceInfo(
      address: address,
      name: name.isNotEmpty ? name : product ?? s.projectDefaultDevice,
      product: product,
      manufacturer: productRef == null ? null : manufacturers[productRef.split('_').first],
      location: locations[di.getAttribute('Id')],
      description: _nonEmpty(di.getAttribute('Description')),
      serial: _serial(di.getAttribute('SerialNumber')),
    );

    // Additional addresses of IP interfaces (tunnels) – otherwise "foreign".
    final additional = di.findElements('AdditionalAddresses').firstOrNull?.findElements('Address') ?? const [];
    for (final (i, el) in additional.indexed) {
      final number = int.tryParse(el.getAttribute('Address') ?? '');
      if (number == null) continue;
      final pa = (address & 0xFF00) | number;
      devices.putIfAbsent(
        pa,
        () => DeviceInfo(
          address: pa,
          name: '${devices[address]!.name} · ${_nonEmpty(el.getAttribute('Name')) ?? 'Tunnel ${i + 1}'}',
          product: product,
          manufacturer: devices[address]!.manufacturer,
          location: devices[address]!.location,
          tunnelOf: address,
        ),
      );
    }

    // Arguments of the module instances ("MD-2_M-2_MI-1" → "MD-2_A-2" → "87"), among them the base
    // number of the objects of each channel.
    final moduleArgs = {
      for (final mi in di.findAllElements('ModuleInstance'))
        mi.getAttribute('Id') ?? '': {
          for (final a in mi.findAllElements('Argument')) a.getAttribute('RefId') ?? '': a.getAttribute('Value') ?? '',
        },
    };

    for (final co in di.findAllElements('ComObjectInstanceRef')) {
      final refs = _linkedGroupIds(co);
      if (refs.isEmpty) continue;
      final refId = co.getAttribute('RefId') ?? '';
      final app = appOf[di];
      final appObject = app == null ? appObjects[refId] : appObjects[_appRefId(app, refId)];
      // Objects from modules: number in the module plus the instance's base number; without both,
      // better no number than a wrong one.
      final module = RegExp(r'^(MD-\d+_M-\d+_MI-\d+)_O-').firstMatch(refId)?.group(1);
      final int? number;
      if (module != null) {
        final base = appObject?.baseNumber;
        final offset = base == null ? null : int.tryParse(moduleArgs[module]?[base] ?? '');
        number = appObject?.number == null || offset == null ? null : appObject!.number! + offset;
      } else {
        number = int.tryParse(RegExp(r'O-(\d+)').firstMatch(refId)?.group(1) ?? '');
      }
      // Only unambiguous values ("DPST-9-1"), no lists of allowed types.
      final dptText = _nonEmpty(co.getAttribute('DatapointType')) ?? appObject?.dpt;
      final objectDpt = dptText == null || dptText.trim().contains(' ') ? null : Dpt.tryParse(dptText);
      bool? own(String name) => switch (co.getAttribute(name)) {
        'Enabled' => true,
        'Disabled' => false,
        _ => null,
      };
      final base = appObject?.flags;
      final c = own('CommunicationFlag') ?? base?.communication;
      final r = own('ReadFlag') ?? base?.read;
      final t = own('TransmitFlag') ?? base?.transmit;
      final w = own('WriteFlag') ?? base?.write;
      final u = own('UpdateFlag') ?? base?.update;
      final flags = c == null || r == null || t == null || w == null || u == null
          ? null
          : ComFlags(communication: c, read: r, write: w, transmit: t, update: u);
      // Sending: Ü (transmit) flag – except for inputs that accept values (S + A), e.g.
      // display/state objects of push buttons with an additional Ü flag. Without the K flag the
      // object does not send at all.
      final bool? flag = t == null ? null : t && c != false && !(w == true && u == true);
      final text = [
        co.getAttribute('Text'),
        co.getAttribute('FunctionText'),
      ].map(_nonEmpty).whereType<String>().join(' – ');
      for (final (i, ref) in refs.indexed) {
        final ga = gaIds[ref];
        if (ga == null) continue;
        (objectDpts[ga] ??= []).add(objectDpt);
        (links[ga] ??= []).add(
          GroupLink(
            device: address,
            object: number,
            text: text.isEmpty ? null : text,
            // Without flags (application missing from the export): first address = sending.
            sends: i == 0 && (flag ?? true),
            flags: flags,
          ),
        );
      }
    }
  }

  // --- Assemble the catalog --------------------------------------------------
  final groups = <int, GroupInfo>{};
  for (final MapEntry(key: address, value: ga) in gaElements.entries) {
    final path = ga.ancestorElements
        .where((e) => e.localName == 'GroupRange')
        .map((e) => e.getAttribute('Name') ?? '')
        .where((n) => n.isNotEmpty)
        .toList()
        .reversed
        .join(' › ');
    final dptAttr = ga.getAttribute('DatapointType');
    groups[address] = GroupInfo(
      address: address,
      name: _nonEmpty(ga.getAttribute('Name')) ?? s.projectDefaultGroup,
      path: path.isEmpty ? null : path,
      dpt: dptAttr == null ? _dptFromObjects(objectDpts[address]) : Dpt.tryParse(dptAttr),
      description: _nonEmpty(ga.getAttribute('Description')),
      links: [...?links[address]]..sort((a, b) => a.device.compareTo(b.device)),
    );
  }
  if (groups.isEmpty) {
    throw FormatException(s.projectNoGroups);
  }
  return GroupCatalog(
    groups,
    devices: devices,
    projectName: projectName,
    style: style,
    manufacturers: {
      for (final MapEntry(:key, :value) in manufacturers.entries)
        if (key.startsWith('M-')) ?int.tryParse(key.substring(2), radix: 16): value,
    },
  );
}

/// Project data (0.xml) and project info (project.xml), decrypted if needed.
({Uint8List data, Uint8List? info}) _openProject(Archive outer, String? password, String? ets6Password, int schema) {
  // Unprotected: P-XXXX/0.xml lies directly in the archive.
  final plain = outer.files.where((f) => RegExp(r'^P-[0-9A-F]+/0\.xml$').hasMatch(f.name)).firstOrNull;
  if (plain != null) {
    final folder = plain.name.split('/').first;
    return (data: plain.content, info: outer.findFile('$folder/project.xml')?.content);
  }

  final inner = outer.files.where((f) => RegExp(r'^P-[0-9A-F]+\.zip$').hasMatch(f.name)).firstOrNull;
  if (inner == null) {
    throw FormatException(s.projectNoData);
  }
  final innerBytes = inner.content;

  // ETS6 (schema ≥ 21) derives the ZIP password via PBKDF2, ETS5 uses it directly. The derivation
  // takes seconds in the browser: only when needed.
  Iterable<String?> candidates() sync* {
    if (password == null || password.isEmpty) {
      yield null;
      return;
    }
    String ets6() => ets6Password ?? ets6ZipPassword(password);
    if (schema >= 21) {
      yield ets6();
      yield password;
    } else {
      yield password;
      yield ets6();
    }
  }

  for (final pw in candidates()) {
    try {
      final archive = decodeZipLimited(innerBytes, password: pw);
      final data = archive.findFile('0.xml')?.content;
      if (data == null) throw FormatException(s.projectMissing0xml);
      return (data: data, info: archive.findFile('project.xml')?.content);
    } on ZipLimitException {
      throw FormatException(s.zipTooLarge);
    } on ArchiveException catch (e) {
      final msg = e.message.toLowerCase();
      if (!msg.contains('password')) {
        throw FormatException(s.projectUnreadable(e.message));
      }
    }
  }
  throw KnxprojPasswordException(wrong: password != null && password.isNotEmpty);
}

/// ETS6: base64(PBKDF2-HMAC-SHA256(utf16le(pw), "21.project.ets.knx.org", 65536, 32)).
String ets6ZipPassword(String password) =>
    base64.encode(_pbkdf2(ets6KeyInput(password), utf8.encode(ets6Salt), ets6Iterations));

/// Inputs of the ETS6 derivation, for a computation outside the parser.
const ets6Salt = '21.project.ets.knx.org';
const ets6Iterations = 65536;

/// Password as UTF-16LE.
Uint8List ets6KeyInput(String password) {
  final pw = Uint8List(password.length * 2);
  for (var i = 0; i < password.length; i++) {
    final c = password.codeUnitAt(i);
    pw[i * 2] = c & 0xFF;
    pw[i * 2 + 1] = c >> 8;
  }
  return pw;
}

/// PBKDF2-HMAC-SHA256 with one block (32-byte key length).
List<int> _pbkdf2(List<int> password, List<int> salt, int iterations) {
  final hmac = Hmac(sha256, password);
  var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final result = List<int>.of(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < result.length; j++) {
      result[j] ^= u[j];
    }
  }
  return result;
}

int _schemaVersion(Uint8List master) {
  final head = latin1.decode(master.sublist(0, master.length.clamp(0, 400)));
  return int.tryParse(RegExp(r'knx\.org/xml/project/(\d+)').firstMatch(head)?.group(1) ?? '') ?? 20;
}

/// Product ID → product name (preferably in [language]) from all Hardware.xml files.
Map<String, String> _products(Archive outer, String language) {
  final result = <String, String>{};
  for (final f in outer.files.where((f) => f.name.endsWith('/Hardware.xml'))) {
    final doc = XmlDocument.parse(utf8.decode(f.content, allowMalformed: true));
    for (final p in doc.findAllElements('Product')) {
      final id = p.getAttribute('Id');
      final text = p.getAttribute('Text');
      if (id != null && text != null) result[id] = text;
    }
    final lang = doc.findAllElements('Language').where((l) => l.getAttribute('Identifier') == language).firstOrNull;
    if (lang == null) continue;
    for (final el in lang.findAllElements('TranslationElement')) {
      final id = el.getAttribute('RefId');
      if (id == null || !result.containsKey(id)) continue;
      final t = el.findElements('Translation').where((t) => t.getAttribute('AttributeName') == 'Text').firstOrNull;
      final text = t?.getAttribute('Text');
      if (text != null && text.isNotEmpty) result[id] = text;
    }
  }
  return result;
}

/// Hardware2Program ID → application program ID from all Hardware.xml files.
Map<String, String> _programsOfHardware(Archive outer) {
  final result = <String, String>{};
  for (final f in outer.files.where((f) => f.name.endsWith('/Hardware.xml'))) {
    final doc = XmlDocument.parse(utf8.decode(f.content, allowMalformed: true));
    for (final h2p in doc.findAllElements('Hardware2Program')) {
      final id = h2p.getAttribute('Id');
      final app = h2p.findElements('ApplicationProgramRef').firstOrNull?.getAttribute('RefId');
      if (id != null && app != null) result[id] = app;
    }
  }
  return result;
}

/// ID of the ComObjectRef in application [app] for the instance reference [refId]: "O-3_R-3" →
/// "M-0008_A-1_O-3_R-3". Objects from modules carry the module instance in the project
/// ("MD-2_M-2_MI-1_O-2-25_R-1"), but only the module in the application ("…_MD-2_O-2-25_R-1").
String _appRefId(String app, String refId) {
  if (refId.startsWith('M-')) return refId;
  return '${app}_${refId.replaceFirstMapped(RegExp(r'^(MD-\d+)_M-\d+_MI-\d+_'), (m) => '${m[1]}_')}';
}

/// Flag attributes of a communication object in the ETS.
const _flagNames = ['CommunicationFlag', 'ReadFlag', 'WriteFlag', 'TransmitFlag', 'UpdateFlag'];

/// ComObjectRef ID → flags and datapoint type (ComObjectRef overrides ComObject) – only for the
/// [needed] references. `flags` is `null` if the ComObject is missing and the reference does not
/// name all flags itself. For objects from modules, [number] is relative to the module argument
/// [baseNumber] (short ID like "MD-2_A-2"), whose value the module instance in the project
/// specifies.
///
/// Application programs are often tens of MB in size. They are therefore not loaded into memory as
/// a whole, but scanned piece by piece for `<ComObject …>` and `<ComObjectRef …>` tags while
/// unpacking.
typedef _AppObject = ({ComFlags? flags, String? dpt, int? number, String? baseNumber});

Map<String, _AppObject> _objectFlags(Archive outer, Set<String> needed) {
  final result = <String, _AppObject>{};
  String? attr(String t, String name) => RegExp('\\s$name="([^"]*)"').firstMatch(t)?.group(1);
  bool? flag(String tag, String name) => switch (attr(tag, name)) {
    'Enabled' => true,
    'Disabled' => false,
    _ => null,
  };
  // The program ID is the part before "_O-" or "_MD-", e.g. "M-0008_A-1".
  final apps = {for (final id in needed) id.split(RegExp('_(O|MD)-')).first};
  for (final app in apps) {
    final file = outer.findFile('${app.split('_').first}/$app.xml');
    if (file == null) continue;
    final objects = <String, ({ComFlags flags, String? dpt, int? number, String? baseNumber})>{};
    final refs = <(String id, String? ref, String tag)>[];
    final scanner = TagScanner(['<ComObjectRef ', '<ComObject '], (tag) {
      final id = attr(tag, 'Id');
      if (id == null) return;
      if (tag.startsWith('<ComObject ')) {
        // Missing attributes: defaults of the ETS schema (only K is on).
        objects[id] = (
          flags: ComFlags(
            communication: flag(tag, 'CommunicationFlag') ?? true,
            read: flag(tag, 'ReadFlag') ?? false,
            write: flag(tag, 'WriteFlag') ?? false,
            transmit: flag(tag, 'TransmitFlag') ?? false,
            update: flag(tag, 'UpdateFlag') ?? false,
          ),
          dpt: _nonEmpty(attr(tag, 'DatapointType')),
          number: int.tryParse(attr(tag, 'Number') ?? ''),
          baseNumber: attr(tag, 'BaseNumber')?.replaceFirst('${app}_', ''),
        );
      } else if (needed.contains(id)) {
        refs.add((id, attr(tag, 'RefId'), tag));
      }
    });
    file.writeContent(scanner);
    scanner.finish();
    for (final (id, ref, tag) in refs) {
      final base = objects[ref];
      final c = flag(tag, 'CommunicationFlag') ?? base?.flags.communication;
      final r = flag(tag, 'ReadFlag') ?? base?.flags.read;
      final w = flag(tag, 'WriteFlag') ?? base?.flags.write;
      final t = flag(tag, 'TransmitFlag') ?? base?.flags.transmit;
      final u = flag(tag, 'UpdateFlag') ?? base?.flags.update;
      final flags = c == null || r == null || w == null || t == null || u == null
          ? null
          : ComFlags(communication: c, read: r, write: w, transmit: t, update: u);
      result[id] = (
        flags: flags,
        dpt: _nonEmpty(attr(tag, 'DatapointType')) ?? base?.dpt,
        number: base?.number,
        baseNumber: base?.baseNumber,
      );
    }
  }
  return result;
}

/// Accepts unpacked bytes piece by piece and reports every complete tag that starts with one of the
/// [prefixes] (up to `>`) as Latin-1 text.
///
/// The decompressor (inflate) reads back up to 32 KB while writing ([writeBackReference]); hence a
/// sliding window: fill the buffer, scan on overflow and keep only the end (window or partial tag).
/// Memory use thus stays at a few hundred KB, regardless of the file size. Call [finish] after
/// unpacking.
class TagScanner extends OutputStream {
  TagScanner(this.prefixes, this.onTag) : super(byteOrder: ByteOrder.littleEndian);

  final List<String> prefixes;
  final void Function(String tag) onTag;

  static const _window = 32 * 1024;
  late final _patterns = [for (final p in prefixes) latin1.encode(p)];
  late final _longest = _patterns.map((p) => p.length).reduce((a, b) => a > b ? a : b);

  Uint8List _buf = Uint8List(1 << 18);
  int _len = 0; // used in _buf
  int _scan = 0; // not yet scanned from here on
  int _total = 0; // total written

  @override
  int get length => _total;

  @override
  void clear() {
    _len = 0;
    _scan = 0;
    _total = 0;
  }

  @override
  void flush() {}

  /// Scans the rest; afterwards the scanner is done.
  void finish() {
    _scanTo(final_: true);
  }

  void _reserve(int n) {
    if (_len + n <= _buf.length) return;
    final stop = _scanTo();
    final keep = (stop < _len - _window ? stop : _len - _window).clamp(0, _len);
    if (keep > 0) {
      _buf.setRange(0, _len - keep, _buf, keep);
      _len -= keep;
      _scan -= keep;
    }
    if (_len + n > _buf.length) {
      final bigger = Uint8List((_len + n) * 2);
      bigger.setRange(0, _len, _buf);
      _buf = bigger;
    }
  }

  @override
  void writeByte(int value) {
    _reserve(1);
    _buf[_len++] = value;
    _total++;
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final n = length ?? bytes.length;
    // Copy, in case [bytes] is a view into our own buffer (subset).
    final source = _len + n > _buf.length && bytes is Uint8List && identical(bytes.buffer, _buf.buffer)
        ? Uint8List.fromList(bytes.sublist(0, n))
        : bytes;
    _reserve(n);
    _buf.setRange(_len, _len + n, source);
    _len += n;
    _total += n;
  }

  @override
  void writeBackReference(int distance, int count) {
    _reserve(count);
    for (var k = 0; k < count; k++) {
      _buf[_len] = _buf[_len - distance];
      _len++;
    }
    _total += count;
  }

  @override
  void writeStream(InputStream stream) => writeBytes(stream.toUint8List());

  @override
  Uint8List subset(int start, [int? end]) {
    final offset = _total - _len; // absolute position of _buf[0]
    final s = start < 0 ? _len + start : start - offset;
    final e = end == null ? _len : (end < 0 ? _len + end : end - offset);
    return Uint8List.sublistView(_buf, s, e);
  }

  /// Scans [_scan, _len); returns the start of a still incomplete tag (or _len), from which the
  /// next scan continues.
  int _scanTo({bool final_ = false}) {
    var i = _scan;
    var stop = _len;
    while (true) {
      final start = _indexOf(0x3C, i); // '<'
      if (start < 0) break;
      final pattern = _patterns.where((p) => _startsWith(start, p)).firstOrNull;
      if (pattern == null) {
        if (!final_ && _len - start < _longest) {
          stop = start; // possibly truncated start
          break;
        }
        i = start + 1;
        continue;
      }
      final end = _indexOf(0x3E, start); // '>'
      if (end < 0) {
        stop = start;
        break;
      }
      onTag(latin1.decode(Uint8List.sublistView(_buf, start, end + 1)));
      i = end + 1;
    }
    _scan = stop;
    return stop;
  }

  int _indexOf(int byte, int from) {
    for (var k = from; k < _len; k++) {
      if (_buf[k] == byte) return k;
    }
    return -1;
  }

  bool _startsWith(int at, List<int> p) {
    if (at + p.length > _len) return false;
    for (var k = 0; k < p.length; k++) {
      if (_buf[at + k] != p[k]) return false;
    }
    return true;
  }
}

/// Manufacturer ID ("M-0008") → name from knx_master.xml (via regex, since it is large).
Map<String, String> _manufacturers(Uint8List master) {
  final text = utf8.decode(master, allowMalformed: true);
  final result = <String, String>{};
  for (final m in RegExp(r'<Manufacturer\s[^>]*>').allMatches(text)) {
    final tag = m.group(0)!;
    final id = RegExp(r'\sId="([^"]+)"').firstMatch(tag)?.group(1);
    final name = RegExp(r'\sName="([^"]+)"').firstMatch(tag)?.group(1);
    if (id != null && name != null) result[id] = _unescape(name);
  }
  return result;
}

/// Individual address from area, line and device number.
int? _deviceAddress(XmlElement di) {
  final device = int.tryParse(di.getAttribute('Address') ?? '');
  if (device == null) return null;
  final line = di.ancestorElements.where((e) => e.localName == 'Line').firstOrNull;
  final area = di.ancestorElements.where((e) => e.localName == 'Area').firstOrNull;
  final l = int.tryParse(line?.getAttribute('Address') ?? '');
  final a = int.tryParse(area?.getAttribute('Address') ?? '');
  if (l == null || a == null) return null;
  return (a << 12) | (l << 8) | device;
}

/// Associated group addresses of an object as short IDs, sending ones first. ETS5/6: attribute
/// `Links`; older schemas: `Connectors/Send|Receive`.
List<String> _linkedGroupIds(XmlElement co) {
  final links = co.getAttribute('Links');
  if (links != null) {
    return links.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).map((s) => _shortId(s, 'GA-')).toList();
  }
  final connectors = co.findElements('Connectors').firstOrNull;
  if (connectors == null) return const [];
  return [
    ...connectors.findElements('Send'),
    ...connectors.findElements('Receive'),
  ].map((e) => e.getAttribute('GroupAddressRefId')).whereType<String>().map((s) => _shortId(s, 'GA-')).toList();
}

/// "P-03E1-0_GA-369" → "GA-369".
String _shortId(String id, String marker) {
  final i = id.lastIndexOf(marker);
  return i < 0 ? id : id.substring(i);
}

String? _nonEmpty(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');

/// Serial number from the ETS (Base64, 6 bytes) as 12 hex characters.
String? _serial(String? value) {
  if (value == null || value.isEmpty) return null;
  try {
    final bytes = base64.decode(value);
    if (bytes.length != 6) return null;
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join();
  } on FormatException {
    return null;
  }
}

/// Datapoint type from the associated communication objects – deliberately cautious: a wrong type
/// decodes every telegram wrongly. Only if all objects that specify one name the same main type;
/// the subtype only if it matches too.
Dpt? _dptFromObjects(List<Dpt?>? candidates) {
  final known = [...?candidates?.whereType<Dpt>()];
  if (known.isEmpty) return null;
  final main = known.first.main;
  if (known.any((d) => d.main != main)) return null;
  final subs = known.map((d) => d.sub).toSet();
  return Dpt(main, subs.length == 1 ? subs.single : null);
}
