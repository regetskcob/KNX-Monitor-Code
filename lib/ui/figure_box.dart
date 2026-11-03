import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../l10n/locale_controller.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// A key figure of the green box. [status] sets symbol and color when the value
/// stands out.
typedef BoxFigure = ({String label, String value, HorizontStatus? status});

/// Green box of the tool pages: key figures, the first one large and green;
/// [footer] next to or below them. The main action sits full-width below the
/// box on narrow layouts, and on the right inside the box on wide ones.
class FigureBox extends StatelessWidget {
  const FigureBox({super.key, this.figures = const [], this.action, this.footer, this.above, this.below});

  final List<BoxFigure> figures;
  final Widget? action;

  /// Last run, history: narrow below a line, wide next to the figures.
  final Widget? footer;

  /// Above the figures, full width (explanation before the first run).
  final Widget? above;

  /// Below the figures, full width (progress, switches).
  final Widget? below;

  /// From this text scale on, the narrow layout is kept.
  static const _maxWideScale = 1.3;

  /// Maximum share of the width for the main action inside the box.
  static const _maxActionShare = 0.45;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= Breakpoints.medium && MediaQuery.textScalerOf(context).scale(1) <= _maxWideScale;
        final numbers = figures.isEmpty
            ? null
            : Wrap(
                spacing: HzSpace.s24,
                runSpacing: HzSpace.s8,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [for (final (i, figure) in figures.indexed) _Figure(figure: figure, main: i == 0)],
              );
        final footer = this.footer;
        final action = this.action;
        final content = wide
            ? Row(
                spacing: HzSpace.s24,
                children: [
                  // With a footer (few figures), only as wide as needed.
                  if (numbers != null) footer == null ? Expanded(child: numbers) : numbers,
                  if (footer != null) Expanded(child: footer),
                  if (numbers == null && footer == null) const Spacer(),
                  // As wide as the label; the figures keep their space.
                  if (action != null)
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: box.maxWidth * _maxActionShare),
                      child: action,
                    ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?numbers,
                  if (footer != null) ...[
                    if (numbers != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
                        child: Divider(
                          height: Lines.hairline,
                          thickness: Lines.hairline,
                          color: hz.accentText.withValues(alpha: 0.22),
                        ),
                      ),
                    footer,
                  ],
                ],
              );
        // Material instead of DecoratedBox so switches inside show their press
        // feedback.
        final surface = Material(
          color: hz.accentTint,
          shape: const RoundedRectangleBorder(borderRadius: Radii.box),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(HzSpace.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (above case final above?) ...[above, const SizedBox(height: HzSpace.s12)],
                content,
                if (below case final below?) ...[const SizedBox(height: HzSpace.s12), below],
              ],
            ),
          ),
        );
        if (wide || action == null) return surface;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            surface,
            const SizedBox(height: HzSpace.s12),
            action,
          ],
        );
      },
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.figure, required this.main});

  final BoxFigure figure;
  final bool main;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final status = figure.status;
    final style = main
        ? context.figures(theme.textTheme.titleLarge).copyWith(color: hz.accentText, fontWeight: FontWeight.w700)
        : context.figures(theme.textTheme.titleMedium).copyWith(fontWeight: FontWeight.w600);
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Kennung(figure.label),
          const SizedBox(height: HzSpace.s2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status != null) ...[
                Icon(status.icon, size: 16, color: status.color(hz)),
                const SizedBox(width: HzSpace.s4),
              ],
              Text(figure.value, style: status == null ? style : style.copyWith(color: status.color(hz))),
            ],
          ),
        ],
      ),
    );
  }
}

/// Filter as a segmented toggle: full width when narrow (scrolling sideways
/// with large text), at most [maxWidth] when wide so the segments don't spread
/// too far apart.
class FilterBar<T> extends StatelessWidget {
  const FilterBar({super.key, required this.segments, required this.selected, required this.onChanged, this.maxWidth});

