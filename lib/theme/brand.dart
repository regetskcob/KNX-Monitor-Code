import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

/// Product name (not translated).
const appName = 'KNX Monitor';

/// The brand: KNX Monitor in Horizont, accent "Bus".
abstract final class Brand {
  /// The product whose accent, glyph and icon the app carries.
  static const product = HorizontProduct.knx;

  /// The illustrated app icon (bus terminal on the bus cable), exported from Horizont
  /// (`icons/export/knx/`). Never redraw or scale.
  static const iconAsset = 'assets/brand/icon_1024.png';
}

/// The app icon as an image: red/grey bus terminal on the green bus cable as the horizon. The
/// widget rounds the corners; the graphic itself is borderless.
class AppIconImage extends StatelessWidget {
  const AppIconImage({this.size = 64, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      // Like the platform icons: radius 22.5 % of the edge.
      borderRadius: BorderRadius.circular(size * 0.225),
      child: Image.asset(Brand.iconAsset, width: size, height: size, semanticLabel: appName),
    );
  }
}
