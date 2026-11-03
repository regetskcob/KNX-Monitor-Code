import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../model/device_channels.dart';
import '../model/device_shapes.dart';
import '../model/telegram_log.dart';
import '../theme/palette.dart';
import 'device_drawing.dart';

/// Presence detector on the ceiling (top view) or motion detector on the wall
/// (front view): housing with lens, around it the detection area, filled on
/// presence/motion. Next to it brightness, light and day/night.
/// Deliberately drawn neutrally, without any manufacturer's shape.
class PresenceView extends StatelessWidget {
  const PresenceView({super.key, required this.address, required this.log, this.wall = false, this.compact = false});

  final int address;
  final TelegramLog log;

  /// Whether this is a motion detector on the wall instead of a presence detector on the ceiling.
  final bool wall;

  /// Only the drawing (distribution board).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final catalog = CatalogStore.instance.catalog;
    final roles = <SensorRole, DeviceObject>{};
    for (final o in objectsOf(address, catalog)) {
      final r = roleOf(o, catalog);
      if (r != null) roles.putIfAbsent(r, () => o);
    }
    return DeviceDrawing(
      address: address,
      log: log,
      compact: compact,
      height: 250,
      semantics: (latest) => _readouts(roles, latest).map((r) => '${r.$1}: ${r.$2}').join(', '),
      painter: (style, latest, _) => _PresencePainter(
        style: style,
        wall: wall,
        present: _active(roles[SensorRole.presence], latest),
        light: _active(roles[SensorRole.light], latest),
        readouts: _readouts(roles, latest),
      ),
    );
  }

  static bool? _active(DeviceObject? o, Map<int, Telegram> latest) {
    if (o == null) return null;
    final v = numberOf(o.address, latest);
    return v == null ? null : v > 0;
  }

  /// (Label, value) for the corners of the drawing.
  static List<(String, String)> _readouts(Map<SensorRole, DeviceObject> roles, Map<int, Telegram> latest) {
    final store = CatalogStore.instance;
    return [
      for (final r in const [SensorRole.brightness, SensorRole.presence, SensorRole.light, SensorRole.dayNight])
        if (roles[r] case final o?)
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

class _PresencePainter extends CustomPainter {
  _PresencePainter({
    required this.style,
    required this.wall,
    required this.present,
    required this.light,
    required this.readouts,
  });

  final DrawingStyle style;
  final bool wall;
  final bool? present;
  final bool? light;
  final List<(String, String)> readouts;

  @override
  void paint(Canvas canvas, Size size) {
    wall ? _wall(canvas, size) : _ceiling(canvas, size);
    _corners(canvas, size);
  }

  void _ceiling(Canvas canvas, Size size) {
    final hz = style.hz;
    final c = size.center(Offset.zero);
    final zone = size.height * 0.47;
    // Detection area: dashed rings, filled on presence.
    if (present == true) canvas.drawCircle(c, zone, style.fill(hz.accent.withValues(alpha: 0.10)));
    for (final f in [1.0, 0.72]) {
      _dashedCircle(canvas, c, zone * f, style.stroke(present == true ? hz.accent : hz.line));
    }
    // Flat housing: narrow rim, large flat lens, facets only in the middle.
    final r = size.height * 0.22;
    canvas.drawCircle(c, r, style.fill(hz.surface));
    canvas.drawCircle(c, r, style.stroke(hz.lineStrong));
    final lens = r * 0.88;
    canvas.drawCircle(c, lens, style.fill(hz.sunken));
    canvas.drawCircle(c, lens, style.stroke(hz.line));
    final cluster = r * 0.24;
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: cluster)));
    final facet = style.stroke(hz.lineStrong);
    const step = 7.0;
    for (var y = -cluster; y <= cluster; y += step * 0.86) {
      final shift = ((y / (step * 0.86)).round().isOdd) ? step / 2 : 0;
      for (var x = -cluster - step; x <= cluster + step; x += step) {
        _hexagon(canvas, c + Offset(x + shift, y), step * 0.5, facet);
      }
    }
    canvas.restore();
    // Sensor dots on the lens.
    for (var k = 0; k < 4; k++) {
      final p = c + Offset.fromDirection(math.pi / 4 + math.pi / 2 * k, lens * 0.55);
      canvas.drawCircle(p, 2.2, style.fill(hz.line));
    }
    // Status LED at the rim
    final led = c + Offset(lens - 4, 0);
    canvas.drawCircle(led, 3, style.fill(present == true ? Palette.ledOn : hz.line));
    canvas.drawCircle(led, 3, style.stroke(hz.lineStrong));
  }

  /// Side view, deliberately generic: angular housing directly on the wall,
  /// below it a spherical lens; detection fan towards the bottom left.
  void _wall(Canvas canvas, Size size) {
    final hz = style.hz;
    final cx = size.width / 2;
    final h = size.height;
    final wallX = cx + 64;
    final box = Rect.fromLTRB(cx - 30, h * 0.2, wallX, h * 0.42);
    final lens = Rect.fromCircle(center: Offset(box.center.dx - 6, box.bottom), radius: 30);
    final lit = present == true || light == true;
    // Detection fan from the lens.
    final apex = lens.center + const Offset(0, 12);
    final fan = h * 0.55;
    const start = math.pi * 0.5, sweep = math.pi * 0.5;
    if (lit) {
      canvas.drawArc(
        Rect.fromCircle(center: apex, radius: fan),
        start,
        sweep,
        true,
        style.fill(hz.accent.withValues(alpha: 0.10)),
      );
    }
    for (final f in [0.55, 0.78, 1.0]) {
      _dashedArc(canvas, apex, fan * f, start, sweep, style.stroke(lit ? hz.accent : hz.line));
    }
    // Wand
    canvas.drawRect(Rect.fromLTWH(wallX, h * 0.04, 8, h * 0.72), style.fill(hz.sunken));
    canvas.drawLine(Offset(wallX, h * 0.04), Offset(wallX, h * 0.76), style.stroke(hz.lineStrong));
    // Spherical lens below the housing.
    canvas.drawArc(lens, 0, math.pi, true, style.fill(lit ? hz.accentTint : hz.sunken));
    for (final f in [0.4, 0.72]) {
      canvas.drawArc(Rect.fromCircle(center: lens.center, radius: 30 * f), 0, math.pi, false, style.stroke(hz.line));
    }
    for (var k = 1; k < 6; k++) {
      canvas.drawLine(lens.center, lens.center + Offset.fromDirection(math.pi * k / 6, 30), style.stroke(hz.line));
    }
    canvas.drawArc(lens, 0, math.pi, true, style.stroke(hz.lineStrong));
    // Housing with a bevelled front and status LED.
    final body = Path()
      ..moveTo(wallX, box.top)
      ..lineTo(box.left + 14, box.top)
      ..lineTo(box.left, box.top + 16)
      ..lineTo(box.left, box.bottom)
      ..lineTo(wallX, box.bottom)
      ..close();
    canvas.drawPath(body, style.fill(hz.surface));
    canvas.drawPath(body, style.stroke(hz.lineStrong));
    canvas.drawLine(Offset(box.left + 6, box.bottom - 8), Offset(wallX - 6, box.bottom - 8), style.stroke(hz.line));
    canvas.drawCircle(Offset(box.left + 10, box.top + 26), 3, style.fill(present == true ? Palette.ledOn : hz.line));
    // Light switched by the detector (outside, left): on = filled with rays.
    if (light != null) {
      final bulb = Offset(box.left - 56, h * 0.3);
      canvas.drawCircle(bulb, 10, light! ? style.fill(hz.warning) : style.stroke(hz.lineStrong, 1.4));
      canvas.drawRect(
        Rect.fromCenter(center: bulb + const Offset(0, 13), width: 8, height: 6),
        style.fill(hz.textMuted),
      );
      if (light!) {
        for (var a = 0; a < 8; a++) {
          final d = Offset.fromDirection(math.pi * 2 * a / 8 - math.pi / 2, 1);
          if (d.dy > 0.5) continue;
          canvas.drawLine(bulb + d * 14, bulb + d * 19, style.stroke(hz.warning, 1.4));
        }
      }
    }
  }

  /// Values in the four corners: top left, top right, bottom left, bottom right.
  void _corners(Canvas canvas, Size size) {
    final w = size.width * 0.3;
    for (final (i, (name, value)) in readouts.take(4).indexed) {
      final right = i.isOdd;
      final y = i < 2 ? 14.0 : size.height - 30;
      final x = right ? size.width : 0.0;
      final align = right ? TextAlign.right : TextAlign.left;
      style.label(canvas, name, Offset(x, y), align: align, small: true, muted: true, maxWidth: w);
      style.label(canvas, value, Offset(x, y + 16), align: align, bold: true, maxWidth: w);
    }
  }

  void _hexagon(Canvas canvas, Offset c, double r, Paint p) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final v = c + Offset.fromDirection(math.pi / 3 * i + math.pi / 6, r);
      i == 0 ? path.moveTo(v.dx, v.dy) : path.lineTo(v.dx, v.dy);
    }
    canvas.drawPath(path..close(), p);
  }

  void _dashedCircle(Canvas canvas, Offset c, double r, Paint p) => _dashedArc(canvas, c, r, 0, math.pi * 2, p);

  void _dashedArc(Canvas canvas, Offset c, double r, double start, double sweep, Paint p) {
    final dash = 6 / r;
    final rect = Rect.fromCircle(center: c, radius: r);
    for (var a = start; a < start + sweep; a += dash * 2) {
      canvas.drawArc(rect, a, math.min(dash, start + sweep - a), false, p);
    }
  }

  @override
  bool shouldRepaint(_PresencePainter old) => true;
}
