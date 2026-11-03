import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../model/device_channels.dart';
import '../model/device_shapes.dart';
import '../model/telegram_log.dart';
import 'device_drawing.dart';

/// Smoke detector on the ceiling (top view): round housing with smoke inlet,
/// test button and alarm LED. On its own alarm the LED lights and the rings
/// change color; on a networked alarm from another detector only the rings do.
/// The objects with their values in the corners.
/// Deliberately drawn neutrally, without any manufacturer's shape.
class SmokeDetectorView extends StatelessWidget {
  const SmokeDetectorView({super.key, required this.address, required this.log, this.compact = false});

  final int address;
  final TelegramLog log;

  /// Only the drawing (distribution board).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Sent objects first: its own alarm before the networked ones.
    final objects = objectsOf(address, CatalogStore.instance.catalog)
      ..sort((a, b) => (b.sends ? 1 : 0) - (a.sends ? 1 : 0));
    return DeviceDrawing(
      address: address,
      log: log,
      compact: compact,
      height: 220,
      semantics: (latest) => _readouts(objects, latest).map((r) => '${r.$1}: ${r.$2}').join(', '),
      painter: (style, latest, _) => _SmokePainter(
        style: style,
        alarm: objects.any((o) => o.sends && _on(o, latest)),
        networked: objects.any((o) => !o.sends && _on(o, latest)),
        readouts: _readouts(objects, latest),
      ),
    );
  }

  static bool _on(DeviceObject o, Map<int, Telegram> latest) => (numberOf(o.address, latest) ?? 0) > 0;

  /// (Label, value) for the corners of the drawing.
  static List<(String, String)> _readouts(List<DeviceObject> objects, Map<int, Telegram> latest) {
    final store = CatalogStore.instance;
    return [
      for (final o in objects.take(4))
        (
          store.info(o.address)?.name ?? formatGroup(o.address),
          switch (latest[o.address]) {
            final t? when t.type != TelegramType.read => store.value(t),
            _ => '–',
          },
        ),
    ];
  }
}

class _SmokePainter extends CustomPainter {
  _SmokePainter({required this.style, required this.alarm, required this.networked, required this.readouts});

  final DrawingStyle style;
  final bool alarm;
  final bool networked;
  final List<(String, String)> readouts;

  @override
  void paint(Canvas canvas, Size size) {
    final hz = style.hz;
    final c = size.center(Offset.zero);
    final r = size.height * 0.3;
    // Warning rings around the housing.
    if (alarm) canvas.drawCircle(c, size.height * 0.47, style.fill(hz.criticalTint));
    for (final f in [1.18, 1.48]) {
      canvas.drawCircle(c, r * f, style.stroke(alarm || networked ? hz.critical : hz.line));
    }
    // Housing
    canvas.drawCircle(c, r, style.fill(hz.surface));
    canvas.drawCircle(c, r, style.stroke(hz.lineStrong));
    // Smoke inlet: slots in a circle.
    const slots = 24;
    for (var k = 0; k < slots; k++) {
      final d = Offset.fromDirection(math.pi * 2 * k / slots, 1);
      canvas.drawLine(c + d * r * 0.62, c + d * r * 0.84, style.stroke(hz.lineStrong, 1.6));
    }
    // Test button in the middle, alarm LED at its edge.
    final button = r * 0.44;
    canvas.drawCircle(c, button, style.fill(hz.sunken));
    canvas.drawCircle(c, button, style.stroke(hz.line));
    final led = c + Offset(0, -button * 0.55);
    canvas.drawCircle(led, 3.2, style.fill(alarm ? hz.critical : hz.line));
    canvas.drawCircle(led, 3.2, style.stroke(hz.lineStrong));
    // Smoke wisps at the bottom right rising towards the detector; distinguishes
    // it from the presence detector; on alarm in warning color with a flame below.
    final smoke = alarm ? hz.critical : hz.textMuted;
    final base = c + Offset(r * 1.35, r * 1.2);
    for (var k = 0; k < 3; k++) {
      final x = base.dx + (k - 1) * 11.0;
      final y = base.dy - (k.isOdd ? 6.0 : 0.0);
      canvas.drawPath(
        Path()
          ..moveTo(x, y)
          ..cubicTo(x - 8, y - 10, x + 8, y - 18, x, y - 28)
          ..cubicTo(x - 7, y - 36, x + 4, y - 44, x - 3, y - 52),
        style.stroke(smoke, 2),
      );
    }
    if (alarm) {
      // Flame: warning color outside, lighter core inside.
      final f = base + const Offset(0, 24);
      Path flame(double s) => Path()
        ..moveTo(f.dx, f.dy - 26 * s)
        ..cubicTo(f.dx + 14 * s, f.dy - 12 * s, f.dx + 12 * s, f.dy, f.dx, f.dy)
        ..cubicTo(f.dx - 12 * s, f.dy, f.dx - 14 * s, f.dy - 10 * s, f.dx - 5 * s, f.dy - 16 * s)
        ..cubicTo(f.dx - 4 * s, f.dy - 9 * s, f.dx, f.dy - 12 * s, f.dx, f.dy - 26 * s)
        ..close();
      canvas.drawPath(flame(1), style.fill(hz.critical));
      canvas.drawPath(flame(0.55), style.fill(hz.warning));
    }
    _corners(canvas, size);
  }

  /// Values in the four corners: top left, top right, bottom left, bottom right.
  void _corners(Canvas canvas, Size size) {
    final w = size.width * 0.3;
    for (final (i, (name, value)) in readouts.indexed) {
      final right = i.isOdd;
      final y = i < 2 ? 14.0 : size.height - 30;
      final x = right ? size.width : 0.0;
      final align = right ? TextAlign.right : TextAlign.left;
      style.label(canvas, name, Offset(x, y), align: align, small: true, muted: true, maxWidth: w);
      style.label(canvas, value, Offset(x, y + 16), align: align, bold: true, maxWidth: w);
    }
  }

  @override
  bool shouldRepaint(_SmokePainter old) => true;
}
