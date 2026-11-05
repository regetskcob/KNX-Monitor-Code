import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'atomic_file.dart';
import 'dpt_value.dart';
import 'grafana.dart';
import 'http.dart';

import 'package:knx/knx.dart';

import 'outbound.dart';

/// Settings of the data export (`export.json` in the installation). Off by
/// default; credentials never leave the server and appear in no log.
class ExportSettings {
  ExportSettings({
    this.includeValues = false,
    this.prometheus = false,
    this.prometheusPort = defaultPort,
    this.prometheusToken = '',
    this.influx = false,
    this.influxUrl = '',
    this.influxOrg = '',
    this.influxBucket = '',
    this.influxDatabase = '',
    this.influxToken = '',
    this.intervalSeconds = 30,
  });

  /// Usual port of Prometheus exporters; a separate one so `/metrics` does not
  /// depend on Ingress or the box login.
  static const defaultPort = 9464;

  /// Also group addresses, names, values and senders. Otherwise only bus counters.
  bool includeValues;

  bool prometheus;
  int prometheusPort;
  String prometheusToken;

  bool influx;
  String influxUrl;

  /// InfluxDB 2: organization and bucket. InfluxDB 1: only [influxDatabase].
  String influxOrg;
  String influxBucket;
  String influxDatabase;
  String influxToken;
  int intervalSeconds;

  factory ExportSettings.fromJson(Map<String, Object?> j) => ExportSettings(
    includeValues: j['includeValues'] == true,
    prometheus: j['prometheus'] == true,
    prometheusPort: switch (j['prometheusPort']) {
      final int p when p >= 1024 && p <= 65535 => p,
      _ => defaultPort,
    },
    prometheusToken: j['prometheusToken'] as String? ?? '',
    influx: j['influx'] == true,
    influxUrl: j['influxUrl'] as String? ?? '',
    influxOrg: j['influxOrg'] as String? ?? '',
    influxBucket: j['influxBucket'] as String? ?? '',
    influxDatabase: j['influxDatabase'] as String? ?? '',
    influxToken: j['influxToken'] as String? ?? '',
    intervalSeconds: switch (j['intervalSeconds']) {
      final int s => s.clamp(10, 3600),
      _ => 30,
    },
  );

  Map<String, Object?> toJson({bool secrets = true}) => {
    'includeValues': includeValues,
    'prometheus': prometheus,
    'prometheusPort': prometheusPort,
    'influx': influx,
    'influxUrl': influxUrl,
    'influxOrg': influxOrg,
    'influxBucket': influxBucket,
    'influxDatabase': influxDatabase,
    'intervalSeconds': intervalSeconds,
    if (secrets) ...{
      'prometheusToken': prometheusToken,
      'influxToken': influxToken,
    } else ...{
      'hasPrometheusToken': prometheusToken.isNotEmpty,
      'hasInfluxToken': influxToken.isNotEmpty,
    },
  };
}

/// Whether this peer may fetch `/metrics`. Only from the local network: private
/// ranges, CGNAT/VPN, link-local and loopback.
bool isLocalPeer(InternetAddress address) {
  if (address.type != InternetAddressType.IPv4) return address.isLoopback || address.isLinkLocal;
  final [a, b, ...] = address.rawAddress;
  return a == 10 ||
      a == 127 ||
      (a == 172 && b >= 16 && b < 32) ||
      (a == 192 && b == 168) ||
      (a == 100 && b >= 64 && b < 128) ||
      (a == 169 && b == 254);
}

/// What the export needs to know about the project and the bus.
abstract class ExportSource {
  bool get connected;
  int get recorderDropped;
  Map<String, Object?>? get busmon;
  bool get timeKnown;
  String formatGroup(int group);
  String? nameOf(int group);
  (int, int?)? dptOf(int group);
}

