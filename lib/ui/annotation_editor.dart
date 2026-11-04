import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:horizont/horizont.dart';

import '../l10n/locale_controller.dart';
import '../model/annotation.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';

/// Result of the comment dialog; [delete] = remove the comment.
typedef AnnotationEdit = ({String note, List<String> shots, bool delete});

/// Writes or edits a comment: what happened, plus up to three screenshots.
/// [context] shows at the top what the comment is attached to (telegram, chart,
/// point in time). [values]: the chart's values at that time, shown below it.
/// `null` = cancelled.
Future<AnnotationEdit?> showAnnotationEditor(
  BuildContext context, {
  required String about,
  Annotation? initial,
  List<ChartValue> values = const [],
}) => showAdaptiveDialog<AnnotationEdit>(
  context: context,
  builder: (_) => _AnnotationDialog(about: about, initial: initial, values: values),
);

class _AnnotationDialog extends StatefulWidget {
  const _AnnotationDialog({required this.about, this.initial, this.values = const []});

  final String about;
  final Annotation? initial;
  final List<ChartValue> values;

  @override
  State<_AnnotationDialog> createState() => _AnnotationDialogState();
}

class _AnnotationDialogState extends State<_AnnotationDialog> {
  late final _note = TextEditingController(text: widget.initial?.note);
  late List<String> _shots = [...?widget.initial?.shots];
  String? _error;

  /// Screenshots newly saved in this dialog: delete them right away on cancel
  /// or when they are removed again.
  final _added = <String>{};

  Future<void> _dropUnused({required bool cancelled}) async {
    for (final id in _added) {
      if (cancelled || !_shots.contains(id)) await ShotStore.instance.delete(id);
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final note = _note.text.trim();
    if (note.isEmpty && _shots.isEmpty) {
      setState(() => _error = s.annotationEmpty);
      return;
    }
    _dropUnused(cancelled: false);
    Navigator.pop(context, (note: note, shots: _shots, delete: false));
  }

  /// Value before → value then, one row per series.
  Widget _values(BuildContext context) {
    final hz = context.hz;
    final theme = Theme.of(context);
    final name = theme.textTheme.bodySmall?.copyWith(color: hz.textMuted);
    final value = context.mono(theme.textTheme.bodyMedium).copyWith(color: hz.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: HzSpace.s4,
      children: [
        Kennung(s.annotationValuesLabel),
        for (final v in widget.values)
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(v.name, style: name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: HzSpace.s12),
              if (v.before case final before?) ...[
                Text(before, style: value.copyWith(color: hz.textMuted)),
                Text('  →  ', style: value.copyWith(color: hz.textFaint)),
              ],
              Text(v.now, style: value.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
      ],
    );
  }

  /// Wide screens (iPad, Mac, browser) get a regular dialog with buttons
  /// instead of the narrow phone alert.
  Widget _action(
    BuildContext context, {
    required bool wide,
    required String label,
    required VoidCallback onPressed,
    bool primary = false,
    bool destructive = false,
  }) {
    if (!wide) {
      return horizontDialogAction(
        context,
        label: label,
        onPressed: onPressed,
        primary: primary,
        destructive: destructive,
      );
    }
    final theme = HorizontTheme.of(context);
    if (primary) return FilledButton(onPressed: onPressed, child: Text(label));
    return TextButton(
      style: destructive ? TextButton.styleFrom(foregroundColor: theme.colors.critical) : null,
      onPressed: onPressed,
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: context.hz.textMuted);
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final title = Text(editing ? s.annotationEditTitle : s.annotationTitle);
    final content = Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: wide ? 520 : 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.about, style: context.mono(muted)),
            if (widget.values.isNotEmpty) ...[const SizedBox(height: HzSpace.s16), _values(context)],
            const SizedBox(height: HzSpace.s16),
            HorizontField(
              label: s.annotationNoteLabel,
              child: TextField(
                style: context.hzTheme.field,
                controller: _note,
                autofocus: !editing,
                minLines: wide ? 3 : 2,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => _error == null ? null : setState(() => _error = null),
                decoration: InputDecoration(hintText: s.annotationNoteHint, errorText: _error),
              ),
            ),
            const SizedBox(height: HzSpace.s16),
            ShotPicker(
              shots: _shots,
              onChanged: (v) => setState(() {
                _added.addAll(v.where((id) => !_shots.contains(id) && !(widget.initial?.shots.contains(id) ?? false)));
                _shots = v;
              }),
            ),
          ],
        ),
      ),
    );
    final actions = [
      if (editing)
        _action(
          context,
          wide: wide,
          label: s.annotationDelete,
          destructive: true,
          onPressed: () {
            // Images newly added in the dialog don't belong to anything yet:
            // delete them.
            _dropUnused(cancelled: true);
            Navigator.pop(context, (note: '', shots: <String>[], delete: true));
          },
        ),
      _action(
        context,
        wide: wide,
        label: s.commonCancel,
        onPressed: () {
          _dropUnused(cancelled: true);
          Navigator.pop(context);
        },
      ),
      _action(context, wide: wide, label: s.commonSave, primary: true, onPressed: _submit),
    ];
    if (wide) {
      return AlertDialog(
        scrollable: true,
        title: title,
        content: content,
        actionsPadding: const EdgeInsets.fromLTRB(HzSpace.s24, 0, HzSpace.s24, HzSpace.s24),
        actions: actions,
      );
    }
    return AlertDialog.adaptive(
      // With the keyboard open, small phones get cramped (A14): the content
      // scrolls.
      scrollable: true,
      title: title,
      content: content,
      actions: actions,
    );
  }
}

