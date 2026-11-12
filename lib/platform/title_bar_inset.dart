import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Height at the top of the Mac window that the traffic-light buttons cover. The window has no
/// title bar of its own (macos/Runner/MainFlutterWindow.swift), so the app keeps this strip free
/// like a status bar. 0 everywhere else and in full screen.
class TitleBarInset {
  TitleBarInset._();

  static final value = ValueNotifier<double>(0);
  static const _channel = MethodChannel('knx/window');

  /// Asks the window once and follows its changes (full screen on and off).
  static Future<void> load() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'titleBarInset') value.value = (call.arguments as num).toDouble();
    });
    try {
      value.value = (await _channel.invokeMethod<num>('titleBarInset'))?.toDouble() ?? 0;
    } on Object catch (e) {
      // Tests and an older native part: no strip.
      debugPrint('Fenster: $e');
    }
  }
}

/// Adds [TitleBarInset] to the top padding, so app bars, [SafeArea] and the sidebar start below
/// the window buttons.
class TitleBarPadding extends StatelessWidget {
  const TitleBarPadding({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: TitleBarInset.value,
    builder: (context, inset, _) {
      if (inset == 0) return child;
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(
          padding: media.padding.copyWith(top: media.padding.top + inset),
          viewPadding: media.viewPadding.copyWith(top: media.viewPadding.top + inset),
        ),
        child: child,
      );
    },
  );
}

/// Content beside the sidebar: the window buttons lie over the sidebar only, so this content
/// moves up a little. Not all the way: the strip at the very top drags the window and takes the
/// clicks, a control must not end up in it.
class BesideTitleBar extends StatelessWidget {
  const BesideTitleBar({super.key, this.active = true, required this.child});

  /// False while the sidebar is hidden and the content starts below the buttons again.
  final bool active;
  final Widget child;

  static const _relief = 12.0;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: TitleBarInset.value,
    builder: (context, inset, _) {
      // Once only: a page inside the tool shell that has a sidebar of its own must not move up twice
      // and end in the strip that drags the window.
      if (inset == 0 || !active || context.getInheritedWidgetOfExactType<_Relieved>() != null) return child;
      final media = MediaQuery.of(context);
      final up = inset < _relief ? inset : _relief;
      return _Relieved(
        child: MediaQuery(
          data: media.copyWith(
            padding: media.padding.copyWith(top: media.padding.top - up),
            viewPadding: media.viewPadding.copyWith(top: media.viewPadding.top - up),
          ),
          child: child,
        ),
      );
    },
  );
}

/// Marks content that [BesideTitleBar] has moved up already.
class _Relieved extends InheritedWidget {
  const _Relieved({required super.child});

  @override
  bool updateShouldNotify(_Relieved oldWidget) => false;
}
