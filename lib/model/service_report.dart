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

  /// The items the customer should pay attention to.
  int get attention => [...findings, ...health].where((l) => l.level != ServiceLevel.info).length;

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
    );
  }

  /// Checksum (SHA-256) over the content, as with the acceptance protocol.
  String get checksum => sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();
}

/// Notices for the report from the recording and the health check.
typedef ServiceEvidence = ({List<ServiceLine> findings, List<ServiceLine> health});

/// Pure, for tests and the background isolate: translates without app state.
ServiceEvidence buildServiceEvidence(Recording? recording, HealthRun? run) => (
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
        ServiceLine(
          switch (f.kind.severity) {
            Severity.error => ServiceLevel.fix,
            Severity.warning => ServiceLevel.watch,
            Severity.info || Severity.ok => ServiceLevel.info,
          },
          findingTitle(f),
          findingDetail(f),
        ),
  ],
);

/// [buildServiceEvidence] in language [language]: natively in the background,
/// because the app keeps its own language. In the browser (no isolates) in the
/// app's language.
Future<ServiceEvidence> collectServiceEvidence({required String language, Recording? recording, HealthRun? run}) async {
  if (kIsWeb) return buildServiceEvidence(recording, run);
  final store = CatalogStore.instance;
  return Isolate.run(_evidenceTask(language, recording, run, store.catalog, Map.of(store.overrides)));
}

/// Separate function so the task only captures its arguments.
ServiceEvidence Function() _evidenceTask(
  String language,
  Recording? recording,
  HealthRun? run,
  GroupCatalog catalog,
  Map<int, Dpt> overrides,
) => () {
  LocaleController.instance.debugSetLocale(Locale(language));
  CatalogStore.instance
    ..catalog = catalog
    ..overrides = overrides;
  return buildServiceEvidence(recording, run);
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
