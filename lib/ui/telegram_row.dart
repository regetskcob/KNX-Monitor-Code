import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../model/expert_mode.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/alarms.dart';
import '../model/analysis.dart';
import '../model/annotation.dart';
import '../model/plain_text.dart';
import '../model/tap_points.dart';
import '../model/live_plain.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'annotations.dart';

const tabular = [FontFeature.tabularFigures()];

/// Time "hh:mm:ss.mmm"; without [millis] "hh:mm:ss", without [seconds] "hh:mm".
String formatTime(DateTime t, {bool seconds = true, bool millis = true}) {
  String two(int v) => v.toString().padLeft(2, '0');
  final hm = '${two(t.hour)}:${two(t.minute)}';
  if (!seconds) return hm;
  if (!millis) return '$hm:${two(t.second)}';
  return '$hm:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
}

/// Date depending on the language as "14.10.2026" or "2026-10-14".
String formatDate(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return s.localeName.startsWith('de')
      ? '${two(t.day)}.${two(t.month)}.${t.year}'
      : '${t.year}-${two(t.month)}-${two(t.day)}';
}

/// From this width the monitor shows telegrams as a table.
const wideRowBreakpoint = 720.0;

/// A row in the monitor: type, name/address, sender, time, value.
///
/// Narrow as a compact two-line row, wide ([wide]) as a table row with columns
/// matching [TelegramTableHeader].
class TelegramRow extends StatelessWidget {
  const TelegramRow({
    super.key,
    required this.telegram,
    this.wide = false,
    this.count,
    this.selected,
    this.focused = false,
    this.related = false,
    this.zebra = false,
    this.issues = const [],
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapUp,
  });

  final Telegram telegram;
  final bool wide;

  /// Number of telegrams on this address (values view).
  final int? count;

  /// Selection mode: checkbox instead of the type abbreviation. `null` = not in selection mode.
  final bool? selected;

  /// Whether it is opened in the detail panel.
  final bool focused;

  /// Same group address as the focused telegram; subtly marked.
  final bool related;

  /// Shaded row (zebra stripes as in the PDF).
  final bool zebra;

  /// Anomalies (repetition, no response …) as small chips.
  final List<TelegramIssue> issues;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final GestureTapUpCallback? onSecondaryTapUp;

