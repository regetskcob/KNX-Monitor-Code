import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import 'brand.dart';

/// Light/dark theme from Horizont, product Busclear (accent "Bus") in the soft variant (Horizont's
/// default for apps since 0.13.0).
///
/// Everything essential (hand-set scheme, typography, components, platform feel) comes from the
/// package. In the Home Assistant add-on ([homeAssistant]) the app takes over Home Assistant's
/// neutral colours so it sits calmly in the Ingress frame; accent and font stay.
abstract final class AppTheme {
  static ThemeData light({bool homeAssistant = false}) => _build(Brightness.light, homeAssistant);

  static ThemeData dark({bool homeAssistant = false}) => _build(Brightness.dark, homeAssistant);

  static ThemeData _build(Brightness brightness, bool homeAssistant) {
    final base = buildHorizontTheme(Brand.product, brightness, host: homeAssistant ? HorizontHost.homeAssistant : null);
    final sheetShape = base.bottomSheetTheme.shape;
    return base.copyWith(
      // Do not glue actions on the right to the edge (e.g. the record button with border); Material
      // sets no spacing here.
      appBarTheme: base.appBarTheme.copyWith(actionsPadding: const EdgeInsetsDirectional.only(end: HzSpace.s8)),
      // Sheets extend under the navigation bar into the rounded display corners – the border would
      // be cut off there. Draw only at the top.
      bottomSheetTheme: sheetShape is RoundedRectangleBorder
          ? base.bottomSheetTheme.copyWith(
              shape: TopOutlineBorder(side: sheetShape.side, borderRadius: sheetShape.borderRadius),
            )
          : null,
    );
  }
}

/// Rounded rectangle whose border lies only along the top edge (with the top corners); sides and
/// bottom edge meet the screen edge.
class TopOutlineBorder extends RoundedRectangleBorder {
  const TopOutlineBorder({super.side, super.borderRadius});

  @override
  TopOutlineBorder copyWith({BorderSide? side, BorderRadiusGeometry? borderRadius}) =>
      TopOutlineBorder(side: side ?? this.side, borderRadius: borderRadius ?? this.borderRadius);

  @override
  TopOutlineBorder scale(double t) => TopOutlineBorder(side: side.scale(t), borderRadius: borderRadius * t);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    final r = borderRadius.resolve(textDirection);
    // Centre of the line inside the shape, like an inside border.
    final inset = side.strokeInset;
    final box = rect.deflate(inset);
    final tl = r.topLeft.x - inset;
    final tr = r.topRight.x - inset;
    final path = Path()
      ..moveTo(box.left, box.top + tl)
      ..arcToPoint(Offset(box.left + tl, box.top), radius: Radius.circular(tl))
      ..lineTo(box.right - tr, box.top)
      ..arcToPoint(Offset(box.right, box.top + tr), radius: Radius.circular(tr));
    canvas.drawPath(path, side.toPaint());
  }
}
