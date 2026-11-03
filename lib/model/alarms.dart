import '../catalog_store.dart';
import '../knx/group_catalog.dart';
import '../knx/telegram.dart';

/// Kind of message that needs special attention.
enum AlarmKind {
  /// Alarm (smoke, water, intrusion …) – DPT 1.005 or DPT 21.001 "InAlarm".
  alarm,

  /// Fault/defect of a device – DPT 21.001 "Fault" or a telling name.
  fault,
}

final _alarmWords = RegExp(
  r'alarm|sabotage|tamper|einbruch|intrusion|burglar|leck|leak|rauch|smoke|brand|fire|überflut|flood|panik|panic',
);
final _faultWords = RegExp(r'störung|stoerung|defekt|fehler|fault|error|failure|ausfall|malfunction|broken|trouble');

/// Alarm/fault kind of a group address, `null` if none.
///
/// KNX standardizes DPT 1.005 (alarm) and DPT 21.001 (status with bits for fault
/// and alarm). Many projects report faults as 1-bit values with a telling name
/// ("Sensor defekt", sensor faulty) – we recognize those by name.
AlarmKind? alarmKindOf(GroupInfo? info) {
  if (info == null) return null;
  final dpt = info.dpt;
  if (dpt?.main == 1 && dpt?.sub == 5) return AlarmKind.alarm;
  if (dpt?.main == 21 && dpt?.sub == 1) return AlarmKind.fault;
  // Only evaluate names for 1-bit values – "Alarmzentrale Szene" and the like stay out.
  if (dpt != null && dpt.main != 1) return null;
  final text = '${info.name} ${info.path ?? ''}'.toLowerCase();
  if (_alarmWords.hasMatch(text)) return AlarmKind.alarm;
  if (_faultWords.hasMatch(text)) return AlarmKind.fault;
  return null;
}

/// Whether [t] reports an active alarm or an active fault.
///
/// 1-bit: value 1 = active. DPT 21.001: bit 1 (fault), bit 3 (alarm) or bit 4
/// (alarm not acknowledged) set. Read requests are never active.
AlarmKind? activeAlarm(Telegram t) {
  if (t.type == TelegramType.read || t.data.isEmpty) return null;
  final kind = alarmKindFor(t.destination);
  if (kind == null) return null;
  final dpt = CatalogStore.instance.info(t.destination)?.dpt;
  if (dpt?.main == 21) {
    final bits = t.data[0];
    if (bits & 0x18 != 0) return AlarmKind.alarm;
    if (bits & 0x02 != 0) return AlarmKind.fault;
    return null;
  }
  return t.isSmall && t.data[0] & 0x01 == 1 ? kind : null;
}

/// [alarmKindOf] for an address, cached per project (checking the name is too
/// expensive for every frame).
AlarmKind? alarmKindFor(int address) {
  final catalog = CatalogStore.instance.catalog;
  if (!identical(catalog, _cachedCatalog)) {
    _cache.clear();
    _cachedCatalog = catalog;
  }
  return _cache.putIfAbsent(address, () => (alarmKindOf(catalog[address]),)).$1;
}

final _cache = <int, (AlarmKind?,)>{};
GroupCatalog? _cachedCatalog;