  @override
  Widget build(BuildContext context) {
    final t = telegram;

    final leading = selected != null
        ? SizedBox.square(
            dimension: 28,
            child: Checkbox(value: selected, onChanged: (_) => onTap?.call(), visualDensity: VisualDensity.compact),
          )
        : TypeBadge(type: t.type, outgoing: t.outgoing);
    // Commented: a small flag on the kind.
    final flagged = ListenableBuilder(
      listenable: AnnotationStore.instance,
      builder: (context, child) => !AnnotationScope.hasTelegram(t)
          ? child!
          : Stack(
              clipBehavior: Clip.none,
              children: [
                child!,
                PositionedDirectional(
                  top: -6,
                  end: -6,
                  child: Icon(
                    AppIcons.annotationSet,
                    size: HzIconSize.badge,
                    color: context.hz.warning,
                    semanticLabel: s.annotationsLabel,
                  ),
                ),
              ],
            ),
      child: leading,
    );

    // Horizont: selection is accent-tint, in the standard style with a 2 px line
    // on the left in the accent colour (the soft style leaves it out); an alarm
    // is the same line in critical (with a badge in the row); rows are separated
    // by a hairline.
    final alarm = activeAlarm(telegram);
    final hz = context.hz;
    final color = switch (this) {
      _ when selected == true || focused => hz.accentTint,
      _ when alarm != null => hz.criticalTint,
      _ when related => hz.accentTint.withValues(alpha: 0.5),
      _ => Colors.transparent,
    };
    final chosen = (focused || selected == true) && !context.hzTheme.soft;
    final line = alarm != null ? hz.critical : (chosen ? hz.accent : Colors.transparent);
    return Material(
      color: color,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTapUp: onSecondaryTapUp,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: line, width: Lines.selection),
              bottom: BorderSide(color: hz.line, width: Lines.hairline),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            HzSpace.s16 - Lines.selection,
            wide ? HzSpace.s8 : HzSpace.s12,
            HzSpace.s16,
            wide ? HzSpace.s8 : HzSpace.s12,
          ),
          child: wide
              // The column "Seen at" only where the table has room for it (issue #8).
              ? LayoutBuilder(
                  builder: (context, box) => _wide(
                    context,
                    flagged,
                    seenColumn: TelegramTableHeader.hasSeenColumn(box.maxWidth + HzSpace.s16 * 2),
                  ),
                )
              : _compact(context, flagged),
        ),
      ),
    );
  }

  Widget _compact(BuildContext context, Widget leading) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final store = CatalogStore.instance;
    final t = telegram;
    // Time first, always in the same place (fixed width) and understated; then
    // the group address emphasized, the sender muted.
    final metaStyle = context.figures(theme.textTheme.bodySmall).copyWith(color: scheme.onSurfaceVariant);
    final addressStyle = context.mono(theme.textTheme.bodySmall).copyWith(color: scheme.onSurfaceVariant);
    // Kind only for experts and in the selection.
    final showLeading = expert || selected != null;
    // In plain language the sender is already part of the sentence.
    final plain = LivePlainSetting.instance.value;
    final rest = [
      if (!plain) t.outgoing ? s.rowSent : store.sender(t),
      if (count != null) '$count×',
    ].join(metaSeparator);
    final meta = TextSpan(
      children: [
        TextSpan(
          text: formatTime(t.time, millis: expert),
          style: TextStyle(color: context.hz.textFaint),
        ),
        if (plain) ...[
          const TextSpan(text: metaSeparator),
          TextSpan(
            text: t.destinationText,
            style: TextStyle(color: context.hz.text, fontWeight: FontWeight.w600),
          ),
        ],
        if (rest.isNotEmpty) TextSpan(text: '$metaSeparator$rest'),
      ],
    );

    // The value gets its share of this row, not of the window: in the live column beside the
    // overview (a third of a wide window) a long value pushed the row out of its card.
    return LayoutBuilder(
      builder: (context, box) => Row(
        children: [
          if (showLeading) ...[leading, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Address and name first, as in the wide table.
                Text.rich(
                  TextSpan(
                    children: [
                      if (!plain && store.infoOf(t) != null)
                        TextSpan(
                          text: '${t.destinationText} ',
                          style: addressStyle.copyWith(fontWeight: FontWeight.w600),
                        ),
                      TextSpan(text: plain ? telegramSentence(t) : store.title(t)),
                    ],
                  ),
                  maxLines: plain ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: HzSpace.s2),
                if (issues.isNotEmpty || activeAlarm(t) != null) ...[
                  IssueChips(issues: issues, telegram: t, alarm: activeAlarm(t)),
                  const SizedBox(height: 3),
                ],
                if (TapScope.labels.length > 1) ...[TapChips(telegram: t), const SizedBox(height: 3)],
                Text.rich(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: metaStyle),
              ],
            ),
          ),
          // Plain language: the value is part of the sentence.
          if (!plain) ...[
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth * 0.4),
              child: _Value(telegram: t),
            ),
          ],
        ],
      ),
    );
  }

  Widget _wide(BuildContext context, Widget leading, {bool seenColumn = false}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final store = CatalogStore.instance;
    final t = telegram;
    final info = store.infoOf(t);
    final device = store.deviceOf(t);
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final mono = context.hzTheme.data;

    Widget twoLines(String top, String? bottom, {TextStyle? style}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(top, maxLines: 2, overflow: TextOverflow.ellipsis, style: style ?? mono),
        if (bottom != null && bottom.isNotEmpty)
          Text(bottom, maxLines: 2, overflow: TextOverflow.ellipsis, style: muted),
      ],
    );

    final chips = [
      if (issues.any((i) => i != TelegramIssue.unusualHop) || activeAlarm(t) != null) ...[
        const SizedBox(height: HzSpace.s4),
        IssueChips(
          issues: [
            for (final i in issues)
              if (i != TelegramIssue.unusualHop) i,
          ],
          telegram: t,
          alarm: activeAlarm(t),
        ),
      ],
    ];
    // Plain language: one sentence instead of sender, name and value.
    if (LivePlainSetting.instance.value) {
      return Row(
        children: [
          SizedBox(
            width: TelegramTableHeader.timeWidth,
            child: Text(formatTime(t.time), style: mono),
          ),
          if (expert || selected != null)
            SizedBox(
              width: TelegramTableHeader.typeWidth,
              child: Align(alignment: Alignment.centerLeft, child: leading),
            ),
          SizedBox(
            width: TelegramTableHeader.gaWidth,
            child: Text(t.destinationText, style: mono.copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                twoLines(
                  telegramSentence(t),
                  [?info?.path, if (count != null) '$count×'].join(metaSeparator),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                ...chips,
              ],
            ),
          ),
        ],
      );
    }
    final names = TelegramTableHeader.hasNameColumn;
    final under = [
      ...chips,
      // Several tap points, but no room for their column: under the name.
      if (TapScope.labels.length > 1 && !seenColumn)
        Padding(
          padding: const EdgeInsets.only(top: HzSpace.s2),
          child: TapChips(telegram: t),
        ),
    ];
    return Row(
      children: [
        SizedBox(
          width: TelegramTableHeader.timeWidth,
          child: Text(formatTime(t.time), style: mono),
        ),
        // Kind only for experts and in the selection, as on the phone.
        if (expert || selected != null)
          SizedBox(
            width: TelegramTableHeader.typeWidth,
            child: Align(alignment: Alignment.centerLeft, child: leading),
          ),
        SizedBox(
          width: TelegramTableHeader.gaWidth,
          child: Text(t.destinationText, style: mono.copyWith(fontWeight: FontWeight.w600)),
        ),
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (t.outgoing)
                twoLines(s.rowSent, s.rowThisTunnel)
              else
                // Expert mode: also the sender's installation location from the project.
                twoLines(t.sourceText, [?device?.name, if (expert) ?device?.location].join(' · ')),
              // Without the column "Name": its chips under the sender.
              if (!names) ...under,
            ],
          ),
        ),
        const SizedBox(width: HzSpace.s12),
        if (expert) ...[
          SizedBox(
            width: TelegramTableHeader.hopWidth,
            child: _Hop(telegram: t),
          ),
          const SizedBox(width: HzSpace.s12),
        ],
        if (names) ...[
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                twoLines(
                  info?.name ?? '—',
                  info?.path,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                // Der Hop-Count steht breit in einer eigenen Spalte.
                ...under,
              ],
            ),
          ),
          const SizedBox(width: HzSpace.s12),
        ],
        // Several tap points (issue #8): where it was seen, in a column of its own.
        if (seenColumn) ...[
          SizedBox(
            width: TelegramTableHeader.seenWidth,
            child: TapChips(telegram: t),
          ),
          const SizedBox(width: HzSpace.s12),
        ],
        // Without names the value gets the room of the name.
        Expanded(
          flex: names ? 3 : 3 + 5,
          child: Align(
            alignment: Alignment.centerRight,
            child: _Value(telegram: t, count: count),
          ),
        ),
      ],
    );
  }
}

