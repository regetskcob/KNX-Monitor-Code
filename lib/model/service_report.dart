import 'dart:convert';
import 'dart:isolate';
import 'dart:ui' show Locale;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../catalog_store.dart';
import '../knx/demo_tunnel.dart';
import '../knx/group_catalog.dart';
import '../l10n/locale_controller.dart';
import 'acceptance.dart';
import 'annotation.dart';
import 'dali_service.dart';
import 'findings.dart';
import 'health.dart';
import 'installation.dart';
import 'recording.dart';

/// How urgent an item is for the customer – in words, not in technical levels.
enum ServiceLevel {
  /// Should be fixed.
  fix,

  /// Keep an eye on.
  watch,

  /// For information.
  info,
}

/// An automatic notice, captured in its language at the time of the report.
@immutable
class ServiceLine {
  const ServiceLine(this.level, this.title, [this.detail = '']);

  final ServiceLevel level;
  final String title;
  final String detail;

  Map<String, Object?> toJson() => {'l': level.name, 't': title, if (detail.isNotEmpty) 'd': detail};

  factory ServiceLine.fromJson(Map<String, Object?> j) => ServiceLine(
    ServiceLevel.values.asNameMap()[j['l']] ?? ServiceLevel.info,
    j['t'] as String? ?? '',
    j['d'] as String? ?? '',
  );
}

/// A comment from the recording or installation, with the IDs of its screenshots.
@immutable
class ServiceComment {
  const ServiceComment({required this.time, required this.note, this.shots = const []});

  final DateTime time;
  final String note;

  /// IDs in the [ShotStore]; if an image is missing later, the text remains.
  final List<String> shots;

  Map<String, Object?> toJson() => {'t': time.millisecondsSinceEpoch, 'n': note, if (shots.isNotEmpty) 's': shots};

  factory ServiceComment.fromJson(Map<String, Object?> j) => ServiceComment(
    time: DateTime.fromMillisecondsSinceEpoch(j['t'] as int? ?? 0),
    note: j['n'] as String? ?? '',
    shots: [...?(j['s'] as List?)?.cast<String>()],
  );
}

/// Photo from the photo documentation in the report: ID and caption at the time
/// of the report. If the image is missing later, the caption remains.
@immutable
class ServicePhoto {
  const ServicePhoto(this.id, this.caption);

  final String id;
  final String caption;

  Map<String, Object?> toJson() => {'i': id, if (caption.isNotEmpty) 'c': caption};

  factory ServicePhoto.fromJson(Map<String, Object?> j) =>
      ServicePhoto(j['i'] as String? ?? '', j['c'] as String? ?? '');
}

/// What a report is. Stored only when it is not a plain [visit], so older
/// reports keep their bytes and checksum; an older app reads the other two as
/// an ordinary report with the same four texts.
enum ServiceKind {
  /// Service call: something was wrong, the business came.
  visit,

  /// Recurring maintenance visit: fixed checklist, compared with the last one.
  maintenance,

  /// Short status reply to the customer after a fault report: what was
  /// reported ([ServiceReport.occasion]), what was found
  /// ([ServiceReport.observed]) and what happens next
  /// ([ServiceReport.recommendation]). No evidence, no technical values.
  reply,
}

/// Result of a checklist item of a maintenance visit.
enum CheckResult { unchecked, ok, attention }

/// A checklist item of a maintenance visit. [key] identifies the item across
/// reports (and languages), [label] is the text at the time of the report.
@immutable
class ServiceCheck {
  const ServiceCheck(this.key, this.label, [this.result = CheckResult.unchecked]);

  final String key;
  final String label;
  final CheckResult result;

  Map<String, Object?> toJson() => {'k': key, 't': label, 'r': result.name};

  factory ServiceCheck.fromJson(Map<String, Object?> j) => ServiceCheck(
    j['k'] as String? ?? '',
    j['t'] as String? ?? '',
    CheckResult.values.asNameMap()[j['r']] ?? CheckResult.unchecked,
  );
}

/// The fixed outline of a maintenance visit, in this order.
const maintenanceCheckKeys = ['visual', 'supply', 'health', 'functions', 'backup'];

