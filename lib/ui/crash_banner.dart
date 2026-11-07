import 'dart:async';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../l10n/locale_controller.dart';
import '../model/crash_guard.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'support_package_screen.dart' show SupportPackageScreen;
import 'telegram_row.dart' show formatDate, formatTime;

/// Follows the pages of the app's navigator, for [CrashBannerHost]: dialogs
/// and sheets do not count.
class PageRouteTracker extends NavigatorObserver with ChangeNotifier {
  final _pages = <Route<dynamic>>[];

  /// Pages on the stack; 1 = only the start page (connect screen).
  int get depth => _pages.length;

  /// Route name of the top page.
  String? get topName => _pages.lastOrNull?.settings.name;

  // Called while the navigator builds: tell the listeners afterwards.
  void _changed() => scheduleMicrotask(notifyListeners);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute) return;
    _pages.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_pages.remove(route)) _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_pages.remove(route)) _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _pages.indexOf(oldRoute);
    if (i >= 0) _pages.removeAt(i);
    if (newRoute is PageRoute) _pages.insert(i >= 0 ? i : _pages.length, newRoute);
    _changed();
  }
}

/// The notice after an unexpected end, on every page above the connect screen
/// (which shows it as a card): the app may open the monitor or a file directly,
/// and the notice must not go unseen. Above the navigator, so it is one place
/// for all pages; it stays until it is viewed or closed.
class CrashBannerHost extends StatelessWidget {
  const CrashBannerHost({super.key, required this.routes, required this.onReport, required this.child, this.guard});

  final PageRouteTracker routes;

  /// Opens the diagnostics package for the end at the given time.
  final ValueChanged<DateTime> onReport;
  final Widget child;
  final CrashGuard? guard;

  @override
  Widget build(BuildContext context) {
    final guard = this.guard ?? CrashGuard.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([guard, routes]),
      builder: (context, _) {
        final when = guard.unclean;
        final show = when != null && routes.depth > 1 && routes.topName != SupportPackageScreen.routeName;
        return Column(
          children: [
            if (show) CrashBanner(time: when, onView: () => onReport(when), onClose: guard.dismiss),
            // Keyed: the navigator below must keep its state when the banner comes and goes.
            Expanded(
              key: const ValueKey('app'),
              child: MediaQuery.removePadding(context: context, removeTop: show, child: child),
            ),
          ],
        );
      },
    );
  }
}

/// "Unerwartet beendet am … Bericht?" (ended unexpectedly … report?) with
/// "Ansehen" (view) and close. Above the navigator: no tooltips (no overlay).
class CrashBanner extends StatelessWidget {
  const CrashBanner({super.key, required this.time, required this.onView, required this.onClose});

  final DateTime time;
  final VoidCallback onView;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final theme = Theme.of(context);
    return Material(
      color: hz.warningTint,
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Widths.reading),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gap.gutter, HzSpace.s4, HzSpace.s4, HzSpace.s4),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(HorizontStatus.warning.icon, color: hz.warning, size: HzIconSize.row),
                  ),
                  const SizedBox(width: Gap.item),
                  Expanded(
                    child: Text(
                      s.crashBanner('${formatDate(time)} ${formatTime(time, seconds: false)}'),
                      style: theme.textTheme.bodyMedium?.copyWith(color: hz.warning, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: Gap.item),
                  OutlinedButton(onPressed: onView, child: Text(s.crashBannerView)),
                  Semantics(
                    button: true,
                    label: s.commonClose,
                    child: ExcludeSemantics(
                      child: IconButton(
                        onPressed: onClose,
                        icon: Icon(AppIcons.close, color: hz.warning),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
