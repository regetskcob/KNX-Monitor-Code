import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../catalog_store.dart';
import '../knx/demo_tunnel.dart';
import '../knx/telegram.dart';
import '../platform/addon.dart';
import 'dali.dart';
import 'dali_demo.dart';
import 'history_store.dart';
import 'installation.dart';
import 'server_features.dart';

/// Whether the last result of a test kind is recent enough.
enum TestDue {
  /// No result seen yet.
  none,

  /// A result within the interval.
  current,

  /// The last result was the first one seen for this luminaire: the test may be much older, its
  /// age is unknown. Neither current nor overdue.
  unknownAge,

  /// No new result for longer than the interval.
  overdue,
}

/// An emergency luminaire in the log: its last results and whether a test is due.
class EmergencyOverview {
  EmergencyOverview({required this.group, this.gear, this.gateway});

  /// Group address of the test result object.
  final int group;

  /// The luminaire, if the model knows it.
  final DaliGear? gear;
  final int? gateway;

  /// Last results from the gateway (foreign ones never count).
  EmergencyTest? lastFunction;
  EmergencyTest? lastDuration;
  EmergencyTest? lastPartial;
  TestDue functionDue = TestDue.none;
  TestDue durationDue = TestDue.none;

  /// Results from another sender than the gateway: shown, never counted.
  int foreign = 0;

  /// The last function or duration test failed.
  bool get failed => lastFunction?.result == EmergencyResult.failed || lastDuration?.result == EmergencyResult.failed;
  bool get overdue => functionDue == TestDue.overdue || durationDue == TestDue.overdue;

  /// Needs a look: overdue, failed, age unknown, or no result at all yet.
  bool get open =>
      overdue ||
      failed ||
      functionDue == TestDue.unknownAge ||
      durationDue == TestDue.unknownAge ||
      (lastFunction == null && lastDuration == null);
}

/// The emergency lighting log of the active installation: what the converters of self-testing
/// emergency luminaires reported, one line per result in `dali_tests/<year>.ndjson`. Lines are
/// only ever appended, at most [emergencyLogMaxBytes] per year.
///
/// On the add-on and the box the server writes the log, also at night without an open app; the
/// app then only reads. Without such a server the app writes while it is connected.
class DaliTestLog extends ChangeNotifier {
  DaliTestLog._() {
    DaliStore.instance
      ..onTests = record
      ..testFailedOf = _testFailed;
  }

  static final instance = DaliTestLog._();
  static const dir = 'dali_tests';

  final _entries = <EmergencyTest>[];
  final _keys = <String>{};
  bool _loaded = false;

  /// Result objects whose last counting function or duration test failed.
  final _failedGroups = <int>{};

  /// Years whose file reached its limit or was read only in part: entries may be missing.
  final limitedYears = <int>{};

  final _added = StreamController<List<EmergencyTest>>.broadcast();

  /// New results from the live monitor (for the notifications).
  Stream<List<EmergencyTest>> get added => _added.stream;

  /// All entries, oldest first.
  List<EmergencyTest> get entries {
    _syncDemo();
    return List.unmodifiable(_entries);
  }

  bool _testFailed(DaliGear gear) {
    _syncDemo();
    final group = gear.resultGroup;
    if (group != null) return _failedGroups.contains(group);
    // A luminaire whose result object the project no longer has, known by its address.
    return _entries.any(
      (e) => !e.foreign && e.gateway == gear.gateway && e.address == gear.address && _failedGroups.contains(e.group),
    );
  }

  ({List<EmergencyTest> entries, Set<String> keys, Set<int> failed})? _beforeDemo;

  /// The demo house has its own log in memory (see [DaliStore]): entering the demo sets the
  /// installation's entries aside and shows the demo's, leaving it brings them back.
  void _syncDemo() {
    if (DemoTunnel.active == (_beforeDemo != null)) return;
    // The store first: it swaps the tracker the entries are announced to.
    DaliStore.instance.project;
    if (DemoTunnel.active) {
      _beforeDemo = (entries: List.of(_entries), keys: Set.of(_keys), failed: Set.of(_failedGroups));
      _clear();
      _take(demoEmergencyLog(DemoTunnel.clock()));
    } else {
      final before = _beforeDemo!;
      _beforeDemo = null;
      _clear();
      _entries.addAll(before.entries);
      _keys.addAll(before.keys);
      _failedGroups.addAll(before.failed);
    }
  }

