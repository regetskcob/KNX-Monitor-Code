import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../knx/dali.dart';
import '../knx/group_catalog.dart';

/// What a communication object of a DALI gateway carries.
enum DaliRole {
  /// DPT 237.600 or 238.600: faults per DALI address in the payload.
  diagnostic(DaliIndex.none),

  /// 1 bit per control gear: 1 = lamp failure.
  lampFault(DaliIndex.gear),

  /// 1 bit per control gear: 1 = failure of the control gear (or "any fault" where a gateway does
  /// not tell lamp and gear apart).
  gearFault(DaliIndex.gear),

  /// 1 bit per group: 1 = a fault in the group.
  groupFault(DaliIndex.group),

  /// Number of failed lamps or control gear on the gateway.
  faultCount(DaliIndex.none),

  /// Gateway-specific fault number, explained by the profile's code table.
  faultCode(DaliIndex.none),

  /// Burn hours of a control gear.
  burnHours(DaliIndex.gear),

  /// DPT 244.600 of one emergency converter.
  emergencyStatus(DaliIndex.gear),

  /// DPT 245.600 of one emergency converter.
  emergencyResult(DaliIndex.gear),

  /// Group: switch (1 bit, input of the gateway).
  groupSwitch(DaliIndex.group),

  /// Group: relative dimming (DPT 3, input).
  groupDim(DaliIndex.group),

  /// Group: brightness value (DPT 5.001, input).
  groupValue(DaliIndex.group),

  /// Group: switch state (1 bit, output of the gateway).
  groupStatus(DaliIndex.group),

  /// Group: brightness state (DPT 5.001, output).
  groupValueStatus(DaliIndex.group);

  const DaliRole(this.counts);

  /// What the number of the object counts.
  final DaliIndex counts;
}

/// What the number in an object counts.
enum DaliIndex { none, gear, group }

/// Whether a profile was checked against a real gateway.
enum DaliProfileStatus {
  /// Built from the manufacturer's documentation only.
  documented,

  /// Checked against telegrams of a real gateway.
  verified,
}

/// A rule of a profile: which objects carry which [role].
///
/// Either by object number ([first], every [step] objects, [count] times: the n-th object belongs
/// to index n) or by object text ([pattern], the first group is the number as the gateway prints
/// it).
@immutable
class DaliRule {
  const DaliRule({required this.role, this.pattern, this.first, this.step = 1, this.count = 1});

  final DaliRole role;
  final RegExp? pattern;
  final int? first;
  final int step;
  final int count;

  /// `null` for an entry that is no rule (unknown role, broken pattern, neither number nor text).
  static DaliRule? fromJson(Object? json) {
    if (json is! Map) return null;
    final role = DaliRole.values.asNameMap()[json['role']];
    if (role == null) return null;
    RegExp? pattern;
    if (json['text'] case final String text when text.isNotEmpty && text.length <= 200) {
      try {
        pattern = RegExp(text, caseSensitive: false);
      } on FormatException {
        return null;
      }
    }
    final first = json['first'];
    final step = json['step'];
    final count = json['count'];
    if (pattern == null && first is! int) return null;
    return DaliRule(
      role: role,
      pattern: pattern,
      first: first is int && first >= 0 ? first : null,
      step: step is int && step > 0 ? step : 1,
      count: count is int && count > 0 && count <= 64 ? count : 1,
    );
  }

  /// Index as the gateway counts it (not yet a DALI address) for an object with [number] and
  /// [text]; `(matched, index)`.
  (bool, int?) match(int? number, String? text) {
    final first = this.first;
    if (first != null) {
      if (number == null || number < first) return (false, null);
      final offset = number - first;
      if (offset % step != 0 || offset ~/ step >= count) return (false, null);
      return (true, role.counts == DaliIndex.none ? null : offset ~/ step);
    }
    final m = text == null ? null : pattern?.firstMatch(text);
    if (m == null) return (false, null);
    if (role.counts == DaliIndex.none) return (true, null);
    final n = m.groupCount >= 1 ? int.tryParse(m.group(1) ?? '') : null;
    return n == null ? (false, null) : (true, n);
  }
}

/// Profile of a gateway family: how to recognise it in the project and what its objects mean.
@immutable
class DaliProfile {
  const DaliProfile({
    required this.id,
    required this.name,
    required this.status,
    this.source = const {},
    this.note = const {},
    this.manufacturers = const [],
    this.products = const [],
    this.gearBase = 0,
    this.groupBase = 0,
    this.rules = const [],
    this.faultCodes = const {},
  });

