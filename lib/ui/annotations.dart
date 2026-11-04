import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/annotation.dart';
import '../model/recording.dart';
import 'annotation_editor.dart';
import 'recording_timeline.dart';
import 'telegram_row.dart';

/// Where comments go: into the own installation ([AnnotationStore]) or, while a
/// recording from someone else's diagnostics package is open, into that
/// recording.
abstract final class AnnotationScope {
  static Recording? _foreign;

  /// Set by the monitor: starts a recording from a point in the past if none is
  /// running and recording is possible; `null` = not possible.
  static Future<bool> Function(DateTime from)? Function()? recordOffer;

  /// How far back the pre-roll reaches at most.
  static const maxPreRoll = Duration(minutes: 5);

  /// Recording opened from a diagnostics package, otherwise `null`.
  static Recording? get foreign => _foreign;

  static void open(Recording r) {
    if (r.diagnostics != null) _foreign = r;
  }

  static void close(Recording r) {
    if (identical(_foreign, r)) _foreign = null;
  }

  /// Comments in [from]…[to] wherever comments currently go.
  static List<Annotation> inRange(DateTime? from, DateTime? to) => switch (_foreign) {
    final r? => [
      for (final a in r.annotations)
        if ((from == null || !a.time.isBefore(from)) && (to == null || !a.time.isAfter(to))) a,
    ],
    null => AnnotationStore.instance.inRange(from, to),
  };

  /// Whether the telegram has a comment (flag in the list).
  static bool hasTelegram(Telegram t) => switch (_foreign) {
    final r? => r.annotations.any(
      (a) => a.telegram?.time == t.time && a.telegram?.source == t.source && a.telegram?.destination == t.destination,
    ),
    null => AnnotationStore.instance.hasTelegram(t.time, t.source, t.destination),
  };

  static List<Annotation> get _all => _foreign?.annotations ?? AnnotationStore.instance.all;

  /// All comments on a group address from all sessions: on its telegrams and in
  /// charts that show it. Newest first.
  static List<Annotation> forGroup(int ga) => [
    for (final a in _all.reversed)
      if (a.telegram?.destination == ga || (a.chart?.groups.contains(ga) ?? false)) a,
  ];

  /// All comments involving a device: on telegrams it sends, on addresses it is
  /// linked to in the project, and on charts with one of these addresses.
  static List<Annotation> forDevice(int pa, Set<int> groups) => [
    for (final a in _all.reversed)
      if ((a.telegram != null && (a.telegram!.source == pa || groups.contains(a.telegram!.destination))) ||
          (a.chart?.groups.any(groups.contains) ?? false))
        a,
  ];

  /// Comments on a telegram.
  static List<Annotation> forTelegram(Telegram t) => switch (_foreign) {
    final r? => [
      for (final a in r.annotations)
        if (a.telegram case final ref?
            when ref.time == t.time && ref.source == t.source && ref.destination == t.destination)
          a,
    ],
    null => AnnotationStore.instance.forTelegram(t.time, t.source, t.destination),
  };

  static Future<void> _add(Annotation a) async {
    if (_foreign case final r?) {
      r.annotations
        ..add(a)
        ..sort((x, y) => x.time.compareTo(y.time));
      await RecordingStore.instance.save(r);
    } else {
      await AnnotationStore.instance.add(a);
    }
  }

  static Future<void> _replace(Annotation before, Annotation? after) async {
    final r = _foreign;
    if (r == null) {
      await (after == null ? AnnotationStore.instance.remove(before) : AnnotationStore.instance.replace(after));
      return;
    }
    final i = r.annotations.indexWhere((x) => x.id == before.id);
    if (i < 0) return;
    if (after == null) {
      r.annotations.removeAt(i);
    } else {
      r.annotations[i] = after;
    }
    await RecordingStore.instance.save(r);
    for (final id in before.shots.where((id) => !(after?.shots.contains(id) ?? false))) {
      await ShotStore.instance.delete(id);
    }
  }
}

/// Comment on a telegram (live list, history, recording, timeline). If the
/// monitor isn't recording yet, the app then offers to start a recording
/// including the last few seconds, so the telegram ends up in it.
Future<void> annotateTelegram(BuildContext context, Telegram t) async {
  // Ask first, then write: this way the recording is already running while the
  // comment is being written. It starts shortly before the telegram.
  final from = t.time.subtract(const Duration(seconds: 5));
  final start = AnnotationScope._foreign == null ? AnnotationScope.recordOffer?.call() : null;
  if (start != null && DateTime.now().difference(from) <= AnnotationScope.maxPreRoll) {
    final choice = await showAdaptiveDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog.adaptive(
        title: Text(s.annotationChoiceTitle),
        content: Text(s.annotationChoiceText(formatTime(from, millis: false))),
        actions: [
          horizontDialogAction(dialog, label: s.commonCancel, onPressed: () => Navigator.pop(dialog)),
          horizontDialogAction(dialog, label: s.annotationChoiceOnly, onPressed: () => Navigator.pop(dialog, false)),
          horizontDialogAction(
            dialog,
            label: s.annotationChoiceRecord,
            primary: true,
            onPressed: () => Navigator.pop(dialog, true),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice && !await start(from) && context.mounted) {
      showHorizontMessage(context, s.annotationRecordFailed, status: HorizontStatus.critical);
    }
    if (!context.mounted) return;
  }
  final edit = await showAnnotationEditor(context, about: describeTelegram(t));
  if (edit == null || edit.delete) return;
  await AnnotationScope._add(
    Annotation(id: Annotation.newId(), time: t.time, note: edit.note, shots: edit.shots, telegram: TelegramRef.of(t)),
  );
}

/// Comment on a point in time without a telegram (timeline, "Jetzt" (now)).
Future<void> annotateTime(BuildContext context, DateTime time) async {
  final edit = await showAnnotationEditor(context, about: s.annotationAboutTime(formatTime(time)));
  if (edit == null || edit.delete) return;
  await AnnotationScope._add(Annotation(id: Annotation.newId(), time: time, note: edit.note, shots: edit.shots));
}

/// Comment in a chart: the point in time under the crosshair, plus the group
/// addresses shown and the visible range.
Future<void> annotateChart(
  BuildContext context, {
  required DateTime time,
  required List<int> groups,
  required DateTime from,
  required DateTime to,
  List<ChartValue> values = const [],
}) async {
  final chart = ChartRef(groups: groups, from: from, to: to, values: values);
  final draft = Annotation(id: Annotation.newId(), time: time, chart: chart);
  final edit = await showAnnotationEditor(context, about: describeAnnotation(draft), values: values);
  if (edit == null || edit.delete) return;
  await AnnotationScope._add(draft.copyWith(note: edit.note, shots: edit.shots));
}

/// Edits or deletes a comment.
Future<void> editAnnotation(BuildContext context, Annotation a) async {
  final edit = await showAnnotationEditor(
    context,
    about: describeAnnotation(a),
    initial: a,
    values: a.chart?.values ?? const [],
  );
  if (edit == null) return;
  await AnnotationScope._replace(a, edit.delete ? null : a.copyWith(note: edit.note, shots: edit.shots));
}