/// Column headers matching the wide [TelegramRow]: labels on the lowered
/// surface, a hairline below.
class TelegramTableHeader extends StatelessWidget {
  const TelegramTableHeader({super.key});

  static const timeWidth = 112.0;
  static const typeWidth = 52.0;
  static const gaWidth = 88.0;
  static const hopWidth = 56.0;

  /// Column "Seen at": room for three chips in a row, more wrap.
  static const seenWidth = 132.0;

  /// Table width from which the column "Seen at" is shown. Below, the tap points' chips sit under
  /// the name, so that names and senders do not break in the middle of a word.
  static const seenFrom = 1000.0;

  /// Whether a table of [width] shows the column "Seen at": several tap points and room.
  static bool hasSeenColumn(double width) => TapScope.labels.length > 1 && width >= seenFrom;

  /// Whether the column "Name" shows: only with names from a project or taught in. Without
  /// them it would read "—" in every row; the value gets its room instead.
  static bool get hasNameColumn => !CatalogStore.instance.catalog.isEmpty;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    return Container(
      decoration: BoxDecoration(
        color: hz.sunken,
        border: Border(
          bottom: BorderSide(color: hz.line, width: Lines.hairline),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: HzSpace.s16, vertical: HzSpace.s8),
      // The column "Name" follows the project (see [hasNameColumn]).
      child: ListenableBuilder(
        listenable: CatalogStore.instance,
        builder: (context, _) => LayoutBuilder(
          builder: (context, box) => Row(
            children: [
              SizedBox(width: timeWidth, child: Kennung(s.columnTime)),
              if (expert) SizedBox(width: typeWidth, child: Kennung(s.columnType)),
              SizedBox(width: gaWidth, child: Kennung(s.columnAddress)),
              if (LivePlainSetting.instance.value)
                Expanded(child: Kennung(s.plainColumnEvent))
              else
                ..._columns(seen: hasSeenColumn(box.maxWidth + HzSpace.s16 * 2)),
            ],
          ),
        ),
      ),
    );
  }