  final String id;
  final String name;
  final DaliProfileStatus status;

  /// The document the profile was built from, by language (`de`, `en`; `''` for one text).
  final Map<String, String> source;

  /// What the profile leaves out or assumes, by language.
  final Map<String, String> note;

  String sourceText(String language) => _pick(source, language);
  String noteText(String language) => _pick(note, language);

  static String _pick(Map<String, String> texts, String language) =>
      texts[language.split('_').first] ?? texts['en'] ?? texts[''] ?? texts.values.firstOrNull ?? '';

  /// A text in one language or several (`{"de": …, "en": …}`).
  static Map<String, String> _texts(Object? v) => switch (v) {
    final String text => {'': text},
    final Map<Object?, Object?> map => {
      for (final MapEntry(:key, :value) in map.entries.take(8))
        if (key is String && value is String && value.length <= 4000) key: value,
    },
    _ => const {},
  };

  /// Parts of the manufacturer's name, lower case; one must occur.
  final List<String> manufacturers;

  /// Parts of the product name, lower case; one must occur.
  final List<String> products;

  /// Number the gateway prints for DALI short address 0 (object texts say "ECG 1" for address 0
  /// on many gateways). Only applies to rules by text; rules by number count from 0.
  final int gearBase;

  /// Number the gateway prints for DALI group 0.
  final int groupBase;
  final List<DaliRule> rules;

  /// Meaning of the values of a [DaliRole.faultCode] object.
  final Map<int, String> faultCodes;

  /// `null` for anything that is no profile.
  static DaliProfile? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final match = json['match'];
    if (id is! String || id.isEmpty || name is! String || match is! Map) return null;
    List<String> parts(Object? v) => [
      if (v is List)
        for (final e in v.take(20))
          if (e is String && e.trim().isNotEmpty) e.trim().toLowerCase(),
    ];
    final products = parts(match['product']);
    final manufacturers = parts(match['manufacturer']);
    // A profile that matches every device would turn every device into a gateway.
    if (products.isEmpty) return null;
    final codes = json['faultCodes'];
    int base(Object? v) => v is int && v >= 0 && v <= 1 ? v : 0;
    return DaliProfile(
      id: id,
      name: name,
      // Anything but an explicit "verified" stays "from documentation".
      status: json['status'] == 'verified' ? DaliProfileStatus.verified : DaliProfileStatus.documented,
      source: _texts(json['source']),
      note: _texts(json['note']),
      manufacturers: manufacturers,
      products: products,
      gearBase: base(json['gearBase']),
      groupBase: base(json['groupBase']),
      rules: [
        if (json['rules'] case final List<Object?> rules)
          for (final r in rules.take(200)) ?DaliRule.fromJson(r),
      ],
      faultCodes: {
        if (codes is Map)
          for (final MapEntry(:key, :value) in codes.entries.take(256))
            if (int.tryParse('$key') case final code? when value is String) code: value,
      },
    );
  }

  /// Whether [device] is a gateway of this family.
  bool matches(DeviceInfo device) {
    final product = '${device.product ?? ''} ${device.name}'.toLowerCase();
    final manufacturer = (device.manufacturer ?? '').toLowerCase();
    return products.any(product.contains) &&
        (manufacturers.isEmpty || manufacturer.isEmpty || manufacturers.any(manufacturer.contains));
  }
}

/// The profiles shipped with the app (`assets/dali_profiles/*.json`).
abstract final class DaliProfiles {
  static const _dir = 'assets/dali_profiles/';

  /// A profile is a few kilobytes; anything much larger is not one.
  static const _maxBytes = 256 * 1024;

  static List<DaliProfile> all = const [];
  static bool _loaded = false;

  /// Reads the profiles once. A profile that cannot be read is skipped.
  static Future<void> load({AssetBundle? bundle}) async {
    if (_loaded) return;
    _loaded = true;
    final assets = bundle ?? rootBundle;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(assets);
      final result = <DaliProfile>[];
      for (final path
          in manifest.listAssets().where((p) => p.startsWith(_dir) && p.endsWith('.json')).toList()..sort()) {
        try {
          final text = await assets.loadString(path, cache: false);
          if (text.length > _maxBytes) continue;
          if (DaliProfile.fromJson(jsonDecode(text)) case final profile?) result.add(profile);
        } on Object catch (e) {
          debugPrint('DALI-Profil $path nicht lesbar: $e');
        }
      }
      all = result;
    } on Object catch (e) {
      debugPrint('DALI-Profile nicht geladen: $e');
    }
  }

  static DaliProfile? byId(String? id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  @visibleForTesting
  static void debugSet(List<DaliProfile> profiles) {
    all = profiles;
    _loaded = true;
  }
}

