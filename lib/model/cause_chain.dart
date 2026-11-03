import '../knx/group_catalog.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import 'object_groups.dart';

/// What a telegram is in the context of another one.
enum ChainRole {
  /// Likely trigger: the sending device has just received this address (logic,
  /// timer) or it is the command for the status feedback.
  cause,

  /// Status feedback of an actuator to the command (status, position …).
  feedback,

  /// Follow-up telegram from a device that received the command, to another
  /// address (logic, scene, central function).
  followUp,

  /// At the same time, but without a recognizable connection.
  coincident,
}

/// Kind of the telegram in focus – determines the wording.
enum ChainKind { scene, central, command, feedback }

/// A telegram of the chain with its offset from the one in focus.
class ChainLink {
  const ChainLink(this.telegram, this.role, this.offset);

  final Telegram telegram;
  final ChainRole role;

  /// Offset from the telegram in focus (negative = before).
  final Duration offset;
}

/// Cause chain around a telegram: what triggered it and what followed.
///
/// Based purely on the capture and the project – without a project there is only
/// proximity in time ([ChainRole.coincident]). Connections are derived from the
/// associations (which device listens to which address) and the objects from
/// [ObjectIndex] (command and status feedback of a channel).
class CauseChain {
  CauseChain._(this.focus, this.kind, this.before, this.after);

  /// Window after the telegram in which reactions are searched.
  static const window = Duration(seconds: 2);

  /// Window before it for the trigger (logic reacts quickly).
  static const causeWindow = Duration(milliseconds: 1500);

  final Telegram focus;
  final ChainKind kind;

  /// Before, nearest first; at most one trigger plus simultaneous ones.
  final List<ChainLink> before;

  /// After, in chronological order.
  final List<ChainLink> after;

  /// Likely trigger, if recognized.
  ChainLink? get cause => before.where((l) => l.role == ChainRole.cause).firstOrNull;

  List<ChainLink> get feedbacks => [
    for (final l in after)
      if (l.role == ChainRole.feedback) l,
  ];

  List<ChainLink> get followUps => [
    for (final l in after)
      if (l.role == ChainRole.followUp) l,
  ];

  /// Status feedback and follow-up telegrams.
  List<ChainLink> get reactions => [
    for (final l in after)
      if (l.role != ChainRole.coincident) l,
  ];

  /// Devices that reacted (distinct senders).
  Set<int> get reactingDevices => {for (final l in reactions) l.telegram.source};

  /// Builds the chain around [focus] from [log] (sorted by time, oldest first).
  /// Whether there are telegrams before or after that belong to the focus.
  bool get hasContext => before.isNotEmpty || after.isNotEmpty;

  factory CauseChain.of(Telegram focus, List<Telegram> log, GroupCatalog catalog) {
    final index = ObjectIndex.forCatalog(catalog);
    final object = index.objectOf(focus.destination);
    final info = catalog[focus.destination];

    // Devices that listen to an address (association without sending).
    Set<int> listeners(int ga) => {
      for (final l in catalog[ga]?.links ?? const <GroupLink>[])
        if (!l.sends || (l.flags?.write ?? false)) l.device,
    };
    final focusListeners = listeners(focus.destination);
    bool isFeedbackGa(int ga) {
      final name = catalog[ga]?.name;
      if (name == null) return false;
      final member = index.objectOf(ga)?.members.where((m) => m.address == ga).firstOrNull;
      return member?.feedback ?? ObjectIndex.isFeedbackName(name);
    }

    final focusIsFeedback = focus.type == TelegramType.response || isFeedbackGa(focus.destination);
    // Measured values (brightness, temperature, counters) are sent cyclically or on
    // change; a telegram shortly before did not trigger them.
    final focusIsMeasurement = _measurementDpts.contains(info?.dpt?.main);
    final kind = _kindOf(info, focusListeners.length, feedback: focusIsFeedback);

    final at = log.indexWhere((t) => identical(t, focus));
    final start = at >= 0 ? at : log.indexWhere((t) => !t.time.isBefore(focus.time));
    final before = <ChainLink>[];
    final after = <ChainLink>[];

    // Before: backwards up to causeWindow.
    for (var i = (start < 0 ? log.length : start) - 1; i >= 0; i--) {
      final t = log[i];
      final offset = t.time.difference(focus.time);
      if (-offset > causeWindow) break;
      if (identical(t, focus) || t.type == TelegramType.read) continue;
      final role = focusIsMeasurement || before.any((l) => l.role == ChainRole.cause)
          ? ChainRole.coincident
          : _causeRole(t, focus, object, listeners, focusIsFeedback: focusIsFeedback);
      before.add(ChainLink(t, role, offset));
    }

    // After: forwards up to window.
    for (var i = start < 0 ? log.length : start + (at >= 0 ? 1 : 0); i < log.length; i++) {
      final t = log[i];
      if (identical(t, focus)) continue;
      final offset = t.time.difference(focus.time);
      if (offset > window) break;
      if (t.type == TelegramType.read) continue;
      final related =
          t.source != focus.source &&
          (focusListeners.contains(t.source) ||
              (object != null && index.objectOf(t.destination) == object && t.destination != focus.destination));
      final role = !related || focusIsFeedback
          ? ChainRole.coincident
          : (isFeedbackGa(t.destination) || t.type == TelegramType.response)
          ? ChainRole.feedback
          : ChainRole.followUp;
      after.add(ChainLink(t, role, offset));
    }
    return CauseChain._(focus, kind, before, after);
  }