  /// Sender, hop (only in expert mode), name and value as separate columns.
  List<Widget> _columns({required bool seen}) => [
    // Sender and hop together, the name right next to the value.
    Expanded(flex: 3, child: Kennung(s.columnSender)),
    const SizedBox(width: HzSpace.s12),
    if (expert) ...[SizedBox(width: hopWidth, child: Kennung(s.columnHop)), const SizedBox(width: HzSpace.s12)],
    if (hasNameColumn) ...[Expanded(flex: 5, child: Kennung(s.columnName)), const SizedBox(width: HzSpace.s12)],
    if (seen) ...[SizedBox(width: seenWidth, child: Kennung(s.tapColumnSeen)), const SizedBox(width: HzSpace.s12)],
    Expanded(
      flex: hasNameColumn ? 3 : 3 + 5,
      child: Align(alignment: Alignment.centerRight, child: Kennung(s.columnValue)),
    ),
  ];
}

/// Hop count in Monaspace; unusual values (≠ 6, via couplers) with a triangle in
/// warning, the tooltip explains it.
class _Hop extends StatelessWidget {
  const _Hop({required this.telegram});

  final Telegram telegram;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final unusual = telegram.unusualHop;
    final text = Text(
      '${telegram.hopCount}',
      style: context.hzTheme.data.copyWith(color: unusual ? hz.warning : hz.textMuted),
    );
    if (!unusual) return text;
    return Tooltip(
      message: TelegramIssue.unusualHop.hint,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(HorizontStatus.warning.icon, size: 14, color: hz.warning),
          const SizedBox(width: HzSpace.s4),
          text,
        ],
      ),
    );
  }
}

/// Value of a telegram in Monaspace; muted for read telegrams.
class _Value extends StatelessWidget {
  const _Value({required this.telegram, this.count});

  final Telegram telegram;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final read = telegram.type == TelegramType.read;
    final alarm = activeAlarm(telegram) != null;
    return Text(
      CatalogStore.instance.value(telegram),
      textAlign: TextAlign.end,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: context
          .figures(Theme.of(context).textTheme.bodyMedium)
          .copyWith(
            fontWeight: read ? null : FontWeight.w600,
            color: alarm ? hz.critical : (read ? hz.textMuted : hz.text),
          ),
    );
  }
}

/// Abbreviation of the telegram kind (W/R/A) in Monaspace on the tint of its
/// color: W in accent, R in warning, A in info. Self-sent ones are outlined
/// instead of tinted. Always with a letter, never color alone.
class TypeBadge extends StatelessWidget {
  const TypeBadge({super.key, required this.type, this.outgoing = false, this.size = 24});

  final TelegramType type;
  final bool outgoing;
  final double size;

