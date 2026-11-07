import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../l10n/locale_controller.dart';
import '../model/data_export.dart';
import '../platform/addon.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'plant_report_screen.dart' show plantNotifyError;
import '../platform/secret_clipboard.dart';

/// Data export to InfluxDB and Prometheus with a Grafana template. Off by
/// default; credentials only go to the server and never come back.
class DataExportScreen extends StatefulWidget {
  const DataExportScreen({super.key, this.client = const DataExportClient()});

  final DataExportClient client;

  @override
  State<DataExportScreen> createState() => _DataExportScreenState();
}

class _DataExportScreenState extends State<DataExportScreen> {
  DataExportState? _state;
  String? _error;
  bool _busy = false;
  bool _prometheus = false;
  bool _influx = false;
  bool _values = false;
  final _port = TextEditingController();
  final _url = TextEditingController();
  final _org = TextEditingController();
  final _bucket = TextEditingController();
  final _database = TextEditingController();
  final _token = TextEditingController();
  final _interval = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final c in [_port, _url, _org, _bucket, _database, _token, _interval]) {
      c.dispose();
    }
    super.dispose();
  }

  void _apply(DataExportState st) {
    _state = st;
    _error = null;
    _prometheus = st.prometheus;
    _influx = st.influx;
    _values = st.includeValues;
    _port.text = '${st.port}';
    _url.text = st.influxUrl;
    _org.text = st.influxOrg;
    _bucket.text = st.influxBucket;
    _database.text = st.influxDatabase;
    _interval.text = '${st.intervalSeconds}';
    _token.clear();
  }

  Future<void> _load() async {
    try {
      final st = await widget.client.load();
      if (mounted) setState(() => _apply(st));
    } on AddonException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Map<String, Object?> get _changes => {
    'includeValues': _values,
    'prometheus': _prometheus,
    'prometheusPort': int.tryParse(_port.text.trim()) ?? 9464,
    'influx': _influx,
    'influxUrl': _url.text.trim(),
    'influxOrg': _org.text.trim(),
    'influxBucket': _bucket.text.trim(),
    'influxDatabase': _database.text.trim(),
    'intervalSeconds': int.tryParse(_interval.text.trim()) ?? 30,
    if (_token.text.isNotEmpty) 'influxToken': _token.text,
  };

  /// `true` if the server accepted it.
  Future<bool> _save() async {
    setState(() => _busy = true);
    try {
      final st = await widget.client.save(_changes);
      if (!mounted) return true;
      setState(() => _apply(st));
      if (st.generatedToken case final token?) await _showToken(token);
      return true;
    } on AddonException catch (e) {
      if (mounted) setState(() => _error = e.message.startsWith('influx') ? s.plantNotifyErrorInvalid : e.message);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showToken(String token) => showAdaptiveDialog<void>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: Text(s.dataExportTokenTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(s.dataExportTokenBody),
          const SizedBox(height: Gap.item),
          SelectableText(token, style: context.hzTheme.data),
        ],
      ),
      actions: [
        TextButton(onPressed: () => unawaited(copySecret(token)), child: Text(s.dataExportCopy)),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.dataExportClose)),
      ],
    ),
  );

  Future<void> _test() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await _save()) return;
    try {
      final error = await widget.client.test();
      messenger.showSnackBar(
        SnackBar(content: Text(error == null ? s.dataExportTestOk : s.plantTestFailed(plantNotifyError(error)))),
      );
    } on AddonException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(s.plantTestFailed(e.message))));
    }
  }

  Future<void> _grafana(String kind) async {
    try {
      final json = await widget.client.grafana(kind);
      if (!mounted) return;
      await saveBytes(
        context,
        utf8.encode(const JsonEncoder.withIndent('  ').convert(json)),
        'knx-monitor-grafana-$kind.json',
        mimeType: 'application/json',
      );
    } on AddonException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool obscure = false,
    TextInputType? keyboard,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(top: Gap.item),
    child: HorizontField(
      label: label,
      child: TextField(
        controller: controller,
        obscureText: obscure,
        autocorrect: false,
        enableSuggestions: !obscure,
        keyboardType: keyboard,
        decoration: InputDecoration(hintText: hint),
      ),
    ),
  );

  /// Read-only state of the MQTT telegram stream (issue #11): switched in the
  /// add-on options or environment, so the page only reports, with a reason
  /// for every telegram that stays off the broker.
  List<Widget> _mqttLines(MqttTelegramState mqtt, TextStyle? muted) {
    if (!mqtt.enabled) return [Text(s.dataExportMqttOff, style: muted)];
    final lines = <Widget>[
      HorizontStatusLine(
        mqtt.connected ? HorizontStatus.positive : HorizontStatus.warning,
        mqtt.connected ? s.dataExportMqttOn(mqtt.sent, mqtt.dropped) : s.dataExportMqttDisconnected,
      ),
      if (mqtt.secure) HorizontStatusLine(HorizontStatus.warning, s.dataExportMqttSecureOn),
      if (mqtt.secureSkipped > 0)
        HorizontStatusLine(HorizontStatus.info, s.dataExportMqttSecureSkipped(mqtt.secureSkipped)),
      if (mqtt.undecrypted > 0)
        HorizontStatusLine(HorizontStatus.warning, s.dataExportMqttUndecrypted(mqtt.undecrypted)),
    ];
    return [
      for (final (i, line) in lines.indexed) ...[if (i > 0) const SizedBox(height: Gap.item), line],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final muted = theme.textTheme.bodySmall?.copyWith(color: hz.textMuted);
    final st = _state;
    return Scaffold(
      appBar: AppBar(title: Text(s.dataExportTitle)),
      body: st == null
          ? Center(child: _error == null ? const CircularProgressIndicator.adaptive() : Text(_error!))
          : ListView(
              padding: EdgeInsets.all(Gap.gutterFor(MediaQuery.sizeOf(context).width)),
              children: [
                Text(s.dataExportIntro, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
                const SizedBox(height: Gap.section),
                if (_error != null) ...[
                  HorizontStatusLine(HorizontStatus.critical, _error!),
                  const SizedBox(height: Gap.item),
                ],
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.dataExportValues),
                  subtitle: Text(s.dataExportValuesHint),
                  value: _values,
                  onChanged: _busy ? null : (v) => setState(() => _values = v),
                ),
                const Divider(height: Lines.hairline),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.dataExportPrometheus),
                  value: _prometheus,
                  onChanged: _busy ? null : (v) => setState(() => _prometheus = v),
                ),
                if (_prometheus) ...[
                  _field(s.dataExportPort, _port, keyboard: TextInputType.number),
                  const SizedBox(height: Gap.item),
                  Text(s.dataExportPortHint(_port.text), style: muted),
                  if (st.hasPrometheusToken) Text(s.dataExportTokenSet, style: muted),
                  if (st.prometheusError != null) ...[
                    const SizedBox(height: Gap.item),
                    HorizontStatusLine(HorizontStatus.critical, s.dataExportBindError),
                  ],
                ],
                const Divider(height: Lines.hairline),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.dataExportInflux),
                  value: _influx,
                  onChanged: _busy ? null : (v) => setState(() => _influx = v),
                ),
                if (_influx) ...[
                  _field(s.dataExportInfluxUrl, _url, keyboard: TextInputType.url, hint: 'http://192.168.1.10:8086'),
                  _field(s.dataExportInfluxOrg, _org),
                  _field(s.dataExportInfluxBucket, _bucket),
                  _field(s.dataExportInfluxDatabase, _database),
                  _field(
                    s.dataExportInfluxToken,
                    _token,
                    obscure: true,
                    hint: st.hasInfluxToken ? s.plantNotifyTokenSet : s.plantNotifyTokenOptional,
                  ),
                  _field(s.dataExportInterval, _interval, keyboard: TextInputType.number),
                  if (st.influxError case final code?) ...[
                    const SizedBox(height: Gap.item),
                    HorizontStatusLine(HorizontStatus.critical, s.plantTestFailed(plantNotifyError(code))),
                  ],
                ],
                const SizedBox(height: Gap.section),
                Wrap(
                  spacing: Gap.item,
                  runSpacing: Gap.item,
                  children: [
                    FilledButton(onPressed: _busy ? null : _save, child: Text(s.dataExportSave)),
                    if (_influx) OutlinedButton(onPressed: _busy ? null : _test, child: Text(s.dataExportTest)),
                  ],
                ),
                const SizedBox(height: Gap.section),
                Kennung(s.dataExportGrafana),
                const SizedBox(height: Gap.item),
                Text(s.dataExportGrafanaHint, style: muted),
                const SizedBox(height: Gap.item),
                Wrap(
                  spacing: Gap.item,
                  runSpacing: Gap.item,
                  children: [
                    OutlinedButton(onPressed: () => _grafana('prometheus'), child: Text(s.dataExportGrafanaPrometheus)),
                    OutlinedButton(onPressed: () => _grafana('influxdb'), child: Text(s.dataExportGrafanaInflux)),
                  ],
                ),
                if (st.mqttTelegrams case final mqtt?) ...[
                  const SizedBox(height: Gap.section),
                  Kennung(s.dataExportMqtt),
                  const SizedBox(height: Gap.item),
                  ..._mqttLines(mqtt, muted),
                ],
              ],
            ),
    );
  }
}