/// Data export to Prometheus (scraping `/metrics`, own port) and InfluxDB
/// (sends batches to the configured target).
///
/// Runs alongside: [add] works only in memory and never throws; an
/// unreachable target costs a bounded buffer, never the recording.
class DataExporter {
  DataExporter(this.data, {required this.source, void Function(String message)? log, DateTime Function()? now})
    : _log = log ?? stderr.writeln,
      _now = now ?? DateTime.now;

  final Directory data;
  final ExportSource source;
  final void Function(String message) _log;
  final DateTime Function() _now;

  /// Upper limit of the InfluxDB buffer; beyond it the oldest lines are dropped.
  static const maxBuffered = 10000;
  static const maxBatch = 5000;

  ExportSettings settings = ExportSettings();

  File get _file => File('${data.path}/export.json');

  // Counters and last values, only while the export is running.
  int telegrams = 0;
  int repeats = 0;
  DateTime? _lastTelegram;
  final _senders = <int, int>{};
  final _groups = <int, int>{};
  final _values = <int, double>{};

  final _buffer = <String>[];
  int droppedLines = 0;
  Timer? _timer;
  bool _sending = false;
  int _failures = 0;
  DateTime? _nextTry;

  HttpServer? _metrics;
  String? prometheusError;
  String? influxError;
  DateTime? influxLast;

  bool get active => settings.prometheus || settings.influx;

  /// Loads the settings and starts whatever is enabled. Corrupt file:
  /// everything off instead of guessing.
  Future<void> start() async {
    try {
      if (await _file.exists()) {
        settings = ExportSettings.fromJson(jsonDecode(await _file.readAsString()) as Map<String, Object?>);
      }
    } on Object {
      _log('export.json nicht lesbar – Datenexport bleibt aus');
      settings = ExportSettings();
    }
    await _apply();
  }

  Future<void> _apply() async {
    await _stopServices();
    if (settings.prometheus) await _bindMetrics();
    if (settings.influx) {
      _timer = Timer.periodic(Duration(seconds: settings.intervalSeconds), (_) => unawaited(flush()));
    }
    if (!active) {
      _senders.clear();
      _groups.clear();
      _values.clear();
      _buffer.clear();
    }
  }

  Future<void> _stopServices() async {
    _timer?.cancel();
    _timer = null;
    final server = _metrics;
    _metrics = null;
    await server?.close(force: true);
  }

  Future<void> stop() async {
    await _stopServices();
    // Last batch, but not at the expense of shutting down: systemd and the
    // Supervisor only wait for a limited time.
    if (settings.influx) await flush().timeout(const Duration(seconds: 3), onTimeout: () {});
  }

  /// Applies changes. Empty tokens mean "unchanged", `clearInfluxToken`
  /// deletes, and so does a new InfluxDB target without a new token (the
  /// token belongs to the old target). Without a Prometheus token one is
  /// generated and returned once,
  /// because `/metrics` never answers without one. Throws [FormatException]
  /// for an invalid target; then everything stays as it was.
  Future<String?> update(Map<String, Object?> changes) async {
    final merged = settings.toJson()..addAll(changes);
    for (final key in ['prometheusToken', 'influxToken']) {
      final value = changes[key];
      if (value is! String || value.isEmpty) {
        merged[key] = key == 'prometheusToken' ? settings.prometheusToken : settings.influxToken;
      }
    }
    final url = changes['influxUrl'];
    final newToken = changes['influxToken'] is String && (changes['influxToken']! as String).isNotEmpty;
    if (!newToken && url is String && url != settings.influxUrl) merged['influxToken'] = '';
    if (changes['clearInfluxToken'] == true) merged['influxToken'] = '';
    final next = ExportSettings.fromJson(merged);
    if (next.influx) {
      if (parseOutboundTarget(next.influxUrl) == null) throw const FormatException('influxUrl');
      final v2 = next.influxOrg.isNotEmpty && next.influxBucket.isNotEmpty;
      if (!v2 && next.influxDatabase.isEmpty) throw const FormatException('influxBucket');
    }
    String? generated;
    if (next.prometheus && next.prometheusToken.isEmpty) {
      final random = Random.secure();
      generated = base64Url.encode([for (var i = 0; i < 24; i++) random.nextInt(256)]);
      next.prometheusToken = generated;
    }
    settings = next;
    await writeAtomic(_file, text: jsonEncode(settings.toJson()));
    await _apply();
    return generated;
  }

