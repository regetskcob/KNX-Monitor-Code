import 'dart:convert';
import 'dart:ui' show Offset;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../catalog_store.dart';
import '../knx/demo_tunnel.dart';
import 'commissioning.dart';
import 'installation.dart';

/// Signature as strokes: points relative to the field (x and y each 0–1); the
/// field has the aspect ratio [aspect]. Stored as vectors and drawn in the PDF,
/// so it stays sharp at any size.
@immutable
class Signature {
  const Signature(this.strokes);

  static const empty = Signature([]);

  /// Width : height of the signature field.
  static const aspect = 3.0;

  final List<List<Offset>> strokes;

  bool get isEmpty => strokes.every((s) => s.length < 2);

  /// Rounded to four digits: enough for any print size, keeps the file small.
  List<List<List<double>>> toJson() => [
    for (final stroke in strokes)
      [
        for (final p in stroke) [_round(p.dx), _round(p.dy)],
      ],
  ];

  static double _round(double v) => (v.clamp(0, 1) * 10000).roundToDouble() / 10000;

  factory Signature.fromJson(Object? j) => Signature([
    for (final stroke in (j as List? ?? const []))
      [for (final p in stroke as List) Offset(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble())],
  ]);
}

/// Acceptance protocol: a frozen snapshot of the commissioning with customer and
/// site details and the signatures of both parties. Immutable once signed;
/// changes mean a new protocol.
@immutable
class Acceptance {
  const Acceptance({
    required this.created,
    required this.project,
    required this.customer,
    required this.site,
    required this.technician,
    required this.customerSigner,
    required this.remarks,
    required this.followUps,
    required this.language,
    required this.items,
    required this.groups,
    required this.customerSignature,
    required this.technicianSignature,
    this.started,
    this.gateway,
    this.checkedBy,
    this.checkedByMember,
    this.checkedAt,
    this.approvedBy,
    this.approvedByMember,
    this.approvedAt,
  });

  /// Creates a protocol from the current commissioning state. Names and ranges of
  /// the addresses are stored as well, so a later project import does not change
  /// the protocol.
  factory Acceptance.fromCommissioning(
    Commissioning c, {
    required String customer,
    required String site,
    required String technician,
    required String customerSigner,
    required String remarks,
    required String followUps,
    required String language,
    required Signature customerSignature,
    required Signature technicianSignature,
    String? gateway,
    DateTime? now,
  }) {
    final store = CatalogStore.instance;
    final items = [for (final i in c.items.values) CheckItem.fromJson(i.toJson())];
    return Acceptance(
      created: now ?? DateTime.now(),
      project: store.catalog.projectName,
      customer: customer.trim(),
      site: site.trim(),
      technician: technician.trim(),
      customerSigner: customerSigner.trim(),
      remarks: remarks.trim(),
      followUps: followUps.trim(),
      language: language,
      items: items,
      groups: {
        for (final i in items) i.address: (name: store.info(i.address)?.name ?? '', path: store.info(i.address)?.path),
      },
      customerSignature: customerSignature,
      technicianSignature: technicianSignature,
      started: c.started,
      gateway: gateway,
    );
  }

  final DateTime created;
  final String? project;
  final String customer;
  final String site;
  final String technician;

  /// Name of the customer's signatory (in block letters).
  final String customerSigner;
  final String remarks;

  /// Open items and agreed follow-up work.
  final String followUps;

  /// Language of the protocol (`de`, `en`), independent of the app.
  final String language;
  final DateTime? started;
  final String? gateway;
  final List<CheckItem> items;

  /// Name and range (ETS path) per address at the time of acceptance.
  final Map<int, ({String name, String? path})> groups;
  final Signature customerSignature;
  final Signature technicianSignature;

  /// Four-eyes acceptance (Pro team): who pre-checked and who signed off. Empty for
  /// all other protocols; the file is then byte-identical to before and its
  /// checksum stays valid.
  final String? checkedBy;
  final String? checkedByMember;
  final DateTime? checkedAt;
  final String? approvedBy;
  final String? approvedByMember;
  final DateTime? approvedAt;

  bool get fourEyes => checkedBy != null || approvedBy != null;

  /// Copy with the stamp. This changes the checksum, which covers the names too.
  Acceptance stamped({
    String? checkedBy,
    String? checkedByMember,
    DateTime? checkedAt,
    String? approvedBy,
    String? approvedByMember,
    DateTime? approvedAt,
  }) => Acceptance(
    created: created,
    project: project,
    customer: customer,
    site: site,
    technician: technician,
    customerSigner: customerSigner,
    remarks: remarks,
    followUps: followUps,
    language: language,
    items: items,
    groups: groups,
    customerSignature: customerSignature,
    technicianSignature: technicianSignature,
    started: started,
    gateway: gateway,
    checkedBy: checkedBy ?? this.checkedBy,
    checkedByMember: checkedByMember ?? this.checkedByMember,
    checkedAt: checkedAt ?? this.checkedAt,
    approvedBy: approvedBy ?? this.approvedBy,
    approvedByMember: approvedByMember ?? this.approvedByMember,
    approvedAt: approvedAt ?? this.approvedAt,
  );

