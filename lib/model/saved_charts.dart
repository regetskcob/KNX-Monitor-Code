import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../catalog_store.dart';
import '../knx/dpt_codec.dart';
import '../knx/telegram.dart';
import '../platform/addon.dart';
import 'bus_metrics.dart';
import 'installation.dart';
import 'box_keyring_consent.dart';
import 'plan.dart';

/// Named charts (name → group addresses) per installation: stored under the ETS
/// project, without a project under the gateway – 1/2/3 means something
/// different in every installation. Appear on the dashboard and under
/// "Diagramme" (charts).
///
/// In the add-on or on the box they are additionally stored on the server as
/// [serverPath]: the same for all browsers and for the dashboard card in Home
/// Assistant (`knx-monitor-chart-card`), including name, DPT, unit and switch
/// labels per address – the server does not know the language.
class SavedCharts extends ChangeNotifier {
  SavedCharts._();

  static final instance = SavedCharts._();

  /// Charts for the server and dashboard card, next to the installation's project.
  static const serverPath = 'charts.json';

  String? _shared;
  bool _following = false;

  /// Formerly one shared key for all installations; taken over into an
  /// installation the first time it is opened.
  static const _legacyKey = 'chart_selections';

  String _scope = '';
  String? _installation;
  String get _key => InstallationStore.instance.key('charts:$_scope');

  /// At most this many series per chart.
  static const maxSeries = 8;

  final _charts = <String, List<int>>{};
  bool _loaded = false;

  Map<String, List<int>> get charts => Map.unmodifiable(_charts);
  bool get isEmpty => _charts.isEmpty;

  /// Switches the installation (ETS project or gateway) and loads its charts.
  Future<void> useScope(String scope) async {
    final installation = InstallationStore.instance.active.id;
    if (_loaded && scope == _scope && installation == _installation) return;
    _scope = scope;
    _installation = installation;
    _loaded = false;
    _charts.clear();
    await load();
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    _shared = null;
    final prefs = await SharedPreferences.getInstance();
    // In the add-on the server's charts apply – the same for all browsers.
    if (await _loadShared(prefs)) {
      notifyListeners();
      _follow();
      return;
    }
    var json = prefs.getString(_key);
    final legacy = prefs.getString(_legacyKey);
    if (json == null && legacy != null) {
      json = legacy;
      await prefs.setString(_key, legacy);
      await prefs.remove(_legacyKey);
    }
    try {
      final raw = jsonDecode(json ?? '{}') as Map<String, Object?>;
      for (final MapEntry(:key, :value) in raw.entries) {
        _charts[key] = [for (final v in value! as List) v as int];
      }
    } on Object {
      // broken → empty
    }
    notifyListeners();
    _follow();
    unawaited(share().catchError((Object e) => debugPrint('Diagramme: $e')));
  }

  /// Takes over the charts from the add-on if they belong to this installation.
  Future<bool> _loadShared(SharedPreferences prefs) async {
    if (!Addon.embedded) return false;
    try {
      final text = await InstallationStore.instance.storage.read(serverPath);
      if (text == null) return false;
      final json = jsonDecode(text) as Map<String, Object?>;
      if (json['scope'] != _scope) return false;
      for (final c in json['charts'] as List? ?? const []) {
        final chart = (c as Map).cast<String, Object?>();
        _charts[chart['name']! as String] = [
          for (final sr in chart['series'] as List? ?? const []) (sr as Map)['address']! as int,
        ];
      }
      _shared = text;
      await prefs.setString(_key, jsonEncode(_charts));
      return true;
    } on Object catch (e) {
      debugPrint('Diagramme im Add-on nicht lesbar: $e');
      return false;
    }
  }

  Future<void> _store() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_charts));
    await share();
  }

  /// The project (names, types) and the tier determine what the card shows.
  void _follow() {
    if (_following || !Addon.available) return;
    _following = true;
    void again() => unawaited(share().catchError((Object e) => debugPrint('Diagramme: $e')));
    CatalogStore.instance.addListener(again);
    Plan.instance.addListener(again);
  }

  /// Content of [serverPath]: per chart the series with everything the card needs
  /// for labeling.
  @visibleForTesting
  Map<String, Object?> serverJson() => {
    'scope': _scope,
    'allowed': Plan.instance.allows(Feature.charts),
    'charts': [
      for (final MapEntry(key: name, value: addresses) in _charts.entries)
        {
          'name': name,
          'series': [for (final a in addresses) _seriesJson(a)],
        },
    ],
  };

  static Map<String, Object?> _seriesJson(int address) {
    // Metric: the server computes it from the history (`metric`, for lines `line`).
    if (BusMetric.of(address) case final m?) {
      return {
        'address': address,
        'label': m.line == null ? m.key : BusMetric.lineLabel(m.line!),
        'name': m.name,
        'metric': m.key,
        'line': ?m.line,
        'unit': m.unit,
      };
    }
    final catalog = CatalogStore.instance;
    final dpt = catalog.dptOf(address);
    final name = catalog.info(address)?.name;
    final unit = dpt == null ? '' : dptUnit(dpt);
    final (off, on) = dpt1Labels(dpt?.sub);
    return {
      'address': address,
      'label': formatGroup(address),
      if (name != null && name.isNotEmpty) 'name': name,
      if (dpt != null) 'dpt': [dpt.main, ?dpt.sub],
      if (unit.isNotEmpty) 'unit': unit,
      'off': off,
      'on': on,
    };
  }

  /// Stores the charts on the add-on or box (see [serverPath]).
  Future<void> share() async {
    if (!_loaded || !Addon.available) return;
    final text = jsonEncode(serverJson());
    if (text == _shared) return;
    if (Addon.box case final box?) {
      // A box paired through a foreign link gets nothing before the user agreed.
      if (!await BoxProjectConsent.allowed(box)) return;
      await Addon.putFile(serverPath, utf8.encode(text));
    } else {
      await InstallationStore.instance.storage.write(serverPath, text);
    }
    // Only after writing: if it fails, the next occasion tries again.
    _shared = text;
  }

  /// Free name: [base], otherwise "[base] 2", "[base] 3" …
  String uniqueName(String base) {
    if (!_charts.containsKey(base)) return base;
    for (var i = 2; ; i++) {
      if (!_charts.containsKey('$base $i')) return '$base $i';
    }
  }

  /// Creates [name] or replaces its addresses; with [from], renames (the
  /// position stays).
  Future<void> put(String name, List<int> addresses, {String? from}) async {
    final list = addresses.take(maxSeries).toList();
    if (from != null && from != name && _charts.containsKey(from)) {
      final entries = _charts.entries.toList();
      _charts
        ..clear()
        ..addEntries([
          for (final e in entries)
            if (e.key == from) MapEntry(name, list) else if (e.key != name) e,
        ]);
    } else {
      _charts[name] = list;
    }
    notifyListeners();
    await _store();
  }

  Future<void> remove(String name) async {
    if (_charts.remove(name) == null) return;
    notifyListeners();
    await _store();
  }

  @visibleForTesting
  void reset() {
    _charts.clear();
    _loaded = false;
    _scope = '';
    _shared = null;
  }
}
