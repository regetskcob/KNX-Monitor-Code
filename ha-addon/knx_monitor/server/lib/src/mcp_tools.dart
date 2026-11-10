import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:knx/knx.dart';

import 'alarms.dart';
import 'dpt_value.dart';
import 'project_evidence.dart';
import 'project_lint.dart';
import 'recorder.dart';
import 'report.dart';

/// Files the app writes into the installation's data folder (`CatalogStore` in the app); a test
/// compares them with lib/catalog_store.dart.
const appDptOverridesFile = 'dpt_overrides.json';
const appNameOverridesFile = 'name_overrides.json';
const appCatalogFile = 'catalog.json';

/// What the MCP tools read from an installation. An interface so tests run without a bus.
class McpSource {
  McpSource({required this.data, required this.recorder, required this.alarms, this.status});

  /// Data folder of the installation (`catalog.json`, `dpt_overrides.json`, `name_overrides.json`,
  /// history), the files the app writes.
  final Directory data;
  final Recorder recorder;
  final AlarmWatch alarms;

  /// Connection state for the overview (`GET /api/bus` without secrets).
  final Map<String, Object?> Function()? status;
}

/// An argument was missing or invalid: the answer explains it to the caller.
class McpToolError implements Exception {
  const McpToolError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The read-only tools of Busclear's MCP server: recorded telegrams, device activity, findings
/// over a period, the project check and a proposal for the XKNX Editor. Nothing here sends to the
/// bus or changes stored data.
class McpTools {
  McpTools(this.source, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final McpSource source;
  final DateTime Function() _now;

  /// Most days one call reads.
  static const maxDays = 31;

  /// Most telegrams one search returns.
  static const maxTelegrams = 1000;

  /// Tool definitions for `tools/list`.
  static final List<Map<String, Object?>> definitions = [
    {
      'name': 'overview',
      'description':
          'Overview of the installation Busclear records: project name, number of group addresses and devices, '
          'recorded history (first day, days, size) and bus connection. Start here.',
      'inputSchema': {'type': 'object', 'properties': <String, Object?>{}},
      'annotations': {'readOnlyHint': true},
    },
    {
      'name': 'search_telegrams',
      'description':
          'Search the recorded group telegrams, newest first. Filter by group address, sender, type, time range '
          'and value. Times are ISO 8601 (local time if without offset); default is the last 24 hours. '
          'Each result has the time, sender with device name, group address with name and datapoint type, '
          'the raw payload (hex) and the numeric value where the type is known.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'group_address': {'type': 'string', 'description': 'e.g. "1/2/3"'},
          'source': {'type': 'string', 'description': 'individual address of the sender, e.g. "1.1.5"'},
          'type': {
            'type': 'string',
            'enum': ['write', 'response', 'read'],
          },
          'from': {'type': 'string', 'description': 'start, ISO 8601'},
          'to': {'type': 'string', 'description': 'end, ISO 8601'},
          'value': {'type': 'number', 'description': 'numeric value equal to'},
          'min': {'type': 'number', 'description': 'numeric value at least'},
          'max': {'type': 'number', 'description': 'numeric value at most'},
          'limit': {'type': 'integer', 'description': 'most results, default 100, at most $maxTelegrams'},
        },
      },
      'annotations': {'readOnlyHint': true},
    },
    {
      'name': 'device_activity',
      'description':
          'What a device sent over the last days: telegrams per day, the group addresses it sent to with their '
          'names, and when it was last heard. A device that sends nothing over days may be offline or broken.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'device': {'type': 'string', 'description': 'individual address, e.g. "1.1.5"'},
          'days': {'type': 'integer', 'description': 'default 7, at most $maxDays'},
        },
        'required': ['device'],
      },
      'annotations': {'readOnlyHint': true},
    },
    {
      'name': 'findings',
      'description':
          'Findings from the recorded traffic over the last days, as in Busclear\'s installation report: devices '
          'and cyclic values that went silent, stuck measurements, frequent repetitions, bus load, outages, bus '
          'errors. Also availability and traffic figures.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'days': {'type': 'integer', 'description': 'default 7, at most $maxDays'},
        },
      },
      'annotations': {'readOnlyHint': true},
    },
    {
      'name': 'project_check',
      'description':
          'Checks the KNX project (as imported into Busclear from ETS, the XKNX Editor or Home Assistant) without '
          'bus traffic: missing read or transmit flags, several senders or read answers, addresses without '
          'sender or receiver, missing names and datapoint types, devices without links, never programmed or '
          'with a pending download.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'limit': {'type': 'integer', 'description': 'most entries per kind, default 50'},
        },
      },
      'annotations': {'readOnlyHint': true},
    },
    {
      'name': 'project_vs_bus',
      'description':
          'Compares the project with the recorded bus over the last days: devices that send where the project '
          'says they cannot (the device does not carry the project: compare it, e.g. with the XKNX Editor\'s '
          'download preview), commands to actuators whose status of the same channel does not answer, which of '
          'the project\'s several senders were really heard, and how many reads of status addresses without R '
          'stayed unanswered. Also from the history: datapoint type suggestions for addresses without one (DPST token '
          'for the editor\'s set_group_address_dpt, with certainty), contact or alarm addresses stuck on 1 for days, '
          'and presence or motion triggering on most nights.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'days': {'type': 'integer', 'description': 'default 7, at most $maxDays'},
          'limit': {'type': 'integer', 'description': 'most entries per list, default 50'},
        },
      },
      'annotations': {'readOnlyHint': true},
    },
    {
      'name': 'editor_handover',
      'description':
          'A proposal for the XKNX Editor (github.com/XKNX/xknx-editor): unambiguous corrections as operations '
          'for its project_batch tool (datapoint types and names corrected in Busclear, the C flag, the R flag '
          'of the object that sends an unreadable status) and notes for the comments of group addresses and '
          'devices. Busclear applies nothing; show it to the user and apply it with the editor\'s tools '
          '(dry_run first), never program devices without the user.',
      'inputSchema': {'type': 'object', 'properties': <String, Object?>{}},
      'annotations': {'readOnlyHint': true},
    },
  ];

  Future<Object?> call(String name, Map<String, Object?> args) async => switch (name) {
    'overview' => overview(),
    'search_telegrams' => searchTelegrams(args),
    'device_activity' => deviceActivity(args),
    'findings' => findings(args),
    'project_check' => projectCheck(args),
    'project_vs_bus' => projectVsBus(args),
    'editor_handover' => editorHandover(),
    _ => throw McpToolError('unknown tool $name'),
  };

  // --- overview ---------------------------------------------------------------------------------

  Future<Map<String, Object?>> overview() async {
    final catalog = await LintCatalog.load(source.data);
    final usage = await source.recorder.usage();
    return {
      'project': ?catalog.projectName,
      'group_addresses': catalog.groups.length,
      'devices': catalog.devices.values.where((d) => !d.tunnel).length,
      'history': {'first_day': ?usage['first'], 'days': usage['days'], 'bytes': usage['bytes']},
      'connection': ?source.status?.call(),
      'now': _now().toIso8601String(),
    };
  }

  // --- search_telegrams -------------------------------------------------------------------------

  Future<Map<String, Object?>> searchTelegrams(Map<String, Object?> args) async {
    await source.alarms.loadCatalog();
    final catalog = await LintCatalog.load(source.data);
    final now = _now();
    final to = _time(args['to'], 'to') ?? now;
    final from = _time(args['from'], 'from') ?? to.subtract(const Duration(hours: 24));
    if (from.isAfter(to)) throw const McpToolError('from is after to');
    if (to.difference(from) > const Duration(days: maxDays)) throw const McpToolError('at most $maxDays days');
    final group = _group(args['group_address'], catalog.style);
    final sender = _individual(args['source']);
    final type = switch (args['type']) {
      null => null,
      'read' => 0,
      'response' => 1,
      'write' => 2,
      final v => throw McpToolError('unknown type $v'),
    };
    final value = _number(args['value']);
    final min = _number(args['min']);
    final max = _number(args['max']);
    final limit = (_int(args['limit']) ?? 100).clamp(1, maxTelegrams);
    final start = from.microsecondsSinceEpoch;
    final end = to.microsecondsSinceEpoch;

    final found = <Map<String, Object?>>[];
    var truncated = false;
    for (
      var d = DateTime(to.year, to.month, to.day);
      !d.isBefore(DateTime(from.year, from.month, from.day));
      d = DateTime(d.year, d.month, d.day - 1)
    ) {
      final lines = await source.recorder.dayLines(Recorder.dayName(d));
      if (lines == null) continue;
      final day = <Map<String, Object?>>[];
      await for (final line in lines) {
        // Cheap filters on the raw line first.
        if (group != null && Recorder.field(line, 'd') != '$group') continue;
        if (sender != null && Recorder.field(line, 's') != '$sender') continue;
        final t = int.tryParse(Recorder.field(line, 't') ?? '');
        if (t == null || t < start || t > end) continue;
        final Map<String, Object?> j;
        try {
          j = jsonDecode(line) as Map<String, Object?>;
        } on FormatException {
          continue;
        }
        if (type != null && j['y'] != type) continue;
        final entry = _telegram(j, catalog);
        if (value != null || min != null || max != null) {
          final v = entry['value'];
          if (v is! num) continue;
          if (value != null && v != value) continue;
          if (min != null && v < min) continue;
          if (max != null && v > max) continue;
        }
        day.add(entry);
      }
      day.sort((a, b) => (b['_t']! as int).compareTo(a['_t']! as int));
      for (final e in day) {
        if (found.length == limit) {
          truncated = true;
          break;
        }
        found.add(e);
      }
      if (truncated) break;
    }
    for (final e in found) {
      e.remove('_t');
    }
    return {
      'from': from.toIso8601String(),
      'to': to.toIso8601String(),
      'count': found.length,
      if (truncated) 'more': true,
      'telegrams': found,
    };
  }

  Map<String, Object?> _telegram(Map<String, Object?> j, LintCatalog catalog) {
    final d = j['d']! as int;
    final s = j['s']! as int;
    final t = j['t']! as int;
    final dpt = source.alarms.dptOf(d);
    final x = j['x'] as String? ?? '';
    final y = j['y'] as int? ?? 2;
    final number = y == 0 ? null : numericValue(dpt, hexBytes(x), small: j['m'] == true);
    return {
      '_t': t,
      'time': DateTime.fromMicrosecondsSinceEpoch(t).toIso8601String(),
      'type': const ['read', 'response', 'write'][y.clamp(0, 2)],
      'source': formatIndividual(s),
      'source_name': ?catalog.devices[s]?.name,
      'group_address': source.alarms.formatGroup(d),
      'name': ?source.alarms.nameOf(d),
      if (dpt != null) 'dpt': dpt.$2 == null ? '${dpt.$1}' : '${dpt.$1}.${dpt.$2.toString().padLeft(3, '0')}',
      if (y != 0) 'raw': x,
      'value': ?number,
      if (j['rp'] == true) 'repeated': true,
    };
  }

  // --- device_activity --------------------------------------------------------------------------

  Future<Map<String, Object?>> deviceActivity(Map<String, Object?> args) async {
    await source.alarms.loadCatalog();
    final catalog = await LintCatalog.load(source.data);
    final device = _individual(args['device']) ?? (throw const McpToolError('device is required, e.g. "1.1.5"'));
    final days = (_int(args['days']) ?? 7).clamp(1, maxDays);
    final today = _now();
    final perDay = <String, int>{};
    final perGroup = <int, int>{};
    int? last;
    var repeated = 0;
    for (var i = days - 1; i >= 0; i--) {
      final name = Recorder.dayName(DateTime(today.year, today.month, today.day - i));
      final lines = await source.recorder.dayLines(name);
      var n = 0;
      if (lines != null) {
        await for (final line in lines) {
          if (Recorder.field(line, 's') != '$device' || line.contains('"o":true')) continue;
          n++;
          final d = int.tryParse(Recorder.field(line, 'd') ?? '');
          if (d != null) perGroup[d] = (perGroup[d] ?? 0) + 1;
          final t = int.tryParse(Recorder.field(line, 't') ?? '');
          if (t != null && (last == null || t > last)) last = t;
          if (line.contains('"rp":true')) repeated++;
        }
      }
      perDay[name] = n;
    }
    final info = catalog.devices[device];
    final groups = perGroup.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return {
      'device': formatIndividual(device),
      'name': ?info?.name,
      'product': ?info?.product,
      'location': ?info?.location,
      'in_project': info != null,
      'telegrams_per_day': perDay,
      'total': perDay.values.fold<int>(0, (a, b) => a + b),
      if (repeated > 0) 'repeated': repeated,
      'last_heard': last == null ? null : DateTime.fromMicrosecondsSinceEpoch(last).toIso8601String(),
      'sent_to': [
        for (final e in groups.take(50))
          {
            'group_address': source.alarms.formatGroup(e.key),
            'name': ?source.alarms.nameOf(e.key),
            'telegrams': e.value,
          },
      ],
    };
  }

  // --- findings ---------------------------------------------------------------------------------

  Future<Map<String, Object?>> findings(Map<String, Object?> args) async {
    await source.alarms.loadCatalog();
    final days = (_int(args['days']) ?? 7).clamp(1, maxDays);
    final now = _now();
    final from = DateTime(now.year, now.month, now.day - (days - 1));
    final path = source.data.path;
    final rollups = <Map<String, Object?>>[];
    // "Silent since" needs a look back before the period; as far again as the period, not the full
    // report lookback, so a call stays quick. Completed days the report service already condensed
    // come from its files, the rest is condensed here in an isolate (nothing is written).
    for (var d = from.subtract(Duration(days: days)); !d.isAfter(now); d = DateTime(d.year, d.month, d.day + 1)) {
      final day = Recorder.dayName(d);
      final stored = File('$path/reports/days/$day.json');
      Map<String, Object?>? r;
      if (day != Recorder.dayName(now) && await stored.exists()) {
        try {
          r = jsonDecode(await stored.readAsString()) as Map<String, Object?>;
        } on Object {
          r = null;
        }
      }
      r ??= await Isolate.run(() => computeDayRollup(path, day));
      if (r != null) rollups.add(r);
    }
    final report = buildInstallationReport(
      period: ReportPeriod('last-$days-days', from, DateTime(now.year, now.month, now.day + 1)),
      kind: ReportSettings.monthly,
      rollups: rollups,
      catalog: reportCatalogOf(source.alarms),
      now: now,
      partial: true,
    );
    const deviceKinds = {'deviceSilent', 'repeats'};
    return {
      'from': from.toIso8601String(),
      'to': now.toIso8601String(),
      'coverage': report['coverage'],
      'availability': report['availability'],
      'traffic': report['traffic'],
      'load': report['load'],
      'findings': [
        for (final f in (report['findings'] as List? ?? const []).cast<Map<String, Object?>>())
          {
            'kind': f['kind'],
            'level': f['level'],
            if (f['address'] case final int a)
              deviceKinds.contains(f['kind']) ? 'device' : 'group_address': deviceKinds.contains(f['kind'])
                  ? formatIndividual(a)
                  : source.alarms.formatGroup(a),
            'name': ?f['name'],
            if (f['since'] case final int since) 'since': DateTime.fromMillisecondsSinceEpoch(since).toIso8601String(),
            'rate': ?f['rate'],
            'count': ?f['count'],
            'value': ?f['value'],
          },
      ],
    };
  }

  // --- project_check ----------------------------------------------------------------------------

  Future<Map<String, Object?>> projectCheck(Map<String, Object?> args) async {
    final catalog = await LintCatalog.load(source.data);
    if (catalog.isEmpty) return {'project': null, 'message': 'No project imported into Busclear.'};
    final limit = (_int(args['limit']) ?? 50).clamp(1, 1000);
    final r = ProjectLintResult.of(catalog);
    return {
      'project': ?catalog.projectName,
      'flags_known': r.hasFlags,
      'checks': {
        for (final MapEntry(key: kind, value: list) in r.lists.entries)
          if (list.isNotEmpty)
            kind: {
              'meaning': ProjectLintResult.kinds[kind]!.meaning,
              'count': list.length,
              'items': list.take(limit).toList(),
            },
      },
    };
  }

  // --- project_vs_bus ---------------------------------------------------------------------------

  Future<Map<String, Object?>> projectVsBus(Map<String, Object?> args) async {
    final catalog = await LintCatalog.load(source.data);
    if (catalog.isEmpty) return {'project': null, 'message': 'No project imported into Busclear.'};
    final days = (_int(args['days']) ?? 7).clamp(1, maxDays);
    final limit = (_int(args['limit']) ?? 50).clamp(1, 1000);
    final e = await ProjectEvidence.of(catalog, source.recorder, now: _now(), days: days);
    return {
      for (final MapEntry(:key, :value) in e.result.entries)
        key: value is List ? {'count': value.length, 'items': value.take(limit).toList()} : value,
    };
  }

  // --- editor_handover --------------------------------------------------------------------------

  /// Same format as the app's handover file (`busclear-xknx-editor`, lib/model/xknx_editor_handover.dart).
  Future<Map<String, Object?>> editorHandover() async {
    final catalog = await LintCatalog.load(source.data);
    if (catalog.isEmpty) return {'project': null, 'message': 'No project imported into Busclear.'};
    String ga(int a) => formatGroupAddress(a, catalog.style);
    final operations = <Map<String, Object?>>[];
    final notes = <String, Map<String, Object?>>{};
    void note(String key, Map<String, Object?> target, String text) {
      final n = notes.putIfAbsent(key, () => {...target, 'lines': <String>[]});
      final line = '[Busclear] $text';
      final lines = n['lines']! as List<String>;
      if (!lines.contains(line)) lines.add(line);
    }

    // Datapoint types and names corrected in the app.
    final overrides = await _json(appDptOverridesFile);
    for (final MapEntry(:key, :value) in overrides.entries) {
      final a = int.tryParse(key);
      if (a == null || value is! List || value.length < 2 || value[1] == null) continue;
      final g = catalog.groups[a];
      if (g == null || (g.dpt?.$1 == value[0] && g.dpt?.$2 == value[1])) continue;
      operations.add({
        'op': 'set_group_address_dpt',
        'params': {'group_address': ga(a), 'dpt': 'DPST-${value[0]}-${value[1]}'},
      });
    }
    final names = await _json(appNameOverridesFile);
    for (final MapEntry(:key, :value) in names.entries) {
      final a = int.tryParse(key);
      if (a == null || value is! String || value.isEmpty || catalog.groups[a]?.name == value) continue;
      if (catalog.groups[a] == null) continue;
      operations.add({
        'op': 'rename_group_address',
        'params': {'group_address': ga(a), 'name': value},
      });
    }

    final r = ProjectLintResult.of(catalog);
    String gaKey(Map<String, Object?> item) => 'g${item['group_address']}';
    for (final item in r.lists['object_without_communication']!) {
      for (final o in (item['objects'] as List).cast<Map<String, Object?>>()) {
        if (o['ref'] case final String ref) {
          operations.add({
            'op': 'set_com_object_flag',
            'params': {'device_address': o['device'], 'com_object_ref_id': ref, 'flag': 'communication', 'value': true},
          });
        } else {
          note(gaKey(item), {
            'group_address': item['group_address'],
          }, 'Object of ${o['device']} without C flag: set C.');
        }
      }
    }
    for (final item in r.lists['read_without_read_flag']!) {
      final objects = (item['objects'] as List).cast<Map<String, Object?>>();
      final sender = objects.where((o) => o['sends'] == true && o['ref'] is String).firstOrNull;
      if (sender != null) {
        operations.add({
          'op': 'set_com_object_flag',
          'params': {
            'device_address': sender['device'],
            'com_object_ref_id': sender['ref'],
            'flag': 'read',
            'value': true,
          },
        });
      } else {
        note(gaKey(item), {
          'group_address': item['group_address'],
        }, 'Status cannot be read: set R on the object that holds the state.');
      }
    }
    const texts = {
      'status_without_transmit': 'No object sends this status: set T on the object that holds the state.',
      'multiple_read_answers': 'Several objects answer reads: keep R only on the object that holds the state.',
      'without_receiver': 'Command address without receiver (no object with C and W): link a receiver or remove it.',
      'no_name': 'Address has the default name only: give it a name.',
      'no_dpt': 'Address without datapoint type: set the type.',
    };
    for (final MapEntry(key: kind, value: text) in texts.entries) {
      for (final item in r.lists[kind]!) {
        note(gaKey(item), {'group_address': item['group_address']}, text);
      }
    }
    for (final item in r.lists['device_without_links']!) {
      note('d${item['device']}', {
        'device_address': item['device'],
      }, 'Device without links: link group addresses or remove the device.');
    }
    for (final item in r.lists['device_never_programmed']!) {
      note('d${item['device']}', {'device_address': item['device']}, 'Never programmed according to the project.');
    }
    for (final item in r.lists['device_download_pending']!) {
      note('d${item['device']}', {
        'device_address': item['device'],
      }, 'Download pending: ${(item['parts'] as List).join(', ')}.');
    }
    return {
      'format': 'busclear-xknx-editor',
      'version': 1,
      'project': ?catalog.projectName,
      'instructions':
          'Apply "operations" with the XKNX Editor MCP tool project_batch (dry_run first). Append each note\'s '
          '"lines" to the comment of its group address or device (project_get_comment / project_set_comment), '
          'replacing earlier lines that start with "[Busclear]". Nothing is programmed: the user downloads the '
          'changed devices in the editor.',
      'operations': operations,
      'notes': notes.values.toList(),
    };
  }

  // --- helpers ----------------------------------------------------------------------------------

  Future<Map<String, Object?>> _json(String name) async {
    final file = File('${source.data.path}/$name');
    try {
      if (!await file.exists()) return const {};
      final v = jsonDecode(await file.readAsString());
      return v is Map ? v.cast<String, Object?>() : const {};
    } on Object {
      return const {};
    }
  }

  static DateTime? _time(Object? v, String name) {
    if (v == null) return null;
    final t = v is String ? DateTime.tryParse(v) : null;
    if (t == null) throw McpToolError('$name is not an ISO 8601 time');
    return t.toLocal();
  }

  static int? _group(Object? v, GroupStyle style) {
    if (v == null) return null;
    final a = v is String ? parseGroupAddress(v, style) : null;
    if (a == null) throw McpToolError('group_address "$v" is not a group address');
    return a;
  }

  static int? _individual(Object? v) {
    if (v == null) return null;
    final a = v is String ? parseIndividual(v) : null;
    if (a == null) throw McpToolError('"$v" is not an individual address');
    return a;
  }

  static num? _number(Object? v) => switch (v) {
    null => null,
    final num n => n,
    final String s => num.tryParse(s) ?? (throw McpToolError('"$s" is not a number')),
    _ => throw McpToolError('"$v" is not a number'),
  };

  static int? _int(Object? v) => switch (v) {
    null => null,
    final int n => n,
    final num n => n.toInt(),
    final String s => int.tryParse(s),
    _ => null,
  };
}
