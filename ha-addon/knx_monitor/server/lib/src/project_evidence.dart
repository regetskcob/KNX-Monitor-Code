import 'dart:convert';

import 'package:knx/knx.dart';

import 'project_lint.dart';
import 'recorder.dart';

/// Project against bus: what the recorded history says about the project (`GET
/// /api/project-evidence`, MCP tool `project_vs_bus`).
///
/// - **unexpected_senders**: a device of the project sends (write or response) to a group address
///   on which, according to the project, it has no sending object – or no object at all. The
///   device then does not carry the project (changed after the last download, replaced, or the
///   project is outdated): compare it with the project, e.g. with the XKNX Editor's download
///   preview.
/// - **commands_without_feedback**: commands to an actuator whose status object of the same
///   channel does not answer within [feedbackWindow]. Pairs come from the project: the actuator
///   listens on the command address and sends on a status address of the same channel (object
///   text) or of the same name without the status words.
/// - **multiple_senders** / **read_without_answer**: the project check's findings with figures
///   from the bus: which senders were really heard, how many reads stayed unanswered.
class ProjectEvidence {
  ProjectEvidence._(this.result);

  final Map<String, Object?> result;

  /// How long a status answer may take after a command.
  static const feedbackWindow = Duration(seconds: 5);

  /// How long a response may take after a read.
  static const readWindow = Duration(seconds: 3);

  /// Commands at least before "without feedback" is reported.
  static const minCommands = 3;