  @override
  Widget build(BuildContext context) {
    final label = Palette.label(type);
    final semantic = outgoing ? s.badgeSentSemantics(label) : label;
    final c = context.hz;
    final status = switch (type) {
      TelegramType.write => null,
      TelegramType.read => HorizontStatus.warning,
      TelegramType.response => HorizontStatus.info,
    };
    final fg = status?.color(c) ?? c.accentText;
    final edge = MediaQuery.textScalerOf(context).scale(size);
    return Tooltip(
      message: semantic,
      child: Semantics(
        label: semantic,
        excludeSemantics: true,
        child: Container(
          width: edge,
          height: edge,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: outgoing ? null : (status?.tint(c) ?? c.accentTint),
            border: outgoing ? Border.all(color: fg, width: Lines.hairline) : null,
            borderRadius: Radii.row,
          ),
          child: Icon(Palette.icon(type), size: edge * 0.68, color: fg),
        ),
      ),
    );
  }
}

/// Hints on a telegram as status badges: warnings with a triangle, information
/// neutral; an active alarm first with an octagon.
class IssueChips extends StatelessWidget {
  const IssueChips({super.key, required this.issues, required this.telegram, this.alarm});

  final List<TelegramIssue> issues;
  final Telegram telegram;

  /// Active alarm/fault, as a critical badge in front.
  final AlarmKind? alarm;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: HzSpace.s4,
      runSpacing: HzSpace.s4,
      children: [
        if (alarm != null) AlarmChip(kind: alarm!),
        // Hop hint only in expert mode.
        for (final issue in issues)
          if (expert || issue != TelegramIssue.unusualHop)
            Tooltip(
              message: issue.hint,
              child: HorizontBadge(
                issue.warning ? HorizontStatus.warning : HorizontStatus.neutral,
                label: issue == TelegramIssue.unusualHop ? '${issue.label} ${telegram.hopCount}' : issue.label,
              ),
            ),
      ],
    );
  }
}

/// Critical badge "Alarm" or "Störung" (fault): octagon, word, color.
class AlarmChip extends StatelessWidget {
  const AlarmChip({super.key, required this.kind, this.large = false});

  final AlarmKind kind;

  /// Kept for callers; the badge has one size.
  final bool large;

  @override
  Widget build(BuildContext context) =>
      HorizontBadge(HorizontStatus.critical, label: kind == AlarmKind.alarm ? s.alarmLabel : s.faultLabel);
}

/// Tap points where a telegram was seen (issue #8): one small chip per tap point, the first one
/// (origin) emphasized. Only with more than one tap point; otherwise nothing changes.
class TapChips extends StatelessWidget {
  const TapChips({super.key, required this.telegram});

  final Telegram telegram;

  @override
  Widget build(BuildContext context) {
    final labels = TapScope.labels;
    if (labels.length < 2) return const SizedBox.shrink();
    final hz = context.hz;
    final style = context.hzTheme.data.copyWith(fontSize: 12, height: 16 / 12);
    String label(int tap) => tap < labels.length ? labels[tap] : '${tap + 1}';
    final taps = telegram.taps.toList();
    // Tap points that were not reachable at that time, as one mark with the names behind it: a
    // missing chip must not read as "filtered", but a chip per tap point in every row is noise.
    // Paused ones are not named here at all, the strip above the list says so.
    final away = [
      for (var tap = 0; tap < labels.length; tap++)
        if (!taps.contains(tap) && TapScope.gaps.state(tap, telegram.time) == TapSeen.away) label(tap),
    ];
    final awayText = away.isEmpty ? null : s.tapRowAway(away.join(', '));
    return Semantics(
      label: ['${s.detailsPath}: ${taps.map(label).join(', ')}', ?awayText].join(', '),
      child: ExcludeSemantics(
        child: Wrap(
          spacing: HzSpace.s4,
          runSpacing: HzSpace.s4,
          children: [
            for (final (i, tap) in taps.indexed)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: i == 0 ? hz.accentTint : hz.surface,
                  border: Border.all(color: i == 0 ? hz.accent : hz.lineStrong),
                  borderRadius: Radii.row,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  child: Text(
                    label(tap),
                    style: style.copyWith(
                      color: i == 0 ? hz.accentText : hz.text,
                      fontWeight: i == 0 ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              ),
            if (awayText != null)
              Tooltip(
                message: awayText,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: hz.sunken, borderRadius: Radii.row),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_outlined, size: 12, color: hz.textMuted),
                        const SizedBox(width: 3),
                        Text('${away.length}', style: style.copyWith(color: hz.textMuted)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
