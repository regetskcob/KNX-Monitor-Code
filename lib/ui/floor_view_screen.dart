import 'dart:async';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/floor_view.dart';
import '../model/plan.dart';
import '../model/site_photos.dart';
import '../model/telegram_log.dart';
import '../platform/addon.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'group_address_picker.dart';
import 'plan_screen.dart';
import 'telegram_row.dart';

/// Width floor plan images are decoded at, whatever their size on disk.
const floorImageCacheWidth = 2048;

IconData floorPointIcon(FloorPointKind k) => switch (k) {
  FloorPointKind.light => AppIcons.light,
  FloorPointKind.button => AppIcons.touch,
  FloorPointKind.blind => AppIcons.blinds,
  FloorPointKind.socket => AppIcons.energy,
  FloorPointKind.heating => AppIcons.thermostat,
  FloorPointKind.sensor => AppIcons.sensors,
  FloorPointKind.contact => AppIcons.window,
  FloorPointKind.other => AppIcons.objects,
};

String floorPointKindName(FloorPointKind k) => switch (k) {
  FloorPointKind.light => s.floorKindLight,
  FloorPointKind.button => s.floorKindButton,
  FloorPointKind.blind => s.floorKindBlind,
  FloorPointKind.socket => s.floorKindSocket,
  FloorPointKind.heating => s.floorKindHeating,
  FloorPointKind.sensor => s.floorKindSensor,
  FloorPointKind.contact => s.floorKindContact,
  FloorPointKind.other => s.floorKindOther,
};

String floorStateName(PointState state) => switch (state) {
  PointState.active => s.floorStateActive,
  PointState.heard => s.floorStateHeard,
  PointState.unheard => s.floorStateUnheard,
  PointState.silent => s.floorStateSilent,
  PointState.unlinked => s.floorStateUnlinked,
};

String _when(DateTime t, DateTime now) =>
    now.difference(t).inHours < 20 ? formatTime(t, millis: false) : '${formatDate(t)} ${formatTime(t, seconds: false)}';

/// One level of a [FloorView]: image or room outlines, on top the points. The
/// state of a point shows in its shape as well as its colour, and every point
/// is a button with a spoken label.
class FloorCanvas extends StatelessWidget {
  const FloorCanvas({
    super.key,
    required this.floor,
    required this.stateOf,
    this.image,
    this.selected,
    this.onPoint,
    this.onPlan,
    this.onMove,
    this.onMoveEnd,
  });

  final FloorLevel floor;
  final Uint8List? image;
  final PointState Function(FloorPoint point) stateOf;
  final String? selected;
  final ValueChanged<FloorPoint>? onPoint;

  /// Tap on a free spot, in shares of the plan.
  final void Function(double x, double y)? onPlan;

  /// A point is dragged by this share of the plan; [onMoveEnd] when the finger lifts.
  final void Function(FloorPoint point, double dx, double dy)? onMove;
  final ValueChanged<FloorPoint>? onMoveEnd;

