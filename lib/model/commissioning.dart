import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../catalog_store.dart';
import '../knx/group_catalog.dart';
import '../knx/knx_tunnel.dart';
import '../knx/demo_tunnel.dart';
import '../knx/read_sweep.dart';
import '../knx/telegram.dart';
import '../platform/storage.dart';
import 'installation.dart';

/// Status and feedback addresses – German and English names.
final _statusName = RegExp(
  r'status|rückmeld|rücmled|\brm\b|ist[- ]|feedback|zustand|actual|\bstate\b',
  caseSensitive: false,
);

/// Whether [g] is one of the addresses that should respond during commissioning.
bool isStatusGroup(GroupInfo g) => _statusName.hasMatch(g.name) || _statusName.hasMatch(g.path ?? '');

/// Addresses for the checklist: status addresses (for projects with
/// associations, only the associated ones), or all of them with [all].
List<int> commissioningScope({bool all = false}) {
  final groups = CatalogStore.instance.catalog.groups.values;
  final hasLinks = groups.any((g) => g.links.isNotEmpty);
  return [
    for (final g in groups)
      if (all || (isStatusGroup(g) && (!hasLinks || g.links.isNotEmpty))) g.address,
  ]..sort();
}

/// Whether [source] sends to [address] although, according to the project,
/// another device sends there. Only if the project knows sending associations
/// for the address.
bool isForeignSender(int address, int source) {
  final senders = {
    for (final l in CatalogStore.instance.catalog[address]?.links ?? const <GroupLink>[])
      if (l.sends) l.device,
  };
  return senders.isNotEmpty && !senders.contains(source);
}

/// Addresses for the ring-through test: all with a sending device in the project
/// (push buttons, sensors, status feedback). Without associations (CSV), all.
List<int> rollCallScope() {
  final groups = CatalogStore.instance.catalog.groups.values;
  final hasLinks = groups.any((g) => g.links.isNotEmpty);
  return [
    for (final g in groups)
      if (!hasLinks || g.links.any((l) => l.sends)) g.address,
  ]..sort();
}

/// Result of a check item.
enum CheckState {
  /// Not checked yet.
  open,

  /// The device responded to the read request.
  answered,

  /// Seen on the bus during the ring-through test (write or response).
  seen,

  /// No response within the response window.
  noAnswer,

  /// Ticked off by hand as OK (e.g. function checked on site).
  ok,

  /// Marked by hand as a problem.
  issue;

  bool get done => this == answered || this == seen || this == ok;
}

/// A check item: a group address with its result.
class CheckItem {
  CheckItem(
    this.address, {
    this.state = CheckState.open,
    this.value,
    this.source,
    this.time,
    this.note,
    this.foreign = false,
  });

  final int address;
  CheckState state;

  /// Response value in plain text.
  String? value;

  /// Responding device.
  int? source;
  DateTime? time;
  String? note;

  /// The sender is not the device that, according to the project, sends to this
  /// address (swapped wiring, wrong individual address).
  bool foreign;

  Map<String, Object?> toJson() => {
    'a': address,
    's': state.name,
    'v': ?value,
    'src': ?source,
    't': ?time?.millisecondsSinceEpoch,
    'n': ?note,
    if (foreign) 'f': true,
  };

  factory CheckItem.fromJson(Map<String, Object?> j) => CheckItem(
    j['a']! as int,
    state: CheckState.values.asNameMap()[j['s']] ?? CheckState.open,
    value: j['v'] as String?,
    source: j['src'] as int?,
    time: j['t'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['t']! as int),
    note: j['n'] as String?,
    foreign: j['f'] == true,
  );
}

/// Commissioning checklist: read status addresses, tick off responses, rate the
/// rest by hand. Stays saved until it is restarted – commissioning often takes
/// several days.
class Commissioning extends ChangeNotifier {
  Commissioning._();

  static final instance = Commissioning._();
  static const _path = 'commissioning.json';

  /// Check items in address order.
  final items = <int, CheckItem>{};
  DateTime? started;
  bool _loaded = false;

  bool running = false;

  /// Ring-through test: tick off addresses as soon as they are sent on the bus
  /// (press a push button, open a window), without an active read request.
  bool rollCall = false;
  int sent = 0;
  int toSend = 0;