  /// Text of a file, at most [emergencyLogReadBytes] of it; `cut` if there was more.
  static ({String text, bool cut}) _head(String text) {
    if (text.length <= emergencyLogReadBytes) return (text: text, cut: false);
    return (text: text.substring(0, emergencyLogReadBytes), cut: true);
  }

  void _readFile(String name, String content, List<EmergencyTest> into) {
    final (:text, :cut) = _head(content);
    final read = readEmergencyLog(text, cut: cut);
    into.addAll(read.entries);
    if (read.overflow || read.truncated) {
      if (int.tryParse(name.substring(0, 4)) case final year?) limitedYears.add(year);
    }
  }

  Future<void> load() async {
    // In the demo the installation's log stays closed; it is read when the demo is over.
    if (_loaded || DemoTunnel.active) return;
    _loaded = true;
    final found = <EmergencyTest>[];
    try {
      final storage = InstallationStore.instance.storage;
      for (final f in await storage.list(dir)) {
        if (!RegExp(r'^\d{4}\.ndjson$').hasMatch(f.name)) continue;
        try {
          final text = await storage.read('$dir/${f.name}');
          if (text != null) _readFile(f.name, text, found);
        } on Object catch (e) {
          debugPrint('Prüfbuch ${f.name} nicht lesbar: $e');
        }
      }
    } on Object catch (e) {
      debugPrint('Prüfbuch nicht lesbar: $e');
    }
    if (Addon.box != null) found.addAll(await _fromBox());
    _take(found);
    notifyListeners();
  }

  /// Via the Busclear Box: the log it wrote, not only what this device saw.
  Future<List<EmergencyTest>> _fromBox() async {
    final result = <EmergencyTest>[];
    try {
      final installations = InstallationStore.instance;
      final id = installations.boxIdOf(installations.active.id);
      List<Object?> files;
      var inRoot = false;
      try {
        files = await Addon.listInstallationFiles(id, dir);
      } on AddonException catch (e) {
        if (e.status != 404) rethrow;
        // Older boxes do not know installations and keep everything in the root.
        inRoot = true;
        files = await Addon.listFiles(dir);
      }
      for (final f in files.whereType<Map<Object?, Object?>>()) {
        final name = f['name'];
        if (name is! String || !RegExp(r'^\d{4}\.ndjson$').hasMatch(name)) continue;
        final bytes = inRoot ? await Addon.getFile('$dir/$name') : await Addon.getInstallationFile(id, '$dir/$name');
        if (bytes != null) _readFile(name, utf8.decode(bytes, allowMalformed: true), result);
      }
    } on Object catch (e) {
      debugPrint('Prüfbuch der Box nicht gelesen: $e');
    }
    return result;
  }

  /// Adds what is new of [found] (in memory) and tells the tracker what is known already.
  List<EmergencyTest> _take(Iterable<EmergencyTest> found) {
    final fresh = [
      for (final e in found)
        if (_keys.add(e.key)) e,
    ];
    if (fresh.isEmpty) return fresh;
    _entries
      ..addAll(fresh)
      ..sort((a, b) => a.time.compareTo(b.time));
    final last = <(int, EmergencyTestKind), EmergencyTest>{};
    for (final e in _entries) {
      DaliStore.instance.tracker.seed(e);
      if (!e.foreign) last[(e.group, e.kind)] = e;
    }
    _failedGroups
      ..clear()
      ..addAll([
        for (final MapEntry(key: (group, kind), value: e) in last.entries)
          if (kind != EmergencyTestKind.partial && e.result == EmergencyResult.failed) group,
      ]);
    return fresh;
  }

