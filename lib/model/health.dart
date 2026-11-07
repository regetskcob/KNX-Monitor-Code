import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../catalog_store.dart';
import '../knx/dpt_codec.dart';
import '../knx/group_catalog.dart';
import '../knx/knx_tunnel.dart';
import '../knx/demo_tunnel.dart';
import '../knx/read_sweep.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../platform/notify.dart';
import '../platform/storage.dart';
import 'analysis.dart';
import 'commissioning.dart';
import 'history_store.dart';
import 'statistics.dart';
import 'telegram_log.dart';
import 'weekly_report.dart';
import 'installation.dart';

/// Areas of the health check.
enum HealthArea { read, cycle, readings, dpt, bus }

enum Severity { ok, info, warning, error }

/// Kind of a finding.
enum FindingKind {
  /// Used to respond to reads, no longer does.
  newSilent(HealthArea.read, Severity.error),

  /// Has never responded – usually the read flag is missing.
  alwaysSilent(HealthArea.read, Severity.info),

  /// Status address without an associated device in the project – is not read.
  unlinked(HealthArea.read, Severity.info),

  /// Usually sends regularly, but has been silent much longer than usual.
  overdue(HealthArea.cycle, Severity.warning),

  /// Measured value outside the plausible range.
  outOfRange(HealthArea.readings, Severity.error),

  /// Cyclic measured value has not changed for many hours.
  stuck(HealthArea.readings, Severity.warning),

  /// Payload length does not match the DPT of the group address.
  dptSize(HealthArea.dpt, Severity.error),

  /// Value is invalid for the DPT (e.g. 0x7FFF for DPT 9).
  dptValue(HealthArea.dpt, Severity.warning),

  /// Address without a DPT; senders send values of different lengths.
  mixedSizes(HealthArea.dpt, Severity.warning),

  /// Sender repeats conspicuously often (missing acknowledgments).
  repeats(HealthArea.bus, Severity.warning),

  /// Read requests from other devices go unanswered.
  unansweredReads(HealthArea.bus, Severity.info);

  const FindingKind(this.area, this.severity);
  final HealthArea area;
  final Severity severity;

  /// Whether it concerns a device (otherwise a group address).
  bool get device => this == repeats;
}

/// A finding – data only; texts are created in the UI/PDF.
class HealthFinding {
  const HealthFinding(
    this.kind,
    this.address, {
    this.since,
    this.interval,
    this.value,
    this.source,
    this.count,
    this.expected,
    this.actual,
    this.rate,
  });

  final FindingKind kind;

  /// Group address, or for [FindingKind.device] the individual address.
  final int address;

  /// Last seen / since when.
  final DateTime? since;
  final Duration? interval;

  /// Value in plain text (current or conspicuous value).
  final String? value;
  final int? source;
  final int? count;
  final int? expected;
  final int? actual;
  final double? rate;

  String get key => '${kind.name}:$address${source == null ? '' : ':$source'}';

  Map<String, Object?> toJson() => {
    'k': kind.name,
    'a': address,
    'since': ?since?.millisecondsSinceEpoch,
    'iv': ?interval?.inSeconds,
    'v': ?value,
    'src': ?source,
    'n': ?count,
    'exp': ?expected,
    'act': ?actual,
    'r': ?rate,
  };

  static HealthFinding? fromJson(Map<String, Object?> j) {
    final kind = FindingKind.values.asNameMap()[j['k']];
    if (kind == null) return null;
    return HealthFinding(
      kind,
      j['a']! as int,
      since: j['since'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['since']! as int),
      interval: j['iv'] == null ? null : Duration(seconds: j['iv']! as int),
      value: j['v'] as String?,
      source: j['src'] as int?,
      count: j['n'] as int?,
      expected: j['exp'] as int?,
      actual: j['act'] as int?,
      rate: (j['r'] as num?)?.toDouble(),
    );
  }
}

/// A check run with its findings.
class HealthRun {
  HealthRun(
    this.time,
    this.findings, {
    required this.asked,
    required this.answered,
    this.newKeys = const {},
    this.passive = false,
  });