  // --- Telegrams ----------------------------------------------------------------

  /// Telegram line in history format. Memory only; never throws.
  void add(Map<String, Object?> line) {
    if (!active) return;
    try {
      telegrams++;
      if (line['rp'] == true) repeats++;
      final micros = line['t']! as int;
      _lastTelegram = DateTime.fromMicrosecondsSinceEpoch(micros);
      if (!settings.includeValues) return;
      final source_ = line['s']! as int;
      final group = line['d']! as int;
      if (line['o'] != true) _senders[source_] = (_senders[source_] ?? 0) + 1;
      if (line['y'] == 0) return; // A read request has no value.
      _groups[group] = (_groups[group] ?? 0) + 1;
      final bytes = hexBytes(line['x'] as String? ?? '');
      final value = numericValue(source.dptOf(group), Uint8List.fromList(bytes), small: line['m'] == true);
      if (value == null || !value.isFinite) return;
      _values[group] = value;
      if (settings.influx && source.timeKnown) {
        final name = source.nameOf(group);
        _push(
          'knx_monitor_group,ga=${_tag(source.formatGroup(group))}${name == null ? '' : ',name=${_tag(name)}'} '
          'value=$value ${micros ~/ 1000}',
        );
      }
    } on Object catch (_) {
      // An odd line must not disturb recording.
    }
  }

  void _push(String line) {
    if (_buffer.length >= maxBuffered) {
      _buffer.removeAt(0);
      droppedLines++;
    }
    _buffer.add(line);
  }