/// Text of a checklist item in the language of [l]; `null` for a key this
/// version does not know (then the stored label of the report stays).
String? maintenanceCheckLabel(String key, AppLocalizations l) => switch (key) {
  'visual' => l.srMaintCheckVisual,
  'supply' => l.srMaintCheckSupply,
  'health' => l.srMaintCheckHealth,
  'functions' => l.srMaintCheckFunctions,
  'backup' => l.srMaintCheckBackup,
  _ => null,
};

/// Checklist for a new maintenance report in [language]: the same outline as
/// [previous] (the last maintenance report of the installation) if there is
/// one, otherwise the fixed one; results always start as "not checked".
List<ServiceCheck> maintenanceChecklist(String language, {ServiceReport? previous}) {
  final l = lookupAppLocalizations(Locale(language));
  final outline = previous == null || previous.checklist.isEmpty
      ? [for (final key in maintenanceCheckKeys) ServiceCheck(key, '')]
      : previous.checklist;
  return [for (final c in outline) ServiceCheck(c.key, maintenanceCheckLabel(c.key, l) ?? c.label)];
}

/// What a later maintenance report keeps of the one before, so the comparison
/// in its PDF never changes: only the comparable parts. [findings] and [health]
/// are `null` when that report had no recording or no health check, which is
/// different from "had one and it found nothing".
@immutable
class ServiceBaseline {
  const ServiceBaseline({
    required this.created,
    required this.language,
    this.findings,
    this.health,
    this.healthTime,
    this.checklist = const [],
  });

  factory ServiceBaseline.of(ServiceReport r) => ServiceBaseline(
    created: r.created,
    language: r.language,
    findings: r.recordingStart == null ? null : r.findings,
    health: r.healthTime == null ? null : r.health,
    healthTime: r.healthTime,
    checklist: r.checklist,
  );

  final DateTime created;
  final String language;
  final List<ServiceLine>? findings;
  final List<ServiceLine>? health;
  final DateTime? healthTime;
  final List<ServiceCheck> checklist;

  Map<String, Object?> toJson() => {
    'created': created.millisecondsSinceEpoch,
    'language': language,
    if (findings != null) 'findings': [for (final f in findings!) f.toJson()],
    if (health != null) 'health': [for (final h in health!) h.toJson()],
    'healthTime': ?healthTime?.millisecondsSinceEpoch,
    if (checklist.isNotEmpty) 'checklist': [for (final c in checklist) c.toJson()],
  };

  factory ServiceBaseline.fromJson(Map<String, Object?> j) {
    List<ServiceLine>? lines(String key) =>
        j[key] == null ? null : [for (final l in j[key]! as List) ServiceLine.fromJson((l as Map).cast())];
    return ServiceBaseline(
      created: DateTime.fromMillisecondsSinceEpoch(j['created'] as int? ?? 0),
      language: j['language'] as String? ?? 'de',
      findings: lines('findings'),
      health: lines('health'),
      healthTime: j['healthTime'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['healthTime']! as int),
      checklist: [for (final c in (j['checklist'] as List?) ?? const []) ServiceCheck.fromJson((c as Map).cast())],
    );
  }
}

/// A maintenance report compared with the one before. Only what both reports
/// really contain: notices are compared per source (recording, health check)
/// that both have, and only when both are in the same language, because the
/// notices are stored as text.
@immutable
class ServiceComparison {
  const ServiceComparison({
    required this.previous,
    required this.linesCompared,
    this.added = const [],
    this.gone = const [],
    this.remaining = const [],
    this.healthBefore,
    this.healthNow,
    this.healthTimeBefore,
    this.checks = const [],
  });

  /// When the previous report was created.
  final DateTime previous;

  /// Whether any notices could be compared at all. If not, [added], [gone]
  /// and [remaining] are empty and say nothing.
  final bool linesCompared;
  final List<ServiceLine> added;
  final List<ServiceLine> gone;
  final List<ServiceLine> remaining;

  /// Points of the health check to fix and to watch, then and now; `null`
  /// unless both reports include a health check.
  final ({int fix, int watch})? healthBefore;
  final ({int fix, int watch})? healthNow;
  final DateTime? healthTimeBefore;

  /// Checklist items both reports have, with the result then and now.
  final List<({String label, CheckResult before, CheckResult now})> checks;
}

