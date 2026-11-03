import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/device_channels.dart';
import '../model/device_shapes.dart';
import '../model/telegram_log.dart';
import '../theme/palette.dart';
import 'device_drawing.dart';

/// Push-button interface/binary input for a flush-mounted box: housing with bus
/// terminal, programming button and type plate, one wire to the left per input,
/// with the contact (open/closed) and the current value at the wire's end.
class FlushInputView extends StatelessWidget {
  const FlushInputView({super.key, required this.address, required this.log, this.compact = false});

  /// Only the drawing (distribution board).
  final bool compact;

  final int address;
  final TelegramLog log;

  static const _row = 34.0;

  @override
  Widget build(BuildContext context) {
    final channels = channelsOf(address, CatalogStore.instance.catalog).where((c) => c.label.isNotEmpty).toList();
    return DeviceDrawing(
      address: address,
      log: log,
      compact: compact,
      height: math.max(170, channels.length * _row + 40),
      semantics: (latest) =>
          [for (final c in channels) s.deviceChannelSemantics(_title(c), _state(c, latest).$2)].join(', '),
      painter: (style, latest, _) => _FlushInputPainter(
        style: style,
        address: address,
        inputs: [for (final c in channels) (c.label, _title(c), _state(c, latest))],
      ),
    );
  }

  static String _title(DeviceChannel c) {
    final o = c.objects.first;
    final text = o.text?.replaceFirst(RegExp(r'^[^:]*:\s*'), '').trim() ?? '';
    return text.isNotEmpty ? text : (CatalogStore.instance.info(o.address)?.name ?? formatGroup(o.address));
  }

  /// Active (`null` = unknown) and the value as text.
  static (bool?, String) _state(DeviceChannel c, Map<int, Telegram> latest) {
    final t = primaryValue(c, latest);
    if (t == null || t.type == TelegramType.read) return (null, '–');
    final v = numberOf(t.destination, latest);
    return (v == null ? null : v > 0, CatalogStore.instance.value(t));
  }
}

class _FlushInputPainter extends CustomPainter {
  _FlushInputPainter({required this.style, required this.address, required this.inputs});

  final DrawingStyle style;
  final int address;

  /// Channel, label, (active, value).
  final List<(String, String, (bool?, String))> inputs;

  @override
  void paint(Canvas canvas, Size size) {
    final hz = style.hz;
    // Housing on the right, wires to the left.
    final side = math.min(130.0, size.width * 0.3);
    final u = side / 44; // Pixels per mm (housing ≈ 44 mm)
    // Type plate with at most 4 inputs per row; from 5 on the housing grows.
    final perRow = math.min(inputs.length, 4);
    final plateRows = (inputs.length / 4).ceil().clamp(1, 4);
    final height = side + (plateRows - 1) * 12 * u;
    final box = Rect.fromLTWH(size.width - side - 4, (size.height - height) / 2, side, height);

    // Wires first; the housing is drawn on top.
    final tipX = size.width - side - 4 - side * 0.4;
    final top = (size.height - inputs.length * FlushInputView._row) / 2 + FlushInputView._row / 2;
    for (final (i, (ch, title, (active, value))) in inputs.indexed) {
      final y = top + i * FlushInputView._row;
      // Drahtaustritt links unten am Stecker.
      final start = Offset(box.left - 3 * u, box.top + box.height * 0.62 + (i - (inputs.length - 1) / 2) * 2.5 * u);
      final end = Offset(tipX, y);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(start.dx - side * 0.25, start.dy, end.dx + side * 0.2, end.dy, end.dx, end.dy);
      final wire = i.isEven ? hz.critical : hz.text;
      canvas.drawPath(path, style.stroke(wire, 2.2));
      // Abisoliertes Ende
      canvas.drawLine(end, end - const Offset(9, 0), style.stroke(hz.textMuted, 1.6));
      _contact(canvas, Offset(end.dx - 26, y), active);
      final textRight = end.dx - 44;
      style.label(canvas, '$ch  $title', Offset(textRight, y - 7), align: TextAlign.right, maxWidth: textRight);
      style.label(canvas, value, Offset(textRight, y + 8), align: TextAlign.right, small: true, muted: true);
    }

    // Housing
    final shape = RRect.fromRectAndRadius(box, Radius.circular(3 * u));
    canvas.drawRRect(shape, style.fill(hz.surface));
    canvas.drawRRect(shape, style.stroke(hz.lineStrong));
    // Red/black bus terminal and input terminal on top.
    final clamp = Rect.fromLTWH(box.left + 14 * u, box.top - 2 * u, 9 * u, 7 * u);
    canvas.drawRect(Rect.fromLTWH(clamp.left - 10 * u, clamp.top, 9 * u, clamp.height), style.fill(hz.textMuted));
    canvas.drawRect(Rect.fromLTWH(clamp.left, clamp.top, clamp.width / 2, clamp.height), style.fill(hz.critical));
    canvas.drawRect(
      Rect.fromLTWH(clamp.left + clamp.width / 2, clamp.top, clamp.width / 2, clamp.height),
      style.fill(hz.text),
    );
    // Programming LED and button
    style.label(canvas, 'PROG.', Offset(box.right - 4 * u, box.top + 13 * u), align: TextAlign.right, small: true);
    canvas.drawCircle(Offset(box.right - 7 * u, box.top + 8 * u), 1.6 * u, style.fill(hz.line));
    canvas.drawCircle(Offset(box.right - 7 * u, box.top + 8 * u), 1.6 * u, style.stroke(hz.lineStrong));
    // Type plate with individual address and wiring diagram.
    final plate = Rect.fromLTWH(box.left + 4 * u, box.top + 16 * u, box.width - 8 * u, 8 * u + plateRows * 12 * u);
    canvas.drawRect(plate, style.stroke(hz.line));
    style.label(
      canvas,
      formatIndividual(address),
      Offset(plate.left + 2 * u, plate.top + 3 * u),
      small: true,
      maxWidth: plate.width - 4 * u,
    );
    final n = inputs.length;
    final column = plate.width / perRow;
    for (final (i, (ch, _, (active, _))) in inputs.indexed) {
      final x = plate.left + (i % perRow + 0.5) * column;
      final y = plate.top + 9 * u + (i ~/ perRow) * 12 * u;
      style.label(canvas, ch, Offset(x, y), align: TextAlign.center, small: true, bold: true);
      _contact(canvas, Offset(x, y + 6 * u), active, width: math.min(14, column - 8));
    }
    // Anschlussstecker unten (Drahtaustritt)
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(box.left - 1.5 * u, box.top + box.height * 0.62),
        width: 3 * u,
        height: math.max(6, n * 2.5 + 2) * u,
      ),
      style.stroke(hz.lineStrong),
    );
  }

  /// Switch contact: closed = straight line and LED on; open = lever.
  void _contact(Canvas canvas, Offset c, bool? active, {double width = 16}) {
    final hz = style.hz;
    final line = style.stroke(active == null ? hz.line : hz.textMuted, 1.4);
    final a = c - Offset(width / 2, 0);
    final b = c + Offset(width / 2, 0);
    canvas.drawCircle(a, 1.8, style.fill(hz.textMuted));
    canvas.drawCircle(b, 1.8, style.fill(hz.textMuted));
    canvas.drawLine(a, active == true ? b : a + Offset(width * 0.9, -width * 0.45), line);
    if (active == true) canvas.drawCircle(c + const Offset(0, -6), 2.4, style.fill(Palette.ledOn));
  }

  @override
  bool shouldRepaint(_FlushInputPainter old) => true;
}
