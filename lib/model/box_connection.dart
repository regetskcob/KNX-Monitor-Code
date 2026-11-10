import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/addon.dart';
import '../platform/box_link.dart';

/// The paired Busclear Box and whether the app currently runs through it instead of
/// a gateway (native only; in the browser on the box this is the normal case).
///
/// Also receives pairing links that the system passes to the app when the QR
/// code is scanned ([incoming]); the connect screen then asks before pairing.
class BoxConnection extends ChangeNotifier with WidgetsBindingObserver {
  BoxConnection._();

  static final instance = BoxConnection._();

  static const _linkKey = 'box_link';
  static const _activeKey = 'box_active';

  /// Pairing with device access and Wi-Fi password: in the keychain, only on this
  /// device (like the keyring).
  static const _vault = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      usesDataProtectionKeychain: false,
    ),
  );

  static Future<String?> _readVault() async {
    try {
      return await _vault.read(key: _linkKey);
    } on Object {
      return null;
    }
  }

  /// Most recently paired box (for reconnecting).
  BoxLink? saved;

  /// Whether the app talks to [saved] instead of a gateway.
  bool get active => Addon.box != null;

  /// Freshly opened pairing link, not yet confirmed.
  final incoming = ValueNotifier<BoxLink?>(null);

  bool _listening = false;

  /// Counts [use], [leave] and [forget] so a running [load] notices them.
  int _changes = 0;

  /// Call before `runApp` so links arrive before the navigator (which would
  /// otherwise interpret them as a route).
  void listen() {
    if (_listening) return;
    _listening = true;
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    final initial = BoxLink.parse(binding.platformDispatcher.defaultRouteName);
    if (initial != null) incoming.value = initial;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    // Older versions stored the link in the settings.
    final legacy = prefs.getString(_linkKey);
    if (legacy != null) {
      await _vault.write(key: _linkKey, value: legacy);
      await prefs.remove(_linkKey);
    }
    final changes = _changes;
    final stored = BoxLink.parse(await _readVault() ?? '');
    // The keychain can take seconds at startup. The old state must not overwrite
    // a pairing made in the meantime.
    if (changes != _changes) return;
    saved = stored;
    Addon.box = saved != null && (prefs.getBool(_activeKey) ?? false) ? saved : null;
    notifyListeners();
  }

  /// Pairs [link] and switches to box mode.
  Future<void> use(BoxLink link) async {
    _changes++;
    saved = link;
    Addon.box = link;
    await _vault.write(key: _linkKey, value: '${link.toUri()}');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_activeKey, true);
    notifyListeners();
  }

  /// Back to the direct connection with the gateway; the pairing remains.
  Future<void> leave() async {
    _changes++;
    Addon.box = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_activeKey, false);
    notifyListeners();
  }

  /// Deletes the pairing.
  Future<void> forget() async {
    _changes++;
    saved = null;
    Addon.box = null;
    await _vault.delete(key: _linkKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeKey);
    notifyListeners();
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async {
    final link = BoxLink.parse('${routeInformation.uri}');
    if (link == null) return false;
    incoming.value = link;
    return true;
  }
}
