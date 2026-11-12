import 'dart:async';

import '../catalog_store.dart';
import '../knx/knx_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import 'commissioning.dart';
import 'dali.dart';

/// What came back after switching a DALI group.
class DaliSwitchResult {
  const DaliSwitchResult({required this.switched, required this.on, this.feedback, this.answeredBy});

  /// The group that was switched and the value sent.
  final DaliGroup switched;
  final bool on;

  /// The feedback telegram, if any came within the window.
  final Telegram? feedback;

  /// The group whose status address reported; `null` without feedback.
  final DaliGroup? answeredBy;

  /// The feedback came from another group's status address: the group assignment in the gateway
  /// does not match the project.
  bool get foreign => answeredBy != null && answeredBy!.group != switched.group;
}

/// How long a gateway may take to report the new state of a group.
const daliFeedbackWindow = Duration(seconds: 3);

/// Switches [group] over the bus and waits for the feedback of the gateway's groups: the state of
/// the same group, or of another one if the assignment is wrong. Only groups whose status address
/// the project knows can answer.
///
/// Sends through [tunnel] like any other write; the caller asks for confirmation first.
Future<DaliSwitchResult> switchDaliGroup(
  KnxTunnel tunnel,
  DaliGroup group, {
  required bool on,
  Duration window = daliFeedbackWindow,
}) async {
  final address = group.switchGroup;
  if (address == null) throw StateError('DALI group without a switch address');
  final groups = DaliStore.instance.groupsOf(group.gateway);
  final byStatus = <int, DaliGroup>{
    for (final g in groups) ...{?g.statusGroup: g, ?g.valueStatusGroup: g},
  };
  final done = Completer<void>();
  Telegram? own;
  Telegram? other;
  final sub = tunnel.telegrams.listen((t) {
    // Only the gateway's feedback counts: any device could send on a status address.
    if (t.outgoing || t.type == TelegramType.read || t.source != group.gateway) return;
    final from = byStatus[t.destination];
    if (from == null) return;
    if (from.group == group.group) {
      own ??= t;
      if (!done.isCompleted) done.complete();
    } else if (_matches(t, on)) {
      // Another group's status counts only with the value just switched.
      other ??= t;
    }
  });
  try {
    await tunnel.write(address, small: on ? 1 : 0);
    await done.future.timeout(window, onTimeout: () {});
  } finally {
    // Not awaited: nothing depends on it, and the result should not wait for the stream.
    unawaited(sub.cancel());
  }
  // "Wrong assignment" only when the own group stayed silent.
  final feedback = own ?? other;
  return DaliSwitchResult(
    switched: group,
    on: on,
    feedback: feedback,
    answeredBy: feedback == null ? null : byStatus[feedback.destination],
  );
}

/// Whether [t] carries the switched value: 1 bit on/off, or a brightness above 0 for on.
bool _matches(Telegram t, bool on) {
  if (t.data.isEmpty) return false;
  if (t.isSmall) return (t.data[0] & 1 == 1) == on;
  return t.data.length == 1 && (t.data[0] > 0) == on;
}

/// Puts the result of [switchDaliGroup] on the commissioning checklist, under the switch address
/// of the group: the feedback value and sender, and `foreign` with a note when another group
/// answered. A rating by hand stays.
void recordDaliSwitch(DaliSwitchResult result) {
  final address = result.switched.switchGroup;
  if (address == null) return;
  final feedback = result.feedback;
  Commissioning.instance.record(
    address,
    state: feedback == null ? CheckState.noAnswer : CheckState.seen,
    value: feedback == null ? null : CatalogStore.instance.value(feedback),
    source: feedback?.source,
    time: feedback?.time ?? DateTime.now(),
    foreign: result.foreign,
    note: result.foreign ? daliForeignText(result) : null,
  );
}

/// "Rückmeldung kam von Gruppe 4, geschaltet wurde Gruppe 3."
String daliForeignText(DaliSwitchResult result) =>
    s.daliCommForeign(result.answeredBy?.group ?? 0, result.switched.group);
