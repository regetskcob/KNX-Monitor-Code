import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import 'availability.dart';
import 'recording.dart';

/// How serious a finding is.
enum FindingLevel { critical, warning, info }

/// An automatic finding from a diagnostic package.
typedef Finding = ({FindingLevel level, String text});

/// Findings from the technical details, traffic and log of a diagnostic package,
/// most important first: what usually matters first when debugging.
List<Finding> findingsOf(Recording r, {String? currentVersion}) {
  final d = r.diagnostics ?? const {};
  final tech = (d['technical'] as Map?)?.cast<String, Object?>() ?? const {};
  final connection = (tech['connection'] as Map?)?.cast<String, Object?>() ?? const {};
  final secure = (tech['secure'] as Map?)?.cast<String, Object?>() ?? const {};
  final traffic = (tech['traffic'] as Map?)?.cast<String, Object?>() ?? const {};
  final app = (tech['app'] as Map?)?.cast<String, Object?>() ?? const {};
  final out = <Finding>[];

  if (connection['error'] case final String error when error.isNotEmpty) {
    out.add((level: FindingLevel.critical, text: s.findingConnectionError(error)));
  } else if (connection['state'] case final String state when state != 'connected') {
    out.add((level: FindingLevel.warning, text: s.findingConnectionState(state)));
  }
  final rejected = (secure['telegramsRejected'] as num?)?.toInt() ?? 0;
  if (rejected > 0) out.add((level: FindingLevel.critical, text: s.findingSecureRejected(rejected)));
  final withoutKey = (secure['telegramsWithoutKey'] as num?)?.toInt() ?? 0;
  if (withoutKey > 0) out.add((level: FindingLevel.warning, text: s.findingSecureWithoutKey(withoutKey)));

  final total = (traffic['telegrams'] as num?)?.toInt() ?? r.telegrams.length;
  final repeated = (traffic['repeated'] as num?)?.toInt() ?? r.telegrams.where((t) => t.repeated).length;
  if (total > 0 && repeated * 20 > total) {
    out.add((level: FindingLevel.warning, text: s.findingRepeated(repeated, (repeated * 100 / total).round())));
  }
  final peak = peakPerSecond(r.telegrams);
  if (peak > peakLoadLimit) out.add((level: FindingLevel.warning, text: s.findingPeakLoad(peak)));
  final unanswered = (traffic['unansweredReads'] as num?)?.toInt() ?? 0;
  if (unanswered > 0) out.add((level: FindingLevel.warning, text: s.findingUnansweredReads(unanswered)));
  final confirmErrors = r.telegrams.where((t) => t.confirmError).length;
  if (confirmErrors > 0) out.add((level: FindingLevel.warning, text: s.findingConfirmErrors(confirmErrors)));

  final outages = [
    for (final o in (tech['availability'] as List?) ?? const [])
      if (o is Map) Outage.fromJson(o.cast()),
  ];
  if (outages.isNotEmpty) {
    out.add((level: FindingLevel.warning, text: s.findingOutages(outages.length, outageSummary(outages))));
  }

  final restarts = (tech['restarts'] as List?)?.length ?? 0;
  if (restarts > 0) out.add((level: FindingLevel.warning, text: s.findingRestarts(restarts)));

  final log = [...?(d['log'] as List?)?.cast<String>()];
  final errors = log.where(isErrorLine).length;
  if (errors > 0) out.add((level: FindingLevel.info, text: s.findingLogErrors(errors)));

  if (app['version'] case final String version
      when currentVersion != null && compareVersions(version, currentVersion) < 0) {
    out.add((level: FindingLevel.info, text: s.findingOldVersion(version, currentVersion)));
  }
  if (app['mode'] case final String mode when mode != 'release') {
    out.add((level: FindingLevel.info, text: s.findingBuildMode(mode)));
  }
  if (r.telegrams.isEmpty) out.add((level: FindingLevel.info, text: s.findingNoTelegrams));
  return out;
}

/// From this many telegrams in one second, a peak counts as a finding: TP1 at
/// 9600 baud handles about 40 short telegrams per second; beyond that,
/// telegrams pile up in the devices.
const peakLoadLimit = 30;

