import '../catalog_store.dart';
import '../knx/group_catalog.dart';
import '../knx/telegram.dart';
import 'analysis.dart';
import 'commissioning.dart' show isStatusGroup;
import 'telegram_log.dart';

/// Group address that occurs on the bus but is not in the project.
class UnknownAddress {
  UnknownAddress(this.address);
  final int address;
  int count = 0;
  final senders = <int>{};
  Telegram? last;
}

/// Sender that is not assigned to any device in the project.
class UnknownDevice {
  UnknownDevice(this.address);
  final int address;
  int count = 0;
  final groups = <int>{};
}

/// Address whose data length does not match the DPT in the project.
class SizeMismatch {
  SizeMismatch(this.address, this.dpt, this.expected);
  final int address;
  final Dpt dpt;

  /// Expected length in bytes; 0 = value in the APCI (≤ 6 bits).
  final int expected;
  final seen = <int>{};
  int count = 0;
}

/// Compares the observed bus traffic with the imported ETS project.
class ProjectCheck {
  ProjectCheck._(
    this.unknownAddresses,
    this.unknownDevices,
    this.sizeMismatches,
    this.neverSeen,
    this.total, {
    this.centralOffOn = const [],
  });

  factory ProjectCheck.of(TelegramLog log) {
    final catalog = CatalogStore.instance.catalog;
    final unknownAddresses = <int, UnknownAddress>{};
    final unknownDevices = <int, UnknownDevice>{};
    final mismatches = <int, SizeMismatch>{};
    final centralOffOn = <int, int>{};
    final seen = <int>{};
    final checkDevices = catalog.devices.isNotEmpty;

    for (final t in log.log) {
      seen.add(t.destination);
      final info = catalog[t.destination];
      if (info == null) {
        final u = unknownAddresses.putIfAbsent(t.destination, () => UnknownAddress(t.destination));
        u.count++;
        if (!t.outgoing) u.senders.add(t.source);
        u.last = t;
      } else if (isCentralOffOn(t, info)) {
        centralOffOn[t.destination] = (centralOffOn[t.destination] ?? 0) + 1;
      } else if (info.dpt case final dpt? when t.type != TelegramType.read) {
        final expected = expectedSize(dpt);
        final actual = t.isSmall ? 0 : t.data.length;
        if (expected != null && expected != actual) {
          final m = mismatches.putIfAbsent(t.destination, () => SizeMismatch(t.destination, dpt, expected));
          m.count++;
          m.seen.add(actual);
        }
      }
      if (checkDevices && !t.outgoing && catalog.devices[t.source] == null) {
        final d = unknownDevices.putIfAbsent(t.source, () => UnknownDevice(t.source));
        d.count++;
        d.groups.add(t.destination);
      }
    }

    int byCount<T>(T a, T b, int Function(T) count) => count(b).compareTo(count(a));
    return ProjectCheck._(
      unknownAddresses.values.toList()..sort((a, b) => byCount(a, b, (x) => x.count)),
      unknownDevices.values.toList()..sort((a, b) => byCount(a, b, (x) => x.count)),
      mismatches.values.toList()..sort((a, b) => a.address.compareTo(b.address)),
      [
        for (final ga in catalog.groups.keys)
          if (!seen.contains(ga)) ga,
      ]..sort(),
      log.log.length,
      centralOffOn: [for (final e in centralOffOn.entries) (address: e.key, count: e.value)]
        ..sort((a, b) => a.address.compareTo(b.address)),
    );
  }

  final List<UnknownAddress> unknownAddresses;
  final List<UnknownDevice> unknownDevices;
  final List<SizeMismatch> sizeMismatches;

  /// Project addresses that never appeared on the bus during the observation period.
  final List<int> neverSeen;

  /// Number of evaluated telegrams.
  final int total;

  /// Central-off addresses (by name) that received a 1.
  final List<({int address, int count})> centralOffOn;
}