  static const _hit = 44.0;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    return AspectRatio(
      aspectRatio: floor.aspect,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final h = box.maxHeight;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: onPlan == null ? null : (d) => onPlan!(d.localPosition.dx / w, d.localPosition.dy / h),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: hz.sunken,
                      border: Border.all(color: hz.line, width: Lines.hairline),
                    ),
                  ),
                ),
                if (image != null)
                  Positioned.fill(
                    child: ExcludeSemantics(
                      child: Image.memory(
                        image!,
                        fit: BoxFit.fill,
                        gaplessPlayback: true,
                        // Never decode larger than needed: an image from elsewhere can have many megapixels.
                        cacheWidth: floorImageCacheWidth,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: CustomPaint(
                      painter: _RoomPainter(
                        floor.rooms,
                        line: hz.lineStrong,
                        style: (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(
                          color: hz.textMuted,
                        ),
                        labels: image == null,
                      ),
                    ),
                  ),
                ),
                for (final p in floor.points)
                  Positioned(
                    left: p.x * w - _hit / 2,
                    top: p.y * h - _hit / 2,
                    width: _hit,
                    height: _hit,
                    child: _PointDot(
                      point: p,
                      state: stateOf(p),
                      selected: p.id == selected,
                      onTap: onPoint == null ? null : () => onPoint!(p),
                      onDrag: onMove == null ? null : (delta) => onMove!(p, delta.dx / w, delta.dy / h),
                      onDragEnd: onMoveEnd == null ? null : () => onMoveEnd!(p),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RoomPainter extends CustomPainter {
  const _RoomPainter(this.rooms, {required this.line, required this.style, required this.labels});

  final List<FloorArea> rooms;
  final Color line;
  final TextStyle style;
  final bool labels;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = line;
    for (final r in rooms) {
      final rect = Rect.fromLTWH(r.x * size.width, r.y * size.height, r.w * size.width, r.h * size.height);
      canvas.drawRect(rect, stroke);
      if (!labels || r.name.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(text: r.name, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: (rect.width - 12).clamp(0, double.infinity));
      painter.paint(canvas, rect.topLeft + const Offset(6, 4));
    }
  }

  @override
  bool shouldRepaint(_RoomPainter old) =>
      old.rooms != rooms || old.line != line || old.style != style || old.labels != labels;
}

class _PointDot extends StatelessWidget {
  const _PointDot({
    required this.point,
    required this.state,
    required this.selected,
    this.onTap,
    this.onDrag,
    this.onDragEnd,
  });

  final FloorPoint point;
  final PointState state;
  final bool selected;
  final VoidCallback? onTap;
  final ValueChanged<Offset>? onDrag;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final icon = floorPointIcon(point.kind);
    Widget disc({
      required Color fill,
      required Color iconColor,
      Color? border,
      double borderWidth = 1.5,
      double size = 26,
      BoxShape shape = BoxShape.circle,
    }) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: shape,
        color: fill,
        border: border == null ? null : Border.all(color: border, width: borderWidth),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.6, color: iconColor),
    );
    // A shape per state, never colour alone, each with the symbol of the kind: halo around a
    // filled disc, filled disc, hollow ring, ring with a warning sign, square. Symbols instead of
    // letters, so large text does not squeeze them.
    final Widget mark = switch (state) {
      PointState.active => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hz.accentTint,
          border: Border.all(color: hz.accent, width: 2),
        ),
        alignment: Alignment.center,
        child: disc(fill: hz.accent, iconColor: hz.onAccent),
      ),
      PointState.heard => disc(fill: hz.textMuted, iconColor: hz.surface),
      PointState.unheard => disc(fill: hz.surface, border: hz.lineStrong, iconColor: hz.textMuted),
      PointState.silent => SizedBox(
        width: 34,
        height: 34,
        child: Stack(
          alignment: Alignment.center,
          children: [
            disc(fill: hz.warningTint, border: hz.warning, borderWidth: 2, iconColor: hz.warning),
            Positioned(
              right: 0,
              top: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, color: hz.surface),
                child: Icon(HorizontStatus.warning.icon, size: 14, color: hz.warning),
              ),
            ),
          ],
        ),
      ),
      PointState.unlinked => disc(
        fill: hz.surface,
        border: hz.line,
        iconColor: hz.textFaint,
        size: 22,
        shape: BoxShape.rectangle,
      ),
    };
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: [point.name, if (point.room.isNotEmpty) point.room, floorStateName(state)].join(', '),
      child: Tooltip(
        message: point.name,
        excludeFromSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onPanUpdate: onDrag == null ? null : (d) => onDrag!(d.delta),
          onPanEnd: onDragEnd == null ? null : (_) => onDragEnd!(),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: selected ? Border.all(color: hz.text, width: 2) : null,
            ),
            child: Center(child: mark),
          ),
        ),
      ),
    );
  }
}

/// Bus on the floor plan: telegrams make points light up, silent ones stand
/// out. Works with any floor plan drawn here; a house plan can write the same
/// file.
class FloorViewScreen extends StatefulWidget {
  const FloorViewScreen({super.key, required this.log, this.clock = DateTime.now});

  final TelegramLog log;

  /// The time "now"; replaceable in tests.
  final DateTime Function() clock;

  @override
  State<FloorViewScreen> createState() => _FloorViewScreenState();
}

class _FloorViewScreenState extends State<FloorViewScreen> {
  final _store = FloorViewStore.instance;
  final _activity = FloorActivity();
  Timer? _tick;
  String? _floorId;
  String? _selected;
  bool _editing = false;
  final _images = <String, Uint8List>{};