/// A communication object of a gateway with its meaning.
@immutable
class DaliObject {
  const DaliObject({required this.group, required this.gateway, required this.role, this.index, this.sends = false});

  /// Group address the object is linked to.
  final int group;

  /// Individual address of the gateway.
  final int gateway;
  final DaliRole role;

  /// DALI short address or group (already counted from 0), `null` if the object has none or the
  /// project does not tell.
  final int? index;

  /// The gateway sends on this address according to the project.
  final bool sends;

  Map<String, Object?> toJson() => {'gw': gateway, 'r': role.name, 'i': ?index};
}

/// A gateway as the project knows it.
@immutable
class DaliProjectGateway {
  const DaliProjectGateway({required this.address, this.name, this.location, this.profile});

  final int address;
  final String? name;
  final String? location;
  final DaliProfile? profile;
}

/// The DALI side of the imported project: which devices are gateways and what their objects mean.
///
/// A device counts as a gateway if one of its objects carries DPT 237.600, 238.600, 244.600 or
/// 245.600, or if a profile matches its manufacturer and product. Numbers of control gear and
/// groups come from the profile's rules, otherwise from object texts and group address names
/// ("EVG 12 Lampenfehler", "Gruppe 3 Schalten").
@immutable
class DaliProject {
  const DaliProject({this.gateways = const {}, this.objects = const {}, this.diagnostics = const {}});

  static const empty = DaliProject();

  final Map<int, DaliProjectGateway> gateways;

  /// Group address → object. Diagnostic addresses shared by several gateways are in
  /// [diagnostics]; here they point to the first one.
  final Map<int, DaliObject> objects;

  /// Diagnostic group address → gateways sending on it.
  final Map<int, Set<int>> diagnostics;

  bool get isEmpty => gateways.isEmpty;

  /// Objects of [gateway] with [role].
  Iterable<DaliObject> objectsOf(int gateway, [DaliRole? role]) =>
      objects.values.where((o) => o.gateway == gateway && (role == null || o.role == role));

  static final _gearNumber = RegExp(
    r'(?:\bevg|\becg|ballast|vorschaltger[aä]t|betriebsger[aä]t|notleuchte|notlicht|konverter|converter|emergency|leuchte|luminaire|\blamp|\bteilnehmer)\W{0,3}(\d{1,2})\b',
    caseSensitive: false,
  );
  static final _groupNumber = RegExp(r'(?:gruppe|group|\bgrp)\W{0,3}(\d{1,2})\b|\bG(\d{1,2})\b', caseSensitive: false);
  static final _faultWords = RegExp(
    r'st[oö]rung|stoerung|defekt|fehler|fault|error|failure|ausfall|malfunction',
    caseSensitive: false,
  );
  static final _lampWords = RegExp(r'lampe|leuchtmittel|\blamp', caseSensitive: false);