  double get progress => toSend == 0 ? 1 : sent / toSend;
  int count(CheckState state) => items.values.where((i) => i.state == state).length;
  int get checked => items.values.where((i) => i.state != CheckState.open).length;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final read = await readStored(InstallationStore.instance.storage, _path, (text) {
      final j = jsonDecode(text) as Map<String, Object?>;
      started = j['started'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['started']! as int);
      rollCall = j['rollCall'] == true;
      for (final e in (j['items'] as List? ?? const [])) {
        final item = CheckItem.fromJson(e as Map<String, Object?>);
        items[item.address] = item;
      }
      return true;
    });
    if (read == true) notifyListeners();
  }

  /// Demo starts: empty state in memory only; the saved one stays untouched.
  void startDemo() {
    cancel();
    _clear();
    _loaded = true;
    notifyListeners();
  }

  /// Reloads the saved state (after a demo).
  Future<void> reload() async {
    cancel();
    _clear();
    _loaded = false;
    await load();
    notifyListeners();
  }

  final _saving = <Future<void>>{};

  Future<void> _save() async {
    if (DemoTunnel.active) return; // Demo: do not persist anything
    final write = _write();
    _saving.add(write);
    try {
      await write;
    } finally {
      _saving.remove(write);
    }
  }

  /// Waits until pending saves are done (switching installations, tests that
  /// clean up their folder). A still-delayed save (see [observe]) runs
  /// immediately.
  Future<void> flush() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      unawaited(_save());
    }
    return Future.wait([..._saving]).then((_) {}, onError: (Object _) {});
  }

  Future<void> _write() => InstallationStore.instance.storage.write(
    _path,
    jsonEncode({
      'started': started?.millisecondsSinceEpoch,
      if (rollCall) 'rollCall': true,
      'items': [for (final i in items.values) i.toJson()],
    }),
  );

  /// Creates check items for [addresses]; existing results remain.
  void prepare(Iterable<int> addresses) {
    started ??= DateTime.now();
    final sorted = {...items.keys, ...addresses}.toList()..sort();
    final old = Map.of(items);
    items
      ..clear()
      ..addAll({for (final a in sorted) a: old[a] ?? CheckItem(a)});
    notifyListeners();
    unawaited(_save());
  }

  /// Discards all results and starts over with [addresses].
  void restart(Iterable<int> addresses) {
    cancel();
    items.clear();
    started = null;
    prepare(addresses);
  }

  /// Sets a result by hand (OK, problem, or open again).
  void mark(int address, CheckState state) {
    final item = items[address];
    if (item == null) return;
    item.state = state;
    if (state == CheckState.open) {
      item
        ..value = null
        ..source = null
        ..time = null
        ..foreign = false;
    }
    notifyListeners();
    unawaited(_save());
  }

  /// Turns the ring-through test on or off.
  void setRollCall(bool on) {
    if (rollCall == on) return;
    rollCall = on;
    notifyListeners();
    unawaited(_save());
  }

  /// Telegram from the bus during the ring-through test: a write or response
  /// ticks off an open (or silent) address. Items that were read or rated by hand
  /// stay as they are; telegrams sent by us do not count.
  /// Returns the ticked item (for the sound acknowledgement), otherwise `null`.
  CheckItem? observe(Telegram t) {
    if (!rollCall || t.outgoing || t.type == TelegramType.read) return null;
    final item = items[t.destination];
    if (item == null || (item.state != CheckState.open && item.state != CheckState.noAnswer)) return null;
    item
      ..state = CheckState.seen
      ..value = CatalogStore.instance.value(t)
      ..source = t.source
      ..time = t.time
      ..foreign = isForeignSender(t.destination, t.source);
    notifyListeners();
    _scheduleSave();
    return item;
  }

  /// Takes the result of a check made elsewhere (switching a DALI group and watching its
  /// feedback): creates the item if it is missing. A rating by hand (OK, problem) stays; a [note]
  /// replaces the previous one only when given.
  void record(
    int address, {
    required CheckState state,
    String? value,
    int? source,
    DateTime? time,
    bool foreign = false,
    String? note,
  }) {
    started ??= DateTime.now();
    if (!items.containsKey(address)) {
      // Keep the address order of the list.
      final old = Map.of(items);
      items
        ..clear()
        ..addAll({
          for (final a in {...old.keys, address}.toList()..sort()) a: old[a] ?? CheckItem(a),
        });
    }
    final item = items[address]!;
    if (item.state != CheckState.ok && item.state != CheckState.issue) item.state = state;
    item
      ..value = value
      ..source = source
      ..time = time
      ..foreign = foreign;
    if (note != null) item.note = note;
    notifyListeners();
    _scheduleSave();
  }

  /// One push button after another: do not write after every telegram.
  Timer? _saveTimer;
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () => unawaited(_save()));
  }

  void setNote(int address, String? note) {
    final item = items[address];
    if (item == null) return;
    item.note = note == null || note.trim().isEmpty ? null : note.trim();
    notifyListeners();
    unawaited(_save());
  }

  /// Reads [addresses] one after another; responses are ticked off, and whatever
  /// stays silent after the response window counts as "no response". Results set
  /// by hand (OK/problem) remain untouched.
  Future<void> read(KnxTunnel tunnel, List<int> addresses) async {
    if (running) return;
    running = true;
    sent = 0;
    toSend = addresses.length;
    final store = CatalogStore.instance;
    bool manual(CheckItem? i) => i == null || i.state == CheckState.ok || i.state == CheckState.issue;
    notifyListeners();
    try {
      final answers = await ReadSweep.run(
        tunnel,
        addresses,
        cancelled: () => !running,
        onSent: (n) {
          sent = n;
          notifyListeners();
        },
        onAnswer: (t) {
          final item = items[t.destination];
          if (manual(item)) return;
          item!
            ..state = CheckState.answered
            ..value = store.value(t)
            ..source = t.source
            ..time = t.time
            ..foreign = isForeignSender(t.destination, t.source);
          notifyListeners();
        },
      );
      if (running) {
        // Silent this time – an earlier response no longer counts either.
        for (final a in addresses) {
          final item = items[a];
          if (answers.containsKey(a) || manual(item)) continue;
          item!
            ..state = CheckState.noAnswer
            ..value = null
            ..source = null
            ..time = null
            ..foreign = false;
        }
      }
    } finally {
      running = false;
      notifyListeners();
      await _save();
    }
  }

  void cancel() {
    if (!running) return;
    running = false;
    notifyListeners();
  }

  /// For tests only: allows [load] again.
  @visibleForTesting
  void debugAllowLoad() => _loaded = false;

  /// For tests only: resets the state without saving.
  void _clear() {
    items.clear();
    started = null;
    rollCall = false;
    _saveTimer?.cancel();
  }

  @visibleForTesting
  void debugReset() {
    running = false;
    _clear();
    _loaded = true;
  }
}
