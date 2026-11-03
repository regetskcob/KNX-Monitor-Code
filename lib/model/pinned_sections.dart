import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'installation.dart';

/// Sections of the overview and rooms of the objects view pinned to the top, in
/// pinning order. Identifiers: section ID ("type:datetime", "main:8") or
/// "room:" + room name.
class PinnedSections extends ChangeNotifier {
  PinnedSections._();

  static final instance = PinnedSections._();
  static const _key = 'pinned_sections';

  List<String> _ids = [];
  bool _loaded = false;

  List<String> get ids => List.unmodifiable(_ids);
  bool contains(String id) => _ids.contains(id);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    _ids = prefs.getStringList(InstallationStore.instance.key(_key)) ?? [];
    notifyListeners();
  }

  /// After switching the installation.
  Future<void> reload() async {
    _loaded = false;
    await load();
  }

  Future<void> toggle(String id) async {
    _ids = contains(id) ? (_ids..remove(id)) : [..._ids, id];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(InstallationStore.instance.key(_key), _ids);
  }

  /// Group addresses pinned as favorites (identifier "ga:" + address).
  Set<int> get favorites => {
    for (final id in _ids)
      if (id.startsWith('ga:')) ?int.tryParse(id.substring(3)),
  };

  bool isFavorite(int address) => contains('ga:$address');
  Future<void> toggleFavorite(int address) => toggle('ga:$address');

  /// [ids] with pinned ones first (in pinning order), the rest unchanged.
  List<String> order(List<String> ids) {
    final present = ids.toSet();
    return [
      for (final id in _ids)
        if (present.contains(id)) id,
      for (final id in ids)
        if (!_ids.contains(id)) id,
    ];
  }
}

/// Collapsed sections of the overview and rooms of the objects view (same
/// identifiers as [PinnedSections]).
class CollapsedSections extends ChangeNotifier {
  CollapsedSections._();

  static final instance = CollapsedSections._();
  static const _key = 'collapsed_sections_v2'; // v2: language-independent identifiers

  Set<String> _ids = {};
  bool _loaded = false;

  bool contains(String id) => _ids.contains(id);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    _ids = (prefs.getStringList(InstallationStore.instance.key(_key)) ?? const []).toSet();
    notifyListeners();
  }

  /// After switching the installation.
  Future<void> reload() async {
    _loaded = false;
    await load();
  }

  Future<void> toggle(String id) async {
    _ids = contains(id) ? (_ids..remove(id)) : {..._ids, id};
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(InstallationStore.instance.key(_key), _ids.toList());
  }
}
