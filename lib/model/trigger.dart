import '../catalog_store.dart';
import '../knx/dpt_codec.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import 'alarms.dart';
import 'analysis.dart';
import 'telegram_log.dart';

enum TriggerKind { address, alarm, repeated, unanswered, unknown }

/// How the value of a telegram is compared with the value of the condition.
/// Less/greater only for numbers; equal/not equal for numbers as numbers,
/// otherwise as text (case-insensitive).
enum ValueCompare {
  contains,
  equals,
  notEquals,
  less,
  greater;

  /// Symbol for lists and the description.
  String get symbol => switch (this) {
    contains => s.watchContains,
    equals => '=',
    notEquals => '≠',
    less => '<',
    greater => '>',
  };
}

/// Condition for an automatic recording with pre- and post-trigger capture.
class TriggerConfig {
  const TriggerConfig({
    required this.kind,
    this.address,
    this.value,
    this.pre = 50,
    this.post = 50,
    this.rearm = false,
    this.compare = ValueCompare.contains,
  });

  final TriggerKind kind;

  /// Group address for [TriggerKind.address].
  final int? address;

  /// Optional: value to compare against (plain text, e.g. "Ein" (on) or "21").
  final String? value;

  /// Comparison with [value].
  final ValueCompare compare;

  /// Telegrams before triggering (from the history).
  final int pre;

  /// Telegrams after triggering.
  final int post;

  /// Re-arm after saving.
  final bool rearm;

  /// Whether [t] fires the trigger. (Without [TriggerKind.unanswered] – that only
  /// becomes clear after the response deadline has passed, see [MonitorModel].)
  bool matches(Telegram t, TelegramLog log) => switch (kind) {
    TriggerKind.address => t.destination == address && t.type != TelegramType.read && _valueMatches(t),
    TriggerKind.alarm => activeAlarm(t) != null,
    TriggerKind.repeated => t.repeated,
    TriggerKind.unanswered => false,
    TriggerKind.unknown => issuesOf(t, log).contains(TelegramIssue.unknownAddress),
  };

  bool _valueMatches(Telegram t) {
    final want = value?.trim().toLowerCase() ?? '';
    if (want.isEmpty) return true;
    final store = CatalogStore.instance;
    final text = store.value(t).toLowerCase();
    if (compare == ValueCompare.contains) return text.contains(want);
    final number = double.tryParse(want.replaceAll(',', '.'));
    final actual = numericValue(store.dptOf(t.destination), t);
    if (number == null || actual == null) {
      return switch (compare) {
        ValueCompare.equals => text == want,
        ValueCompare.notEquals => text != want,
        _ => false,
      };
    }
    return switch (compare) {
      ValueCompare.equals => actual == number,
      ValueCompare.notEquals => actual != number,
      ValueCompare.less => actual < number,
      ValueCompare.greater => actual > number,
      ValueCompare.contains => true,
    };
  }

  /// Comparison as text, e.g. "< 20"; `null` without a value.
  String? get valueText => value == null || value!.isEmpty ? null : '${compare.symbol} $value';

  /// Short description for the status display and the recording note.
  String describe() => switch (kind) {
    TriggerKind.address => [
      formatGroup(address ?? 0),
      ?CatalogStore.instance.info(address ?? 0)?.name,
      ?valueText,
    ].join(' '),
    TriggerKind.alarm => s.triggerKindAlarm,
    TriggerKind.repeated => s.triggerKindRepeated,
    TriggerKind.unanswered => s.triggerKindUnanswered,
    TriggerKind.unknown => s.triggerKindUnknown,
  };
}
