import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../platform/addon.dart';
import '../platform/notify.dart';
import 'alarms.dart';
import 'expert_mode.dart';
import 'plan.dart';

/// Einstellung „Alarm-Mitteilungen“ (Standard: an).
class AlarmNotifySetting extends ValueNotifier<bool> {
  AlarmNotifySetting._() : super(true);

  static final instance = AlarmNotifySetting._();
  static const _key = 'alarm_notifications';

  Future<void> load() async {
    if (Addon.available) {
      // In the add-on the server sends notifications; the setting lives there.
      try {
        final config = ((await Addon.status())['config'] as Map?)?.cast<String, Object?>() ?? const {};
        value = config['alarms'] != false;
      } on Object {
        value = true;
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    value = prefs.getBool(_key) ?? true;
  }

  /// Notifications exist only in expert mode and from Plus on, but then always:
  /// the setting follows the switch and the tier (also on the add-on server).
  void followExpertMode() {
    void sync() {
      final on = ExpertMode.instance.value && Plan.instance.allows(Feature.alarms);
      if (value != on) set(on);
    }

    sync();
    ExpertMode.instance.addListener(sync);
    Plan.instance.addListener(sync);
  }

  Future<void> set(bool on) async {
    value = on;
    if (Addon.available) {
      try {
        await Addon.configure({'alarms': on});
      } on Object {
        // Older add-on: notifies via the browser.
      }
    }
    if (on) await requestNotificationPermission();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, on);
  }
}

/// Signature for sending (replaceable in tests).
typedef AlarmSender = Future<void> Function({required String id, required String title, required String body});

/// Notifies when a group address enters the alarm or fault state – as a
/// notification on the device or in Home Assistant.
///
/// At most one notification per address per [throttle]; returning to the normal
/// state is not reported.
class AlarmNotifier {
  AlarmNotifier(
    Stream<Telegram> telegrams, {
    AlarmSender? send,
    this.throttle = const Duration(minutes: 5),
    ValueListenable<bool>? enabled,
  }) : _send = send ?? sendNotification,
       _enabled = enabled ?? AlarmNotifySetting.instance {
    _sub = telegrams.listen(_onTelegram);
  }

  final AlarmSender _send;
  final ValueListenable<bool> _enabled;
  final Duration throttle;
  late final StreamSubscription<Telegram> _sub;

  /// Last known state per address (active/inactive).
  final _active = <int, bool>{};
  final _lastSent = <int, DateTime>{};

  void _onTelegram(Telegram t) {
    if (t.type == TelegramType.read) return;
    final kind = activeAlarm(t);
    final was = _active[t.destination] ?? false;
    _active[t.destination] = kind != null;
    if (kind == null || was || !_enabled.value) return;
    final last = _lastSent[t.destination];
    if (last != null && t.time.difference(last) < throttle) return;
    _lastSent[t.destination] = t.time;

    final store = CatalogStore.instance;
    final name = store.info(t.destination)?.name ?? t.destinationText;
    _send(
      id: 'knx_${t.destination}',
      title: kind == AlarmKind.fault ? s.notifyFaultTitle(name) : s.notifyAlarmTitle(name),
      body: [store.value(t), t.destinationText, formatClock(t.time)].join(' · '),
    );
  }

  Future<void> dispose() => _sub.cancel();
}

/// Time of day "hh:mm:ss".
String formatClock(DateTime t) => [t.hour, t.minute, t.second].map((v) => v.toString().padLeft(2, '0')).join(':');
