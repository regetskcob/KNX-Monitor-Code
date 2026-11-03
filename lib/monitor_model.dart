import 'dart:async';

import 'catalog_store.dart';
import 'knx/knx_tunnel.dart';
import 'knx/telegram.dart';
import 'l10n/locale_controller.dart';
import 'model/alarms.dart';
import 'model/customer.dart';
import 'model/recording.dart';
import 'model/trigger.dart';
import 'model/telegram_log.dart';

import 'package:flutter/material.dart' show DateUtils, debugPrint;

import 'model/history_store.dart';
import 'model/activity_range.dart';
import 'model/installation.dart';
import 'model/plan.dart';
import 'model/commissioning.dart';
import 'model/sound_ack.dart';
import 'model/watch_rules.dart';
import 'model/weekly_report.dart';
import 'knx/demo_tunnel.dart';
import 'knx/routing_tunnel.dart';
import 'knx/shared_tunnel.dart';

/// Live monitor: listens on the tunnel from connecting on, keeps the bus activity of the last 60 s
/// and records on request.
class MonitorModel extends TelegramLog {
  @override
  bool get live => true;

  MonitorModel(this.tunnel) : super(maxEntries: 5000) {
    Plan.instance.demo = tunnel is DemoTunnel;
    _followPlan();
    Plan.instance.addListener(_followPlan);
    _sub = tunnel.telegrams.listen(add);
    // Add-on/box check the watchers themselves and report hits.
    if (tunnel case final SharedTunnel shared) {
      _watchSub = shared.watchHits.listen((h) {
        if (Plan.instance.allows(Feature.watcher)) WatchRules.instance.report(h.ids, h.telegram);
      });
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    // Listening time for the weekly report (not in the demo).
    if (tunnel is! DemoTunnel) unawaited(ListeningLog.instance.load());
    _seedFromHistory();
    if (tunnel is SharedTunnel) tunnel.state.addListener(_followConnection);
    tunnel.gatewayInfo.addListener(_rememberGateway);
    _rememberGateway();
  }

  /// Remember the gateway in the active installation: address when connecting, name, serial number
  /// and MAC once it has described itself. Not for demo, routing (no specific device) and
  /// box/add-on (own server).
  void _rememberGateway() {
    // Not synchronous: the call also comes from initState, where listeners must not build.
    if (tunnel is! DemoTunnel) unawaited(Future.microtask(() => CustomerStore.instance.note(VisitKind.connection)));
    if (tunnel is DemoTunnel || tunnel is RoutingTunnel || tunnel is SharedTunnel) return;
    if (!InstallationStore.instance.switchable) return;
    unawaited(
      InstallationStore.instance
          .rememberGateway(tunnel.host, tunnel.port, info: tunnel.gatewayInfo.value)
          .catchError((Object e) => debugPrint('Gateway nicht gemerkt: $e')),
    );
  }

  /// Telegrams and alarms per minute for "last hour" and "today".
  final minutes = MinuteCounter();
  final _started = DateTime.now();
  int _ticks = 0;

  /// Fill "today" from the stored daily history (only telegrams before connecting – the monitor
  /// counts later ones itself).
  ///
  /// On the add-on or box the server records without gaps: there also take over the history and
  /// last values. Home Assistant rebuilds the panel on every switch, and the view should not start
  /// empty then.
  Future<void> _seedFromHistory() async {
    final history = HistoryStore.instance;
    if (!history.enabled) return;
    try {
      final now = DateTime.now();
      final day = (await history.days()).where((d) => DateUtils.isSameDay(d.date, now)).firstOrNull;
      if (day == null) return;
      final recording = await history.open(day, name: '');
      final earlier = <Telegram>[];
      for (final t in recording.telegrams) {
        if (!t.time.isBefore(_started)) continue;
        minutes.add(t.time, alarm: activeAlarm(t) != null);
        earlier.add(t);
      }
      if (_disposed) return;
      if (tunnel is SharedTunnel && earlier.isNotEmpty) _prepend(earlier);
      notifyListeners();
    } on Object catch (e) {
      debugPrint('Tagesverlauf nicht lesbar: $e');
    }
  }

  /// Last telegram before the connection to the add-on or box was lost (e.g. because the app was in
  /// the background); `null` = no gap open.
  DateTime? _gapFrom;

  /// Connection to the server lost and back again: the server recorded without gaps, so the view
  /// fetches what it missed from the daily history instead of appending new values directly to the
  /// old ones.
  void _followConnection() {
    final state = tunnel.state.value;
    if (state == TunnelState.disconnected && tunnel.error.value != null) {
      _gapFrom ??= log.isEmpty ? DateTime.now() : log.last.time;
    } else if (state == TunnelState.connected && _gapFrom != null) {
      final from = _gapFrom!;
      _gapFrom = null;
      unawaited(_fillGap(from, DateTime.now()));
    }
  }

  /// Insert telegrams from the daily history between [from] and the first one that arrived live
  /// again afterwards (at the latest [reconnected]).
  Future<void> _fillGap(DateTime from, DateTime reconnected) async {
    final history = HistoryStore.instance;
    if (!history.enabled) return;
    try {
      // All days of the gap, also across midnight, in chronological order.
      final first = DateUtils.dateOnly(from);
      final last = DateUtils.dateOnly(reconnected);
      final days = [
        for (final d in await history.days())
          if (!DateUtils.dateOnly(d.date).isBefore(first) && !DateUtils.dateOnly(d.date).isAfter(last)) d,
      ]..sort((a, b) => a.date.compareTo(b.date));
      final recorded = <Telegram>[];
      for (final day in days) {
        if (_disposed) return;
        recorded.addAll((await history.open(day, name: '')).telegrams);
      }
      if (_disposed) return;
      final firstLive = log.where((t) => t.time.isAfter(from)).firstOrNull?.time ?? reconnected;
      final gap = [
        for (final t in recorded)
          if (t.time.isAfter(from) && t.time.isBefore(firstLive)) t,
      ];
      if (gap.isEmpty) return;
      for (final t in gap) {
        minutes.add(t.time, alarm: activeAlarm(t) != null);
      }
      _insertGap(gap, after: from);
      notifyListeners();
    } on Object catch (e) {
      debugPrint('Lücke nicht nachgeladen: $e');
    }
  }

  /// Insert [gap] after the last telegram up to [after]; counters keep running (they also count
  /// what the list has already discarded).
  void _insertGap(List<Telegram> gap, {required DateTime after}) {
    final live = List.of(log);
    final at = live.indexWhere((t) => t.time.isAfter(after));
    final split = at < 0 ? live.length : at;
    final counts = Map.of(typeCounts);
    final (sent, repeated) = (sentCount, repeatedCount);
    // Paused: what was visible stays visible (including the gap if it lies before).
    final shown = visibleLog.length;
    rebuild([
      ...live.sublist(0, split),
      ...gap,
      ...live.sublist(split),
    ], frozen: shown + (split < shown ? gap.length : 0));
    for (final t in gap) {
      counts[t.type] = counts[t.type]! + 1;
    }
    typeCounts.addAll(counts);
    sentCount = sent;
    repeatedCount = repeated;
  }

  /// Put older telegrams before the ones that already arrived live – without arrival animation,
  /// watchers and recording.
  void _prepend(List<Telegram> earlier) {
    final live = List.of(log);
    final (sent, repeated) = (sentCount, repeatedCount);
    final keep = maxEntries == null ? earlier.length : (maxEntries! - live.length).clamp(0, earlier.length);
    rebuild([...earlier.sublist(earlier.length - keep), ...live], frozen: visibleLog.length + keep);
    sentCount = sent;
    repeatedCount = repeated;
  }

  static const activitySeconds = 60;

  /// The daily history loads late; the view may be closed by then.
  bool _disposed = false;

  final KnxTunnel tunnel;
  late final StreamSubscription<Telegram> _sub;
  StreamSubscription<Object?>? _watchSub;
  late final Timer _ticker;

  /// Telegrams per second; last entry = current second.
  final activity = List<int>.filled(activitySeconds, 0, growable: true);

  /// Active alarm/fault messages per second, parallel to [activity].
  final alarmActivity = List<int>.filled(activitySeconds, 0, growable: true);

  @override
  List<int> get alarmBins => switch (ActivityRangeSetting.instance.value) {
    ActivityRange.seconds => alarmActivity,
    ActivityRange.hour => minutes.hour(DateTime.now(), alarms: true),
    ActivityRange.today => minutes.today(DateTime.now(), alarms: true),
  };

  /// Running recording, `null` = none.
  Recorder? recorder;

  /// Armed trigger condition, `null` = none.
  TriggerConfig? trigger;

  /// Whether a recording started by the trigger is running (post-trigger time).
  bool get triggerRecording => _postLeft != null;

  int? _postLeft;
  DateTime? _firedAt;
  final _checkedReads = Expando<bool>();

  /// Finished trigger recordings – the UI saves and reports them.
  final _triggered = StreamController<Recording>.broadcast();
  Stream<Recording> get triggeredRecordings => _triggered.stream;

  void armTrigger(TriggerConfig? config) {
    trigger = config;
    notifyListeners();
  }

  bool get recording => recorder != null;

  /// Telegrams in the last completed second (clock).
  int get rate => activity[activity.length - 2];

  /// Average telegrams per minute in the selected period (60 s: sum of the last minute; hour/today:
  /// average over the recorded time).
  double get ratePerMinute {
    final now = DateTime.now();
    return switch (ActivityRangeSetting.instance.value) {
      ActivityRange.seconds =>
        activity
            .sublist(activity.length - 61 < 0 ? 0 : activity.length - 61, activity.length - 1)
            .fold(0, (a, b) => a + b)
            .toDouble(),
      ActivityRange.hour => minutes.perMinute(now, now.subtract(const Duration(hours: 1)), coveredSince: _started),
      ActivityRange.today => minutes.perMinute(now, DateTime(now.year, now.month, now.day), coveredSince: _started),
    };
  }

  @override
  List<int> get activityBins => switch (ActivityRangeSetting.instance.value) {
    ActivityRange.seconds => activity,
    ActivityRange.hour => minutes.hour(DateTime.now()),
    ActivityRange.today => minutes.today(DateTime.now()),
  };

  @override
  int get activityPast {
    if (ActivityRangeSetting.instance.value != ActivityRange.today) return activityBins.length;
    final now = DateTime.now();
    return (now.hour * 60 + now.minute) ~/ 15 + 1;
  }

  /// "Today": a tick every 6 hours (24 quarter hours).
  @override
  int get activityTicks => ActivityRangeSetting.instance.value == ActivityRange.today ? 24 : 0;

  @override
  String get activityLabel => switch (ActivityRangeSetting.instance.value) {
    ActivityRange.seconds => s.activityLast60s,
    ActivityRange.hour => s.activityLastHour,
    ActivityRange.today => s.activityToday,
  };

  @override
  bool get activitySwitchable => true;

  /// Display name of the gateway, e.g. "Gira X1 · 192.168.1.22".
  String get gatewayLabel => [?tunnel.deviceName.value, tunnel.host].join(' · ');

  /// Upper limit for [session] (protects memory when running for days).
  static const sessionLimit = 200000;

  /// All telegrams since connecting – for the diagnostics package and export. [log] keeps only the
  /// last [maxEntries] for display.
  final session = <Telegram>[];

  @override
  void add(Telegram t) {
    session.add(t);
    // Trim in blocks: removeRange for every telegram would be expensive.
    if (session.length > sessionLimit + sessionLimit ~/ 20) {
      session.removeRange(0, session.length - sessionLimit);
    }
    recorder?.telegrams.add(t);
    activity[activity.length - 1]++;
    final alarm = activeAlarm(t) != null;
    if (alarm) alarmActivity[alarmActivity.length - 1]++;
    minutes.add(t.time, alarm: alarm);
    super.add(t);
    _checkTrigger(t);
    if (Plan.instance.allows(Feature.watcher)) WatchRules.instance.check(t, this, server: tunnel is SharedTunnel);
    if (Plan.instance.allows(Feature.commissioning)) Commissioning.instance.observe(t);
    if (Plan.instance.allows(Feature.soundAck)) SoundAck.instance.check(t);
  }

  void _checkTrigger(Telegram t) {
    final left = _postLeft;
    if (left != null) {
      if (left <= 1) {
        _finishTrigger();
      } else {
        _postLeft = left - 1;
      }
      return;
    }
    final config = trigger;
    if (config != null && recorder == null && config.matches(t, this)) _fireTrigger(config);
  }

  /// Starts the trigger recording with pre-roll from the history.
  void _fireTrigger(TriggerConfig config) {
    _firedAt = DateTime.now();
    final r = Recorder(
      gateway: gatewayLabel,
      project: CatalogStore.instance.catalog.projectName,
      installation: InstallationStore.instance.active.id,
    );
    final before = log.length > config.pre + 1 ? log.sublist(log.length - config.pre - 1) : List.of(log);
    r.telegrams.addAll(before);
    recorder = r;
    _postLeft = config.post;
    if (config.post == 0) _finishTrigger();
    notifyListeners();
  }

  void _finishTrigger() {
    final config = trigger!;
    final fired = _firedAt!;
    final name = s.triggerRecordingName(config.describe());
    final note = s.triggerNote(
      config.describe(),
      '${fired.hour.toString().padLeft(2, '0')}:${fired.minute.toString().padLeft(2, '0')}:'
      '${fired.second.toString().padLeft(2, '0')}',
      config.pre,
      config.post,
    );
    final r = stopRecording(name: name, note: note);
    _postLeft = null;
    if (!config.rearm) trigger = null;
    if (r != null) _triggered.add(r);
    notifyListeners();
  }

  /// Read requests without a response can only be detected after the deadline.
  void _checkUnanswered() {
    final config = trigger;
    if (config?.kind != TriggerKind.unanswered || recorder != null) return;
    final cutoff = DateTime.now().subtract(TelegramLog.readTimeout * 3);
    for (var i = log.length - 1; i >= 0 && log[i].time.isAfter(cutoff); i--) {
      final t = log[i];
      if (_checkedReads[t] == true || !isUnanswered(t)) continue;
      _checkedReads[t] = true;
      _fireTrigger(config!);
      return;
    }
  }

  /// Pre-roll on a long press of the record button.
  static const preRoll = Duration(seconds: 10);

  /// Starts a recording; with [preRoll] it begins that far in the past and already contains that
  /// period's telegrams.
  void startRecording({Duration preRoll = Duration.zero}) {
    final started = DateTime.now().subtract(preRoll);
    final r = Recorder(
      gateway: gatewayLabel,
      project: CatalogStore.instance.catalog.projectName,
      installation: InstallationStore.instance.active.id,
      started: started,
    );
    if (preRoll > Duration.zero) {
      var i = log.length;
      while (i > 0 && !log[i - 1].time.isBefore(started)) {
        i--;
      }
      r.telegrams.addAll(log.sublist(i));
    }
    recorder = r;
    notifyListeners();
  }

  /// Stops the recording and returns it (not yet saved).
  Recording? stopRecording({required String name, String? note}) {
    final r = recorder?.stop(name: name, note: note);
    recorder = null;
    notifyListeners();
    return r;
  }

  void _tick() {
    _checkUnanswered();
    if (++_ticks % 60 == 0) {
      minutes.prune(DateTime.now());
      if (tunnel is! DemoTunnel && tunnel.state.value == TunnelState.connected) {
        ListeningLog.instance.addMinute(DateTime.now());
      }
    }
    activity
      ..removeAt(0)
      ..add(0);
    alarmActivity
      ..removeAt(0)
      ..add(0);
    notifyListeners();
  }

  /// Free: only the last hour in the monitor.
  void _followPlan() => maxAge = Plan.instance.liveWindow;

  @override
  void dispose() {
    _disposed = true;
    unawaited(ListeningLog.instance.flush());
    Plan.instance.removeListener(_followPlan);
    if (tunnel is DemoTunnel) Plan.instance.demo = false;
    tunnel.gatewayInfo.removeListener(_rememberGateway);
    tunnel.state.removeListener(_followConnection);
    _triggered.close();
    _sub.cancel();
    _watchSub?.cancel();
    _ticker.cancel();
    super.dispose();
  }
}
