import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/model/watch_rules.dart';
import 'package:knx_monitor/ui/watch_screen.dart';

import 'window.dart';

void main() {
  final rules = WatchRules.instance;
  tearDown(() => rules.value = const []);

  List<WatchRule> some(int n) => [for (var i = 0; i < n; i++) WatchRule(id: 'r$i', address: 0x0800 + i)];

  Finder rule(String address) => find.textContaining(RegExp('^$address'), findRichText: true);

  testWidgets('breites Fenster: Wächter in Spalten, spaltenweise von oben nach unten', (tester) async {
    rules.value = some(9);
    await pumpWindow(tester, const WatchScreen(), wideWindow);
    final columns = columnsOf(tester, find.byType(Switch)).toList()..sort();
    expect(columns, hasLength(3));
    expect(columns.last, greaterThan(wideWindow.width / 2));
    // Der zweite steht unter dem ersten, der vierte beginnt die nächste Spalte.
    final first = tester.getTopLeft(rule('1/0/0'));
    expect(tester.getTopLeft(rule('1/0/1')).dx, first.dx);
    expect(tester.getTopLeft(rule('1/0/1')).dy, greaterThan(first.dy));
    expect(tester.getTopLeft(rule('1/0/3')).dy, first.dy);
    expect(tester.getTopLeft(rule('1/0/3')).dx, greaterThan(first.dx));
  });

  testWidgets('breites Fenster: ein einzelner Wächter wird nicht über die Breite gezogen', (tester) async {
    rules.value = some(1);
    await pumpWindow(tester, const WatchScreen(), wideWindow);
    expect(tester.getTopLeft(find.byType(Switch)).dx, lessThan(wideWindow.width / 2));
  });

  testWidgets('Telefon und schmales Fenster: eine Liste, auch bei doppelter Schrift ohne Überlauf', (tester) async {
    rules.value = some(9);
    for (final scale in [1.0, 2.0]) {
      await pumpWindow(tester, const WatchScreen(), phoneWindow, textScale: scale);
      expect(columnsOf(tester, find.byType(Switch)), hasLength(1), reason: 'Schrift $scale');
    }
    await pumpWindow(tester, const WatchScreen(), const Size(800, 1000));
    expect(columnsOf(tester, find.byType(Switch)), hasLength(1));
    await pumpWindow(tester, const WatchScreen(), wideWindow, textScale: 2);
  });

  testWidgets('ohne Wächter bleibt die Erklärung eine Lesespalte', (tester) async {
    await pumpWindow(tester, const WatchScreen(), wideWindow);
    expect(tester.getSize(find.byType(ListView)).width, lessThan(wideWindow.width / 2 + 100));
  });
}