/// Up to [max] screenshots: pick them, save them downscaled ([ShotStore]), show
/// them as thumbnails and remove them again.
class ShotPicker extends StatefulWidget {
  const ShotPicker({super.key, required this.shots, required this.onChanged, this.max = Annotation.maxShots});

  final List<String> shots;
  final ValueChanged<List<String>> onChanged;
  final int max;

  @override
  State<ShotPicker> createState() => _ShotPickerState();
}

class _ShotPickerState extends State<ShotPicker> {
  bool _busy = false;
  String? _error;

  Future<void> _add() async {
    final room = widget.max - widget.shots.length;
    if (room <= 0) return;
    if (_busy) return;
    setState(() => _busy = true);
    List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(type: FileType.image);
    } on PlatformException catch (e) {
      // Second pick while the first one was still open: ignore silently.
      debugPrint('Bildauswahl: $e');
      files = const [];
    }
    if (files.isEmpty) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final added = <String>[];
    try {
      for (final f in files.take(room)) {
        final bytes = await f.readAsBytes();
        try {
          added.add(await ShotStore.instance.put(await compressShotAsync(bytes)));
        } on FormatException {
          _error = s.shotsInvalid(f.name);
        } on ShotQuotaExceeded {
          _error = s.shotsQuota;
          break;
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (added.isNotEmpty) widget.onChanged([...widget.shots, ...added]);
  }

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: hz.textMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Kennung(s.shotsLabel),
        const SizedBox(height: HzSpace.s8),
        Wrap(
          spacing: HzSpace.s8,
          runSpacing: HzSpace.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final id in widget.shots)
              ShotThumb(id: id, onRemove: () => widget.onChanged([...widget.shots.where((x) => x != id)])),
            if (widget.shots.length < widget.max)
              OutlinedButton.icon(
                onPressed: _busy ? null : _add,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator.adaptive(strokeWidth: Lines.selection),
                      )
                    : const Icon(AppIcons.image, size: 18),
                label: Text(s.shotsAdd),
              ),
          ],
        ),
        const SizedBox(height: HzSpace.s4),
        Text(s.shotsHint(widget.max), style: muted),
        if (_error case final error?) Text(error, style: muted?.copyWith(color: hz.critical)),
      ],
    );
  }
}

/// Thumbnail of a screenshot; tapping shows it full size.
class ShotThumb extends StatelessWidget {
  const ShotThumb({super.key, required this.id, this.onRemove, this.size = 64});

  final String id;
  final VoidCallback? onRemove;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    return FutureBuilder<Uint8List?>(
      future: ShotStore.instance.read(id),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        final image = Container(
          width: size * 1.4,
          height: size,
          decoration: BoxDecoration(
            borderRadius: Radii.tile,
            border: Border.all(color: hz.line, width: Lines.hairline),
            color: hz.sunken,
          ),
          clipBehavior: Clip.antiAlias,
          child: bytes == null ? null : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Semantics(
              button: true,
              label: s.shotsOpen,
              child: InkWell(
                borderRadius: Radii.tile,
                onTap: bytes == null ? null : () => showShot(context, bytes),
                child: image,
              ),
            ),
            if (onRemove != null)
              PositionedDirectional(
                top: -10,
                end: -10,
                child: IconButton.filledTonal(
                  tooltip: s.shotsRemove,
                  iconSize: 14,
                  visualDensity: VisualDensity.compact,
                  onPressed: onRemove,
                  icon: const Icon(AppIcons.close),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Screenshot at full size, with zoom.
Future<void> showShot(BuildContext context, Uint8List bytes) => showDialog<void>(
  context: context,
  builder: (dialog) => Dialog(
    insetPadding: const EdgeInsets.all(HzSpace.s16),
    clipBehavior: Clip.antiAlias,
    child: Stack(
      children: [
        InteractiveViewer(maxScale: 5, child: Image.memory(bytes)),
        PositionedDirectional(
          top: HzSpace.s8,
          end: HzSpace.s8,
          child: IconButton.filledTonal(
            tooltip: s.commonClose,
            onPressed: () => Navigator.pop(dialog),
            icon: const Icon(AppIcons.close),
          ),
        ),
      ],
    ),
  ),
);
