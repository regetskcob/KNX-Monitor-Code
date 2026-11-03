import 'package:flutter/foundation.dart';

import '../platform/addon.dart';
import 'box_keyring_consent.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../knx/knx_tunnel.dart';
import '../knx/routing_tunnel.dart';
import '../knx/secure/keyring_store.dart';
import '../knx/secure_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import 'installation.dart';

/// Kind of connection to the bus.
enum ConnectionMode {
  /// Tunneling over UDP (default, any IP interface).
  udp,

  /// Tunneling over TCP (KNXnet/IP 2.0) – more robust against Wi-Fi dropouts.
  tcp,

  /// Routing via multicast – does not occupy a tunnel slot.
  routing,

  /// Tunneling over IP Secure (TCP, encrypted).
  secure,

  /// Add-on only: telegrams from the Home Assistant KNX integration, no tunnel of
  /// its own.
  homeAssistant,

  /// Only via the KNX box: an attached KNX HAT (kBerry), no gateway.
  hat,
}

/// Connection settings (expert mode): kind, fixed tunnel address, routing
/// sender, credentials for IP Secure.
class ConnectionOptions extends ChangeNotifier {
  ConnectionOptions._();

  static final instance = ConnectionOptions._();

  ConnectionMode mode = ConnectionMode.udp;

  /// Requested tunnel address, `null` = any free slot.
  int? tunnelAddress;

  /// Sender address for routing.
  int routingAddress = 0x00FE; // 0.0.254

  /// IP Secure: user ID of the tunnel (2 … 127) and passwords from the ETS.
  int secureUserId = 2;
  String secureUserPassword = '';
  String secureDeviceAuthentication = '';

  /// KNX HAT: own address (`null` = the module's) and bus monitor instead of the
  /// link layer.
  int? hatAddress;
  bool hatBusmonitor = false;

  static const _modeKey = 'conn_mode';
  static const _tunnelKey = 'conn_tunnel_address';
  static const _routingKey = 'conn_routing_address';
  static const _userIdKey = 'conn_secure_user';
  static const _hatAddressKey = 'conn_hat_address';
  static const _hatBusmonitorKey = 'conn_hat_busmonitor';

  /// Settings of the active installation.
  static String _k(String key) => InstallationStore.instance.key(key);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    // Passwords in memory only: they belong to the previous installation.
    secureUserPassword = '';
    secureDeviceAuthentication = '';
    mode = ConnectionMode.values.asNameMap()[prefs.getString(_k(_modeKey))] ?? ConnectionMode.udp;
    tunnelAddress = prefs.getInt(_k(_tunnelKey));
    routingAddress = prefs.getInt(_k(_routingKey)) ?? 0x00FE;
    secureUserId = prefs.getInt(_k(_userIdKey)) ?? 2;
    hatAddress = prefs.getInt(_k(_hatAddressKey));
    hatBusmonitor = prefs.getBool(_k(_hatBusmonitorKey)) ?? false;
    notifyListeners();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(_modeKey), mode.name);
    if (tunnelAddress == null) {
      await prefs.remove(_k(_tunnelKey));
    } else {
      await prefs.setInt(_k(_tunnelKey), tunnelAddress!);
    }
    await prefs.setInt(_k(_routingKey), routingAddress);
    await prefs.setInt(_k(_userIdKey), secureUserId);
    if (hatAddress == null) {
      await prefs.remove(_k(_hatAddressKey));
    } else {
      await prefs.setInt(_k(_hatAddressKey), hatAddress!);
    }
    await prefs.setBool(_k(_hatBusmonitorKey), hatBusmonitor);
    notifyListeners();
  }

  /// Settings for the add-on server (`/api/bus`).
  Map<String, Object?> toAddon({required String host, required int port, bool keyringAllowed = true}) => {
    'enabled': true,
    'mode': mode == ConnectionMode.homeAssistant ? 'ha' : mode.name,
    'host': host,
    'port': port,
    'tunnelAddress': tunnelAddress == null ? null : formatIndividual(tunnelAddress!),
    'routingAddress': formatIndividual(routingAddress),
    'language': LocaleController.instance.locale.languageCode,
    if (mode == ConnectionMode.hat) ...{
      'hatAddress': hatAddress == null ? null : formatIndividual(hatAddress!),
      'hatBusmonitor': hatBusmonitor,
    },
    if (mode == ConnectionMode.secure)
      'secure': {
        // Without consent, no user ID either: the box keeps what it has.
        if (keyringAllowed || secureUserPassword.isNotEmpty)
          'userId': _addonCredentials(keyringAllowed)?.userId ?? secureUserId,
        // Empty = keep the password stored on the server.
        'userPassword': _addonCredentials(keyringAllowed)?.password ?? '',
        'deviceAuthentication': _addonCredentials(keyringAllowed)?.deviceAuthentication ?? '',
      },
  };

  /// Like [toAddon], but on a box first asks whether anything from the keyring may go there.
  Future<Map<String, Object?>> toAddonAsked({required String host, required int port}) async {
    final box = Addon.box;
    final fromKeyring = mode == ConnectionMode.secure && secureUserPassword.isEmpty;
    final allowed = box == null || !fromKeyring || await BoxKeyringConsent.allowed(box);
    return toAddon(host: host, port: port, keyringAllowed: allowed);
  }

  /// Data entered by the user is always sent; data from the keyring only with consent.
  ({int userId, String password, String? deviceAuthentication})? _addonCredentials(bool keyringAllowed) =>
      keyringAllowed || secureUserPassword.isNotEmpty ? secureCredentials() : null;

  /// Credentials: entered or from the keyring (matching the tunnel address).
  ({int userId, String password, String? deviceAuthentication})? secureCredentials() {
    if (secureUserPassword.isNotEmpty) {
      return (
        userId: secureUserId,
        password: secureUserPassword,
        deviceAuthentication: secureDeviceAuthentication.isEmpty ? null : secureDeviceAuthentication,
      );
    }
    final keys = KeyringStore.instance;
    final tunnel = keys.tunnelFor(address: tunnelAddress) ?? keys.tunnelFor();
    if (tunnel == null || tunnel.userId == null || tunnel.password == null) return null;
    return (
      userId: tunnel.userId!,
      password: tunnel.password!,
      deviceAuthentication: secureDeviceAuthentication.isNotEmpty
          ? secureDeviceAuthentication
          : keys.deviceAuthentication[tunnel.host],
    );
  }

  KnxTunnel _secure(String host, int port) {
    final c = secureCredentials();
    if (c == null) throw KnxException(s.secureNoCredentials, ConnectProblem.secureMissing);
    return SecureTunnel(
      host,
      port: port,
      requestedAddress: tunnelAddress,
      userId: c.userId,
      userPassword: c.password,
      deviceAuthentication: c.deviceAuthentication,
    );
  }

  /// Builds the matching connection (native).
  KnxTunnel create(String host, int port) => switch (mode) {
    ConnectionMode.routing => RoutingTunnel(address: routingAddress),
    ConnectionMode.secure => _secure(host, port),
    ConnectionMode.homeAssistant => throw KnxException(s.connectModeHaAddonOnly),
    ConnectionMode.hat => throw KnxException(s.connectModeHatBoxOnly),
    _ => KnxTunnel(host, port: port, tcp: mode == ConnectionMode.tcp, requestedAddress: tunnelAddress),
  };
}
