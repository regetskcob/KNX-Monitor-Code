import 'dart:convert';
import 'dart:io';

/// Alarm checking in the add-on – the same rules as in the app
/// (`lib/model/alarms.dart`), so notifications arrive even without an open
/// browser.
///
/// Alarm: DPT 1.005 or DPT 21.001 bit 3/4; fault: DPT 21.001 bit 1 or a 1-bit
/// address with a telling name. At most one notification per address per
/// [throttle], only on the change into the active state.
class AlarmWatch {
  AlarmWatch(this.data, {required this.notify, this.onChange, this.throttle = const Duration(minutes: 5)});

  final Directory data;
  final Future<void> Function({required String id, required String title, required String message}) notify;

  /// Every on or off change of an alarm or fault address, without throttling
  /// and even with notifications turned off (event for Home Assistant
  /// automations).
  final void Function(AlarmChange change)? onChange;
  final Duration throttle;

  bool enabled = true;
  String language = 'de';

  Map<int, _Group> _groups = const {};
  String _style = 'threeLevel';
  DateTime? _catalogTime;
  DateTime? _namesTime;
  final _active = <int, bool>{};

  /// Kind of the last active state per address: the reset reports the same
  /// kind (DPT 21.001 can carry both alarm and fault).
  final _activeKind = <int, String>{};
  final _lastSent = <int, DateTime>{};

  /// Alarm and fault addresses currently in the active state (since the start
  /// of the add-on; the state is not persisted).
  int get openCount => _active.values.where((on) => on).length;

  /// The most recent change of an address into the active state, with the
  /// telegram's time; `null` until one happens after the start.
  ({AlarmChange change, DateTime time})? lastTriggered;

  static final _alarmWords = RegExp(
    r'alarm|sabotage|tamper|einbruch|intrusion|burglar|leck|leak|rauch|smoke|brand|fire|überflut|flood|panik|panic',
  );
  static final _faultWords = RegExp(
    r'störung|stoerung|defekt|fehler|fault|error|failure|ausfall|malfunction|broken|trouble',
  );

  /// Rereads the catalog when the app has changed it, together with the names
  /// corrected in the app (`name_overrides.json`), which replace the project's.
  Future<void> _reloadCatalog() async {
    final file = File('${data.path}/catalog.json');
    final namesFile = File('${data.path}/name_overrides.json');
    try {
      final modified = await file.lastModified();
      final namesModified = await namesFile.exists() ? await namesFile.lastModified() : null;
      if (modified == _catalogTime && namesModified == _namesTime) return;
      _catalogTime = modified;
      _namesTime = namesModified;
      final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final names = await _readNames(namesFile);
      _style = json['style'] as String? ?? 'threeLevel';
      _groups = {
        for (final g in (json['groups'] as List? ?? const []).cast<Map<String, Object?>>())
          g['a']! as int: _Group(
            name: names[g['a']! as int] ?? g['n'] as String? ?? '',
            path: g['p'] as String?,
            main: (g['d'] as List?)?[0] as int?,
            sub: (g['d'] as List?)?[1] as int?,
          ),
      };
    } on Object {
      _groups = const {};
      _catalogTime = null;
      _namesTime = null;
    }
  }

  /// Corrected names by address; a missing or unreadable file corrects nothing.
  static Future<Map<int, String>> _readNames(File file) async {
    try {
      if (!await file.exists()) return const {};
      return {
        for (final MapEntry(:key, :value) in (jsonDecode(await file.readAsString()) as Map<String, Object?>).entries)
          if (int.tryParse(key) case final a? when value is String) a: value,
      };
    } on Object {
      return const {};
    }
  }

  /// Reads the catalog if it has changed (also used by the box clock).
  Future<void> loadCatalog() => _reloadCatalog();

  /// Main type of the datapoint from the project, otherwise `null`.
  int? dptMainOf(int group) => _groups[group]?.main;

  /// Group addresses of the project.
  Iterable<int> get groups => _groups.keys;

  /// Name of the group address (corrected in the app or from the project), otherwise `null`.
  String? nameOf(int group) => switch (_groups[group]?.name) {
    final String n when n.isNotEmpty => n,
    _ => null,
  };

