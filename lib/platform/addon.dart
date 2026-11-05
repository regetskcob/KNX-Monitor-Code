import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'addon_io.dart' if (dart.library.js_interop) 'addon_web.dart' as impl;
import '../knx/telegram.dart';
import 'box_link.dart';

/// Connection to the server of the Home Assistant add-on or the KNX box.
///
/// The server keeps the bus connection open permanently, records and distributes the frames to all
/// open views. In the browser it is the server that delivers the page; natively (iPad, iPhone) the
/// paired [box].
abstract final class Addon {
  /// Whether the app runs in the add-on or on the box in the browser.
  static bool get embedded => impl.addonAvailable;

  /// Native: the box the app is currently attached to (instead of the gateway).
  static BoxLink? box;

  /// Whether the app talks to an add-on or box server.
  static bool get available => embedded || box != null;

  /// WebSocket "ws/bus" to the shared tunnel.
  static Future<AddonSocket> openBus() => impl.openAddonBus();

  /// Status and settings of the continuous recording.
  static Future<Map<String, Object?>> status() => impl.addonGet('api/bus');

  /// Changes settings (only the given fields) and returns the new status.
  ///
  /// [probe]: adopt a changed bus connection only once it is up; otherwise the previous one stays
  /// (including continuous recording and fault hunting), and an [AddonException] with the reason is
  /// returned.
  static Future<Map<String, Object?>> configure(Map<String, Object?> changes, {bool probe = false}) => impl.addonPut(
    'api/bus',
    {...changes, if (probe) 'probe': true},
    // Probe connection: the server waits for the gateway (up to 5 s, longer for IP Secure).
    timeout: probe ? const Duration(seconds: 30) : null,
  );

  /// Error message of the server from a response with an error status (`{error, problem}`),
  /// otherwise `null`.
  static AddonException? errorOf(List<int> body) {
    try {
      final j = jsonDecode(utf8.decode(body));
      if (j is Map && j['error'] is String) {
        final problem = j['problem'];
        return AddonException(j['error'] as String, problem: problem is String ? problem : null);
      }
    } on FormatException {
      // not JSON: generic message
    }
    return null;
  }

  /// Long-term analysis of the history over the last [days] days.
  static Future<Map<String, Object?>> stats(int days) => impl.addonGet('api/bus/stats?days=$days');

  /// Recording outages within the period.
  static Future<List<Object?>> outages(DateTime from, DateTime to, {String? installation}) => impl.addonGetList(
    'api/bus/availability?from=${from.millisecondsSinceEpoch}&to=${to.millisecondsSinceEpoch}'
    '${installation == null ? '' : '&installation=$installation'}',
  );

  /// Unexpected server restarts in the last 30 days (for the diagnostics package).
  static Future<List<Object?>> restarts() => impl.addonGetList('api/restarts');

  // --- Installation report (box and add-on) --------------------------------------

  /// Settings, status and list of reports (see `server/lib/src/report.dart`).
  static Future<Map<String, Object?>> report() => impl.addonGet('api/report');
  static Future<Map<String, Object?>> configureReport(Map<String, Object?> changes) =>
      impl.addonPut('api/report', changes);
  static Future<Map<String, Object?>> readReport(String id) => impl.addonGet('api/report/$id');

  /// Interim state of the current period.
  static Future<Map<String, Object?>> generateReport() async =>
      (await impl.addonPost('api/report/generate', const {}))! as Map<String, Object?>;

  /// Test notification to the selected target: `{ok, error}`.
  static Future<Map<String, Object?>> testReportNotification() async =>
      (await impl.addonPost('api/report/test', const {}))! as Map<String, Object?>;

  /// Next maintenance date from the customer file (date only).
  static Future<void> setMaintenanceDue(DateTime? due) =>
      impl.addonPost('api/report/maintenance', {'due': due?.millisecondsSinceEpoch});

  // --- Data export (box and add-on) ----------------------------------------------

