import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../theme/tokens.dart';
import '../model/analysis.dart';
import '../theme/palette.dart';
import 'telegram_row.dart';
import '../theme/app_icons.dart';

/// Live history, newest on top. New telegrams slide in and are briefly tinted,
/// but only when the list is scrolled to the top (otherwise nothing jumps under the finger).
class LiveList extends StatefulWidget {
  const LiveList({
    super.key,
    required this.items,
    required this.live,
    required this.onTap,
    required this.onLongPress,
    this.onContextMenu,
    required this.isFresh,
    required this.issuesOf,
    this.selection,
    this.focused,
    this.isContext,
    this.markOf,
  });

  /// Only context around a filter match (shown dimmed).
  final bool Function(Telegram)? isContext;

  /// Color mark per filter group (with several OR groups).
  final Color? Function(Telegram)? markOf;

  /// Telegrams, oldest first.
  final List<Telegram> items;

  /// Whether the monitor is running (not paused); only then are rows animated.
  final bool live;
  final Set<Telegram>? selection;

  /// Opened in the detail panel; telegrams of the same address are highlighted too.
  final Telegram? focused;
  final ValueChanged<Telegram> onTap;
  final ValueChanged<Telegram> onLongPress;

  /// Right-click on a row, with the position on screen.
  final void Function(Telegram, Offset)? onContextMenu;

  /// Just arrived; shown with an animation.
  final bool Function(Telegram) isFresh;

  /// Anomalies per telegram.
  final List<TelegramIssue> Function(Telegram) issuesOf;

  @override
  State<LiveList> createState() => _LiveListState();
}

class _LiveListState extends State<LiveList> {
  final _scroll = ScrollController();
  bool _atTop = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final atTop = _scroll.offset < 24;
      if (atTop != _atTop) setState(() => _atTop = atTop);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return HorizontEmptyHint(icon: AppIcons.sensors, text: s.liveWaiting);

    // Identity → index, so rows keep their state when items are inserted.
    final index = Map<Telegram, int>.identity();
    for (var i = 0; i < items.length; i++) {
      index[items[items.length - 1 - i]] = i;
    }
    final animate = widget.live && _atTop;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= wideRowBreakpoint;
        return Stack(
          children: [
            // No card around the list: rows are separated by the hairline. On very
            // wide screens (21:9) no wider than [Widths.wide], so name and value
            // stay within one glance on the same row.
            Align(
              alignment: AlignmentDirectional.topStart,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Widths.wide),
                child: Column(
                  children: [
                    if (wide) const TelegramTableHeader(),
                    Expanded(
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.only(bottom: HzSpace.s96),
                        itemCount: items.length,
                        findChildIndexCallback: (key) => index[(key as ObjectKey).value],
                        itemBuilder: (context, i) {
                          final index = items.length - 1 - i;
                          final t = items[index];
                          return KeyedSubtree(
                            key: ObjectKey(t),
                            child: Arrival(
                              animate: animate && widget.isFresh(t),
                              child: _Marked(
                                context: widget.isContext?.call(t) ?? false,
                                mark: widget.markOf?.call(t),
                                child: TelegramRow(
                                  telegram: t,
                                  wide: wide,
                                  // Stripes by index from the oldest telegram, stable when inserting.
                                  zebra: index.isOdd,
                                  issues: widget.issuesOf(t),
                                  selected: widget.selection?.contains(t),
                                  focused: identical(t, widget.focused),
                                  related: widget.focused?.destination == t.destination,
                                  onTap: () => widget.onTap(t),
                                  onLongPress: () => widget.onLongPress(t),
                                  onSecondaryTapUp: widget.onContextMenu == null
                                      ? null
                                      : (d) => widget.onContextMenu!(t, d.globalPosition),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Back to the newest telegrams.
            Positioned(
              top: wide ? HzSpace.s48 + HzSpace.s4 : HzSpace.s8,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedSlide(
                  offset: _atTop ? const Offset(0, -1.5) : Offset.zero,
                  duration: Motion.of(context),
                  curve: Motion.curve,
                  child: AnimatedOpacity(
                    opacity: _atTop ? 0 : 1,
                    duration: Motion.of(context),
                    curve: Motion.curve,
                    child: IgnorePointer(
                      ignoring: _atTop,
                      // Sits above the rows: surface and line instead of a shadow.
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(backgroundColor: context.hz.surface),
                        onPressed: () => _scroll.animateTo(0, duration: Motion.slowOf(context), curve: Motion.curve),
                        icon: const Icon(AppIcons.toTop, size: 18),
                        label: Text(s.liveNewest),
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

/// Context rows dimmed, filter groups with a colored stripe at the edge.
class _Marked extends StatelessWidget {
  const _Marked({required this.context, required this.mark, required this.child});

  final bool context;
  final Color? mark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget result = child;
    if (mark != null) {
      result = DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: mark!, width: Lines.selection),
          ),
        ),
        child: result,
      );
    }
    if (this.context) result = Opacity(opacity: 0.45, child: result);
    return result;
  }
}

/// Expands a new item and briefly holds it in accent tint, which then fades
/// out. Respects "reduce motion".
class Arrival extends StatefulWidget {
  const Arrival({super.key, required this.animate, required this.child});

  final bool animate;
  final Widget child;

  @override
  State<Arrival> createState() => _ArrivalState();
}

class _ArrivalState extends State<Arrival> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: Motion.calm);
  late final _size = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.3, curve: Motion.curve),
  );
  late final _tint = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.3, 1, curve: Motion.curveOut),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.animate && !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.isCompleted) return widget.child;
    return SizeTransition(
      sizeFactor: _size,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: _size,
        child: AnimatedBuilder(
          animation: _tint,
          builder: (context, child) => DecoratedBox(
            decoration: BoxDecoration(color: context.hz.accentTint.withValues(alpha: 1 - _tint.value)),
            child: child,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
