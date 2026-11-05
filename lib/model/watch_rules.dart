import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../platform/addon.dart';
import 'installation.dart';
import 'plan.dart';
import 'telegram_log.dart';
import 'trigger.dart';

/// Watcher: alerts with a sound and notification as soon as a group address is
/// sent (optionally with a value). Same condition as the trigger recording
/// ([TriggerConfig]); the JSON format is designed so that the KNX box and the
/// add-on server can evaluate the same rules.
class WatchRule {
  const WatchRule({
    required this.id,
    required this.address,
    this.value,
    this.compare = ValueCompare.contains,
    this.sound = true,
    this.enabled = true,
  });

  factory WatchRule.fromJson(Map<String, Object?> j) => WatchRule(
    id: j['id']! as String,
    address: j['address']! as int,
    value: j['value'] as String?,
    compare: ValueCompare.values.asNameMap()[j['compare']] ?? ValueCompare.contains,
    sound: j['sound'] as bool? ?? true,
    enabled: j['enabled'] as bool? ?? true,
  );

  final String id;
  final int address;

  /// Optional: value to compare against (plain text, e.g. "Ein", on).
  final String? value;

  /// Comparison with [value]; older rules without one: "contains".
  final ValueCompare compare;

  /// With sound; otherwise only a notification and a notice in the app.
  final bool sound;
  final bool enabled;

  TriggerConfig get condition =>
      TriggerConfig(kind: TriggerKind.address, address: address, value: value, compare: compare);

  bool matches(Telegram t, TelegramLog log) => enabled && condition.matches(t, log);

  String describe() => condition.describe();

  /// Datapoint types whose numeric value the server reads itself (like [numericValue]).
  static const _serverNumeric = {5, 6, 7, 8, 9, 12, 13, 14};

  /// The app does not send more matching raw values than this; the rule is then
  /// only checked by the app.
  static const _maxValues = 4096;

  static final _noLog = TelegramLog();

  /// For add-on and box: the rule in a form the server can check without its own
  /// DPT conversion – without a value every telegram, for numbers a comparison,
  /// otherwise the matching raw values (determined with the same check as in the
  /// app). `null` if that is not possible; then the app checks it.
  Map<String, Object?>? serverCheck() {
    final want = value?.trim() ?? '';
    if (want.isEmpty) return const {'any': true};
    final dpt = CatalogStore.instance.dptOf(address);
    final number = double.tryParse(want.replaceAll(',', '.'));
    if (compare != ValueCompare.contains && number != null && dpt != null && _serverNumeric.contains(dpt.main)) {
      return {
        'num': [dpt.main, dpt.sub],
        'op': compare.name,
        'n': number,
      };
    }
    final (small, bytes) = _shapeOf(dpt) ?? (false, -1);
    if (bytes < 0) return null;
    final values = <int>[];
    final count = small ? 64 : 1 << (8 * bytes);
    for (var v = 0; v < count; v++) {
      final t = Telegram(
        time: DateTime(2000),
        source: 0,
        destination: address,
        type: TelegramType.write,
        data: Uint8List.fromList(small ? [v] : [for (var i = bytes - 1; i >= 0; i--) (v >> (8 * i)) & 0xFF]),
        isSmall: small,
      );
      if (!condition.matches(t, _noLog)) continue;
      values.add(v);
      if (values.length > _maxValues) return null;
    }
    return {'small': small, 'bytes': bytes, 'values': values};
  }

  /// Payload of a datapoint type: in the APCI byte (≤ 6 bits) or number of bytes;
  /// `null` for types whose values cannot be enumerated.
  static (bool, int)? _shapeOf(Dpt? dpt) => switch (dpt?.main) {
    1 || 2 || 3 || 23 => (true, 0),
    4 || 5 || 6 || 17 || 18 || 20 || 26 => (false, 1),
    7 || 8 || 9 || 22 => (false, 2),
    _ => null,
  };

  WatchRule copyWith({bool? sound, bool? enabled}) => WatchRule(
    id: id,
    address: address,
    value: value,
    compare: compare,
    sound: sound ?? this.sound,
    enabled: enabled ?? this.enabled,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'address': address,
    if (value != null && value!.isNotEmpty) 'value': value,
    if (value != null && value!.isNotEmpty && compare != ValueCompare.contains) 'compare': compare.name,
    'sound': sound,
    'enabled': enabled,
  };
}

/// A hit: which rule, which telegram; [fromServer]: reported by the add-on or
/// box, the notification to Home Assistant has already been sent.
typedef WatchHit = ({WatchRule rule, Telegram telegram, bool fromServer});

/// The device's rules and their evaluation in the live monitor.
class WatchRules extends ValueNotifier<List<WatchRule>> {
  WatchRules._() : super(const []);

  static final instance = WatchRules._();
  static const _key = 'watch_rules';

  /// Rules for add-on and box, next to the installation's project.
  static const serverPath = 'watch_rules.json';

  /// Rules the server checks (ids); the app does not check them again on the
  /// shared tunnel.
  Set<String> _serverRules = const {};
  String? _shared;
  bool _following = false;
  bool _loaded = false;

  /// The same rule alerts at most this often (bouncing push buttons, cyclic
  /// senders) – otherwise it would ring every second.
  static const cooldown = Duration(seconds: 3);

  final _hits = StreamController<WatchHit>.broadcast();
  final _last = <String, DateTime>{};

  /// Hits for the UI (sound, notification, notice).
  Stream<WatchHit> get hits => _hits.stream;

  /// Whether at least one rule is armed.
  bool get armed => value.any((r) => r.enabled);