/// Service report for the customer: reason, observation, work done,
/// recommendation, plus what the recording, the comments and the health check
/// provide. Immutable once created, like the acceptance protocol: all texts are
/// stored in the report's language, and a later project import does not change it.
@immutable
class ServiceReport {
  const ServiceReport({
    required this.created,
    required this.customer,
    required this.site,
    required this.technician,
    required this.language,
    required this.occasion,
    required this.observed,
    required this.done,
    required this.recommendation,
    this.project,
    this.recordingName,
    this.recordingStart,
    this.recordingEnd,
    this.telegrams = 0,
    this.comments = const [],
    this.photos = const [],
    this.findings = const [],
    this.health = const [],
    this.healthTime,
    this.signer = '',
    this.signature = Signature.empty,
    this.gateway,
    this.kind = ServiceKind.visit,
    this.checklist = const [],
    this.previous,
    this.reportedAt,
  });

  final DateTime created;
  final String? project;
  final String customer;
  final String site;
  final String technician;

  /// Language of the report (`de`, `en`), independent of the app.
  final String language;

  /// Reason for the visit, what was observed, what was done, recommendation.
  final String occasion;
  final String observed;
  final String done;
  final String recommendation;

  /// The recording the report is based on (optional).
  final String? recordingName;
  final DateTime? recordingStart;
  final DateTime? recordingEnd;
  final int telegrams;
  final List<ServiceComment> comments;

  /// Explicitly selected photos from the photo documentation.
  final List<ServicePhoto> photos;

  /// Notices from the recording.
  final List<ServiceLine> findings;

  /// Findings of the health check and when it ran.
  final List<ServiceLine> health;
  final DateTime? healthTime;

  /// Customer's signature (optional).
  final String signer;
  final Signature signature;
  final String? gateway;

  final ServiceKind kind;

  /// Maintenance visit: what was looked at, with the result.
  final List<ServiceCheck> checklist;

  /// Maintenance visit: the comparable parts of the maintenance report before
  /// this one; `null` for the first.
  final ServiceBaseline? previous;

  /// Reply to a fault report: when the customer reported it.
  final DateTime? reportedAt;

  /// The items the customer should pay attention to.
  int get attention =>
      [...findings, ...health].where((l) => l.level != ServiceLevel.info).length +
      checklist.where((c) => c.result == CheckResult.attention).length;

