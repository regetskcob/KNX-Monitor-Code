import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// Soft upper edge of a scrolling area that slides under a fixed head (the activity box of the
/// overview): the content blurs in steps towards the edge and fades into the background, so no
/// card is cut off mid-line. The mirror of the activity bar at the bottom of the statistics.
///
/// Placed over the top of the scrolling area, it takes no taps. With "reduce motion" or high
/// contrast it is a plain fade without blur: blur behind text is harder to read for some, and it
/// costs frames on weak devices.
class TopEdgeFade extends StatelessWidget {
  const TopEdgeFade({super.key, this.height = defaultHeight});

  /// Height of the band in logical pixels.
  final double height;

  static const defaultHeight = 28.0;

  /// Blur per step from the edge downwards (strongest at the edge), as in the statistics.
  static const _sigmas = [7.0, 4.5, 2.6, 1.4, 0.6];

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final media = MediaQuery.of(context);
    final plain = media.disableAnimations || media.highContrast;
    final step = height / _sigmas.length;
    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          children: [
            if (!plain)
              for (var i = 0; i < _sigmas.length; i++)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  // The strongest step covers only the top, the weakest the whole band: the blur
                  // adds up towards the edge and runs out softly at the bottom.
                  height: (i + 1) * step,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: _sigmas[i], sigmaY: _sigmas[i]),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 1],
                    colors: [
                      hz.bg.withValues(alpha: plain ? 0.9 : 0.75),
                      hz.bg.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
