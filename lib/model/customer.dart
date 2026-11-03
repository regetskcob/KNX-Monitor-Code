import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../knx/demo_tunnel.dart';
import '../platform/storage.dart';
import 'installation.dart';

/// Customer data of an installation. Stored only on this device (`customer.json`
/// in the installation's folder) and never part of a diagnostic package or a
/// handover; older installations simply have no file.
@immutable
class CustomerRecord {
  const CustomerRecord({
    this.customer = '',
    this.site = '',
    this.contact = '',
    this.phone = '',
    this.email = '',
    this.notes = '',
    this.orderNumber = '',
    this.maintenanceMonths,
    this.maintenanceSince,
  });

  static const empty = CustomerRecord();

  final String customer;

  /// Address of the installation, multi-line.
  final String site;
  final String contact;
  final String phone;
  final String email;

  /// E.g. "Verteiler im Keller" (distribution board in the basement).
  final String notes;

  /// Customer or order number.
  final String orderNumber;

  /// Maintenance interval in months; `null` = no maintenance agreed.
  final int? maintenanceMonths;

  /// From when the interval counts, as long as there is no visit.
  final DateTime? maintenanceSince;

  bool get isEmpty =>
      customer.isEmpty &&
      site.isEmpty &&
      contact.isEmpty &&
      phone.isEmpty &&
      email.isEmpty &&
      notes.isEmpty &&
      orderNumber.isEmpty &&
      maintenanceMonths == null;

  /// All texts that count in the search and in the [Scrubber].
  List<String> get texts => [customer, ...site.split('\n'), contact, phone, email, orderNumber];

  /// Next maintenance date: interval from the last maintenance-relevant visit,
  /// otherwise from [maintenanceSince]. `null` without an interval.
  DateTime? nextMaintenance(List<Visit> visits) {
    final months = maintenanceMonths;
    if (months == null || months <= 0) return null;
    final last = visits
        .where((v) => v.kind.countsAsMaintenance)
        .map((v) => v.time)
        .fold<DateTime?>(maintenanceSince, (a, b) => a == null || b.isAfter(a) ? b : a);
    if (last == null) return null;
    // End of month: Jan 31 + 1 month is the last day of February, not March 3.
    final target = DateTime(last.year, last.month + months);
    final lastDay = DateTime(target.year, target.month + 1, 0).day;
    return DateTime(target.year, target.month, last.day > lastDay ? lastDay : last.day);
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'customer': customer,
    'site': site,
    'contact': contact,
    'phone': phone,
    'email': email,
    'notes': notes,
    'orderNumber': orderNumber,
    'maintenanceMonths': ?maintenanceMonths,
    'maintenanceSince': ?maintenanceSince?.millisecondsSinceEpoch,
  };

  /// Missing or wrongly typed fields stay empty.
  factory CustomerRecord.fromJson(Map<String, Object?> j) {
    String text(String key) => j[key] is String ? j[key]! as String : '';
    return CustomerRecord(
      customer: text('customer'),
      site: text('site'),
      contact: text('contact'),
      phone: text('phone'),
      email: text('email'),
      notes: text('notes'),
      orderNumber: text('orderNumber'),
      maintenanceMonths: j['maintenanceMonths'] is int ? j['maintenanceMonths']! as int : null,
      maintenanceSince: j['maintenanceSince'] is int
          ? DateTime.fromMillisecondsSinceEpoch(j['maintenanceSince']! as int)
          : null,
    );
  }
}

/// Kind of an entry in the visit history.
enum VisitKind {
  /// Connected to the installation (at most one per day).
  connection,
  commissioning,
  acceptance,
  serviceReport,

  /// Fault report received from the customer.
  faultReport,

  /// Handover package created.
  handover,

  /// Installation report of the box created as PDF.
  report,

  /// Custom entry.
  manual;

  /// Restarts the maintenance interval.
  bool get countsAsMaintenance => this == serviceReport || this == manual || this == acceptance;
}

/// An entry in the visit history of an installation.
@immutable
class Visit {
  const Visit({required this.id, required this.time, required this.kind, this.text = '', this.minutes, this.ref});

  final String id;
  final DateTime time;
  final VisitKind kind;
  final String text;

  /// Duration in minutes (custom entries).
  final int? minutes;

