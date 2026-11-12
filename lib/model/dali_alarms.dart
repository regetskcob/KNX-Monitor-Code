import 'dart:async';

import 'package:flutter/foundation.dart';

import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../platform/notify.dart';
import 'alarm_notifier.dart';
import 'dali.dart';
import 'dali_labels.dart';
import 'dali_log.dart';

/// Notifies when a luminaire or DALI group enters a fault and when it is back to normal, and when
/// an emergency test fails, as a notification on the device, like [AlarmNotifier] does for alarm
/// addresses.
///
/// The state counts per luminaire, not per group address: one diagnostic address reports many. All
/// changes go through a [FaultDebouncer] (the same rules as the server): a state counts once it
/// held for a while, notifications per gateway and minute are capped, beyond that one summary.
class DaliAlarmNotifier {
  DaliAlarmNotifier({
    Stream<DaliChange>? changes,
    Stream<List<EmergencyTest>>? tests,
    AlarmSender? send,
    FaultDebouncer? debouncer,
    ValueListenable<bool>? enabled,
    bool Function()? serverNotifies,
    DateTime Function()? now,
  }) : _send = send ?? sendNotification,
       _debouncer = debouncer ?? FaultDebouncer(),
       _enabled = enabled ?? AlarmNotifySetting.instance,
       _serverNotifies = serverNotifies ?? (() => false),
       _now = now ?? DateTime.now {
    _sub = (changes ?? DaliStore.instance.changes).listen(_onChange);
    _testSub = (tests ?? DaliTestLog.instance.added).listen(_onTests);
  }

  final AlarmSender _send;
  final FaultDebouncer _debouncer;
  final ValueListenable<bool> _enabled;

  /// The add-on server or box sends the notifications itself.
  final bool Function() _serverNotifies;
  final DateTime Function() _now;
  late final StreamSubscription<DaliChange> _sub;
  late final StreamSubscription<List<EmergencyTest>> _testSub;
  Timer? _timer;

  /// Texts per key, the newest (bounded like the debouncer's keys).
  final _labels = <String, ({String title, String body, String fault})>{};

  void _onChange(DaliChange change) {
    final target = change.target;
    final id = target is DaliGear ? target.id : (target as DaliGroup).id;
    final name = target is DaliGear ? daliGearLabel(target) : daliGroupLabel(target as DaliGroup);
    _remember(id, daliAlarmTitle(change), daliAlarmBody(change), name);
    _debouncer.report(id, change.gateway.address, change.after, change.time);
    _schedule();
  }

  void _onTests(List<EmergencyTest> entries) {
    final store = DaliStore.instance;
    for (final e in entries.where((e) => !e.foreign)) {
      final gear = store.gearOfResult(e.group);
      final name = gear == null ? s.daliEmergencyAt(formatGroup(e.group)) : daliGearLabel(gear);
      final key = 'test:${e.group}';
      _remember(key, s.daliServiceTestFailed(name), s.daliGatewayAt(formatIndividual(e.gateway ?? 0)), name);
      _debouncer.report(key, e.gateway ?? 0, e.result == EmergencyResult.failed ? 8 : 0, e.time);
    }
    _schedule();
  }

  void _remember(String key, String title, String body, String name) {
    _labels.remove(key);
    _labels[key] = (title: title, body: body, fault: name);
    while (_labels.length > _debouncer.maxKeys) {
      _labels.remove(_labels.keys.first);
    }
  }

  void _schedule() {
    final due = _debouncer.nextDue;
    if (due == null) return;
    _timer?.cancel();
    final wait = due.difference(_now());
    _timer = Timer(wait.isNegative ? Duration.zero : wait, flush);
  }

  /// Sends what settled by now.
  void flush() {
    final quiet = !_enabled.value || _serverNotifies();
    for (final n in _debouncer.take(_now())) {
      if (!n.notify || quiet) continue;
      if (n.count > 0) {
        unawaited(
          _send(
            id: 'knx_dali_${n.gateway}_summary',
            title: s.daliNotifySummary(n.count),
            body: s.daliGatewayAt(formatIndividual(n.gateway)),
          ).catchError((Object e) => debugPrint('DALI-Mitteilung: $e')),
        );
        continue;
      }
      final label = _labels[n.key];
      if (label == null) continue;
      final title = n.after == 0 ? s.daliNotifyOk(label.fault) : label.title;
      unawaited(
        _send(
          id: 'knx_dali_${n.key}',
          title: title,
          body: label.body,
        ).catchError((Object e) => debugPrint('DALI-Mitteilung: $e')),
      );
    }
    _schedule();
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _sub.cancel();
    await _testSub.cancel();
  }
}