  /// Settings and status (see `server/lib/src/exporter.dart`).
  static Future<Map<String, Object?>> exportStatus() => impl.addonGet('api/export');
  static Future<Map<String, Object?>> configureExport(Map<String, Object?> changes) =>
      impl.addonPut('api/export', changes);

  /// Probe InfluxDB: `{ok, error}`.
  static Future<Map<String, Object?>> testExport() async =>
      (await impl.addonPost('api/export/test', const {}))! as Map<String, Object?>;

  /// The server's history from [from] to [to] (at most 31 days) as an ETS group monitor file
  /// (`CommunicationLog`, readable by Home Assistant's KNX integration, SpectrumKNX and the ETS).
  /// In the browser the download goes straight to disk and the result is `null`; natively it
  /// returns the file for saving.
  static Future<Uint8List?> etsHistory(DateTime from, DateTime to, {String? installation}) => impl.addonDownload(
    'api/export/ets-xml?from=${from.millisecondsSinceEpoch}&to=${to.millisecondsSinceEpoch}'
    '${installation == null ? '' : '&installation=${Uri.encodeQueryComponent(installation)}'}',
    etsHistoryFileName(from, to),
  );

  /// The server's whole history as a zip with one ETS file per day (SpectrumKNX imports it in one
  /// go). In the browser straight to disk (`null`), natively as bytes; reading weeks of history on
  /// the box can take minutes.
  static Future<Uint8List?> etsHistoryAll({String? installation}) => impl.addonDownload(
    'api/export/ets-xml?all=1'
    '${installation == null ? '' : '&installation=${Uri.encodeQueryComponent(installation)}'}',
    etsHistoryAllFileName(DateTime.now()),
    timeout: const Duration(minutes: 30),
  );

  /// File name of [etsHistoryAll]: `knx-monitor-history-<today>.zip`.
  static String etsHistoryAllFileName(DateTime now) =>
      'knx-monitor-history-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.zip';

  /// File name of [etsHistory], like the server's: `knx-monitor-<first day>-<last day>.xml`.
  static String etsHistoryFileName(DateTime from, DateTime to) {
    String day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return 'knx-monitor-${day(from)}-${day(to.subtract(const Duration(microseconds: 1)))}.xml';
  }

  /// Telegrams of [addresses] (with their DPT for thinning) between [from] and [to] from the
  /// server's history, at most 31 days, already thinned to a few thousand per address (see
  /// `server/lib/src/history_query.dart`). The last value before [from] comes first.
  static Future<Map<int, List<Telegram>>> historyTelegrams(Map<int, Dpt?> addresses, DateTime from, DateTime to) async {
    final a = [
      for (final MapEntry(key: address, value: dpt) in addresses.entries)
        dpt == null ? '$address' : '$address:${dpt.main}${dpt.sub == null ? '' : '.${dpt.sub}'}',
    ].join(',');
    final j = await impl.addonGet(
      'api/bus/telegrams?a=$a&from=${from.millisecondsSinceEpoch}&to=${to.millisecondsSinceEpoch}',
    );
    final telegrams = j['telegrams'] as Map<String, Object?>? ?? const {};
    return {
      for (final MapEntry(:key, :value) in telegrams.entries)
        ?int.tryParse(key): [
          for (final line in value as List<Object?>? ?? const []) Telegram.fromJson(line! as Map<String, Object?>),
        ],
    };
  }

  /// Grafana template (`prometheus` or `influxdb`).
  static Future<Map<String, Object?>> grafanaTemplate(String kind) => impl.addonGet('api/export/grafana?kind=$kind');

  // --- KNX box only ------------------------------------------------------------

  /// Name, role (`admin`/`device`) and clock of the box.
  static Future<Map<String, Object?>> boxInfo() => impl.addonGet('api/box');

  /// Offers this device's time. Result: `set`, `ok`, `differs` (then ask and retry with [force]) or
  /// `unsupported`.
  static Future<Map<String, Object?>> offerTime({bool force = false}) async =>
      (await impl.addonPost('api/box/time', {'epochMs': DateTime.now().millisecondsSinceEpoch, 'force': force}))
          as Map<String, Object?>;

