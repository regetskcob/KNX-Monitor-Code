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
import 'figure_box.dart';
import 'form_columns.dart';
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

  // MQTT telegram stream (issue #11), applied on its own (`PUT /api/export/mqtt`).
  bool _mqttOn = false;
  bool _mqttRaw = false;
  bool _mqttRawOnly = false;
  bool _mqttRetain = false;
  bool _mqttRepeats = false;
  bool _mqttSecure = false;
  final _mqttFilter = TextEditingController();

  @override
  void initState() {
    super.initState();
    // The plain-HTTP hint depends on what is typed.
    _url.addListener(_refresh);
    _token.addListener(_refresh);
    unawaited(_load());
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// Whether the InfluxDB token would travel unencrypted: a plain `http://` address and a token
  /// (typed now or stored on the server).
  bool _tokenInPlain(DataExportState st) =>
      _url.text.trim().toLowerCase().startsWith('http://') && (_token.text.isNotEmpty || st.hasInfluxToken);

  @override
  void dispose() {
    for (final c in [_port, _url, _org, _bucket, _database, _token, _interval, _mqttFilter]) {
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
    if (st.mqttTelegrams case final mqtt?) _applyMqtt(mqtt);
  }

  void _applyMqtt(MqttTelegramState mqtt) {
    _mqttOn = mqtt.enabled;
    _mqttRaw = mqtt.raw;
    _mqttRawOnly = mqtt.rawOnly;
    _mqttRetain = mqtt.retainValues;
    _mqttRepeats = mqtt.repeats;
    _mqttSecure = mqtt.secure;
    _mqttFilter.text = mqtt.filter;
  }

  bool _mqttChanged(MqttTelegramState mqtt) =>
      _mqttOn != mqtt.enabled ||
      _mqttRaw != mqtt.raw ||
      _mqttRawOnly != mqtt.rawOnly ||
      _mqttRetain != mqtt.retainValues ||
      _mqttRepeats != mqtt.repeats ||
      _mqttSecure != mqtt.secure ||
      _mqttFilter.text.trim() != mqtt.filter;

  /// Applies the stream settings, or goes back to the server's default with [reset]. The other
  /// fields of the page keep what was typed.
  Future<void> _saveMqtt({bool reset = false}) async {
    setState(() => _busy = true);
    try {
      final st = await widget.client.saveMqtt(
        reset
            ? const {'reset': true}
            : {
                'enabled': _mqttOn,
                'raw': _mqttRaw,
                'rawOnly': _mqttRaw && _mqttRawOnly,
                'retainValues': _mqttRetain,
                'repeats': _mqttRepeats,
                'secure': _mqttSecure,
                'filter': _mqttFilter.text.trim(),
              },
      );
      if (!mounted) return;
      setState(() {
        _state = st;
        _error = null;
        if (st.mqttTelegrams case final mqtt?) _applyMqtt(mqtt);
      });
    } on AddonException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Asks before bus data leaves for the broker; `true` to go ahead.
  Future<bool> _confirmMqtt(String title, String body) async =>
      await showAdaptiveDialog<bool>(
        context: context,
        builder: (context) => AlertDialog.adaptive(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.commonCancel)),
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(s.dataExportMqttConfirm)),
          ],
        ),
      ) ??
      false;

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
    String? help,
  }) => HorizontField(
    label: label,
    help: help,
    child: TextField(
      controller: controller,
      style: context.hzTheme.field,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: !obscure,
      keyboardType: keyboard,
      decoration: InputDecoration(hintText: hint),
    ),
  );

  /// A destination in the card of counters and values: its switch and, while it is on, its
  /// fields and messages below.
  Widget _target(String title, bool value, ValueChanged<bool> onChanged, List<Widget> details) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SwitchRow(title: title, value: value, onChanged: _busy ? null : onChanged),
      if (value)
        Padding(
          padding: const EdgeInsets.only(bottom: Gap.card),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: Gap.inner, children: details),
        ),
    ],
  );

  /// Counters and values for Prometheus and InfluxDB, with the button that saves exactly these.
  List<Widget> _metrics(DataExportState st, TextStyle? muted) => [
    SectionHead(s.dataExportMetrics),
    RowCard(
      children: [
        SwitchRow(
          title: s.dataExportValues,
          meta: s.dataExportValuesHint,
          value: _values,
          onChanged: _busy ? null : (v) => setState(() => _values = v),
        ),
        _target(s.dataExportPrometheus, _prometheus, (v) => setState(() => _prometheus = v), [
          _field(s.dataExportPort, _port, keyboard: TextInputType.number, help: s.dataExportPortHint(_port.text)),
          if (st.hasPrometheusToken) Text(s.dataExportTokenSet, style: muted),
          if (st.prometheusError != null) HorizontStatusLine(HorizontStatus.critical, s.dataExportBindError),
        ]),
        _target(s.dataExportInflux, _influx, (v) => setState(() => _influx = v), [
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
          if (_tokenInPlain(st)) HorizontStatusLine(HorizontStatus.info, s.dataExportInfluxPlain),
          _field(s.dataExportInterval, _interval, keyboard: TextInputType.number),
          if (st.influxError case final code?)
            HorizontStatusLine(HorizontStatus.critical, s.plantTestFailed(plantNotifyError(code))),
        ]),
      ],
    ),
    const SizedBox(height: Gap.inner),
    Wrap(
      spacing: Gap.item,
      runSpacing: Gap.item,
      children: [
        FilledButton(onPressed: _busy ? null : _save, child: Text(s.dataExportSave)),
        if (_influx) OutlinedButton(onPressed: _busy ? null : _test, child: Text(s.dataExportTest)),
      ],
    ),
  ];

  List<Widget> _grafanaTemplates(TextStyle? muted) => [
    SectionHead(s.dataExportGrafana),
    SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Gap.inner,
        children: [
          Text(s.dataExportGrafanaHint, style: muted),
          Wrap(
            spacing: Gap.item,
            runSpacing: Gap.item,
            children: [
              OutlinedButton(onPressed: () => _grafana('prometheus'), child: Text(s.dataExportGrafanaPrometheus)),
              OutlinedButton(onPressed: () => _grafana('influxdb'), child: Text(s.dataExportGrafanaInflux)),
            ],
          ),
        ],
      ),
    ),
  ];

  /// The MQTT telegram stream: its settings on servers that let the app change it, then its
  /// state.
  List<Widget> _mqtt(MqttTelegramState mqtt, TextStyle? muted) {
    final lines = _mqttLines(mqtt, muted);
    return [
      SectionHead(s.dataExportMqtt),
      if (mqtt.configurable) ..._mqttSettings(mqtt, muted),
      if (lines.isNotEmpty) ...[
        if (mqtt.configurable) const SizedBox(height: Gap.inner),
        SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: Gap.item, children: lines),
        ),
      ],
    ];
  }

  /// Settings of the MQTT telegram stream, on servers that let the app change it.
  List<Widget> _mqttSettings(MqttTelegramState mqtt, TextStyle? muted) {
    Widget toggle(String title, String? hint, bool value, ValueChanged<bool> onChanged) =>
        SwitchRow(title: title, meta: hint, value: value, onChanged: _busy ? null : onChanged);
    return [
      RowCard(
        children: [
          toggle(s.dataExportMqttSwitch, s.dataExportMqttSwitchHint, _mqttOn, (v) async {
            if (v && !mqtt.enabled) {
              if (!await _confirmMqtt(s.dataExportMqttConfirmTitle, s.dataExportMqttConfirmBody)) return;
              // KNX Secure telegrams may already be switched on in the options or environment
              // while the stream is off: they need their own yes, or they stay out.
              if (_mqttSecure &&
                  !await _confirmMqtt(s.dataExportMqttSecureConfirmTitle, s.dataExportMqttSecureConfirmBody)) {
                _mqttSecure = false;
              }
            }
            if (mounted) setState(() => _mqttOn = v);
          }),
          if (_mqttOn) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.inner),
              child: _field(
                s.dataExportMqttFilter,
                _mqttFilter,
                hint: '1/#,3/2/#,4/1/7',
                help: s.dataExportMqttFilterHint,
              ),
            ),
            toggle(s.dataExportMqttRetainSwitch, s.dataExportMqttRetainHint, _mqttRetain, (v) {
              setState(() => _mqttRetain = v);
            }),
            toggle(s.dataExportMqttRaw, s.dataExportMqttRawHint, _mqttRaw, (v) => setState(() => _mqttRaw = v)),
            if (_mqttRaw)
              toggle(s.dataExportMqttRawOnly, s.dataExportMqttRawOnlyHint, _mqttRawOnly, (v) {
                setState(() => _mqttRawOnly = v);
              }),
            toggle(s.dataExportMqttRepeats, null, _mqttRepeats, (v) => setState(() => _mqttRepeats = v)),
            toggle(s.dataExportMqttSecureSwitch, s.dataExportMqttSecureHint, _mqttSecure, (v) async {
              if (v &&
                  !mqtt.secure &&
                  !await _confirmMqtt(s.dataExportMqttSecureConfirmTitle, s.dataExportMqttSecureConfirmBody)) {
                return;
              }
              if (mounted) setState(() => _mqttSecure = v);
            }),
          ],
        ],
      ),
      const SizedBox(height: Gap.item),
      Text(mqtt.fromApp ? s.dataExportMqttSourceApp : s.dataExportMqttSourceDefault, style: muted),
      const SizedBox(height: Gap.inner),
      Wrap(
        spacing: Gap.item,
        runSpacing: Gap.item,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton(onPressed: _busy || !_mqttChanged(mqtt) ? null : _saveMqtt, child: Text(s.dataExportMqttSave)),
          if (mqtt.fromApp)
            OutlinedButton(onPressed: _busy ? null : () => _saveMqtt(reset: true), child: Text(s.dataExportMqttReset)),
          if (_mqttChanged(mqtt)) Text(s.dataExportMqttUnsaved, style: muted),
        ],
      ),
    ];
  }

  /// How Home Assistant gets its entities (issue #12): from the Busclear integration or from
  /// the MQTT device. Nothing on servers that do not report it.
  ///
  /// Below it one line on the health check the server runs for Home Assistant: on or off, and
  /// when it last ran. The findings themselves are in Home Assistant, not here.
  List<Widget> _homeAssistantLines(MqttTelegramState? mqtt, ServerHealthCheckState? health) {
    final lines = <Widget>[
      if (mqtt?.discovery case final discovery?)
        switch ((mqtt!.integration, mqtt.connected, discovery)) {
          (true, _, _) => HorizontStatusLine(HorizontStatus.positive, s.dataExportHaIntegration),
          (_, false, _) => HorizontStatusLine(HorizontStatus.warning, s.dataExportHaDisconnected),
          (_, _, true) => HorizontStatusLine(HorizontStatus.positive, s.dataExportHaMqttDevice),
          _ => HorizontStatusLine(HorizontStatus.info, s.dataExportHaNoDiscovery),
        },
      if (health != null)
        switch ((health.enabled, health.time)) {
          (false, _) => HorizontStatusLine(HorizontStatus.neutral, s.dataExportHaHealthOff),
          (_, null) => HorizontStatusLine(HorizontStatus.info, s.dataExportHaHealthNever),
          (_, final time?) => HorizontStatusLine(switch (health.status) {
            'ok' => HorizontStatus.positive,
            'faults' => HorizontStatus.critical,
            _ => HorizontStatus.warning,
          }, s.dataExportHaHealthRun(_when(time), health.findings)),
        },
    ];
    if (lines.isEmpty) return const [];
    return [
      SectionHead(s.dataExportHa),
      SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: Gap.item, children: lines),
      ),
    ];
  }

  /// "03:00" for today, otherwise "11.11. 03:00", as the health check writes its times.
  static String _when(DateTime t) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final clock = '${two(t.hour)}:${two(t.minute)}';
    return t.year == now.year && t.month == now.month && t.day == now.day
        ? clock
        : '${two(t.day)}.${two(t.month)}. $clock';
  }

  /// State of the MQTT telegram stream (issue #11), with a reason for every telegram that
  /// stays off the broker. On servers that cannot change it from the app, also how to switch
  /// it on.
  List<Widget> _mqttLines(MqttTelegramState mqtt, TextStyle? muted) {
    if (!mqtt.enabled) return [if (!mqtt.configurable) Text(s.dataExportMqttOff, style: muted)];
    final lines = <Widget>[
      if (mqtt.paused) HorizontStatusLine(HorizontStatus.warning, s.dataExportMqttPaused),
      HorizontStatusLine(
        mqtt.connected ? HorizontStatus.positive : HorizontStatus.warning,
        mqtt.connected ? s.dataExportMqttOn(mqtt.sent, mqtt.dropped) : s.dataExportMqttDisconnected,
      ),
      if (mqtt.seq case final seq?)
        HorizontStatusLine(
          HorizontStatus.info,
          s.dataExportMqttDetails(
            mqtt.rawOnly
                ? 'rawOnly'
                : mqtt.raw
                ? 'raw'
                : 'none',
            mqtt.filter.isEmpty ? s.dataExportMqttFilterAll : mqtt.filter,
            seq,
          ),
        ),
      if (mqtt.retainValues) HorizontStatusLine(HorizontStatus.info, s.dataExportMqttRetain(mqtt.valuesSent)),
      if (mqtt.secure) HorizontStatusLine(HorizontStatus.warning, s.dataExportMqttSecureOn),
      if (mqtt.secureSkipped > 0)
        HorizontStatusLine(HorizontStatus.info, s.dataExportMqttSecureSkipped(mqtt.secureSkipped)),
      if (mqtt.undecrypted > 0)
        HorizontStatusLine(HorizontStatus.warning, s.dataExportMqttUndecrypted(mqtt.undecrypted)),
    ];
    return lines;
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
          // Phone and narrow windows: one column in reading width. From the expanded width on
          // two card columns, and three where each still gets a column's width: what is saved
          // together stays in one column with its button.
          : LayoutBuilder(
              builder: (context, box) {
                final metrics = _metrics(st, muted);
                final grafana = _grafanaTemplates(muted);
                final mqtt = switch (st.mqttTelegrams) {
                  final mqtt? => _mqtt(mqtt, muted),
                  null => const <Widget>[],
                };
                final homeAssistant = _homeAssistantLines(st.mqttTelegrams, st.healthCheck);
                final three = box.maxWidth >= 3 * Widths.column + 2 * Gap.section + 2 * Gap.gutter;
                return FormColumns(
                  intro: [
                    Text(s.dataExportIntro, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
                    if (_error != null) ...[
                      const SizedBox(height: Gap.item),
                      HorizontStatusLine(HorizontStatus.critical, _error!),
                    ],
                  ],
                  columns: mqtt.isEmpty
                      ? [
                          metrics,
                          [...grafana, ...homeAssistant],
                        ]
                      : three
                      ? [
                          metrics,
                          mqtt,
                          [...grafana, ...homeAssistant],
                        ]
                      : [
                          [...metrics, ...grafana],
                          [...mqtt, ...homeAssistant],
                        ],
                  narrow: [...metrics, ...grafana, ...mqtt, ...homeAssistant],
                );
              },
            ),
    );
  }
}