  /// Reads [days] days of [recorder] up to [now] against [catalog].
  static Future<ProjectEvidence> of(
    LintCatalog catalog,
    Recorder recorder, {
    required DateTime now,
    int days = 7,
  }) async {
    final style = catalog.style;
    String ga(int a) => formatGroupAddress(a, style);
    String deviceName(int a) => catalog.devices[a]?.name ?? '';

    // --- What the project says --------------------------------------------------------------
    // Sending links per group address; all linked devices per group address.
    final sendersOf = <int, Set<int>>{};
    final linkedOf = <int, Map<int, List<LintLink>>>{};
    for (final g in catalog.groups.values) {
      for (final l in g.links) {
        (linkedOf[g.address] ??= {}).putIfAbsent(l.device, () => []).add(l);
        if (l.sends) (sendersOf[g.address] ??= {}).add(l.device);
      }
    }
    // Command → status pairs per actuator.
    final pairs = <int, List<({int device, int status})>>{}; // command address → pairs
    for (final device in {
      for (final g in catalog.groups.values)
        for (final l in g.links) l.device,
    }) {
      final commands = <String, List<int>>{};
      final statuses = <String, List<int>>{};
      for (final g in catalog.groups.values) {
        for (final l in g.links.where((l) => l.device == device && l.known)) {
          final status = isStatusGroup(g);
          for (final key in _keys(l.text, g.name)) {
            if (status && l.sends) {
              (statuses[key] ??= []).add(g.address);
            } else if (!status && l.write && !l.sends) {
              (commands[key] ??= []).add(g.address);
            }
          }
        }
      }
      for (final MapEntry(:key, value: cmds) in commands.entries) {
        final st = statuses[key];
        // Only unambiguous: one status for the channel or name.
        if (st == null || st.toSet().length != 1) continue;
        for (final c in cmds.toSet()) {
          final list = pairs[c] ??= [];
          if (!list.any((p) => p.device == device)) list.add((device: device, status: st.first));
        }
      }
    }
    final readCheck = {
      for (final g in catalog.groups.values)
        if (isStatusGroup(g) &&
            g.links.isNotEmpty &&
            g.links.every((l) => l.known) &&
            !g.links.any((l) => l.answersReads))
          g.address,
    };
    final multi = {
      for (final MapEntry(key: a, value: s) in sendersOf.entries)
        if (s.length > 1) a,
    };

    // --- What the bus shows -----------------------------------------------------------------
    final heard = <(int, int), int>{}; // (group, source) → telegrams (write/response)
    final insights = _Insights(catalog, now);
    final pendingCommands = <({int group, int device, int status, int time})>[];
    final feedback = <(int, int), ({int commands, int answered, int last})>{}; // (command, device)
    final lastStatus = <(int, int), List<int>>{}; // (status group, device) → times
    final reads = <int, ({int reads, int answered})>{};
    final openReads = <int, List<int>>{};
    final start = DateTime(now.year, now.month, now.day - (days - 1));
    final end = now.microsecondsSinceEpoch;
    for (var d = start; !d.isAfter(now); d = DateTime(d.year, d.month, d.day + 1)) {
      final lines = await recorder.dayLines(Recorder.dayName(d));
      if (lines == null) continue;
      final day = <({int t, int s, int d, int y, String x, bool m})>[];
      await for (final line in lines) {
        final t = int.tryParse(Recorder.field(line, 't') ?? '');
        final s = int.tryParse(Recorder.field(line, 's') ?? '');
        final dest = int.tryParse(Recorder.field(line, 'd') ?? '');
        final y = int.tryParse(Recorder.field(line, 'y') ?? '');
        if (t == null || s == null || dest == null || y == null || t > end) continue;
        day.add((t: t, s: s, d: dest, y: y, x: _hexField(line), m: line.contains('"m":true')));
      }
      day.sort((a, b) => a.t.compareTo(b.t));
      for (final m in day) {
        if (m.y != 0) insights.add(m.d, m.t, m.x, small: m.m);
        if (m.y != 0) heard[(m.d, m.s)] = (heard[(m.d, m.s)] ?? 0) + 1;
        // Status answers of actuators.
        if (m.y != 0) (lastStatus[(m.d, m.s)] ??= []).add(m.t);
        // Commands (writes) on paired addresses.
        if (m.y == 2) {
          for (final p in pairs[m.d] ?? const <({int device, int status})>[]) {
            // The actuator's own status echo on the command address is no command.
            if (m.s == p.device) continue;
            pendingCommands.add((group: m.d, device: p.device, status: p.status, time: m.t));
          }
        }
        // Reads and their answers on status addresses without R.
        if (readCheck.contains(m.d)) {
          final r = reads[m.d] ?? (reads: 0, answered: 0);
          if (m.y == 0) {
            reads[m.d] = (reads: r.reads + 1, answered: r.answered);
            (openReads[m.d] ??= []).add(m.t);
          } else if (m.y == 1) {
            final open = openReads[m.d] ?? [];
            final hit = open.where((t) => m.t - t <= readWindow.inMicroseconds && m.t >= t).toList();
            if (hit.isNotEmpty) {
              open.remove(hit.first);
              reads[m.d] = (reads: r.reads, answered: r.answered + 1);
            }
          }
        }
      }
    }
    for (final c in pendingCommands) {
      final times = lastStatus[(c.status, c.device)] ?? const <int>[];
      final answered = times.any((t) => t >= c.time && t - c.time <= feedbackWindow.inMicroseconds);
      final f = feedback[(c.group, c.device)] ?? (commands: 0, answered: 0, last: 0);
      feedback[(c.group, c.device)] = (
        commands: f.commands + 1,
        answered: f.answered + (answered ? 1 : 0),
        last: answered ? f.last : (c.time > f.last ? c.time : f.last),
      );
    }

    // --- Findings ----------------------------------------------------------------------------
    final unexpected = <Map<String, Object?>>[];
    for (final MapEntry(key: (group, source), value: n) in heard.entries) {
      final device = catalog.devices[source];
      // Tunnels (visualisation, Home Assistant) and devices outside the project have their own checks.
      if (device == null || device.tunnel) continue;
      if (catalog.groups[group] == null) continue;
      if (sendersOf[group]?.contains(source) ?? false) continue;
      final links = linkedOf[group]?[source];
      // Without known flags the project cannot tell.
      if (links != null && links.any((l) => !l.known)) continue;
      unexpected.add({
        'device': formatIndividual(source),
        'device_name': deviceName(source),
        'group_address': ga(group),
        'name': catalog.groups[group]!.name,
        'telegrams': n,
        'project': links == null
            ? 'no object of the device is linked to this address'
            : 'linked, but not as sender (flags ${links.map((l) => l.flags).join('/')})',
      });
    }
    unexpected.sort((a, b) => (b['telegrams']! as int).compareTo(a['telegrams']! as int));

    final noFeedback = <Map<String, Object?>>[];
    for (final MapEntry(key: (group, device), value: f) in feedback.entries) {
      if (f.commands < minCommands || f.answered * 2 > f.commands) continue;
      final status = pairs[group]!.firstWhere((p) => p.device == device).status;
      noFeedback.add({
        'device': formatIndividual(device),
        'device_name': deviceName(device),
        'command': ga(group),
        'command_name': catalog.groups[group]?.name,
        'status': ga(status),
        'status_name': catalog.groups[status]?.name,
        'commands': f.commands,
        'answered': f.answered,
        if (f.last > 0) 'last_unanswered': DateTime.fromMicrosecondsSinceEpoch(f.last).toIso8601String(),
      });
    }
    noFeedback.sort((a, b) => (b['commands']! as int).compareTo(a['commands']! as int));

    final senders = <Map<String, Object?>>[];
    for (final group in multi.toList()..sort()) {
      final project = sendersOf[group]!;
      final observed = {
        for (final MapEntry(key: (g, s), value: n) in heard.entries)
          if (g == group) s: n,
      };
      final active = project.where(observed.containsKey).toList()..sort();
      senders.add({
        'group_address': ga(group),
        'name': catalog.groups[group]?.name,
        'project_senders': [for (final s in project.toList()..sort()) formatIndividual(s)],
        'heard': {for (final s in active) formatIndividual(s): observed[s]},
        'confirmed': active.length > 1,
      });
    }
    senders.sort((a, b) => (a['confirmed'] == b['confirmed'] ? 0 : (a['confirmed'] == true ? -1 : 1)));

    final unread = <Map<String, Object?>>[
      for (final group in readCheck.toList()..sort())
        {
          'group_address': ga(group),
          'name': catalog.groups[group]?.name,
          'reads': reads[group]?.reads ?? 0,
          'answered': reads[group]?.answered ?? 0,
        },
    ]..sort((a, b) => (b['reads']! as int).compareTo(a['reads']! as int));

    return ProjectEvidence._({
      'from': start.toIso8601String(),
      'to': now.toIso8601String(),
      'days': days,
      'unexpected_senders': unexpected,
      'commands_without_feedback': noFeedback,
      'multiple_senders': senders,
      'read_without_answer': unread,
      ...insights.result(ga),
    });
  }