  /// Trigger: the command of the same object before a status feedback, or an
  /// address the sender listens to (it reacted to it).
  static ChainRole _causeRole(
    Telegram t,
    Telegram focus,
    ObjectGroup? object,
    Set<int> Function(int) listeners, {
    required bool focusIsFeedback,
  }) {
    if (t.source == focus.source) return ChainRole.coincident;
    if (focusIsFeedback && object != null && object.commands.any((m) => m.address == t.destination)) {
      return ChainRole.cause;
    }
    if (listeners(t.destination).contains(focus.source)) return ChainRole.cause;
    return ChainRole.coincident;
  }

  /// Main groups of measured values: counter, floating point, energy, power.
  static const _measurementDpts = {7, 8, 9, 12, 13, 14};

  static final _sceneWords = RegExp(r'szene|scene', caseSensitive: false);
  static final _centralWords = RegExp(
    r'zentral|central|\balle?s?\b|\ball\b|global|haus aus|panik|panic',
    caseSensitive: false,
  );

  static ChainKind _kindOf(GroupInfo? info, int listeners, {required bool feedback}) {
    final d = info?.dpt;
    if (d != null && (d.main == 17 || d.main == 18) || _sceneWords.hasMatch(info?.name ?? '')) return ChainKind.scene;
    if (_centralWords.hasMatch(info?.name ?? '') || listeners >= 4) return ChainKind.central;
    return feedback ? ChainKind.feedback : ChainKind.command;
  }

  // --- Sentences -------------------------------------------------------------------
  // The sentence summarizes the whole chain. Single telegrams as a sentence come
  // from the beginners' plain-text module (`telegramSentence` in
  // lib/model/plain_text.dart); once it is available, the chain rows
  // ([CauseChainView]) use it instead of name · value · sender.

  /// A sentence about the chain, e.g. "Scene 3 came from 1.1.200 visualization,
  /// 180 ms later 6 devices reported back."
  String describe({required String Function(Telegram) title, required String Function(int) device}) {
    final what = switch (kind) {
      ChainKind.scene => s.chainKindScene(title(focus)),
      ChainKind.central => s.chainKindCentral(title(focus)),
      ChainKind.command || ChainKind.feedback => title(focus),
    };
    final from = s.chainFrom(what, device(focus.source));
    final reactions = this.reactions;
    final cause = this.cause;
    final parts = <String>[
      if (cause != null) s.chainAfterCause(from, formatMs(-cause.offset), title(cause.telegram)) else from,
      if (reactions.isNotEmpty)
        s.chainReactions(formatMs(reactions.last.offset), reactingDevices.length)
      else if (kind != ChainKind.feedback)
        s.chainNoReaction(formatMs(window)),
    ];
    return '${parts.join(', ')}.';
  }
}

/// "180 ms" or "1.2 s".
String formatMs(Duration d) {
  final ms = d.inMilliseconds.abs();
  if (ms < 1000) return '$ms ms';
  return '${localizeDecimal((ms / 1000).toStringAsFixed(1))} s';
}

/// Response times command → status feedback of a channel.
class ReactionStats {
  ReactionStats(this.object, this.samples, this.missing);

  final ObjectGroup object;

  /// Measured times, ascending; empty if no command was answered.
  final List<Duration> samples;

  /// Commands without status feedback within the window.
  final int missing;

  int get count => samples.length;

  /// At least one status feedback measured; otherwise all times are `null`.
  bool get measured => samples.isNotEmpty;
  Duration? get min => measured ? samples.first : null;
  Duration? get max => measured ? samples.last : null;
  Duration? get median => _quantile(0.5);
  Duration? get p90 => _quantile(0.9);

  Duration? _quantile(double q) => measured ? samples[((samples.length - 1) * q).round()] : null;

  /// Maximum time for a status feedback to count as the answer to the command.
  static const window = Duration(seconds: 3);

  /// Per object with command and status feedback: the first feedback after each
  /// write command. Channels that never answered come first (only [missing]),
  /// then the slowest.
  static List<ReactionStats> of(List<Telegram> log, GroupCatalog catalog) {
    final index = ObjectIndex.forCatalog(catalog);
    final open = <ObjectGroup, List<Telegram>>{};
    final samples = <ObjectGroup, List<Duration>>{};
    final missing = <ObjectGroup, int>{};

    void expire(DateTime now) {
      for (final MapEntry(key: o, value: pending) in open.entries) {
        while (pending.isNotEmpty && now.difference(pending.first.time) > window) {
          pending.removeAt(0);
          missing[o] = (missing[o] ?? 0) + 1;
        }
      }
    }

    for (final t in log) {
      expire(t.time);
      if (t.type == TelegramType.read) continue;
      final o = index.objectOf(t.destination);
      if (o == null || o.feedbacks.isEmpty || o.commands.isEmpty) continue;
      final member = o.members.firstWhere((m) => m.address == t.destination);
      if (!member.feedback && t.type == TelegramType.write) {
        (open[o] ??= []).add(t);
      } else if (member.feedback) {
        final pending = open[o];
        if (pending == null || pending.isEmpty) continue;
        // One status feedback answers all open commands (double click, central).
        for (final c in pending) {
          if (c.source != t.source) (samples[o] ??= []).add(t.time.difference(c.time));
        }
        pending.clear();
      }
    }
    // Commands shortly before the end of the capture do not yet count as "without feedback".
    if (log.isNotEmpty) expire(log.last.time);
    return [
      for (final o in {...samples.keys, ...missing.keys})
        ReactionStats(o, (samples[o] ?? <Duration>[])..sort(), missing[o] ?? 0),
    ]..sort((a, b) {
      if (a.measured != b.measured) return a.measured ? 1 : -1;
      if (!a.measured) return b.missing.compareTo(a.missing);
      return b.median!.compareTo(a.median!);
    });
  }
}