  /// Reference: ID of the recording of a fault report.
  final String? ref;

  static String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  Map<String, Object?> toJson() => {
    'id': id,
    't': time.millisecondsSinceEpoch,
    'k': kind.name,
    if (text.isNotEmpty) 'x': text,
    'm': ?minutes,
    'r': ?ref,
  };

  factory Visit.fromJson(Map<String, Object?> j) => Visit(
    id: j['id'] as String? ?? newId(),
    time: DateTime.fromMillisecondsSinceEpoch(j['t']! as int),
    // Kind from a newer version: show it as a custom entry instead of losing it.
    kind: VisitKind.values.asNameMap()[j['k']] ?? VisitKind.manual,
    text: j['x'] as String? ?? '',
    minutes: j['m'] as int?,
    ref: j['r'] as String?,
  );
}

/// What the installation list is sorted by.
enum CustomerSort { name, lastVisit, maintenance }

/// A row of the installation list.
@immutable
class CustomerEntry {
  const CustomerEntry({required this.installation, required this.record, required this.visits});

  final Installation installation;
  final CustomerRecord record;

  /// Newest first.
  final List<Visit> visits;

  String get title => record.customer.isNotEmpty ? record.customer : installation.name;

  DateTime? get lastVisit => visits.firstOrNull?.time;
  DateTime? get nextMaintenance => record.nextMaintenance(visits);

  bool maintenanceDue(DateTime now) {
    final next = nextMaintenance;
    return next != null && !next.isAfter(now);
  }

  /// Whether it matches the search. Multiple words must all occur.
  bool matches(String query) {
    final haystack = [installation.name, ...record.texts, record.notes].join(' ').toLowerCase();
    return query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).every(haystack.contains);
  }
}

/// Searches and sorts; for maintenance, due ones first and installations without
/// an interval at the end. Pure, so it is testable without storage.
List<CustomerEntry> filterCustomers(
  List<CustomerEntry> entries, {
  String query = '',
  CustomerSort sort = CustomerSort.name,
}) {
  int byName(CustomerEntry a, CustomerEntry b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());
  int orderDate(DateTime? a, DateTime? b, CustomerEntry x, CustomerEntry y, {required bool newestFirst}) {
    if (a == null && b == null) return byName(x, y);
    if (a == null) return 1;
    if (b == null) return -1;
    final c = newestFirst ? b.compareTo(a) : a.compareTo(b);
    return c != 0 ? c : byName(x, y);
  }

  return [
    for (final e in entries)
      if (e.matches(query)) e,
  ]..sort(
    (a, b) => switch (sort) {
      CustomerSort.name => byName(a, b),
      CustomerSort.lastVisit => orderDate(a.lastVisit, b.lastVisit, a, b, newestFirst: true),
      CustomerSort.maintenance => orderDate(a.nextMaintenance, b.nextMaintenance, a, b, newestFirst: false),
    },
  );
}

/// Customer records of all installations. Reads all `customer.json` and
/// `visits.json` at startup so the list can search and the [Scrubber] knows the
/// names. In the add-on (one installation) in the data folder.
class CustomerStore extends ChangeNotifier {
  CustomerStore._();

  static final instance = CustomerStore._();

  static const customerFile = 'customer.json';
  static const visitsFile = 'visits.json';

  final _records = <String, CustomerRecord>{};
  final _visits = <String, List<Visit>>{};

  AppStorage _storage(String id) =>
      kIsWeb ? AppStorage.instance : ScopedStorage(AppStorage.instance, 'installations/$id/');

  CustomerRecord record(String id) => _records[id] ?? CustomerRecord.empty;

  /// Newest first.
  List<Visit> visits(String id) => List.unmodifiable(_visits[id] ?? const <Visit>[]);

  List<CustomerEntry> get entries => [
    for (final i in InstallationStore.instance.list)
      CustomerEntry(installation: i, record: record(i.id), visits: visits(i.id)),
  ];

  /// Whether maintenance of the installation is due.
  bool maintenanceDue(String id, {DateTime? now}) {
    final next = record(id).nextMaintenance(visits(id));
    return next != null && !next.isAfter(now ?? DateTime.now());
  }

  /// Whether there is at least one filled-in customer record.
  bool get hasRecords => _records.values.any((r) => !r.isEmpty);

