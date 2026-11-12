import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/tokens.dart';
import 'more_menu.dart';
import '../platform/title_bar_inset.dart';

/// Toolbar on the tool pages too: the monitor registers its menu here, tools
/// open with [pushTool] and draw the bar on the left as well. It collapses and
/// expands together with the monitor.
class ToolShell {
  ToolShell._();

  static final instance = ToolShell._();
  static const _key = 'menu_sidebar_open';

  /// Leiste ausgeklappt (gemerkt).
  final open = ValueNotifier<bool>(true);

  /// Menu of the monitor; `null` while none is open.
  MoreMenu Function()? menu;

  /// Topmost tool; switching in the bar replaces it.
  ToolRoute<dynamic>? _current;

  /// Title of the tool currently being opened from the menu (highlight in the
  /// bar); [pushTool] takes it over.
  String? opening;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    open.value = prefs.getBool(_key) ?? true;
  }

  Future<void> toggle() async {
    open.value = !open.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, open.value);
  }
}

/// Opens a tool. If one is already on top, it is replaced (switching in the
/// bar) so that "Back" always leads to the monitor. The bar is the same on all
/// tool pages; pages with their own left column (device tree of the topology)
/// adapt to the room that is left for them.
Future<T?> pushTool<T>(BuildContext context, WidgetBuilder builder, {String? title}) {
  final navigator = Navigator.of(context);
  final shell = ToolShell.instance;
  final current = shell._current;
  title ??= shell.opening;
  shell.opening = null;
  if (current != null && current.isCurrent) {
    final route = ToolRoute<T>(builder: builder, title: title, replacing: true);
    navigator.replace(oldRoute: current, newRoute: route);
    return route.popped;
  }
  return navigator.push(ToolRoute<T>(builder: builder, title: title));
}

/// Page of a tool with the toolbar on the left (from [Breakpoints.expanded],
/// unless collapsed).
class ToolRoute<T> extends MaterialPageRoute<T> {
  ToolRoute({required super.builder, this.title, this.replacing = false});

  /// Title of the tool, for the highlight in the bar.
  final String? title;

  /// Whether it replaces another tool: without a transition, the bar stays still.
  final bool replacing;

  @override
  Duration get transitionDuration => replacing ? Duration.zero : super.transitionDuration;

  @override
  void install() {
    super.install();
    ToolShell.instance._current = this;
  }

  @override
  void dispose() {
    if (ToolShell.instance._current == this) ToolShell.instance._current = null;
    super.dispose();
  }

  @override
  Widget buildContent(BuildContext context) => _ShellFrame(title: title, child: super.buildContent(context));

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // With the bar it stays in place and only the content changes: without a transition.
    if (_ShellFrame.shows(context)) return child;
    return super.buildTransitions(context, animation, secondaryAnimation, child);
  }
}

class _ShellFrame extends StatelessWidget {
  const _ShellFrame({required this.title, required this.child});
  final String? title;
  final Widget child;

  /// Whether the bar sits next to the page at this width.
  static bool shows(BuildContext context) {
    final shell = ToolShell.instance;
    return shell.menu != null && MediaQuery.sizeOf(context).width >= Breakpoints.expanded;
  }

  @override
  Widget build(BuildContext context) {
    final shell = ToolShell.instance;
    return ValueListenableBuilder(
      valueListenable: shell.open,
      builder: (context, _, _) {
        final menu = shell.menu;
        if (menu == null || !shows(context)) return child;
        return Row(
          children: [
            // HorizontSidebar brings its surface, hairline, safe area and Material itself.
            MoreSidebar(menu: menu, active: title),
            Expanded(child: BesideTitleBar(child: child)),
          ],
        );
      },
    );
  }
}