  /// Whether this app writes the log: not when a server keeps it, and on a server's tunnel not
  /// before its status said what it can (a log written twice has every entry twice).
  bool get _appWrites {
    if (DemoTunnel.active) return false;
    final features = ServerFeatures.instance;
    if (!Addon.available) return !features.dali;
    return features.known && !features.dali;
  }

  /// Whether the server keeps the log (rebuilding is then its business).
  bool get serverKeeps => ServerFeatures.instance.dali;

  /// New results from the live monitor. Written by the app unless the server keeps the log.
  void record(List<EmergencyTest> entries) {
    _syncDemo();
    final fresh = _take(entries);
    if (fresh.isEmpty) return;
    notifyListeners();
    _added.add(fresh);
    if (_appWrites) unawaited(_append(fresh));
  }

  Future<void> _append(List<EmergencyTest> entries) async {
    final byYear = <int, List<EmergencyTest>>{};
    for (final e in entries) {
      (byYear[e.time.year] ??= []).add(e);
    }
    try {
      final storage = InstallationStore.instance.storage;
      final sizes = {for (final f in await storage.list(dir)) f.name: f.size};
      for (final MapEntry(key: year, value: list) in byYear.entries) {
        if (limitedYears.contains(year)) continue;
        final chunk = emergencyLogChunk(sizes['$year.ndjson'] ?? 0, list, DateTime.now());
        if (chunk.text.isNotEmpty) await storage.append(emergencyLogPath(year), chunk.text);
        if (chunk.overflow || (sizes['$year.ndjson'] ?? 0) >= emergencyLogMaxBytes) {
          limitedYears.add(year);
          notifyListeners();
        }
      }
    } on Object catch (e) {
      debugPrint('Prüfbuch nicht geschrieben: $e');
    }
  }

  /// Rebuilds entries from the daily history, as far as it reaches: what the app missed while it
  /// was closed or before the log existed. Returns how many entries were added; `null` when the
  /// server keeps the log (it recorded without gaps, rebuilding would only add every entry twice).
  Future<int?> rebuildFromHistory() async {
    if (serverKeeps || (Addon.available && !ServerFeatures.instance.known)) return null;
    await load();
    final history = HistoryStore.instance;
    final days = (await history.days()).toList()..sort((a, b) => a.date.compareTo(b.date));
    if (days.isEmpty) return 0;
    final store = CatalogStore.instance;
    final dali = DaliStore.instance;
    final tracker = EmergencyTracker();
    // What was known before the history starts, so its first telegram is not a "first" result.
    final start = days.first.date;
    for (final e in _entries) {
      if (e.time.isBefore(start)) tracker.seed(e);
    }
    final found = <EmergencyTest>[];
    for (final day in days) {
      final List<Telegram> telegrams;
      try {
        telegrams = (await history.open(day, name: '')).telegrams;
      } on Object catch (e) {
        debugPrint('Tagesverlauf ${day.path} nicht lesbar: $e');
        continue;
      }
      for (final t in telegrams) {
        if (t.type == TelegramType.read || t.isSmall || t.outgoing) continue;
        final dpt = store.dptOf(t.destination);
        if (dpt == null || !isDaliDpt(dpt.main, dpt.sub)) continue;
        final object = dali.project.objects[t.destination];
        if (dpt.main == 244) {
          final status = decodeConverterStatus(t.data);
          final gear = dali.gearOf(object?.gateway ?? t.source).where((g) => g.statusGroup == t.destination);
          if (status != null && gear.firstOrNull?.resultGroup != null) {
            tracker.status(gear.first.resultGroup!, status, trusted: object == null || object.gateway == t.source);
          }
        } else if (dpt.main == 245) {
          final gear = dali.gearOfResult(t.destination);
          found.addAll(
            tracker.result(
              t.destination,
              t.data,
              t.time,
              gateway: object?.gateway ?? t.source,
              address: gear?.address ?? object?.index,
              source: t.source,
            ),
          );
        }
      }
    }
    final fresh = _take(found);
    if (fresh.isEmpty) return 0;
    notifyListeners();
    if (_appWrites) await _append(fresh);
    return fresh.length;
  }

