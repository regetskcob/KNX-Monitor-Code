import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/common.dart';

// Knöpfe nebeneinander, solange jeder in seine Hälfte passt, sonst
// untereinander – die Beschriftung bricht nie um.
void main() {
  Future<void> pump(WidgetTester tester, double width) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: const EvenRow(
              spacing: 10,
              children: [
                SizedBox(key: Key('a'), width: 120, height: 40),
                SizedBox(key: Key('b'), width: 80, height: 50),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('side by side, equal width and height', (tester) async {
    await pump(tester, 310);
    expect(tester.getRect(find.byKey(const Key('a'))), const Rect.fromLTWH(0, 0, 150, 50));
    expect(tester.getRect(find.byKey(const Key('b'))), const Rect.fromLTWH(160, 0, 150, 50));
  });

  testWidgets('stacked at full width when one does not fit', (tester) async {
    await pump(tester, 240);
    expect(tester.getRect(find.byKey(const Key('a'))), const Rect.fromLTWH(0, 0, 240, 40));
    expect(tester.getRect(find.byKey(const Key('b'))), const Rect.fromLTWH(0, 50, 240, 50));
  });

  // Die Knöpfe des Gerätefensters auf schmalen Telefonen (430 pt, 16 pt
  // Rand): Keine Beschriftung bricht um.
  group('device sheet buttons', () {
    const map = 'Kommunikationskarte';
    const filter = 'Im Monitor filtern';

    Future<void> buttons(WidgetTester tester, {required double width, double scale = 1}) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(size: const Size(1600, 1200), textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: EvenRow(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.hub, size: 18),
                        label: const Text(map),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.filter_list, size: 18),
                        label: const Text(filter),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    /// Höhe einer Beschriftung, wenn sie viel Platz hat (eine Zeile).
    Future<double> oneLine(WidgetTester tester, String label, double scale) async {
      await buttons(tester, width: 1600, scale: scale);
      return tester.getSize(find.text(label)).height;
    }

    // 430 pt mit Normalschrift; doppelte Schrift auf 800 pt, weil die
    // Testschrift Ahem breiter läuft als die echte und „Kommunikationskarte“
    // sonst nicht einmal in die volle Breite passt.
    for (final (width, scale) in [(398.0, 1.0), (800.0, 2.0)]) {
      testWidgets('$width pt at text scale $scale: stacked, one line each', (tester) async {
        final mapLine = await oneLine(tester, map, scale);
        final filterLine = await oneLine(tester, filter, scale);
        await buttons(tester, width: width, scale: scale);
        expect(tester.getSize(find.text(map)).height, mapLine);
        expect(tester.getSize(find.text(filter)).height, filterLine);
        final first = tester.getRect(find.byType(OutlinedButton).first);
        final second = tester.getRect(find.byType(OutlinedButton).last);
        expect(second.top, greaterThan(first.bottom));
        expect(first.width, width);
      });
    }

    testWidgets('wide: side by side at equal width', (tester) async {
      await buttons(tester, width: 1000);
      final first = tester.getRect(find.byType(OutlinedButton).first);
      final second = tester.getRect(find.byType(OutlinedButton).last);
      expect(second.top, first.top);
      expect(first.width, second.width);
    });
  });
}