  @override
  void initState() {
    super.initState();
    _activity.since = widget.log.log.isEmpty ? widget.clock() : widget.log.log.first.time;
    widget.log.addListener(_onLog);
    _onLog();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(
      _store.ensureLoaded(demo: () => demoFloorView(german: s.localeName.startsWith('de'))).then((_) => _history()),
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    widget.log.removeListener(_onLog);
    unawaited(_store.save());
    super.dispose();
  }

  void _onLog() => _activity.takeLatest(widget.log.latest);

  /// With the add-on or box the server knows the history: silence over days.
  Future<void> _history() async {
    if (!Addon.available) return;
    try {
      final answer = await Addon.floorView();
      final last = answer['last'];
      if (last is Map) {
        for (final MapEntry(:key, :value) in last.entries) {
          final address = int.tryParse('$key');
          if (address != null && value is int) _activity.note(address, DateTime.fromMillisecondsSinceEpoch(value));
        }
      }
      if (answer['since'] case final int since) {
        final t = DateTime.fromMillisecondsSinceEpoch(since);
        if (t.isBefore(_activity.since ?? widget.clock())) _activity.since = t;
      }
      if (mounted) setState(() {});
    } on Object catch (e) {
      debugPrint('Busansicht: Verlauf nicht lesbar: $e');
    }
  }

  FloorLevel? get _floor {
    final floors = _store.view.floors;
    if (floors.isEmpty) return null;
    return floors.firstWhere((f) => f.id == _floorId, orElse: () => floors.first);
  }

  Uint8List? _imageOf(FloorLevel floor) {
    final file = floor.image;
    if (file == null) return null;
    final known = _images[file];
    if (known != null) return known;
    unawaited(
      _store.image(floor).then((b) {
        if (b != null && mounted) setState(() => _images[file] = b);
      }),
    );
    return null;
  }

  Future<String?> _prompt(String title, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final text = await showAdaptiveDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog.adaptive(
        title: Text(title),
        content: Material(
          type: MaterialType.transparency,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLength: floorViewMaxText,
            textCapitalization: TextCapitalization.sentences,
          ),
        ),
        actions: [
          horizontDialogAction(dialog, label: s.commonCancel, onPressed: () => Navigator.pop(dialog)),
          horizontDialogAction(
            dialog,
            label: s.commonSave,
            primary: true,
            onPressed: () => Navigator.pop(dialog, controller.text.trim()),
          ),
        ],
      ),
    );
    disposeAfterDialog(controller);
    return text;
  }

  Future<void> _addFloor() async {
    // As in the house plan: the first level is free.
    if (_store.view.floors.isNotEmpty && !await unlock(context, Feature.homePlan)) return;
    if (!mounted) return;
    final name = await _prompt(s.floorLevelName, initial: s.floorLevelDefault);
    if (name == null || name.isEmpty) return;
    final view = _store.view;
    final floor = FloorLevel(id: view.newId('f'), name: name);
    view.floors.add(floor);
    _store.changed();
    setState(() {
      _floorId = floor.id;
      _editing = true;
    });
  }

  Future<void> _pickImage(FloorLevel floor) async {
    final messenger = ScaffoldMessenger.of(context);
    final file = await FilePicker.pickFile(type: FileType.image);
    final bytes = await file?.readAsBytes();
    if (bytes == null) return;
    try {
      final jpeg = await compute(compressSitePhoto, bytes);
      final codec = await ui.instantiateImageCodec(jpeg);
      final frame = await codec.getNextFrame();
      final aspect = frame.image.width / frame.image.height;
      frame.image.dispose();
      codec.dispose();
      await _store.setImage(floor, jpeg, aspect);
      _images.remove(floor.image);
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(s.floorImageUnreadable)));
    }
  }

  Future<void> _editPoint(FloorLevel floor, FloorPoint point, {bool isNew = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    final delete = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PointSheet(point: point, isNew: isNew),
    );
    // Changes apply as they are made. A new point that got neither a name nor an address was a
    // slip of the finger and goes; a deleted one can be brought back.
    final empty = point.name.isEmpty && point.addresses.isEmpty;
    final index = floor.points.indexOf(point);
    if (index >= 0 && (delete == true || (isNew && empty))) {
      floor.points.removeAt(index);
      if (delete == true && !empty) {
        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(s.floorPointDeleted),
              action: SnackBarAction(
                label: s.commonUndo,
                onPressed: () {
                  if (!_store.view.floors.contains(floor) || floor.points.contains(point)) return;
                  floor.points.insert(index.clamp(0, floor.points.length), point);
                  _store.changed();
                },
              ),
            ),
          );
      }
    }
    _store.changed();
  }

  Future<void> _deleteFloor(FloorLevel floor) async {
    final ok = await showAdaptiveDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog.adaptive(
        title: Text(s.floorDeleteLevelAsk(floor.name)),
        content: Text(s.floorDeleteLevelBody(floor.points.length)),
        actions: [
          horizontDialogAction(dialog, label: s.commonCancel, onPressed: () => Navigator.pop(dialog, false)),
          horizontDialogAction(
            dialog,
            label: s.commonDelete,
            destructive: true,
            onPressed: () => Navigator.pop(dialog, true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _images.remove(floor.image);
    await _store.removeFloor(floor);
    if (mounted) setState(() => _selected = null);
  }

  void _tapPlan(FloorLevel floor, double x, double y) {
    if (!_editing) return setState(() => _selected = null);
    if (floor.points.length >= floorViewMaxPoints) return;
    final point = FloorPoint(id: _store.view.newId('p'), name: '', x: x.clamp(0.0, 1.0), y: y.clamp(0.0, 1.0));
    floor.points.add(point);
    unawaited(_editPoint(floor, point, isNew: true));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _store,
    builder: (context, _) {
      final view = _store.view;
      final floor = _floor;
      final fromPlan = view.source == FloorView.sourceHomePlan;
      final canEdit = !fromPlan && !_store.tooNew;
      return Scaffold(
        appBar: AppBar(
          title: BarTitle(s.floorTitle),
          actions: [
            if (canEdit && floor != null)
              TextButton(
                onPressed: () => setState(() => _editing = !_editing),
                child: Text(_editing ? s.floorEditDone : s.floorEdit),
              ),
          ],
        ),
        body: !_store.loaded
            ? const Center(child: CircularProgressIndicator())
            : _store.tooNew
            ? Padding(padding: Gap.page, child: Text(s.floorTooNew))
            : floor == null
            ? _empty()
            : LayoutBuilder(
                builder: (context, box) {
                  final plan = _planColumn(view, floor, fromPlan);
                  final list = _pointList(floor);
                  if (box.maxWidth >= Breakpoints.expanded) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ListView(padding: Gap.page, children: plan),
                        ),
                        SizedBox(
                          width: 360,
                          child: ListView(padding: Gap.page, children: list),
                        ),
                      ],
                    );
                  }
                  return ListView(
                    padding: Gap.page,
                    children: [
                      ...plan,
                      const SizedBox(height: Gap.section),
                      ...list,
                    ],
                  );
                },
              ),
      );
    },
  );

  Widget _empty() => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Widths.reading),
      child: ListView(
        padding: Gap.page,
        children: [
          Text(s.floorEmptyTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Gap.item),
          Text(s.floorEmptyBody),
          const SizedBox(height: Gap.section),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _addFloor,
              icon: const Icon(AppIcons.add),
              label: Text(s.floorAddLevel),
            ),
          ),
        ],
      ),
    ),
  );

  List<Widget> _planColumn(FloorView view, FloorLevel floor, bool fromPlan) {
    final now = widget.clock();
    return [
      Wrap(
        spacing: HzSpace.s4,
        runSpacing: HzSpace.s4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final f in view.floors)
            ChoiceChip(
              label: Text(f.name),
              selected: f == floor,
              onSelected: (_) => setState(() {
                _floorId = f.id;
                _selected = null;
              }),
            ),
          if (_editing) ...[
            ActionChip(avatar: const Icon(AppIcons.add, size: 18), label: Text(s.floorAddLevel), onPressed: _addFloor),
            ActionChip(
              avatar: const Icon(AppIcons.image, size: 18),
              label: Text(s.floorPickImage),
              onPressed: () => _pickImage(floor),
            ),
          ],
        ],
      ),
      const SizedBox(height: Gap.inner),
      if (_editing) ...[
        Text(s.floorEditHint, style: TextStyle(color: context.hz.textMuted)),
        // Apart from the chips above and in the colour of deleting: it removes points and image.
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: context.hz.critical),
            onPressed: () => unawaited(_deleteFloor(floor)),
            icon: const Icon(AppIcons.delete, size: 18),
            label: Text(s.floorDeleteLevel),
          ),
        ),
      ],
      if (fromPlan)
        Padding(
          padding: const EdgeInsets.only(bottom: Gap.item),
          child: Text(s.floorFromPlan, style: TextStyle(color: context.hz.textMuted)),
        ),
      FloorCanvas(
        floor: floor,
        image: _imageOf(floor),
        selected: _selected,
        stateOf: (p) => _activity.stateOf(p, now),
        onPoint: (p) => _editing ? unawaited(_editPoint(floor, p)) : setState(() => _selected = p.id),
        onPlan: (x, y) => _tapPlan(floor, x, y),
        onMove: !_editing
            ? null
            : (p, dx, dy) => setState(() {
                p
                  ..x = (p.x + dx).clamp(0.0, 1.0)
                  ..y = (p.y + dy).clamp(0.0, 1.0);
              }),
        onMoveEnd: !_editing ? null : (_) => _store.changed(),
      ),
      _detail(floor, now),
      const SizedBox(height: Gap.item),
      // Legend: the same shapes as on the plan, with words; two tidy columns on a phone.
      LayoutBuilder(
        builder: (context, box) {
          final column = box.maxWidth < 560 ? (box.maxWidth - HzSpace.s8) / 2 : null;
          return Wrap(
            spacing: column == null ? HzSpace.s16 : HzSpace.s8,
            runSpacing: HzSpace.s4,
            children: [
              for (final state in PointState.values)
                SizedBox(
                  width: column,
                  child: Row(
                    mainAxisSize: column == null ? MainAxisSize.min : MainAxisSize.max,
                    children: [
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: ExcludeSemantics(
                          child: _PointDot(
                            point: FloorPoint(id: '', name: '', x: 0, y: 0),
                            state: state,
                            selected: false,
                          ),
                        ),
                      ),
                      Flexible(child: Text(floorStateName(state), style: Theme.of(context).textTheme.bodySmall)),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ];
  }

  /// The picked point in words, right under the plan: on a phone the list is out of sight.
  Widget _detail(FloorLevel floor, DateTime now) {
    final p = floor.points.where((p) => p.id == _selected).firstOrNull;
    if (p == null) return const SizedBox.shrink();
    final hz = context.hz;
    final theme = Theme.of(context);
    final last = _activity.lastOf(p);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: const ValueKey('floor-detail'),
        margin: const EdgeInsets.only(top: Gap.item),
        padding: const EdgeInsets.all(HzSpace.s12),
        decoration: BoxDecoration(color: hz.accentTint, borderRadius: Radii.box),
        child: Row(
          spacing: HzSpace.s8,
          children: [
            ExcludeSemantics(child: Icon(floorPointIcon(p.kind), size: 20, color: hz.text)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name.isEmpty ? floorPointKindName(p.kind) : p.name, style: theme.textTheme.titleSmall),
                  Text(
                    [
                      if (p.room.isNotEmpty) p.room,
                      floorStateName(_activity.stateOf(p, now)),
                      if (last != null) s.floorDetailLast(_when(last, now)),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (p.addresses.isNotEmpty)
                    Text(
                      p.addresses.map(formatGroup).join(', '),
                      style: context.figures(theme.textTheme.bodySmall).copyWith(color: hz.textMuted),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _pointList(FloorLevel floor) {
    final now = widget.clock();
    final hz = context.hz;
    final theme = Theme.of(context);
    final states = {for (final p in floor.points) p: _activity.stateOf(p, now)};
    final silent = [
      for (final p in floor.points)
        if (states[p] == PointState.silent) p,
    ];
    final unheard = [
      for (final p in floor.points)
        if (states[p] == PointState.unheard) p,
    ];
    final heard = [
      for (final p in floor.points)
        if (states[p] == PointState.active || states[p] == PointState.heard) p,
    ]..sort((a, b) => _activity.lastOf(b)!.compareTo(_activity.lastOf(a)!));
    final unlinked = [
      for (final p in floor.points)
        if (states[p] == PointState.unlinked) p,
    ];
    final since = _activity.since;
    Widget row(FloorPoint p, String detail) => InkWell(
      onTap: () => _editing ? unawaited(_editPoint(floor, p)) : setState(() => _selected = p.id),
      child: Container(
        color: p.id == _selected ? hz.accentTint : null,
        padding: const EdgeInsets.symmetric(vertical: HzSpace.s8, horizontal: HzSpace.s8),
        child: Row(
          spacing: HzSpace.s8,
          children: [
            ExcludeSemantics(child: Icon(floorPointIcon(p.kind), size: 20, color: hz.textMuted)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name.isEmpty ? floorPointKindName(p.kind) : p.name),
                  Text(
                    [if (p.room.isNotEmpty) p.room, p.addresses.map(formatGroup).join(', ')].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                  ),
                ],
              ),
            ),
            Text(detail, style: context.figures(theme.textTheme.bodySmall).copyWith(color: hz.textMuted)),
          ],
        ),
      ),
    );

    Widget card(String title, List<FloorPoint> points, String Function(FloorPoint) detail, {String? note}) => Padding(
      padding: const EdgeInsets.only(bottom: Gap.inner),
      child: SectionCard(
        title: title,
        count: points.length,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (note != null) Text(note, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
            for (final p in points) row(p, detail(p)),
          ],
        ),
      ),
    );

    return [
      if (floor.points.isEmpty) Text(s.floorNoPoints, style: TextStyle(color: hz.textMuted)),
      if (silent.isNotEmpty)
        card(
          s.floorSilentTitle,
          silent,
          (_) => '—',
          note: since == null ? null : s.floorSilentSince(_when(since, now)),
        ),
      if (heard.isNotEmpty) card(s.floorHeardTitle, heard, (p) => _when(_activity.lastOf(p)!, now)),
      if (unheard.isNotEmpty)
        card(
          s.floorUnheardTitle,
          unheard,
          (_) => '',
          note: since == null ? null : s.floorUnheardSince(_when(since, now)),
        ),
      if (unlinked.isNotEmpty) card(s.floorUnlinkedTitle, unlinked, (_) => ''),
    ];
  }
}

/// Name, kind and group addresses of a point. Changes apply as they are made; pops `true` to
/// delete the point.
class _PointSheet extends StatefulWidget {
  const _PointSheet({required this.point, required this.isNew});

  final FloorPoint point;
  final bool isNew;

  @override
  State<_PointSheet> createState() => _PointSheetState();
}

class _PointSheetState extends State<_PointSheet> {
  late final _name = TextEditingController(text: widget.point.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.point;
    final catalog = CatalogStore.instance.catalog;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, MediaQuery.viewInsetsOf(context).bottom + Gap.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Gap.inner,
          children: [
            Text(s.floorPointTitle, style: Theme.of(context).textTheme.titleLarge),
            TextField(
              controller: _name,
              maxLength: floorViewMaxText,
              decoration: InputDecoration(labelText: s.floorPointName),
              textCapitalization: TextCapitalization.sentences,
              onChanged: (v) => p.name = v.trim(),
            ),
            Wrap(
              spacing: HzSpace.s4,
              runSpacing: HzSpace.s4,
              children: [
                for (final k in FloorPointKind.values)
                  ChoiceChip(
                    label: Text(floorPointKindName(k)),
                    selected: p.kind == k,
                    onSelected: (_) => setState(() => p.kind = k),
                  ),
              ],
            ),
            for (final a in p.addresses)
              Text([formatGroup(a), ?catalog[a]?.name].join(' · '), style: TextStyle(color: context.hz.textMuted)),
            OutlinedButton(
              onPressed: () async {
                final picked = await pickGroupAddresses(
                  context,
                  title: p.name.isEmpty ? floorPointKindName(p.kind) : p.name,
                  initial: p.addresses,
                  max: floorViewMaxAddresses,
                );
                if (picked == null || !mounted) return;
                setState(() {
                  p.addresses
                    ..clear()
                    ..addAll(picked);
                  if (p.name.isEmpty && picked.isNotEmpty) {
                    p.name = catalog[picked.first]?.name ?? '';
                    _name.text = p.name;
                  }
                });
              },
              child: Text(s.floorPointAddresses),
            ),
            Row(
              spacing: HzSpace.s8,
              children: [
                if (!widget.isNew)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: context.hz.critical),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(s.commonDelete),
                  ),
                const Spacer(),
                FilledButton(onPressed: () => Navigator.pop(context, false), child: Text(s.floorEditDone)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
