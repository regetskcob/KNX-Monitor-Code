import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import 'dali.dart';
import 'dali_labels.dart';
import 'watch_rules.dart';

/// The watchers "DALI fault" for [gateway]: one rule per diagnostic address (DPT 237.600 or
/// 238.600), on any fault flag, optionally only for one luminaire or group ([target]).
///
/// A watcher fires on every telegram that reports a fault, like every watcher; the change into
/// the fault and back is what the alarm notification reports. Addresses that cannot carry the
/// target (DPT 238.600 knows no groups) are left out.
List<WatchRule> daliWatchRules(DaliGateway gateway, {DaliTarget? target, bool sound = true, DateTime? now}) {
  final store = DaliStore.instance;
  final stamp = (now ?? DateTime.now()).microsecondsSinceEpoch.toRadixString(36);
  final who = switch (target) {
    final DaliGear gear when gear.name != null => '${daliGearLabel(gear)} (${daliAddressText(gear)})',
    final DaliGear gear => daliGearLabel(gear),
    final DaliGroup group => daliGroupLabel(group),
    _ => '${daliGatewayLabel(gateway)} ${formatIndividual(gateway.address)}',
  };
  final rules = <WatchRule>[];
  for (final address in store.diagnosticGroupsOf(gateway.address).toList()..sort()) {
    final dpt = CatalogStore.instance.dptOf(address);
    if (dpt == null) continue;
    final bits = switch (target) {
      DaliGear(address: final a?) => daliFaultBits(dpt.main, address: a),
      DaliGroup(:final group) => daliFaultBits(dpt.main, address: group, isGroup: true),
      DaliGear() => null,
      _ => daliFaultBits(dpt.main),
    };
    if (bits == null) continue;
    rules.add(
      WatchRule.flags(
        id: '$stamp${rules.length}',
        address: address,
        bits: bits,
        title: s.daliWatchRuleTitle(who),
        sound: sound,
      ),
    );
  }
  return rules;
}
