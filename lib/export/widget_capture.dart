import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Renders [child] invisibly (off screen, in the overlay of [context]) at width [width] and returns
/// a PNG – e.g. a device drawing for a PDF report. Theme, language and fonts come from the running
/// app. [settle] gives images and graphics time to load. With [background] it crops margins of that
/// colour (down to [margin] logical pixels). `null` if the overlay is missing or the image cannot
/// be created.
Future<Uint8List?> captureWidget(
  BuildContext context,
  Widget child, {
  required double width,
  double pixelRatio = 2,
  Color? background,
  double margin = 12,
  Duration settle = const Duration(milliseconds: 250),
}) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return null;
  final key = GlobalKey();
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      // Left of the screen: drawn but not seen.
      left: -width - 1000,
      top: 0,
      width: width,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(color: background ?? const Color(0x00000000), child: child),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(settle);
    await WidgetsBinding.instance.endOfFrame;
    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || !boundary.hasSize || boundary.size.isEmpty) return null;
    var image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      if (background != null) {
        final cropped = await trimBackground(image, background, (margin * pixelRatio).round());
        if (cropped != null) {
          image.dispose();
          image = cropped;
        }
      }
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    entry.remove();
  }
}

/// Crops margins in the colour [background], leaving [margin] pixels; `null` if there is nothing to
/// crop.
Future<ui.Image?> trimBackground(ui.Image image, Color background, int margin) async {
  final data = await image.toByteData();
  if (data == null) return null;
  final w = image.width, h = image.height;
  final r = (background.r * 255).round(), g = (background.g * 255).round(), b = (background.b * 255).round();
  bool ink(int x, int y) {
    final i = (y * w + x) * 4;
    return (data.getUint8(i) - r).abs() + (data.getUint8(i + 1) - g).abs() + (data.getUint8(i + 2) - b).abs() > 24;
  }

  var top = 0, bottom = h - 1, left = 0, right = w - 1;
  bool rowEmpty(int y) => !Iterable<int>.generate(w).any((x) => ink(x, y));
  bool columnEmpty(int x, int y0, int y1) => !Iterable<int>.generate(y1 - y0 + 1, (k) => y0 + k).any((y) => ink(x, y));
  while (top < bottom && rowEmpty(top)) {
    top++;
  }
  while (bottom > top && rowEmpty(bottom)) {
    bottom--;
  }
  while (left < right && columnEmpty(left, top, bottom)) {
    left++;
  }
  while (right > left && columnEmpty(right, top, bottom)) {
    right--;
  }
  final rect = Rect.fromLTRB(
    (left - margin).clamp(0, w).toDouble(),
    (top - margin).clamp(0, h).toDouble(),
    (right + 1 + margin).clamp(0, w).toDouble(),
    (bottom + 1 + margin).clamp(0, h).toDouble(),
  );
  if (rect.width >= w && rect.height >= h) return null;
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
    ..drawRect(Offset.zero & rect.size, Paint()..color = background)
    ..drawImageRect(image, rect, Offset.zero & rect.size, Paint());
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(rect.width.round(), rect.height.round());
  } finally {
    picture.dispose();
  }
}
