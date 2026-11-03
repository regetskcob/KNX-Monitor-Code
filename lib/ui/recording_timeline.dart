import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/annotation.dart';
import '../model/recording.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'annotation_editor.dart';
import 'annotations.dart';
import 'telegram_row.dart';

/// Timeline of a recording: one row per group address, one tick per telegram.
/// Dragging pans, mouse wheel with Ctrl/⌘ or pinch zooms. The pointer over a
/// telegram shows it, tapping comments on it (or on the point in time);
/// comments appear as flags above. With [player] the playhead moves along, and
/// a tap on the time axis jumps there.
class RecordingTimelineScreen extends StatefulWidget {
  const RecordingTimelineScreen({super.key, required this.recording, this.player, this.focus});

  final Recording recording;
  final RecordingPlayer? player;

  /// Point in time visible at the start (e.g. a comment from the finding).
  final DateTime? focus;

  @override
  State<RecordingTimelineScreen> createState() => _RecordingTimelineScreenState();
}

class _RecordingTimelineScreenState extends State<RecordingTimelineScreen> {
  Recording get _r => widget.recording;

  /// Comments within the recording's time span: those of your own installation
  /// or, for a foreign diagnostics package, those of the recording ([AnnotationScope]).
  List<Annotation> get _annotations => AnnotationScope.inRange(_r.started, _r.ended);

  @override
  void initState() {
    super.initState();
    AnnotationScope.open(_r);
    AnnotationStore.instance.addListener(_changed);
    RecordingStore.instance.addListener(_changed);
  }

  @override
  void dispose() {
    AnnotationStore.instance.removeListener(_changed);
    RecordingStore.instance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _annotate({required DateTime time, Telegram? telegram}) =>
      telegram == null ? annotateTime(context, time) : annotateTelegram(context, telegram);

  Future<void> _open(Annotation a) => editAnnotation(context, a);

  final _view = GlobalKey<_TimelineViewState>();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Kennung(_r.name), Text(s.timelineTitle)],
        ),
      ),
      body: _r.telegrams.isEmpty
          ? Center(child: Text(s.timelineEmpty))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, HzSpace.s8),
                  child: Text(s.timelineHint, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
                ),
                Expanded(
                  flex: 3,
                  child: TimelineView(
                    key: _view,
                    recording: _r,
                    annotations: _annotations,
                    player: widget.player,
                    focus: widget.focus,
                    onAnnotate: _annotate,
                    onOpen: _open,
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  flex: 2,
                  child: _annotations.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(Gap.gutter),
                            child: Text(s.timelineNoAnnotations, textAlign: TextAlign.center),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
                          children: [
                            for (final a in _annotations)
                              AnnotationTile(
                                annotation: a,
                                onTap: () => _view.currentState?.reveal(a),
                                onEdit: () => _open(a),
                              ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}

/// "21:40:38.450 · 1.1.30 → 1/1/3 Licht Küche · Ein"
String describeTelegram(Telegram t) {
  final store = CatalogStore.instance;
  final name = store.catalog[t.destination]?.name;
  return [
    formatTime(t.time),
    '${formatIndividual(t.source)} → ${formatGroup(t.destination)}${name == null || name.isEmpty ? '' : ' $name'}',
    store.value(t),
  ].join(metaSeparator);
}

/// What a comment is attached to, in one line.
String describeAnnotation(Annotation a) {
  final catalog = CatalogStore.instance.catalog;
  if (a.telegram case final ref?) {
    final name = catalog[ref.destination]?.name;
    return [
      formatTime(ref.time),
      '${formatIndividual(ref.source)} → ${formatGroup(ref.destination)}${name == null || name.isEmpty ? '' : ' $name'}',
    ].join(metaSeparator);
  }
  if (a.chart case final chart?) {
    final names = [
      for (final g in chart.groups.take(3)) catalog[g]?.name.isNotEmpty == true ? catalog[g]!.name : formatGroup(g),
    ];
    return [formatTime(a.time), s.annotationAboutChart(names.join(', '))].join(metaSeparator);
  }
  return s.annotationAboutTime(formatTime(a.time));
}

/// A comment in lists (timeline, finding): time and reference, text, images.
class AnnotationTile extends StatelessWidget {
  const AnnotationTile({super.key, required this.annotation, this.onTap, this.onEdit});

  final Annotation annotation;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final theme = Theme.of(context);
    final a = annotation;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.gutter, vertical: HzSpace.s8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(AppIcons.annotationSet, size: 18, color: hz.warning),
            ),
            const SizedBox(width: HzSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    describeAnnotation(a),
                    style: context.mono(theme.textTheme.bodySmall).copyWith(color: hz.textMuted),
                  ),
                  if (a.note.isNotEmpty) ...[const SizedBox(height: HzSpace.s4), Text(a.note)],
                  if (a.shots.isNotEmpty) ...[
                    const SizedBox(height: HzSpace.s8),
                    Wrap(
                      spacing: HzSpace.s8,
                      runSpacing: HzSpace.s8,
                      children: [for (final id in a.shots) ShotThumb(id: id, size: 48)],
                    ),
                  ],
                ],
              ),
            ),
            if (onEdit != null)
              IconButton(tooltip: s.annotationEditTitle, onPressed: onEdit, icon: const Icon(AppIcons.edit)),
          ],
        ),
      ),
    );
  }
}