  final DateTime time;

  /// Ran without a read test: says nothing about read findings (those from the
  /// last full run remain valid).
  final bool passive;
  final List<HealthFinding> findings;
  final int asked;
  final int answered;

  /// Findings that were not present in the previous run.
  final Set<String> newKeys;

  bool isNew(HealthFinding f) => newKeys.contains(f.key);

  /// Most severe finding of an area.
  Severity worst(HealthArea area) => findings
      .where((f) => f.kind.area == area)
      .map((f) => f.kind.severity)
      .fold(Severity.ok, (a, b) => b.index > a.index ? b : a);

  int countIn(HealthArea area) => findings.where((f) => f.kind.area == area).length;

  Map<String, Object?> toJson() => {
    't': time.millisecondsSinceEpoch,
    'asked': asked,
    'answered': answered,
    'f': [for (final f in findings) f.toJson()],
    'new': newKeys.toList(),
    if (passive) 'p': true,
  };

  factory HealthRun.fromJson(Map<String, Object?> j) => HealthRun(
    DateTime.fromMillisecondsSinceEpoch(j['t']! as int),
    [for (final f in (j['f'] as List? ?? const [])) ?HealthFinding.fromJson(f as Map<String, Object?>)],
    asked: j['asked'] as int? ?? 0,
    answered: j['answered'] as int? ?? 0,
    newKeys: {for (final k in (j['new'] as List? ?? const [])) k as String},
    passive: j['p'] == true,
  );
}

/// Findings that apply after [runs] (newest first): those of the newest run; if
/// it is passive, plus the read findings of the last full run – a run without a
/// read test can neither confirm nor resolve them.
List<HealthFinding> currentFindings(List<HealthRun> runs) {
  final latest = runs.firstOrNull;
  if (latest == null) return const [];
  if (!latest.passive) return latest.findings;
  final full = runs.where((r) => !r.passive).firstOrNull;
  final keys = {for (final f in latest.findings) f.key};
  return [
    ...latest.findings,
    if (full != null)
      for (final f in full.findings)
        if (f.kind.area == HealthArea.read && !keys.contains(f.key)) f,
  ];
}

// --- Checks (pure, testable) --------------------------------------------------

/// Read test: who responds, who is newly or always silent.
List<HealthFinding> readFindings({
  required List<int> asked,
  required Map<int, Telegram> answers,
  required Set<int> readable,
  required Map<int, DateTime> lastAnswer,
}) => [
  for (final a in asked)
    if (!answers.containsKey(a))
      readable.contains(a)
          ? HealthFinding(FindingKind.newSilent, a, since: lastAnswer[a])
          : HealthFinding(FindingKind.alwaysSilent, a),
];

/// Cycle watcher: addresses that send regularly according to the history (median
/// interval ≤ 6 h, at least 6 telegrams) but have now been silent for longer
/// than three times that (at least 15 min). The rule itself is shared with the
/// add-on server ([cycleSilencesOf] in package:knx).
List<HealthFinding> cycleFindings(Iterable<Telegram> telegrams, DateTime now) => [
  for (final s in cycleSilencesOf(telegrams, now))
    HealthFinding(FindingKind.overdue, s.address, since: s.last, interval: s.interval),
];

/// Plausible range per measured quantity (DPT); `null` = no check.
(double, double)? plausibleRange(Dpt dpt) => switch ((dpt.main, dpt.sub)) {
  (9, 1) => (-30, 60), // Temperature °C
  (9, 4) => (0, 200000), // Brightness lx
  (9, 5) => (0, 60), // Wind m/s
  (9, 7) => (0, 100), // Humidity %
  (9, 8) => (0, 10000), // CO₂ ppm
  (9, 28) => (0, 220), // Wind km/h
  _ => null,
};