  /// Entries between [from] and [to] (both optional), oldest first.
  List<EmergencyTest> between(DateTime? from, DateTime? to) => [
    for (final e in entries)
      if ((from == null || !e.time.isBefore(from)) && (to == null || !e.time.isAfter(to))) e,
  ];

  /// One row per emergency luminaire: the ones the model knows and every object with an entry.
  /// Failed first, then overdue, then by address.
  List<EmergencyOverview> overview(DateTime now) {
    _syncDemo();
    final dali = DaliStore.instance;
    final rows = <int, EmergencyOverview>{};
    final withoutResult = <EmergencyOverview>[];
    for (final gear in dali.emergencyGear) {
      final row = EmergencyOverview(group: gear.resultGroup ?? -1, gear: gear, gateway: gear.gateway);
      gear.resultGroup == null ? withoutResult.add(row) : rows[gear.resultGroup!] = row;
    }
    for (final e in _entries) {
      final row = rows.putIfAbsent(
        e.group,
        () => EmergencyOverview(
          group: e.group,
          gateway: e.gateway,
          // A luminaire whose result object the project no longer has, known by its address.
          gear: e.gateway != null && e.address != null ? dali.gear(e.gateway!, e.address!) : null,
        ),
      );
      if (e.foreign) {
        row.foreign++;
        continue;
      }
      switch (e.kind) {
        case EmergencyTestKind.function:
          row.lastFunction = e;
        case EmergencyTestKind.duration:
          row.lastDuration = e;
        case EmergencyTestKind.partial:
          row.lastPartial = e;
      }
    }
    TestDue due(EmergencyTest? last, int days) => last == null
        ? TestDue.none
        : now.difference(last.time) > Duration(days: days)
        ? TestDue.overdue
        : last.first
        ? TestDue.unknownAge
        : TestDue.current;
    final all = [...rows.values, ...withoutResult];
    for (final row in all) {
      row
        ..functionDue = due(row.lastFunction, dali.settings.functionDays)
        ..durationDue = due(row.lastDuration, dali.settings.durationDays);
    }
    int rank(EmergencyOverview r) => r.failed
        ? 0
        : r.overdue
        ? 1
        : 2;
    return all..sort((a, b) {
      if (rank(a) != rank(b)) return rank(a).compareTo(rank(b));
      return (a.gear?.address ?? 100 + a.group).compareTo(b.gear?.address ?? 100 + b.group);
    });
  }

  /// Days between [from] and [to] the daily history has nothing for: results from then are
  /// missing. `null` if there is no history to tell (off, or nothing recorded yet).
  Future<List<({DateTime from, DateTime to})>?> gaps(DateTime from, DateTime to) async {
    final List<HistoryDay> days;
    try {
      days = await HistoryStore.instance.days();
    } on Object {
      return null;
    }
    if (days.isEmpty) return null;
    DateTime day(DateTime t) => DateTime(t.year, t.month, t.day);
    final have = {for (final d in days) day(d.date)};
    final first = have.reduce((a, b) => a.isBefore(b) ? a : b);
    final result = <({DateTime from, DateTime to})>[];
    DateTime? open;
    var d = day(from).isBefore(first) ? first : day(from);
    final last = day(to);
    while (!d.isAfter(last)) {
      if (!have.contains(d)) {
        open ??= d;
      } else if (open != null) {
        result.add((from: open, to: DateTime(d.year, d.month, d.day - 1)));
        open = null;
      }
      d = DateTime(d.year, d.month, d.day + 1);
    }
    if (open != null) result.add((from: open, to: last));
    return result;
  }

  /// Reloads the saved log (after a demo, on switching the installation).
  Future<void> reload() async {
    _beforeDemo = null;
    _clear();
    _loaded = false;
    await load();
    notifyListeners();
  }

  void _clear() {
    _entries.clear();
    _keys.clear();
    _failedGroups.clear();
    limitedYears.clear();
  }

  @visibleForTesting
  void debugReset() {
    _clear();
    _loaded = true;
  }

  /// For tests only: allows [load] again.
  @visibleForTesting
  void debugAllowLoad() => _loaded = false;
}