  /// Escapes tag values in line protocol.
  static String _tag(String v) => v
      .replaceAll(r'\', r'\\')
      .replaceAll(',', r'\,')
      .replaceAll('=', r'\=')
      .replaceAll(' ', r'\ ')
      .replaceAll('\n', r'\n');

  // --- InfluxDB -----------------------------------------------------------------

  Uri? _influxTarget() {
    final base = parseOutboundTarget(settings.influxUrl);
    if (base == null) return null;
    final path = base.pathSegments.where((s) => s.isNotEmpty).toList();
    final v2 = settings.influxOrg.isNotEmpty && settings.influxBucket.isNotEmpty;
    return base.replace(
      pathSegments: [
        ...path,
        if (v2) ...['api', 'v2', 'write'] else 'write',
      ],
      queryParameters: v2
          ? {'org': settings.influxOrg, 'bucket': settings.influxBucket, 'precision': 'ms'}
          : {'db': settings.influxDatabase, 'precision': 'ms'},
    );
  }

  Future<OutboundResult> _send(List<String> lines) async {
    final target = _influxTarget();
    if (target == null) return const OutboundResult.failed('invalid');
    return postOutbound(
      target,
      headers: {
        if (settings.influxToken.isNotEmpty) HttpHeaders.authorizationHeader: 'Token ${settings.influxToken}',
        HttpHeaders.contentTypeHeader: 'text/plain; charset=utf-8',
      },
      body: utf8.encode(lines.join('\n')),
    );
  }

  /// Bus counters as a line.
  String _busLine() =>
      'knx_monitor_bus connected=${source.connected ? 1 : 0}i,telegrams_total=${telegrams}i,'
      'repeats_total=${repeats}i,dropped_total=${source.recorderDropped}i ${_now().millisecondsSinceEpoch}';

  /// Sends a batch; after failures with growing intervals (at most 5 minutes).
  /// Errors only show up in the status, never with address or token.
  Future<void> flush() async {
    if (!settings.influx || _sending || !source.timeKnown) return;
    final now = _now();
    if (_nextTry case final next? when now.isBefore(next)) return;
    _sending = true;
    try {
      _push(_busLine());
      final count = _buffer.length > maxBatch ? maxBatch : _buffer.length;
      final batch = _buffer.sublist(0, count);
      final result = await _send(batch);
      if (result.ok) {
        _buffer.removeRange(0, count > _buffer.length ? _buffer.length : count);
        _failures = 0;
        _nextTry = null;
        influxError = null;
        influxLast = now;
      } else {
        _failures++;
        final wait = min(300, settings.intervalSeconds * (1 << min(_failures, 8)));
        _nextTry = now.add(Duration(seconds: wait));
        if (influxError != result.code) _log('Datenexport InfluxDB: nicht zugestellt (${result.code})');
        influxError = result.code;
      }
    } on Object {
      influxError = 'network';
    } finally {
      _sending = false;
    }
  }

  /// Writes a sample line so the app can check the target.
  Future<OutboundResult> test() => _send([_busLine()]);

  // --- Prometheus ---------------------------------------------------------------

  Future<void> _bindMetrics() async {
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, settings.prometheusPort);
      _metrics = server;
      prometheusError = null;
      server.listen((request) => unawaited(_serveMetrics(request)), onError: (Object _) {});
    } on Object {
      prometheusError = 'bind';
      _log('Datenexport Prometheus: Port ${settings.prometheusPort} nicht verfügbar');
    }
  }

  /// Comparison without early exit, so the timing does not reveal the token.
  static bool _sameToken(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<void> _serveMetrics(HttpRequest request) async {
    final response = request.response;
    try {
      final peer = request.connectionInfo?.remoteAddress;
      if (peer == null || !isLocalPeer(peer)) {
        response.statusCode = HttpStatus.forbidden;
      } else if (request.uri.path != '/metrics' || request.method != 'GET') {
        response.statusCode = HttpStatus.notFound;
      } else {
        final auth = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
        final token = auth.startsWith('Bearer ') ? auth.substring(7).trim() : '';
        if (settings.prometheusToken.isEmpty || !_sameToken(token, settings.prometheusToken)) {
          response.statusCode = HttpStatus.unauthorized;
          response.headers.set(HttpHeaders.wwwAuthenticateHeader, 'Bearer');
        } else {
          response.headers.contentType = ContentType(
            'text',
            'plain',
            parameters: {'version': '0.0.4'},
            charset: 'utf-8',
          );
          response.write(prometheusText());
        }
      }
    } on Object {
      response.statusCode = HttpStatus.internalServerError;
    }
    await response.close().catchError((Object _) {});
  }

  /// Escapes label values in the Prometheus text format.
  static String _label(String v) => v.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n');

  /// Metrics in the Prometheus text format.
  String prometheusText() {
    final out = StringBuffer();
    void metric(String name, String type, String help, num value) {
      out
        ..writeln('# HELP $name $help')
        ..writeln('# TYPE $name $type')
        ..writeln('$name $value');
    }

    metric('knx_monitor_connected', 'gauge', 'Bus connected (1) or not (0).', source.connected ? 1 : 0);
    metric('knx_monitor_telegrams_total', 'counter', 'Group telegrams since export start.', telegrams);
    metric('knx_monitor_repeats_total', 'counter', 'Repeated telegrams since export start.', repeats);
    metric('knx_monitor_recorder_dropped_total', 'counter', 'Telegrams the recorder dropped.', source.recorderDropped);
    metric('knx_monitor_export_dropped_total', 'counter', 'Lines dropped from the export buffer.', droppedLines);
    if (_lastTelegram case final last?) {
      metric(
        'knx_monitor_last_telegram_timestamp_seconds',
        'gauge',
        'Time of the last group telegram.',
        last.millisecondsSinceEpoch / 1000,
      );
    }
    if (source.busmon case final busmon?) {
      out
        ..writeln('# HELP knx_monitor_busmon_frames_total Frames on the bus (KNX HAT in bus monitor mode).')
        ..writeln('# TYPE knx_monitor_busmon_frames_total counter');
      busmon.forEach((kind, value) => out.writeln('knx_monitor_busmon_frames_total{kind="${_label(kind)}"} $value'));
    }
    if (settings.includeValues) {
      out
        ..writeln('# HELP knx_monitor_sender_telegrams_total Telegrams per sender since export start.')
        ..writeln('# TYPE knx_monitor_sender_telegrams_total counter');
      _senders.forEach(
        (address, n) => out.writeln('knx_monitor_sender_telegrams_total{source="${formatIndividual(address)}"} $n'),
      );
      String labels(int group) {
        final name = source.nameOf(group);
        return 'ga="${_label(source.formatGroup(group))}"${name == null ? '' : ',name="${_label(name)}"'}';
      }

      out
        ..writeln('# HELP knx_monitor_group_telegrams_total Telegrams per group address since export start.')
        ..writeln('# TYPE knx_monitor_group_telegrams_total counter');
      _groups.forEach((group, n) => out.writeln('knx_monitor_group_telegrams_total{${labels(group)}} $n'));
      out
        ..writeln('# HELP knx_monitor_group_value Last numeric value of a group address.')
        ..writeln('# TYPE knx_monitor_group_value gauge');
      _values.forEach((group, value) => out.writeln('knx_monitor_group_value{${labels(group)}} $value'));
    }
    return out.toString();
  }

  Map<String, Object?> status() => {
    'settings': settings.toJson(secrets: false),
    'prometheusRunning': _metrics != null,
    'prometheusError': prometheusError,
    'influxError': influxError,
    'influxLast': influxLast?.millisecondsSinceEpoch,
    'buffered': _buffer.length,
    'droppedLines': droppedLines,
  };
}