/// Most telegrams within one calendar second.
int peakPerSecond(List<Telegram> telegrams) {
  final perSecond = <int, int>{};
  var peak = 0;
  for (final t in telegrams) {
    final second = t.time.millisecondsSinceEpoch ~/ 1000;
    final n = perSecond[second] = (perSecond[second] ?? 0) + 1;
    if (n > peak) peak = n;
  }
  return peak;
}

/// Whether the log line contains an error or exception.
bool isErrorLine(String line) =>
    RegExp(r'error|fehler|exception|failed|fehlgeschlagen|timeout', caseSensitive: false).hasMatch(line);

/// Compares "1.7.2" with "1.7.10" numerically; build suffixes do not count.
int compareVersions(String a, String b) {
  List<int> parts(String v) => [for (final p in v.split('+').first.split('.')) int.tryParse(p) ?? 0];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final c = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
    if (c != 0) return c;
  }
  return 0;
}

/// The technical details of a package as rows for the findings: (term, value).
List<(String, String)> technicalFacts(Map<String, Object?> tech) {
  Map<String, Object?> sub(String k) => (tech[k] as Map?)?.cast<String, Object?>() ?? const {};
  String? str(Object? v) => v == null ? null : '$v';
  final app = sub('app');
  final connection = sub('connection');
  final gateway = sub('gateway');
  final secure = sub('secure');
  final traffic = sub('traffic');
  final addon = sub('addon');
  final where = [if (tech['homeAssistantAddon'] == true) 'Home Assistant', if (tech['viaBox'] == true) 'KNX-Box'];
  return [
    if (app.isNotEmpty)
      (
        s.factApp,
        [str(app['version']), if (app['build'] != null) '(${app['build']})', str(app['mode'])].nonNulls.join(' '),
      ),
    if (tech['platform'] != null)
      (s.factPlatform, [str(tech['platform']), str(tech['os']), ...where].nonNulls.join(' · ')),
    if (addon.isNotEmpty)
      (s.factAddon, [str(addon['version']), str(addon['state']), str(addon['mode'])].nonNulls.join(' · ')),
    if (connection.isNotEmpty)
      (
        s.factConnection,
        [
          str(connection['kind']),
          str(connection['state']),
          if (connection['tunnelAddress'] != null) '${s.factTunnel} ${connection['tunnelAddress']}',
        ].nonNulls.join(' · '),
      ),
    if (gateway.isNotEmpty)
      (
        s.factGateway,
        [
          str(gateway['name']),
          str(gateway['medium']),
          str(gateway['individualAddress']),
          if (gateway['tunnelSlots'] != null) s.factTunnelSlots(gateway['tunnelSlots']! as int),
        ].nonNulls.join(' · '),
      ),
    if (secure.isNotEmpty)
      (
        s.factSecure,
        secure['keyringLoaded'] == true
            ? s.factSecureLoaded((secure['groupKeyCount'] as num?)?.toInt() ?? 0)
            : s.factSecureNone,
      ),
    if (traffic.isNotEmpty)
      (
        s.factTraffic,
        s.factTrafficValue(
          (traffic['telegrams'] as num?)?.toInt() ?? 0,
          (traffic['repeated'] as num?)?.toInt() ?? 0,
          (traffic['unansweredReads'] as num?)?.toInt() ?? 0,
        ),
      ),
    if (tech['plan'] != null) (s.factPlan, '${tech['plan']}${tech['expertMode'] == true ? ' · ${s.factExpert}' : ''}'),
  ];
}

/// Number of telegrams per group address, most frequent first (for the findings).
List<(int, int)> busiestGroups(List<Telegram> telegrams, {int top = 5}) {
  final counts = <int, int>{};
  for (final t in telegrams) {
    counts[t.destination] = (counts[t.destination] ?? 0) + 1;
  }
  final list = [for (final e in counts.entries) (e.key, e.value)]..sort((a, b) => b.$2.compareTo(a.$2));
  return list.take(top).toList();
}