/// The drawn timeline with its own panning and zooming.
class TimelineView extends StatefulWidget {
  const TimelineView({
    super.key,
    required this.recording,
    required this.annotations,
    this.player,
    this.focus,
    this.onAnnotate,
    this.onOpen,
  });

  final Recording recording;
  final List<Annotation> annotations;
  final RecordingPlayer? player;
  final DateTime? focus;

  /// Sets a comment: on a telegram or at a point in time.
  final void Function({required DateTime time, Telegram? telegram})? onAnnotate;
  final ValueChanged<Annotation>? onOpen;

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

/// A tick of the timeline: row and telegram.
typedef _Hit = ({int lane, Telegram telegram});

class _TimelineViewState extends State<TimelineView> {
  static const _labelWidth = 190.0;
  static const _laneHeight = 34.0;
  static const _flagBand = 28.0;
  static const _axisHeight = 26.0;
  static const _minPxPerSec = 0.02;
  static const _maxPxPerSec = 2000.0;

  /// Left edge of the view in seconds from the start of the recording.
  double _offset = 0;
  double _pxPerSec = 20;
  double? _fitted;
  _Hit? _hover;
  Offset? _hoverAt;
  double _vScroll = 0;
  double _scaleStart = 1;

  Recording get _r => widget.recording;

  /// Rows: addresses with comments first (otherwise commented telegrams would
  /// often be far down out of sight), then by first appearance.
  List<int> get _lanes {
    final key = {for (final a in widget.annotations) ?a.telegram?.destination};
    if (_lanesFor == null || !setEquals(_lanesFor, key)) {
      _lanesFor = key;
      final order = _laneOrder(_r.telegrams);
      _flagged = order.where(key.contains).length;
      _laneCache = [...order.where(key.contains), ...order.where((ga) => !key.contains(ga))];
    }
    return _laneCache;
  }

  Set<int>? _lanesFor;

  /// Rows at the top with commented telegrams (only addresses of this recording).
  int _flagged = 0;
  List<int> _laneCache = const [];

  late final Map<int, List<Telegram>> _byLane = {
    for (final ga in _laneOrder(_r.telegrams))
      ga: [
        for (final t in _r.telegrams)
          if (t.destination == ga) t,
      ],
  };

  double get _duration => math.max(_r.duration.inMicroseconds / 1e6, 1);

  static List<int> _laneOrder(List<Telegram> telegrams) {
    final seen = <int>{};
    return [
      for (final t in telegrams)
        if (seen.add(t.destination)) t.destination,
    ];
  }

  double _sec(DateTime t) => t.difference(_r.started).inMicroseconds / 1e6;
  DateTime _timeAt(double sec) => _r.started.add(Duration(microseconds: (sec * 1e6).round()));

  @override
  void initState() {
    super.initState();
    widget.player?.addListener(_onPlayer);
  }

  @override
  void dispose() {
    widget.player?.removeListener(_onPlayer);
    super.dispose();
  }

  void _onPlayer() => setState(() {});

  /// Pans the view so that [a] is in the center, also vertically to the row of
  /// its telegram.
  void reveal(Annotation a) {
    final size = context.size ?? const Size(800, 400);
    final width = size.width - _labelWidth;
    final lane = a.telegram == null ? -1 : _lanes.indexOf(a.telegram!.destination);
    setState(() {
      _offset = _clampOffset(_sec(a.time) - width / _pxPerSec / 2, width);
      if (lane >= 0) {
        final visible = size.height - _flagBand - _axisHeight;
        _vScroll = math.max(0.0, lane * _laneHeight - visible / 2 + _laneHeight / 2);
      }
    });
  }