  /// Builds the DALI side of [catalog]. [dptOf] gives the datapoint type of a group address (with
  /// the types chosen in the app).
  static DaliProject of(GroupCatalog catalog, Dpt? Function(int address) dptOf, {List<DaliProfile>? profiles}) {
    if (catalog.isEmpty) return empty;
    final known = profiles ?? DaliProfiles.all;
    final gateways = <int, DaliProjectGateway>{};
    void addGateway(int pa, [DaliProfile? profile]) {
      final device = catalog.devices[pa];
      if (device != null && device.isTunnel) return;
      gateways[pa] ??= DaliProjectGateway(
        address: pa,
        name: device?.name,
        location: device?.location,
        profile: profile ?? (device == null ? null : known.where((p) => p.matches(device)).firstOrNull),
      );
    }

    for (final device in catalog.devices.values) {
      final profile = known.where((p) => p.matches(device)).firstOrNull;
      if (profile != null) addGateway(device.address, profile);
    }
    for (final g in catalog.groups.values) {
      final dpt = dptOf(g.address);
      if (dpt == null || !isDaliDpt(dpt.main, dpt.sub) || g.links.isEmpty) continue;
      final senders = g.links.where((l) => l.sends).toList();
      for (final l in senders.isEmpty ? g.links : senders) {
        addGateway(l.device);
      }
    }
    if (gateways.isEmpty) return empty;

    // What the objects say, with numbers as the gateway prints them.
    final found = <({GroupInfo info, GroupLink link, DaliRole role, int? printed, bool byNumber})>[];
    for (final g in catalog.groups.values) {
      final dpt = dptOf(g.address);
      for (final l in g.links) {
        final gateway = gateways[l.device];
        if (gateway == null) continue;
        final hit = _roleOf(g, l, dpt, gateway.profile);
        if (hit != null) found.add((info: g, link: l, role: hit.$1, printed: hit.$2, byNumber: hit.$3));
      }
    }

    // Without a profile: texts that print a 0 count from 0, texts that reach 64 (or 16 for
    // groups) count from 1. Anything else is taken as printed.
    int baseOf(int pa, DaliIndex index) {
      final gateway = gateways[pa]!;
      if (gateway.profile case final p?) return index == DaliIndex.gear ? p.gearBase : p.groupBase;
      final numbers = [
        for (final f in found)
          if (f.link.device == pa && f.role.counts == index && !f.byNumber) ?f.printed,
      ];
      if (numbers.contains(0)) return 0;
      return numbers.contains(index == DaliIndex.gear ? 64 : 16) ? 1 : 0;
    }

    final objects = <int, DaliObject>{};
    final diagnostics = <int, Set<int>>{};
    for (final f in found) {
      final pa = f.link.device;
      int? index;
      if (f.role.counts != DaliIndex.none && f.printed != null) {
        index = f.byNumber ? f.printed! : f.printed! - baseOf(pa, f.role.counts);
        final max = f.role.counts == DaliIndex.gear ? 63 : 15;
        if (index < 0 || index > max) continue;
      }
      if (f.role == DaliRole.diagnostic) (diagnostics[f.info.address] ??= {}).add(pa);
      objects.putIfAbsent(
        f.info.address,
        () => DaliObject(group: f.info.address, gateway: pa, role: f.role, index: index, sends: f.link.sends),
      );
    }
    return DaliProject(gateways: gateways, objects: objects, diagnostics: diagnostics);
  }

  /// Role, printed number and whether the number came from the object number.
  static (DaliRole, int?, bool)? _roleOf(GroupInfo g, GroupLink l, Dpt? dpt, DaliProfile? profile) {
    final texts = [l.text, g.name];
    int? printed(RegExp pattern) {
      for (final text in texts) {
        final m = text == null ? null : pattern.firstMatch(text);
        if (m == null) continue;
        for (var i = 1; i <= m.groupCount; i++) {
          if (int.tryParse(m.group(i) ?? '') case final n?) return n;
        }
      }
      return null;
    }

    if (dpt != null && isDaliDpt(dpt.main, dpt.sub)) {
      // A profile may know the converter from the object number; otherwise the text tells.
      if (profile != null && (dpt.main == 244 || dpt.main == 245)) {
        final role = dpt.main == 244 ? DaliRole.emergencyStatus : DaliRole.emergencyResult;
        for (final rule in profile.rules.where((r) => r.role == role && r.first != null)) {
          final (matched, index) = rule.match(l.object, null);
          if (matched) return (role, index, true);
        }
      }
      return switch (dpt.main) {
        244 => (DaliRole.emergencyStatus, printed(_gearNumber), false),
        245 => (DaliRole.emergencyResult, printed(_gearNumber), false),
        _ => (DaliRole.diagnostic, null, false),
      };
    }
    if (profile != null) {
      for (final rule in profile.rules) {
        final byNumber = rule.first != null;
        final (matched, index) = byNumber ? rule.match(l.object, null) : rule.match(null, l.text ?? g.name);
        if (matched) return (rule.role, index, byNumber);
      }
    }
    final text = texts.whereType<String>().join(' ');
    final fault = _faultWords.hasMatch(text);
    if (printed(_gearNumber) case final n?) {
      if (dpt?.main != 1 || !fault) return null;
      return (_lampWords.hasMatch(text) ? DaliRole.lampFault : DaliRole.gearFault, n, false);
    }
    if (printed(_groupNumber) case final n?) {
      return switch (dpt?.main) {
        1 when fault => (DaliRole.groupFault, n, false),
        1 => (l.sends ? DaliRole.groupStatus : DaliRole.groupSwitch, n, false),
        3 => (DaliRole.groupDim, n, false),
        5 => (l.sends ? DaliRole.groupValueStatus : DaliRole.groupValue, n, false),
        _ => null,
      };
    }
    return null;
  }
}
