import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../knx/demo_tunnel.dart';
import 'installation.dart';

/// Lock addresses whose reading the user has turned around (`lock_polarity.json`
/// of the active installation): whether 1 or 0 locks differs between
/// manufacturers and is not in the telegram.
class LockPrefs extends ChangeNotifier {
  LockPrefs._();

  static final instance = LockPrefs._();
  static const path = 'lock_polarity.json';

  Set<int> inverted = {};
  String? _loadedFor;

  Future<void> load() async {
    final id = InstallationStore.instance.active.id;
    if (_loadedFor == id) return;
    _loadedFor = id;
    inverted = {};
    if (!DemoTunnel.active) {
      try {
        final text = await InstallationStore.instance.storage.read(path);
        if (text != null) inverted = {...(jsonDecode(text) as List).whereType<int>()};
      } on Object catch (e) {
        debugPrint('Sperr-Deutung nicht geladen: $e');
      }
    }
    notifyListeners();
  }

  Future<void> toggle(int address) async {
    inverted = {...inverted};
    if (!inverted.remove(address)) inverted.add(address);
    notifyListeners();
    if (DemoTunnel.active) return;
    await InstallationStore.instance.storage.write(path, jsonEncode(inverted.toList()..sort()));
  }

  @visibleForTesting
  void debugReset() {
    inverted = {};
    _loadedFor = null;
  }
}