  double _clampOffset(double offset, double width) {
    final max = math.max(0.0, _duration - width / _pxPerSec);
    return offset.clamp(0.0, max);
  }

  void _zoom(double factor, double anchorX, double width) {
    final anchorSec = _offset + anchorX / _pxPerSec;
    final next = (_pxPerSec * factor).clamp(_minPxPerSec, _maxPxPerSec);
    setState(() {
      _pxPerSec = next;
      _offset = _clampOffset(anchorSec - anchorX / next, width);
    });
  }

  _Hit? _hitAt(Offset local, double width) {
    final lane = ((local.dy - _flagBand + _vScroll) / _laneHeight).floor();
    if (local.dy < _flagBand || lane < 0 || lane >= _lanes.length) return null;
    final sec = _offset + local.dx / _pxPerSec;
    final list = _byLane[_lanes[lane]]!;
    // Nearest telegram in the row, at most 6 pixels away.
    var lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_sec(list[mid].time) < sec) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    _Hit? best;
    var bestDx = 6.0;
    for (final i in [lo - 1, lo]) {
      if (i < 0 || i >= list.length) continue;
      final dx = ((_sec(list[i].time) - sec) * _pxPerSec).abs();
      if (dx <= bestDx) {
        bestDx = dx;
        best = (lane: lane, telegram: list[i]);
      }
    }
    return best;
  }

  Annotation? _flagAt(Offset local) {
    if (local.dy > _flagBand) return null;
    for (final a in widget.annotations) {
      final x = (_sec(a.time) - _offset) * _pxPerSec;
      if ((local.dx - x).abs() <= 10) return a;
    }
    return null;
  }

