import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import 'health.dart';
import 'installation.dart';

/// Status light of the health check in plain language – always with a word and
/// a symbol, never color alone.
enum HealthLight {
  /// Not checked yet (or too long ago).
  unknown,

  /// All OK (at most notices).
  green,

  /// Something stands out, but it is not urgent.
  yellow,

  /// Something no longer responds or delivers impossible values.
  red;

  String get label => switch (this) {
    unknown => s.lightUnknown,
    green => s.lightGreen,
    yellow => s.lightYellow,
    red => s.lightRed,
  };
}

/// Status light from a check run; older than [maxAge] counts as "not checked".
/// [findings]: the applicable findings, if they differ from the run (passive
/// run, see [currentFindings]).
HealthLight lightOf(
  HealthRun? run,
  DateTime now, {
  Duration maxAge = const Duration(days: 7),
  List<HealthFinding>? findings,
}) {
  if (run == null || now.difference(run.time) > maxAge) return HealthLight.unknown;
  final worst = (findings ?? run.findings)
      .map((f) => f.kind.severity)
      .fold(Severity.ok, (a, b) => b.index > a.index ? b : a);
  return switch (worst) {
    Severity.error => HealthLight.red,
    Severity.warning => HealthLight.yellow,
    Severity.ok || Severity.info => HealthLight.green,
  };
}

/// Counts for the status light: from warning up. Notices (missing read flag and
/// the like) are project maintenance, not an everyday problem.
bool _counts(HealthFinding f) => f.kind.severity.index >= Severity.warning.index;

/// What the report can judge.
class ReportBasis {
  const ReportBasis({required this.continuous, required this.listened, required this.days, this.server});

  /// Whether the box or add-on records around the clock.
  final bool continuous;

  /// Time the app listened during the week (without continuous operation).
  final Duration listened;

  /// Days with listening.
  final int days;

  /// "Busclear Box" or "Home-Assistant-Add-on" for continuous operation.
  final String? server;
}

/// Weekly report: status light, one sentence, open and resolved findings, basis.
class WeeklyReport {
  const WeeklyReport({
    required this.light,
    required this.runs,
    required this.open,
    required this.resolved,
    required this.basis,
    this.lastFull,
  });

  final HealthLight light;

  /// Last run with a read test, if the newest one was passive.
  final DateTime? lastFull;

  /// Check runs of the last 7 days, newest first.
  final List<HealthRun> runs;

  /// Findings from warning up in the newest run.
  final List<HealthFinding> open;

  /// Findings from warning up that appeared during the week and are now gone.
  final List<HealthFinding> resolved;
  final ReportBasis basis;

  /// The one sentence for the start page.
  String get summary {
    if (runs.isEmpty) return s.weekNotChecked;
    final base = switch (open.length) {
      0 => s.weekAllGood,
      1 => s.weekOneIssue(plainFinding(open.first)),
      final n => s.weekIssues(n, plainFinding(open.first)),
    };
    return resolved.isEmpty ? base : '$base ${s.weekResolved(resolved.length)}';
  }

  /// Say honestly what the report judges.
  String get basisText {
    final checks = s.weekChecks(runs.length);
    if (basis.continuous) return s.weekBasisContinuous(basis.server ?? '', checks);
    if (basis.listened == Duration.zero) return s.weekBasisNone(checks);
    return s.weekBasisPartial(_duration(basis.listened), basis.days, checks);
  }
}

/// Builds the weekly report from the runs (newest first).
WeeklyReport weeklyReport(List<HealthRun> runs, DateTime now, {required ReportBasis basis}) {
  final week = [
    for (final r in runs)
      if (now.difference(r.time) <= const Duration(days: 7)) r,
  ];
  final latest = week.firstOrNull;
  // Passive runs (without a read test) say nothing about read findings.
  final current = week.isEmpty ? const <HealthFinding>[] : currentFindings(runs);
  final open = [...current.where(_counts)];
  final openKeys = {for (final f in open) f.key};
  final resolved = <String, HealthFinding>{
    for (final (i, r) in week.indexed.skip(1))
      for (final f in r.findings.where(_counts))
        if (!openKeys.contains(f.key) && (f.kind.area != HealthArea.read || week.take(i).any((n) => !n.passive)))
          f.key: f,
  };
  final full = runs.where((r) => !r.passive).firstOrNull;
  return WeeklyReport(
    light: lightOf(latest, now, findings: current),
    runs: week,
    open: open,
    resolved: resolved.values.toList(),
    basis: basis,
    lastFull: latest != null && latest.passive ? full?.time : null,
  );
}

