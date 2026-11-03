import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../l10n/locale_controller.dart';
import '../theme/brand.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';

/// Start screen. Takes over quietly from the native splash (paper, app icon in
/// the same place): label and name appear below it, then [onDone].
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  /// Edge length of the icon, as in the native start screen (144 pt).
  static const _logo = 144.0;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: Motion.calm);
  late final _title = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.2, 0.6, curve: Motion.curve),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.isCompleted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
    } else {
      _controller.forward().whenComplete(widget.onDone);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Full area: the AnimatedSwitcher in main.dart only passes loose constraints;
    // otherwise the splash shrinks to the icon (a square in splash color on
    // black, title cut off).
    return SizedBox.expand(
      child: Material(
        color: Palette.launchBackground(Theme.of(context).brightness == Brightness.dark),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const ExcludeSemantics(child: AppIconImage(size: SplashScreen._logo)),
            // Title at a fixed distance below the centered icon: the box of gap
            // and title is centered, the title shifted down by half its height,
            // so its top edge lies at center + icon/2 + gap.
            Positioned.fill(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: SplashScreen._logo + 2 * HzSpace.s24),
                  child: FractionalTranslation(
                    translation: const Offset(0, 0.5),
                    child: FadeTransition(
                      opacity: _title,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Kennung(s.splashSubtitle),
                          const SizedBox(height: HzSpace.s4),
                          HorizontLockup(Brand.product, label: appName, style: Theme.of(context).textTheme.titleLarge),
                        ],
                      ),
                    ),
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
