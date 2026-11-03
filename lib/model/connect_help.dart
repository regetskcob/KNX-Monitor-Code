import '../knx/gateway_info.dart';
import '../knx/knx_tunnel.dart';
import '../l10n/locale_controller.dart';
import 'connection_options.dart';

/// What the help offers directly as the next step.
enum HelpAction {
  /// Search for gateways on the network (also shows free tunnels).
  scan,

  /// Load the keyring (.knxkeys) from the ETS.
  keyring,

  /// Help with the project file (keyring, password from the electrician).
  projectHelp,

  /// Try it without an installation.
  demo,
}

/// Plain-language explanation of a connection error: what is going on and what
/// helps next.
class ConnectHelp {
  const ConnectHelp(this.title, this.steps, {this.actions = const []});

  final String title;

  /// Next steps, most likely first.
  final List<String> steps;
  final List<HelpAction> actions;
}

/// Help for [problem]; `null` if the cause is unknown. [port] and [mode] make it
/// more specific (unusual port, routing, TCP).
ConnectHelp? connectHelp(ConnectProblem? problem, {required ConnectionMode mode, required int port}) {
  final oddPort = port != 3671;
  return switch (problem) {
    null => null,
    ConnectProblem.noResponse => ConnectHelp(
      s.helpNoResponseTitle,
      [if (oddPort) s.helpOddPort(port), s.helpCheckIp, s.helpSameNetwork, s.helpBusPower],
      actions: const [HelpAction.scan],
    ),
    ConnectProblem.network => ConnectHelp(
      s.helpNetworkTitle,
      [
        s.helpWifiOn,
        s.helpLocalNetworkPermission,
        if (mode == ConnectionMode.tcp || mode == ConnectionMode.secure) s.helpTcpPort(port) else s.helpCheckIp,
      ],
      actions: const [HelpAction.scan],
    ),
    ConnectProblem.noFreeTunnel => ConnectHelp(
      s.helpNoTunnelTitle,
      [s.helpTunnelsHeld, s.helpCloseEts, s.helpScanShowsSlots, s.helpUseRouting],
      actions: const [HelpAction.scan],
    ),
    ConnectProblem.tunnelAddress => ConnectHelp(s.helpTunnelAddressTitle, [s.helpNoFixedAddress]),
    ConnectProblem.unsupported => ConnectHelp(s.helpUnsupportedTitle, [s.helpNotAnInterface, s.helpUseRouting]),
    ConnectProblem.secureAuth => ConnectHelp(
      s.helpSecureAuthTitle,
      [s.helpSecureKeyring, s.helpSecurePasswordInEts, s.helpSecureNotProjectPassword],
      actions: const [HelpAction.keyring, HelpAction.projectHelp],
    ),
    ConnectProblem.secureDevice => ConnectHelp(
      s.helpSecureDeviceTitle,
      [s.helpSecureDeviceCode, s.helpSecureRightDevice],
      actions: const [HelpAction.keyring],
    ),
    ConnectProblem.secureMissing => ConnectHelp(
      s.helpSecureMissingTitle,
      [s.helpSecureKeyring, s.helpAskElectrician],
      actions: const [HelpAction.keyring, HelpAction.projectHelp],
    ),
    ConnectProblem.routing => ConnectHelp(s.helpRoutingTitle, [s.helpRoutingMulticast, s.helpTryTunnel]),
  };
}

/// Help when the gateway search finds nothing. [box]: the box searches on its cable.
ConnectHelp noGatewayHelp({bool box = false}) => ConnectHelp(
  s.helpNoGatewayTitle,
  [if (!box) s.helpSameNetwork, s.helpSearchSilent, s.helpRoutingSearch, s.helpTryDemo],
  actions: const [HelpAction.demo],
);

/// Free tunnels according to the gateway description, e.g. "2 of 4 tunnels
/// free"; `null` if the device reports no tunnels.
String? freeTunnels(GatewayInfo info) {
  if (info.slots.isEmpty) return null;
  return s.helpFreeTunnels(info.slots.where((t) => t.free && t.usable).length, info.slots.length);
}
