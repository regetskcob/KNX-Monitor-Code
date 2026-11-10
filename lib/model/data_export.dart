import 'package:flutter/foundation.dart';

import '../platform/addon.dart';

/// State of the data export on the server (`server/lib/src/exporter.dart`).
/// Tokens never come back, only whether one is set; a newly generated
/// Prometheus token exactly once as [generatedToken].
@immutable
class DataExportState {
  const DataExportState(this.json);
  final Map<String, Object?> json;

  Map<String, Object?> get settings => (json['settings'] as Map?)?.cast<String, Object?>() ?? const {};
  bool get includeValues => settings['includeValues'] == true;
  bool get prometheus => settings['prometheus'] == true;
  int get port => settings['prometheusPort'] as int? ?? 9464;
  bool get hasPrometheusToken => settings['hasPrometheusToken'] == true;
  bool get influx => settings['influx'] == true;
  String get influxUrl => settings['influxUrl'] as String? ?? '';
  String get influxOrg => settings['influxOrg'] as String? ?? '';
  String get influxBucket => settings['influxBucket'] as String? ?? '';
  String get influxDatabase => settings['influxDatabase'] as String? ?? '';
  bool get hasInfluxToken => settings['hasInfluxToken'] == true;
  int get intervalSeconds => settings['intervalSeconds'] as int? ?? 30;
  String? get prometheusError => json['prometheusError'] as String?;
  String? get influxError => json['influxError'] as String?;
  String? get generatedToken => json['generatedToken'] as String?;

  /// MQTT telegram stream (issue #11); `null` when the server has no broker.
  MqttTelegramState? get mqttTelegrams => switch (json['mqttTelegrams']) {
    final Map<Object?, Object?> m => MqttTelegramState(m.cast<String, Object?>()),
    _ => null,
  };
}

/// State of "every telegram to MQTT" on the server (`MqttBridge.telegramStatus`).
@immutable
class MqttTelegramState {
  const MqttTelegramState(this.json);
  final Map<String, Object?> json;

  bool get enabled => json['enabled'] == true;
  bool get connected => json['connected'] == true;

  /// Whether decrypted KNX Data Secure telegrams are sent too.
  bool get secure => json['secure'] == true;
  int get sent => json['sent'] as int? ?? 0;
  int get dropped => json['dropped'] as int? ?? 0;

  /// Secured telegrams left out because [secure] is off.
  int get secureSkipped => json['secureSkipped'] as int? ?? 0;

  /// Secured telegrams left out because the server could not decrypt them.
  int get undecrypted => json['undecrypted'] as int? ?? 0;

  /// Whether the cEMI frame and further raw fields are sent too.
  bool get raw => json['raw'] == true;

  /// Whether only raw data goes out (no names, DPT, value, unit).
  bool get rawOnly => json['rawOnly'] == true;

  /// Whether the last value per address also goes to `knx_monitor/value/…`, retained.
  bool get retainValues => json['retainValues'] == true;

  /// Values sent to the value topics since the server started.
  int get valuesSent => json['valuesSent'] as int? ?? 0;

  /// Group address filter as set on the server, e.g. `1/#,3/2/#`; empty = all.
  String get filter => json['filter'] as String? ?? '';

  /// Running number of the last telegram due to be sent; `null` on servers
  /// before the field existed.
  int? get seq => json['seq'] as int?;
}

/// Talks to the server; replaceable in tests.
class DataExportClient {
  const DataExportClient();

  Future<DataExportState> load() async => DataExportState(await Addon.exportStatus());
  Future<DataExportState> save(Map<String, Object?> changes) async =>
      DataExportState(await Addon.configureExport(changes));

  /// `null` = delivered, otherwise the reason from the server.
  Future<String?> test() async {
    final result = await Addon.testExport();
    return result['ok'] == true ? null : '${result['error'] ?? 'network'}';
  }

  Future<Map<String, Object?>> grafana(String kind) => Addon.grafanaTemplate(kind);
}
