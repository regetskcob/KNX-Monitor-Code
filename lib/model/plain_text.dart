import '../catalog_store.dart';
import '../knx/dpt_codec.dart';
import '../knx/dpt_guess.dart';
import '../knx/group_catalog.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import 'commissioning.dart' show isStatusGroup;

/// A telegram as a sentence for beginners: "Taster Flur hat Küchenlicht
/// eingeschaltet", "Aktor Küche meldet Küchenlicht Status: Ein" (hallway push
/// button switched on the kitchen light; kitchen actuator reports kitchen light
/// status: on).
///
/// Pure and stateless: names and type come as arguments, the language from [s].
/// [telegramSentence] takes them from the loaded project. Used by the live list
/// outside expert mode and by the cause chain.
String plainSentence(Telegram t, {String? sender, String? target, Dpt? dpt, bool status = false}) {
  final who = t.outgoing ? s.plainThisApp : (sender ?? s.plainDevice(t.sourceText));
  final what = target ?? s.plainAddress(t.destinationText);
  if (t.type == TelegramType.read) return s.plainRead(who, what);
  final value = plainValue(t, dpt);
  // Measured values (temperature, power …) are reported, not "set".
  if (t.type == TelegramType.response || status || _measurement(t, dpt)) return s.plainReport(who, what, value);
  final action = _action(t, dpt);
  return action == null ? s.plainSet(who, what, value) : s.plainAction(who, what, action);
}

/// Sentence for [t] with names and type from the loaded project or learned data.
String telegramSentence(Telegram t, {CatalogStore? store}) {
  final c = store ?? CatalogStore.instance;
  final info = c.info(t.destination);
  return plainSentence(
    t,
    sender: plainSender(t.source, store: c),
    target: info?.name,
    dpt: c.dptOf(t.destination),
    status: info != null && isStatusGroup(info),
  );
}

/// Name of the sending device from the project; `null` if unknown.
String? plainSender(int address, {CatalogStore? store}) {
  final d = (store ?? CatalogStore.instance).device(address);
  if (d == null || d.isTunnel) return null;
  return d.name;
}

/// Value in plain text: decoded with a known [dpt], otherwise with a guessed
/// type, and as a last resort the heuristic short form.
String plainValue(Telegram t, Dpt? dpt) {
  final known = dpt == null ? null : decodeDpt(dpt, t);
  if (known != null) return known;
  final guess = guessDpt([t]);
  return (guess == null ? null : decodeDpt(guess.dpt, t)) ?? t.valueText;
}

/// Numbers with 2 bytes or more: measured value, counter, power.
bool _measurement(Telegram t, Dpt? dpt) {
  final main = dpt?.main ?? guessDpt([t])?.dpt.main;
  return const {7, 8, 9, 12, 13, 14}.contains(main);
}

/// Verb for a switching command before sending; `null` = no verb.
String? plainWriteAction(Telegram t, Dpt? dpt) => _action(t, dpt);

/// Verb for switching commands (DPT 1) – otherwise `null` ("set to …").
String? _action(Telegram t, Dpt? dpt) {
  if (!t.isSmall) return null;
  final type = dpt ?? guessDpt([t])?.dpt;
  if (type == null || type.main != 1) return null;
  final on = (t.data.isEmpty ? 0 : t.data[0]) & 1 == 1;
  return switch (type.sub) {
    null || 1 => on ? s.plainSwitchedOn : s.plainSwitchedOff,
    8 => on ? s.plainMovedDown : s.plainMovedUp,
    9 => on ? s.plainClosed : s.plainOpened,
    10 => on ? s.plainStarted : s.plainStopped,
    3 => on ? s.plainEnabled : s.plainDisabled,
    17 => s.plainTriggered,
    _ => null,
  };
}
