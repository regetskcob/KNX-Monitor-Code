import '../knx/demo_tunnel.dart';
import '../knx/gateway_info.dart';
import '../knx/group_catalog.dart';
import '../knx/knx_tunnel.dart';
import '../knx/secure/keyring_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';

/// How the app is connected to the bus – from a security perspective.
enum LinkSecurity {
  /// KNX IP Secure (encrypted, with password).
  ipSecure,

  /// Tunneling without encryption (UDP/TCP).
  plainTunnel,

  /// Routing via multicast without encryption.
  plainRouting,

  /// Directly on the bus (the box's KNX HAT) – no IP path.
  direct,

  /// Via Home Assistant – path unknown.
  unknown,

  /// Demo house – no real bus.
  demo;

  /// From the connection type ([KnxTunnel.kind]).
  static LinkSecurity of(KnxTunnel tunnel) {
    if (tunnel is DemoTunnel) return LinkSecurity.demo;
    final kind = tunnel.kind;
    if (kind.contains('IP Secure')) return LinkSecurity.ipSecure;
    if (kind.contains('KNX-HAT')) return LinkSecurity.direct;
    if (kind.contains('Home Assistant')) return LinkSecurity.unknown;
    if (kind.contains('Routing')) return LinkSecurity.plainRouting;
    return LinkSecurity.plainTunnel;
  }
}

/// Weight of a finding. Deliberately without "critical": the check gives
/// recommendations, it does not raise alarms.
enum SecurityLevel { good, info, advice }

class SecurityFinding {
  const SecurityFinding(this.level, this.title, this.text);

  final SecurityLevel level;
  final String title;
  final String text;
}

/// Foreign sender: sends, but is not in the project.
typedef ForeignSender = ({int address, int count, Set<int> groups});

/// Inputs of the security check – separate from the app state, so it can be
/// checked with recordings and in tests.
class SecurityInput {
  const SecurityInput({
    required this.link,
    required this.catalog,
    required this.telegrams,
    this.gateway,
    this.securedGroups = const {},
    this.keyringLoaded = false,
    this.secureWithoutKey = 0,
    this.secureRejected = 0,
    this.ownAddresses = const {},
  });

  /// From the running monitor.
  factory SecurityInput.live(KnxTunnel tunnel, GroupCatalog catalog, List<Telegram> telegrams) {
    final keys = KeyringStore.instance;
    return SecurityInput(
      link: LinkSecurity.of(tunnel),
      catalog: catalog,
      telegrams: telegrams,
      gateway: tunnel.gatewayInfo.value,
      securedGroups: keys.dataSecure?.groupKeys.keys.toSet() ?? const {},
      keyringLoaded: keys.loaded,
      secureWithoutKey: keys.withoutKey.value,
      secureRejected: keys.rejected.value,
      ownAddresses: {?tunnel.tunnelAddress},
    );
  }

  final LinkSecurity link;
  final GroupCatalog catalog;
  final List<Telegram> telegrams;
  final GatewayInfo? gateway;

  /// Group addresses with a Data Secure key (from the keyring).
  final Set<int> securedGroups;
  final bool keyringLoaded;

  /// Data Secure telegrams without a matching key or with an invalid MAC.
  final int secureWithoutKey;
  final int secureRejected;

  /// Own tunnel address(es) – not a foreign sender.
  final Set<int> ownAddresses;
}

/// Security check: connection, Data Secure in the project and in the traffic,
/// foreign senders. The result is calm recommendations in plain language.
class SecurityCheck {
  SecurityCheck._({
    required this.findings,
    required this.gatewaySecure,
    required this.projectGroups,
    required this.projectSecured,
    required this.seenGroups,
    required this.seenSecured,
    required this.foreign,
    required this.keyringLoaded,
  });

  final List<SecurityFinding> findings;

  /// Whether the gateway reports the "Security" service family (null = unknown).
  final bool? gatewaySecure;
  final int projectGroups;
  final int projectSecured;
  final int seenGroups;
  final int seenSecured;
  final List<ForeignSender> foreign;

  /// Without a keyring the Secure shares are unknown, not zero.
  final bool keyringLoaded;

  /// "Security" service family in the gateway's self-description.
  static const _securityFamily = 0x09;

