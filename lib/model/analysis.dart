import '../catalog_store.dart';
import '../knx/group_catalog.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import 'commissioning.dart' show isStatusGroup;
import 'telegram_log.dart';

/// Anomaly of a telegram, for troubleshooting.
enum TelegramIssue {
  /// Repeated – the first attempt was not acknowledged.
  repeated(true),

  /// Sent by us and not acknowledged by the bus.
  notConfirmed(true),

  /// Read request without a response within the deadline.
  unanswered(true),

  /// Data length does not match the DPT from the project.
  sizeMismatch(true),

  /// Group address missing from the imported project.
  unknownAddress(false),

  /// Sender missing from the project's topology.
  unknownDevice(false),

  /// Hop count ≠ 6 – passed through a coupler, or a special case (7).
  unusualHop(false),

  /// A central-off address (by name) receives a 1.
  centralOffOn(true);

  const TelegramIssue(this.warning);

  /// Short label, e.g. "Wiederholt" (repeated).
  String get label => switch (this) {
    repeated => s.issueRepeatedLabel,
    notConfirmed => s.issueNotConfirmedLabel,
    unanswered => s.issueUnansweredLabel,
    sizeMismatch => s.issueSizeMismatchLabel,
    unknownAddress => s.issueUnknownAddressLabel,
    unknownDevice => s.issueUnknownDeviceLabel,
    unusualHop => s.issueUnusualHopLabel,
    centralOffOn => s.issueCentralOffOnLabel,
  };

  /// Explanation for troubleshooting.
  String get hint => switch (this) {
    repeated => s.issueRepeatedHint,
    notConfirmed => s.issueNotConfirmedHint,
    unanswered => s.issueUnansweredHint,
    sizeMismatch => s.issueSizeMismatchHint,
    unknownAddress => s.issueUnknownAddressHint,
    unknownDevice => s.issueUnknownDeviceHint,
    unusualHop => s.issueUnusualHopHint,
    centralOffOn => s.issueCentralOffOnHint,
  };

  /// A real problem (warning color) rather than mere information.
  final bool warning;
}

/// Expected payload length per DPT main group; 0 = value in the APCI (≤ 6 bits).
int? expectedSize(Dpt dpt) => switch (dpt.main) {
  1 || 2 || 3 => 0,
  4 || 5 || 6 || 17 || 18 || 20 || 21 || 23 || 26 || 238 => 1,
  7 || 8 || 9 || 22 || 237 || 244 => 2,
  10 || 11 || 232 => 3,
  12 || 13 || 14 || 15 => 4,
  245 || 251 => 6,
  19 || 29 => 8,
  16 => 14,
  _ => null,
};

/// Anomalies of [t] in the context of [log] and the imported project.
List<TelegramIssue> issuesOf(Telegram t, TelegramLog log) {
  final store = CatalogStore.instance;
  final catalog = store.catalog;
  final info = catalog[t.destination];
  final size = info?.dpt == null ? null : expectedSize(info!.dpt!);
  final actual = t.isSmall ? 0 : t.data.length;
  return [
    if (t.repeated) TelegramIssue.repeated,
    if (t.confirmError) TelegramIssue.notConfirmed,
    if (log.isUnanswered(t)) TelegramIssue.unanswered,
    if (t.type != TelegramType.read && size != null && size != actual) TelegramIssue.sizeMismatch,
    if (!catalog.isEmpty && info == null) TelegramIssue.unknownAddress,
    if (catalog.devices.isNotEmpty && !t.outgoing && store.device(t.source) == null) TelegramIssue.unknownDevice,
    if (t.unusualHop) TelegramIssue.unusualHop,
    if (info != null && isCentralOffOn(t, info)) TelegramIssue.centralOffOn,
  ];
}

/// Whether the address is named like a central-off function ("Alles aus",
/// "Zentral Licht aus", "All off"). Addresses that also carry "ein" (on) in
/// the name ("Zentral ein/aus") and status feedback do not count.
bool isCentralOffName(GroupInfo g) {
  final name = g.name.toLowerCase();
  return RegExp(r'\b(aus|off)\b').hasMatch(name) &&
      RegExp(r'\b(zentral|central|alle|alles|all|gesamt)\b').hasMatch(name) &&
      !RegExp(r'\b(ein|an|on)\b').hasMatch(name) &&
      !isStatusGroup(g);
}

/// Whether [t] writes a 1 to a central-off address. Only 1-bit values.
bool isCentralOffOn(Telegram t, GroupInfo g) =>
    t.type == TelegramType.write &&
    t.isSmall &&
    t.data.isNotEmpty &&
    t.data.first & 0x01 == 1 &&
    (g.dpt == null || g.dpt!.main == 1) &&
    isCentralOffName(g);