  /// Datapoint type (main type, subtype) from the project, otherwise `null`.
  (int, int?)? dptOf(int group) => switch (_groups[group]?.main) {
    final int main => (main, _groups[group]?.sub),
    null => null,
  };

  /// `alarm`, `fault` or `null`: the same classification as the notifications.
  String? kindOf(int group) => _kind(_groups[group]);

  /// Name including path in lower case, for searching for keywords.
  String searchTextOf(int group) => switch (_groups[group]) {
    final g? => '${g.name} ${g.path ?? ''}'.toLowerCase(),
    null => '',
  };

  String? _kind(_Group? g) {
    if (g == null) return null;
    if (g.main == 1 && g.sub == 5) return 'alarm';
    if (g.main == 21 && g.sub == 1) return 'fault';
    if (g.main != null && g.main != 1) return null;
    final text = '${g.name} ${g.path ?? ''}'.toLowerCase();
    if (_alarmWords.hasMatch(text)) return 'alarm';
    if (_faultWords.hasMatch(text)) return 'fault';
    return null;
  }

  /// Checks a telegram line (same format as in the history).
  Future<void> check(Map<String, Object?> t) async {
    if (t['y'] == 0) return; // read request
    await _reloadCatalog();
    final address = t['d']! as int;
    final group = _groups[address];
    final kind = _kind(group);
    if (kind == null) return;
    final data = _hexBytes(t['x'] as String? ?? '');
    if (data.isEmpty) return;
    String? active;
    if (group!.main == 21) {
      if (data[0] & 0x18 != 0) {
        active = 'alarm';
      } else if (data[0] & 0x02 != 0) {
        active = 'fault';
      }
    } else if (t['m'] == true && data[0] & 0x01 == 1) {
      active = kind;
    }
    final was = _active[address] ?? false;
    _active[address] = active != null;
    if (active != null) _activeKind[address] = active;
    final time = DateTime.fromMicrosecondsSinceEpoch(t['t']! as int);
    if (was != (active != null)) {
      final change = AlarmChange(
        address: address,
        groupAddress: formatGroup(address),
        name: group.name,
        kind: active ?? _activeKind[address] ?? kind,
        active: active != null,
      );
      // Set before the callback so listeners see the new state.
      if (change.active) lastTriggered = (change: change, time: time);
      onChange?.call(change);
    }
    if (active == null || was || !enabled) return;
    final last = _lastSent[address];
    if (last != null && time.difference(last) < throttle) return;
    _lastSent[address] = time;
    final de = language.startsWith('de');
    final name = group.name.isEmpty ? _formatGroup(address) : group.name;
    final title = switch ((active, de)) {
      ('fault', true) => 'Störung: $name',
      ('fault', false) => 'Fault: $name',
      (_, true) => 'Alarm: $name',
      _ => 'Alarm: $name',
    };
    final clock = [time.hour, time.minute, time.second].map((v) => v.toString().padLeft(2, '0')).join(':');
    await notify(id: 'knx_$address', title: title, message: '${_formatGroup(address)} · $clock');
  }

  /// Group address in the project's style (three-level, two-level or free).
  String formatGroup(int a) => _formatGroup(a);

  String _formatGroup(int a) => switch (_style) {
    'twoLevel' => '${(a >> 11) & 0x1F}/${a & 0x7FF}',
    'free' => '$a',
    _ => '${(a >> 11) & 0x1F}/${(a >> 8) & 0x07}/${a & 0xFF}',
  };

  static List<int> _hexBytes(String s) => [
    for (var i = 0; i + 1 < s.length; i += 2) int.tryParse(s.substring(i, i + 2), radix: 16) ?? 0,
  ];
}

/// An alarm or fault address changes; [kind] is `alarm` or `fault`.
class AlarmChange {
  const AlarmChange({
    required this.address,
    required this.groupAddress,
    required this.name,
    required this.kind,
    required this.active,
  });

  final int address;
  final String groupAddress;
  final String name;
  final String kind;
  final bool active;
}

class _Group {
  const _Group({required this.name, this.path, this.main, this.sub});
  final String name;
  final String? path;
  final int? main;
  final int? sub;
}
