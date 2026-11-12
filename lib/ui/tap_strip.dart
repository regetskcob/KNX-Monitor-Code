import 'dart:async';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../knx/demo_tunnel.dart';
import '../knx/knx_tunnel.dart';
import '../l10n/locale_controller.dart';
import '../model/tap_points.dart';
import '../model/telegram_log.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'telegram_row.dart';

/// The tap points of the open monitor above the live list (issue #8): one card each with its
/// state in words, telegrams per minute, bus load as a bar, repetitions and the measured lag;
/// below them the spans in which a tap point was away. Bus load and errors are counted per tap
/// point, so each line shows what it really carried.
///
/// Nothing with a single tap point. On narrow screens it starts folded to one line.
class TapStrip extends StatefulWidget {
  const TapStrip({super.key, required this.tunnel, required this.log});

  final KnxTunnel tunnel;
  final TelegramLog log;

  @override
  State<TapStrip> createState() => _TapStripState();
}

class _TapStripState extends State<TapStrip> {
  Timer? _tick;
  bool? _open;

  @override
  void initState() {
    super.initState();
    // The rates move on while no telegram arrives.
    _tick = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && widget.tunnel.tapPoints.value.length > 1) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String stateText(TapStatus p) => p.paused
      ? s.tapStatePaused
      : p.connected
      ? (p.silent ? s.tapStateSilent : s.tapStateConnected)
      : p.state == TunnelState.connecting
      ? s.tapStateConnecting
      : s.tapStateAway;