/// Checks on the ETS project itself, without bus traffic: flags of the
/// communication objects and associations. Flag checks only on addresses whose
/// objects all have known flags.
class ProjectLint {
  ProjectLint._({
    required this.hasFlags,
    required this.statusWithoutTransmit,
    required this.multipleSenders,
    required this.readWithoutReadFlag,
    required this.devicesWithoutLinks,
    required this.devicesNeverProgrammed,
    required this.devicesPendingDownload,
    required this.objectsWithoutCommunication,
    required this.multipleReadAnswers,
    required this.withoutSender,
    required this.withoutReceiver,
    required this.crowdedLines,
    required this.unfilteredMainGroups,
    required this.incomplete,
  });

  /// From this many devices on, a line has no reserve left (rule of thumb: keep
  /// about 20 % of 64 devices per segment free).
  static const lineReserveLimit = 50;

  factory ProjectLint.of(GroupCatalog catalog) {
    final statusWithoutTransmit = <GroupInfo>[];
    final multipleSenders = <GroupInfo>[];
    final readWithoutReadFlag = <GroupInfo>[];
    final withoutCommunication = <(GroupInfo, GroupLink)>[];
    final multipleReadAnswers = <GroupInfo>[];
    final withoutSender = <GroupInfo>[];
    final withoutReceiver = <GroupInfo>[];
    final incomplete = <({GroupInfo group, bool noName, bool noDpt})>[];
    final unlinked = <GroupInfo>[];
    final linked = <int>{};
    var hasFlags = false;
    final sorted = catalog.groups.values.toList()..sort((a, b) => a.address.compareTo(b.address));
    for (final g in sorted) {
      final noName = isDefaultGroupName(g);
      if (noName || g.dpt == null) incomplete.add((group: g, noName: noName, noDpt: g.dpt == null));
      for (final l in g.links) {
        linked.add(l.device);
        if (l.flags case final f? when !f.communication) withoutCommunication.add((g, l));
      }
      if (g.links.isEmpty) {
        // Without any association: has no effect. Only report at the end, once it is
        // certain that the project knows associations with flags (otherwise, with CSV,
        // every address would be "without receiver").
        if (!isStatusGroup(g)) unlinked.add(g);
        continue;
      }
      if (g.links.any((l) => l.flags == null)) continue;
      hasFlags = true;
      // With flags, [GroupLink.sends] means: first address, C + T, no input (W + U).
      final senders = g.links.where((l) => l.sends).length;
      if (senders > 1) multipleSenders.add(g);
      // Several objects with C + R all respond to a read request.
      if (g.links.where((l) => l.flags!.answersReads).length > 1) multipleReadAnswers.add(g);
      if (!isStatusGroup(g)) {
        // Status feedback has its own checks; there "no receiver" is common (only a
        // visualization or push-button LED outside the project).
        // Written from outside the project (Home Assistant): it has a sender.
        if (senders == 0 && !catalog.externalSenders.contains(g.address)) withoutSender.add(g);
        if (!g.links.any((l) => l.flags!.communication && l.flags!.write)) withoutReceiver.add(g);
        continue;
      }
      if (senders == 0) statusWithoutTransmit.add(g);
      if (!g.links.any((l) => l.flags!.answersReads)) readWithoutReadFlag.add(g);
    }

    if (hasFlags) {
      withoutReceiver
        ..addAll(unlinked)
        ..sort((a, b) => a.address.compareTo(b.address));
    }

    // Devices per line (area.line); tunnels and couplers do not count.
    final perLine = <int, int>{};
    for (final d in catalog.devices.values) {
      if (d.isTunnel || d.address & 0xFF == 0) continue;
      perLine[d.address >> 8] = (perLine[d.address >> 8] ?? 0) + 1;
    }
    return ProjectLint._(
      hasFlags: hasFlags,
      statusWithoutTransmit: statusWithoutTransmit,
      multipleSenders: multipleSenders,
      readWithoutReadFlag: readWithoutReadFlag,
      // Tunnels are not devices, couplers (device 0) have no objects.
      devicesWithoutLinks: [
        for (final d in catalog.devices.values)
          if (!d.isTunnel && d.address & 0xFF != 0 && !linked.contains(d.address)) d,
      ]..sort((a, b) => a.address.compareTo(b.address)),
      devicesNeverProgrammed: [
        for (final d in catalog.devices.values)
          if (d.neverProgrammed && !d.isTunnel) d,
      ]..sort((a, b) => a.address.compareTo(b.address)),
      devicesPendingDownload: [
        for (final d in catalog.devices.values)
          if (d.pendingDownload.isNotEmpty && !d.isTunnel) d,
      ]..sort((a, b) => a.address.compareTo(b.address)),
      objectsWithoutCommunication: withoutCommunication,
      multipleReadAnswers: multipleReadAnswers,
      withoutSender: withoutSender,
      withoutReceiver: withoutReceiver,
      crowdedLines: [
        for (final e in perLine.entries)
          if (e.value > lineReserveLimit) (line: e.key, devices: e.value),
      ]..sort((a, b) => a.line.compareTo(b.line)),
      // Only relevant if telegrams pass through couplers (several lines).
      unfilteredMainGroups: perLine.length < 2 || catalog.style == GroupStyle.free
          ? const []
          : [
              for (final g in sorted)
                if (unfilteredMainGroup(g.address)) g,
            ],
      incomplete: incomplete,
    );
  }