  /// Texts that never belong in a diagnostic package, not even as free text.
  Iterable<String> get privateNames => _records.values.expand((r) => r.texts).where((t) => t.trim().isNotEmpty);

  /// A broken file only costs its content: it is set aside so the next save does
  /// not overwrite it.
  Future<void> load() async {
    _records.clear();
    _visits.clear();
    for (final i in InstallationStore.instance.list) {
      final storage = _storage(i.id);
      final record = await _read(storage, customerFile, (v) => CustomerRecord.fromJson((v! as Map).cast()));
      if (record != null) _records[i.id] = record;
      final visits = await _read(storage, visitsFile, _parseVisits);
      if (visits != null) _visits[i.id] = visits;
    }
    notifyListeners();
  }

  static List<Visit> _parseVisits(Object? json) {
    final list = <Visit>[];
    for (final v in json! as List) {
      try {
        list.add(Visit.fromJson((v as Map).cast()));
      } on Object catch (e) {
        debugPrint('Besuch übersprungen: $e');
      }
    }
    return list..sort((a, b) => b.time.compareTo(a.time));
  }

  static Future<T?> _read<T>(AppStorage storage, String path, T Function(Object?) parse) =>
      readStored(storage, path, (text) => parse(jsonDecode(text)));

  Future<void> saveRecord(String id, CustomerRecord record) async {
    _records[id] = record;
    notifyListeners();
    if (DemoTunnel.active) return;
    await _storage(id).write(customerFile, jsonEncode(record.toJson()));
  }

  /// Adds an entry or replaces the one with the same ID.
  Future<void> saveVisit(String id, Visit visit) async {
    final list = [..._visits[id] ?? const <Visit>[]]..removeWhere((v) => v.id == visit.id);
    _visits[id] = [...list, visit]..sort((a, b) => b.time.compareTo(a.time));
    await _saveVisits(id);
  }

  Future<void> deleteVisit(String id, String visitId) async {
    _visits[id] = [...?_visits[id]]..removeWhere((v) => v.id == visitId);
    await _saveVisits(id);
  }

  Future<void> _saveVisits(String id) async {
    notifyListeners();
    if (DemoTunnel.active) return;
    await _storage(id).write(visitsFile, jsonEncode([for (final v in _visits[id]!) v.toJson()]));
  }

  /// Records an event in the active installation; an error while saving must not
  /// disturb the actual work (protocol, connection).
  Future<void> note(VisitKind kind, {String text = '', String? ref, String? installation, DateTime? now}) async {
    if (DemoTunnel.active) return;
    final id = installation ?? InstallationStore.instance.active.id;
    final time = now ?? DateTime.now();
    if (kind == VisitKind.connection) {
      // One connection per day is enough; otherwise flaky connections fill the list.
      final seen = visits(id).any(
        (v) =>
            v.kind == VisitKind.connection &&
            v.time.year == time.year &&
            v.time.month == time.month &&
            v.time.day == time.day,
      );
      if (seen) return;
    }
    try {
      await saveVisit(id, Visit(id: Visit.newId(), time: time, kind: kind, text: text, ref: ref));
    } on Object catch (e) {
      debugPrint('Besuch nicht gespeichert: $e');
    }
  }

  @visibleForTesting
  void debugReset() {
    _records.clear();
    _visits.clear();
  }
}

/// Link for calling; `null` without a usable number.
Uri? phoneUri(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  return digits.isEmpty ? null : Uri(scheme: 'tel', path: digits);
}

/// Link for emailing; `null` without an address.
Uri? mailUri(String email) {
  final address = email.trim();
  return address.contains('@') && !address.contains(RegExp(r'\s')) ? Uri(scheme: 'mailto', path: address) : null;
}

/// Link into the platform's maps app; `null` without an address.
Uri? mapsUri(String address, TargetPlatform platform, {bool web = false}) {
  final query = address.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).join(', ');
  if (query.isEmpty) return null;
  if (!web) {
    if (platform == TargetPlatform.android) return Uri(scheme: 'geo', path: '0,0', queryParameters: {'q': query});
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      return Uri.https('maps.apple.com', '/', {'q': query});
    }
  }
  return Uri.https('www.openstreetmap.org', '/search', {'query': query});
}
