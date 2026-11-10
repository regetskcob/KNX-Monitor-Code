import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../knx/gateway_info.dart';
import '../platform/addon.dart';
import '../platform/app_instance.dart';
import '../platform/box_link.dart';
import '../platform/native_bridge.dart';
import 'box_connection.dart';

/// Setup steps, in this order.
enum BoxSetupStep { wifi, reach, pair, time, gateway }

/// State of a step.
enum BoxStepState { waiting, running, done, skipped, manual, failed }

/// Result of the gateway search via the box.
class BoxGateway {
  const BoxGateway(this.host, this.port, this.info);
  final String host;
  final int port;
  final GatewayInfo? info;
}

/// Sets up a Busclear Box from the app, without a browser:
///
/// 1. join the box's Wi-Fi (iOS, Android 10+; otherwise by hand),
/// 2. wait until the box responds,
/// 3. pair with the box password from the sticker (admin access) and, if the
///    box requires it, set a custom password right away ([choosePassword]);
///    until then it allows nothing else,
/// 4. set the box's clock from this device,
/// 5. search for gateways on the box's cable; if there is exactly one, use it.
///
/// With an ordinary pairing link (with access), steps 1 and 3 are skipped.
class BoxSetup extends ChangeNotifier {
  BoxSetup(
    this.link, {
    required this.deviceName,
    Future<String> Function(String ssid, String password)? joinWifi,
    Future<bool> Function(BoxLink link)? reachable,
    this.choosePassword,
    this.reachTimeout = const Duration(seconds: 45),
  }) : _joinWifi = joinWifi ?? NativeBridge.joinWifi,
       _reachable = reachable ?? boxReachable;

  final BoxLink link;
  final String deviceName;
  final Future<String> Function(String ssid, String password) _joinWifi;
  final Future<bool> Function(BoxLink link) _reachable;

  /// Asks for the custom password and sets it; `false` if that fails.
  final Future<bool> Function()? choosePassword;

  /// Error text of the "pair" step if no custom password was set.
  static const passwordMissing = 'password';
  final Duration reachTimeout;

  final states = {for (final s in BoxSetupStep.values) s: BoxStepState.waiting};

  /// Error text of the failed step.
  String? error;

  /// Result of `/api/box/time`: `set`, `ok`, `differs`, `unsupported`.
  String? timeResult;

  /// Gateways found; if there is exactly one, it is already configured.
  List<BoxGateway> gateways = const [];

  /// Configured gateway (set before or just found).
  String? gateway;

  bool get finished => states.values.every((s) => s != BoxStepState.waiting && s != BoxStepState.running);
  bool get failed => states.containsValue(BoxStepState.failed);

  void _set(BoxSetupStep step, BoxStepState state) {
    states[step] = state;
    notifyListeners();
  }

  /// Runs all steps; stops at the first error (the following ones stay
  /// "waiting"). Afterwards the app is switched to the box.
  Future<void> run() async {
    error = null;
    for (final s in BoxSetupStep.values) {
      states[s] = BoxStepState.waiting;
    }
    notifyListeners();
    try {
      await _wifi();
      await _reach();
      await _pair();
      await _time();
      await _gateway();
    } on _Stop {
      // Step is set to "failed", error is set.
    }
  }

  Never _fail(BoxSetupStep step, String message) {
    error = message;
    _set(step, BoxStepState.failed);
    throw const _Stop();
  }

  Future<void> _wifi() async {
    if (link.ssid.isEmpty || link.wifi.isEmpty) return _set(BoxSetupStep.wifi, BoxStepState.skipped);
    _set(BoxSetupStep.wifi, BoxStepState.running);
    final result = await _joinWifi(link.ssid, link.wifi);
    switch (result) {
      case 'joined':
        _set(BoxSetupStep.wifi, BoxStepState.done);
      case 'unsupported':
        // Desktop or older Android: the user joins themselves.
        _set(BoxSetupStep.wifi, BoxStepState.manual);
      case 'denied':
        _fail(BoxSetupStep.wifi, 'denied');
      default:
        _fail(BoxSetupStep.wifi, result);
    }
  }