/// A finding in everyday language: "Fensterkontakt Bad meldet sich nicht mehr"
/// (bathroom window contact no longer responds).
String plainFinding(HealthFinding f) {
  final store = CatalogStore.instance;
  final name = f.kind.device
      ? (store.device(f.address)?.name ?? s.plainDevice(formatIndividual(f.address)))
      : (store.info(f.address)?.name ?? s.plainAddress(formatGroup(f.address)));
  return switch (f.kind) {
    FindingKind.newSilent => s.plainFindingSilent(name),
    FindingKind.alwaysSilent || FindingKind.unlinked => s.plainFindingNoAnswer(name),
    FindingKind.overdue => s.plainFindingOverdue(name),
    FindingKind.outOfRange => s.plainFindingImpossible(name),
    FindingKind.stuck => s.plainFindingStuck(name),
    FindingKind.dptSize || FindingKind.dptValue || FindingKind.mixedSizes => s.plainFindingFormat(name),
    FindingKind.repeats => s.plainFindingRepeats(name),
    FindingKind.unansweredReads => s.plainFindingNoAnswer(name),
  };
}

String _duration(Duration d) =>
    d.inHours >= 1 ? s.weekHours(d.inHours, d.inMinutes % 60) : s.weekMinutes(d.inMinutes.clamp(1, 59));

/// How long the app listened per day (per installation, 14 days) – so the weekly
/// report can say honestly what it judges.
class ListeningLog extends ChangeNotifier {
  ListeningLog._();

  static final instance = ListeningLog._();
  static const _key = 'listening_minutes';
  static const _keepDays = 14;

  /// Day (yyyy-mm-dd) → minutes.
  final minutes = <String, int>{};
  String? _loadedFor;
  int _unsaved = 0;

  static String _day(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  Future<void> load() async {
    final key = InstallationStore.instance.key(_key);
    if (_loadedFor == key) return;
    _loadedFor = key;
    minutes.clear();
    try {
      final text = (await SharedPreferences.getInstance()).getString(key);
      if (text != null) {
        for (final MapEntry(:key, :value) in (jsonDecode(text) as Map<String, Object?>).entries) {
          minutes[key] = value! as int;
        }
      }
    } on Object catch (e) {
      debugPrint('Mithörzeit nicht lesbar: $e');
    }
    notifyListeners();
  }

  /// One minute of listening at [now]; saves every few minutes.
  void addMinute(DateTime now) {
    final day = _day(now);
    minutes[day] = (minutes[day] ?? 0) + 1;
    if (++_unsaved >= 5) unawaited(flush());
  }

  Future<void> flush() async {
    if (_unsaved == 0 || _loadedFor == null) return;
    _unsaved = 0;
    final cutoff = _day(DateTime.now().subtract(const Duration(days: _keepDays)));
    minutes.removeWhere((day, _) => day.compareTo(cutoff) < 0);
    await (await SharedPreferences.getInstance()).setString(_loadedFor!, jsonEncode(minutes));
  }

  /// Listening time and days of the last 7 days up to [now].
  (Duration, int) week(DateTime now) {
    var total = 0;
    var days = 0;
    for (var i = 0; i < 7; i++) {
      final m = minutes[_day(now.subtract(Duration(days: i)))] ?? 0;
      total += m;
      if (m > 0) days++;
    }
    return (Duration(minutes: total), days);
  }

  @visibleForTesting
  void debugReset() {
    minutes.clear();
    _loadedFor = null;
    _unsaved = 0;
  }
}
