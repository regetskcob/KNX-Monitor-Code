import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/annotation.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'annotation_editor.dart';
import 'annotations.dart';
import 'recording_timeline.dart';
import 'telegram_row.dart';

/// All comments of the installation by day, newest first, including those
/// without a recording, for reading, editing and deleting. A phone shows the
/// list and opens the editor on a tap; from [Breakpoints.expanded] on the list
/// stays on the left and the chosen comment is shown on the right, with its
/// screenshots large enough to read.
class AnnotationsScreen extends StatefulWidget {
  const AnnotationsScreen({super.key, this.device, this.groups = const {}});

  /// Only the comments on this device (with its addresses [groups]).
  final int? device;
  final Set<int> groups;

  @override
  State<AnnotationsScreen> createState() => _AnnotationsScreenState();
}

class _AnnotationsScreenState extends State<AnnotationsScreen> {
  /// From this width on the list and the chosen comment sit side by side.
  static const _detailFrom = Breakpoints.expanded;

  /// Width of the list in the wide layout: time, reference and two lines of text.
  static const _listWidth = Widths.column - HzSpace.s32;

  /// Id of the comment shown on the right; the newest while none is chosen or the chosen one is gone.
  String? _selected;

  /// Day headings and one row per comment; with [selected] (wide layout) a row chooses instead of
  /// opening the editor.
  List<Widget> _rows(BuildContext context, List<Annotation> all, {String? selected}) {
    final children = <Widget>[];
    String? day;
    for (final a in all) {
      final d = formatDate(a.time);
      if (d != day) {
        day = d;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(HzSpace.s16, HzSpace.s16, HzSpace.s16, HzSpace.s4),
            child: Kennung(d),
          ),
        );
      }
      children.add(
        selected == null
            ? AnnotationTile(annotation: a, onTap: () => editAnnotation(context, a))
            : HorizontSelectable(
                key: ValueKey('annotation-${a.id}'),
                selected: a.id == selected,
                onTap: () => setState(() => _selected = a.id),
                padding: EdgeInsets.zero,
                child: AnnotationTile(annotation: a),
              ),
      );
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    return Scaffold(
      appBar: AppBar(
        title: device == null
            ? Text(s.annotationsTitle)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Kennung(formatIndividual(device)), Text(s.annotationsTitle)],
              ),
      ),
      body: LayoutBuilder(
        builder: (context, box) => ListenableBuilder(
          listenable: AnnotationStore.instance,
          builder: (context, _) {
            final all = device == null
                ? AnnotationStore.instance.all.reversed.toList()
                : AnnotationScope.forDevice(device, widget.groups);
            if (all.isEmpty) {
              return HorizontEmptyHint(icon: AppIcons.annotation, text: s.annotationsEmpty);
            }
            if (box.maxWidth < _detailFrom) {
              return ListView(
                padding: const EdgeInsets.only(bottom: HzSpace.s32),
                children: _rows(context, all),
              );
            }
            final shown = all.where((a) => a.id == _selected).firstOrNull ?? all.first;
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Widths.wide),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _listWidth,
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: HzSpace.s32),
                        children: _rows(context, all, selected: shown.id),
                      ),
                    ),
                    const VerticalDivider(width: Lines.hairline),
                    Expanded(
                      child: _AnnotationDetail(key: ValueKey('detail-${shown.id}'), annotation: shown),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The chosen comment in the wide layout: reference, text, the chart's values and the screenshots
/// as wide as the pane allows; editing and deleting stay in the editor behind the button.
class _AnnotationDetail extends StatelessWidget {
  const _AnnotationDetail({super.key, required this.annotation});

  final Annotation annotation;

  /// Widest a screenshot is shown in place; tapping still opens it full size.
  static const _maxShotWidth = 720.0;

  /// From this pane width (at text scale 1) the reference and the edit button share a line.
  static const _headerRow = 520.0;

  /// Width to height of the frame a screenshot is fitted into.
  static const _shotAspect = 1.6;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final a = annotation;
    final values = a.chart?.values ?? const <ChartValue>[];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Gap.gutterWide, Gap.section, Gap.gutterWide, Gap.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final about = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Gap.inner,
                children: [
                  Icon(AppIcons.annotationSet, size: 18, color: hz.warning),
                  Expanded(
                    child: Text(
                      describeAnnotation(a),
                      style: context.mono(theme.textTheme.bodySmall).copyWith(color: hz.textMuted),
                    ),
                  ),
                ],
              );
              final edit = OutlinedButton.icon(
                onPressed: () => editAnnotation(context, a),
                icon: const Icon(AppIcons.edit, size: 18),
                label: Text(s.annotationEditTitle),
              );
              // Side by side while the reference keeps a readable share; a narrow pane or large
              // text puts the button below it.
              final scale = MediaQuery.textScalerOf(context).scale(1);
              if (box.maxWidth < _headerRow * scale) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Gap.inner,
                  children: [about, edit],
                );
              }
              return Row(
                spacing: Gap.inner,
                children: [
                  Expanded(child: about),
                  edit,
                ],
              );
            },
          ),
          if (a.note.isNotEmpty) ...[
            const SizedBox(height: Gap.section),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Widths.reading),
              child: Text(a.note, style: theme.textTheme.titleMedium),
            ),
          ],
          if (values.isNotEmpty) ...[
            const SizedBox(height: Gap.section),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Widths.form),
              child: AnnotationValues(values: values),
            ),
          ],
          if (a.shots.isNotEmpty) ...[
            const SizedBox(height: Gap.section),
            LayoutBuilder(
              builder: (context, box) {
                // One screenshot takes the pane, several share it two by two.
                final perRow = a.shots.length == 1 ? 1 : 2;
                final width = ((box.maxWidth - Gap.inner * (perRow - 1)) / perRow).clamp(0.0, _maxShotWidth);
                return Wrap(
                  spacing: Gap.inner,
                  runSpacing: Gap.inner,
                  children: [
                    for (final id in a.shots)
                      ShotThumb(id: id, width: width, size: width / _shotAspect, fit: BoxFit.contain),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