  /// Channel of an object (text before " – ") and the name of its address without status words:
  /// two ways to find the status of a command.
  static Iterable<String> _keys(String? text, String name) sync* {
    final channel = text?.split(' – ').first.trim().toLowerCase();
    if (channel != null && channel.isNotEmpty) yield 'c:$channel';
    final stem = name
        .toLowerCase()
        .replaceAll(
          RegExp(
            r'rückmeldung|rücmledung|status|zustand|feedback|\brm\b|ist[- ]?wert|schalten|ein/aus|an/aus|switch|state',
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (stem.isNotEmpty) yield 'n:$stem';
  }

  String toJson() => jsonEncode(result);
}

/// Words in a group address name for the history checks below.
final _contactName = RegExp(
  r'geöffnet|gekippt|offen|\bauf\b|open|tilt|fenster|tür|tor|window|door|alarm|störung|fault|sabotage',
  caseSensitive: false,
);
final _presenceName = RegExp(r'präsenz|anwesen|bewegung|presence|motion|occupan', caseSensitive: false);

/// What the history says beyond the project's links (MCP `project_vs_bus`, app project check):
///
/// - **dpt_suggestions**: group addresses without a datapoint type, with the type their telegrams
///   suggest (payload length, values, words in the name) as a DPST token ready for the XKNX
///   Editor's `set_group_address_dpt`, and how sure it is.
/// - **long_states**: a contact, alarm or window address that kept the same "on" value for the
///   whole period although it was sent again and again (4/1/13 "gekippt" sent 1 every 30 min for
///   days): a stuck contact or a wrong polarity.
/// - **night_activity**: presence or motion that triggers in the night (0–5 h) on most nights:
///   a detector that sees into a bedroom, a pet, or a wrong sensitivity.
class _Insights {
  _Insights(this.catalog, this.now);

  final LintCatalog catalog;
  final DateTime now;

  final _sizes = <int, Map<int, int>>{}; // group → payload length (0 = in the APCI) → count
  final _values = <int, Set<int>>{}; // group → small values seen
  final _first = <int, int>{};
  final _binary = <int, ({int value, int since, int count, bool changed})>{};
  final _nights = <int, Map<String, int>>{}; // presence group → night → triggers
  final _nightsHeard = <String>{};

  void add(int group, int t, String x, {required bool small}) {
    final g = catalog.groups[group];
    final size = small ? 0 : x.length ~/ 2;
    if (g != null && g.dpt == null) {
      final sizes = _sizes[group] ??= {};
      sizes[size] = (sizes[size] ?? 0) + 1;
    }
    if (!small) return;
    final v = (int.tryParse(x.isEmpty ? '0' : x, radix: 16) ?? 0) & 0x3F;
    if (g != null && g.dpt == null) (_values[group] ??= {}).add(v);
    final time = DateTime.fromMicrosecondsSinceEpoch(t);
    final night = time.hour < 5;
    final nightKey = Recorder.dayName(time);
    if (night) _nightsHeard.add(nightKey);
    if (g == null) return;
    final binary = g.dpt == null ? v <= 1 : g.dpt!.$1 == 1;
    if (binary && _contactName.hasMatch(g.name)) {
      _first[group] ??= t;
      final b = _binary[group];
      _binary[group] = b == null || b.value != v
          ? (value: v, since: t, count: 1, changed: b != null)
          : (value: b.value, since: b.since, count: b.count + 1, changed: b.changed);
    }
    if (binary && v == 1 && night && _presenceName.hasMatch(g.name)) {
      final n = _nights[group] ??= {};
      n[nightKey] = (n[nightKey] ?? 0) + 1;
    }
  }

  /// DPST token and certainty from what was seen on [group].
  (String, String)? _suggest(LintGroup g) {
    final sizes = _sizes[g.address];
    if (sizes == null || sizes.isEmpty) return null;
    final size = (sizes.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    final consistent = sizes.length == 1;
    final n = g.name.toLowerCase();
    bool has(String pattern) => RegExp(pattern).hasMatch(n);
    final (String, bool)? guess = switch (size) {
      0 when (_values[g.address] ?? {}).every((v) => v <= 1) => switch (n) {
        _ when has('auf/ab|auf/zu|fahren|up/down') => ('DPST-1-8', true),
        _ when has('stop|anhalten|lamelle|schritt|step') => ('DPST-1-7', true),
        _ when has('geöffnet|gekippt|offen|fenster|kontakt|window|contact') => ('DPST-1-19', true),
        _ when has('alarm|störung|fault') => ('DPST-1-5', true),
        _ when has('tag/nacht|day/night') => ('DPST-1-24', true),
        _ when has('präsenz|anwesen|bewegung|presence|occupan|motion') => ('DPST-1-18', true),
        _ => ('DPST-1-1', has('schalt|licht|steckdose|switch|ein/aus|an/aus')),
      },
      0 => ('DPST-3-7', has('dimm')),
      1 => switch (n) {
        _ when has('modus|mode|betriebsart') => ('DPST-20-102', true),
        _ when has('szene|scene') => ('DPST-17-1', true),
        _ => ('DPST-5-1', has('wert|position|%|helligkeit|stellwert|dimm|lamelle')),
      },
      2 => switch (n) {
        _ when has('temperatur|temp|soll|ist-|°c') => ('DPST-9-1', true),
        _ when has('verschieb') => ('DPST-9-2', true),
        _ when has('helligkeit|lux|licht') => ('DPST-9-4', true),
        _ when has('wind') => ('DPST-9-5', true),
        _ when has('feucht|humid') => ('DPST-9-7', true),
        _ when has('co2|ppm') => ('DPST-9-8', true),
        _ => ('DPST-9-1', false),
      },
      3 => has('datum|date') ? ('DPST-11-1', true) : ('DPST-10-1', has('zeit|uhr|time')),
      4 => switch (n) {
        _ when has('leistung|power|watt') => ('DPST-14-56', true),
        _ when has('energie|zähler|kwh|verbrauch') => ('DPST-13-13', true),
        _ when has('strom|current') => ('DPST-14-19', true),
        _ when has('spannung|voltage') => ('DPST-14-27', true),
        _ => null,
      },
      8 => ('DPST-19-1', true),
      14 => ('DPST-16-1', has('text|status|meldung')),
      _ => null,
    };
    if (guess == null) return null;
    return (guess.$1, consistent && guess.$2 ? 'high' : 'medium');
  }

  Map<String, Object?> result(String Function(int) ga) {
    final suggestions = <Map<String, Object?>>[
      for (final g
          in catalog.groups.values.where((g) => g.dpt == null).toList()..sort((a, b) => a.address.compareTo(b.address)))
        if (_suggest(g) case (final dpt, final certainty))
          {
            'group_address': ga(g.address),
            'name': g.name,
            'dpt': dpt,
            'certainty': certainty,
            'sizes': {
              for (final MapEntry(:key, :value) in _sizes[g.address]!.entries) key == 0 ? 'apci' : '$key': value,
            },
          },
    ];
    final period = now.microsecondsSinceEpoch;
    final states = <Map<String, Object?>>[];
    for (final MapEntry(key: group, value: b) in _binary.entries) {
      // "On" value kept for at least two days and sent again at least 10 times in that time.
      final days = (period - b.since) / Duration.microsecondsPerDay;
      if (b.value != 1 || b.count < 10 || days < 2) continue;
      states.add({
        'group_address': ga(group),
        'name': catalog.groups[group]!.name,
        'value': b.value,
        'since': DateTime.fromMicrosecondsSinceEpoch(b.since).toIso8601String(),
        'since_period_start': !b.changed,
        'days': double.parse(days.toStringAsFixed(1)),
        'telegrams': b.count,
      });
    }
    states.sort((a, b) => (b['days']! as double).compareTo(a['days']! as double));
    final nights = <Map<String, Object?>>[];
    final heardNights = _nightsHeard.length;
    for (final MapEntry(key: group, value: perNight) in _nights.entries) {
      final active = perNight.length;
      final total = perNight.values.fold<int>(0, (a, b) => a + b);
      // On most nights the bus was heard, at least three nights, more than one trigger per night.
      if (heardNights == 0 || active < 3 || active * 2 < heardNights || total < active * 2) continue;
      nights.add({
        'group_address': ga(group),
        'name': catalog.groups[group]!.name,
        'nights': active,
        'nights_recorded': heardNights,
        'triggers_per_night': double.parse((total / active).toStringAsFixed(1)),
      });
    }
    nights.sort((a, b) => (b['nights']! as int).compareTo(a['nights']! as int));
    return {'dpt_suggestions': suggestions, 'long_states': states, 'night_activity': nights};
  }
}

/// The payload (`"x":"0c33"`) of a history line; [Recorder.field] reads numbers only.
String _hexField(String line) {
  final i = line.indexOf('"x":"');
  if (i < 0) return '';
  final end = line.indexOf('"', i + 5);
  return end < 0 ? '' : line.substring(i + 5, end);
}
