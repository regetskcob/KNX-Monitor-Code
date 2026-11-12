import 'dart:convert';
import 'dart:io';

import 'dali.dart';
import 'dpt_value.dart';

/// Watchers in the add-on or on the box: the same rules as in the app
/// (`lib/model/watch_rules.dart`), so they also apply without an open browser
/// and arrive as Home Assistant notifications.
///
/// The app stores the rules as `watch_rules.json` next to the project, already
/// in checkable form (`check`): without a value every telegram, for small data
/// types the matching raw values, for numbers a comparison, for flag datapoints
/// (DALI diagnostics) a mask on the bits ([bitsCheckMatches]). Rules without
/// `check` are still checked by the app only.
class WatchRuleSet {
  WatchRuleSet(
    this.data, {
    required this.notify,
    this.cooldown = const Duration(seconds: 3),
    this.notifyEvery = const Duration(minutes: 1),
  });

  final Directory data;
  final Future<void> Function({required String id, required String title, required String message}) notify;

  /// The same rule fires at most this often (as in the app).
  final Duration cooldown;

  /// Notifications to Home Assistant at most this often per rule.
  final Duration notifyEvery;

  String language = 'de';

  List<_Rule> _rules = const [];
  DateTime? _rulesTime;
  final _lastHit = <String, DateTime>{};
  final _lastSent = <String, DateTime>{};

  File get _file => File('${data.path}/watch_rules.json');

  Future<void> _reload() async {
    try {
      if (!await _file.exists()) {
        _rules = const [];
        _rulesTime = null;
        return;
      }
      final modified = await _file.lastModified();
      if (modified == _rulesTime) return;
      _rulesTime = modified;
      final json = jsonDecode(await _file.readAsString()) as Map<String, Object?>;
      // One broken rule (a paired device may store its own) must not switch
      // off the others: each one on its own.
      final rules = <_Rule>[];
      var broken = 0;
      for (final r in json['rules'] as List? ?? const []) {
        try {
          if (r is! Map<String, Object?>) {
            broken++;
          } else if (_Rule.parse(r) case final rule?) {
            rules.add(rule);
          }
        } on Object {
          broken++;
        }
      }
      if (broken > 0) stderr.writeln('watch_rules.json: $broken Regel(n) unlesbar, übersprungen');
      _rules = rules;
    } on Object catch (e) {
      // Unreadable as a whole: keep the previous rules, and do not read the
      // file again on every telegram until it changes (_rulesTime stays).
      stderr.writeln('watch_rules.json: $e');
    }
  }

  /// Active rules checked by the server: id and name (for the device triggers
  /// of the MQTT device).
  Future<List<({String id, String name})>> rules() async {
    await _reload();
    return [for (final r in _rules) (id: r.id, name: r.name ?? r.label)];
  }

  /// Checks a telegram line (format as in the history) and returns the ids of
  /// the rules that fired. Cooldowns count from [now], otherwise from the
  /// telegram's time. [onHit] receives every hit after the cooldown, even if
  /// no notification is sent (event for Home Assistant automations).
  Future<List<String>> check(Map<String, Object?> t, {DateTime? now, void Function(WatchHit hit)? onHit}) async {
    if (t['y'] == 0 || t['o'] == true) return const []; // read request, own telegram
    await _reload();
    final at = now ?? DateTime.fromMicrosecondsSinceEpoch(t['t']! as int);
    final hits = <String>[];
    for (final rule in _rules) {
      if (!rule.matches(t)) continue;
      final last = _lastHit[rule.id];
      if (last != null && at.difference(last) < cooldown) continue;
      _lastHit[rule.id] = at;
      hits.add(rule.id);
      onHit?.call(WatchHit(id: rule.id, name: rule.name ?? rule.label, label: rule.label, value: rule.number(t)));
      final sent = _lastSent[rule.id];
      if (sent != null && at.difference(sent) < notifyEvery) continue;
      _lastSent[rule.id] = at;
      await notify(id: 'knx_watch_${rule.id}', title: _title(rule), message: _message(rule, t));
    }
    return hits;
  }

  String _title(_Rule r) => '${language.startsWith('de') ? 'Wächter' : 'Watcher'}: ${r.name ?? r.label}';

  String _message(_Rule r, Map<String, Object?> t) {
    final time = DateTime.fromMicrosecondsSinceEpoch(t['t']! as int);
    final clock = [time.hour, time.minute, time.second].map((v) => v.toString().padLeft(2, '0')).join(':');
    final value = r.number(t);
    return [r.label, if (value != null) _format(value), clock].join(' · ');
  }