  int count(CheckState state) => items.where((i) => i.state == state).length;

  /// Items with result "OK" (read, seen, by hand).
  int get done => items.where((i) => i.state.done).length;

  Map<String, Object?> toJson() => {
    'format': 'knx-monitor-acceptance',
    'version': 1,
    'created': created.millisecondsSinceEpoch,
    'project': project,
    'customer': customer,
    'site': site,
    'technician': technician,
    'customerSigner': customerSigner,
    'remarks': remarks,
    'followUps': followUps,
    'language': language,
    'started': started?.millisecondsSinceEpoch,
    'gateway': gateway,
    'items': [for (final i in items) i.toJson()],
    'groups': {
      for (final MapEntry(:key, :value) in groups.entries) '$key': [value.name, value.path],
    },
    'customerSignature': customerSignature.toJson(),
    'technicianSignature': technicianSignature.toJson(),
    if (checkedBy != null) 'checkedBy': checkedBy,
    if (checkedByMember != null) 'checkedByMember': checkedByMember,
    if (checkedAt != null) 'checkedAt': checkedAt!.millisecondsSinceEpoch,
    if (approvedBy != null) 'approvedBy': approvedBy,
    if (approvedByMember != null) 'approvedByMember': approvedByMember,
    if (approvedAt != null) 'approvedAt': approvedAt!.millisecondsSinceEpoch,
  };

  factory Acceptance.fromJson(Map<String, Object?> j) => Acceptance(
    created: DateTime.fromMillisecondsSinceEpoch(j['created']! as int),
    project: j['project'] as String?,
    customer: j['customer'] as String? ?? '',
    site: j['site'] as String? ?? '',
    technician: j['technician'] as String? ?? '',
    customerSigner: j['customerSigner'] as String? ?? '',
    remarks: j['remarks'] as String? ?? '',
    followUps: j['followUps'] as String? ?? '',
    language: j['language'] as String? ?? 'de',
    started: j['started'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['started']! as int),
    gateway: j['gateway'] as String?,
    items: [for (final i in (j['items'] as List? ?? const [])) CheckItem.fromJson(i as Map<String, Object?>)],
    groups: {
      for (final MapEntry(:key, :value) in (j['groups'] as Map? ?? const {}).entries)
        int.parse(key as String): (name: (value as List)[0] as String, path: value[1] as String?),
    },
    customerSignature: Signature.fromJson(j['customerSignature']),
    technicianSignature: Signature.fromJson(j['technicianSignature']),
    checkedBy: j['checkedBy'] as String?,
    checkedByMember: j['checkedByMember'] as String?,
    checkedAt: j['checkedAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['checkedAt']! as int),
    approvedBy: j['approvedBy'] as String?,
    approvedByMember: j['approvedByMember'] as String?,
    approvedAt: j['approvedAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['approvedAt']! as int),
  );

  /// Checksum (SHA-256) over the content: printed in the PDF so later changes
  /// stand out. Not a qualified electronic signature.
  String get checksum => sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();

  /// Short form for display, e.g. "3f2a…9c1d".
  String get shortChecksum {
    final c = checksum;
    return '${c.substring(0, 8)}…${c.substring(c.length - 8)}';
  }
}

/// Saved acceptance protocols of the active installation
/// (`protocols/<timestamp>.json`), newest first.
class AcceptanceStore extends ChangeNotifier {
  AcceptanceStore._();

  static final instance = AcceptanceStore._();
  static const _dir = 'protocols';

  /// Protocols created in the demo house: kept in memory only, so nothing ends up
  /// in the real installation (as with commissioning).
  final _demo = <Acceptance>[];

  Future<List<Acceptance>> list() async {
    if (DemoTunnel.active) return [..._demo]..sort((a, b) => b.created.compareTo(a.created));
    _demo.clear();
    final storage = InstallationStore.instance.storage;
    final result = <Acceptance>[];
    for (final f in await storage.list(_dir)) {
      if (!f.name.endsWith('.json')) continue;
      try {
        final text = await storage.read('$_dir/${f.name}');
        if (text != null) result.add(Acceptance.fromJson(jsonDecode(text) as Map<String, Object?>));
      } on Object catch (e) {
        debugPrint('Abnahmeprotokoll ${f.name} nicht lesbar: $e');
      }
    }
    return result..sort((a, b) => b.created.compareTo(a.created));
  }

  Future<void> save(Acceptance a) async {
    if (DemoTunnel.active) {
      _demo.add(a);
      return notifyListeners();
    }
    await InstallationStore.instance.storage.write(
      '$_dir/${a.created.millisecondsSinceEpoch}.json',
      jsonEncode(a.toJson()),
    );
    notifyListeners();
  }
}
