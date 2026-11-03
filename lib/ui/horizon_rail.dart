import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:horizont/horizont.dart';

import '../theme/brand.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';

/// Outline along the right edge, modeled on the landing page's horizon
/// (horizont `horizon.js`), vertical: a line with one mark per section, filled
/// in the accent color up to the reading position, with the symbol moving
/// along. The current section shows its name, the others where there is room;
/// tapping jumps there.
class HorizonRail extends StatefulWidget {
  const HorizonRail({super.key, required this.controller, required this.marks});

  final ScrollController controller;

  /// Sections from top to bottom: name and key of their header.
  final List<(String, GlobalKey)> marks;

  /// Width of the column.
  static const width = 168.0;

  @override
  State<HorizonRail> createState() => _HorizonRailState();
}

class _HorizonRailState extends State<HorizonRail> {
  /// Top and bottom margin, distance of the line from the right edge.
  static const _inset = HzSpace.s24;
  static const _lineRight = HzSpace.s24;

  /// Minimum distance between two marks so both show their name.
  static const _labelRoom = 16.0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    // Section positions are only known after the first layout.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void didUpdateWidget(HorizonRail old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (mounted) setState(() {});
  }

  /// Scroll position at which a section's header is at the top; `null` while it
  /// hasn't been built.
  double? _offsetOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final viewport = RenderAbstractViewport.maybeOf(box);
    return viewport?.getOffsetToReveal(box, 0).offset;
  }

  void _jump(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(context, duration: Motion.of(this.context), curve: Motion.curve);
  }

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final c = widget.controller;
    if (!c.hasClients || widget.marks.isEmpty) return const SizedBox(width: HorizonRail.width);
    final position = c.position;
    final max = position.hasContentDimensions ? position.maxScrollExtent : 0.0;
    final pixels = position.hasPixels ? position.pixels : 0.0;
    final progress = max <= 0 ? 0.0 : (pixels / max).clamp(0.0, 1.0);
    final n = widget.marks.length;
    // Fraction per mark: from the position in the content, otherwise evenly
    // spread.
    final at = [
      for (final (i, (_, key)) in widget.marks.indexed)
        switch (_offsetOf(key)) {
          final o? when max > 0 => (o / max).clamp(0.0, 1.0),
          _ => n == 1 ? 0.0 : i / (n - 1),
        },
    ];
    var current = 0;
    for (final (i, (_, key)) in widget.marks.indexed) {
      final o = _offsetOf(key);
      if (o != null && o <= pixels + HzSpace.s8) current = i;
    }
    // At the end of the list the last section counts as reached.
    if (max > 0 && pixels >= max - 1) current = n - 1;
    // Names as labels (mono caps, 11/16), like Horizont's chapters on the web.
    final label = context.hzTheme.kennung.copyWith(color: hz.textFaint);
    return SizedBox(
      width: HorizonRail.width,
      child: LayoutBuilder(
        builder: (context, box) {
          final length = math.max(0.0, box.maxHeight - 2 * _inset);
          double y(double f) => _inset + f * length;
          final lineX = box.maxWidth - _lineRight;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Line, filled part up to the reading position.
              Positioned(
                left: lineX,
                top: _inset,
                height: length,
                width: Lines.hairline,
                child: ColoredBox(color: hz.lineStrong),
              ),
              Positioned(
                left: lineX - 0.5,
                top: _inset,
                height: progress * length,
                width: Lines.selection,
                child: ColoredBox(color: hz.accent),
              ),
              for (final (i, (name, key)) in widget.marks.indexed)
                Positioned(
                  left: 0,
                  width: lineX + HzSpace.s8,
                  top: y(at[i]) - HzSpace.s8,
                  height: HzSpace.s16,
                  child: Semantics(
                    button: true,
                    selected: i == current,
                    label: name,
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _jump(key),
                      child: Row(
                        children: [
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                // Name where there is room; always for the
                                // current one.
                                final before = i == 0 ? double.infinity : (at[i] - at[i - 1]) * length;
                                final after = i == n - 1 ? double.infinity : (at[i + 1] - at[i]) * length;
                                final room = i == current || math.min(before, after) >= _labelRoom;
                                return Text(
                                  room ? name.toUpperCase() : '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: i == current ? label.copyWith(color: hz.text) : label,
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: HzSpace.s4),
                          // Mark: short tick left of the line.
                          Container(
                            width: HzSpace.s8,
                            height: Lines.selection,
                            color: i == current ? hz.accent : hz.lineStrong,
                          ),
                          const SizedBox(width: HzSpace.s4),
                        ],
                      ),
                    ),
                  ),
                ),
              // The symbol moves with the reading position.
              AnimatedPositioned(
                duration: Motion.of(context),
                curve: Motion.curve,
                left: lineX - HzSpace.s8,
                top: y(progress) - HzSpace.s8,
                child: ExcludeSemantics(
                  child: ColoredBox(
                    color: hz.bg,
                    child: HorizontMark(Brand.product, size: HzSpace.s16, color: hz.accentText),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
