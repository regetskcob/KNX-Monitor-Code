import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../knx/group_catalog.dart';
import 'bus_metrics.dart';
import 'chart_templates.dart';

/// Custom template for sharing: roles instead of addresses ("actual
/// temperature, setpoint, control value per room"), plus metrics ([BusMetric]).
/// Created from a saved chart ([ruleFromChart]), shared as a JSON file and
/// applied to another installation's project ([applyRule]).
class TemplateRule {
  const TemplateRule({required this.name, required this.series, this.perRoom = false});

  /// Identifier in the JSON, so foreign files stand out immediately.
  static const format = 'knx-monitor-chart-template';

  final String name;
  final List<RuleSeries> series;

  /// Apply per room (all series were in the same room), otherwise once for the house.
  final bool perRoom;

  Map<String, Object?> toJson() => {
    'format': format,
    'version': 1,
    'name': name,
    'perRoom': perRoom,
    'series': [for (final s in series) s.toJson()],
  };

  /// Reads a template; [FormatException] if it is not one.
  factory TemplateRule.fromJson(Object? json) {
    if (json is! Map || json['format'] != format) throw const FormatException('not a chart template');
    final name = json['name'];
    final list = json['series'];
    if (name is! String || name.trim().isEmpty || list is! List) throw const FormatException('incomplete');
    final series = [
      for (final s in list)
        if (s is Map) ?RuleSeries.fromJson(s),
    ];
    if (series.isEmpty) throw const FormatException('no series');
    return TemplateRule(name: name.trim(), series: series, perRoom: json['perRoom'] == true);
  }
}

/// A series of a template: role (name from the recipes) or metric id.
class RuleSeries {
  const RuleSeries.role(String this.role) : metric = null;
  const RuleSeries.metric(int this.metric) : role = null;

  final String? role;
  final int? metric;

  Map<String, Object?> toJson() => {'role': ?role, 'metric': ?metric};

  static RuleSeries? fromJson(Map<Object?, Object?> j) => switch ((j['role'], j['metric'])) {
    (final String role, _) => RuleSeries.role(role),
    (_, final int metric) when BusMetric.of(metric) != null => RuleSeries.metric(metric),
    _ => null,
  };
}

/// Template from chart [name] with [ids]; [dropped] series without a
/// recognizable role stay out. If all roles were in one room, it applies per
/// room and the room is removed from the name ("Raumklima · EG KÜ" →
/// "Raumklima").
({TemplateRule? rule, int dropped}) ruleFromChart(
  String name,
  List<int> ids,
  Map<int, GroupInfo> groups,
  Map<int, DeviceInfo> devices, {
  required Dpt? Function(int address) dptOf,
}) {
  final series = <RuleSeries>[];
  final places = <String>{};
  var dropped = 0;
  for (final id in ids) {
    if (BusMetric.of(id) != null) {
      series.add(RuleSeries.metric(id));
      continue;
    }
    final g = groups[id];
    final role = g == null ? null : chartRoleOf(g, dptOf(id));
    if (g == null || role == null) {
      dropped++;
      continue;
    }
    series.add(RuleSeries.role(role));
    places.add(chartPlaceOf(g, devices));
  }
  if (series.isEmpty) return (rule: null, dropped: dropped);
  final room = places.length == 1 && places.single.isNotEmpty ? places.single : null;
  var title = name;
  if (room != null) {
    title = name.replaceAll(room, '').replaceAll(RegExp(r'^[\s·\-–:]+|[\s·\-–:]+$'), '').trim();
    if (title.isEmpty) title = name;
  }
  return (rule: TemplateRule(name: title, series: series, perRoom: room != null), dropped: dropped);
}

/// Applies [rule] to a project: per room (or once) the matching addresses in
/// the template's order. A room counts from two hits (or all of them, if the
/// template has only one series).
List<({String place, List<int> ids})> applyRule(
  TemplateRule rule,
  Map<int, GroupInfo> groups,
  Map<int, DeviceInfo> devices, {
  required Dpt? Function(int address) dptOf,
}) {
  final byRole = <String, List<(int, String)>>{};
  for (final g in groups.values.toList()..sort((a, b) => a.address.compareTo(b.address))) {
    final role = chartRoleOf(g, dptOf(g.address));
    if (role != null) (byRole[role] ??= []).add((g.address, chartPlaceOf(g, devices)));
  }
  // Per template series, the first still unused address with this role in the room.
  List<int> fill(bool Function(String place) inRoom) {
    final ids = <int>[];
    for (final s in rule.series) {
      if (s.metric case final m?) {
        ids.add(m);
        continue;
      }
      for (final (a, p) in byRole[s.role] ?? const <(int, String)>[]) {
        if (inRoom(p) && !ids.contains(a)) {
          ids.add(a);
          break;
        }
      }
    }
    return ids;
  }

  final need = rule.series.length < 2 ? rule.series.length : 2;
  if (!rule.perRoom) {
    final ids = fill((_) => true);
    return ids.length >= need ? [(place: '', ids: ids)] : const [];
  }
  final roles = {for (final s in rule.series) ?s.role};
  final rooms = {
    for (final r in roles)
      for (final (_, p) in byRole[r] ?? const <(int, String)>[])
        if (p.isNotEmpty) p,
  };
  final out = <({String place, List<int> ids})>[];
  for (final room in rooms.toList()..sort()) {
    final ids = fill((p) => chartPlaceWithin(p, room));
    if (ids.where((id) => id >= 0).length >= need) out.add((place: room, ids: ids));
  }
  return out;
}

/// Imported custom templates, on this device for all installations.
class CustomTemplates extends ChangeNotifier {
  CustomTemplates._();

  static final instance = CustomTemplates._();
  static const _key = 'chart_template_rules';

  final _rules = <TemplateRule>[];
  Future<void>? _loading;

  List<TemplateRule> get rules => List.unmodifiable(_rules);

  /// Reads the saved templates once; [add] and [remove] wait for it.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      for (final j in jsonDecode(prefs.getString(_key) ?? '[]') as List) {
        _rules.add(TemplateRule.fromJson(j));
      }
    } on Object catch (e) {
      debugPrint('Eigene Vorlagen nicht lesbar: $e');
    }
    notifyListeners();
  }

  /// Adds [rule]; one with the same name is replaced.
  Future<void> add(TemplateRule rule) async {
    await load();
    _rules
      ..removeWhere((r) => r.name == rule.name)
      ..add(rule);
    notifyListeners();
    await _store();
  }

  Future<void> remove(String name) async {
    await load();
    _rules.removeWhere((r) => r.name == name);
    notifyListeners();
    await _store();
  }

  Future<void> _store() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode([for (final r in _rules) r.toJson()]));
  }

  @visibleForTesting
  void reset() {
    _rules.clear();
    _loading = null;
  }
}