  /// Whether the catalog contains flags (from .knxproj since this version);
  /// otherwise the flag checks are empty and the project must be re-imported.
  final bool hasFlags;

  /// Status addresses that no object with the T flag sends to.
  final List<GroupInfo> statusWithoutTransmit;

  /// Addresses that several objects send to – a notice, not an error.
  final List<GroupInfo> multipleSenders;

  /// Status addresses (which are read) without an object with C + R.
  final List<GroupInfo> readWithoutReadFlag;

  /// Devices without any associated group address.
  final List<DeviceInfo> devicesWithoutLinks;

  /// Devices that, according to the project, were never downloaded (only from .knxproj and .xknx
  /// that record downloads).
  final List<DeviceInfo> devicesNeverProgrammed;

  /// Devices changed in the project since their last download ([DeviceInfo.pendingDownload]).
  final List<DeviceInfo> devicesPendingDownload;

  /// Objects with a group address but without the C flag.
  final List<(GroupInfo, GroupLink)> objectsWithoutCommunication;

  /// Addresses with several objects with C + R – a read request then gets
  /// several, possibly different, responses.
  final List<GroupInfo> multipleReadAnswers;

  /// Command addresses that no object in the project sends to (visualization or
  /// logic without a placeholder in the project, or forgotten).
  final List<GroupInfo> withoutSender;

  /// Command addresses that no object with C + W listens to – including those
  /// without any association.
  final List<GroupInfo> withoutReceiver;

  /// Lines with more than [lineReserveLimit] devices.
  final List<({int line, int devices})> crowdedLines;

  /// Addresses in main group 14 or 15 in projects with several lines.
  final List<GroupInfo> unfilteredMainGroups;

  /// Addresses without a name (ETS default) or without a datapoint type.
  final List<({GroupInfo group, bool noName, bool noDpt})> incomplete;

  /// Whether something was found that can be checked even without devices in the project (CSV).
  bool get hasIncomplete => incomplete.isNotEmpty;
}

/// Main group 14 or 15: older line couplers do not keep them in the filter
/// table; depending on the coupler they are blocked or always forwarded.
/// Literature and ETS courses recommend 0–13.
bool unfilteredMainGroup(int address) => switch ((address >> 11) & 0x1F) {
  14 || 15 => true,
  _ => false,
};

/// Name the ETS or the import assigns when none is maintained.
bool isDefaultGroupName(GroupInfo g) {
  final name = g.name.trim().toLowerCase();
  return name.isEmpty ||
      name == formatGroup(g.address) ||
      const {'gruppenadresse', 'group address', 'neue gruppenadresse', 'new group address'}.contains(name);
}
