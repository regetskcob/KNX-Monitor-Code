import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../model/device_channels.dart';
import '../model/device_shapes.dart';
import '../model/telegram_log.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'actuator_view.dart';
import 'live_updates.dart';

/// Paints a device's drawing from the current values; [elapsed] only runs for
/// devices with motion (wind turbine) and stands still with "reduce motion".
typedef DevicePainterBuilder = CustomPainter Function(DrawingStyle style, Map<int, Telegram> latest, Duration elapsed);

/// Colors and font for device drawings, from the theme; labels in Monaspace as
/// on the device.
class DrawingStyle {
  const DrawingStyle(this.hz, this.text);

  final HorizontColors hz;
  final TextStyle text;

  Paint stroke(Color c, [double w = Lines.hairline]) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w;

  Paint fill(Color c) => Paint()..color = c;

  /// Label at [at] (alignment is relative to [at]).
  void label(
    Canvas canvas,
    String value,
    Offset at, {
    TextAlign align = TextAlign.left,
    bool bold = false,
    bool small = false,
    bool muted = false,
    double maxWidth = 160,
    Color? color,
    double scale = 1,
  }) {
    if (value.isEmpty || maxWidth <= 0) return;
    var style = text.copyWith(fontWeight: bold ? FontWeight.w600 : FontWeight.w400);
    if (small) style = style.apply(fontSizeFactor: 0.82);
    if (scale != 1) style = style.apply(fontSizeFactor: scale);
    if (muted) style = style.copyWith(color: hz.textMuted);
    if (color != null) style = style.copyWith(color: color);
    final tp = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    final dx = switch (align) {
      TextAlign.center => at.dx - tp.width / 2,
      TextAlign.right => at.dx - tp.width,
      _ => at.dx,
    };
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
    tp.dispose();
  }
}

/// Device drawing with type and address below and the object list with current
/// values, for sensors and inputs that have no tappable channels.
class DeviceDrawing extends StatefulWidget {
  const DeviceDrawing({
    super.key,
    required this.address,
    required this.log,
    required this.height,
    required this.painter,
    required this.semantics,
    this.animate = false,
    this.compact = false,
  });

  final int address;
  final TelegramLog log;
  final double height;
  final DevicePainterBuilder painter;

  /// Summary for screen readers (the drawing itself is silent).
  final String Function(Map<int, Telegram> latest) semantics;

  /// Whether something moves in the drawing (wind turbine).
  final bool animate;

  /// Only the drawing, without type, address and object list (distribution
  /// board).
  final bool compact;

  @override
  State<DeviceDrawing> createState() => _DeviceDrawingState();
}

class _DeviceDrawingState extends State<DeviceDrawing> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((d) => setState(() => _elapsed = d));
  Duration _elapsed = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.animate && !still && !_ticker.isActive) _ticker.start();
    if (still && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final data = context.hzTheme.data;
    TextStyle mono(TextStyle? size, Color color) => (size ?? data).copyWith(
      fontFamily: HzFont.mono,
      package: HzFont.package,
      fontFeatures: data.fontFeatures,
      color: color,
    );
    final style = DrawingStyle(context.hzDevice, mono(theme.textTheme.labelSmall, hz.text));
    final store = CatalogStore.instance;
    final device = store.device(widget.address);
    final objects = objectsOf(widget.address, store.catalog);
    return ListenableBuilder(
      listenable: liveUpdates(widget.log),
      builder: (context, _) {
        final latest = widget.log.latest;
        final drawing = Semantics(
          label: widget.semantics(latest),
          excludeSemantics: true,
          child: SizedBox(
            height: widget.height,
            child: CustomPaint(painter: widget.painter(style, latest, _elapsed)),
          ),
        );
        if (widget.compact) return drawing;
        // Values in the corners close to the drawing; object list not endlessly
        // wide.
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Widths.lineCard),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                drawing,
                const SizedBox(height: HzSpace.s8),
                Text(
                  [?device?.product ?? device?.name, formatIndividual(widget.address)].join(metaSeparator),
                  textAlign: TextAlign.center,
                  style: mono(theme.textTheme.bodySmall, hz.textMuted),
                ),
                if (objects.isNotEmpty) ...[
                  const SizedBox(height: HzSpace.s8),
                  ChannelObjects(channel: DeviceChannel('', objects), latest: latest),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