  /// Comparison with the previous maintenance report; `null` without one.
  ServiceComparison? get comparison {
    final before = previous;
    if (before == null) return null;
    final sameLanguage = before.language == language;
    final then = <ServiceLine>[];
    final now = <ServiceLine>[];
    var compared = false;
    if (sameLanguage && before.findings != null && recordingStart != null) {
      compared = true;
      then.addAll(before.findings!);
      now.addAll(findings);
    }
    if (sameLanguage && before.health != null && healthTime != null) {
      compared = true;
      then.addAll(before.health!);
      now.addAll(health);
    }
    // "For information" is no finding; the title identifies a notice (the
    // detail may carry numbers that change from visit to visit).
    then.removeWhere((l) => l.level == ServiceLevel.info);
    now.removeWhere((l) => l.level == ServiceLevel.info);
    final titlesThen = {for (final l in then) l.title};
    final titlesNow = {for (final l in now) l.title};
    ({int fix, int watch}) counts(List<ServiceLine> lines) => (
      fix: lines.where((l) => l.level == ServiceLevel.fix).length,
      watch: lines.where((l) => l.level == ServiceLevel.watch).length,
    );
    // Counts, not texts: they compare across languages, unlike the notices above.
    final bothHealth = before.health != null && healthTime != null;
    final results = {for (final c in before.checklist) c.key: c.result};
    return ServiceComparison(
      previous: before.created,
      linesCompared: compared,
      added: [
        for (final l in now)
          if (!titlesThen.contains(l.title)) l,
      ],
      gone: [
        for (final l in then)
          if (!titlesNow.contains(l.title)) l,
      ],
      remaining: [
        for (final l in now)
          if (titlesThen.contains(l.title)) l,
      ],
      healthBefore: bothHealth ? counts(before.health!) : null,
      healthNow: bothHealth ? counts(health) : null,
      healthTimeBefore: bothHealth ? before.healthTime : null,
      checks: [
        for (final c in checklist)
          if (results[c.key] case final then?) (label: c.label, before: then, now: c.result),
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'format': 'knx-monitor-service-report',
    'version': 1,
    'created': created.millisecondsSinceEpoch,
    'project': project,
    'customer': customer,
    'site': site,
    'technician': technician,
    'language': language,
    'occasion': occasion,
    'observed': observed,
    'done': done,
    'recommendation': recommendation,
    'recordingName': recordingName,
    'recordingStart': recordingStart?.millisecondsSinceEpoch,
    'recordingEnd': recordingEnd?.millisecondsSinceEpoch,
    'telegrams': telegrams,
    'comments': [for (final c in comments) c.toJson()],
    // Only if any are selected: checksums of older reports remain valid.
    if (photos.isNotEmpty) 'photos': [for (final p in photos) p.toJson()],
    'findings': [for (final f in findings) f.toJson()],
    'health': [for (final h in health) h.toJson()],
    'healthTime': healthTime?.millisecondsSinceEpoch,
    'signer': signer,
    'signature': signature.toJson(),
    'gateway': gateway,
    // Only when used: checksums of older and of plain reports remain valid.
    if (kind != ServiceKind.visit) 'kind': kind.name,
    if (checklist.isNotEmpty) 'checklist': [for (final c in checklist) c.toJson()],
    'previous': ?previous?.toJson(),
    'reportedAt': ?reportedAt?.millisecondsSinceEpoch,
  };

  factory ServiceReport.fromJson(Map<String, Object?> j) {
    DateTime? time(String key) => j[key] == null ? null : DateTime.fromMillisecondsSinceEpoch(j[key]! as int);
    List<ServiceLine> lines(String key) => [
      for (final l in (j[key] as List?) ?? const []) ServiceLine.fromJson((l as Map).cast()),
    ];
    return ServiceReport(
      created: DateTime.fromMillisecondsSinceEpoch(j['created']! as int),
      project: j['project'] as String?,
      customer: j['customer'] as String? ?? '',
      site: j['site'] as String? ?? '',
      technician: j['technician'] as String? ?? '',
      language: j['language'] as String? ?? 'de',
      occasion: j['occasion'] as String? ?? '',
      observed: j['observed'] as String? ?? '',
      done: j['done'] as String? ?? '',
      recommendation: j['recommendation'] as String? ?? '',
      recordingName: j['recordingName'] as String?,
      recordingStart: time('recordingStart'),
      recordingEnd: time('recordingEnd'),
      telegrams: j['telegrams'] as int? ?? 0,
      comments: [for (final c in (j['comments'] as List?) ?? const []) ServiceComment.fromJson((c as Map).cast())],
      photos: [for (final p in (j['photos'] as List?) ?? const []) ServicePhoto.fromJson((p as Map).cast())],
      findings: lines('findings'),
      health: lines('health'),
      healthTime: time('healthTime'),
      signer: j['signer'] as String? ?? '',
      signature: Signature.fromJson(j['signature']),
      gateway: j['gateway'] as String?,
      // A kind from a newer version reads as a plain report.
      kind: ServiceKind.values.asNameMap()[j['kind']] ?? ServiceKind.visit,
      checklist: [for (final c in (j['checklist'] as List?) ?? const []) ServiceCheck.fromJson((c as Map).cast())],
      previous: j['previous'] == null ? null : ServiceBaseline.fromJson((j['previous']! as Map).cast()),
      reportedAt: time('reportedAt'),
    );
  }

  /// Checksum (SHA-256) over the content, as with the acceptance protocol.
  String get checksum => sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();
}

/// Notices for the report from the recording and the health check.
typedef ServiceEvidence = ({List<ServiceLine> findings, List<ServiceLine> health});

/// Pure, for tests and the background isolate: translates without app state.
///
/// [dali]: what is open on the DALI side right now, one item per luminaire. They stand in for
/// the lighting findings of the health check, which only count per gateway and may be older.
ServiceEvidence buildServiceEvidence(Recording? recording, HealthRun? run, [List<DaliIssue> dali = const []]) => (
  // Only what concerns the customer; app version and log are a matter for support.
  findings: [
    if (recording != null)
      for (final f in findingsOf(recording))
        if (f.level != FindingLevel.info)
          ServiceLine(f.level == FindingLevel.critical ? ServiceLevel.fix : ServiceLevel.watch, f.text),
  ],
  health: [
    if (run != null)
      for (final f in run.findings)
        if (f.kind.area != HealthArea.lighting || f.kind == FindingKind.gatewaySilent)
          ServiceLine(
            switch (f.kind.severity) {
              Severity.error => ServiceLevel.fix,
              Severity.warning => ServiceLevel.watch,
              Severity.info || Severity.ok => ServiceLevel.info,
            },
            findingTitle(f),
            findingDetail(f),
          ),
    ...daliServiceLines(dali),
  ],
);

/// [buildServiceEvidence] in language [language]: natively in the background,
/// because the app keeps its own language. In the browser (no isolates) in the
/// app's language.
Future<ServiceEvidence> collectServiceEvidence({required String language, Recording? recording, HealthRun? run}) async {
  final dali = collectDaliIssues(DateTime.now());
  if (kIsWeb) return buildServiceEvidence(recording, run, dali);
  final store = CatalogStore.instance;
  return Isolate.run(_evidenceTask(language, recording, run, store.catalog, Map.of(store.overrides), dali));
}

/// Separate function so the task only captures its arguments.
ServiceEvidence Function() _evidenceTask(
  String language,
  Recording? recording,
  HealthRun? run,
  GroupCatalog catalog,
  Map<int, Dpt> overrides,
  List<DaliIssue> dali,
) => () {
  LocaleController.instance.debugSetLocale(Locale(language));
  CatalogStore.instance
    ..catalog = catalog
    ..overrides = overrides;
  return buildServiceEvidence(recording, run, dali);
};

/// Comments for the report: those of the recording and those of the installation
/// within its time range; without a recording, those of the last 24 hours (the
/// visit itself).
List<ServiceComment> collectServiceComments(Recording? recording, List<Annotation> all, {DateTime? now}) {
  final end = recording?.ended ?? now ?? DateTime.now();
  final start = recording?.started ?? end.subtract(const Duration(hours: 24));
  final picked = {
    for (final a in all)
      if (!a.time.isBefore(start) && !a.time.isAfter(end)) a.id: a,
    for (final a in recording?.annotations ?? const <Annotation>[]) a.id: a,
  };
  return [
    for (final a in picked.values.toList()..sort((a, b) => a.time.compareTo(b.time)))
      if (a.note.trim().isNotEmpty || a.shots.isNotEmpty)
        ServiceComment(time: a.time, note: a.note.trim(), shots: a.shots),
  ];
}

/// Saved service reports of the active installation
/// (`service_reports/<timestamp>.json`), newest first.
class ServiceReportStore extends ChangeNotifier {
  ServiceReportStore._();

  static final instance = ServiceReportStore._();
  static const dir = 'service_reports';

  /// In the demo house in memory only, like the acceptance protocols.
  final _demo = <ServiceReport>[];

  Future<List<ServiceReport>> list() async {
    if (DemoTunnel.active) return [..._demo]..sort((a, b) => b.created.compareTo(a.created));
    _demo.clear();
    final storage = InstallationStore.instance.storage;
    final result = <ServiceReport>[];
    for (final f in await storage.list(dir)) {
      if (!f.name.endsWith('.json')) continue;
      try {
        final text = await storage.read('$dir/${f.name}');
        if (text != null) result.add(ServiceReport.fromJson((jsonDecode(text) as Map).cast()));
      } on Object catch (e) {
        debugPrint('Servicebericht ${f.name} nicht lesbar: $e');
      }
    }
    return result..sort((a, b) => b.created.compareTo(a.created));
  }

  /// The newest maintenance report of the installation, the baseline of the
  /// next one.
  Future<ServiceReport?> lastMaintenance() async =>
      (await list()).where((r) => r.kind == ServiceKind.maintenance).firstOrNull;

  /// The report created at [created] (as in the file name); `null` if it is gone.
  Future<ServiceReport?> byCreated(int created) async =>
      (await list()).where((r) => r.created.millisecondsSinceEpoch == created).firstOrNull;

  Future<void> save(ServiceReport r) async {
    if (DemoTunnel.active) {
      _demo.add(r);
      return notifyListeners();
    }
    await InstallationStore.instance.storage.write(
      '$dir/${r.created.millisecondsSinceEpoch}.json',
      jsonEncode(r.toJson()),
    );
    notifyListeners();
  }
}