  static HorizontStatus statusOf(TapStatus p) => p.paused
      ? HorizontStatus.neutral
      : p.connected
      ? (p.silent ? HorizontStatus.info : HorizontStatus.positive)
      : p.state == TunnelState.connecting
      ? HorizontStatus.neutral
      : HorizontStatus.warning;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.tunnel.tapPoints, tapGaps]),
      builder: (context, _) {
        final points = widget.tunnel.tapPoints.value;
        if (points.length < 2) return const SizedBox(width: double.infinity);
        final theme = Theme.of(context);
        final hz = context.hz;
        final width = MediaQuery.sizeOf(context).width;
        final gutter = Gap.gutterFor(width);
        final live = points.where((p) => p.connected && !p.paused).length;
        final now = DemoTunnel.active ? DemoTunnel.clock() : DateTime.now();
        final gaps = tapGaps.all.reversed.take(3).toList();
        return LayoutBuilder(
          // Unfolded where there is room (by the width it really gets, not by the device).
          builder: (context, outer) {
            final open = _open ?? outer.maxWidth >= 840;
            final loads = open ? TapLoad.of(widget.log.log, points.length, now: now) : const <TapLoad>[];
            return Padding(
              padding: EdgeInsets.fromLTRB(gutter, HzSpace.s4, gutter, Gap.item),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    button: true,
                    expanded: open,
                    child: InkWell(
                      borderRadius: Radii.tile,
                      onTap: () => setState(() => _open = !open),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                s.tapStripTitle(points.length, live),
                                style: theme.textTheme.labelLarge?.copyWith(color: hz.textMuted),
                              ),
                            ),
                            Icon(open ? Icons.expand_less : Icons.expand_more, color: hz.textMuted),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (open)
                    // Its own height and scrolling: the list below always keeps its room, whatever
                    // the number of tap points and the text size.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: (MediaQuery.sizeOf(context).height * 0.3).clamp(96.0, 320.0),
                      ),
                      child: Scrollbar(
                        child: SingleChildScrollView(
                          primary: false,
                          child: LayoutBuilder(
                            builder: (context, box) {
                              // From four tap points on, or with large text: one line each.
                              final compact = points.length >= 4 || MediaQuery.textScalerOf(context).scale(1) > 1.3;
                              // As many cards side by side as fit at a readable width.
                              final perRow = compact ? 1 : (box.maxWidth / 220).floor().clamp(1, points.length);
                              final cardWidth = (box.maxWidth - HzSpace.s8 * (perRow - 1)) / perRow;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (compact)
                                    for (final p in points) _TapLine(point: p, load: loads[p.index])
                                  else
                                    Wrap(
                                      spacing: HzSpace.s8,
                                      runSpacing: HzSpace.s8,
                                      children: [
                                        for (final p in points)
                                          SizedBox(
                                            width: cardWidth,
                                            child: _TapCard(point: p, load: loads[p.index]),
                                          ),
                                      ],
                                    ),
                                  if (gaps.isNotEmpty) ...[
                                    const SizedBox(height: HzSpace.s8),
                                    for (final g in gaps)
                                      Text(() {
                                        final label = g.tap < points.length ? points[g.tap].label : '${g.tap + 1}';
                                        final from = formatTime(g.from, millis: false);
                                        final text = g.to == null
                                            ? s.tapGapOpen(from, label)
                                            : s.tapGapClosed(from, formatTime(g.to!, millis: false), label);
                                        return g.paused ? '$text · ${s.tapStatePaused}' : text;
                                      }(), style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
                                  ],
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Why a tap point is not connected, in plain words: what the system reports ("SocketException …
/// errno = 51") says nothing to the reader. Texts that are already readable pass.
String tapErrorText(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final lower = raw.toLowerCase();
  if (lower.contains('unreachable') || lower.contains('no route') || lower.contains('failed host lookup')) {
    return s.tapErrorNetwork;
  }
  if (lower.contains('refused')) return s.tapErrorRefused;
  if (lower.contains('timed out') || lower.contains('timeout') || lower.contains('no response')) {
    return s.tapErrorNoAnswer;
  }
  if (lower.contains('exception') || lower.contains('errno') || lower.contains('os error')) return s.tapErrorOther;
  return raw;
}

/// State of a tap point with its reason, for card and line.
String _stateLine(TapStatus point) {
  final state = _TapStripState.stateText(point);
  if (point.connected || point.paused) return state;
  final why = tapErrorText(point.error);
  return why.isEmpty ? state : '$state$metaSeparator$why';
}

/// One tap point in one line (from four tap points on, or with large text): label, name, state
/// in words and the figures. Wraps instead of cutting off.
class _TapLine extends StatelessWidget {
  const _TapLine({required this.point, required this.load});

  final TapStatus point;
  final TapLoad load;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final status = _TapStripState.statusOf(point);
    final percent = load.percent;
    final figures = [
      s.tapLoadRate(load.perMinute.round()),
      s.tapLoadPercent(localizeDecimal(percent.toStringAsFixed(percent < 10 ? 1 : 0))),
      if (load.repeats > 0) s.tapLoadRepeats(load.repeats),
    ].join(metaSeparator);
    final state = _stateLine(point);
    final muted = theme.textTheme.bodySmall?.copyWith(color: hz.textMuted);
    return Semantics(
      container: true,
      label: [s.tapNamed(point.label), point.name, state, figures].join(', '),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: HzSpace.s4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(status.icon, size: 14, color: status.color(hz)),
              ),
              const SizedBox(width: HzSpace.s8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: point.label == point.name ? point.name : '${point.label}  ${point.name}',
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: hz.text),
                      ),
                      TextSpan(text: '$metaSeparator$state$metaSeparator$figures'),
                    ],
                  ),
                  style: muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TapCard extends StatelessWidget {
  const _TapCard({required this.point, required this.load});

  final TapStatus point;
  final TapLoad load;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final status = _TapStripState.statusOf(point);
    final state = _TapStripState.stateText(point);
    final muted = theme.textTheme.bodySmall?.copyWith(color: hz.textMuted);
    final rate = load.perMinute.round();
    final percent = load.percent;
    final percentText = localizeDecimal(percent.toStringAsFixed(percent < 10 ? 1 : 0));
    final window = point.autoWindow;
    final lag = point.lag;
    final figures = [
      s.tapLoadRate(rate),
      s.tapLoadPercent(percentText),
      if (load.repeats > 0) s.tapLoadRepeats(load.repeats),
    ].join(metaSeparator);
    final timing = [
      if (lag != null) s.tapLag(localizeDecimal((lag.inMicroseconds / 1000).toStringAsFixed(1))),
      if (window != null) s.tapWindowAuto(window.inMilliseconds),
    ].join(metaSeparator);
    return Semantics(
      container: true,
      label: [s.tapNamed(point.label), point.name, state, figures, if (timing.isNotEmpty) timing].join(', '),
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: hz.surface,
            border: Border.all(color: point.listening ? hz.line : hz.lineStrong),
            borderRadius: Radii.box,
          ),
          child: Padding(
            padding: const EdgeInsets.all(HzSpace.s12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: hz.accentTint,
                        border: Border.all(color: hz.accent),
                        borderRadius: Radii.row,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        child: Text(
                          point.label,
                          style: context.hzTheme.data.copyWith(
                            fontSize: 12,
                            height: 16 / 12,
                            color: hz.accentText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: HzSpace.s8),
                    Expanded(
                      child: Text(
                        point.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: HzSpace.s4),
                // State in words with a symbol, colour only in addition.
                Row(
                  children: [
                    Icon(status.icon, size: 14, color: status.color(hz)),
                    const SizedBox(width: HzSpace.s4),
                    Expanded(child: Text(_stateLine(point), style: muted)),
                  ],
                ),
                const SizedBox(height: HzSpace.s8),
                Text(figures, style: context.hzTheme.data.copyWith(fontSize: 13)),
                const SizedBox(height: HzSpace.s4),
                ClipRRect(
                  borderRadius: Radii.row,
                  child: LinearProgressIndicator(
                    value: (percent / 100).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: hz.sunken,
                    color: percent >= 50 ? hz.warning : hz.accent,
                  ),
                ),
                if (timing.isNotEmpty) ...[const SizedBox(height: HzSpace.s4), Text(timing, style: muted)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