  final List<ButtonSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final limit = maxWidth ?? Widths.form + HzSpace.s96;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: box.maxWidth < limit ? box.maxWidth : limit),
          child: SegmentedButton<T>(
            showSelectedIcon: false,
            // Segments are equally wide (longest word): little padding so all
            // fit on an iPhone.
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: HzSpace.s8)),
            ),
            segments: segments,
            selected: {selected},
            onSelectionChanged: (v) => onChanged(v.first),
          ),
        ),
      );
    },
  );
}

/// Info symbol in the app bar: opens the page's explanation.
class InfoAction extends StatelessWidget {
  const InfoAction({super.key, required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: title,
    onPressed: () => showInfoDialog(context, title: title, content: Text(text)),
    icon: const Icon(AppIcons.info),
  );
}

/// Rows of a card with hairlines in between; [flat] without surface and border
/// (lists placed directly on the background).
class RowCard extends StatelessWidget {
  const RowCard({super.key, required this.children, this.flat = false});

  final List<Widget> children;
  final bool flat;

  @override
  Widget build(BuildContext context) => SectionCard(
    flat: flat,
    padding: flat ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: Gap.card, vertical: HzSpace.s4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, row) in children.indexed) ...[if (i > 0) const Divider(height: Lines.hairline), row],
      ],
    ),
  );
}

/// Row: title, meta below, value and chevron on the right (if tappable).
class CardRow extends StatelessWidget {
  const CardRow({
    super.key,
    required this.title,
    this.meta,
    this.metaAddress = false,
    this.address,
    this.enabled = true,
    this.value,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.chevron,
  });

  final String title;
  final String? meta;

  /// Meta is an address: in monospace.
  final bool metaAddress;

  /// Address before the title, in monospace.
  final String? address;
  final bool enabled;

  /// Value on the right, muted.
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Chevron on the right; by default on tappable rows without their own
  /// [trailing].
  final bool? chevron;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final metaStyle = theme.textTheme.bodySmall?.copyWith(color: hz.textFaint);
    final arrow = chevron ?? (onTap != null && this.trailing == null);
    final value = this.value;
    final trailing = this.trailing;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      title: address == null
          ? Text(title)
          : Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$address ', style: context.mono(metaStyle)),
                  TextSpan(text: title),
                ],
              ),
            ),
      subtitle: switch (meta) {
        final meta? when metaAddress => Text(meta, style: context.mono(metaStyle)),
        final meta? => Text(meta, style: metaStyle),
        null => null,
      },
      trailing: value == null && trailing == null && !arrow
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              spacing: HzSpace.s4,
              children: [
                if (value != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.4),
                    child: Text(
                      value,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted),
                    ),
                  ),
                ?trailing,
                if (arrow) Icon(AppIcons.next, size: HzIconSize.row, color: hz.textMuted),
              ],
            ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// Row with a switch.
class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.title, this.meta, required this.value, required this.onChanged});

  final String title;
  final String? meta;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: meta == null
        ? null
        : Text(meta!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.hz.textFaint)),
    value: value,
    onChanged: onChanged,
  );
}

/// Section heading with spacing below.
class SectionHead extends StatelessWidget {
  const SectionHead(this.title, {super.key, this.count, this.detail, this.trailing});

  final String title;
  final int? count;

  /// A text such as "2 von 9" (2 of 9) instead of the number.
  final String? detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Gap.section, bottom: Gap.item),
    child: Row(
      spacing: HzSpace.s8,
      children: [
        Expanded(
          child: Row(
            spacing: HzSpace.s8,
            children: [
              Flexible(child: SectionTitle(title, count: count)),
              if (detail != null)
                Text(detail!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.hz.textFaint)),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Explanation of a page behind the info symbol in the app bar.
Future<void> showInfoDialog(BuildContext context, {required String title, required Widget content}) =>
    showAdaptiveDialog<void>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(title),
        content: SingleChildScrollView(child: content),
        actions: [
          horizontDialogAction(context, label: s.commonClose, primary: true, onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