/// `/api/export…`; `true` if [request] has been answered.
///
/// - `GET /api/export` → status and settings (without tokens)
/// - `PUT /api/export` → change ([admin] only); `generatedToken` exactly once
/// - `POST /api/export/test` → sample to InfluxDB ([admin] only)
/// - `GET /api/export/grafana?kind=prometheus|influxdb` → Grafana template
Future<bool> serveExport(HttpRequest request, DataExporter exporter, {required bool admin}) async {
  final path = request.uri.path;
  if (path != '/api/export' && !path.startsWith('/api/export/')) return false;
  final response = request.response;
  final method = request.method;

  Future<void> status(int code) async {
    response.statusCode = code;
    await response.close();
  }

  if (path == '/api/export/grafana' && method == 'GET') {
    await sendJson(response, grafanaDashboard(request.uri.queryParameters['kind'] ?? 'prometheus'));
    return true;
  }
  if (path == '/api/export' && method == 'GET') {
    await sendJson(response, exporter.status());
    return true;
  }
  if (!admin) {
    await status(HttpStatus.forbidden);
    return true;
  }
  if (path == '/api/export' && (method == 'PUT' || method == 'POST')) {
    final raw = await readBody(request, 16 * 1024);
    final Map<String, Object?> changes;
    try {
      changes = (jsonDecode(utf8.decode(raw ?? const [])) as Map).cast<String, Object?>();
    } on Object {
      await status(HttpStatus.badRequest);
      return true;
    }
    try {
      final generated = await exporter.update(changes);
      await sendJson(response, {...exporter.status(), 'generatedToken': ?generated});
    } on FormatException catch (e) {
      response.statusCode = HttpStatus.unprocessableEntity;
      await sendJson(response, {'error': e.message});
    }
    return true;
  }
  if (path == '/api/export/test' && method == 'POST') {
    final result = await exporter.test();
    await sendJson(response, {'ok': result.ok, 'error': ?result.code});
    return true;
  }
  await status(HttpStatus.methodNotAllowed);
  return true;
}