  factory SecurityCheck.of(SecurityInput input) {
    final findings = <SecurityFinding>[];
    final gateway = input.gateway;
    final gatewaySecure = gateway?.services.containsKey(_securityFamily);

    // 1. Connection
    switch (input.link) {
      case LinkSecurity.ipSecure:
        findings.add(SecurityFinding(SecurityLevel.good, s.secLinkSecureTitle, s.secLinkSecureText));
      case LinkSecurity.direct:
        findings.add(SecurityFinding(SecurityLevel.good, s.secLinkDirectTitle, s.secLinkDirectText));
      case LinkSecurity.plainTunnel || LinkSecurity.plainRouting:
        final routing = input.link == LinkSecurity.plainRouting;
        if (gatewaySecure == true) {
          findings.add(
            SecurityFinding(
              SecurityLevel.advice,
              routing ? s.secLinkRoutingCouldTitle : s.secLinkPlainCouldTitle,
              s.secLinkPlainCouldText,
            ),
          );
        } else {
          findings.add(
            SecurityFinding(
              SecurityLevel.info,
              routing ? s.secLinkRoutingTitle : s.secLinkPlainTitle,
              gatewaySecure == false ? s.secLinkPlainNoSecureText : s.secLinkPlainText,
            ),
          );
        }
      case LinkSecurity.unknown:
        findings.add(SecurityFinding(SecurityLevel.info, s.secLinkUnknownTitle, s.secLinkUnknownText));
      case LinkSecurity.demo:
        findings.add(SecurityFinding(SecurityLevel.info, s.secLinkDemoTitle, s.secLinkDemoText));
    }

    // 2. Data Secure in the project and in the traffic
    final groups = input.catalog.groups.keys.toSet();
    final secured = input.securedGroups;
    final projectSecured = groups.where(secured.contains).length;
    final seen = {
      for (final t in input.telegrams)
        if (t.type != TelegramType.read) t.destination,
    };
    final seenSecured = seen.where(secured.contains).length;
    if (!input.keyringLoaded) {
      findings.add(
        SecurityFinding(
          SecurityLevel.info,
          s.secDataNoKeyringTitle,
          input.secureWithoutKey > 0 ? s.secDataNoKeyringSeen(input.secureWithoutKey) : s.secDataNoKeyringText,
        ),
      );
    } else if (secured.isEmpty) {
      findings.add(SecurityFinding(SecurityLevel.info, s.secDataNoneTitle, s.secDataNoneText));
    } else {
      findings.add(
        SecurityFinding(
          SecurityLevel.good,
          s.secDataTitle,
          s.secDataText(projectSecured, groups.length, seenSecured, seen.length),
        ),
      );
    }
    if (input.secureWithoutKey > 0 && input.keyringLoaded) {
      findings.add(
        SecurityFinding(SecurityLevel.advice, s.secWithoutKeyTitle, s.secWithoutKeyText(input.secureWithoutKey)),
      );
    }
    if (input.secureRejected > 0) {
      findings.add(SecurityFinding(SecurityLevel.advice, s.secRejectedTitle, s.secRejectedText(input.secureRejected)));
    }

    // 3. Senders that are not in the project
    final foreign = <int, ({int count, Set<int> groups})>{};
    final devices = input.catalog.devices;
    if (devices.isNotEmpty) {
      for (final t in input.telegrams) {
        if (t.outgoing || input.ownAddresses.contains(t.source) || devices.containsKey(t.source)) continue;
        final f = foreign[t.source] ?? (count: 0, groups: <int>{});
        f.groups.add(t.destination);
        foreign[t.source] = (count: f.count + 1, groups: f.groups);
      }
    }
    final foreignList = [
      for (final MapEntry(key: address, value: f) in foreign.entries)
        (address: address, count: f.count, groups: f.groups),
    ]..sort((a, b) => b.count.compareTo(a.count));
    if (devices.isEmpty) {
      findings.add(SecurityFinding(SecurityLevel.info, s.secForeignNoProjectTitle, s.secForeignNoProjectText));
    } else if (foreignList.isEmpty) {
      findings.add(SecurityFinding(SecurityLevel.good, s.secForeignNoneTitle, s.secForeignNoneText));
    } else {
      findings.add(SecurityFinding(SecurityLevel.advice, s.secForeignTitle(foreignList.length), s.secForeignText));
    }

    return SecurityCheck._(
      findings: findings,
      gatewaySecure: gatewaySecure,
      projectGroups: groups.length,
      projectSecured: projectSecured,
      seenGroups: seen.length,
      seenSecured: seenSecured,
      foreign: foreignList,
      keyringLoaded: input.keyringLoaded,
    );
  }
}
