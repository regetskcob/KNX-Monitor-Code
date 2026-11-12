import '../knx/dali_text.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import 'dali.dart';

/// Name of a luminaire: the one entered in the app, otherwise "EVG 12" or "Notlicht 7".
String daliGearLabel(DaliGear gear) =>
    gear.name ??
    switch (gear.address) {
      final address? => gear.emergency ? s.daliEmergencyN(address) : s.daliGearN(address),
      null => s.daliEmergencyAt(formatGroup(gear.anchor ?? 0)),
    };

/// Name of a DALI group: "G3 Büro 2.15", without a name "Gruppe 3".
String daliGroupLabel(DaliGroup group) =>
    group.name == null ? s.daliGroupN(group.group) : 'G${group.group} ${group.name}';

/// Name of a gateway: entered in the app, from the project, otherwise "DALI-Gateway".
String daliGatewayLabel(DaliGateway gateway) => gateway.name ?? gateway.projectName ?? s.daliGateway;

/// "EVG 12" or "Gruppe 3": the DALI address as the gateway reports it.
String daliAddressText(DaliTarget target) => switch (target) {
  DaliGroup(:final group) => s.daliGroupN(group),
  DaliGear(:final address?) => s.daliGearN(address),
  _ => '',
};

/// State of a luminaire or group in words; "noch keine Meldung" until it reports.
String daliStateText(DaliTarget target) => target.faults == null ? s.daliNoReport : daliFaultsText(target.faults!);

/// "seit 3 Tagen", "seit 5 Std.", "seit 12 Min.", "gerade eben".
String daliSince(DateTime since, DateTime now) {
  final d = now.difference(since);
  if (d.inDays >= 1) return s.daliSinceDays(d.inDays);
  if (d.inHours >= 1) return s.daliSinceHours(d.inHours);
  if (d.inMinutes >= 1) return s.daliSinceMinutes(d.inMinutes);
  return s.daliSinceNow;
}

/// "vor 6 Tagen", "vor 4 Monaten", "heute": how long ago a test result arrived.
String daliAgo(DateTime time, DateTime now) {
  final days = now.difference(time).inDays;
  if (days < 1) return s.daliAgoToday;
  if (days < 60) return s.daliAgoDays(days);
  return s.daliAgoMonths((days / 30.44).round());
}

/// Title of the notification for a change: "Lampenfehler: Flur EG Leuchte 2", back to normal
/// "Wieder in Ordnung: Flur EG Leuchte 2".
String daliAlarmTitle(DaliChange change) {
  final target = change.target;
  final who = target is DaliGear ? daliGearLabel(target) : daliGroupLabel(target as DaliGroup);
  return change.after == 0 ? s.daliNotifyOk(who) : s.daliNotifyFault(daliFaultsText(change.after), who);
}

/// Second line of the notification: "EVG 12 · Flur EG · Gateway 1.1.40 · 12:04:11".
String daliAlarmBody(DaliChange change) {
  final target = change.target;
  String two(int v) => v.toString().padLeft(2, '0');
  final t = change.time;
  return [
    daliAddressText(target),
    if (target is DaliGear) ?target.room,
    s.daliGatewayAt(formatIndividual(change.gateway.address)),
    '${two(t.hour)}:${two(t.minute)}:${two(t.second)}',
  ].where((p) => p.isNotEmpty).join(' · ');
}

/// Name for [DaliText.nameOf]: the luminaire or group a telegram is about, as the model knows it.
String? daliNameOf(Telegram t, {int? address, bool isGroup = false}) {
  final store = DaliStore.instance;
  if (store.isEmpty) return null;
  if (address == null) {
    // Converter status and test result carry no DALI address: the object tells.
    for (final gw in store.gateways) {
      for (final gear in store.gearOf(gw.address)) {
        if (gear.statusGroup == t.destination || gear.resultGroup == t.destination) return daliGearLabel(gear);
      }
    }
    return null;
  }
  final senders = store.project.diagnostics[t.destination] ?? const <int>{};
  final pa = store.gateway(t.source) != null || senders.length != 1 ? t.source : senders.first;
  if (isGroup) {
    final group = store.group(pa, address);
    return group?.name == null ? null : daliGroupLabel(group!);
  }
  final gear = store.gear(pa, address);
  // Unnamed luminaires read "EVG 12" (or "Notlicht 12") in the monitor.
  return gear == null || (gear.name == null && !gear.emergency) ? null : daliGearLabel(gear);
}
