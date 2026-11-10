import 'dart:convert';
import 'dart:io';

import 'package:knx/knx.dart';

/// The project as the app stores it for the server (`catalog.json`, `GroupCatalog.toJson()` in
/// the app), reduced to what the project check needs.
class LintCatalog {
  LintCatalog(
    this.groups,
    this.devices, {
    this.style = GroupStyle.threeLevel,
    this.projectName,
    this.external = const {},
  });

  final Map<int, LintGroup> groups;
  final Map<int, LintDevice> devices;
  final GroupStyle style;
  final String? projectName;

  /// Group addresses written from outside the project (Home Assistant).
  final Set<int> external;

  bool get isEmpty => groups.isEmpty;

  factory LintCatalog.fromJson(Map<String, Object?> j) {
    final style = switch (j['style']) {
      'twoLevel' => GroupStyle.twoLevel,
      'free' => GroupStyle.free,
      _ => GroupStyle.threeLevel,
    };
    final groups = <int, LintGroup>{};
    for (final g in (j['groups'] as List? ?? const []).whereType<Map<String, Object?>>()) {
      final a = g['a'];
      if (a is! int) continue;
      final d = g['d'] as List?;
      groups[a] = LintGroup(
        address: a,
        name: g['n'] as String? ?? '',
        path: g['p'] as String?,
        dpt: d == null || d.isEmpty ? null : (d[0] as int, d.length > 1 ? d[1] as int? : null),
        links: [
          for (final l in (g['l'] as List? ?? const []).whereType<Map<String, Object?>>())
            if (l['d'] case final int device)
              LintLink(
                device: device,
                object: l['o'] as int?,
                text: l['t'] as String?,
                sends: l['s'] == true,
                flags: l['f'] as String?,
                ref: l['r'] as String?,
              ),
        ],
      );
    }
    final devices = <int, LintDevice>{};
    for (final d in (j['devices'] as List? ?? const []).whereType<Map<String, Object?>>()) {
      final a = d['a'];
      if (a is! int) continue;
      devices[a] = LintDevice(
        address: a,
        name: d['n'] as String? ?? '',
        product: d['p'] as String?,
        location: d['l'] as String?,
        tunnel: d['tu'] != null,
        neverProgrammed: d['np'] == true,
        pendingDownload: [...?(d['pd'] as List?)?.whereType<String>()],
      );
    }
    return LintCatalog(
      groups,
      devices,
      style: style,
      projectName: j['project'] as String?,
      external: {...?(j['xs'] as List?)?.whereType<int>()},
    );
  }

  /// `catalog.json` in [data]; empty without a project.
  static Future<LintCatalog> load(Directory data) async {
    final file = File('${data.path}/catalog.json');
    if (!await file.exists()) return LintCatalog(const {}, const {});
    try {
      return LintCatalog.fromJson(jsonDecode(await file.readAsString()) as Map<String, Object?>);
    } on Object {
      return LintCatalog(const {}, const {});
    }
  }
}

class LintGroup {
  const LintGroup({required this.address, required this.name, this.path, this.dpt, this.links = const []});
  final int address;
  final String name;
  final String? path;
  final (int, int?)? dpt;
  final List<LintLink> links;
}

class LintLink {
  const LintLink({required this.device, this.object, this.text, this.sends = false, this.flags, this.ref});
  final int device;
  final int? object;
  final String? text;
  final bool sends;

  /// Flags as letters (`CRWTU`), `null` when unknown.
  final String? flags;
  final String? ref;

  bool get known => flags != null;
  bool get communication => flags?.contains('C') ?? true;
  bool get read => flags?.contains('R') ?? false;
  bool get write => flags?.contains('W') ?? false;
  bool get answersReads => communication && read;
}

class LintDevice {
  const LintDevice({
    required this.address,
    required this.name,
    this.product,
    this.location,
    this.tunnel = false,
    this.neverProgrammed = false,
    this.pendingDownload = const [],
  });
  final int address;
  final String name;
  final String? product;
  final String? location;
  final bool tunnel;
  final bool neverProgrammed;
  final List<String> pendingDownload;
}

/// Same words as `isStatusGroup` in the app (lib/model/commissioning.dart).
final _statusName = RegExp(
  r'status|rückmeld|rücmled|\brm\b|ist[- ]|feedback|zustand|actual|\bstate\b',
  caseSensitive: false,
);

bool isStatusGroup(LintGroup g) => _statusName.hasMatch(g.name) || _statusName.hasMatch(g.path ?? '');

/// The checks on the project itself, without bus traffic: the rules of `ProjectLint` in the app
/// (lib/model/project_check.dart). Both are held to the same expected findings:
/// `test/fixtures/project_lint/` and `project_lint_parity_test.dart` in app and server.
/// Flag checks only on addresses whose objects all have known flags.
class ProjectLintResult {
  ProjectLintResult._(this.catalog, this.lists, {required this.hasFlags});

  final LintCatalog catalog;
  final bool hasFlags;

  /// Findings by kind (see [kinds]): group addresses (`group`) or devices (`device`).
  final Map<String, List<Map<String, Object?>>> lists;