  /// Paired devices (admin only).
  static Future<List<Object?>> boxDevices() => impl.addonGetList('api/box/devices');

  /// Blocks a device, `*` for all.
  static Future<void> revokeDevice(String id) => impl.addonPost('api/box/devices/revoke', {'id': id});

  /// [current]: the box password as it is now; the box asks for it except
  /// while the sticker password must be replaced.
  static Future<void> changeBoxPassword(String password, {String? current}) =>
      impl.addonPost('api/box/password', {'password': password, 'current': ?current});

  /// Change the box's Wi-Fi password; the box then disconnects everyone from its Wi-Fi.
  static Future<void> changeBoxWifi(String password) => impl.addonPost('api/box/wifi', {'password': password});

  /// Whether the box responds at [link]. Also verifies the certificate from the link.
  static Future<bool> reachable(BoxLink link) => impl.addonReachable(link);

  /// Allow or block access over the cable (otherwise only on the box Wi-Fi).
  static Future<void> setBoxLanAccess(bool enabled) => impl.addonPost('api/box/lan', {'enabled': enabled});

  /// KNX HAT (kBerry): system check, current step and last report.
  static Future<Map<String, Object?>> hatStatus() => impl.addonGet('api/box/hat');

  /// Starts the KNX HAT check with [seconds] of listening per step (admin only).
  static Future<void> startHatProbe(int seconds) => impl.addonPost('api/box/hat', {'seconds': seconds});

  /// Gateways the box finds on its network cable: `{host, port, dibs}`.
  static Future<List<Object?>> discover() => impl.addonGetList('api/discover');

  /// Files in the box's data folder (project, keyring, history).
  static Future<Uint8List?> getFile(String path) => impl.addonGetFile(path);
  static Future<void> putFile(String path, List<int> bytes) => impl.addonPutFile(path, bytes);
  static Future<List<Object?>> listFiles(String dir) => impl.addonGetList('api/files/$dir/');

  // --- Installations (box; exactly one in the add-on) -----------------------------

  /// `{active: id, list: [{id, name, created, active}]}`.
  static Future<Map<String, Object?>> installations() => impl.addonGet('api/installations');

  /// Creates an installation with the app's ID (does not switch).
  static Future<void> createInstallation(String id, String name) =>
      impl.addonPost('api/installations', {'id': id, 'name': name});

  /// The box records into [id] from now on (bus connection, project, history).
  static Future<void> activateInstallation(String id) => impl.addonPost('api/installations/active', {'id': id});

  static Future<void> renameInstallation(String id, String name) =>
      impl.addonPatch('api/installations/$id', {'name': name});

  /// Deletes a (non-active) installation including its history on the box.
  static Future<void> deleteInstallation(String id) => impl.addonDelete('api/installations/$id');

  /// Read-only: files of an installation (also a non-active one), e.g. its history.
  static Future<Uint8List?> getInstallationFile(String id, String path) =>
      impl.addonGetFile(path, base: 'api/installations/$id/files/');
  static Future<List<Object?>> listInstallationFiles(String id, String dir) =>
      impl.addonGetList('api/installations/$id/files/$dir/');

  /// Pairs with the box password (from the sticker) and returns the device access.
  static Future<String> pairBox(BoxLink link, String password, String deviceName) =>
      impl.addonPairBox(link, password, deviceName);
}

/// Binary messages with the add-on server (see BusService in the server).
abstract class AddonSocket {
  Stream<Uint8List> get messages;
  void send(List<int> data);
  void close();
}

class AddonException implements Exception {
  const AddonException(this.message, {this.problem, this.status});
  final String message;

  /// Known reason for a connection error from the server (name of a `ConnectProblem`), otherwise
  /// `null`.
  final String? problem;

  /// HTTP status, if the server responded and nothing more specific is known.
  final int? status;
  @override
  String toString() => message;
}