/// Measured values: outside the plausible range or "stuck" (temperature/humidity
/// unchanged for ≥ 12 h with at least 12 telegrams).
List<HealthFinding> valueFindings(Iterable<Telegram> telegrams, DateTime now) {
  final store = CatalogStore.instance;
  final latest = <int, Telegram>{};
  final series = <int, List<(DateTime, double)>>{};
  for (final t in telegrams) {
    if (t.type == TelegramType.read) continue;
    final dpt = store.dptOf(t.destination);
    if (dpt == null || plausibleRange(dpt) == null) continue;
    final v = numericValue(dpt, t);
    if (v == null) continue;
    final prev = latest[t.destination];
    if (prev == null || !t.time.isBefore(prev.time)) latest[t.destination] = t;
    (series[t.destination] ??= []).add((t.time, v));
  }
  final result = <HealthFinding>[];
  for (final MapEntry(key: ga, value: t) in latest.entries) {
    final dpt = store.info(ga)!.dpt!;
    final (lo, hi) = plausibleRange(dpt)!;
    final v = numericValue(dpt, t)!;
    if (v < lo || v > hi) {
      result.add(HealthFinding(FindingKind.outOfRange, ga, value: store.value(t), since: t.time, source: t.source));
      continue;
    }
    if (dpt.sub != 1 && dpt.sub != 7) continue;
    final recent = [
      for (final p in series[ga]!)
        if (now.difference(p.$1) <= const Duration(hours: 24)) p,
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    if (recent.length < 12) continue;
    final span = recent.last.$1.difference(recent.first.$1);
    if (span >= const Duration(hours: 12) && recent.every((p) => p.$2 == recent.first.$2)) {
      result.add(HealthFinding(FindingKind.stuck, ga, value: store.value(t), since: recent.first.$1));
    }
  }
  return result;
}

/// Invalid values per DPT ("invalid" marker or outside the value range).
bool _invalidValue(Dpt dpt, Telegram t) {
  final d = t.data;
  return switch ((dpt.main, t.isSmall ? 0 : d.length)) {
    (9, 2) => d[0] == 0x7F && d[1] == 0xFF,
    (20, 1) when dpt.sub == 102 => d[0] > 4,
    (17, 1) => d[0] > 63,
    (5, 1) when dpt.sub == 1 => false,
    _ => false,
  };
}

/// Datapoint types: length and value matching the DPT of the group address; per
/// sender, so it is clear which device is misconfigured.
List<HealthFinding> dptFindings(Iterable<Telegram> telegrams) {
  final store = CatalogStore.instance;
  final wrongSize = <(int, int), (int, int, DateTime)>{}; // (GA, sender) → (length, count, last)
  final badValue = <(int, int), (Telegram, int)>{};
  final sizesNoDpt = <int, Map<int, int>>{}; // GA without DPT → length → sender
  for (final t in telegrams) {
    if (t.type == TelegramType.read) continue;
    final info = store.info(t.destination);
    final actual = t.isSmall ? 0 : t.data.length;
    final dpt = info?.dpt;
    if (dpt == null) {
      if (info != null) (sizesNoDpt[t.destination] ??= {})[actual] = t.source;
      continue;
    }
    final expected = expectedSize(dpt);
    final key = (t.destination, t.source);
    if (expected != null && expected != actual) {
      final old = wrongSize[key];
      wrongSize[key] = (actual, (old?.$2 ?? 0) + 1, t.time);
    } else if (_invalidValue(dpt, t)) {
      badValue[key] = (t, (badValue[key]?.$2 ?? 0) + 1);
    }
  }
  return [
    for (final MapEntry(key: (ga, src), value: (actual, n, time)) in wrongSize.entries)
      HealthFinding(
        FindingKind.dptSize,
        ga,
        source: src,
        actual: actual,
        expected: expectedSize(store.info(ga)!.dpt!),
        count: n,
        since: time,
      ),
    for (final MapEntry(key: (ga, src), value: (t, n)) in badValue.entries)
      HealthFinding(FindingKind.dptValue, ga, source: src, value: hex(t.data), count: n, since: t.time),
    for (final MapEntry(key: ga, value: sizes) in sizesNoDpt.entries)
      if (sizes.length > 1) HealthFinding(FindingKind.mixedSizes, ga, count: sizes.length),
  ];
}

/// Bus quality from the live history: repetitions per sender, unanswered read
/// requests from other devices per address.
List<HealthFinding> busFindings(TelegramLog log) {
  final stats = BusStatistics.of(log);
  final unanswered = <int, int>{};
  for (final t in log.log) {
    if (t.outgoing || !log.isUnanswered(t)) continue;
    unanswered[t.destination] = (unanswered[t.destination] ?? 0) + 1;
  }
  return [
    for (final x in stats.senders)
      if (x.count >= 20 && x.repeatRate >= 0.05)
        HealthFinding(FindingKind.repeats, x.address, rate: x.repeatRate, count: x.count),
    for (final MapEntry(key: ga, value: n) in unanswered.entries)
      if (n >= 2) HealthFinding(FindingKind.unansweredReads, ga, count: n),
  ];
}

/// Automatic run on connect (default: off – briefly loads the bus).
class HealthAutoRun extends ValueNotifier<bool> {
  HealthAutoRun._() : super(false);
  static final instance = HealthAutoRun._();
  static const _key = 'health_auto';

  Future<void> load() async {
    value = (await SharedPreferences.getInstance()).getBool(_key) ?? false;
  }

  Future<void> set(bool v) async {
    value = v;
    await (await SharedPreferences.getInstance()).setBool(_key, v);
  }
}

/// Health check: read test of known addresses, cycle watcher, plausibility,
/// datapoint types and bus quality. Remembers which addresses have responded
/// before, and the latest runs.
class HealthCheck extends ChangeNotifier {
  HealthCheck._();

  static final instance = HealthCheck._();
  static const _path = 'health.json';
  static const _keepRuns = 30;

  /// Addresses that have responded to a read at least once.
  final readable = <int>{};
  final lastAnswer = <int, DateTime>{};

  /// Runs, newest first.
  final runs = <HealthRun>[];

  bool running = false;
  int sent = 0;
  int toSend = 0;
  bool _loaded = false;

  HealthRun? get last => runs.firstOrNull;
  double get progress => toSend == 0 ? 0 : sent / toSend;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final read = await readStored(InstallationStore.instance.storage, _path, (text) {
      final j = jsonDecode(text) as Map<String, Object?>;
      readable.addAll([for (final a in (j['readable'] as List? ?? const [])) a as int]);
      for (final MapEntry(:key, :value) in ((j['lastAnswer'] as Map?) ?? const {}).entries) {
        lastAnswer[int.parse(key as String)] = DateTime.fromMillisecondsSinceEpoch(value as int);
      }
      runs.addAll([for (final r in (j['runs'] as List? ?? const [])) HealthRun.fromJson(r as Map<String, Object?>)]);
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

  Future<void> _save() async {
    if (DemoTunnel.active) return; // Demo: do not persist anything
    await _write();
  }

  Future<void> _write() => InstallationStore.instance.storage.write(
    _path,
    jsonEncode({
      'readable': readable.toList(),
      'lastAnswer': {for (final MapEntry(:key, :value) in lastAnswer.entries) '$key': value.millisecondsSinceEpoch},
      'runs': [for (final r in runs.take(_keepRuns)) r.toJson()],
    }),
  );

  /// Whether the project contains associations (otherwise e.g. only CSV – then read everything).
  bool get _hasLinks => CatalogStore.instance.catalog.groups.values.any((g) => g.links.isNotEmpty);

  /// Status addresses without an associated device: cannot respond.
  List<int> unlinkedStatus() => [
    if (_hasLinks)
      for (final g in CatalogStore.instance.catalog.groups.values)
        if (isStatusGroup(g) && g.links.isEmpty && !readable.contains(g.address)) g.address,
  ]..sort();

  /// Addresses to read: associated status/feedback addresses from the project and
  /// everything that has responded before.
  List<int> addressesToRead() {
    final groups = CatalogStore.instance.catalog.groups.values;
    final skip = unlinkedStatus().toSet();
    return {
      for (final g in groups)
        if (isStatusGroup(g) && !skip.contains(g.address)) g.address,
      ...readable,
    }.toList()..sort();
  }

  /// Telegrams for cycles/values/datapoint types: live history plus the saved
  /// daily history of today and yesterday (without duplicates).
  Future<List<Telegram>> _telegrams(TelegramLog log, DateTime now) async {
    final seen = <String>{};
    final result = <Telegram>[];
    void add(Telegram t) {
      if (seen.add('${t.time.microsecondsSinceEpoch}:${t.source}:${t.destination}')) result.add(t);
    }

    final history = HistoryStore.instance;
    if (history.enabled) {
      try {
        final days = await history.days();
        for (final day in days) {
          if (now.difference(day.date) > const Duration(days: 2)) continue;
          for (final t in (await history.open(day, name: '')).telegrams) {
            add(t);
          }
        }
      } on Object catch (e) {
        debugPrint('Tagesverlauf für Gesundheitsprüfung nicht lesbar: $e');
      }
    }
    log.log.forEach(add);
    return result;
  }

  /// Runs all checks. [readTest] = send read requests (otherwise only passive
  /// evaluation).
  Future<HealthRun?> run(KnxTunnel tunnel, TelegramLog log, {bool readTest = true}) async {
    if (running) return null;
    await load();
    running = true;
    sent = 0;
    final asked = readTest ? addressesToRead() : <int>[];
    toSend = asked.length;
    notifyListeners();
    try {
      final answers = asked.isEmpty
          ? <int, Telegram>{}
          : await ReadSweep.run(
              tunnel,
              asked,
              cancelled: () => !running,
              onSent: (n) {
                sent = n;
                notifyListeners();
              },
            );
      if (!running) return null;
      final now = DateTime.now();
      final telegrams = await _telegrams(log, now);
      final findings = [
        ...readFindings(asked: asked, answers: answers, readable: readable, lastAnswer: lastAnswer),
        if (readTest)
          for (final a in unlinkedStatus()) HealthFinding(FindingKind.unlinked, a),
        ...cycleFindings(telegrams, now),
        ...valueFindings(telegrams, now),
        ...dptFindings(telegrams),
        ...busFindings(log),
      ]..sort((a, b) => b.kind.severity.index.compareTo(a.kind.severity.index));
      for (final MapEntry(key: a, value: t) in answers.entries) {
        readable.add(a);
        lastAnswer[a] = t.time;
      }
      final previous = last == null ? null : {for (final f in currentFindings(runs)) f.key};
      final run = HealthRun(
        now,
        findings,
        asked: asked.length,
        answered: answers.length,
        passive: !readTest,
        newKeys: {
          for (final f in findings)
            if (previous != null && !previous.contains(f.key)) f.key,
        },
      );
      runs.insert(0, run);
      if (runs.length > _keepRuns) runs.removeRange(_keepRuns, runs.length);
      await _save();
      await _notify(run);
      return run;
    } finally {
      running = false;
      notifyListeners();
    }
  }

  void cancel() {
    if (!running) return;
    running = false;
    notifyListeners();
  }

  /// Notify only for new findings from "warning" up.
  Future<void> _notify(HealthRun run) async {
    final fresh = [
      for (final f in run.findings)
        if (run.isNew(f) && f.kind.severity.index >= Severity.warning.index) f,
    ];
    if (fresh.isEmpty) return;
    try {
      await sendNotification(id: 'health', title: s.healthNotifyTitle(fresh.length), body: notificationBody(fresh));
    } on Object catch (e) {
      debugPrint('Mitteilung Gesundheit: $e');
    }
  }

  /// Automatic run after connecting, if enabled and the last run is older than
  /// 24 h.
  Future<void> maybeAutoRun(KnxTunnel tunnel, TelegramLog log) async {
    await HealthAutoRun.instance.load();
    await load();
    if (!HealthAutoRun.instance.value) return;
    final previous = last?.time;
    if (previous != null && DateTime.now().difference(previous) < const Duration(hours: 24)) return;
    await run(tunnel, log);
  }

  /// Without a read test (does not load the bus) at most once a day, so the status
  /// light and weekly report have something to say even without automatic runs.
  Future<void> maybePassiveRun(KnxTunnel tunnel, TelegramLog log) async {
    await load();
    final previous = last?.time;
    if (previous != null && DateTime.now().difference(previous) < const Duration(hours: 24)) return;
    await run(tunnel, log, readTest: false);
  }

  void _clear() {
    readable.clear();
    lastAnswer.clear();
    runs.clear();
  }

  @visibleForTesting
  void debugReset() {
    running = false;
    _clear();
    _loaded = true;
  }
}

/// Text of the notification after a run: what is wrong in plain words, with the
/// address, at most [shown] findings, then how many more and where the details are.
/// The address alone ("2/4/4 Ventil-Zustand") left the user guessing.
String notificationBody(List<HealthFinding> fresh, {int shown = 3}) => [
  for (final f in fresh.take(shown)) _withAddress(f),
  s.healthNotifyMore(fresh.length > shown ? fresh.length - shown : 0),
].join('\n');

String _withAddress(HealthFinding f) {
  final text = plainFinding(f);
  final address = f.kind.device ? formatIndividual(f.address) : formatGroup(f.address);
  // Without a name the sentence already carries the address.
  return text.contains(address) ? text : '$text ($address)';
}

/// Address or device with name: "8/1/1 Windgeschwindigkeit".
String findingTitle(HealthFinding f) {
  final store = CatalogStore.instance;
  return f.kind.device
      ? [formatIndividual(f.address), ?store.device(f.address)?.name].join('  ')
      : [formatGroup(f.address), ?store.info(f.address)?.name].join('  ');
}

/// Description of a finding in the current language.
String findingDetail(HealthFinding f) {
  final store = CatalogStore.instance;
  String sender(int? pa) => pa == null ? '—' : [formatIndividual(pa), ?store.device(pa)?.name].join(' ');
  String bytes(int? n) => n == 0 ? s.healthBits : s.healthBytes(n ?? 0);
  return switch (f.kind) {
    FindingKind.newSilent => s.healthNewSilent(f.since == null ? '—' : _when(f.since!)),
    FindingKind.alwaysSilent => _silentDetail(f.address),
    FindingKind.unlinked => s.healthUnlinked,
    FindingKind.overdue => s.healthOverdue(formatInterval(f.interval!), _when(f.since!)),
    FindingKind.outOfRange => s.healthOutOfRange(f.value ?? '—', sender(f.source)),
    FindingKind.stuck => s.healthStuck(f.value ?? '—', _when(f.since!)),
    FindingKind.dptSize => s.healthDptSize(
      sender(f.source),
      bytes(f.actual),
      store.dptOf(f.address)?.toString() ?? '—',
      bytes(f.expected),
      f.count ?? 1,
    ),
    FindingKind.dptValue => s.healthDptValue(sender(f.source), f.value ?? '', f.count ?? 1),
    FindingKind.mixedSizes => s.healthMixedSizes(f.count ?? 2),
    FindingKind.repeats => s.healthRepeats(localizeDecimal(((f.rate ?? 0) * 100).toStringAsFixed(1)), f.count ?? 0),
    FindingKind.unansweredReads => s.healthUnansweredReads(f.count ?? 0),
  };
}

/// "Has never responded – check the read flag on the sending object (1.1.1 …)".
String _silentDetail(int ga) {
  final store = CatalogStore.instance;
  final senders = [
    for (final l in store.info(ga)?.links ?? const <GroupLink>[])
      if (l.sends) [formatIndividual(l.device), ?store.device(l.device)?.name].join(' '),
  ];
  return senders.isEmpty ? s.healthAlwaysSilent : s.healthAlwaysSilentAt(senders.join(', '));
}

String _when(DateTime t) {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final clock = '${two(t.hour)}:${two(t.minute)}';
  final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
  return sameDay ? clock : '${two(t.day)}.${two(t.month)}. $clock';
}
