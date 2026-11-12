import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import 'dali.dart';
import 'dali_log.dart';
import 'health.dart';

/// How long a gateway may be silent before it is a finding.
const daliSilentAfter = Duration(hours: 48);

/// The bus must have been heard at least this long within [daliSilentAfter]: an app that was
/// closed for two days knows nothing about a silent gateway.
const daliSilentMinHeard = Duration(hours: 24);

/// Two telegrams further apart than this count as "not listening in between".
const _hearingGap = Duration(minutes: 15);

/// How long the bus was heard between [from] and [to] according to [times] (any order): the sum of
/// the gaps between neighbours that are close enough.
Duration heardFor(Iterable<DateTime> times, DateTime from, DateTime to) {
  final sorted = [
    for (final t in times)
      if (!t.isBefore(from) && !t.isAfter(to)) t,
  ]..sort();
  var heard = Duration.zero;
  for (var i = 1; i < sorted.length; i++) {
    final gap = sorted[i].difference(sorted[i - 1]);
    if (gap <= _hearingGap) heard += gap;
  }
  return heard;
}

/// Lighting findings of the health check, one per gateway and kind: how many luminaires report a
/// lamp or gear failure, a gateway that fell silent, emergency luminaires that are overdue or
/// failed. [telegrams] is what the check looked at (for the silence rule).
List<HealthFinding> lightingFindings({
  required DaliStore store,
  required List<EmergencyOverview> tests,
  required Iterable<Telegram> telegrams,
  required DateTime now,
}) {
  final result = <HealthFinding>[];
  final gateways = store.gateways;
  if (gateways.isEmpty && tests.isEmpty) return result;
  DateTime? earliest(Iterable<DateTime?> times) =>
      times.whereType<DateTime>().fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);

  final from = now.subtract(daliSilentAfter);
  final recent = <DateTime>[];
  final sendersSeen = <int>{};
  for (final t in telegrams) {
    if (t.time.isBefore(from) || t.time.isAfter(now)) continue;
    recent.add(t.time);
    if (!t.outgoing) sendersSeen.add(t.source);
  }
  final heardEnough = gateways.isNotEmpty && heardFor(recent, from, now) >= daliSilentMinHeard;

  for (final gw in gateways) {
    final gear = store.gearOf(gw.address);
    final lamp = gear.where((g) => (g.faults ?? 0) & DaliFault.lamp != 0).toList();
    final broken = gear.where((g) => (g.faults ?? 0) & (DaliFault.gear | DaliFault.converter) != 0).toList();
    if (lamp.isNotEmpty) {
      result.add(
        HealthFinding(FindingKind.lampFault, gw.address, count: lamp.length, since: earliest(lamp.map((g) => g.since))),
      );
    }
    if (broken.isNotEmpty) {
      result.add(
        HealthFinding(
          FindingKind.gearFault,
          gw.address,
          count: broken.length,
          since: earliest(broken.map((g) => g.since)),
        ),
      );
    }
    final seen = gw.lastSeen;
    if (heardEnough && seen != null && seen.isBefore(from) && !sendersSeen.contains(gw.address)) {
      result.add(HealthFinding(FindingKind.gatewaySilent, gw.address, since: seen));
    }
  }
  final overdue = <int, int>{};
  final failed = <int, int>{};
  for (final row in tests) {
    final gw = row.gateway ?? 0;
    if (row.failed) failed[gw] = (failed[gw] ?? 0) + 1;
    if (row.overdue) overdue[gw] = (overdue[gw] ?? 0) + 1;
  }
  return [
    ...result,
    for (final MapEntry(:key, :value) in failed.entries) HealthFinding(FindingKind.testFailed, key, count: value),
    for (final MapEntry(:key, :value) in overdue.entries) HealthFinding(FindingKind.testOverdue, key, count: value),
  ];
}

/// [lightingFindings] for the active installation as it is now.
Future<List<HealthFinding>> currentLightingFindings(Iterable<Telegram> telegrams, DateTime now) async {
  final store = DaliStore.instance;
  if (store.isEmpty) return const [];
  await DaliTestLog.instance.load();
  return lightingFindings(store: store, tests: DaliTestLog.instance.overview(now), telegrams: telegrams, now: now);
}

/// Description of a lighting finding in the current language. Uses only what the finding carries,
/// so it also works where the stores are not loaded (PDF and report isolates).
String lightingFindingDetail(HealthFinding f) => switch (f.kind) {
  FindingKind.lampFault => s.daliHealthLampFault(f.count ?? 1),
  FindingKind.gearFault => s.daliHealthGearFault(f.count ?? 1),
  FindingKind.gatewaySilent => s.daliHealthSilent(_since(f.since)),
  FindingKind.testOverdue => s.daliHealthTestOverdue(f.count ?? 1),
  FindingKind.testFailed => s.daliHealthTestFailed(f.count ?? 1),
  _ => '',
};

String _since(DateTime? t) {
  if (t == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)}. ${two(t.hour)}:${two(t.minute)}';
}