  /// Kinds with their subject and a short English explanation for an AI reader.
  static const kinds = <String, ({String subject, String meaning})>{
    'status_without_transmit': (subject: 'group', meaning: 'status address that no object with the T flag sends to'),
    'read_without_read_flag': (
      subject: 'group',
      meaning: 'status address without an object with C and R: reads stay unanswered',
    ),
    'multiple_read_answers': (subject: 'group', meaning: 'several objects with C and R: one read gets several answers'),
    'object_without_communication': (subject: 'group', meaning: 'object linked to the address without the C flag'),
    'multiple_senders': (subject: 'group', meaning: 'several objects send to the address (often intended)'),
    'without_sender': (subject: 'group', meaning: 'command address no object in the project sends to (notice)'),
    'without_receiver': (subject: 'group', meaning: 'command address without an object with C and W'),
    'no_name': (subject: 'group', meaning: 'address with the default name only'),
    'no_dpt': (subject: 'group', meaning: 'address without a datapoint type'),
    'main_group_14_15': (subject: 'group', meaning: 'address in main group 14 or 15 with several lines'),
    'device_without_links': (subject: 'device', meaning: 'device without any linked group address'),
    'device_never_programmed': (subject: 'device', meaning: 'device never downloaded according to the project'),
    'device_download_pending': (subject: 'device', meaning: 'device changed in the project since its last download'),
    'crowded_line': (subject: 'line', meaning: 'line with more than 50 devices'),
  };

  factory ProjectLintResult.of(LintCatalog catalog) {
    final lists = {for (final k in kinds.keys) k: <Map<String, Object?>>[]};
    String ga(int a) => formatGroupAddress(a, catalog.style);
    Map<String, Object?> group(LintGroup g, [Iterable<LintLink>? links]) => {
      'group_address': ga(g.address),
      'name': g.name,
      if (links != null)
        'objects': [
          for (final l in links)
            {
              'device': formatIndividual(l.device),
              'object': ?l.object,
              'text': ?l.text,
              'flags': ?l.flags,
              'ref': ?l.ref,
              if (l.sends) 'sends': true,
            },
        ],
    };
    Map<String, Object?> device(LintDevice d, [Map<String, Object?> extra = const {}]) => {
      'device': formatIndividual(d.address),
      'name': d.name,
      'product': ?d.product,
      'location': ?d.location,
      ...extra,
    };

    var hasFlags = false;
    final linked = <int>{};
    final unlinked = <LintGroup>[];
    final sorted = catalog.groups.values.toList()..sort((a, b) => a.address.compareTo(b.address));
    for (final g in sorted) {
      final name = g.name.trim().toLowerCase();
      final noName =
          name.isEmpty ||
          name == ga(g.address) ||
          const {'gruppenadresse', 'group address', 'neue gruppenadresse', 'new group address'}.contains(name);
      if (noName) lists['no_name']!.add(group(g));
      if (g.dpt == null) lists['no_dpt']!.add(group(g));
      for (final l in g.links) {
        linked.add(l.device);
        if (l.known && !l.communication) lists['object_without_communication']!.add(group(g, [l]));
      }
      if (g.links.isEmpty) {
        if (!isStatusGroup(g)) unlinked.add(g);
        continue;
      }
      if (g.links.any((l) => !l.known)) continue;
      hasFlags = true;
      final senders = g.links.where((l) => l.sends).length;
      if (senders > 1) lists['multiple_senders']!.add(group(g, g.links.where((l) => l.sends)));
      if (g.links.where((l) => l.answersReads).length > 1) {
        lists['multiple_read_answers']!.add(group(g, g.links.where((l) => l.answersReads)));
      }
      if (!isStatusGroup(g)) {
        if (senders == 0 && !catalog.external.contains(g.address)) lists['without_sender']!.add(group(g, g.links));
        if (!g.links.any((l) => l.communication && l.write)) lists['without_receiver']!.add(group(g, g.links));
        continue;
      }
      if (senders == 0) lists['status_without_transmit']!.add(group(g, g.links));
      if (!g.links.any((l) => l.answersReads)) lists['read_without_read_flag']!.add(group(g, g.links));
    }
    if (hasFlags) {
      lists['without_receiver']!
        ..addAll([for (final g in unlinked) group(g)])
        ..sort((a, b) => (a['group_address']! as String).compareTo(b['group_address']! as String));
    }
    final perLine = <int, int>{};
    for (final d in catalog.devices.values.toList()..sort((a, b) => a.address.compareTo(b.address))) {
      if (d.tunnel) continue;
      // Couplers (device 0) have no objects and do not count for the line, but can be pending.
      if (d.address & 0xFF != 0) {
        perLine[d.address >> 8] = (perLine[d.address >> 8] ?? 0) + 1;
        if (!linked.contains(d.address)) lists['device_without_links']!.add(device(d));
      }
      if (d.neverProgrammed) lists['device_never_programmed']!.add(device(d));
      if (d.pendingDownload.isNotEmpty) {
        lists['device_download_pending']!.add(device(d, {'parts': d.pendingDownload}));
      }
    }
    for (final MapEntry(key: line, value: n) in perLine.entries) {
      if (n > 50) lists['crowded_line']!.add({'line': '${line >> 4}.${line & 0xF}', 'devices': n});
    }
    if (perLine.length >= 2 && catalog.style != GroupStyle.free) {
      for (final g in sorted) {
        final main = (g.address >> 11) & 0x1F;
        if (main == 14 || main == 15) lists['main_group_14_15']!.add(group(g));
      }
    }
    return ProjectLintResult._(catalog, lists, hasFlags: hasFlags);
  }
}