  Future<void> _reach() async {
    _set(BoxSetupStep.reach, BoxStepState.running);
    final end = DateTime.now().add(reachTimeout);
    // After switching Wi-Fi it takes a few seconds to get an address.
    while (!await _reachable(link)) {
      if (DateTime.now().isAfter(end)) _fail(BoxSetupStep.reach, 'unreachable');
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    _set(BoxSetupStep.reach, BoxStepState.done);
  }

  Future<void> _pair() async {
    if (!link.needsPairing) {
      await BoxConnection.instance.use(link);
      return _set(BoxSetupStep.pair, BoxStepState.skipped);
    }
    _set(BoxSetupStep.pair, BoxStepState.running);
    try {
      final key = await Addon.pairBox(link, link.password, deviceName, app: await AppInstance.id());
      await BoxConnection.instance.use(link.paired(key));
      await _ownPassword();
      _set(BoxSetupStep.pair, BoxStepState.done);
    } on AddonException catch (e) {
      _fail(BoxSetupStep.pair, e.message);
    }
  }

  /// New box: as long as the sticker password is valid, nothing works except changing it.
  Future<void> _ownPassword() async {
    final Map<String, Object?> info;
    try {
      info = await Addon.boxInfo();
    } on AddonException catch (e) {
      if (e.status == HttpStatus.notFound) return; // Older box: not required.
      rethrow; // Unreachable does not mean "not required": pairing fails visibly.
    }
    if (info['passwordChangeRequired'] != true) return;
    final ask = choosePassword;
    if (ask == null || !await ask()) _fail(BoxSetupStep.pair, passwordMissing);
  }

  Future<void> _time() async {
    _set(BoxSetupStep.time, BoxStepState.running);
    try {
      timeResult = (await Addon.offerTime())['result'] as String?;
      _set(BoxSetupStep.time, timeResult == 'unsupported' ? BoxStepState.skipped : BoxStepState.done);
    } on AddonException {
      // Older box without a clock: continue, setup does not depend on it.
      _set(BoxSetupStep.time, BoxStepState.skipped);
    }
  }

  Future<void> _gateway() async {
    _set(BoxSetupStep.gateway, BoxStepState.running);
    try {
      final config = ((await Addon.status())['config'] as Map?)?.cast<String, Object?>() ?? const {};
      final host = config['host'] as String? ?? '';
      if (host.isNotEmpty) {
        gateway = host;
        return _set(BoxSetupStep.gateway, BoxStepState.done);
      }
      gateways = [
        for (final g in (await Addon.discover()).cast<Map<Object?, Object?>>())
          BoxGateway(
            g['host']! as String,
            g['port'] as int? ?? 3671,
            GatewayInfo.parse(Uint8List.fromList(_hex(g['dibs'] as String? ?? ''))),
          ),
      ];
      if (gateways.length == 1) {
        final g = gateways.single;
        await Addon.configure({'enabled': true, 'mode': 'udp', 'host': g.host, 'port': g.port});
        gateway = g.host;
        return _set(BoxSetupStep.gateway, BoxStepState.done);
      }
      // None or several: choose in the connect screen.
      _set(BoxSetupStep.gateway, BoxStepState.manual);
    } on AddonException {
      _set(BoxSetupStep.gateway, BoxStepState.manual);
    }
  }

  static List<int> _hex(String s) => [
    for (var i = 0; i + 1 < s.length; i += 2) int.tryParse(s.substring(i, i + 2), radix: 16) ?? 0,
  ];
}

class _Stop implements Exception {
  const _Stop();
}

/// Whether the box responds. A 401 counts too: it is there, it just wants credentials.
Future<bool> boxReachable(BoxLink link) => Addon.reachable(link);
