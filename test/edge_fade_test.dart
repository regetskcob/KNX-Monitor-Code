import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/edge_fade.dart';

/// The soft edge under the overview's activity box: blur in steps like the statistics, none with
/// "reduce motion" or high contrast, and it never takes a tap.
void main() {
  Future<void> pump(WidgetTester tester, {bool reduce = false, bool contrast = false}) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce, highContrast: contrast),
          child: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: TextButton(onPressed: () => tapped = true, child: const Text('darunter')),
                ),
                const Positioned(top: 0, left: 0, right: 0, child: TopEdgeFade(height: 400)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('darunter'));
    expect(tapped, isTrue, reason: 'the edge lets taps through');
  }

  testWidgets('Blur in five steps towards the edge', (tester) async {
    await pump(tester);
    expect(find.byType(BackdropFilter), findsNWidgets(5));
  });

  testWidgets('reduce motion or high contrast: only the fade', (tester) async {
    await pump(tester, reduce: true);
    expect(find.byType(BackdropFilter), findsNothing);
    await pump(tester, contrast: true);
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
