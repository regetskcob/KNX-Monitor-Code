import 'package:flutter/foundation.dart';

import '../knx/demo_tunnel.dart';
import '../platform/addon.dart';
import 'customer.dart';
import 'installation.dart';

/// Installation report from the box and add-on (`server/lib/src/report.dart`).
/// The server only delivers numbers and addresses; texts and the PDF are created here.
@immutable
class PlantReport {
  const PlantReport(this.json);

  final Map<String, Object?> json;

  String get id => json['id']! as String;
  bool get quarterly => json['period'] == 'quarterly';
  DateTime get from => _time(json['from'])!;
  DateTime get to => _time(json['to'])!;
  DateTime get generated => _time(json['generated'])!;
  bool get partial => json['partial'] == true;

  /// Last day of the period (`to` is exclusive).
  DateTime get lastDay => to.subtract(const Duration(milliseconds: 1));

  Map<String, Object?> _map(String key) => (json[key] as Map?)?.cast<String, Object?>() ?? const {};
  List<Map<String, Object?>> _list(Map<String, Object?> m, String key) => [
    for (final e in (m[key] as List?) ?? const []) (e! as Map).cast<String, Object?>(),
  ];

  int get coveredDays => (_map('coverage')['days'] as int?) ?? 0;
  int get totalDays => (_map('coverage')['total'] as int?) ?? 0;

  /// Share of time with a connection (0–1); `null` without a sign of life.
  double? get availability => (_map('availability')['ratio'] as num?)?.toDouble();
  List<Map<String, Object?>> get outages => _list(_map('availability'), 'outages');
  List<Map<String, Object?>> get restarts => _list(_map('availability'), 'restarts');

  int get telegrams => (_map('traffic')['total'] as int?) ?? 0;
  int get avgPerDay => (_map('traffic')['avgPerDay'] as int?) ?? 0;
  String? get peakDay => _map('traffic')['peakDay'] as String?;
  int get peakDayCount => (_map('traffic')['peakDayCount'] as int?) ?? 0;
  Map<String, Object?>? get peakHour => (_map('traffic')['peakHour'] as Map?)?.cast<String, Object?>();
  List<Map<String, Object?>> get topSenders => _list(_map('traffic'), 'topSenders');

  double get averageLoad => (_map('load')['average'] as num?)?.toDouble() ?? 0;
  double get peakLoad => (_map('load')['peak'] as num?)?.toDouble() ?? 0;
  List<Map<String, Object?>> get lines => _list(_map('load'), 'lines');

  List<Map<String, Object?>> get repeats => _list(json, 'repeats');
  List<Map<String, Object?>> get safety => _list(json, 'safety');
  List<Map<String, Object?>> get findings => _list(json, 'findings');
  List<Map<String, Object?>> get resolved => _list(json, 'resolved');
  DateTime? get maintenanceDue => _time(json['maintenanceDue']);

  /// Findings that need attention; `0` means "all OK".
  int get attention => findings.where((f) => f['level'] == 'critical' || f['level'] == 'warning').length;

  static DateTime? _time(Object? v) => v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
}

/// A row of the report list.
@immutable
class PlantReportEntry {
  const PlantReportEntry(this.json);
  final Map<String, Object?> json;

  String get id => json['id']! as String;
  bool get quarterly => json['period'] == 'quarterly';
  DateTime get from => DateTime.fromMillisecondsSinceEpoch(json['from']! as int);
  DateTime get to => DateTime.fromMillisecondsSinceEpoch(json['to']! as int);
  bool get partial => json['partial'] == true;
  int get findings => json['findings'] as int? ?? 0;
  int get critical => json['critical'] as int? ?? 0;
  int get fresh => json['new'] as int? ?? 0;
  int get resolved => json['resolved'] as int? ?? 0;
}

/// State of the report feature on the server.
@immutable
class PlantReportOverview {
  const PlantReportOverview(this.json);
  final Map<String, Object?> json;

  Map<String, Object?> get settings => (json['settings'] as Map?)?.cast<String, Object?>() ?? const {};
  bool get enabled => settings['enabled'] == true;
  bool get quarterly => settings['period'] == 'quarterly';
  String get notifyKind => settings['notifyKind'] as String? ?? 'off';
  String get notifyUrl => settings['notifyUrl'] as String? ?? '';
  String get notifyTopic => settings['notifyTopic'] as String? ?? '';
  bool get hasToken => settings['hasNotifyToken'] == true;
  bool get notifyReady => settings['notifyReady'] != false;
  bool get notifyUrgent => settings['notifyUrgent'] != false;
  bool get canHomeAssistant => json['canHomeAssistant'] == true;
  String? get lastNotifyError => json['lastNotifyError'] as String?;
  String? get lastError => json['lastError'] as String?;
  List<PlantReportEntry> get reports => [
    for (final r in (json['reports'] as List?) ?? const []) PlantReportEntry((r! as Map).cast<String, Object?>()),
  ];
}

/// Talks to the server; replaceable in tests.
class PlantReportClient {
  const PlantReportClient();

  Future<PlantReportOverview> overview() async => PlantReportOverview(await Addon.report());
  Future<PlantReportOverview> configure(Map<String, Object?> changes) async =>
      PlantReportOverview(await Addon.configureReport(changes));
  Future<PlantReport> read(String id) async => PlantReport(await Addon.readReport(id));
  Future<PlantReport> generateNow() async => PlantReport(await Addon.generateReport());

  /// `null` = delivered, otherwise the reason from the server.
  Future<String?> sendTest() async {
    final result = await Addon.testReportNotification();
    return result['ok'] == true ? null : '${result['error'] ?? 'network'}';
  }

  Future<void> setMaintenance(DateTime? due) => Addon.setMaintenanceDue(due);
}

/// Sends the next maintenance date of the active installation to the server, so
/// it appears in the report and the notification is sent. Only the date: the
/// customer data stays on the device. Failures do no harm; it is retried next time.
class MaintenanceSync {
  MaintenanceSync({this.client = const PlantReportClient()});

  static final instance = MaintenanceSync();

  final PlantReportClient client;
  bool _listening = false;
  Object? _sent = const Object();

  void start() {
    if (_listening) return;
    _listening = true;
    CustomerStore.instance.addListener(_changed);
  }

  void _changed() => push();

  /// Next date from the record: last visit plus interval.
  Future<void> push({bool force = false}) async {
    if (!Addon.available || DemoTunnel.active) return;
    final store = CustomerStore.instance;
    final id = InstallationStore.instance.active.id;
    final due = store.record(id).nextMaintenance(store.visits(id));
    if (!force && due == _sent) return;
    _sent = due;
    try {
      await client.setMaintenance(due);
    } on Object catch (e) {
      _sent = const Object();
      debugPrint('Wartungstermin nicht übertragen: $e');
    }
  }
}