  String _format(double v) {
    final text = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    return language.startsWith('de') ? text.replaceAll('.', ',') : text;
  }
}

/// A fired watcher: id and name from the app, numeric value for rules with a
/// comparison.
class WatchHit {
  const WatchHit({required this.id, required this.name, required this.label, this.value});

  final String id;

  /// Name of the group address, otherwise the rule's description.
  final String name;

  /// Description from the app, e.g. "8/1/1 wind speed > 10".
  final String label;
  final double? value;
}

/// Checkable rule in the watcher format (`id`, `address`, `label`, `check`),
/// e.g. for the fault hunt. `null` if it cannot be checked.
({String label, bool Function(Map<String, Object?> t) matches, double? Function(Map<String, Object?> t) number})?
parseServerRule(Map<String, Object?> j) => switch (_Rule.parse({...j, 'enabled': true})) {
  final r? => (label: r.label, matches: r.matches, number: r.number),
  null => null,
};

class _Rule {
  _Rule({
    required this.id,
    required this.address,
    required this.label,
    this.name,
    this.any = false,
    this.small = false,
    this.bytes = 0,
    this.values = const {},
    this.dpt,
    this.op,
    this.n,
    this.bits,
  });

  /// `null` for disabled rules and those only the app checks.
  static _Rule? parse(Map<String, Object?> j) {
    final check = (j['check'] as Map?)?.cast<String, Object?>();
    if (j['enabled'] == false || check == null) return null;
    final id = j['id'] as String?;
    final address = j['address'] as int?;
    if (id == null || address == null) return null;
    final label = j['label'] as String? ?? '$address';
    final name = j['name'] as String?;
    if (check['any'] == true) return _Rule(id: id, address: address, label: label, name: name, any: true);
    if (check['values'] case final List<Object?> values) {
      return _Rule(
        id: id,
        address: address,
        label: label,
        name: name,
        small: check['small'] == true,
        bytes: check['bytes'] as int? ?? 0,
        values: values.cast<int>().toSet(),
      );
    }
    // Flags of the payload: `bytes` and `mask` must be there, or the rule could never fire.
    if (check['bits'] case final Map<Object?, Object?> bits) {
      if (bits['bytes'] is! int || bits['mask'] is! int) return null;
      return _Rule(id: id, address: address, label: label, name: name, bits: bits.cast<String, Object?>());
    }
    if (check['num'] case [final int main, final int? sub]) {
      return _Rule(
        id: id,
        address: address,
        label: label,
        name: name,
        dpt: (main, sub),
        op: check['op'] as String?,
        n: (check['n'] as num?)?.toDouble(),
      );
    }
    return null;
  }

  final String id;
  final int address;

  /// Description from the app, e.g. "8/1/1 wind speed > 10".
  final String label;

  /// Name of the group address from the project.
  final String? name;

  final bool any;

  /// Matching raw values (bytes as a number, most significant first).
  final bool small;
  final int bytes;
  final Set<int> values;

  /// Numeric comparison: datapoint type, `equals`/`notEquals`/`less`/`greater`, number.
  final (int, int?)? dpt;
  final String? op;
  final double? n;

  /// Check on the flags of the payload (see [bitsCheckMatches]).
  final Map<String, Object?>? bits;

  bool matches(Map<String, Object?> t) {
    if (t['d'] != address) return false;
    if (any) return true;
    final data = hexBytes(t['x'] as String? ?? '');
    final isSmall = t['m'] == true;
    if (bits case final bits?) return !isSmall && bitsCheckMatches(bits, data);
    if (values.isNotEmpty) {
      if (isSmall != small || (!small && data.length != bytes) || data.isEmpty) return false;
      return values.contains(data.fold<int>(0, (v, b) => (v << 8) | b));
    }
    final actual = number(t);
    final want = n;
    if (actual == null || want == null) return false;
    return switch (op) {
      'equals' => actual == want,
      'notEquals' => actual != want,
      'less' => actual < want,
      'greater' => actual > want,
      _ => false,
    };
  }

  /// Numeric value like the app's `numericValue`; `null` if the rule has no
  /// numeric comparison or the telegram does not match.
  double? number(Map<String, Object?> t) {
    final dpt = this.dpt;
    if (dpt == null || t['m'] == true) return null;
    return numericValue(dpt, hexBytes(t['x'] as String? ?? ''), small: false);
  }
}
