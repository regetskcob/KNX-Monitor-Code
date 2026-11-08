/// Grafana template for the data export, kept as data in the server: this way it
/// ships with the add-on and the box without its own path in image and package.
///
/// [kind] `prometheus` (default) or `influxdb` (Flux). On import, Grafana asks
/// for the data source (`__inputs`).
Map<String, Object?> grafanaDashboard(String kind) {
  final influx = kind == 'influxdb';
  final datasource = influx ? r'${DS_INFLUXDB}' : r'${DS_PROMETHEUS}';

  Map<String, Object?> target(String query) => influx
      ? {
          'query': query,
          'refId': 'A',
          'datasource': {'uid': datasource},
        }
      : {
          'expr': query,
          'refId': 'A',
          'legendFormat': '__auto',
          'datasource': {'uid': datasource},
        };

  String flux(String measurement, String field) =>
      'from(bucket: v.defaultBucket)\n'
      '  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)\n'
      '  |> filter(fn: (r) => r._measurement == "$measurement" and r._field == "$field")\n';

  var id = 0;
  Map<String, Object?> panel(String title, String type, String query, int x, int y, {int w = 12, String? unit}) => {
    'id': ++id,
    'title': title,
    'type': type,
    'datasource': {'uid': datasource},
    'gridPos': {'h': 8, 'w': w, 'x': x, 'y': y},
    'targets': [target(query)],
    'fieldConfig': {
      'defaults': {'unit': ?unit},
      'overrides': const <Object?>[],
    },
  };

  final panels = influx
      ? [
          panel('Bus connected', 'stat', '${flux('knx_monitor_bus', 'connected')}  |> last()', 0, 0, w: 6),
          panel(
            'Telegrams per minute',
            'timeseries',
            '${flux('knx_monitor_bus', 'telegrams_total')}'
                '  |> derivative(unit: 1m, nonNegative: true)',
            6,
            0,
            w: 18,
          ),
          panel(
            'Repeats per minute',
            'timeseries',
            '${flux('knx_monitor_bus', 'repeats_total')}'
                '  |> derivative(unit: 1m, nonNegative: true)',
            0,
            8,
          ),
          panel('Dropped by the recorder', 'timeseries', flux('knx_monitor_bus', 'dropped_total'), 12, 8),
          panel('Group values (with values enabled)', 'timeseries', flux('knx_monitor_group', 'value'), 0, 16, w: 24),
        ]
      : [
          panel('Bus connected', 'stat', 'knx_monitor_connected', 0, 0, w: 6),
          panel('Telegrams per minute', 'timeseries', 'rate(knx_monitor_telegrams_total[5m]) * 60', 6, 0, w: 18),
          panel('Repeats per minute', 'timeseries', 'rate(knx_monitor_repeats_total[5m]) * 60', 0, 8),
          panel(
            'Seconds since the last telegram',
            'timeseries',
            'time() - knx_monitor_last_telegram_timestamp_seconds',
            12,
            8,
            unit: 's',
          ),
          panel(
            'Dropped telegrams',
            'timeseries',
            'knx_monitor_recorder_dropped_total + knx_monitor_export_dropped_total',
            0,
            16,
          ),
          panel(
            'Bus monitor frames per minute (KNX HAT)',
            'timeseries',
            'rate(knx_monitor_busmon_frames_total[5m]) * 60',
            12,
            16,
          ),
          panel(
            'Most active senders (with values enabled)',
            'timeseries',
            'topk(10, rate(knx_monitor_sender_telegrams_total[1h]))',
            0,
            24,
          ),
          panel(
            'Most active group addresses (with values enabled)',
            'timeseries',
            'topk(10, rate(knx_monitor_group_telegrams_total[1h]))',
            12,
            24,
          ),
          panel('Group values (with values enabled)', 'timeseries', 'knx_monitor_group_value', 0, 32, w: 24),
        ];

  return {
    '__inputs': [
      {
        'name': influx ? 'DS_INFLUXDB' : 'DS_PROMETHEUS',
        'label': influx ? 'InfluxDB' : 'Prometheus',
        'type': 'datasource',
        'pluginId': influx ? 'influxdb' : 'prometheus',
      },
    ],
    'title': 'Busclear',
    'uid': influx ? 'knx-monitor-influxdb' : 'knx-monitor-prometheus',
    'tags': const ['knx', 'knx-monitor'],
    'timezone': 'browser',
    'refresh': '1m',
    'schemaVersion': 39,
    'version': 1,
    'time': const {'from': 'now-24h', 'to': 'now'},
    'panels': panels,
  };
}
