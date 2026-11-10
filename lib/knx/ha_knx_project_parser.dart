import '../l10n/locale_controller.dart';
import 'group_catalog.dart';
import 'knxproj_parser.dart' show dptFromObjects, serialFromBase64;
import 'telegram.dart';

/// Reads the KNX project of Home Assistant's KNX integration, as its WebSocket command
/// `knx/get_knx_project` returns it (the format of xknxproject, github.com/XKNX/xknxproject): the
/// same catalog as from a .knxproj. The integration has the project from its panel or from the
/// XKNX Editor.
///
/// [haGroups]: group addresses Home Assistant writes to (entities, exposes), as printed addresses;
/// they become [GroupCatalog.externalSenders].
///
/// Throws [FormatException] when [project] is not such a project.
GroupCatalog parseHaKnxProject(Map<String, Object?> project, {Iterable<String> haGroups = const []}) {
  Map<String, Object?> map(Object? v) => v is Map ? v.cast<String, Object?>() : const {};
  String? text(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

  final info = map(project['info']);
  final gas = map(project['group_addresses']);
  if (gas.isEmpty) throw FormatException(s.projectNoGroups);
  final style = switch (info['group_address_style']) {
    'TwoLevel' => GroupStyle.twoLevel,
    'Free' => GroupStyle.free,
    _ => GroupStyle.threeLevel,
  };
  int? group(String printed) => parseGroupAddress(printed, style);

  // --- Locations: the space that lists a device, up to below the building ----------------------
  final locationOf = <String, String>{};
  void walkSpaces(Map<String, Object?> spaces, List<String> path) {
    for (final space in spaces.values) {
      final sp = map(space);
      final name = text(sp['name']);
      final here = [...path, if (sp['type'] != 'Building' && name != null) name];
      for (final device in (sp['devices'] as List? ?? const []).whereType<String>()) {
        locationOf.putIfAbsent(device, () => here.join(' › '));
      }
      walkSpaces(map(sp['spaces']), here);
    }
  }

  walkSpaces(map(project['locations']), const []);

  // --- KNX RF: the topology names the medium per line and lists its devices --------------------
  final rfDevices = <String>{};
  for (final area in map(project['topology']).values) {
    for (final line in map(map(area)['lines']).values) {
      final l = map(line);
      if (isRfMedium(l['medium_type'])) rfDevices.addAll((l['devices'] as List? ?? const []).whereType<String>());
    }
  }

  // --- Devices ----------------------------------------------------------------------------------
  final rawDevices = map(project['devices']);
  final downloadKnown = rawDevices.values.any((d) => text(map(d)['last_download']) != null);
  final devices = <int, DeviceInfo>{};
  final manufacturers = <int, String>{};
  for (final MapEntry(key: ia, value: raw) in rawDevices.entries) {
    final d = map(raw);
    final address = parseIndividual(ia);
    if (address == null) continue;
    final product = text(d['hardware_name']) ?? text(d['order_number']);
    final manufacturer = text(d['manufacturer_name']);
    final mid = RegExp(r'^M-([0-9A-Fa-f]{4})_').firstMatch(text(d['product_id']) ?? text(d['application']) ?? '');
    if (manufacturer != null && mid != null) manufacturers[int.parse(mid.group(1)!, radix: 16)] = manufacturer;
    final downloaded = text(d['last_download']) != null;
    devices[address] = DeviceInfo(
      address: address,
      name: text(d['name']) ?? product ?? s.projectDefaultDevice,
      product: product,
      manufacturer: manufacturer,
      location: switch (locationOf[ia]) {
        final l? when l.isNotEmpty => l,
        _ => null,
      },
      description: text(d['description']),
      serial: serialFromBase64(text(d['serial_number'])),
      neverProgrammed: downloadKnown && !downloaded,
      rf: rfDevices.contains(ia),
      pendingDownload: !downloaded
          ? const []
          : [
              for (final (part, key) in const [
                (DownloadPart.address, 'individual_address_loaded'),
                (DownloadPart.application, 'application_program_loaded'),
                (DownloadPart.parameters, 'parameters_loaded'),
                (DownloadPart.groups, 'communication_part_loaded'),
                (DownloadPart.medium, 'medium_config_loaded'),
              ])
                if (d[key] == false) part,
            ],
    );
  }

  // --- Associations -----------------------------------------------------------------------------
  final links = <int, List<GroupLink>>{};
  final objectDpts = <int, List<Dpt?>>{};
  for (final MapEntry(key: id, value: raw) in map(project['communication_objects']).entries) {
    final o = map(raw);
    final device = parseIndividual(text(o['device_address']) ?? '');
    if (device == null) continue;
    final f = map(o['flags']);
    bool? flag(String name) => f[name] is bool ? f[name]! as bool : null;
    final c = flag('communication');
    final r = flag('read');
    final w = flag('write');
    final t = flag('transmit');
    final u = flag('update');
    final flags = c == null || r == null || w == null || t == null || u == null
        ? null
        : ComFlags(communication: c, read: r, write: w, transmit: t, update: u);
    final transmits = t == null ? null : t && c != false && !(w == true && u == true);
    final dpts = [
      for (final d in (o['dpts'] as List? ?? const []))
        if (map(d)['main'] case final int main) Dpt(main, map(d)['sub'] as int?),
    ];
    final objectText = [text(o['text']), text(o['function_text'])].whereType<String>().toSet().join(' – ');
    // "1.1.5/M-0083_A-…_O-0_R-1": the part after the device address is the reference the ETS and
    // the XKNX Editor use.
    final slash = id.indexOf('/');
    final ref = slash < 0 ? null : id.substring(slash + 1);
    for (final (i, printed) in (o['group_address_links'] as List? ?? const []).whereType<String>().indexed) {
      final ga = group(printed);
      if (ga == null) continue;
      (objectDpts[ga] ??= []).add(dpts.length == 1 ? dpts.single : null);
      (links[ga] ??= []).add(
        GroupLink(
          device: device,
          object: o['module_def'] == null && o['number'] is int ? o['number'] as int : null,
          text: objectText.isEmpty ? null : objectText,
          sends: i == 0 && (transmits ?? true),
          flags: flags,
          ref: ref,
        ),
      );
    }
  }

  // --- Group ranges for the path ----------------------------------------------------------------
  final pathOf = <String, String>{};
  void walkRanges(Map<String, Object?> ranges, List<String> path) {
    for (final range in ranges.values) {
      final r = map(range);
      final name = text(r['name']);
      final here = [...path, ?name];
      for (final printed in (r['group_addresses'] as List? ?? const []).whereType<String>()) {
        pathOf[printed] = here.join(' › ');
      }
      walkRanges(map(r['group_ranges']), here);
    }
  }

  walkRanges(map(project['group_ranges']), const []);

  final groups = <int, GroupInfo>{};
  for (final MapEntry(key: printed, value: raw) in gas.entries) {
    final g = map(raw);
    final address = (g['raw_address'] as int?) ?? group(printed);
    if (address == null || address < 0 || address > 0xFFFF) continue;
    final dpt = map(g['dpt']);
    groups[address] = GroupInfo(
      address: address,
      name: text(g['name']) ?? s.projectDefaultGroup,
      path: switch (pathOf[printed]) {
        final p? when p.isNotEmpty => p,
        _ => null,
      },
      dpt: dpt['main'] is int ? Dpt(dpt['main']! as int, dpt['sub'] as int?) : dptFromObjects(objectDpts[address]),
      description: text(g['description']),
      links: [...?links[address]]..sort((a, b) => a.device.compareTo(b.device)),
    );
  }
  if (groups.isEmpty) throw FormatException(s.projectNoGroups);
  return GroupCatalog(
    groups,
    devices: devices,
    projectName: text(info['name']),
    style: style,
    manufacturers: manufacturers,
    externalSenders: {...haGroups.map(group).whereType<int>()},
  );
}