  Future<void> load() async {
    try {
      await _load();
    } finally {
      // Store only afterwards – otherwise an early project switch would overwrite the
      // server's rules with an empty list.
      _loaded = true;
      _follow();
    }
  }

  Future<void> _load() async {
    // In the add-on the server's rules apply – the same for all browsers.
    if (Addon.embedded) {
      try {
        final shared = await InstallationStore.instance.storage.read(serverPath);
        if (shared != null) {
          final rules = (jsonDecode(shared) as Map<String, Object?>)['rules'] as List? ?? const [];
          value = [for (final j in rules) WatchRule.fromJson((j as Map).cast<String, Object?>())];
          return;
        }
      } on Object catch (e) {
        debugPrint('Wächter im Add-on nicht lesbar: $e');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      value = [for (final j in jsonDecode(raw) as List) WatchRule.fromJson((j as Map).cast<String, Object?>())];
    } on Object catch (e) {
      debugPrint('Wächter nicht lesbar: $e');
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode([for (final r in value) r.toJson()]));
    await share();
  }

  /// The project (types, names) and the tier determine what the server may check.
  void _follow() {
    if (_following || !Addon.available) return;
    _following = true;
    void again() => unawaited(share().catchError((Object e) => debugPrint('Wächter: $e')));
    CatalogStore.instance.addListener(again);
    Plan.instance.addListener(again);
  }

  /// Rule with a description for the notification and a checkable form; without
  /// the watcher tier, without [WatchRule.serverCheck] (the server then does not check it).
  static Map<String, Object?> _serverEntry(WatchRule r, {required bool allowed}) {
    final name = CatalogStore.instance.info(r.address)?.name;
    return {
      ...r.toJson(),
      'label': r.describe(),
      if (name != null && name.isNotEmpty) 'name': name,
      if (allowed) 'check': ?r.serverCheck(),
    };
  }

  /// Stores the rules on the add-on or box so they take effect there even without
  /// the app open and arrive as notifications.
  Future<void> share() async {
    if (!_loaded) return;
    final allowed = Plan.instance.allows(Feature.watcher);
    final server = <String>{};
    final rules = [for (final r in value) _serverEntry(r, allowed: allowed)];
    for (final r in rules) {
      if (r['check'] != null) server.add(r['id']! as String);
    }
    _serverRules = server;
    if (!Addon.available) return;
    final text = jsonEncode({'rules': rules});
    if (text == _shared) return;
    _shared = text;
    if (Addon.box != null) {
      await Addon.putFile(serverPath, utf8.encode(text));
    } else {
      await InstallationStore.instance.storage.write(serverPath, text);
    }
  }

  Future<void> add(WatchRule rule) async {
    value = [...value, rule];
    await _save();
  }

  Future<void> replace(WatchRule rule) async {
    value = [for (final r in value) r.id == rule.id ? rule : r];
    await _save();
  }

  /// Puts [rule] back at [index] (clamped), e.g. to undo [remove]. A rule that
  /// is already there stays once (Undo tapped twice).
  Future<void> insert(int index, WatchRule rule) async {
    if (value.any((r) => r.id == rule.id)) return;
    value = [...value]..insert(index.clamp(0, value.length), rule);
    await _save();
  }

  Future<void> remove(String id) async {
    value = [
      for (final r in value)
        if (r.id != id) r,
    ];
    await _save();
  }

  /// Whether there is already a rule for [address].
  WatchRule? forAddress(int address) {
    for (final r in value) {
      if (r.address == address) return r;
    }
    return null;
  }

  /// Checks an incoming telegram (from the live monitor). [server]: on the shared
  /// tunnel of the add-on or box – there the server checks the rules it can and
  /// reports them via [report].
  void check(Telegram t, TelegramLog log, {DateTime? now, bool server = false}) {
    final at = now ?? DateTime.now();
    for (final r in value) {
      if (server && _serverRules.contains(r.id)) continue;
      if (!r.matches(t, log)) continue;
      _hit(r, t, at, fromServer: false);
    }
  }

  /// Hits reported by the server.
  void report(Iterable<String> ids, Telegram t, {DateTime? now}) {
    final at = now ?? DateTime.now();
    for (final r in value) {
      if (r.enabled && ids.contains(r.id)) _hit(r, t, at, fromServer: true);
    }
  }

  void _hit(WatchRule r, Telegram t, DateTime at, {required bool fromServer}) {
    final last = _last[r.id];
    if (last != null && at.difference(last) < cooldown) return;
    _last[r.id] = at;
    _hits.add((rule: r, telegram: t, fromServer: fromServer));
  }
}

/// Throttles how loud a watcher gets per hit: sound at most every [soundEvery],
/// system notification (and vibration only with it) at most every
/// [notifyEvery] – a frequently sending address should not ring and buzz
/// constantly. The notice in the app comes with every hit.
class WatchAlertThrottle {
  static const soundEvery = Duration(seconds: 5);
  static const notifyEvery = Duration(seconds: 30);

  final _lastSound = <String, DateTime>{};
  final _lastNotify = <String, DateTime>{};

  /// What may sound when watcher [id] hits at time [now].
  /// [canNotify]: the app sends notifications itself here (not in the add-on,
  /// where the server does it).
  ({bool sound, bool notify, bool vibrate}) hit(
    String id,
    DateTime now, {
    required bool wantsSound,
    required bool canNotify,
  }) {
    bool due(Map<String, DateTime> last, Duration every) {
      final at = last[id];
      if (at != null && now.difference(at) < every) return false;
      last[id] = now;
      return true;
    }

    final notify = canNotify && due(_lastNotify, notifyEvery);
    final sound = wantsSound && due(_lastSound, soundEvery);
    return (sound: sound, notify: notify, vibrate: sound && notify);
  }
}