  void _tap(Offset local, double width, double height) {
    if (_flagAt(local) case final a?) {
      widget.onOpen?.call(a);
      return;
    }
    final time = _timeAt(_offset + local.dx / _pxPerSec);
    // Zeitachse unten: Abspielkopf dorthin.
    if (local.dy > height - _axisHeight) {
      widget.player?.seek(time.difference(_r.started));
      return;
    }
    final hit = _hitAt(local, width);
    widget.onAnnotate?.call(time: time, telegram: hit?.telegram);
  }

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final theme = Theme.of(context);
    final catalog = CatalogStore.instance.catalog;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - _labelWidth;
        final height = constraints.maxHeight;
        final visibleLanes = height - _flagBand - _axisHeight;
        final maxV = math.max(0.0, _lanes.length * _laneHeight - visibleLanes);
        _vScroll = _vScroll.clamp(0.0, maxV);
        // On the first build show the whole recording, at most 20 px per second.
        if (_fitted == null && width > 0) {
          _fitted = math.min(20.0, width / _duration).clamp(_minPxPerSec, _maxPxPerSec);
          _pxPerSec = _fitted!;
          if (widget.focus case final focus?) {
            _pxPerSec = math.max(_pxPerSec, 20);
            _offset = _clampOffset(_sec(focus) - width / _pxPerSec / 2, width);
          }
        }
        final label = theme.textTheme.bodySmall;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Row labels: group address and name.
            // Only in the row area, not over flags or the time axis.
            Padding(
              padding: const EdgeInsets.only(top: _flagBand, bottom: _axisHeight),
              child: SizedBox(
                width: _labelWidth,
                child: ClipRect(
                  child: Stack(
                    children: [
                      for (final (i, ga) in _lanes.indexed)
                        if ((i + 1) * _laneHeight > _vScroll && i * _laneHeight < _vScroll + visibleLanes)
                          Positioned(
                            top: i * _laneHeight - _vScroll,
                            left: Gap.gutter,
                            right: HzSpace.s8,
                            height: _laneHeight,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(formatGroup(ga), style: context.mono(label).copyWith(fontWeight: FontWeight.w600)),
                                if (catalog[ga]?.name case final name? when name.isNotEmpty)
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: label?.copyWith(color: hz.textMuted),
                                  ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Semantics(
                label: s.timelineSemantics(_r.telegrams.length, widget.annotations.length),
                child: Listener(
                  onPointerSignal: (e) {
                    if (e is! PointerScrollEvent) return;
                    final keys = HardwareKeyboard.instance;
                    if (keys.isControlPressed || keys.isMetaPressed) {
                      _zoom(math.pow(1.0015, -e.scrollDelta.dy).toDouble(), e.localPosition.dx, width);
                    } else if (keys.isShiftPressed || e.scrollDelta.dx.abs() > e.scrollDelta.dy.abs()) {
                      final d = e.scrollDelta.dx.abs() > 0 ? e.scrollDelta.dx : e.scrollDelta.dy;
                      setState(() => _offset = _clampOffset(_offset + d / _pxPerSec, width));
                    } else {
                      setState(() => _vScroll = (_vScroll + e.scrollDelta.dy).clamp(0.0, maxV));
                    }
                  },
                  child: MouseRegion(
                    cursor: _hover == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
                    onHover: (e) => setState(() {
                      _hover = _hitAt(e.localPosition, width);
                      _hoverAt = e.localPosition;
                    }),
                    onExit: (_) => setState(() => _hover = null),
                    child: GestureDetector(
                      onScaleStart: (_) => _scaleStart = _pxPerSec,
                      onScaleUpdate: (d) {
                        if (d.pointerCount > 1) {
                          final next = (_scaleStart * d.horizontalScale).clamp(_minPxPerSec, _maxPxPerSec);
                          _zoom(next / _pxPerSec, d.localFocalPoint.dx, width);
                        } else {
                          setState(() {
                            _offset = _clampOffset(_offset - d.focalPointDelta.dx / _pxPerSec, width);
                            _vScroll = (_vScroll - d.focalPointDelta.dy).clamp(0.0, maxV);
                          });
                        }
                      },
                      onTapUp: (d) => _tap(d.localPosition, width, height),
                      child: Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _TimelinePainter(
                                recording: _r,
                                annotations: widget.annotations,
                                flagged: _flagged,
                                lanes: _lanes,
                                byLane: _byLane,
                                offset: _offset,
                                pxPerSec: _pxPerSec,
                                vScroll: _vScroll,
                                hover: _hover?.telegram,
                                playhead: widget.player == null || widget.player!.position >= widget.player!.duration
                                    ? null
                                    : widget.player!.position.inMicroseconds / 1e6,
                                colors: hz,
                                label: context.mono(label).copyWith(color: hz.textFaint),
                                flagBand: _flagBand,
                                laneHeight: _laneHeight,
                                axisHeight: _axisHeight,
                              ),
                            ),
                          ),
                          if (_hover case final hit?)
                            Positioned(
                              left: math.min((_hoverAt?.dx ?? 0) + 12, math.max(0, width - 300)),
                              top: math.min((_hoverAt?.dy ?? 0) + 12, math.max(0, height - 90)),
                              child: IgnorePointer(child: _HoverCard(telegram: hit.telegram)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Details of a telegram under the pointer.
class _HoverCard extends StatelessWidget {
  const _HoverCard({required this.telegram});

  final Telegram telegram;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final theme = Theme.of(context);
    final t = telegram;
    final store = CatalogStore.instance;
    final name = store.catalog[t.destination]?.name;
    final device = store.catalog.devices[t.source]?.name;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: hz.surface,
          borderRadius: Radii.tile,
          border: Border.all(color: hz.line, width: Lines.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(HzSpace.s8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(formatTime(t.time), style: context.mono(theme.textTheme.bodySmall)),
              Text(
                '${formatIndividual(t.source)}${device == null ? '' : ' $device'}',
                style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '→ ${formatGroup(t.destination)}${name == null || name.isEmpty ? '' : ' $name'}',
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                [Palette.label(t.type), store.value(t), if (t.repeated) s.timelineRepeated].join(metaSeparator),
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.recording,
    required this.annotations,
    required this.flagged,
    required this.lanes,
    required this.byLane,
    required this.offset,
    required this.pxPerSec,
    required this.vScroll,
    required this.hover,
    required this.playhead,
    required this.colors,
    required this.label,
    required this.flagBand,
    required this.laneHeight,
    required this.axisHeight,
  });

  final Recording recording;
  final List<Annotation> annotations;

  /// Number of rows at the top with commented telegrams.
  final int flagged;
  final List<int> lanes;
  final Map<int, List<Telegram>> byLane;
  final double offset;
  final double pxPerSec;
  final double vScroll;
  final Telegram? hover;
  final double? playhead;
  final HorizontColors colors;
  final TextStyle label;
  final double flagBand;
  final double laneHeight;
  final double axisHeight;

  double _x(DateTime t) => (t.difference(recording.started).inMicroseconds / 1e6 - offset) * pxPerSec;

  /// Spacing of the time marks in seconds: at least 80 pixels.
  double _step() {
    const steps = [0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200, 14400];
    for (final st in steps) {
      if (st * pxPerSec >= 80) return st.toDouble();
    }
    return steps.last.toDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = colors.line
      ..strokeWidth = Lines.hairline;
    final lanesBottom = size.height - axisHeight;
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, flagBand, size.width, lanesBottom));
    // Zeilen.
    for (var i = 0; i <= lanes.length; i++) {
      final y = flagBand + i * laneHeight - vScroll;
      if (y < flagBand - laneHeight || y > lanesBottom) continue;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    // Telegrams as ticks, color by kind; repetitions critical.
    final visibleFrom = offset - 1;
    final visibleTo = offset + size.width / pxPerSec + 1;
    for (final (i, ga) in lanes.indexed) {
      final top = flagBand + i * laneHeight - vScroll;
      if (top + laneHeight < flagBand || top > lanesBottom) continue;
      for (final t in byLane[ga]!) {
        final sec = t.time.difference(recording.started).inMicroseconds / 1e6;
        if (sec < visibleFrom || sec > visibleTo) continue;
        final x = (sec - offset) * pxPerSec;
        final color = t.repeated || t.confirmError
            ? colors.critical
            : switch (t.type) {
                TelegramType.write => colors.info,
                TelegramType.response => colors.positive,
                TelegramType.read => colors.warning,
              };
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 2.5, top + 8, 5, laneHeight - 16),
          const Radius.circular(1.5),
        );
        canvas.drawRRect(rect, Paint()..color = color);
        if (identical(t, hover)) {
          canvas.drawRRect(
            rect.inflate(2.5),
            Paint()
              ..color = colors.accent
              ..style = PaintingStyle.stroke
              ..strokeWidth = Lines.data,
          );
        }
      }
    }
    // Divider below the addresses with comments so the sorting stays readable:
    // subtle, and it ends with the recording, not at the edge of the screen.
    if (flagged > 0 && flagged < lanes.length) {
      final y = flagBand + flagged * laneHeight - vScroll;
      final end = _x(recording.ended).clamp(0.0, size.width);
      canvas.drawLine(
        Offset(0, y),
        Offset(end, y),
        Paint()
          ..color = colors.warning.withValues(alpha: 0.4)
          ..strokeWidth = Lines.hairline,
      );
    }
    // Commented telegrams: ring in the color of the flags.
    for (final a in annotations) {
      final ref = a.telegram;
      if (ref == null) continue;
      final lane = lanes.indexOf(ref.destination);
      if (lane < 0) continue;
      final x = _x(ref.time);
      final top = flagBand + lane * laneHeight - vScroll;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x - 7, top + 4, 14, laneHeight - 8), const Radius.circular(4)),
        Paint()
          ..color = colors.warning
          ..style = PaintingStyle.stroke
          ..strokeWidth = Lines.selection,
      );
    }
    canvas.restore();
    // Comments: line through the rows and flags on top.
    final flagPaint = Paint()..color = colors.warning;
    for (final a in annotations) {
      final x = _x(a.time);
      if (x < -10 || x > size.width + 10) continue;
      canvas.drawLine(
        Offset(x, flagBand - 6),
        Offset(x, lanesBottom),
        Paint()
          ..color = colors.warning.withValues(alpha: 0.6)
          ..strokeWidth = 1.2,
      );
      canvas.drawPath(
        Path()
          ..moveTo(x, 4)
          ..lineTo(x + 12, 9)
          ..lineTo(x, 14)
          ..close(),
        flagPaint,
      );
      canvas.drawLine(Offset(x, 4), Offset(x, flagBand - 6), flagPaint..strokeWidth = Lines.data);
    }
    // Zeitachse.
    canvas.drawLine(Offset(0, lanesBottom), Offset(size.width, lanesBottom), line);
    final step = _step();
    var tick = (offset / step).ceil() * step;
    while (tick <= offset + size.width / pxPerSec) {
      final x = (tick - offset) * pxPerSec;
      canvas.drawLine(Offset(x, lanesBottom), Offset(x, lanesBottom + 4), line);
      final time = recording.started.add(Duration(microseconds: (tick * 1e6).round()));
      final tp = TextPainter(
        text: TextSpan(
          text: formatTime(time, millis: step < 1),
          style: label,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 3, lanesBottom + 6));
      tick += step;
    }
    // Abspielkopf.
    if (playhead case final p?) {
      final x = (p - offset) * pxPerSec;
      canvas.drawLine(
        Offset(x, flagBand),
        Offset(x, size.height),
        Paint()
          ..color = colors.accent
          ..strokeWidth = Lines.selection,
      );
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) => true;
}
